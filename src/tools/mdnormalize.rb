#!/usr/bin/env ruby
# frozen_string_literal: true

# Simplistic .md file normalizer based on a JSON schema.
module MDNormalize
  module_function

  require 'csv'
  require 'json'
  require 'yaml'

  YAML_SEP = '---'

  # FIXME: Don't include dissolutionDate in fields (usage currently rare)
  SKIP_FIELDS = ['dissolutionDate'].freeze

  # rubocop:disable Metrics/MethodLength, Style/AbcSize
  # Return ordered lisf of fields from schema, minus any SKIP_FIELDS
  # @param file String of JSON schema filename
  # @return array of fields, minus skips
  def dump_schema_fields(file)
    schema = JSON.parse(File.read(file))
    properties = schema['properties']
    fields = properties.keys
    fields - SKIP_FIELDS
  end

  # Normalize a .md file to have frontmatter fields in schema order
  # NOTE lossy; loses comments; places non-schema fields at end of frontmatter
  # NOTE: explicitly turns '' blank entries into nil
  # @param filename to read with frontmatter (markdown body left as-is)
  # @param fieldnames array of fields in order; default FOUNDATION_FIELDNAMES
  # @return string describing our results
  def normalize_file(filename, fieldnames)
    data = File.read(filename)
    _unused, frontmatter, markdown = data.split(YAML_SEP, 3) # YAML data sep
    markdown = '' if markdown.nil?
    yaml = YAML.safe_load(frontmatter, aliases: true)
    # Dump normalized data back to file; note this removes # comments
    newyaml = {}
    fieldnames.each do |fieldname|
      newyaml[fieldname] = yaml.delete(fieldname)
      newyaml[fieldname] = nil if ''.eql?(newyaml[fieldname])
    end
    # If any non-nil existing fields are left, add at end
    # FIXME decide how strict our data needs to be
    yaml.compact!
    yaml.each do |k, v|
      newyaml[k] = v
    end
    output = newyaml.to_yaml
    output << YAML_SEP # NOTE: newline provided by shovel operator below
    output << markdown
    outputfilename = filename # NOTE: overwrite files
    File.open(outputfilename, 'w') do |f|
      f.puts output
    end
    "Wrote out: #{outputfilename}"
  rescue StandardError => e
    "ERROR: (#{filename}): #{e.message}\n\n#{e.backtrace.join("\n\t")}"
  end

  # Normalize .md files into fieldnames order; return report of what's done
  #   SIDE EFFECTS: rewrites files; may lose # yaml comments
  # @param directory to scan all .md files
  # @param fieldlist of fields to force output in order
  # @return array of strings describing each action
  def normalize_dataset(dir, fieldnames)
    Dir["#{dir}/*.md"].map { |f| normalize_file(f, fieldnames) }
  end
end

# ### #### ##### ######
# Main method for command line use
if __FILE__ == $PROGRAM_NAME
  workdir = '../atmp/'
  outfile = '../atmp/mdnormalize.txt'
  schema = '../fossfoundation/_data/foundations-schema.json'
  puts "BEGIN #{__FILE__}.normalize_dataset(#{workdir}, #{schema})"
  fields = MDNormalize.dump_schema_fields(schema)
  lines = MDNormalize.normalize_dataset(workdir, fields)
  File.write(outfile, JSON.pretty_generate(lines))
  puts "END wrote #{outfile}"
end
# rubocop:enable Metrics/MethodLength, Style/AbcSize
