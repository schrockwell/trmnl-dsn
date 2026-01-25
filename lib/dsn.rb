require 'json'
require 'open-uri'
require 'ox'

module DSN
  CONFIG_URL = 'https://eyes.nasa.gov/apps/dsn-now/config.xml'
  DSN_URL = 'https://eyes.nasa.gov/dsn/data/dsn.xml'

  class << self
    def fetch(base_url:)
      config_xml = URI.open(CONFIG_URL).read
      dsn_xml = URI.open(DSN_URL).read

      config_doc = Ox.load(config_xml)
      dsn_element = Ox.load(dsn_xml)

      spacecraft = config_doc.config.spacecraftMap.each.map do |sc|
        [sc[:name].upcase, sc[:friendlyName]]
      end.to_h

      all_signals = parse_signals(dsn_element, spacecraft)
      crafts = group_by_craft(all_signals)
      stations = build_stations(crafts)

      {
        'base_url' => base_url,
        'stations' => stations,
        'updated_at' => Time.now.utc.iso8601
      }
    end

    private

    def parse_signals(dsn_element, spacecraft)
      signals = []
      station_id = nil

      dsn_element.each do |el|
        case el.name
        when 'station'
          station_id = el[:name]
        when 'dish'
          el.each do |dish_el|
            case dish_el.name
            when 'upSignal'
              next unless dish_el[:active] == 'true' && dish_el[:power] != '0'
              craft = spacecraft[dish_el[:spacecraft].upcase] || dish_el[:spacecraft]

              signals << {
                'dir' => 'up',
                'station' => station_id,
                'band' => dish_el[:band],
                'power' => "#{dish_el[:power]} kW",
                'craft' => craft
              }
            when 'downSignal'
              next unless dish_el[:active] == 'true'
              craft = spacecraft[dish_el[:spacecraft].upcase] || dish_el[:spacecraft]

              signals << {
                'dir' => 'down',
                'station' => station_id,
                'band' => dish_el[:band],
                'power' => "#{dish_el[:power]} dBm",
                'data_rate' => data_rate_text(dish_el[:dataRate]),
                'craft' => craft
              }
            end
          end
        end
      end

      signals
    end

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

    def group_by_craft(all_signals)
      all_signals.group_by { |sig| sig['craft'] }.map do |craft, signals|
        sig_count = 0
        sig_count += 1 if signals.any? { |sig| sig['dir'] == 'up' }
        sig_count += 1 if signals.any? { |sig| sig['dir'] == 'down' }

        {
          'name' => craft,
          'icon' => "dsn-#{sig_count}.png",
          'signals' => signals.sort_by { |sig| sig['dir'] == 'up' ? 0 : 1 }.uniq
        }
      end
    end

    def select_station(crafts, station)
      crafts.select { |craft| craft['signals'].any? { |sig| sig['station'] == station } }
            .sort_by { |craft| craft['name'] }
    end

    def build_stations(crafts)
      [
        { 'name' => 'Madrid', 'icon' => 'flag-mdscc-bw.png', 'crafts' => select_station(crafts, 'mdscc') },
        { 'name' => 'Goldstone', 'icon' => 'flag-gdscc-bw.png', 'crafts' => select_station(crafts, 'gdscc') },
        { 'name' => 'Canberra', 'icon' => 'flag-cdscc-bw.png', 'crafts' => select_station(crafts, 'cdscc') }
      ]
    end
  end
end
