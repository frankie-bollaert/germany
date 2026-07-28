# German state geodata bulk download

Scripts to bulk-download the open geodata of German states and convert it to
cloud-optimized formats.

| Data | Downloader | Coverage |
|------|------------|----------|
| **LiDAR / terrain** | `download_rlp_lidar.sh` (`las`, `dgm1`) · `download_bw_lidar.sh` (`dgm1`) | Rheinland-Pfalz, Baden-Württemberg |
| **ALKIS (cadastre)** | `download_alkis.sh <state>` | 15 of 16 states |

Both LiDAR downloaders feed the same converter (`convert_to_cloud_optimized.sh`) and the
same output tree.

# Rheinland-Pfalz

Published by the **Landesamt für Vermessung und Geobasisinformation Rheinland-Pfalz (LVermGeo)**.

## Datasets

| Key   | Product                                  | Format   | Tiles   | Statewide size |
|-------|------------------------------------------|----------|---------|----------------|
| `las` | Classified point cloud, surface+terrain (LPO+LPG) | `.laz` | ~21,207 | **~5.18 TB**   |
| `dgm1`| DGM1 — bare-earth terrain model, 1 m grid | GeoTIFF | ~21,082 | **~32.8 GB**   |

- **Tiling:** 1 km × 1 km, SW (lower-left) corner snapped to whole km.
- **CRS:** ETRS89 / UTM Zone 32 — **EPSG:25832** (LAZ vertical may be compound EPSG:5555).
- **Portal:** <https://geoshop.rlp.de> · files served from `https://geobasis-rlp.de`.

## License — attribution required

**Datenlizenz Deutschland – Namensnennung 2.0 (DL-DE/BY 2.0)** — *not* DL-DE/Zero.
Free, no access restrictions, but you **must** credit:

```
©GeoBasis-DE / LVermGeoRP <year>, dl-de/by-2-0, www.lvermgeo.rlp.de
```

## How it works

The state surveying office publishes official **Metalink-4 (`.meta4`)** manifests listing every
tile with its size and **SHA-256** hash. `aria2c` reads these natively, giving parallel,
**resumable**, integrity-checked downloads from a single command.

Statewide manifests (`07` = RLP state prefix):
- LAS:  `https://geobasis-rlp.de/data/las/current/meta4/las_las_07.meta4`
- DGM1: `https://geobasis-rlp.de/data/dgm1/current/meta4/dgm1_tif_07.meta4`

Sub-state manifests exist if you want less than the whole state — append the
district / Verbandsgemeinde / Gemeinde key: `..._07{kreissch|vgnr|gmdesch}.meta4`.

## Usage

```bash
brew install aria2          # or: apt install aria2

./download_rlp_lidar.sh dgm1                 # ~33 GB  -> ./rlp_lidar/dgm1
./download_rlp_lidar.sh las  /mnt/big/rlp    # ~5.2 TB -> mind your disk & bandwidth!
./download_rlp_lidar.sh both

DRY_RUN=1 ./download_rlp_lidar.sh las        # print tile count + size, download nothing
JOBS=12 CONN=4 ./download_rlp_lidar.sh dgm1  # tune parallelism
```

# Baden-Württemberg

Published by the **Landesamt für Geoinformation und Landentwicklung Baden-Württemberg (LGL)**.

## Datasets

| Key    | Product                                   | Format             | Tiles  | Statewide size |
|--------|-------------------------------------------|--------------------|--------|----------------|
| `dgm1` | DGM1 — bare-earth terrain model, 1 m grid | ASCII **XYZ** in `.zip` | 9,370 zips | **~125 GB** |

- **Tiling:** downloads are **2 km × 2 km ZIPs**, each holding four 1 km × 1 km tiles
  (`*.xyz` + a `*.csv` with acquisition date, accuracy and CRS) — so ~37,480 one-km tiles.
- **CRS:** ETRS89 / UTM Zone 32 — **EPSG:25832**; heights DHHN2016 (compound EPSG:7837).
  The XYZ files themselves carry no CRS; the converter stamps EPSG:25832 on.
- **No point cloud:** BW publishes no open LiDAR point cloud. The portal's `3DM` /
  "Laserscandaten 2000–2005" product is flagged inactive and every `3dm_*.zip` URL 404s,
  so there is no BW counterpart to RLP's `las`. `download_bw_lidar.sh las` says so and exits.
- **Portal:** <https://opengeodata.lgl-bw.de>.

Other products sit on the same 2 km grid and the same URL scheme (`dom1`, `ndom1`, `dgm025`,
`dom5`, `dop20`, `lod1`/`lod2`) — downloading one is a single line in `product_type()`, but
the converter only knows the zipped-XYZ layout `dgm1` uses.

