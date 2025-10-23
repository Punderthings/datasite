#!/usr/bin/env ruby
# frozen_string_literal: true

# NPScraper: Not Perfect Non Profit scraping methods
#   Scan a website and attempt to gather common links or text blobs related
#   to nonprofit status, governance, site navigation, and related data.
module NPScraper
  module_function

  include NPSchema

  require 'nokogiri'
  require 'open-uri'
  require 'json'
  require 'fileutils'

  HACK_DO_ABOUT = false # FIXME: reads multiple files that need caching

  # @return text content of first node.css(selector) found; nil if none
  def get_first_css(node, selector)
    nodelist = node.css(selector)
    nodelist[0].first.content.strip.gsub(/[\t\n]/, '') if nodelist[0]
  end

  # @return hash of data from Yoast SEO when available; nil otherwise
  def get_yoast_graph(head)
    node = head.at_css('.yoast-schema-graph')
    return nil unless node

    begin
      yoast = JSON.parse(node.content)
    rescue StandardError => e
      yoast['error_get_yoast_graph'] =
        "#{e.message}\n\n#{e.backtrace.join("\n\t")}"
    end
    yoast
  end

  # Get a single meta value if present
  def get_meta(node, xpath)
    node.xpath(xpath)&.first&.content
  end

  # FIXME: refactor to pass rubocop checks
  # rubocop:disable Metrics/MethodLength, Style/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  # @return hash of various head > meta fields of interest
  def get_metas(head)
    metas = {}
    metas['title'] = get_meta(head, 'title')
    metas['titleog'] = get_meta(head, 'meta[@property="og:title"]')
    metas['descriptionog'] = get_meta(head, 'meta[@property="og:description"]')
    metas['description'] = get_meta(head, 'meta[@name="description"]')
    metas['twitter'] = get_meta(head, 'meta[@name="twitter:site"]')
    nodelist = head.xpath('link[@rel="canonical"]')
    metas['canonical'] = nodelist[0]['href'] if nodelist[0]
    nodelist = head.xpath('link[@rel="icon"][@sizes="32x32"]')
    metas['icon32'] = nodelist[0]['href'] if nodelist[0]
    metas['generator'] = []
    head.xpath('meta[@name="generator"]').each do |n|
      metas['generator'] << n['content']
    end
    metas['yoast'] = get_yoast_graph(head)
    metas
  end

  # Simplistic link simplfying: try to collapse duplicates
  # @return absolute url, or nil if non-useful (i.e. # fragment or blank href)
  def absolute_href(base, href)
    return nil if href.nil?
    return nil if %r{/?#\z}.match(href) # Skip bare fragments

    url = URI(href)
    url.absolute? ? url.to_s : URI(base).merge(href).to_s
  end

  # @return hash of interesting unique hrefs
  def get_links(siteurl, nodelist, lookfor)
    tmp = Hash.new { |h, k| h[k] = [] }
    nodelist.each do |node| # FIXME: horribly inefficient
      txt = node.content
      lookfor.each do |id, regex|
        if regex.match(txt)
          abshref = absolute_href(siteurl, node['href'])
          tmp[id] << abshref if abshref
        end
      end
    end
    links = {}
    tmp.each do |k, v| # TODO: find better way to ensure uniqueness
      links[k] = v.to_a.uniq
    end
    links
  end

  # Collect all links to lookfor, and normalize/unique them
  # @return hash of interesting unique hrefs, plus all links text separately
  def get_links_all(siteurl, nodelist, lookfor)
    links = get_links(siteurl, nodelist, lookfor)
    links[ALLLINKS] = []
    nodelist.map(&:content).uniq.each do |txt|
      if txt
        t = txt.strip.gsub(NORMALIZE_PAT, NORMALIZE_MAP)
        links[ALLLINKS] << t if t.length > 3 # Arbitrary; ignore non-word links
      end
    end
    links
  end

  # Scan nodelist for each of the lookfor patterns
  # @return hash of arrays of text nodes matching our maps
  def scan_text(nodelist, lookfor)
    texts = {}
    lookfor.each do |id, regex|
      texts[id] = nodelist.map(&:content).select { |t| regex.match(t) }
    end
    texts
  end

  # Parse stream of html and run various scans
  # @return hash of various potentially useful data
  def parse_site(io, siteurl, errlog)
    data = Hash.new { |h, k| h[k] = [] }
    begin
      doc = Nokogiri::HTML5(io)
      body = doc.xpath('/html/body')
      CSS_MAP.each do |id, selector|
        data[id] = get_first_css(body, selector)
      end
      data[METAS] = get_metas(doc.xpath('/html/head'))
      data[LINKS] = get_links(siteurl, doc.css('a'), LINKRX_MAP)
      data[NAVLINKS] = get_links_all(siteurl, doc.css('nav a'), LINKRX_MAP)
      data[FOOTERLINKS] =
        get_links_all(siteurl, doc.css('footer a'), LINKRX_MAP)
      data[TEXT_MATCHES] =
        scan_text(doc.xpath('/html/body//text()'), TEXTRX_MAP)
      if HACK_DO_ABOUT && data[TEXT_MATCHES][EIN_SCAN].empty?
        # If we didn't find any EINs, then also parse about pages to scan text
        abouts = data[LINKS]['aboutlinks']
        if abouts # rubocop:disable Style/SafeNavigation
          abouts.each do |u|
            next if u.nil?
            # Don't bother parsing links that are just fragments
            next if u.start_with?('#')

            url = URI(u)
            url = URI(siteurl).merge(u).to_s unless url.absolute?
            # Read the about url (no caching) and do partial scan
            errlog << "Parsing about link: #{url}"
            aio = URI.parse(url).open.read
            adoc = Nokogiri::HTML(aio)
            data[TEXT_MATCHES][url] =
              scan_text(adoc.xpath('/html/body//text()'), TEXTRX_MAP)
          end
        end
        donates = data[LINKS]['donatelinks']
        if donates # rubocop:disable Style/SafeNavigation
          donates.each do |u|
            next if u.nil?
            # Don't bother parsing links that are just fragments
            next if u.start_with?('#')

            url = URI(u)
            url = URI(siteurl).merge(u).to_s unless url.absolute?
            # Read the about url (no caching) and do partial scan
            errlog << "Parsing donate link: #{url}"
            aio = URI.parse(url).open.read
            adoc = Nokogiri::HTML(aio)
            data[TEXT_MATCHES][url] =
              scan_text(adoc.xpath('/html/body//text()'), TEXTRX_MAP)
          end
        end
      end

      itemtypes = body.xpath('//*[@itemtype]') # Site uses schema.org metadata?
      unless itemtypes.children.empty?
        data['itemtypes'] = itemtypes.children.length
      end
    rescue StandardError => e
      errlog << "error_#{__method__}(#{siteurl}): #{e.message}"
      data["error_#{__method__}"] =
        "#{e.message}\n\n#{e.backtrace.join("\n\t")}"
    end
    data
  end

  # Simplistic identifier based on url.
  # @return name_org form of url, like company_com
  def url2identifier(url)
    URI(url.downcase).host.sub('www.', '').gsub('.', '_')
  end

  # Get the plain html of a news website, aggressively caching
  # @param url String of site to grab
  # @param dir String local directory for cache
  # @param filename String local file to cache
  # @param refresh Boolean if true, force a lookup from site
  # @return io stream of the site's .html content
  def get_site(url, cachedir, file, errlog, refresh: false)
    FileUtils.mkpath(cachedir)
    filename = File.join(cachedir, file)
    begin
      if refresh || !File.exist?(filename)
        File.open(filename, 'w') do |f|
          f.puts URI.parse(url).open.read
        end
      end
      File.open(filename)
    rescue StandardError => e
      errlog << "get_site: #{e.message}\n\n#{e.backtrace.join("\n\t")}"
      nil
    end
  end

  # Convenience method to scrape one site into detailed nested hashes
  def scrape_site(siteurl, cachedir, org, errlog)
    ident = url2identifier(siteurl)
    io = get_site(siteurl, cachedir, "#{ident}.html", errlog, refresh: false)
    data = parse_site(io, siteurl, errlog)
    # If we are given manual data about the org, pass it through
    org&.each do |k, v| # FIXME: check safe navigation instead of if org
      data[k] = v # REVIEW: This may overwrite some scanned data
    end
    data['identifier'] = ident
    data
  end
end
# rubocop:enable Metrics/MethodLength, Style/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
