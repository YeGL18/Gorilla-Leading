require 'rexml/document'
require 'json'
require 'open3'
require 'fileutils'

# Download the two official KMZ files before running this reproducible import.
records = %w[sec rlc].flat_map do |kind|
  xml, status = Open3.capture2('unzip', '-p', "/private/tmp/hk-#{kind}.kmz")
  abort 'Invalid KMZ' unless status.success?
  doc = REXML::Document.new(xml)
  REXML::XPath.match(doc, '//*[local-name()="Placemark"]').map do |point|
    fields = REXML::XPath.match(point, './/*[local-name()="SimpleData"]').to_h { |e| [e.attributes['name'], e.text.to_s] }
    coords = REXML::XPath.first(point, './/*[local-name()="coordinates"]').text.split(',').map { |v| Float(v) }
    abort 'Coordinate outside Hong Kong' unless (22.1..22.6).cover?(coords[1]) && (113.8..114.5).cover?(coords[0])
    {id: "#{kind}-#{fields.fetch(kind == 'sec' ? 'SEC_ID' : 'RLC_ID')}", kind: kind,
     name: fields.fetch('SITE_DESC_CHI'), english: fields.fetch('SITE_DESC_ENG'),
     latitude: coords[1], longitude: coords[0]}
  end
end
abort 'Empty or duplicate data' unless records.size > 300 && records.map { |r| r[:id] }.uniq.size == records.size
path = File.expand_path('../GorillaTranslate/Resources/traffic_cameras.json', __dir__)
catalog = {attribution: 'Hong Kong SAR Government Transport Department / DATA.GOV.HK. All rights in the source data belong to their respective owners.',
  downloadedAt: '2026-10-26', terms: 'https://data.gov.hk/en/terms-and-conditions',
  sources: ['https://www.td.gov.hk/datagovhk_td/locations-of-sec/resources/locations_of_sec.kmz',
            'https://www.td.gov.hk/datagovhk_td/junctions-with-rlc/resources/junctions_with_rlc.kmz'], cameras: records}
File.write(path, JSON.pretty_generate(catalog) + "\n")
puts records.group_by { |r| r[:kind] }.transform_values(&:size)
