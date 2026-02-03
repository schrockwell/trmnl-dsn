package dsn

import (
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"
)

const (
	configURL = "https://eyes.nasa.gov/apps/dsn-now/config.xml"
	dsnURL    = "https://eyes.nasa.gov/dsn/data/dsn.xml"
)

// XML structures for config.xml

type xmlConfig struct {
	SpacecraftMap xmlSpacecraftMap `xml:"spacecraftMap"`
}

type xmlSpacecraftMap struct {
	Spacecraft []xmlSpacecraft `xml:"spacecraft"`
}

type xmlSpacecraft struct {
	Name         string `xml:"name,attr"`
	FriendlyName string `xml:"friendlyName,attr"`
}

// XML structures for dsn.xml (station and dish are flat siblings under <dsn>)

type xmlDish struct {
	UpSignals   []xmlUpSignal   `xml:"upSignal"`
	DownSignals []xmlDownSignal `xml:"downSignal"`
}

type xmlUpSignal struct {
	Active     string `xml:"active,attr"`
	Power      string `xml:"power,attr"`
	Spacecraft string `xml:"spacecraft,attr"`
	Band       string `xml:"band,attr"`
}

type xmlDownSignal struct {
	Active     string `xml:"active,attr"`
	Power      string `xml:"power,attr"`
	Spacecraft string `xml:"spacecraft,attr"`
	Band       string `xml:"band,attr"`
	DataRate   string `xml:"dataRate,attr"`
}

// JSON output structures

type Signal struct {
	Dir      string `json:"dir"`
	Station  string `json:"station"`
	Band     string `json:"band"`
	Power    string `json:"power"`
	DataRate string `json:"data_rate,omitempty"`
	Craft    string `json:"craft"`
}

type Craft struct {
	Name    string   `json:"name"`
	Icon    string   `json:"icon"`
	Signals []Signal `json:"signals"`
}

type Station struct {
	Name   string  `json:"name"`
	Icon   string  `json:"icon"`
	Crafts []Craft `json:"crafts"`
}

type Response struct {
	Stations  []Station `json:"stations"`
	UpdatedAt string    `json:"updated_at"`
}

func fetchURL(url string) ([]byte, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

func dataRateText(raw string) string {
	var baud int
	fmt.Sscanf(raw, "%d", &baud)

	switch {
	case baud > 1_000_000:
		return fmt.Sprintf("%d Mbps", baud/1_000_000)
	case baud > 1_000:
		return fmt.Sprintf("%d kbps", baud/1_000)
	default:
		return fmt.Sprintf("%d bps", baud)
	}
}

func dedup(signals []Signal) []Signal {
	seen := make(map[string]bool)
	var result []Signal
	for _, s := range signals {
		key := s.Dir + "|" + s.Station + "|" + s.Band + "|" + s.Power + "|" + s.DataRate + "|" + s.Craft
		if !seen[key] {
			seen[key] = true
			result = append(result, s)
		}
	}
	return result
}

func Fetch() (*Response, error) {
	configData, err := fetchURL(configURL)
	if err != nil {
		return nil, fmt.Errorf("fetching config: %w", err)
	}

	dsnData, err := fetchURL(dsnURL)
	if err != nil {
		return nil, fmt.Errorf("fetching dsn: %w", err)
	}

	var config xmlConfig
	if err := xml.Unmarshal(configData, &config); err != nil {
		return nil, fmt.Errorf("parsing config: %w", err)
	}

	// Build spacecraft name lookup (uppercased ID -> friendly name)
	spacecraft := make(map[string]string)
	for _, sc := range config.SpacecraftMap.Spacecraft {
		spacecraft[strings.ToUpper(sc.Name)] = sc.FriendlyName
	}

	// Parse DSN XML with streaming decoder, since <station> and <dish> are
	// flat siblings under the root <dsn> element.
	var allSignals []Signal
	var stationID string

	decoder := xml.NewDecoder(strings.NewReader(string(dsnData)))
	for {
		tok, err := decoder.Token()
		if err != nil {
			break
		}
		se, ok := tok.(xml.StartElement)
		if !ok {
			continue
		}
		switch se.Name.Local {
		case "station":
			for _, attr := range se.Attr {
				if attr.Name.Local == "name" {
					stationID = attr.Value
				}
			}
		case "dish":
			var dish xmlDish
			if err := decoder.DecodeElement(&dish, &se); err != nil {
				continue
			}
			for _, up := range dish.UpSignals {
				if up.Active != "true" || up.Power == "0" {
					continue
				}
				craft := spacecraft[strings.ToUpper(up.Spacecraft)]
				if craft == "" {
					craft = up.Spacecraft
				}
				allSignals = append(allSignals, Signal{
					Dir:     "up",
					Station: stationID,
					Band:    up.Band,
					Power:   up.Power + " kW",
					Craft:   craft,
				})
			}
			for _, down := range dish.DownSignals {
				if down.Active != "true" {
					continue
				}
				craft := spacecraft[strings.ToUpper(down.Spacecraft)]
				if craft == "" {
					craft = down.Spacecraft
				}
				allSignals = append(allSignals, Signal{
					Dir:      "down",
					Station:  stationID,
					Band:     down.Band,
					Power:    down.Power + " dBm",
					DataRate: dataRateText(down.DataRate),
					Craft:    craft,
				})
			}
		}
	}

	// Group signals by craft
	craftMap := make(map[string][]Signal)
	var craftOrder []string
	for _, sig := range allSignals {
		if _, exists := craftMap[sig.Craft]; !exists {
			craftOrder = append(craftOrder, sig.Craft)
		}
		craftMap[sig.Craft] = append(craftMap[sig.Craft], sig)
	}

	var crafts []Craft
	for _, name := range craftOrder {
		signals := craftMap[name]

		hasUp := false
		hasDown := false
		for _, s := range signals {
			if s.Dir == "up" {
				hasUp = true
			} else {
				hasDown = true
			}
		}
		sigCount := 0
		if hasUp {
			sigCount++
		}
		if hasDown {
			sigCount++
		}

		// Sort: up before down, then deduplicate
		sort.SliceStable(signals, func(i, j int) bool {
			if signals[i].Dir == "up" && signals[j].Dir != "up" {
				return true
			}
			return false
		})
		signals = dedup(signals)

		crafts = append(crafts, Craft{
			Name:    name,
			Icon:    fmt.Sprintf("dsn-%d.png", sigCount),
			Signals: signals,
		})
	}

	// Build stations
	selectStation := func(stationID string) []Craft {
		var result []Craft
		for _, c := range crafts {
			for _, sig := range c.Signals {
				if sig.Station == stationID {
					result = append(result, c)
					break
				}
			}
		}
		sort.Slice(result, func(i, j int) bool {
			return result[i].Name < result[j].Name
		})
		return result
	}

	return &Response{
		Stations: []Station{
			{Name: "Madrid", Icon: "flag-mdscc-bw.png", Crafts: selectStation("mdscc")},
			{Name: "Goldstone", Icon: "flag-gdscc-bw.png", Crafts: selectStation("gdscc")},
			{Name: "Canberra", Icon: "flag-cdscc-bw.png", Crafts: selectStation("cdscc")},
		},
		UpdatedAt: time.Now().UTC().Format(time.RFC3339),
	}, nil
}
