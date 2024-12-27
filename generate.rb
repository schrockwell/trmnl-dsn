#! /usr/bin/env ruby

# Standard libs
require 'fileutils'
require 'json'
require 'open-uri'
require 'time'

# Third-party
require 'liquid'
require 'ox'

@base_url = ENV['BASE_URL'] || raise('BASE_URL not set')

@config_xml = URI.open('https://eyes.nasa.gov/apps/dsn-now/config.xml').read
@dsn_xml = URI.open('https://eyes.nasa.gov/dsn/data/dsn.xml').read

@config_doc = Ox.load(@config_xml)
@dsn_element = Ox.load(@dsn_xml) # this is an Element, not a Document

@spacecraft = @config_doc.config.spacecraftMap.each.map do |sc|
  [sc[:name].upcase, sc[:friendlyName]]
end.to_h

def data_rate_text(baud)
  baud = baud.to_i
  if baud > 1_000_000
    "#{baud / 1_000_000} Mbps"
  elsif baud > 1_000
    "#{baud / 1_000} kbps"
  else
    "#{baud} bps"
  end
end

station_id = nil

@all_signals = []

@dsn_element.each do |el|
  case el.name
  when 'station'
    station_id = el[:name]
  when 'dish'
    el.each do |dish_el|
      case dish_el.name
      when 'upSignal'
        next unless dish_el[:active] == 'true'
        craft = @spacecraft[dish_el[:spacecraft].upcase] || dish_el[:spacecraft]

        @all_signals << {
          'dir' => 'up',
          'station' => station_id,
          'band' => dish_el[:band],
          'power' => "#{dish_el[:power]} kW",
          'craft' => craft
        }
      when 'downSignal'
        next unless dish_el[:active] == 'true'
        craft = @spacecraft[dish_el[:spacecraft].upcase] || dish_el[:spacecraft]

        @all_signals << {
          'dir' => 'down',
          'station' => station_id,
          'band' => dish_el[:band],
          'power' => "#{dish_el[:power]} dBm",
          'data_rate' => data_rate_text(dish_el[:dataRate]),
          'craft' => craft
        }
      end
    end
  else
    nil # ignore
  end
end.compact

@crafts = @all_signals.group_by { |sig| sig['craft'] }.map do |craft, signals|
  sig_count = 0
  sig_count += 1 if signals.any? { |sig| sig['dir'] == 'up' }
  sig_count += 1 if signals.any? { |sig| sig['dir'] == 'down' }

  {
    'name' => craft,
    'icon' => "dsn-#{sig_count}.png",
    'signals' => signals
  }
end.sort_by { |craft| craft['craft'] }

@stations = [
  { 'name' => 'Madrid', 'icon' => 'flag-mdscc-bw.png', 'crafts' => @crafts.select { |craft| craft['signals'].any? { |sig| sig['station'] == 'mdscc' } }.sort_by { |craft| craft['name'] } },
  { 'name' => 'Goldstone', 'icon' => 'flag-gdscc-bw.png', 'crafts' => @crafts.select { |craft| craft['signals'].any? { |sig| sig['station'] == 'gdscc' } }.sort_by { |craft| craft['name'] }  },
  { 'name' => 'Canberra', 'icon' => 'flag-cdscc-bw.png', 'crafts' => @crafts.select { |craft| craft['signals'].any? { |sig| sig['station'] == 'cdscc' } }.sort_by { |craft| craft['name'] }  }
]

@output = { 
  'base_url' => @base_url,
  'stations' => @stations,
  'updated_at' => Time.now.utc.iso8601
}

@template = Liquid::Template.parse(File.open('template.html').read)

puts 'Recreating _site directory...'
FileUtils.rm_rf('_site')
Dir.mkdir('_site')

puts 'Copying images...'
FileUtils.cp_r('images', '_site/images')

puts 'Writing _site/index.html...'
File.open('_site/index.html', 'w') do |file|
  file.write(@template.render(@output))
end

puts 'Writing _site/dsn.json...'
File.open('_site/dsn.json', 'w') do |file|
  file.write(@output.to_json)
end

puts 'Done!'


# @json_body = {
#   merge_variables: @output
# }.to_json

# # post it to https://usetrmnl.com/api/custom_plugins/4e4ac460-a136-45aa-959f-82a89800fc1d

# @response = system('curl', '-s', '-o', '/dev/null', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', @json_body, 'https://usetrmnl.com/api/custom_plugins/4e4ac460-a136-45aa-959f-82a89800fc1d')
# p @response