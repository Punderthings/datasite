#!/usr/bin/env ruby
# frozen_string_literal: true

# NPCondenser: Not Perfect Non Profit condenser
#   Given data from npscraper, organize the output into a schema template.
module NPCondenser
  include NPSchema

  require 'json'
  require 'yaml'
  # FIXME: refactor to pass rubocop checks
  # rubocop:disable Metrics/MethodLength, Style/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Breakout scanning textmatches for nonprofit hints
  # @param matchhash of array text bits
  # @return simplified text values array
  def condense_textmatch(matchhash)
    nonprofit = []
    matchhash&.each_value do |v|
      nonprofit << v.join(';') unless v.empty?
    end
    nonprofit
  end

  # Set some defaults if yoast SEO block found
  # @param yoast Hash of yoast data
  # @param socials Hash to mutate if we find additional data
  # @return orgname String if data exists
  def condense_yoast(yoast, socials)
    graph = yoast['@graph'] if yoast.is_a?(Hash)
    return '' unless graph.is_a?(Array)

    orgname = ''
    graph.each do |elem|
      next unless elem.is_a?(Hash)
      next unless 'Organization'.eql?(elem.fetch('@type', nil))

      orgname = elem['name']
      sameas = Array(elem.fetch('sameAs', nil)) # May be a single string
      SOCIAL_MAP.each do |id, regex|
        found = sameas.find { |s| regex.match(s.to_s) }
        socials[id] = found if found
      end
    end
    orgname
  end

  # Encapsulate aggregating links (mutates inputs)
  def aggregate_links(data, aggregate)
    data.dig(NAVLINKS, ALLLINKS)&.each do |l|
      aggregate[NAVLINKS][l] += 1
    end
    data.dig(FOOTERLINKS, ALLLINKS)&.each do |l|
      aggregate[FOOTERLINKS][l] += 1
    end
  end

  # Convenience method to condense site data and aggregate data across sites
  # HACK: This method does a best guess at each datafield
  def condense_site(file, aggregate, errlog)
    data = JSON.load_file(file)
    metas = data[METAS] || {} # Missing if the site fetch/parse failed
    links = data[LINKS] || {}
    condensed = {}
    socials = {}
    identifier = File.basename(file)
    aggregate['sites'] << identifier
    condensed['identifier'] = identifier
    condensed['title'] = metas.fetch('title', nil)
    condensed['title'] ||= metas.fetch('titleog', nil)
    condensed['commonName'] = data.fetch('commonName', nil)
    condensed['legalName'] = condense_yoast(metas.fetch('yoast', nil), socials)
    condensed['legalName_alt'] = data.fetch('legalName', nil)
    socials['twitter'] = metas.fetch('twitter', nil)
    condensed['description'] = metas.fetch('description', nil)
    condensed['description'] ||= metas.fetch('descriptionog', nil)
    condensed['description_alt'] ||= data.fetch('description', nil)
    condensed['website'] = metas.fetch('canonical', nil)
    condensed['website'] ||= data.fetch('website', nil)
    condensed['slogan'] = data.fetch('slogan', nil)
    condensed['copyright'] = data['copyright'] if data.key?('copyright')
    condensed['imprint'] = data['imprint'] if data.key?('imprint')
    condensed['addressCountry'] = data.fetch('addressCountry', '')
    condensed['addressRegion'] = data.fetch('addressRegion', '')
    LINKRX_MAP.each_key do |k|
      condensed[k] = links.fetch(k, nil)
    end
    # Simplistic collapse of any nonprofit hints
    condensed['taxID'] = data.fetch('taxID', nil)
    condensed['nonprofitStatus'] = data.fetch('nonprofitStatus', nil)
    condensed['nonprofitStatus_alt'] = condense_textmatch(data['textmatch'])
    condensed['icon32'] = metas['icon32']
    condensed['webgenerator'] = metas.fetch('generator', [])&.to_s
    condensed['social'] = socials

    # Write out the condensed yaml in md file
    File.open(file.sub(/\.json\z/, '.md'), 'w') do |f|
      f.puts condensed.to_yaml
    end
    # Also collect all links in an aggregator
    aggregate_links(data, aggregate)
  rescue StandardError => e
    errlog << "#{__method__}(#{file}): #{e.message}\n\n" \
              "#{e.backtrace.join("\n\t")}"
  end

  # Condense scanned json data into schema-hinted md files
  # @param dir String to scan for .json
  # @return hash of overall cross-scanned data
  # NOTE: writes out individual .md files
  def condense_sites(dir, errlog)
    data = {
      NAVLINKS => Hash.new(0),
      FOOTERLINKS => Hash.new(0),
      'sites' => []
    }
    Dir["#{dir}/*.json"].each do |f|
      # HACK: ignore synopsis file (check basename: dir may contain the name)
      next if File.basename(f).start_with?('npdetector')

      condense_site(f, data, errlog)
    end
    # Optionally: dump any links that have few repeats, and sort
    # data[NAVLINKS] = data[NAVLINKS].reject { |_k, v| v < 2 }
    # data[FOOTERLINKS] = data[FOOTERLINKS].reject { |_k, v| v < 2 }
    # unless data[NAVLINKS].empty?
    #   data[NAVLINKS] = [data[NAVLINKS].sort_by { |_k, v| -v }].to_h
    # end
    # unless data[FOOTERLINKS].empty?
    #   data[FOOTERLINKS] = [data[FOOTERLINKS].sort_by { |_k, v| -v }].to_h
    # end
    data['npdetectorlog'] = errlog
    data
  end
end
# rubocop:enable Metrics/MethodLength, Style/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