## License — attribution required

**Datenlizenz Deutschland – Namensnennung 2.0 (DL-DE/BY 2.0)** — you must credit:

```
Datenquelle: LGL, www.lgl-bw.de  ·  dl-de/by-2-0
```

## How it works

BW publishes **no manifest**. The portal draws its 2 km download grid as **Mapbox vector
tiles**, and each grid cell carries a JSON blob listing that cell's per-product download URL.
The script fetches the four zoom-7 vector tiles that cover the state, decodes them with a
small stdlib-only MVT reader, and writes an `aria2c` input file. The tile list is therefore
always current rather than hard-coded — and `BBOX` can subset it without extra requests.

Unlike RLP's Metalink, **no checksums are published**: downloads are parallel and resumable
(`--continue`), but only size-checked, not hash-verified.

## Usage

```bash
brew install aria2          # or: apt install aria2

./download_bw_lidar.sh dgm1                  # ~125 GB -> ./bw_lidar/dgm1
./download_bw_lidar.sh dgm1 /mnt/big/bw

DRY_RUN=1 ./download_bw_lidar.sh dgm1        # tile count + sampled size estimate, no download
BBOX="500,5400,520,5420" ./download_bw_lidar.sh dgm1   # subset by UTM32 km (minE,minN,maxE,maxN)
JOBS=12 CONN=4 ./download_bw_lidar.sh dgm1   # tune parallelism
```

Grid cells are named `<easting_km>-<northing_km>` of the SW corner, with **odd** eastings and
**even** northings (e.g. `517-5424`) — `BBOX` is inclusive on both ends.

# ALKIS — the cadastre, all states

`download_alkis.sh` pulls **ALKIS** (*Amtliches Liegenschaftskatasterinformationssystem* —
parcels, building footprints, land use) for any German state that publishes it openly.
Owner names are never open data; every state releases only the *ohne Eigentümer* (oE) variant.

