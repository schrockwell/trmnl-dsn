#! /usr/bin/env ruby

# Standard libs
require 'fileutils'
require 'json'
require 'open-uri'
require 'time'

# Third-party
require 'ox'
require 'trmnl_preview'

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
        next unless dish_el[:active] == 'true' && dish_el[:power] != '0'
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
    'signals' => signals.sort_by { |sig| sig['dir'] == 'up' ? 0 : 1 }.uniq
  }
end

def select_station(crafts, station)
  crafts.select { |craft| craft['signals'].any? { |sig| sig['station'] == station } }.sort_by { |craft| craft['name'] }
end

@stations = [
  { 'name' => 'Madrid', 'icon' => 'flag-mdscc-bw.png', 'crafts' => select_station(@crafts, 'mdscc') },
  { 'name' => 'Goldstone', 'icon' => 'flag-gdscc-bw.png', 'crafts' => select_station(@crafts, 'gdscc') },
  { 'name' => 'Canberra', 'icon' => 'flag-cdscc-bw.png', 'crafts' => select_station(@crafts, 'cdscc') }
]

@output = { 
  'base_url' => @base_url,
  'stations' => @stations,
  'updated_at' => Time.now.utc.iso8601
}

puts 'Recreating _site directory...'
FileUtils.rm_rf('_site')
Dir.mkdir('_site')

puts 'Copying images...'
FileUtils.cp_r('images', '_site/images')

puts 'Writing _site/dsn.json...'
File.open('_site/dsn.json', 'w') do |file|
  file.write(@output.to_json)
end

puts 'Writing _site/index.html...'

context = TRMNLPreview::Context.new('.')
context.poll_data # copy from _site/dsn.json to tmp/data.json
File.write('_site/index.html', context.render_full_page('full'))

puts 'Done!'