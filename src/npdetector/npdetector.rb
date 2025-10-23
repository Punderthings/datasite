#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'npschema'
require_relative 'npscraper'
require_relative 'npcondenser'

# NPDetector: Not Perfect Non Profit detector
#   Scan a website and attempt to gather common links or text blobs related
#   to nonprofit status, governance, site navication, and related data.
#   NOTE: Requires manual review of results!
class NPDetector
  include NPSchema
  include NPScraper
  include NPCondenser

  require 'json'
  require 'yaml'
  require 'optparse'
  require 'csv'
  require 'fileutils'

  attr_accessor :errlog, :workdir, :cachedir

  # Simplistic workdirs and logging setup
  def initialize(workdir, cachedir)
    @errlog = []
    @workdir = workdir
    @cachedir = cachedir
  end

  # Read a CSV of sites to scan with override metadata
  # @param file String name of csv file to read with headers
  # @return array of hashes of field mappings
  def read_csv(file)
    CSV.new(File.read(file), headers: true).to_a.map(&:to_hash)
  end

  # Scan the orgarray of hashes, outputting into dir with cache
  # @param workdir String for output of json/md
  # @param cachedir String for storing html scrapes
  # @param orgarray array of hashes to scrape
  # @param errlog to push any messages/errors into
  def scrape_sites(workdir, cachedir, orgarray, errlog)
    FileUtils.mkpath(cachedir)
    orgarray.each do |orghash|
      @errlog << orghash['website']
      sitehash = scrape_site(orghash['website'], cachedir, orghash, errlog)
      File.open(File.join(workdir, "#{sitehash['identifier']}.json"),
                'w') do |f|
        f.puts JSON.pretty_generate(sitehash)
      end
    end
  end
end

# ### #### ##### ######
# Main methods for command line use
if __FILE__ == $PROGRAM_NAME
  workdir = '_npwork'
  infile = File.join(workdir, 'npdetector.csv')
  reportfile = File.join(workdir, 'npdetector.json')
  npd = NPDetector.new(workdir, File.join(workdir, 'cache'))
  csv = npd.read_csv(infile)
  npd.scrape_sites(npd.workdir, npd.cachedir, csv, npd.errlog)
  report = npd.condense_sites(npd.workdir, npd.errlog)
  File.open(reportfile, 'w') do |f|
    f.puts JSON.pretty_generate(report)
  end
  puts "DONE: see cross report: #{reportfile}"
  puts "DEBUG \n #{npd.errlog}"
end
