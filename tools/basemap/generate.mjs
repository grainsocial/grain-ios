// Writes Grain/Resources/Basemap/basemap-{light,dark}.json — the MapLibre style
// for grain's self-hosted Protomaps basemap, the same one grain.social draws.
//
// The web app assembles this style at runtime from protomaps-themes-base. The
// Android app can't run that package, so the same call runs here at
// development time and the result ships as an asset. Re-run with
// `just basemap-style` after bumping the theme package or changing anything
// below; the output is committed so a build needs neither node nor npm.
//
// Tiles come from tiles.grain.social, the Worker that serves z/x/y tiles out
// of the planet PMTiles archive on R2 (see stacks/edge in the infra repo). The
// web style stops there: maplibre-gl draws labels without a glyph endpoint.
// MapLibre Native does not — a style without `glyphs` renders no text at all —
// so the label fonts and the two sprite icons come from Protomaps' public
// asset host until the edge Worker serves them too.
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { layers, namedTheme } from "protomaps-themes-base";

const TILES_ORIGIN = "https://tiles.grain.social";
const ASSETS_ORIGIN = "https://protomaps.github.io/basemaps-assets";

const out = resolve(dirname(fileURLToPath(import.meta.url)), "../../Grain/Resources/Basemap");
mkdirSync(out, { recursive: true });

for (const theme of ["light", "dark"]) {
  const style = {
    version: 8,
    name: `grain-${theme}`,
    glyphs: `${ASSETS_ORIGIN}/fonts/{fontstack}/{range}.pbf`,
    sprite: `${ASSETS_ORIGIN}/sprites/v4/${theme}`,
    sources: {
      protomaps: {
        type: "vector",
        tiles: [`${TILES_ORIGIN}/planet/{z}/{x}/{y}.mvt`],
        // From the archive header, as on the web; saves a TileJSON round trip.
        minzoom: 0,
        maxzoom: 15,
        // Required by ODbL wherever the basemap is shown.
        attribution: "© OpenStreetMap",
      },
    },
    // `lang` is what produces the label layers at all — without it `layers()`
    // returns geometry only.
    layers: layers("protomaps", namedTheme(theme), { lang: "en" }),
  };
  const file = resolve(out, `basemap-${theme}.json`);
  writeFileSync(file, JSON.stringify(style, null, 2) + "\n");
  console.log(`wrote ${file} (${style.layers.length} layers)`);
}