**No state requires a login for what this script downloads.** Per-state status,
licenses and the three content gaps are tabulated in
[`bundeslaender.md`](bundeslaender.md#alkis--cadastral-open-data-per-state).

```bash
brew install aria2          # or: apt install aria2

./download_alkis.sh --list                   # every state key + its datasets
./download_alkis.sh nw                       # NRW, NAS, ~25 GB -> ./alkis/nw
./download_alkis.sh nw gpkg                  # NRW, simplified GeoPackage (much smaller)
./download_alkis.sh bw shape /mnt/big        # -> /mnt/big/bw

DRY_RUN=1 ./download_alkis.sh th             # file count + size estimate, download nothing
JOBS=12 CONN=4 ./download_alkis.sh bb        # tune parallelism
PAGE=50000 ./download_alkis.sh ni            # page size for the WFS/OGC-API states
```

## What each state gives you

| Key | State | Datasets (default first) | Unit | Statewide size |
|-----|-------|--------------------------|------|----------------|
| `bw` | Baden-Württemberg | `nas`, `shape` | Gemarkung (~3,380) | ~23 GB |
| `by` | Bayern | `tn`, `hausumringe`, `verwaltung` | statewide / Bezirk | ~5.4 GB (`tn`) |
| `be` | Berlin | `flurstuecke`, `gebaeude` | WFS pages | ~403k parcels |
| `bb` | Brandenburg | `nas`, `shape` | Landkreis (18) | ~4 GB |
| `hb` | Bremen | `flurstuecke` | one GetFeature | small |
| `hh` | Hamburg | `gml` | statewide, quarterly | ~0.46 GB |
| `he` | Hessen | `flurstuecke`, `zoning` | OGC API pages | ~5.0 M parcels |
| `mv` | Mecklenburg-Vorpommern | `nas` | Gemeinde (~1,450 files) | — |
| `ni` | Niedersachsen | `flurstueck`, `gebaeude` | WFS pages | ~6.3 M parcels |
| `nw` | Nordrhein-Westfalen | `nas`, `gpkg` | Kreis (53) | ~25 GB |
| `rp` | Rheinland-Pfalz | `lika`, `hu` | 1 km tile (20,511) | ~31 GB |
| `sl` | Saarland | `nas`, `shape` | Landkreis (7) | ~2.1 GB |
| `sn` | Sachsen | `nas` | statewide | one ZIP |
| `sh` | Schleswig-Holstein | `geojson` | statewide | ~243 MB |
| `th` | Thüringen | `shape`, `nas` | Flur (~16,500) | ~1.2 GB |
| `st` | Sachsen-Anhalt | — | — | **not published** |

`bw`, `by` and `rp` come with a caveat printed at run time — Bayern publishes no open vector
parcels and RLP only a rasterised cadastral map. `st` exits with an explanation rather than
pretending there is something to fetch.

## How it works

There is no shared national interface, so the script carries one plan per state and four
download engines:

| Engine | States | Mechanism |
|--------|--------|-----------|
| `aria2` | `bw` `by` `bb` `hh` `mv` `nw` `sl` `sn` `sh` `th` | build a file list, hand it to `aria2c` |
| `metalink` | `rp` | official `.meta4` with per-file **SHA-256** → `aria2c --check-integrity` |
| `wfs2` | `be` `ni` | WFS 2.0 paged with `COUNT`/`STARTINDEX` → one GML per page |
| `wfs1` | `hb` | WFS 1.1 has no standard paging; Bremen fits in one request |
| `ogcapi` | `he` | OGC API Features, follow `rel="next"` → one GeoJSON per page |

The file lists are **never hard-coded** — they are rebuilt on every run from whatever each
state publishes as its index:

- **BW** draws its Gemarkung grid as **Mapbox vector tiles** carrying a JSON blob with each
  cell's download URLs — the same trick as its LiDAR 2×2 km grid, so `download_bw_lidar.sh`
  and `download_alkis.sh` share the stdlib-only MVT reader.
- **NRW** serves a machine-readable XML index per product folder.
- **BB** is a plain Apache directory listing.
- **MV** and **TH** publish standards-compliant **INSPIRE ATOM** feeds.
- **HH** is queried through the transparency portal's **CKAN API**, so the newest quarterly
  snapshot is picked automatically rather than pinned.
- **SL** is a password-less public **Nextcloud** share, listed over WebDAV `PROPFIND`.

Only RLP publishes checksums, so only `rp` is hash-verified; everywhere else downloads are
parallel, resumable (`--continue`) and size-checked.

# Convert to cloud-optimized formats

`convert_to_cloud_optimized.sh` turns the downloaded tiles into streamable formats:

| Source                      | Cloud-optimized output            | Tool | Output tree | Notes |
|-----------------------------|-----------------------------------|------|-------------|-------|
| `dgm1` GeoTIFF (RLP)        | **COG** (Cloud Optimized GeoTIFF) | GDAL | `dtm/de/rlp/` | Float32, ZSTD + PREDICTOR=3, AVERAGE overviews, 512px tiles |
| `dgm1` zipped XYZ (BW)      | **COG**, 4 per zip                | GDAL | `dtm/de/bw/`  | same recipe + `-a_srs EPSG:25832 -ot Float32`; 29 MB XYZ → ~1.8 MB COG |
| `las` `.laz` (RLP)          | **COPC** (`.copc.laz`)            | PDAL | `point-cloud/de/rlp/` | octree-indexed, HTTP range-streamable; ~189 MB LAZ → ~144 MB COPC |

Output is organized by product type then ISO-style location (`de` = Germany, then the state),
relative to an optional `output_base` (default `.`):

```
<output_base>/dtm/de/rlp/dgm1_32_400_5580_1_rp_2024.tif
<output_base>/dtm/de/bw/dgm1_32_517_5424_1_bw_2023.tif
<output_base>/point-cloud/de/rlp/LAS_320_5510_las12.copc.laz
```

```bash
brew install gdal pdal

./convert_to_cloud_optimized.sh dgm1                    # ./rlp_lidar/dgm1 -> ./dtm/de/rlp
./convert_to_cloud_optimized.sh las                     # ./rlp_lidar/las  -> ./point-cloud/de/rlp
./convert_to_cloud_optimized.sh both ./rlp_lidar /data  # -> /data/{dtm,point-cloud}/de/rlp

./convert_to_cloud_optimized.sh bw dgm1                 # ./bw_lidar/dgm1  -> ./dtm/de/bw
./convert_to_cloud_optimized.sh bw dgm1 ./bw_lidar /data

DRY_RUN=1 ./convert_to_cloud_optimized.sh las           # list, convert nothing
JOBS=8 ./convert_to_cloud_optimized.sh dgm1             # cap parallelism (default = CPU count)
KEEP=0 ./convert_to_cloud_optimized.sh dgm1             # delete each source after a verified convert
```

The leading state token (`rlp` | `bw`) is optional and defaults to `rlp`, so the original
invocations are unchanged. BW zips are unpacked to a temp dir per zip, converted, then the
temp dir is removed; a zip whose four COGs already exist and are newer is skipped without
unpacking (`KEEP=0` deletes the zip after all four convert cleanly).

- Re-running **skips** already-converted, up-to-date outputs (safe to resume).
- COG compression is overridable via `COG_COMPRESS` / `COG_PRED` / `COG_LEVEL` — if your GDAL
  build has the **LERC** codec, `COG_COMPRESS=LERC_ZSTD` is ideal for elevation (this brew build lacks it).
- COPC is **CPU-heavy** (~20–30 s/tile); the full ~21k-tile point cloud is a long run — size accordingly.

# Notes

**Both states**

- **Never cache a tile list** — coverage is regenerated as campaigns land, so both downloaders
  rebuild theirs on every run (RLP re-fetches the manifest, BW re-decodes the grid tiles).
- **Resume** is automatic (`--continue`). Integrity: RLP verifies SHA-256 from the manifest; BW
  publishes no hashes, so only size is checked.
- Both states are on the same grid origin (EPSG:25832, SW corner snapped to whole km), so RLP
  and BW tiles line up where the states meet.

**RLP**

- **bDOM** (image-based DSM) is open data on the same portal but no bulk `.meta4` was verified.
- Per-tile direct URL (alternative to the manifest), e.g. tile SW-corner 320 km E / 5510 km N:
  `https://geobasis-rlp.de/data/las/current/las/lpolpg_32_320_5510_1_rp.laz`

**BW**

- Per-tile direct URL, e.g. the 2 km cell at 517 km E / 5424 km N:
  `https://opengeodata.lgl-bw.de/data/dgm/dgm1_32_517_5424_2_bw.zip`
- Each 1 km XYZ is 29 MB of text (1,000,000 lines) — expect the unzip+convert step to be
  I/O-bound, ~2 s/tile; statewide that is ~37k tiles.
- The `.csv` beside each XYZ carries acquisition date, update date, accuracy (0.15 m) and the
  height reference — worth keeping if provenance matters; the converter ignores it.

# Sources

**RLP**

- Product/license: <https://lvermgeo.rlp.de/geodaten-geoshop/open-data>
- Machine config (URL schemes): <https://geoshop.rlp.de/files/anpassungen/hvd/products/las.json>
- Metadata: <https://gdk.gdi-de.org/geonetwork/srv/api/records/3d339d76-6160-49d2-bf47-a93e05f76ab2>

**BW**

- Portal: <https://opengeodata.lgl-bw.de> · product/license overview:
  <https://www.lgl-bw.de/Produkte/Open-Data/index.html>
- Product catalogue (JSON the portal itself reads): <https://opengeodata.lgl-bw.de/assets/config/local/odp-products.json>
- Download grid (vector tiles + bounds): `https://opengeodata.lgl-bw.de/tiles/vts/2x2Gitter/{z}/{x}/{y}.pbf`,
  <https://opengeodata.lgl-bw.de/tiles/vts/2x2Gitter/metadata.json>
- DGM1 metadata record: <https://metadaten.geoportal-bw.de/geonetwork/srv/api/records/8ca22d63-e92d-4ca1-879e-68f62978b21a>

**ALKIS** (one per state, all verified live July 2026)

- BW: <https://opengeodata.lgl-bw.de> · grid `tiles/vts/Gemarkungen/{z}/{x}/{y}.pbf`, files `/data/alkis/`
- BY: product catalogue <https://geodaten.bayern.de/opengeodata/json/opengeodata_produkte.json>
- BE: <https://gdi.berlin.de/services/wfs/alkis_flurstuecke> · <https://daten.berlin.de>
- BB: <https://data.geobasis-bb.de/geobasis/daten/alkis/Vektordaten/>
- HB: <https://geodienste.bremen.de/wfs_hduk2958loah3976niun> · <https://www.geo.bremen.de/produkte/open-data-produktuebersicht-15654>
- HH: <https://suche.transparenz.hamburg.de/api/3/action/package_search?q=title:ALKIS%20Liegenschaftskarte>
- HE: <https://www.geoportal.hessen.de/spatial-objects/710> · portal <https://hvbg.hessen.de/geoinformation/open-data>
- MV: <https://www.geodaten-mv.de/dienste/alkis_nas_atom>
- NI: <https://opendata.lgln.niedersachsen.de/doorman/noauth/alkis_wfs_nas>
- NW: <https://www.opengeodata.nrw.de/produkte/geobasis/lk/akt/>
- RP: <https://geobasis-rlp.de/data/lika/current/meta4/> · product config <https://geoshop.rlp.de/files/anpassungen/hvd/products/lika.json>
- SL: <https://www.shop.lvgl.saarland.de/cloud/freiegeobasisdaten>
- SN: <https://www.geodaten.sachsen.de/downloadbereich-alkis-4176.html>
- ST: <https://www.lvermgeo.sachsen-anhalt.de/de/gdp-open-data.html> (ALKIS **not** included)
- SH: <https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/dl-alkis.html>
- TH: <https://geoportal.geoportal-th.de/dienste/atom_th_alkis>
