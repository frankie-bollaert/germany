# German state geodata bulk download

Scripts to bulk-download the open geodata of Germany's 16 federal states (*Bundesländer*) and
convert it to cloud-optimized formats. Everything here works **anonymously — no account, no
API key, no login.** Where a state is missing, it is because no anonymous *bulk* endpoint was
found, not because the data is gated.

| Data | Downloader | Coverage |
|------|------------|----------|
| **LiDAR / terrain** | `download_<id>_lidar.sh` (`las`, `dgm1`) | 13 of 16 states statewide, + ST sample areas |
| **ALKIS (cadastre)** | `download_alkis.sh <id>` | 16 of 16 states |
| **All of the above at once** | `download_all.sh` | [Downloading everything](#downloading-everything) |
| **ALKIS → DuckDB tables** | `alkis_to_duckdb.sh` | [Loading ALKIS into DuckDB](#loading-alkis-into-duckdb) |
| **DuckDB → GeoParquet** | `duckdb_to_geoparquet.sh` | [Exporting to GeoParquet](#exporting-to-geoparquet) |
| **LiDAR, sample squares only** | `download_samples.sh` | [A 5×5 km square per state](#lidar-for-the-sample-squares-only) |
| **BY cadastral map (raster)** | `download_by_parzellarkarte.sh` | [Bayern's Parzellarkarte](#bayerns-parzellarkarte-the-cadastre-as-a-picture) |
| **Hauskoordinaten / Hausumringe** | *(source inventory only, no script yet)* | [`cadastre-products.md`](cadastre-products.md) |
| **Nationwide parcels, paid** | *(not scriptable — ships on a USB drive)* | [`cadastre-products.md`](cadastre-products.md) |

All LiDAR downloaders feed the same converter (`convert_to_cloud_optimized.sh`) and the same
output tree. States are keyed by a two-letter **ID** throughout — see
[The state ID](#the-state-id).
Status was surveyed live on **2026-07-28**; counts and volumes are what the sources reported
then, and every script recomputes them at runtime (`DRY_RUN=1`).

**Contents** — the three availability questions first, then the detail:

1. [Complete coverage — all four datasets](#1-complete-coverage--all-four-datasets)
2. [LiDAR / terrain availability](#2-lidar--terrain-availability)
3. [ALKIS / cadastre availability](#3-alkis--cadastre-availability)

Once the ALKIS data is down, [Loading ALKIS into DuckDB](#loading-alkis-into-duckdb) turns it
into `plots`, `structures` and `structure_versions`.

---

# Downloading everything

The per-state scripts each take one state and one dataset. `download_all.sh` walks the whole
matrix — 29 ALKIS combinations across 16 states, 19 LiDAR combinations across 11 — into one
state-major tree:

```
<root>/alkis/<id>-<dataset>/      ./alkis/nw-nas, ./alkis/bw-shape, ./alkis/st-flurstueck
<root>/lidar/<id>-<dataset>/      ./lidar/nw-dgm1, ./lidar/rp-las
```

```bash
./download_all.sh --list                 # the matrix, its sizes, and where each part lands
./download_all.sh alkis                  # 29 combinations, ~132 GB + 23 M streamed features
./download_all.sh dgm1                   # 10 terrain models, ~630 GB + 3 unsized sources
./download_all.sh all /mnt/big           # everything, including 12 TB+ of point cloud

DRY_RUN=1 ./download_all.sh all          # every sub-script prints its plan, downloads nothing
ONLY=nw,bw ./download_all.sh alkis       # two states only
SKIP=by,rp ./download_all.sh alkis       # drop the two states with no vector Flurstücke
```

## Only parcels and building footprints

`cadastre` is the ALKIS group narrowed to products that hold parcels or building footprints,
and `FORMAT=` picks one of the two exports where a state publishes both:

```bash
FORMAT=simple ./download_all.sh cadastre --list   # 19 products, ~35.6 GB
FORMAT=nas    ./download_all.sh cadastre          # same 19, full NAS instead: ~63.6 GB
              ./download_all.sh alkis             # everything ALKIS: 29 products, ~132.4 GB
```

Restricting is only partly the downloader's decision — most states do not offer the choice:

| How the state publishes | States | What you can ask for |
|-------------------------|--------|----------------------|
| Separate endpoint per object class | BE, NI, ST | Parcels and footprints, each on its own |
| Separate endpoint, parcels only | HB, HE | Parcels; no footprint endpoint in these two |
| Standalone footprint product only | BY (`hausumringe`), RP (`hu`) | Footprints; neither publishes open vector parcels |
| One package, every object class | BW, BB, HH, MV, NW, SL, SN, TH | Nothing narrower than the whole package |

For that last group the restriction has to happen after the download, not during it:

```bash
ogr2ogr -f GPKG parcels_buildings.gpkg 202601_gru_vereinf_05114000_Krefeld_EPSG25832.gpkg \
        Flurstueck GebauedeBauwerk
```

Those layer names are from the NRW GeoPackage, which carries `Flurstueck`, `FlurstueckPunkt`,
`GebauedeBauwerk`, `KatasterBezirk`, `Nutzung`, `NutzungFlurstueck` and `VerwaltungsEinheit` —
five of the seven layers are not parcels or footprints. In full NAS the equivalent classes are
`AX_Flurstueck` and `AX_Gebaeude`.

What `WANT=` drops outright: BY's `tn` (land use, 5.4 GB) and `verwaltung`, HE's `zoning`,
ST's `nutzung`, and RP's `lika` — a 30.7 GB rasterised cadastral map, the single largest
saving. `FORMAT=` then drops the duplicate export for BW, BB, NW, SL and TH, which is another
~37 GB of the same content in a second file format.

### Schleswig-Holstein is a two-step source

`download_alkis.sh sh` fetches `ALKIS_SH_Massendownload.geojson`, and despite the name that
file is an **index, not the cadastre**: one polygon per Flur, each feature carrying a
`LINK_DATA` URL to that Flur's NAS `.xml.gz`.

```json
{ "GEMARKUNG": "Ellhöft", "FLUR": "015515003", "DATUM": "2026-07-10",
  "LINK_DATA": ".../massen.php?file=015515003.xml.gz&id=1&live=07_2026" }
```

Fetching one of those packages confirms the cadastre is behind the link — Flur `015515003`
carries 88 `AX_Flurstueck` and 2 `AX_Gebaeude`. So SH parcels and footprints need a second
pass over the index that `download_alkis.sh` does not yet make; `download_all.sh` prints this
caveat when it selects the state.

One flat directory per product is not just tidiness. The four ALKIS states served by a WFS or
OGC API (BE, HE, NI, ST) page their output into `part-00001.gml` whatever dataset was asked
for, so two of their datasets sharing a directory would overwrite each other silently. The
`<id>-<dataset>` leaf makes that impossible.

A failing combination is logged to `<root>/.download_all.failures` and the walk continues;
re-running the same command retries it and resumes everything else. The only change this makes
to the per-state scripts is `OUTDIR=` — set it yourself and any of them writes straight into
the path you give instead of appending its own subdirectory.

---

# Loading ALKIS into DuckDB

`alkis_to_duckdb.sh` turns what the downloaders left under `./alkis` into three tables in a
DuckDB database. It downloads nothing — it only reads what is already on disk, so it can be
run against a partial tree and re-run as more arrives.

```bash
brew install gdal duckdb      # or: apt install gdal-bin duckdb

./alkis_to_duckdb.sh --list                  # what is on disk and what it would produce
./alkis_to_duckdb.sh                         # everything -> ./alkis.duckdb
STATES="be nw" ./alkis_to_duckdb.sh          # two states only
KINDS=plots  ./alkis_to_duckdb.sh            # parcels only, skip the footprints
JOBS=8 ./alkis_to_duckdb.sh /mnt/big/germany.duckdb
```

| Table | One row per | Filled from |
|-------|-------------|-------------|
| `plots` | Flurstück | BB, BE, BW, MV, NW, SN |
| `structures` | building footprint identity | BB, BE, BW, BY, MV, NW, SN |
| `structure_versions` | footprint geometry, `→ structures.id` | the same seven |

Seven of the sixteen states are wired up: `bb-shape` (zipped Shapefile per Landkreis, see
below), `be-flurstuecke` / `be-gebaeude` (paged GML), `bw-shape` (zipped Shapefile per
Gemarkung), `by-hausumringe` (zipped Shapefile per Bezirk), `mv-nas` (zipped Shapefile per
Gemeinde, see below), `nw` (GeoPackage per Kreis) and `sn` (statewide NAS, see below).
Deliberately not loaded: `bb-nas` and `bw-nas` (the same content as their `-shape` siblings,
already loaded from the easier format), `by-tn` (land use — neither parcels nor footprints)
and `st` (never fetched). Bayern contributes **no plots at all**, which is the content gap
described in [The two content gaps](#the-two-content-gaps). The remaining eight states
(`hb`, `he`, `hh`, `ni`, `rp`, `sh`, `sl`, `th`) are downloaded but have no `DATASETS` entry
yet — the downloaders have run ahead of the loader.

## Brandenburg: a third state on the *vereinfacht* profile

BB publishes the whole state twice — `bb-nas` and `bb-shape`, one zip per Landkreis (18) in
each. The Shapefile half is the **ALKIS *vereinfacht* profile**, the same one MV and NW ship,
so it costs no new reader: the existing `zipshp` reader and the MV field lists carry over
almost unchanged. The NAS half is redundant once it is loaded, exactly as in MV.

The layers are `Flurstueck` and `GebauedeBauwerk` — note BB reproduces NW's misspelling of
*Gebäude* — alongside `KatasterBezirk`, `Nutzung`, `NutzungFlurstueck` and
`VerwaltungsEinheit`, none of which map to a table here.

Three deltas against MV/NW, all small:

- The land-use text is **`tntext`**, where MV and NW both call it `tntxt`. A one-character
  difference, but `ogr2ogr -select` is fatal on a field the source lacks, so BB needs its own
  entry in `fields_for` rather than reusing NW's.
- There is an extra **`flurstnr`** — the parcel number as a single string, where
  `flstnrzae`/`flstnrnen` are the split halves. It is carried into `metadata`.
- **Brandenburg has no Regierungsbezirke.** `regbezirk` is null in every row and only the key
  `regbezschl` (`120`) is set. Both are kept so the metadata shape matches MV and NW.

`aktualit` is text with a trailing `Z` (`"2024-06-04Z"`), as in MV, so it needs the same
`try_cast`. The CRS is **EPSG:25833** and the `.prj` declares it, so unlike the NAS sources BB
needs no `srs_for` entry.

Every text field is 254 bytes wide and values do sit at the cap, but no value in the state is
cut mid-character — all 18 packages load without DuckDB's `Invalid string encoding` — so BB
does **not** need [the truncated-UTF-8 repair](#the-truncated-utf-8-repair) that MV does.

Loaded, the state gives **3,145,234 parcels** over 29,495 km² (Brandenburg is 29,654 km², so
the parcel mosaic covers 99.5 % of it) and **2,478,799 footprints**. The counts read
3,145,235 and 2,478,917 before dedup: 1 parcel and 118 buildings appear in two packages at
once, every one of them on a Landkreis boundary, and the loader's `QUALIFY` keeps the first.
No row is lost to empty or missing geometry.

One operational note: the original `download_all.sh` run left BB half-fetched — 7 of the 18
shape zips were truncated, with aria2 control files still beside them (`alkis bb shape
(exit 1)` in `.download_all.failures`). Re-running the downloader resumes them in place:

```bash
OUTDIR=../germany-data/alkis/bb-shape ./download_alkis.sh bb shape
```

## Mecklenburg-Vorpommern: the same profile as NW, in a different box

MV was nearly free, because **MV and NW publish the identical ALKIS *vereinfacht* profile**:
the same 22 parcel attributes in the same order (`oid`, `aktualit`, `idflurst`, `flaeche`,
`flstkennz`, …) and the same 10 building attributes. Only the container differs — MV ships
zipped Shapefiles per Gemeinde where NW ships a GeoPackage per Kreis — so the existing
`zipshp` reader handles it and the field lists carry straight over.

Two things do need care:

**MV publishes every Gemeinde twice**, as `<ags>_NAS_<name>.zip` *and* `<ags>_SHP_<name>.zip`,
into one directory — 724 of each, 7.5 GB together. The dataset glob is therefore `*_SHP_*.zip`
and not `*.zip`; with the looser glob the 724 NAS archives are picked up too and every one
fails, because `/vsizip/<nas>.zip/Flurstueck.shp` does not exist. The NAS half is redundant
once the Shapefile half is loaded, and nothing reads it.

**`aktualit` is text here, not a date** — `"2024-04-22Z"` — where NW's GeoPackage gives a real
`DATE`. It needs `try_cast`, which NW does not. DuckDB parses the trailing `Z` itself, so only
the empty string has to be guarded.

All 724 packages were checked to carry both `Flurstueck.shp` and `GebaeudeBauwerk.shp`, so
there is no Gemeinde-shaped hole in either table.

### The truncated-UTF-8 repair

Every text attribute in MV's DBF is 254 bytes wide, and the publisher cuts long values to fit
**without respecting character boundaries**. One parcel's land-use summary ends
`…Forstwirtschaftsfl\xC3` — the lead byte of `ä` with its continuation byte gone. GDAL copies
the bytes through without complaint, but DuckDB rejects the entire Parquet file with
`Invalid string encoding`, so **one Gemeinde takes the whole state's load down**. Scanning all
724 packages: 1 file, 1 column — enough to break everything.

MV is therefore staged through `-dialect SQLITE -sql` rather than a plain `-select`, with

```sql
CASE WHEN length(CAST(f AS BLOB)) >= 254 THEN substr(f, 1, length(f) - 1) ELSE f END
```

applied to every 254-wide field. Only values *sitting at the cap* are touched — the only ones
that can have been cut — and they lose one more character from a string the publisher had
already truncated. Everything below the cap passes through byte-identical. It is applied to
all capped fields rather than just the one known to be broken today, because it is the same
defect with the same fix and there is no reason to guess which field breaks in the next
release. The `BLOB` cast is why this needs the SQLITE dialect: OGR SQL has no way to measure
a string in bytes.

## Sachsen: the NAS reader

Sachsen is the one state that ships a single statewide NAS *Bestandsdatenauszug* rather than
per-region files, and it needed a fourth reader. Three things are specific to it, all
measured on the 2026-07 export:

**It is a zip inside a zip** — `alkis_sn.zip` → `E_<auftrag>.zip` → 1,596 XML parts, ~95 GB
unzipped. Reading a part through nested `/vsizip` takes **88 s**; the same part as a plain
file parses in **0.4 s**. A deflate member cannot seek backwards, so the GML driver's rewinds
restart decompression from the top, twice over. The inner zip is therefore unwrapped once
into staging (2.4 GB, cached) and each part is extracted to a temp file, converted, and
deleted — peak extra disk is `JOBS × ~60 MB`, not 95 GB.

**The parts are split by object type, disjointly.** `AX_Flurstueck` is in 569 parts,
`AX_Gebaeude` in a *different* 508, and 519 parts hold neither. The archive is indexed once
(`parts.index`, ~30 s) so each dataset converts only its own third instead of all 1,596 twice.

**The parts do not share a schema.** `AX_Flurstueck` comes in 3 variants and `AX_Gebaeude` in
8. `zeitpunktDerEntstehung` is missing from 25 of the 569 parcel parts and
`gebaeudekennzeichen` from 103 of the 508 building parts — and `ogr2ogr -select` is *fatal* on
a field the source lacks, so a naive field list dies partway through. One `.gfs` is generated
from a part carrying the full field list and placed next to every extracted part; that pins a
single schema for the dataset and turns a missing field into `NULL` instead of an aborted run.
If no part satisfies the field list, the run stops and says so — that is how a changed export
announces itself rather than silently dropping a column.

Two smaller quirks: `srsName` is the AdV URN `urn:adv:crs:ETRS89_UTM33`, which GDAL does not
resolve, so the layer reports no CRS at all and `-s_srs EPSG:25833` is supplied explicitly;
and geometry is `CurvePolygon`, because ALKIS uses circular arcs, which `-nlt MULTIPOLYGON`
linearises.

Both downloaders' output locations are accepted — `./download_alkis.sh sn` writes `alkis/sn`
while `download_all.sh` writes `alkis/sn-nas`. A dataset's source dir may now list
alternatives as `sn|sn-nas`, and the first one with matching files wins; without that, SN
would be silently skipped depending on which downloader had been used.

## Staging is what makes it resumable

Every source is a different format in a different CRS, so each file is first converted by
`ogr2ogr` into GeoParquet — EPSG:4326, WKB, `MULTIPOLYGON`, geometry column renamed to `geom`
so the load SQL is source-agnostic — under `./alkis/.duckdb-stage/<state>-<kind>/`. DuckDB
then reads each dataset as one parquet glob.

A staged `.parquet` is never rebuilt, so an interrupted run resumes at the file it stopped on,
and the load itself is idempotent: `plots` and `structures` are keyed on
`(local_id, local_id_region)` and `structure_versions` on `(structure_id, valid_from)`, all
inserted `ON CONFLICT DO NOTHING`. **You can run this while `download_all.sh` is still
downloading** — files that aria2c still holds a `.aria2` control file for, or that were
touched in the last `SETTLE=60` seconds, are skipped rather than half-read. Re-run when the
download finishes and only the new files are converted.

`KEEP_STAGE=0` deletes each dataset's staging once it has loaded, at the cost of that
resumability. Staging the full tree costs roughly 8 GB, plus 2.4 GB for Sachsen's unwrapped
NAS archive, which lives under `.duckdb-stage/.nas/` and is what makes a second SN run skip
straight to converting.

## What goes in which column

`local_id` is the AAA object identifier **exactly as the state publishes it** — `oid` in NW
and BW (a 16-character id plus a two-character object-type suffix, `FL` for Flurstück, `BL`
for Bauwerk), `uuid` in BE, `identifier` in SN (the full AAA URN,
`urn:adv:oid:DESNALK0Aa2000Wy`). `local_id_region` and `region` are both the state ID, which makes
the pair unique nationwide. Bayern's Hausumringe carry no identifier of any kind, so one is
synthesised from the source file stem and the feature id (`091_Oberbayern_Hausumringe:1722464`);
it is stable for as long as the source file is.

Everything not mapped to a column of its own lands in `plots.metadata` as JSON, under German
key names (`flurstueckskennzeichen`, `gemarkungsschluessel`, `lagebezeichnung`, …) plus a
`quelle` naming the product it came from.

Two columns need a fallback. `area` uses the *amtliche Fläche* the cadastre states (`flaeche`,
`afl`, `amtlicheFlaeche`); where that is missing or zero it falls back to `ST_Area_Spheroid`
of the geometry. `valid_from` uses the source's own date (`aktualit`, `beg`), but **Berlin's
`gebaeude` layer and Bayern's Hausumringe carry no date at all** — those get a dataset-level
snapshot date, the newest source file's mtime, which for a fresh download is when the state
served it. Override with `FALLBACK_DATE=`. Sachsen sits between the two: parcels prefer
`zeitpunktDerEntstehung` (when the parcel came into existence) but it is null in about a
quarter of rows, so they fall back to `beginnt` — when this object *version* became current —
which is always present and is what buildings use directly.

`structure_versions.type` is a plain German label everywhere, but Sachsen is the only source
that ships it as a **numeric AdV code** rather than resolved text, so the loader translates
it. All 2,539,965 buildings in the export were scanned rather than sampled: 59 distinct codes
occur, and each is mapped from the
[AdV code list](https://repository.gdi-de.org/schemas/adv/citygml/Codelisten/BuildingFunctionTypeAdV.xml)
— `1000` → *Wohngebäude* (57% of them), `2000` → *Gebäude für Wirtschaft oder Gewerbe*,
`2463` → *Garage*, and so on. A code outside that set keeps its number
(`Gebäudefunktion 1234`) instead of collapsing into a generic bucket, so a future export's
new codes show up in a `GROUP BY` rather than hiding.

## The DuckDB translation of the PostGIS schema

- `geometry(Polygon,4326)` becomes plain `GEOMETRY`: DuckDB's spatial type carries no typmod,
  so the *Polygon* and *4326* parts are enforced by the script instead. `ogr2ogr` does the
  reprojection, and single-part `MULTIPOLYGON`s are unwrapped to `POLYGON`. Genuinely
  multi-part parcels — 0.6% of NW — stay `MULTIPOLYGON` and are counted in the run summary.
- `jsonb` becomes `JSON`.
- The `structures` table's `tableoid`/`cmax`/`xmax`/`cmin`/`xmin`/`ctid` columns are PostgreSQL
  *system* columns that leaked into the dump. They have no DuckDB equivalent and are omitted.
- Two `UNIQUE` constraints are added that the dump does not have: `structures
  (local_id, local_id_region)`, needed to find a structure when attaching its versions, and
  `structure_versions (structure_id, valid_from)`, which is what makes a re-run idempotent
  instead of duplicating every version row.

An `ingest_log` table records rows read, rows kept and multi-part count per dataset, and the
run prints it at the end. Rows are dropped only for a null or empty geometry, or for a
duplicate `local_id` within the same dataset: 1,285 of BW's 6.53 M footprints, and in MV 38
parcels plus 440 footprints — all duplicate `oid`s, none an empty geometry. MV's are a
side-effect of per-Gemeinde packaging: an object on a municipal boundary is published in both
neighbouring packages, so the dedup is doing exactly what it exists for. BE, BY, NW and SN
drop nothing.

Geometry is passed through as the cadastre drew it, not repaired: 68 of 13.6 M parcels fail
`ST_IsValid` (self-intersections in the source). Run them through `ST_MakeValid` if your
consumer needs OGC-valid input.

## Exporting to GeoParquet

`duckdb_to_geoparquet.sh` writes those tables back out as (Geo)Parquet — the whole set in
about 13 seconds.

```bash
./duckdb_to_geoparquet.sh                         # ./alkis.duckdb -> ./export
./duckdb_to_geoparquet.sh alkis.duckdb /mnt/out
TABLES="plots footprints" ./duckdb_to_geoparquet.sh
PARTITION=0 ./duckdb_to_geoparquet.sh             # one flat file per table
DRY_RUN=1 ./duckdb_to_geoparquet.sh               # print the COPY statements, write nothing
```

| Output | Rows | Size | Partitioned by |
|--------|------|------|----------------|
| `export/plots/` | 13.6 M | 3.8 GB | `region` |
| `export/structures/` | 23.2 M | 466 MB | `local_id_region` |
| `export/structure_versions.parquet` | 23.2 M | 3.1 GB | — |
| `export/footprints/` | 23.2 M | 2.5 GB | `local_id_region` |

DuckDB writes GeoParquet 1.0 **natively**: with the spatial extension loaded a plain
`COPY … (FORMAT PARQUET)` emits the `geo` metadata key that GDAL, QGIS and GeoPandas read.
There is no separate format name to ask for, and the `FORMAT GDAL, DRIVER 'Parquet'` route is
not available — DuckDB's bundled GDAL carries no Parquet driver.

The export always attaches the database **read-only**, so it is safe to run while the file is
open in QGIS. QGIS holds a write lock, and without `-readonly` DuckDB refuses to attach at all.

`footprints` is not a table — it is `structures` joined to `structure_versions` and collapsed
into one self-contained spatial layer, which is usually what a downstream GIS wants; the split
into identity and version is a database concern rather than a file-format one. It is not in
the default set, being the same data as `structure_versions` in a second shape. Note also that
**`structures` has no geometry column**, so that one is plain Parquet, not GeoParquet.

Two things about the output:

- **A partitioned column lives in the directory name, not the data.** Read the set back with
  `read_parquet('export/plots/**/*.parquet', hive_partitioning = true)` to recover `region`,
  or set `PARTITION=0` for one flat file per table that keeps the column inline.
- **The CRS is implicit.** DuckDB writes no `crs` key, which per the GeoParquet spec means the
  default `OGC:CRS84` — exactly what these geometries are. GDAL resolves it back to
  EPSG:4326.

---

# LiDAR for the sample squares only

`download_samples.sh` runs the LiDAR downloaders over the 5×5 km squares in
[`sample_squares.tsv`](sample_squares.tsv) — one per state, aligned to the UTM kilometre grid
in that state's own CRS so the square lands on tile boundaries and never asks for a partial
tile. This is the sampling path; `download_all.sh` has no `BBOX` and always takes whole states.

```bash
DRY_RUN=1 ./download_samples.sh both       # every state's plan and tile count, no transfer
./download_samples.sh dgm1                 # terrain for all 16 squares -> ./samples/<id>/dgm1
./download_samples.sh both                 # terrain + a centred point-cloud core
STATES="nw be sn" ./download_samples.sh both
LAS_KM=5 ./download_samples.sh las         # full square of point cloud, ~2.4 GB per state
```

Output is `./samples/<id>/{dgm1,las}` — the layout `convert_to_cloud_optimized.sh` expects, so
`./convert_to_cloud_optimized.sh dgm1 ./samples/nw ./cog` follows directly.

What a `both` run actually plans, verified live 2026-07-29:

| State | dgm1 | las | Note |
|-------|------|-----|------|
| BB Lübbenau | 25 tiles | **0** | ALS still partial — the centred core is in a gap; 5 tiles across the full square |
| NW Königswinter | 25 tiles | 9 tiles (1.5 GB) | 1 km grid, the reference case |
| NI Goslar | 25 tiles | — | no open point cloud |
| MV Sassnitz | 6 tiles | 9 tiles | dgm1 on a 2 km grid, las on 1 km |
| SN Bad Schandau | 4 tiles | 4 tiles | 2 km packaging both products |
| BW Heidelberg | 4 tiles | — | no open point cloud |
| BE Berlin-Mitte | 9 tiles | 1 region (0.9 GB) | las ships as city-region ZIPs, not tiles — cut by region, not by square |
| BY Garmisch | refused | 4 tiles | dgm1 is one statewide Metalink, uncuttable |
| RP St. Goarshausen | refused | refused | no `BBOX` support at all |
| ST Wernigerode | — | **0** | no open dgm1; the square is outside both open LAZ areas |
| TH Eisenach | 25 tiles | 9 tiles (~1.3 GB) | 1 km grid like NW; newest of three vintages unless `VINTAGE=` |
| SL Mettlach | — | 9 tiles (~0.4 GB) | `dgm1` is published but not wired into the script; `las` is cut out of the district ZIPs |

The five states with no LiDAR downloader (HB, HH, HE, SL, SH) are skipped with a
reason. ST has one, but its square (Wernigerode) sits outside both areas Sachsen-Anhalt
publishes openly, so it plans 0 tiles and is reported as a coverage gap. **Refusals are the point**: a downloader that ignores `BBOX` accepts the square and
plans the whole state, so RP alone would pull 32.8 GB of terrain and 5.18 TB of point cloud
under the guise of a sample. Each is detected and refused rather than skipped quietly;
`ALLOW_UNCUT=1` forces them, which is only useful with `DRY_RUN=1` to see the size.

Berlin's point cloud is the one refusal with a way out. It has no tile grid at all — the city
ships as nine region ZIPs, 232.3 GB together, and a region is the smallest unit on offer. But
the regions are wildly uneven, and the smallest is sample-sized: **Nordost, 0.9 GB** (11 las
tiles, 2.4 GB unzipped) against 47.7 GB for Suedost. So BE is cut by region rather than by
square, and lands in the same range as the square-cut states:

```bash
./download_samples.sh las                              # BE gets Nordost, 0.9 GB
BE_LAS_REGIONS="Nordost Ost" ./download_samples.sh las # 15.6 GB
BE_LAS_REGIONS="" ./download_samples.sh las            # refuse BE again, as before
REGIONS=Mitte ./download_be_lidar.sh las               # or straight from the downloader
```

The catch, worth knowing before you compare the two BE samples: Nordost is Buch/Karow on the
city's northeast edge, ~25 km from the Berlin-Mitte square the `dgm1` sample uses. They do not
overlap. Co-locating them means `REGIONS=Mitte`, which is 34.2 GB. A region name the feed does
not offer is a hard error listing the nine valid ones — not an empty download that reports
success.

Two units meet here. Every downloader takes `BBOX` as **UTM kilometres, inclusive of both
corners** — so the TSV's true 5 km extent (`371..376`) has 1 subtracted from each maximum,
because passing it verbatim selects six tiles per axis. Niedersachsen is the exception under
the hood: its STAC API filters only in WGS84 degrees, so `download_ni_lidar.sh` now accepts
either, telling them apart by magnitude, and applies a UTM box to the tile key carried in each
item name (`dgm1_32_601_5752_1_ni_2018` → 601, 5752). Exact, but it costs a walk of the whole
~141-page catalogue to find 25 tiles. That walk is item metadata only — the 25 matching
URLs are all that reach aria2c.

---

# 1. Complete coverage — all four datasets

Sections 2 and 3 each answer one dataset at a time. This one answers the crossing question:
**for which states can we fetch point cloud *and* terrain *and* parcels *and* building
footprints?** Footprint sources are detailed in
[`cadastre-products.md`](cadastre-products.md#3-open-data-equivalents-per-bundesland).

**Ten states: BB, BE, BW, MV, NI, NW, SL, SN, ST, TH** — seven of them free end to end, and
three (BW, NI, ST) only because a point cloud you buy still counts as a point cloud you can
have.

<img src="coverage_map.svg" alt="Map of the 16 Bundesländer coloured by coverage: green (BB, BE, BW, MV, NI, NW, SL, SN, ST, TH) for all four datasets, with BW, NI and ST marked € because their point cloud is bought rather than downloaded; orange (BY, HE, RP) for one missing; light red (HB) for no bulk LiDAR route; dark red (HH, SH) for no point cloud on any terms" width="560">

Both the ten and the six that fall short are tabulated in
[README.md §3](README.md#3-complete-coverage--all-four-datasets).

Footprints are never a separate fetch in these ten: ALKIS carries `AX_Gebaeude`, so the
parcel download brings them along. The extra products in the last column are convenience —
smaller, simpler files than a full NAS package for anyone who wants only footprints.

**TH joined this list on 2026-08-03**, and only the elevation half changed: its cadastre was
always scriptable. The point cloud and terrain turned out to be published through three
standard INSPIRE Atom feeds linked at the foot of the `gaialight` page that had been the
blocker — see [Thüringen](#thüringen-three-atom-feeds-behind-a-portal). Its footprints had
also been counted as unscriptable because the *standalone* Hausumringe product is
CAPTCHA-gated; they ship inside the ALKIS package, which is the same route that already
counted for BB, SL, SH and HH.

**SL joined on the same day, with one asterisk.** All four datasets are open and anonymously
downloadable, which is what the map colours by — but `download_sl_lidar.sh` fetches the point
cloud only, so the repo can currently script three of SL's four. Its DGM1 sits in the same
share, in the same packaging, and wiring it in is one folder name. See
[Saarland](#saarland-the-share-the-repo-was-already-reading).

Picking between them: **NW** is the strongest — every product carries a machine-readable
index, and DL-DE/Zero 2.0 means no attribution obligation. **BE** is the fastest to fetch
end to end (~0.2 GB of DGM1, 9 point-cloud packages, WFS cadastre) and also DL-DE/Zero, which
makes it the natural smoke test for a full four-dataset pipeline. **BB** carries one caveat:
its point cloud is still **partial** — 13,086 LAZ tiles against a complete 31,291-tile DGM1
grid, released campaign by campaign.

**BW, NI and ST are green with a `€`, and that mark is doing real work.** Each sells a
statewide point cloud it will not let you download, so the data is obtainable but never for
free and never through a URL — LGL's `ALS_2` for a handling fee, LGLN's Laserscan-Punktwolke
on a KOVerm quote, LVermGeo's 3D-Messdaten at 190 € (and in ST's case the terrain is on the
same invoice). The tooltip on both maps carries the product, the terms and who to ask. Before
2026-08-05 all three were drawn as though the data did not exist, which was the wrong claim
about four states at once; see [The states that sell it](#the-states-that-sell-it).

The map still carries **two shades of red**, because the two ways of ending up without
elevation are not the same problem. Light red is a delivery gap: the products exist and are
open, but nothing hands them over whole, so the state moves up the day a route appears. Only
**HB** is left there — ST vacated it the moment a price list started counting. Dark red is a
supply gap: **HH and SH** neither publish a point cloud nor offer to sell one, so there is
nothing to fetch and nothing to buy, even though both have working DGM1 downloaders. The
LiDAR map below ranks them the same way, for the same reason.

**HE left light red on 2026-08-04 without anyone writing code**, which is what "a route
appears" looks like in practice: HVBG will copy the statewide laser scan onto a hard disk you
post them, so Hessen's elevation is now obtainable in full and only its footprints are missing
— an orange state, one dataset short. It carries a `*` on the map because none of that comes
through an endpoint. See [Hessen: a hard disk in the post](#hessen-a-hard-disk-in-the-post).

This map and the two below it are drawn by [`coverage_map.py`](coverage_map.py) from
`bundeslaender.geojson`, so they follow the data rather than the README.md tables. Regenerate all
three with `./coverage_map.py all` after any coverage change; the script writes both an `.svg`
and a `.png` per map, same image either way, but only the vector one carries a per-state
tooltip.

## Why the other six fall short

The six are the rest of the table in
[README.md §3](README.md#3-complete-coverage--all-four-datasets) — same columns as the ten,
so the gaps line up against them.

Every one of the six has open, scriptable **parcels**. The gaps cluster: RP and BY are a
single content gap each — a rasterised cadastre, with everything else in place. HE is a third
single-gap state, and the odd one out, because its missing dataset is footprints rather than
elevation: the Downloadcenter's Hausumringe needs a free account, while its point cloud and
DGM1 are both obtainable in full. HH and SH have no point cloud on any terms, free or paid,
which is the only gap on this list that no amount of money closes. That leaves HB, where no
bulk elevation route of any kind has been identified — not an access restriction, an absence
of a route. HB, HE, HH and SH additionally have no scriptable standalone footprint product.

Three states left this list on 2026-08-05 without publishing anything new: BW, NI and ST all
sell their point cloud, and once a purchase counts as a route their four datasets are all
obtainable. What they carry instead is a `€`.

## Fetching all four today

Whole-state, `download_all.sh` covers it — `ONLY=<id> ./download_all.sh all` fetches every
dataset that state publishes. What has no single command is a *sample*: `download_samples.sh`
drives only the LiDAR side, because `download_alkis.sh` has no `BBOX` support, so parcels and
footprints stay per-state or per-package until that lands. For one of the ten states — the
seven free ones; for BW, NI and ST the point cloud arrives by invoice, not by script:

```bash
ONLY=<id> ./download_all.sh all                 # all four datasets, statewide volumes
# or, one product at a time:
./download_<id>_lidar.sh both ./samples/<id>    # point cloud + terrain
./download_alkis.sh <id>                        # parcels + building footprints
```

---

# 2. LiDAR / terrain availability

**No state gates its LiDAR behind a login** — every one of the 16 publishes elevation as open
data. The dividing line this map draws is whether the *whole state* can be obtained at all, by
any confirmed route: a script, Hessen's hard disk in the post, or an order form.

<img src="lidar_map.svg" alt="Map of the 16 Bundesländer coloured by LiDAR availability: green for the 13 states whose point cloud and terrain can both be obtained in bulk, HE starred because it arrives offline on a posted hard disk and BW, NI and ST marked € because their point cloud is bought; orange (HB) for open data not obtainable whole; red (HH, SH) for terrain only, no point cloud on any terms" width="560">

Green is the thirteen states whose elevation can be had in both products — nine by script,
plus HE by post (`*`), plus BW, NI and ST by purchase (`€`). Orange is HB alone, which
publishes elevation openly and hands over no more than a fraction of it. Red is HH and SH,
scripted and working for terrain but with **no point cloud on any terms**.
Regenerate with `./coverage_map.py lidar`.

Red is therefore not worse than orange by accident: an orange state is one route away from
green, while a red state has nothing more to give — not even for money. HH and SH crossed from
orange to red on 2026-08-04 by gaining a downloader, not by losing anything.

**Red is now a genuinely empty shelf, which it was not before.** A 1 m DGM is derived from a
laser scan, so every state in this table has flown one; the question is what it does with the
scan afterwards. Until 2026-08-05 this map answered that question with "does it publish it",
and painted BW, NI and ST the same as HH and SH — four states drawn as though the survey had
never happened, when three of them will sell you the whole thing. Red now means the narrower
and truer claim: nobody here has found a route, free or paid. HH and SH are what is left of
it — and that is a "not found", not a "does not exist". LGV Hamburg and LVermGeo SH were both
checked on 2026-08-05 and neither lists a point-cloud product; SH's price list sells the DGM1
it also gives away free. Neither office was asked directly, so if one of them turns out to
sell a scan, that is a `€` and a colour change, in the same spirit as the corrections in
[Bremen: the last unproven verdict](#bremen-the-last-unproven-verdict).

**Why HE is green with no downloader.** The colour answers "can we have all of it", and the
answer is yes: HVBG copies the statewide laser scan onto a disk you post them, and DGM1 is a
free storefront order. Colouring that worse than BY's Atom feeds would say Hessen withholds
something it does not — the gap is in this repo's automation, not in the state's publishing,
and the `*` is where that gap is recorded. See
[Hessen: a hard disk in the post](#hessen-a-hard-disk-in-the-post).

**ST is green, but it does not get HE's `§`/`*` treatment.** The two arrangements sound alike
— both are "on request", neither has an endpoint — and the difference is the invoice. Hessen's
disk is free, so its elevation costs nothing but postage; Sachsen-Anhalt's statewide
3D-Messdaten is 190 € je Datensatz, and the DGM and DOM derived from it are sold alongside.
Both states can be had whole, which is why both are green; `*` and `€` say on what terms. What
ST gives away anonymously is still just two sample areas and a five-tile DGM1 cap. See
[Sachsen-Anhalt](#sachsen-anhalt-samples-not-a-state).

The per-state table — products, downloader, CRS and licence — is
[README.md §1](README.md#1-lidar--terrain-availability).

**13 of 16 states are scripted statewide** — 315,593 km², 88% of Germany's land area by the
figures in [The 16 Bundesländer](#the-16-bundesländer), and well over 12 TB of point cloud
between them. Three numbers follow from there, and they are worth keeping apart:

| Elevation obtainable … | km² | share | who |
|---|---:|---:|---|
| by a script here | 315,593 | 88% | the 13 downloaders |
| + free, but offline | 336,709 | 94% | + HE's posted hard disk |
| + paid | 357,168 | **99.9%** | + ST's 190 € order — everything but Bremen |
| …of which the **point cloud** too | 340,609 | 95% | all but HB, HH and SH |

The first two differ by exactly the 21,116 km² that arrive by courier; the third by ST's
20,459, which is what a price list buys. The fourth is the one to quote when the point cloud
is what matters: HH and SH have working terrain downloaders and no laser scan on offer at all,
so 4.6% of Germany is terrain-only whatever the budget.

SH and HH joined on 2026-08-04 and both are terrain-only, because neither publishes or sells a
point cloud — which is why they are red on the LiDAR map rather than green. SL's terrain is
now wired in alongside its point cloud, so the ◐ that used to sit in its DTM column is gone.

## Volumes for the scripted states

Volumes are what a downloader here actually plans. The `€` cells have none: nobody has bought
those products, so the tile counts and sizes are unknown — see
[The states that sell it](#the-states-that-sell-it).

| ID | State | `las` (point cloud) | `dgm1` (terrain) |
|----|-------|---------------------|------------------|
| **BY** | Bayern | ~69,546 tiles (1 km), multi-TB | 71,979 tiles, 217 GB |
| **BE** | Berlin | 9 region packages, 232.3 GB | 297 tiles (2 km), ~0.2 GB |
| **BB** | Brandenburg | 13,086 tiles (1 km), ~1.35 TB | 31,291 tiles (1 km), ~36 GB |
| **MV** | Mecklenburg-Vorpommern | 25,466 tiles (1 km) | 6,407 tiles (2 km) |
| **NI** | Niedersachsen | € not downloadable — LGLN order | 49,708 tiles (1 km), **already COG** |
| **NW** | Nordrhein-Westfalen | 35,860 tiles (1 km), 3.49 TB | 35,860 tiles (1 km), 78.8 GB |
| **RP** | Rheinland-Pfalz | ~21,207 tiles (1 km), 5.18 TB | ~21,082 tiles (1 km), 32.8 GB |
| **SN** | Sachsen | 4,981 tiles (2 km) | 4,981 tiles (2 km) |
| **BW** | Baden-Württemberg | € not downloadable — LGL `ALS_2` order | 9,370 zips (2 km), ~125 GB |
| **TH** | Thüringen | 16,945 tiles (1 km), ~1.52 TB | 16,945 tiles (1 km), ~127 GB |
| **SL** | Saarland | 3,076 tiles (1 km), 124 GB | 3,076 tiles (1 km), 12.3 GB GeoTIFF or 2.1 GB LAZ |
| **SH** | Schleswig-Holstein | ❌ none published, none for sale | 18,685 tiles (1 km), ~515 GB — **ASCII XYZ** |
| **HH** | Hamburg | ❌ none published, none for sale | 880 tiles (1 km), 1.37 GB GeoTIFF (2022 edition) |
| **ST** | Sachsen-Anhalt | 62 tiles (2 km), 20.4 GB free — **two sample areas**; € statewide by order | € by order — the free UI caps a selection at 5 tiles |

TH's figures are for the newest of its three vintages; all three together are ~2.9 TB of
point cloud and ~219 GB of terrain, on the same grid.

## Thüringen: three Atom feeds behind a portal

Thüringen looks like a portal state and is not one. `dl-dhm.html` is a `gaialight` map app
whose `overview.php`/`details.php` need the app's internal filter state — that is where the
first attempt at this stopped, and why the README listed TH as unscriptable until 2026-08-03.
But the same page links three **standard INSPIRE Atom download services** at the bottom, and
those are a complete inventory:

```
https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_las   # point cloud
https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_dgm   # terrain
https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_dom   # surface
```

Each is a service feed → one dataset feed → one `<link rel="section">` per tile, with a direct
`.zip` URL and a WGS84 bbox. No login, no CAPTCHA, no token — verified live 2026-08-03 by
HEADing a sample from every vintage. `download_th_lidar.sh` drives them.

All three products share one **1 km grid**, in EPSG:25832, and each is published in three
flight campaigns:

| `VINTAGE=` | Tiles | `las` | `dgm1` | `dom1` | Grid | Heights |
|-----------|-------|-------|--------|--------|------|---------|
| `2010-2013` | 17,127 | ~443 GB | ~19 GB | ~19 GB | **2 m** (`dgm2_*`) | DHHN92 / GCG2005 |
| `2014-2019` | 17,127 | ~975 GB | ~73 GB | ~76 GB | 1 m | DHHN2016 / GCG2016 |
| `2020-2025` | 16,945 | ~1.52 TB | ~127 GB | ~131 GB | 1 m | DHHN2016 / GCG2016 |

The newest is the default. Sizes are a 32-tile HEAD sample per cell (2026-08-03) extrapolated
by the mean; the feed publishes none. `las` tiles are heavily right-skewed by terrain cover —
a forested Eisenach tile is 270 MB against a 65 MB median — so a median-based estimate would
understate the total by a third, and even the mean is only an order of magnitude. The
2020-2025 grid is 182 tiles *smaller* than the older two, and those 182 are a strict subset:
that vintage is missing them, it adds nothing new.

Two things to know before sizing a disk. The oldest vintage is a **2 metre** model published
as `dgm2_*`/`dom2_*` — asking for `dgm1` there gets you the coarser grid, and the script says
so at run time. And each `dgm1`/`dom1` zip carries the same grid **twice**, as a GeoTIFF and
as an ASCII `.xyz` about ten times its size (2.9 MB vs 29 MB for one tile); they cannot be
requested separately, so most of a "115 GB" terrain run is ASCII you may not want.

```bash
./download_th_lidar.sh dgm1 ../germany-data/th_lidar     # newest terrain, ~127 GB
./download_th_lidar.sh las /mnt/big/th                   # ~1.5 TB
VINTAGE=2014-2019 ./download_th_lidar.sh dom1            # an older campaign
DRY_RUN=1 BBOX="591,5646,595,5650" ./download_th_lidar.sh las   # the Eisenach square
```

The published unit is the per-tile `.zip` and it is left as downloaded, like SN and BB: `las`
holds a `.laz` plus a `.meta` sidecar, `dgm1`/`dom1` hold `.tif` + `.xyz` + `.meta`. The
`.meta` is worth reading — it names the flight campaign, the acquisition month and the stated
accuracy per tile. No checksums are published, so downloads are resumable and size-checked,
not hash-verified.

## Saarland: the share the repo was already reading

Saarland's whole 2025 airborne laser scan is open — 3,076 tiles, 124 GB of classified LAZ,
six of six Landkreise — and it has been sitting in a folder next to one this repo opens on
every `download_alkis.sh sl` run. LVGL publishes its statewide open data through a
password-less Nextcloud share; `plan_sl()` reads `OD_ALKIS_nas_LK` out of it. One PROPFIND
level up are eighteen folders, including:

| Folder | Contents | Size |
|--------|----------|------|
| `OD_LIDAR_Punktwolke_2025_laz_LK` | **classified point cloud, `.laz`** | **115.7 GB** |
| `OD_DGM1_2025_tif_LK` · `…_laz_LK` | terrain, GeoTIFF · LAZ | 5.1 GB · 2.0 GB |
| `OD_DOM1_2025_tif_LK` · `…_laz_LK` | surface model | 5.7 GB · 2.8 GB |
| `OD_TrueDOP20_2025_tif_LK` | true orthophotos, 20 cm | 217.3 GB |
| `OD_Gebäudemodelle_LoD2_gml_LK` | LoD2 building models | 1.2 GB |

The README said "no open LiDAR bulk product identified" for SL until 2026-08-03. It was never
a delivery problem — nobody listed the share.

Licence is **DL-DE/BY 2.0**, and LVGL states the source note verbatim:
`© GeoBasis DE/LVGL-SL (Jahr der Bereitstellung)`.

The point cloud is one ZIP per district, 12.5–26.2 GB each, on a 1 km grid spanning
E 308–384 / N 5441–5500 (UTM32):

| `KREISE=` | District | Tiles | Archive |
|-----------|----------|-------|---------|
| `MZG` | Merzig-Wadern | 649 | 26.2 GB |
| `NK` | Neunkirchen | 310 | 12.5 GB |
| `SB` | Regionalverband Saarbrücken | 499 | 20.6 GB |
| `SLS` | Saarlouis | 547 | 21.6 GB |
| `SPK` | Saarpfalz-Kreis | 509 | 20.6 GB |
| `WND` | St. Wendel | 562 | 22.7 GB |

Nextcloud's public WebDAV endpoint serves those archives anonymously **and honours Range**, so
`download_sl_lidar.sh` never downloads one whole: it reads each ZIP's central directory over
ranges, then range-fetches and inflates only the tiles selected, straight to `.laz` — the same
technique as [Sachsen-Anhalt](#sachsen-anhalt-samples-not-a-state). A tile is ~38 MB, 4 M
points, 4 pts/m², classified, with Intensity and GPS time.

```bash
./download_sl_lidar.sh las ../germany-data/sl_lidar    # all six districts, 124 GB
KREISE=NK ./download_sl_lidar.sh                       # one district, 12.5 GB
DRY_RUN=1 ./download_sl_lidar.sh                       # plan the 3,076 tiles, fetch nothing
BBOX="321,5485,323,5487" ./download_sl_lidar.sh        # the repo's Mettlach square, 9 tiles
```

DGM1 and DOM1 are in the same share in the same packaging, so they are the same code path with
a different folder name — `./download_sl_lidar.sh dgm1` and `dom1`, or `both` for `las` plus
`dgm1`. `FORMAT=tif` (the default) or `FORMAT=laz` picks the encoding; the terrain is 3,076
tiles either way, 12.3 GB of GeoTIFF or 2.1 GB of LAZ once unpacked. `las` is published only
as LAZ, so `FORMAT` does not apply to it.

One thing this script does *not* do:
it discovers the share token by following the `/cloud/freiegeobasisdaten` alias, whereas
`download_alkis.sh` still has that token hard-coded — worth unifying, since a re-share would
break the ALKIS side silently. Note the alias redirects to an **`http://`** URL and the site's
http→https rule drops the path, so the token has to be read from the first `Location` header,
not from the end of the redirect chain.

## Schleswig-Holstein: the index was never empty

This repo recorded SH as "`overview.php` returns an empty FeatureCollection". That is true of
`overview.php`, and irrelevant: the portal publishes a *Massendownload* index as a static
file, and it holds **18,685 tiles**, every one with a direct `link_data` URL.

```
.../dladownload/single.php?file=DGM1_SH__Massendownload.geojson&id=4
```

9 MB of GeoJSON, EPSG:25832, one feature per km² carrying `kachel`, `datum` and `link_data`.
Vintages run 2005–2025 and there is exactly **one tile per km²** — a reflown km² replaces its
predecessor instead of being added alongside it, so unlike NI there is no "newest campaign"
filter to apply. The mix is uneven, though: 3,550 tiles are still 2005 against 3,963 from
2025, so `MINYEAR=2020` is offered for anyone who would rather have a hole than a
twenty-year-old height.

Licence is **CC BY 4.0** — `©GeoBasis-DE/LVermGeo SH/CC BY 4.0`, and with
`(Quelle verändert)` appended once the data has been altered.

Three properties of this endpoint shaped the downloader, and all three will bite anything
naive pointed at it:

- **It ignores `Range` and sends no `Content-Length`.** PHP streams the body chunked, so
  aria2c cannot resume a partial tile and there is no size to check against. Tiles are
  therefore all-or-nothing: `.part`, validated, renamed.
- **Every response has ~759 bytes of HTML navigation markup stapled on after the last data
  record.** Left in place it corrupts the XYZ for every downstream reader. Stripping it is
  the fix; its presence is also the only proof the response ran to completion, which is what
  substitutes for the missing `Content-Length`.
- **Some index entries are dead**, and the server answers those with **HTTP 200** and a German
  error body — "Die verwendete Massendownload-Datei ist veraltet" — which a naive downloader
  writes out as a 962-byte `.xyz`. About 1.7% of a 60-tile sample, all of it 2005 vintage.
  `download_sh_lidar.sh` detects them, skips them and lists them at the end; re-running will
  not help, because they are holes in SH's own catalogue.

Each tile is validated before it is renamed into place: the closing markup must be there, and
the first and last records must equal the tile's NW and SE corners as computed from its name.
That catches truncation and mis-served tiles alike, and makes resume cheap — a tile whose last
record already matches its SE corner is skipped.

```bash
./download_sh_lidar.sh dgm1 ../germany-data/sh_lidar   # statewide, ~515 GB
BBOX="424,6002,428,6006" ./download_sh_lidar.sh        # one 4x4 km corner
MINYEAR=2020 ./download_sh_lidar.sh                    # skip the older vintages
```

Budget for it: **no gzip** — the server does not honour `Accept-Encoding`, so ~515 GB is the
wire volume as well as the disk volume. And the product is **ASCII XYZ**, roughly 7× the size
of the equivalent GeoTIFF, so `gdal_translate -a_srs EPSG:25832` before
`convert_to_cloud_optimized.sh` rather than instead of it.

## Hamburg: the listing 403s, the files never did

HH was recorded here as reachable "only by exact known URL", because `daten-hamburg.de`
returns 403 on directory listings. It still does. What was missing was never access — every
archive is a plain anonymous HTTPS GET with `Content-Length` and working `Range` — but the
*file list*, and that comes from the Transparenzportal's CKAN API, which `download_alkis.sh
hh` was already querying for ALKIS.

The catalogue holds dozens of near-duplicate packages (snapshot copies, re-registrations), so
`download_hh_lidar.sh` selects resources by their file URL path rather than by package name,
and reads the vintage out of each filename. Two products:

| Dataset | What | Vintages | Newest |
|---------|------|----------|--------|
| `dgm1` | terrain, 1 m grid, ~880 tiles | 9, from 2013 to 2022-04-30 | 1.37 GB GeoTIFF |
| `dom1` | **bDOM** — surface model computed from aerial imagery, not laser | 4, from 2018 to 2022-11-21 | 3.34 GB GeoTIFF |

**The portal's own format labels are wrong for the newest DGM1.** The Transparenzportal lists
`dgm1_hh_2022-04-30.zip` as *PNG*; the archive contains GeoTIFF. The script reads the entry
names out of each archive instead of trusting the catalogue, which also handles the older
editions being ASCII XYZ — the packaging changed at 2022 and the metadata did not keep up.
(The `2x2km` in the older filenames is legacy too; their entries are 1 km tiles.)

Both products honour `Range`, so tiles come out of the archive the same way Saarland's and
Sachsen-Anhalt's do — central directory over ranges, then only the tiles selected:

```bash
./download_hh_lidar.sh dgm1 ../germany-data/hh_lidar   # newest edition, 1.37 GB
LIST=1 ./download_hh_lidar.sh dgm1                     # show the 9 vintages
VINTAGE=2021 ./download_hh_lidar.sh dgm1               # an older one (XYZ, not GeoTIFF)
BBOX="565,5930,570,5935" ./download_hh_lidar.sh        # central Hamburg
```

Hamburg publishes no point cloud and does not sell one either — the one gap on these maps
that money does not close — so `las` exits 3 with that explanation.

## The states that sell it

Three states will hand over a statewide point cloud and will not let you download it. On the
maps they are green with a `€`; here is what is actually on offer, as of 2026-08-05.

| | Product | Coverage | Density | Format | Terms | Ask |
|---|---|---|---|---|---|---|
| **BW** | LGL `ALS_2` | statewide, 2016–21 campaign | ≥ 8 pts/m² | LAZ, LAS or XYZ-ASCII | licensed **Open Data**; effort-based Service-Entgelt, **min. 60 € + VAT** | `geodaten@lgl.bwl.de` · 0711 95980-200 |
| **NI** | LGLN Laserscan-Punktwolke (3D-Messdaten) | statewide | ≥ 4 pts/m² | LAZ 1.2, 1 km² tiles | **KOVerm** fee schedule, no public per-km² rate, quote on request; LGLN **AGNB**, not CC BY | `geoService-3D@lgln.niedersachsen.de` |
| **ST** | LVermGeo 3D-Messdaten | statewide, 6-year cycle | 4–8 pts/m² | LAS 1.2 / LAZ | **190 € je Datensatz**, auf Antrag; DGM and DOM derived from it are sold separately | see below |

Three things are worth noticing across the row.

**Paying does not always mean the data is closed.** BW's `ALS_2` is *open data by licence* —
the 60 € minimum is a handling charge for cutting and shipping it, not a purchase of rights.
NI's is the opposite: a different licence (AGNB) from the CC BY its free DGM1 carries. Same
`€` on the map, quite different downstream.

**None of them has an endpoint, and that is what keeps them out of the downloaders.** Every
one is an email describing an area — coordinates, a shapefile, or tile names — answered with
a quote and then a download link or a posted disk. There is no URL to drive, so `las` exits 3
in all three scripts and says who to write to.

**The free products are not consolation prizes.** BW and NI both give away the DGM1 derived
from these scans, statewide, and this repo scripts both. If bare earth is what you need, you
already have it; the cloud buys the returns themselves — classification, echoes, sub-ground
points. ST is the exception, and the only state where the terrain is on the invoice too.

## Sachsen-Anhalt: samples, not a state

Sachsen-Anhalt is the one state where a downloader exists but the coverage does not. It is
green on the maps because LVermGeo will sell the whole state (see
[The states that sell it](#the-states-that-sell-it)); it is listed apart from the thirteen
because treating it as "scripted" would overstate what the code here gets you.

LVermGeo publishes the statewide point cloud (`3D-Messdaten`, ALS, 4–8 pts/m², classified,
LAS 1.2 / PDRF 3) as a **priced, application-only product** — 190 € per Datensatz, "auf
Antrag". No Atom feed, no WFS, no tile API exposes it, and the free DGM1/DOM1 map downloader
caps a selection at five tiles per request. What *is* free, anonymous and scriptable is two
published sample areas, and that is exactly what `download_st_lidar.sh` fetches:

| Area | `AREAS=` | Tiles | Size | Flown |
|------|----------|-------|------|-------|
| Gebiet Hakel | `hakel` | 11 | 2.9 GB | 2019 |
| Gemeinde Halle (Saale) | `halle` | 51 | 17.4 GB | 2017 (one tile 2021) |

Together ~0.1% of the state — two islands, not a coverage layer. Tiles are 2 km,
`3dm_32_<E_km>_<N_km>_2_st_<year>.laz`, UTM32 / DHHN2016, carrying Intensity and RGB.

Both areas are plain ZIPs on the LVermGeo webshare (Halle is ZIP64, over 4 GB). The script
does **not** download the archives whole: it reads each central directory over HTTP range
requests, then range-fetches and inflates only the tiles selected, straight to `.laz`. So
`BBOX` works and costs only the tiles it selects, nothing is staged twice on disk, and resume
is per tile.

```bash
./download_st_lidar.sh las ../germany-data/st_lidar   # both areas, ~20 GB
AREAS=hakel ./download_st_lidar.sh                    # just the 2.9 GB one
DRY_RUN=1 ./download_st_lidar.sh                      # list the 62 tiles, fetch nothing
BBOX="658,5746,662,5750" AREAS=hakel ./download_st_lidar.sh
```

`dgm1` is refused rather than half-implemented, with a pointer to the 5-tile widget. Note the
repo's ST sample square (Wernigerode) falls in neither area, so `download_samples.sh` plans
**0 tiles** for ST and says so — that is a real coverage gap, not a broken downloader.

## Bremen: the last unproven verdict

Bremen is **also open data** — it does not put LiDAR behind a login — but no open bulk product
was ever identified here. Unlike ST, which at least publishes samples, and HE, which will post
you a disk, there is no known route of any kind. That is the whole of what is known, which is
exactly the problem.

Five states have now left this table, and not one of them had changed what it publishes — only
what had been looked at. TH's three INSPIRE Atom feeds were linked from the very page that was
tried. SL's point cloud was in the Nextcloud share this repo *already reads for ALKIS*, one
folder along from the one it was opening. SH's `gaialight` index was recorded here as returning
an empty FeatureCollection — it returns 18,685 tiles, each with a direct link, and the previous
verdict was written from a different endpoint of the same app. HH's blocker was the directory
listing, which does 403 — but the archives behind it never needed one, and the
Transparenzportal's CKAN API lists them. And HE, the fifth, was cleared without any endpoint at
all: someone sent an email and was offered a hard disk.

So treat Bremen's verdict as unproven until someone has checked for an Atom/INSPIRE service
under `…/dienste/`, listed every folder of any share the state already exposes, asked whether
the catalogue API can substitute for a listing that 403s — and, on Hessen's precedent, simply
written to ask. On the evidence so far that verdict has been wrong five times out of six, and
the sixth is the one still standing.

| ID | State | Status | What blocks a bulk copy |
|----|-------|--------|-------------------------|
| **HB** | Bremen | No open LiDAR bulk product identified. | Unknown — no product located, so nothing to characterise. |

## Hessen: a hard disk in the post

Hessen's point cloud is the one dataset in this repo that arrives by post. HVBG confirmed by
email on **2026-08-04**: send them a hard disk, they copy the statewide laser scan onto it and
send it back. The data itself is free — Hessen's geodata has carried **no usage conditions
since 2022-02-01** — so the cost is the disk and the postage in both directions.

**This counts as a bulk route, and HE is green on the LiDAR map because of it.** The maps were
originally colouring by "can a script fetch it", which was a fine proxy for "can we have it"
right up until a state offered to hand over the whole thing on a disk. Those are different
questions and Hessen is where they came apart. Ranking it below BY — whose Atom feeds this repo
does drive — would have said Hessen withholds something it does not; the honest reading is that
Hessen publishes everything and this repo simply has nothing to automate. That distinction is
recorded as the `*` on the map and the § in the README tables, not as a worse colour.

The bar for counting a route without an endpoint is **whole state** and **actually
established** — a product someone can point at, covering all of it, not a "contact us" page
and a hope. Hessen clears it, and so do the three states that sell their point cloud. What
Hessen has that they do not is the price: nothing. That is the whole of the difference between
`*` and `€`, and it is worth keeping visible, because "free if you post a disk" and "190 € je
Datensatz" are not the same offer even when both arrive by post.

This bar used to include **free**, which kept ST orange and BW, NI and ST off the coverage
map's green. That was the wrong cut: it made the maps answer "what can we have for nothing"
while their legends claimed to answer "what can we have". Price is a caveat on a route, not
the absence of one, so it moved from the colour to the label. See
[The states that sell it](#the-states-that-sell-it).

What is *not* claimed here: that no online endpoint exists. HVBG answered a request for the
point cloud with the postal arrangement rather than a link, which is a strong signal — but it
is one email, not an audit of `gds.hessen.de`. If a bulk endpoint does turn up, that is a
correction worth making, in the same spirit as the five in
[Bremen: the last unproven verdict](#bremen-the-last-unproven-verdict).

Practical notes before you post anything:

- **Size the disk generously.** Hessen is 21,116 km². This repo's measured neighbours put a
  statewide point cloud at 5.18 TB for Rheinland-Pfalz (19,858 km²) and ~1.52 TB per vintage
  for Thüringen (16,202 km²) — see [Volumes](#volumes-for-the-scripted-states). That is a wide
  band, and Hessen's own figure was not quoted, so an 8 TB disk is the safe order of magnitude
  rather than a verified requirement.
- **Agree the scope in writing first** — vintages, classification, tiling and format were not
  established in the exchange, and a disk is an expensive way to discover you got the wrong
  one.
- **DGM1 does not need any of this.** It is free in the `gds.hessen.de` storefront, ordered
  through a zero-price cart rather than posted — a separate, online, still-unscripted route.
  That is why HE's DTM column is also ✅ §: obtainable in full, by hand.

Nothing here is wired into `download_all.sh`, and nothing can be — `ONLY=he ./download_all.sh`
covers HE's cadastre and stops there. If a disk arrives, its contents join the tree the same
way any other state's `las` output does; the [per-state notes](#per-state-lidar-notes) below
cover the layout the other downloaders write.

## Two UTM zones

This matters when mosaicking across state borders:

- **EPSG:25832** (UTM 32N): BW, BY, HE, NI, NW, RP, SH, SL, ST, TH — and HH.
- **EPSG:25833** (UTM 33N): BB, BE, MV, SN.

Within a zone all states share the same grid origin (SW corner snapped to whole km), so tiles
line up across borders. Across zones they do not — reproject first.

Tile sizes differ too: 1 km for RP/BY/NW/NI/BB and MV-`las`, 2 km for SN/BE/BW and MV-`dgm1`.

---

# 3. ALKIS / cadastre availability

**ALKIS** (*Amtliches Liegenschaftskatasterinformationssystem*) is the official cadastre:
parcels (*Flurstücke*), building footprints (*Gebäude*), actual land use (*Tatsächliche
Nutzung*), addresses. Each state runs its own, so each publishes it differently — or not at
all. Owner names (*Eigentümerangaben*) are **never** open data anywhere; what states release
is the *ohne Eigentümer* (oE) variant.

<img src="alkis_map.svg" alt="Map of the 16 Bundesländer coloured by cadastre openness: green for the 14 states publishing vector ALKIS ohne Eigentümer in bulk, orange for BY and RP which offer no bulk vector parcels" width="560">

Fourteen states are green. The two orange ones reach that colour from opposite directions,
and neither is a plain delivery bug. **Bayern** does not publish vector parcels at all: the
Bayerisches VermKatG carves Flurstücksinformationen out of the open-data regime, so what is
free is the raster *Parzellarkarte* and the download works fine — parcel geometry simply is
not in what arrives. **Rheinland-Pfalz** does publish vector ALKIS ohne Eigentümer, free, as
the *Bestandsdatenauszug Liegenschaftskataster ohne Eigentümerangaben* — but only as a
per-order "Live-Produkt" generated in a GeoShop cart, and its INSPIRE OGC API Features
service is metadata-marked `Gebührenpflichtig`, points at an internal host that does not
resolve from outside, and answers every feature query with an empty collection (checked
2026-08-04). Same cell, different cause: BY's is statutory and RP's is delivery, which makes
RP the likelier of the two to open. **No state is fully closed.**

The per-state table — openness, access route, format, unit and licence — is
[README.md §2](README.md#2-alkis--cadastre-availability). There, **"login"** means a user
account is needed to get the data and **"anonymous"** means plain HTTP with no credentials.

## What each state gives you

What `download_alkis.sh` actually fetches, per state:

| ID | State | Datasets (default first) | Unit | Statewide size |
|----|-------|--------------------------|------|----------------|
| `bw` | Baden-Württemberg | `nas`, `shape` | Gemarkung (~3,380) | ~23 GB |
| `by` | Bayern | `tn`, `hausumringe`, `verwaltung` | statewide / Bezirk | ~5.4 GB (`tn`) |
| `be` | Berlin | `flurstuecke`, `gebaeude` | WFS pages | ~403k parcels |
| `bb` | Brandenburg | `nas`, `shape` | Landkreis (18) | ~4 GB |
| `hb` | Bremen | `flurstuecke` | one GetFeature | small |
| `hh` | Hamburg | `gml` | statewide, quarterly | ~0.46 GB |
| `he` | Hessen | `flurstuecke`, `zoning` | OGC API pages | ~5.0 M parcels |
| `mv` | Mecklenburg-Vorpommern | `nas` | Gemeinde (724 → 1,448 files) | — |
| `ni` | Niedersachsen | `flurstueck`, `gebaeude` | WFS pages | ~6.3 M parcels |
| `nw` | Nordrhein-Westfalen | `nas`, `gpkg` | Kreis (53) | ~25 GB |
| `rp` | Rheinland-Pfalz | `lika`, `hu` | `lika` 1 km tile (20,511) / `hu` statewide (1 zip) | ~31 GB / 334 MB |
| `sl` | Saarland | `nas`, `shape` | Landkreis (7) | ~2.1 GB |
| `sn` | Sachsen | `nas` | statewide | one ZIP |
| `sh` | Schleswig-Holstein | `geojson` | statewide index | ~243 MB (index only) |
| `th` | Thüringen | `shape`, `nas` | Flur (~16,500) | ~1.2 GB |
| `st` | Sachsen-Anhalt | `flurstueck`, `gebaeude`, `nutzung` | WFS pages | ~2.7 M parcels |

`bw`, `by` and `rp` come with a caveat printed at run time — Bayern publishes no open vector
parcels, and RP publishes them only to order, so what `download_alkis.sh rp` fetches is the
rasterised cadastral map.

## The two content gaps

**No state requires a login for the data listed above.** Fourteen states publish vector
cadastre openly; the two exceptions are content gaps at the source, not access barriers:

- **Bayern** — the *ALKIS-Parzellarkarte* is published as **raster only** (WMS/WMTS and
  GeoTIFF via Metalink) — it *is* open and it *is* downloadable, see
  [Bayern's Parzellarkarte](#bayerns-parzellarkarte-the-cadastre-as-a-picture); what is
  missing is vector. Open vector products are limited to *Tatsächliche Nutzung*
  (statewide GeoPackage, ~5 GB), *Landnutzung* (statewide GeoPackage, 5.7 GB — see below),
  *Hausumringe* (Shape per Regierungsbezirk) and *Verwaltungsgebiete*. Vector parcel geometry
  is sold through GeodatenOnline, which does require an account.

  **`landnutzung.gpkg` is not parcel data**, despite being a large statewide ALKIS-derived
  vector GeoPackage — worth stating plainly, because it is the most parcel-looking thing
  Bayern publishes openly. Verified against the live file 2026-07-31 (read over HTTP range
  requests, no download):

  ```bash
  CPL_VSIL_CURL_ALLOWED_EXTENSIONS=.gpkg \
    ogrinfo -so /vsicurl/https://geodaten.bayern.de/odd/m/3/daten/ln/landnutzung.gpkg
  ```

  It holds **21 layers, one per land-use category** — `ln_wohnnutzung`, `ln_landwirtschaft`,
  `ln_forstwirtschaft`, `ln_bahnverkehr`, `ln_abbau`, `ln_sportanlage`, … — in EPSG:25832.
  The attributes are `uuid`, `beginnt`, `anlass`, `name`, `zeitlichkeit`, `zustand`,
  `datumderletztenueberpruefung`, `ergebnisderueberpruefung`, `istweiterenutzung`,
  `mappingannahme`, `quellobjektid`. **There is no `flurstueckskennzeichen`, no
  Gemarkung/Flur/Zähler/Nenner, no parcel identifier of any kind**, and the polygons are
  use-areas that merge across parcel boundaries rather than following them. It is the same
  family as `by-tn` and fills neither `plots` nor `structures`. Neither `ln` nor `tn` is a
  substitute for the Flurstücke Bayern keeps behind GeodatenOnline.
- **Rheinland-Pfalz** — publishes the **rasterised** Liegenschaftskarte (`lika`, ~20,500
  GeoTIFF tiles, ~31 GB) and *Hausumringe* in bulk, and that is what this repo fetches. It
  also publishes the **vector** ALKIS ohne Eigentümer, free — the *Bestandsdatenauszug
  Liegenschaftskataster ohne Eigentümerangaben* at
  [`geoshop.rlp.de/opendata-alkis.html`](https://geoshop.rlp.de/opendata-alkis.html) — but as
  a **"Shop-/Live-Produkt"**: an extract generated to order in a cart workflow with AGB
  acceptance, not a static tile listing. RP's own wording is *"Individuelle Erzeugung eines
  Bestandsdatenauszugs, welcher nach Ihren Angaben von unseren Diensten neu produziert wird"*,
  which is the opposite of a bulk endpoint.

  The INSPIRE service looks like the way round that and is not. `spatial-objects/584` is a
  live OGC API Features endpoint listing `cp:CadastralParcel`, and it answers `/collections`
  anonymously with HTTP 200 — which is easy to mistake for a working route. Checked
  2026-08-04: its service metadata declares `"license": "Nutzungsbedingungen:Gebührenpflichtig"`,
  its `accessUrl` is `https://geo5balance.vermkv.rlp/` — an internal host that does not
  resolve from the public internet — and **every** feature query, with or without a `bbox`,
  returns an empty `FeatureCollection`. So the collection listing is real and the data behind
  it is not reachable. Parcel geometry otherwise stays per-query through the Flurstückssuche
  WFS.
Both are closed by paying. RP sits inside **FS-DE** (15 states, ~54 M parcels, *ab* €27,000
from the ZSHH), Bayern only in **FS-BY** (€56,000 from the LDBV); neither has a download
endpoint — FS-DE arrives on a returnable USB drive. For **RP** there is a much cheaper third
route: the CISS-Shop sells RP vector ALKIS for a drawn polygon at official state fees, as
DXF/Shape/NAS. Costs, licences, the free FS-DE test Shapefile and the wider commercial market
(geomer, infas 360, Nexiga, CISS TDI, per-object retail):
[`cadastre-products.md`](cadastre-products.md).

### Bayern's Parzellarkarte: the cadastre as a picture

Bayern's gap is a *vector* gap, not a total one. The **ALKIS-Parzellarkarte** is open data
under **CC BY 4.0**, and it is the only open product that shows where Bavaria's parcels are.
`download_by_parzellarkarte.sh` fetches it. Verified live 2026-07-31.

It carries Flurkarte content — parcel boundaries, buildings, Lagebezeichnungen, TN objects —
but per LDBV's own product text **`keine Flurstücksnummern und keine Grenzzeichen`**, with
every boundary drawn as one uniform solid line. The numbers legible on the map are *house*
numbers, not parcel numbers. It is raster: no geometry, no identifiers, no attributes, so it
fills neither `plots` nor `structures`.

The bulk route is the **same `poly2metalink` service `download_by_lidar.sh` uses for `las`**,
but this product is capped at **10 km² per request**, not 2000, so the sweep steps in 3×3 km
cells. The cap is read from the service at run time rather than hard-coded, so an upstream
change fails loudly instead of as a wall of rejected polygons:

```
https://geoservices.bayern.de/services/poly2metalink/datasets/parzellarkarte
→ {"maxPointsPerGeom":20000,"areaLimitQkm":"10","maxTilesToZip":4,"type":"wms","imageFormat":"tiff"}
```

`type: "wms"` is the part that matters. Each returned tile is a WMS `GetMap` call rendered
**on demand** — 11811 × 11811 px at 300 DPI, ~8.5 cm/px, LZW RGB GeoTIFF in EPSG:25832,
**~22 MB and ~20 s of server time each**, in town and open country alike (LZW on 139
megapixels lands in the same place either way). There are no sizes and no checksums in the
metalink, so downloads are resumable but not hash-verified, and `JOBS` defaults to 4 rather
than the 8 the other downloaders use.

That per-tile cost is why **a statewide run is refused unless you pass `ALLOW_STATEWIDE=1`**:
Bavaria's ~70,550 km² would be ~1.5 TB and roughly 400 hours of rendering, requested through
~7,800 POSTs to a live service. Pass a `BBOX` instead.

```bash
# the repo's Bayern sample square — Garmisch-Partenkirchen, 25 tiles, ~0.5 GB
BBOX="656,5260,661,5265" ./download_by_parzellarkarte.sh ../germany-data/by_parzellarkarte
DRY_RUN=1 BBOX="690,5334,693,5337" ./download_by_parzellarkarte.sh   # plan only
```

Two other routes exist for the same product, both free: a
[WMS](https://geoservices.bayern.de/od/wms/alkis/v1/parzellarkarte) (PNG/JPEG, six CRS, daily)
and a [WMTS](https://geoservices.bayern.de/od/wmts/geobasis/v1/1.0.0/WMTSCapabilities.xml),
which is tile-cached and therefore the cheaper option for wide-area use.

The product catalogue that documents all three is machine-readable, and is how the endpoints
above were found rather than guessed — worth knowing, because the `OpenDataDetail.html` pages
are JS-driven and contain nothing useful when fetched directly:
`https://geodaten.bayern.de/opengeodata/json/opengeodata_datensaetze.json` (124 records
across 35 products).

**Sachsen-Anhalt used to be listed here as a third gap.** It is not one: LVermGeo publishes
`ST_LVermGeo_ALKIS_WFS_OpenData`, an anonymous WFS 2.0 carrying `ave:Flurstueck` (~2.7 M),
`ave:GebaeudeBauwerk` (~1.7 M) and `ave:Nutzung` under DL-DE/BY 2.0. It is the
**ALKIS-vereinfacht 2.0** schema rather than full NAS — geometry plus the cadastral keys
(`flstkennz`, `gemarkung`, `flur`, `flaeche`, `lagebeztxt`), no Punktinformationen — which is
the same trade NW's `gru_vereinfacht` and SH's GeoJSON make; see
[NAS — the exchange format](#nas--the-exchange-format). Verified 2026-07-29.

Two portals do sit behind a login, but neither is the only route to their state's data:

- **Hessen** — the *Downloadcenter* on `gds.hessen.de` requires a free customer account for
  packaged files. The INSPIRE **OGC API Features** endpoint carries the same ALKIS oE
  content anonymously, so the downloader uses that instead.
- **Saarland** — `shop.lvgl.saarland.de` is a webshop with accounts, but LVGL also mirrors
  the statewide open datasets on a **password-less public Nextcloud share**, which is what
  the downloader reads. That same share also holds the state's LiDAR, orthophotos and LoD2
  building models — see [Saarland](#saarland-the-share-the-repo-was-already-reading).

Five states publish **services only** — no file packages exist, so a bulk copy means paging
a WFS or OGC API (`download_alkis.sh` does this automatically): BE, HB, NI, HE, ST.

All ALKIS data above is in **ETRS89 / UTM** (EPSG:25832, EPSG:25833 in the east).

---

# The state ID

**The ID is the ISO 3166-2 code without the `DE-` prefix.** It is the only state identifier
this repo uses, and it is the same string everywhere — every table in these two documents, all
three generated maps, and all machine-readable data:

| Where | Form | Example |
|-------|------|---------|
| Tables and prose in these documents | upper case | `NW`, `RP` |
| Map labels on `coverage_map.svg` / `alkis_map.svg` | upper case | `NW`, `RP` |
| `bundeslaender.geojson` — the `key` property | lower case | `"key": "nw"` |
| `sample_squares.tsv` — first column | lower case | `nw` |
| `download_alkis.sh <id>` | lower case | `./download_alkis.sh nw` |
| `STATES=` in `download_samples.sh` | lower case | `STATES="nw rp"` |
| Output trees | lower case | `./alkis/nw`, `./samples/nw` |

**Two filenames predate the rule and do not follow it:** `download_nrw_lidar.sh` and
`download_rlp_lidar.sh` use `nrw`/`rlp` where the ID is `nw`/`rp`, as do the LiDAR output
directories (`rlp_lidar/`) and the converter's output tree (`dtm/de/rlp/`, `point-cloud/de/rlp/`).
`download_samples.sh` bridges the gap in its `script_for()` case, which is why `STATES="nw"`
finds `download_nrw_lidar.sh`. Renaming them would break every existing invocation and output
path, so they stay as they are — but nothing new should use `nrw` or `rlp`.

# How the twelve LiDAR downloaders are built

There is no common German standard, so each script reverse-engineers its state's own
publishing mechanism. What they share: **the tile list is never cached** — it is rebuilt from
the authoritative source on every run — and every transfer is parallel and resumable. Ten go
through `aria2c`; ST and SL are the exceptions, because their tiles live inside big ZIPs and
they range-read them themselves.

| Mechanism | States | Integrity |
|-----------|--------|-----------|
| Metalink-4 manifest with per-tile SHA-256 | RP, BY (`dgm1`) | **hash-verified** |
| `index.json` product inventory | NW | size only |
| Apache directory index | BB | size only |
| INSPIRE Atom feed | BE, MV, TH | size only |
| STAC API | NI | size only |
| Nextcloud public WebDAV share + inventory embedded in the portal's JS | SN | size only |
| Mapbox vector-tile download grid | BW | size only |
| Polygon-to-Metalink service, swept in 1600 km² blocks | BY (`las`) | size only |
| ZIP central directory read over HTTP ranges, tiles inflated individually | ST, SL | size only |

Only RP and Bayern's `dgm1` publish checksums. Everywhere else `--continue` resumes and
sizes are checked, but content is not hash-verified.

All twelve share the same CLI:

```bash
./download_<id>_lidar.sh [dgm1|las|both] [output_dir]

DRY_RUN=1 ./download_xx_lidar.sh las      # print the tile count + size, download nothing
JOBS=12 CONN=4 ./download_xx_lidar.sh dgm1
BBOX="minE,minN,maxE,maxN" ./…            # UTM km subset (NI takes WGS84 degrees instead)
```

Three take an extra selector, because their source publishes more than one of the same
thing: `AREAS=` picks ST's sample areas, `KREISE=` picks SL's district archives, and
`VINTAGE=` picks one of TH's three flight campaigns (newest by default). TH also offers a
third dataset, `dom1`, which no other state does.

> **Mind the CRS.** BB, BE, MV and SN are UTM **zone 33** (EPSG:25833); the rest are zone 32
> (EPSG:25832). Tiles from the two groups do not share a grid, so a `BBOX` is only meaningful
> within one zone.

> **Mind the disk.** `las` for NW alone is 3.5 TB and for RP 5.2 TB. Always `DRY_RUN=1` first.

# Per-state LiDAR notes

## Rheinland-Pfalz (RP)

Published by the **Landesamt für Vermessung und Geobasisinformation Rheinland-Pfalz (LVermGeo)**.

| Key   | Product                                  | Format   | Tiles   | Statewide size |
|-------|------------------------------------------|----------|---------|----------------|
| `las` | Classified point cloud, surface+terrain (LPO+LPG) | `.laz` | ~21,207 | **~5.18 TB**   |
| `dgm1`| DGM1 — bare-earth terrain model, 1 m grid | GeoTIFF | ~21,082 | **~32.8 GB**   |

- **Tiling:** 1 km × 1 km, SW (lower-left) corner snapped to whole km.
- **CRS:** ETRS89 / UTM Zone 32 — **EPSG:25832** (LAZ vertical may be compound EPSG:5555).
- **Portal:** <https://geoshop.rlp.de> · files served from `https://geobasis-rlp.de`.

**License — attribution required.** *Datenlizenz Deutschland – Namensnennung 2.0
(DL-DE/BY 2.0)* — *not* DL-DE/Zero. Free, no access restrictions, but you **must** credit:

```
©GeoBasis-DE / LVermGeoRP <year>, dl-de/by-2-0, www.lvermgeo.rlp.de
```

**How it works.** The state surveying office publishes official **Metalink-4 (`.meta4`)**
manifests listing every tile with its size and **SHA-256** hash. `aria2c` reads these
natively, giving parallel, **resumable**, integrity-checked downloads from a single command.

Statewide manifests (`07` = RP state prefix):
- LAS:  `https://geobasis-rlp.de/data/las/current/meta4/las_las_07.meta4`
- DGM1: `https://geobasis-rlp.de/data/dgm1/current/meta4/dgm1_tif_07.meta4`

Sub-state manifests exist if you want less than the whole state — append the
district / Verbandsgemeinde / Gemeinde key: `..._07{kreissch|vgnr|gmdesch}.meta4`.

```bash
brew install aria2          # or: apt install aria2

./download_rlp_lidar.sh dgm1                 # ~33 GB  -> ./rlp_lidar/dgm1
./download_rlp_lidar.sh las  /mnt/big/rlp    # ~5.2 TB -> mind your disk & bandwidth!
./download_rlp_lidar.sh both

DRY_RUN=1 ./download_rlp_lidar.sh las        # print tile count + size, download nothing
JOBS=12 CONN=4 ./download_rlp_lidar.sh dgm1  # tune parallelism
```

## Baden-Württemberg (BW)

Published by the **Landesamt für Geoinformation und Landentwicklung Baden-Württemberg (LGL)**.

| Key    | Product                                   | Format             | Tiles  | Statewide size |
|--------|-------------------------------------------|--------------------|--------|----------------|
| `dgm1` | DGM1 — bare-earth terrain model, 1 m grid | ASCII **XYZ** in `.zip` | 9,370 zips | **~125 GB** |

- **Tiling:** downloads are **2 km × 2 km ZIPs**, each holding four 1 km × 1 km tiles
  (`*.xyz` + a `*.csv` with acquisition date, accuracy and CRS) — so ~37,480 one-km tiles.
- **CRS:** ETRS89 / UTM Zone 32 — **EPSG:25832**; heights DHHN2016 (compound EPSG:7837).
  The XYZ files themselves carry no CRS; the converter stamps EPSG:25832 on.
- **The point cloud is not on the portal — it is on the order form.** The `3DM` /
  "Laserscandaten 2000–2005" entry is flagged inactive and every `3dm_*.zip` URL 404s, and
  that dead product was read here as "BW has no point cloud". It is not the current one. LGL
  keeps the laser scan under *Laserscandaten*, in three campaigns, and the middle one covers
  the whole state — see below. `download_bw_lidar.sh las` still exits: there is no endpoint.
- **Portal:** <https://opengeodata.lgl-bw.de>.

Other products sit on the same 2 km grid and the same URL scheme (`dom1`, `ndom1`, `dgm025`,
`dom5`, `dop20`, `lod1`/`lod2`) — downloading one is a single line in `product_type()`, but
the converter only knows the zipped-XYZ layout `dgm1` uses.

**License — attribution required.** *DL-DE/BY 2.0* — you must credit:

```
Datenquelle: LGL, www.lgl-bw.de  ·  dl-de/by-2-0
```

**How it works.** BW publishes **no manifest**. The portal draws its 2 km download grid as
**Mapbox vector tiles**, and each grid cell carries a JSON blob listing that cell's per-product
download URL. The script fetches the four zoom-7 vector tiles that cover the state, decodes
them with a small stdlib-only MVT reader, and writes an `aria2c` input file. The tile list is
therefore always current rather than hard-coded — and `BBOX` can subset it without extra
requests.

Unlike RP's Metalink, **no checksums are published**: downloads are parallel and resumable
(`--continue`), but only size-checked, not hash-verified.

```bash
./download_bw_lidar.sh dgm1                  # ~125 GB -> ./bw_lidar/dgm1
./download_bw_lidar.sh dgm1 /mnt/big/bw

DRY_RUN=1 ./download_bw_lidar.sh dgm1        # tile count + sampled size estimate, no download
BBOX="500,5400,520,5420" ./download_bw_lidar.sh dgm1   # subset by UTM32 km (minE,minN,maxE,maxN)
JOBS=12 CONN=4 ./download_bw_lidar.sh dgm1   # tune parallelism
```

Grid cells are named `<easting_km>-<northing_km>` of the SW corner, with **odd** eastings and
**even** northings (e.g. `517-5424`) — `BBOX` is inclusive on both ends.

### The point cloud: open data, sold by the hour

BW's laser scan exists, covers the state, and is *licensed open data*. What it does not have
is a download — you email LGL an area and pay for the work of cutting it. Three campaigns,
under **Laserscandaten** rather than the dead `3DM` entry:

| | Flown | Coverage | Density | Status |
|---|---|---|---|---|
| `ALS_1` | 2000–2005 | statewide | 0.8 pts/m² | **historic** — "wird nicht mehr fortgeführt" |
| `ALS_2` | 2016–2021 | **statewide** | ≥ 8 pts/m² | the one to ask for |
| `ALS_3` | 2022–~2029 | in progress, flown areas available since 2023 | ≥ 8 pts/m² | the recapture |

Delivered as **LAZ**, LAS or XYZ-ASCII, classified into seven classes, heights NHN
(DHHN2016, Höhenstatus 170). Ordering is an email to `geodaten@lgl.bwl.de` (or 0711 95980-200)
naming the extent — ETRS89/UTM coordinates, a shapefile, or tile names off the Geoportal.

**What it costs is handling, not rights:** *"Die Laserscandaten ALS_3 sind Open Data … Hierfür
fällt ein aufwandabhängiges Service-Entgelt an. Das Mindestentgelt beträgt 60,- € (zzgl.
Ust.)."* The same applies to `ALS_2`. So BW is the mildest of the three `€` states — the data
is open, the invoice is for the labour — and it is why the maps show BW green with a `€`
rather than red. Checked 2026-08-05:
[Laserscandaten](https://www.lgl-bw.de/Produkte/3D-Produkte/Laserscandaten/) ·
[ALS_2](https://www.lgl-bw.de/Produkte/3D-Produkte/Laserscandaten/ALS_2/index.html) ·
[ALS_3](https://www.lgl-bw.de/Produkte/3D-Produkte/Laserscandaten/ALS_3/index.html).

The free DGM1 above is derived from these scans, so if bare earth is the goal the download
already covers it.

## Bayern (BY)

Published by the **Landesamt für Digitalisierung, Breitband und Vermessung (LDBV)**.
License **DL-DE/BY 2.0** — credit `Datenquelle: Bayerische Vermessungsverwaltung –
www.geodaten.bayern.de, dl-de/by-2-0`. EPSG:25832, 1 km tiles.

The two products are published completely differently:

- **`dgm1`** — a statewide Metalink-4 manifest, 71,979 tiles / 217 GB, with **SHA-256 per
  tile and two mirrors** (`download1/2.bayernwolke.de`). Handled exactly like RP.
- **`las`** — *no* statewide manifest exists. The point cloud is only reachable through the
  **`poly2metalink` polygon service**, hard-capped at **2000 km² per request**. The script
  sweeps Bavaria in 40×40 km (1600 km²) EWKT polygons, POSTs each, and merges the returned
  metalinks. Those carry URLs only — no sizes, no hashes.

```bash
./download_by_lidar.sh dgm1                            # 217 GB -> ./by_lidar/dgm1
DRY_RUN=1 BBOX="680,5320,760,5400" ./download_by_lidar.sh las    # 6,400 tiles in that box
```

Tiles are addressable directly too: `https://geodaten.bayern.de/odd_data/laser/690_5331.laz`.

## Nordrhein-Westfalen (NW)

Published by **Geobasis NRW**. License **DL-DE/Zero 2.0** — no attribution obligation.
EPSG:25832, 1 km tiles, 35,860 tiles per product.

NW is the cleanest source of the twelve: each product directory carries an `index.json`
listing every file with its byte size and timestamp.

- `las` = `3dm_l_las` (3D-Messdaten Laserscanning, `.laz`) — **3.49 TB**
- `dgm1` = `dgm1_tiff` (GeoTIFF) — **78.8 GB**

```bash
./download_nrw_lidar.sh dgm1                 # 79 GB  -> ./nrw_lidar/dgm1
./download_nrw_lidar.sh las /mnt/big/nrw     # 3.5 TB
```

Per-tile direct URL:
`https://www.opengeodata.nrw.de/produkte/geobasis/hm/dgm1_tiff/dgm1_tiff/dgm1_32_280_5652_1_nw_2022.tif`

## Brandenburg (BB)

Published by **LGB**. License **DL-DE/BY 2.0** — credit `© GeoBasis-DE/LGB <year>,
dl-de/by-2-0`. **EPSG:25833**, 1 km tiles for both products.

LGB serves both products from a plain indexed directory, so the script just parses the
Apache index (which also carries rounded sizes).

- `las` = `als/laz/` — 13,086 tiles, ~100 MB each, **~1.35 TB**. Coverage is **partial** and
  rolls out campaign by campaign; it is much smaller than the complete `dgm1` grid.
- `dgm1` = `dgm/tif/` — 31,291 tiles, ~1.3 MB each, **~36 GB**. (`dgm/xyz/` holds the same
  grid as ASCII.)

Tile key is `33<E_km>-<N_km>`, e.g. `dgm_33250-5888.zip`.

## Sachsen (SN)

Published by **GeoSN**. EPSG:25833, **2 km** tiles, 4,981 tiles per product.

Sachsen publishes neither a manifest nor a directory index. The authoritative inventory is
embedded in the **Batch Download page as JavaScript**: a per-municipality, run-length encoded
list of 1 km grid cells plus a per-product Nextcloud share id. The script decodes that,
aggregates to the 2 km packaging, and subtracts the product's `computed_not_existing` holes
(8 for `dgm1`).

Files come from a **Nextcloud public WebDAV share**. Anonymous `GET` works; `PROPFIND`
(listing) returns 401 — which is exactly why the inventory has to come from the portal page.

```
https://geocloud.landesvermessung.sachsen.de/public.php/dav/files/<share>/dgm1_33334_5652_2_sn_tiff.zip
```

- `las` = `LSC` (Laserscandaten, `.laz` in a zip)
- `dgm1` = `DGM1_TIFF_2km` (GeoTIFF in a zip)

## Niedersachsen (NI)

Published by **LGLN**. License **CC BY 4.0** for the open `dgm1` this script fetches — credit
`© LGLN <year>, CC BY 4.0`. EPSG:25832, 1 km tiles. (The priced point cloud below is *not* CC
BY; see [The point cloud is for sale, not absent](#the-point-cloud-is-for-sale-not-absent).)

Two things make NI unusual:

- Tiles are **already Cloud Optimized GeoTIFFs**, served from IBM Cloud Object Storage.
  `convert_to_cloud_optimized.sh` is *not* needed — the download is the finished product.
- The **STAC catalogue is multi-temporal**: ~70,000 items cover ~48,000 km², because a km²
  that has been reflown appears once per campaign (`…_ni_2016` *and* `…_ni_2025`). The script
  therefore defaults to **`LATEST=1`**, keeping the newest campaign per tile — 49,708 tiles,
  dropping 20,577 older items. Set `LATEST=0` to mirror the whole archive.

`BBOX` here is **WGS84 degrees** (`minLon,minLat,maxLon,maxLat`), because it is passed
straight to the STAC API — unlike every other script, which takes UTM kilometres.

**No *open* point cloud:** the STAC catalogue exposes only `dgm1`, and
`./download_ni_lidar.sh las` says so and exits 3. The scan itself exists — see below.

### The point cloud is for sale, not absent

This is why NI is green with a `€` rather than red: the scan can be had for the whole state,
just never for free and never from a URL.

The open DGM1 is a derived product: LGLN flies an airborne laser scan, classifies it, and
publishes the 1 m raster it computes from that. The scan itself is a separate, **chargeable**
product — the *Laserscan-Punktwolke*, one component of LGLN's **3D-Messdaten** alongside the
Dense-Image-Matching cloud and the (still unfinished) 3D-Strukturinformationen.

| | Laserscan-Punktwolke (3D-Messdaten) |
|---|---|
| Format · unit | LAZ 1.2, **1 km² tiles** — the same grid the free DGM1 uses |
| Density | ≥ 4 points/m² (last/only return) |
| Accuracy | ≤ 0.30 m in position, ≤ 0.15 m in height (95%, 2σ) |
| Reference systems | ETRS89/UTM 32 (EPSG:25832), DHHN2016 heights, GCG2016 |
| Classification | AdV classes 1, 2, 7, 8, 9, 12, 20, 24 — ground, non-ground, outliers, measured *and* synthetic water points, overlap, sub-ground (cellars, ramps) |
| Delivery | download, or a data carrier LGLN posts (SD card, USB stick, hard disk) by volume |
| Price | under the **KOVerm** fee schedule — no published per-km² rate, quote on request |
| Terms | LGLN **AGNB** (`lgln.de/agnb`) — *not* the CC BY 4.0 the DGM1 carries |
| Ask | `geoService-3D@lgln.niedersachsen.de` · sales `vertrieb-lgn@lgln.niedersachsen.de`, 0511 64609-333 |

Product and format description: [Laserscan-Punktwolke (LGLN, Stand
2024-09-04)](https://www.lgln.niedersachsen.de/download/129180/Produkt-_und_Formatbeschreibung_Laserscan-Punktwolke.pdf)
· [3D-Messdaten](https://www.lgln.niedersachsen.de/startseite/geodaten_karten/3d_geobasisdaten/3d_messdaten/3d-messdaten-142870.html).
Checked 2026-08-04.

**There is nothing for `download_ni_lidar.sh` to do here**: an invoiced, mail-order delivery
has no URL to drive, so `las` exits 3 and names the address to write to. If you do buy the
tiles, they land on the same 1 km grid as the `dgm1` output and drop straight into the same
tree. NI is one of three states in this position — see
[The states that sell it](#the-states-that-sell-it).

Worth knowing before you ask for a quote: this same scan is what LGLN rasterises into the DGM1
you can already download, and into the sibling `dom` surface model. If bare earth or a surface
is what you need, the open raster products carry it. Buying the cloud buys the returns
themselves — the classification, the echoes, the sub-ground points — not better terrain.

## Berlin (BE)

Published by **GDI Berlin**. License **DL-DE/Zero 2.0** — no attribution obligation.
EPSG:25833. Both products are INSPIRE **Atom** feeds.

- `dgm1` — ATKIS DGM, **2 km** tiles, `DGM1_<E_km>_<N_km>.zip`, 297 tiles, ~0.2 GB total.
- `las` — Airborne Laserscanning, packaged as **9 whole-city-region ZIPs** (`Mitte.zip`,
  `Nord.zip`, `Ost.zip`, …), *not* a tile grid. `BBOX` cannot subset it and is ignored.

Smallest state in the set — the entire DGM1 fits in a couple of hundred megabytes, which
makes Berlin a good smoke test for the toolchain.

## Mecklenburg-Vorpommern (MV)

Published by **LAiV M-V**. Attribution **required** — the feed's `<rights>` demands a visible
source note `© GeoBasis-DE/M-V <year>`. EPSG:25833. INSPIRE Atom feeds.

- `las` — ALS point cloud, **1 km** tiles, 25,466 tiles.
- `dgm1` — **2 km** tiles, 6,407 tiles. Note the two products use *different* tile sizes.

**The DGM feed is a trap.** It offers each of the 6,407 tiles in six variants, and only one
is elevation data:

| Suffix | What it actually is |
|--------|---------------------|
| `_gtiff.tif` | **Float32 elevation — the DTM.** What the script takes. |
| `_mix.tif` | 8-bit RGB rendering (a picture of the terrain, not heights) |
| `_zcode.tif` | 8-bit palette height-colour image |
| `_schum_NW.tif` | hillshade |
| `_xyz.zip` | ASCII XYZ of the same grid |
| `_isoli.zip` | derived contour lines |

Taking the feed at face value yields 38,442 "tiles" — six copies of the state, mostly not
elevation. Override with `VARIANT=_xyz.zip` etc. if you want a different one. The dataset
UUID is discovered from the service feed rather than hard-coded.

## Thüringen (TH)

Published by **TLBG** through GDI-Th. DL-DE/BY 2.0, attribution `© GDI-Th, Freistaat
Thüringen`. EPSG:25832. INSPIRE Atom feeds, like BE and MV — three of them, one per product,
each carrying three flight campaigns on one 1 km grid. `las`, `dgm1` and `dom1`; `VINTAGE=`
picks the campaign, newest by default. Written up in full under
[Thüringen: three Atom feeds behind a portal](#thüringen-three-atom-feeds-behind-a-portal),
including the two traps — the oldest campaign is a 2 m grid, and every terrain zip ships the
grid twice (GeoTIFF plus a ten-times-larger ASCII `.xyz`).

## Saarland (SL)

Published by **LVGL Saarland**. DL-DE/BY 2.0, attribution `© GeoBasis DE/LVGL-SL <year>`.
EPSG:25832. A password-less Nextcloud share, one ZIP per Landkreis, read over HTTP ranges.
`las`, `dgm1` and `dom1`; `FORMAT=tif|laz` picks the encoding for the two models. Written up
under [Saarland: the share the repo was already reading](#saarland-the-share-the-repo-was-already-reading).

## Schleswig-Holstein (SH)

Published by **LVermGeo SH**. **CC BY 4.0**, attribution `©GeoBasis-DE/LVermGeo SH/CC BY 4.0`.
EPSG:25832. A static GeoJSON index of 18,685 tiles, each with a direct link; `dgm1` only, as
**ASCII XYZ**, ~515 GB. Written up under
[Schleswig-Holstein: the index was never empty](#schleswig-holstein-the-index-was-never-empty),
including the three traps — no `Range` and no `Content-Length`, HTML stapled onto every tile,
and dead index entries served as HTTP 200.

## Hamburg (HH)

Published by **LGV Hamburg**. DL-DE/BY 2.0. EPSG:25832. Archives are anonymous and honour
`Range`; the file list comes from the Transparenzportal CKAN API because directory listings
403. `dgm1` (9 vintages) and `dom1` (the image-derived bDOM). Written up under
[Hamburg: the listing 403s, the files never did](#hamburg-the-listing-403s-the-files-never-did),
including the catalogue calling the newest GeoTIFF edition "PNG".

## Sachsen-Anhalt (ST)

Published by **LVermGeo ST**. The only downloader here that does not cover its state: what is
open is two sample areas inside two big ZIPs, read over HTTP ranges. See
[Sachsen-Anhalt: samples, not a state](#sachsen-anhalt-samples-not-a-state).

# ALKIS — how the downloader works

`download_alkis.sh` pulls ALKIS for any German state that publishes it openly. **No state
requires a login for what this script downloads.**

```bash
brew install aria2          # or: apt install aria2

./download_alkis.sh --list                   # every state ID + its datasets
./download_alkis.sh nw                       # NW, NAS, ~25 GB -> ./alkis/nw
./download_alkis.sh nw gpkg                  # NW, simplified GeoPackage (much smaller)
./download_alkis.sh bw shape /mnt/big        # -> /mnt/big/bw

DRY_RUN=1 ./download_alkis.sh th             # file count + size estimate, download nothing
JOBS=12 CONN=4 ./download_alkis.sh bb        # tune parallelism
PAGE=50000 ./download_alkis.sh ni            # page size for the WFS/OGC-API states
```

There is no shared national interface, so the script carries one plan per state and four
download engines:

| Engine | States | Mechanism |
|--------|--------|-----------|
| `aria2` | `bw` `by` `bb` `hh` `mv` `nw` `sl` `sn` `sh` `th` | build a file list, hand it to `aria2c` |
| `metalink` | `rp` | official `.meta4` with per-file **SHA-256** → `aria2c --check-integrity` |
| `wfs2` | `be` `ni` `st` | WFS 2.0 paged with `COUNT`/`STARTINDEX` → one GML per page |
| `wfs1` | `hb` | WFS 1.1 has no standard paging; Bremen fits in one request |
| `ogcapi` | `he` | OGC API Features, follow `rel="next"` → one GeoJSON per page |

The file lists are **never hard-coded** — they are rebuilt on every run from whatever each
state publishes as its index:

- **BW** draws its Gemarkung grid as **Mapbox vector tiles** carrying a JSON blob with each
  cell's download URLs — the same trick as its LiDAR 2×2 km grid, so `download_bw_lidar.sh`
  and `download_alkis.sh` share the stdlib-only MVT reader.
- **NW** serves a machine-readable XML index per product folder.
- **BB** is a plain Apache directory listing.
- **MV** and **TH** publish standards-compliant **INSPIRE ATOM** feeds.
- **HH** is queried through the transparency portal's **CKAN API**, so the newest quarterly
  snapshot is picked automatically rather than pinned.
- **SL** is a password-less public **Nextcloud** share, listed over WebDAV `PROPFIND`.

Only RP publishes checksums, so only `rp` is hash-verified; everywhere else downloads are
parallel, resumable (`--continue`) and size-checked.

# NAS — the exchange format

Most of what `download_alkis.sh` fetches is **NAS**, and half the ALKIS tables above turn on
the difference between NAS and a *vereinfacht* derivative. Worth knowing what it is.

**NAS = Normbasierte Austauschschnittstelle**, "standards-based exchange interface". It is not
a container like Shapefile or GeoPackage — it is a **GML 3.2.1 application schema** with its
own object model *and its own update protocol*, defined by the AdV in the **GeoInfoDok** on top
of the ISO 19100 series (19107 geometry, 19109 application-schema rules, 19136 GML).

One format serves all three official datasets, together the **AAA model**:

| | |
|---|---|
| **AFIS** | Festpunkte — geodetic control |
| **ALKIS** | the cadastre — what this script fetches |
| **ATKIS** | the topographic landscape model (Basis-DLM) |

So the `.xml` inside `alkis_sn.zip` and a Basis-DLM delivery are the same format carrying
different *Fachschemata*. The schema splits into a fach-neutral **Basisschema** (generic object
properties) and a **Fachschema** (the domain classes), which is why every NAS object shares the
same lifecycle machinery whatever it describes.

**Versions.** The AdV reference version has been **7.1** (AAA-AS 7.1.2) since 2024-01-01;
**GeoInfoDok 6.0.1** is still what a lot of deployed data and tooling speaks. When a vendor
advertises "GeoInfoDok 7 konform", that migration is what they mean.

## Full NAS vs. `vereinfacht`

This is the distinction behind ST's row in the [ALKIS table](#3-alkis--cadastre-availability),
NW's `gru_vereinfacht` GeoPackage and SH's statewide GeoJSON:

| | Full NAS | `vereinfacht` |
|---|---|---|
| **Object model** | relational — `AX_Flurstueck` *points at* its `AX_Buchungsstelle`, `AX_LagebezeichnungMitHausnummer`, `AX_TatsaechlicheNutzung` | flattened into one feature type with attributes |
| **Punktinformationen** | `AX_Grenzpunkt`, `AX_Punktort` — surveyed boundary points with accuracy metadata | dropped; you get the polygon, not the points that define it |
| **Grundbuch linkage** | `AX_Buchungsstelle` / `AX_Buchungsblatt`, the chain from parcel to land register | dropped |
| **Lifecycle** | every object carries `gml:id`, `lebenszeitintervall` (`beginnt`/`endet`), `modellart`, `anlass` — objects are temporal | a snapshot |
| **Updates** | **NBA** (*Nutzerbezogene Bestandsdatenaktualisierung*) — differential insert/replace/delete against a subscription | re-download everything |
| **Full extract** | **BDA** (*Bestandsdatenauszug*) | the only mode |

That NBA/BDA split is why NAS is a *transaction* format rather than a file format: it carries
WFS-Transaction-style operations so a licensee's copy tracks the cadastre continuously. **No
state offers NBA over an open endpoint**, so everything here is a BDA-style snapshot — which is
also why "never cache a tile list" in [Notes](#notes) is the only sync strategy available.

Owner data is orthogonal to all of this: `AX_Person` / `AX_Namensnummer` exist in the full
model but are stripped from every *ohne Eigentümer* variant, NAS or not.

## Why simplified products exist at all

NAS is verbose, deeply nested, and needs a real parser. GDAL ships a dedicated `NAS` driver,
but it is a Xerces-based build option that is not always compiled in; the common alternative is
**PostNAS / norGIS ALKIS-Import** into PostGIS. Ordinary GIS tooling cannot open a NAS file
usefully, which is why states publish a flat derivative beside it — geometry plus the keys you
actually join on, and nothing else. For ST that is `flstkennz`, `gemarkung`, `flur`, `flaeche`,
`lagebeztxt`.

For bulk work that trade is almost always the right one. Reach for full NAS only if you need
boundary-point accuracy, the Grundbuch chain, or change tracking. `download_alkis.sh` fetches
full NAS where it is offered — `bw` `bb` `mv` `ni` `nw` `sl` `sn` `th` — and the simplified
product where that is all a state publishes.

# The 16 Bundesländer

Germany is composed of 16 federal states (*Bundesländer*), including three city-states
(*Stadtstaaten*): Berlin, Bremen and Hamburg.

| ID | State (German) | English | ISO 3166-2 | Capital | Area (km²) | Population (approx.) |
|----|----------------|---------|------------|---------|-----------:|---------------------:|
| **BW** | Baden-Württemberg | Baden-Württemberg | DE-BW | Stuttgart | 35,748 | 11.3 M |
| **BY** | Bayern | Bavaria | DE-BY | München (Munich) | 70,542 | 13.4 M |
| **BE** | Berlin | Berlin | DE-BE | Berlin | 891 | 3.8 M |
| **BB** | Brandenburg | Brandenburg | DE-BB | Potsdam | 29,654 | 2.6 M |
| **HB** | Bremen | Bremen | DE-HB | Bremen | 419 | 0.7 M |
| **HH** | Hamburg | Hamburg | DE-HH | Hamburg | 755 | 1.9 M |
| **HE** | Hessen | Hesse | DE-HE | Wiesbaden | 21,116 | 6.4 M |
| **MV** | Mecklenburg-Vorpommern | Mecklenburg-Western Pomerania | DE-MV | Schwerin | 23,295 | 1.6 M |
| **NI** | Niedersachsen | Lower Saxony | DE-NI | Hannover | 47,710 | 8.1 M |
| **NW** | Nordrhein-Westfalen | North Rhine-Westphalia | DE-NW | Düsseldorf | 34,113 | 18.1 M |
| **RP** | Rheinland-Pfalz | Rhineland-Palatinate | DE-RP | Mainz | 19,858 | 4.2 M |
| **SL** | Saarland | Saarland | DE-SL | Saarbrücken | 2,571 | 1.0 M |
| **SN** | Sachsen | Saxony | DE-SN | Dresden | 18,450 | 4.1 M |
| **ST** | Sachsen-Anhalt | Saxony-Anhalt | DE-ST | Magdeburg | 20,459 | 2.2 M |
| **SH** | Schleswig-Holstein | Schleswig-Holstein | DE-SH | Kiel | 15,804 | 2.9 M |
| **TH** | Thüringen | Thuringia | DE-TH | Erfurt | 16,202 | 2.1 M |

The `DE-xx` ISO codes are commonly used in datasets and shapefiles, and NUTS-1 regions map
1:1 onto the Bundesländer.

**Grouped by region**

- **Northern:** HB, HH, MV, NI, SH
- **Eastern (former GDR):** BE (east), BB, MV, SN, ST, TH
- **Western:** HE, NW, RP, SL
- **Southern:** BW, BY

Boundaries for the maps come from `bundeslaender.geojson`, built by
[`bundeslaender_to_geojson.py`](bundeslaender_to_geojson.py) from BKG VG2500 and carrying this
repo's coverage as feature properties.

# Notes

**All states**

- **Never cache a tile list** — coverage is regenerated as campaigns land, so every downloader
  rebuilds its own on each run (RP/BY re-fetch the manifest, NW the `index.json`, BB the
  directory index, BE/MV the Atom feed, NI the STAC pages, SN the portal's embedded inventory,
  BW the vector-tile grid).
- **Resume** is automatic (`--continue`) everywhere. Integrity: only RP and BY `dgm1` publish
  SHA-256; everywhere else only size is checked.
- **Two UTM zones** — see [Two UTM zones](#two-utm-zones) above. Reproject before mosaicking
  across the 32/33 boundary.
- LiDAR tile counts and volumes are what the sources reported on 2026-07-28; the downloaders
  recompute them at runtime (`DRY_RUN=1`), so treat the tables as indicative. Coverage grows
  as new flight campaigns are released — Brandenburg's point cloud in particular is still
  only partial.
- The ALKIS table's "Download" column answers one question only: can a script fetch the data
  without credentials? Licensing is separate — most states still require attribution.
- Area and population figures are rounded; population is roughly early-2020s.

**RP**

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

**RP**

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

**BY**

- Portal: <https://geodaten.bayern.de/opengeodata/>
- Product catalogue the portal reads: <https://geodaten.bayern.de/opengeodata/json/opengeodata_datensaetze.json>
- DGM1 manifest: `https://geodaten.bayern.de/odd/a/dgm/dgm1/meta/metalink/09.meta4`
- Polygon service (limits + metalink): `https://geoservices.bayern.de/services/poly2metalink/datasets/laser`,
  `POST https://geoservices.bayern.de/services/poly2metalink/metalink/laser` (body = EWKT)
- Metalink usage notes: <https://www.geodaten.bayern.de/odd/m/3/pdf/informationen_metalink.pdf>

**NW**

- Portal: <https://www.opengeodata.nrw.de>
- Product tree: `https://www.opengeodata.nrw.de/produkte/geobasis/hm/` (each folder has an `index.json`)

**BB**

- Portal: <https://data.geobasis-bb.de/geobasis/daten/>
- Product pages: <https://geobasis-bb.de/lgb/de/geodaten/3d-produkte/laserscandaten/>,
  <https://geobasis-bb.de/lgb/de/geodaten/3d-produkte/gelaendemodell/>
- Coverage/currency PDFs: `https://data.geobasis-bb.de/geobasis/information/aktualitaeten/`

**SN**

- Portal: <https://www.geodaten.sachsen.de> · height products:
  <https://www.geodaten.sachsen.de/downloadbereich-digitale-hoehenmodelle-4851.html>
- Batch page carrying the inventory JS: <https://www.geodaten.sachsen.de/batch-download-4719.html>
- 2 km grid shapefile: <https://www.geodaten.sachsen.de/download/Shape_km2_33_UTM.zip>

**NI**

- Portal: <https://opengeodata.lgln.niedersachsen.de>
- STAC API: <https://dgm.stac.lgln.niedersachsen.de/collections/dgm1>

**BE**

- DGM1 Atom: <https://gdi.berlin.de/data/dgm1/atom/> · ALS Atom: <https://gdi.berlin.de/data/a_als/atom/>
- Catalogue: <https://daten.berlin.de>

**MV**

- DGM Atom: <https://www.geodaten-mv.de/dienste/dgm_atom> · ALS Atom: <https://www.geodaten-mv.de/dienste/als_atom>
- Open-data overview: <https://www.laiv-mv.de/Geoinformation/Open_Data_Angebot/>

**ST**

- Open data portal: <https://www.lvermgeo.sachsen-anhalt.de/de/gdp-open-data.html>
- Product page (3D-Messdaten, priced/on request): <https://www.lvermgeo.sachsen-anhalt.de/de/gdp-3d-messdaten.html>
- The two open LAZ areas, direct (range-capable ZIPs):
  - `…/gfds_webshare/download/LVermGeo/Geodatenportal/externedaten/Hakel.zip` (2.9 GB)
  - `…/gfds_webshare/download/LVermGeo/Geodatenportal/externedaten/Gemeinde_HalleSaale.zip` (17.4 GB, ZIP64)
  - host: <https://www.geodatenportal.sachsen-anhalt.de>
- DGM1/DOM1 map downloader (5-tile cap): <https://www.lvermgeo.sachsen-anhalt.de/de/gdp-dgm1.html>
  · its backend is `…/de/mod/2,2913,501/ajax/1/prepare/?`, and the page inlines the whole tile grid as GeoJSON
- Statewide DGM5 as one free ZIP: `…/Online-Bereitstellung-LVermGeo/DGM/DGM5.zip`

**TH**

- INSPIRE Atom services (the bulk route): <https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_las>
  · `…_dgm` · `…_dom` — each a service feed linking one dataset feed of ~17,000 per-tile `<link rel="section">` entries
- Tiles live under `https://geoportal.geoportal-th.de/hoehendaten/{LAS,DGM,DOM}/<product>_<vintage>/`
- The `gaialight` app that is *not* the bulk route: <https://geoportal.geoportal-th.de/gaialight-th/_apps/dladownload/dl-dhm.html>
  · it also links the feeds above, and offers `dgm25_landesweit_th.zip` as a single statewide file
- Per-vintage coverage indexes: `…/hoehendaten/Uebersichten/Stand_<vintage>.zip`, product descriptions `…/README_Hoehendaten_<vintage>.pdf`

**SL**

- Open Data terms and product list: <https://www.shop.lvgl.saarland.de/index.php?option=com_content&view=article&id=18>
  · licence DL-DE/BY 2.0, source note `© GeoBasis DE/LVGL-SL (Jahr der Bereitstellung)`
- The share holding every statewide open dataset: <https://www.shop.lvgl.saarland.de/cloud/freiegeobasisdaten>
  → redirects to `/cloud/index.php/s/<token>`; public WebDAV at `/cloud/public.php/dav/files/<token>/`
- Point cloud folder: `OD_LIDAR_Punktwolke_2025_laz_LK`, one ZIP per Landkreis, plus a
  `Kachelübersicht-Airborne Laserscanning 2025.pdf` tile index
- The GovData entry for the 2016 DGM1 still answers with an "order it on a disk" note — that
  predates the 2025 campaign and is not the current route

**States without a LiDAR script** (starting points if you want to add one)

- SH: <https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/dl-dgm1.html>
  (same `gaialight` app as TH — check `…/dienste/` for an INSPIRE Atom service first)
- HE: <https://hvbg.hessen.de/geoinformation/open-data>
- HH: <https://suche.transparenz.hamburg.de/> (CKAN API at `/api/3/action/package_search`)

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
