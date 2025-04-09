import { DOMParser } from "xmldom";

export default async function handler(event, context) {
  const configRes = await fetch(
    "https://eyes.nasa.gov/apps/dsn-now/config.xml"
  );
  const configXml = await configRes.text();
  const dsnRes = await fetch("https://eyes.nasa.gov/dsn/data/dsn.xml");
  const dsnXml = await dsnRes.text();

  const configDoc = new DOMParser().parseFromString(
    configXml,
    "application/xml"
  );
  const dsnDoc = new DOMParser().parseFromString(dsnXml, "application/xml");

  const spacecraftMap = {};
  const spacecrafts = configDoc.getElementsByTagName("spacecraft");
  for (let i = 0; i < spacecrafts.length; i++) {
    const sc = spacecrafts[i];
    const name = sc.getAttribute("name")?.toUpperCase();
    const friendlyName = sc.getAttribute("friendlyName");
    if (name && friendlyName) spacecraftMap[name] = friendlyName;
  }

  const allSignals = [];
  const stations = dsnDoc.getElementsByTagName("station");
  for (let i = 0; i < stations.length; i++) {
    const station = stations[i];
    const stationId = station.getAttribute("name");
    const dishes = station.getElementsByTagName("dish");
    for (let j = 0; j < dishes.length; j++) {
      const dish = dishes[j];
      const upSignals = dish.getElementsByTagName("upSignal");
      for (let k = 0; k < upSignals.length; k++) {
        const up = upSignals[k];
        if (
          up.getAttribute("active") === "true" &&
          up.getAttribute("power") !== "0"
        ) {
          const craftKey = up.getAttribute("spacecraft")?.toUpperCase();
          const craft = spacecraftMap[craftKey] || craftKey;
          allSignals.push({
            dir: "up",
            station: stationId,
            band: up.getAttribute("band"),
            power: `${up.getAttribute("power")} kW`,
            craft,
          });
        }
      }

      const downSignals = dish.getElementsByTagName("downSignal");
      for (let k = 0; k < downSignals.length; k++) {
        const down = downSignals[k];
        if (down.getAttribute("active") === "true") {
          const craftKey = down.getAttribute("spacecraft")?.toUpperCase();
          const craft = spacecraftMap[craftKey] || craftKey;
          const baud = parseInt(down.getAttribute("dataRate") || "0", 10);
          let dataRate;
          if (baud > 1_000_000) dataRate = `${baud / 1_000_000} Mbps`;
          else if (baud > 1_000) dataRate = `${baud / 1_000} kbps`;
          else dataRate = `${baud} bps`;

          allSignals.push({
            dir: "down",
            station: stationId,
            band: down.getAttribute("band"),
            power: `${down.getAttribute("power")} dBm`,
            data_rate: dataRate,
            craft,
          });
        }
      }
    }
  }

  const crafts = Object.values(
    allSignals.reduce((acc, signal) => {
      const name = signal.craft;
      if (!acc[name]) acc[name] = { name, signals: [] };
      acc[name].signals.push(signal);
      return acc;
    }, {})
  ).map((craft) => {
    const sigCount = new Set(craft.signals.map((sig) => sig.dir)).size;
    return {
      name: craft.name,
      icon: `dsn-${sigCount}.png`,
      signals: craft.signals.sort((a, b) => (a.dir === "up" ? -1 : 1)),
    };
  });

  function selectStation(crafts, station) {
    return crafts
      .filter((c) => c.signals.some((sig) => sig.station === station))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  const output = {
    base_url: "https://trmnl-dsn.netlify.app",
    stations: [
      {
        name: "Madrid",
        icon: "flag-mdscc-bw.png",
        crafts: selectStation(crafts, "mdscc"),
      },
      {
        name: "Goldstone",
        icon: "flag-gdscc-bw.png",
        crafts: selectStation(crafts, "gdscc"),
      },
      {
        name: "Canberra",
        icon: "flag-cdscc-bw.png",
        crafts: selectStation(crafts, "cdscc"),
      },
    ],
    updated_at: new Date().toISOString(),
  };

  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(output, null, 2),
  };
}
