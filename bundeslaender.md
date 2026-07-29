# Bundesländer (German Federal States)

Germany is composed of 16 federal states (*Bundesländer*), including three
city-states (*Stadtstaaten*): Berlin, Bremen, and Hamburg.

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

## The state ID

**The ID is the ISO 3166-2 code without the `DE-` prefix.** It is the only state identifier
this repo uses, and it is the same string everywhere — every table below, both generated maps,
and all machine-readable data:

| Where | Form | Example |
|-------|------|---------|
| Tables and prose in these documents | upper case | `NW`, `RP` |
| Map labels on `coverage_map.png` / `alkis_map.png` | upper case | `NW`, `RP` |
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

## LiDAR / elevation open data

Status as surveyed 2026-07-28. **No state gates its LiDAR behind a login** — every one of the
16 publishes it as open data. The dividing line is whether an anonymous *bulk* endpoint exists
that a script can drive, or whether you have to click through an interactive portal.

Legend: ✅ available and scripted · ⚠️ open but no bulk endpoint found · ❌ not published.

| ID | State | Point cloud | DTM (DGM1) | Bulk downloader | CRS | Licence |
|----|-------|:-----------:|:----------:|-----------------|-----|---------|
| **BW** | Baden-Württemberg | ❌ | ✅ | `download_bw_lidar.sh` | 25832 | DL-DE/BY 2.0 |
| **BY** | Bayern | ✅ | ✅ | `download_by_lidar.sh` | 25832 | DL-DE/BY 2.0 |
| **BE** | Berlin | ✅ | ✅ | `download_be_lidar.sh` | 25833 | DL-DE/Zero 2.0 |
| **BB** | Brandenburg | ✅ | ✅ | `download_bb_lidar.sh` | 25833 | DL-DE/BY 2.0 |
| **HB** | Bremen | ⚠️ | ⚠️ | — | — | — |
| **HH** | Hamburg | ❌ | ⚠️ | — | 25832 | open (Transparenzportal) |
| **HE** | Hessen | ⚠️ | ⚠️ | — | 25832 | open, no conditions (since 2022) |
| **MV** | Mecklenburg-Vorpommern | ✅ | ✅ | `download_mv_lidar.sh` | 25833 | open, attribution required |
| **NI** | Niedersachsen | ❌ | ✅ | `download_ni_lidar.sh` | 25832 | CC BY 4.0 |
| **NW** | Nordrhein-Westfalen | ✅ | ✅ | `download_nrw_lidar.sh` † | 25832 | DL-DE/Zero 2.0 |
| **RP** | Rheinland-Pfalz | ✅ | ✅ | `download_rlp_lidar.sh` † | 25832 | DL-DE/BY 2.0 |
| **SL** | Saarland | ⚠️ | ⚠️ | — | — | — |
| **SN** | Sachsen | ✅ | ✅ | `download_sn_lidar.sh` | 25833 | DL-DE/Zero 2.0 |
| **ST** | Sachsen-Anhalt | ⚠️ | ⚠️ | — | 25832 | DL-DE/BY 2.0 (since 2023) |
| **SH** | Schleswig-Holstein | ❌ | ⚠️ | — | 25832 | open |
| **TH** | Thüringen | ⚠️ | ⚠️ | — | 25832 | DL-DE/BY 2.0 |

† The two filenames that do not match their ID — see [The state ID](#the-state-id).

**9 of 16 states are scripted** — covering roughly two thirds of Germany's land area and,
between them, well over 10 TB of point cloud.

### Volumes for the scripted states

| ID | State | Point cloud | DTM |
|----|-------|-------------|-----|
| **BY** | Bayern | ~69,546 tiles (1 km), multi-TB | 71,979 tiles, 217 GB |
| **BE** | Berlin | 9 region packages | 297 tiles (2 km), ~0.2 GB |
| **BB** | Brandenburg | 13,086 tiles (1 km), ~1.35 TB | 31,291 tiles (1 km), ~36 GB |
| **MV** | Mecklenburg-Vorpommern | 25,466 tiles (1 km) | 6,407 tiles (2 km) |
| **NI** | Niedersachsen | — | 49,708 tiles (1 km), already COG |
| **NW** | Nordrhein-Westfalen | 35,860 tiles (1 km), 3.49 TB | 35,860 tiles (1 km), 78.8 GB |
| **RP** | Rheinland-Pfalz | ~21,207 tiles (1 km), 5.18 TB | ~21,082 tiles (1 km), 32.8 GB |
| **SN** | Sachsen | 4,981 tiles (2 km) | 4,981 tiles (2 km) |
| **BW** | Baden-Württemberg | — | 9,370 zips (2 km), ~125 GB |

### Why the other seven have no script

| ID | State | Blocker |
|----|-------|---------|
| **TH** | Thüringen | Publishes DGM, DOM **and LAZ**, but delivery runs through the `gaialight` map app, whose query API needs an internal `type` key not derivable from the client config. The public RSS is a change log, not an inventory. |
| **SH** | Schleswig-Holstein | Same `gaialight` app; its `overview.php` returns an empty result set without the app's internal filter state. DGM1 only — the open-data catalogue lists no point cloud. |
| **ST** | Sachsen-Anhalt | Open since 2023-07-01 *including* classified laser scan results, and Atom feeds are advertised, but the endpoint was not locatable under the documented host. The web UI caps manual selection at 5 tiles. |
| **HE** | Hessen | Open with no usage conditions since 2022-02-01, DGM1 free in the Downloadcenter — but delivery is an Intershop storefront with no static index or feed. |
| **HH** | Hamburg | DGM1 published via the Transparenzportal, but `daten-hamburg.de` returns 403 on directory listings, so tiles are reachable only by exact known URL. |
| **HB**, **SL** | Bremen, Saarland | No open LiDAR bulk product identified. |

### Two UTM zones

This matters when mosaicking across state borders:

- **EPSG:25832** (UTM 32N): BW, BY, HE, NI, NW, RP, SH, ST, TH — and HH.
- **EPSG:25833** (UTM 33N): BB, BE, MV, SN.

Within a zone all states share the same grid origin (SW corner snapped to whole km), so tiles
line up across borders. Across zones they do not — reproject first.

See [README.md](README.md) for the download mechanisms, per-state gotchas, and usage.

## Grouped by region

**Northern:** Bremen, Hamburg, Mecklenburg-Vorpommern, Niedersachsen, Schleswig-Holstein
**Eastern (former GDR):** Berlin (east), Brandenburg, Mecklenburg-Vorpommern, Sachsen, Sachsen-Anhalt, Thüringen
**Western:** Hessen, Nordrhein-Westfalen, Rheinland-Pfalz, Saarland
**Southern:** Baden-Württemberg, Bayern

## ALKIS — cadastral open data per state

**ALKIS** (*Amtliches Liegenschaftskatasterinformationssystem*) is the official cadastre:
parcels (*Flurstücke*), building footprints (*Gebäude*), actual land use (*Tatsächliche
Nutzung*), addresses. Each state runs its own, so each publishes it differently — or not at
all. Owner names (*Eigentümerangaben*) are **never** open data anywhere; what states release
is the *ohne Eigentümer* (oE) variant.

<img src="alkis_map.png" alt="Map of the 16 Bundesländer coloured by cadastre openness: green for the 13 states publishing full vector ALKIS ohne Eigentümer, orange for BY and RP which publish a raster cadastral map only, red for ST which does not publish it at all" width="560">

Thirteen states are green. The two orange ones are not a delivery problem — BY and RP publish
their cadastre as **raster**, so the download works fine and parcel geometry simply is not in
what arrives. Only ST is closed. Regenerate with `./coverage_map.py alkis`.

Status verified live in July 2026. **"Login"** means a user account is needed to get the
data; **"anonymous"** means plain HTTP with no credentials.

| ID | State | ALKIS as open data | Download | How | Format · unit | License |
|----|-------|--------------------|----------|-----|---------------|---------|
| **BW** | Baden-Württemberg | ✅ full (oE) | **anonymous** | vector-tile grid → ZIP | NAS, Shape · Gemarkung (~3,400) | DL-DE/BY 2.0 |
| **BY** | Bayern | ⚠️ **partial** | **anonymous** | static ZIP / GPKG | no vector Flurstücke — see notes | CC BY 4.0 |
| **BE** | Berlin | ✅ full (oE) | **anonymous** | WFS 2.0 only | GML · statewide (~403k parcels) | DL-DE/Zero 2.0 |
| **BB** | Brandenburg | ✅ full (oE) | **anonymous** | directory listing | NAS, Shape · Landkreis (18) | DL-DE/BY 2.0 |
| **HB** | Bremen | ✅ full (oE) | **anonymous** | WFS 1.1 only | GML · statewide | CC BY 4.0 |
| **HH** | Hamburg | ✅ "ausgewählte Daten" | **anonymous** | CKAN API → ZIP | GML · statewide, quarterly | DL-DE/BY 2.0 |
| **HE** | Hessen | ✅ full (oE) | **anonymous** via API<br>**login** for file packages | OGC API Features / WFS | GeoJSON, GML · statewide (~5.0 M parcels) | DL-DE/Zero 2.0 |
| **MV** | Mecklenburg-Vorpommern | ✅ full (oE) | **anonymous** | INSPIRE ATOM feed | NAS · Gemeinde (~750) | CC BY 4.0 |
| **NI** | Niedersachsen | ✅ full (oE) | **anonymous** | WFS 2.0 (NAS) only | GML · statewide (~6.3 M parcels) | DL-DE/BY 2.0 |
| **NW** | Nordrhein-Westfalen | ✅ full (oE) | **anonymous** | XML index → ZIP | NAS, simplified GPKG · Kreis (53) | DL-DE/Zero 2.0 |
| **RP** | Rheinland-Pfalz | ⚠️ **raster only** | **anonymous** | Metalink-4 | GeoTIFF cadastral map · 1 km tile | DL-DE/BY 2.0 |
| **SL** | Saarland | ✅ full (oE) | **anonymous** | public WebDAV share | NAS, Shape · Landkreis (7) | DL-DE/BY 2.0 |
| **SN** | Sachsen | ✅ full (oE) | **anonymous** | single ZIP | NAS · statewide | DL-DE/BY 2.0 |
| **ST** | Sachsen-Anhalt | ❌ **not open** | — | (formal request to LVermGeo) | — | — |
| **SH** | Schleswig-Holstein | ✅ full (oE) | **anonymous** | single file | GeoJSON · statewide (~243 MB) | CC BY 4.0 |
| **TH** | Thüringen | ✅ full (oE) | **anonymous** | INSPIRE ATOM feed | Shape, NAS · Flur (~16,500) | DL-DE/BY 2.0 |

**No state requires a login for the data listed above.** Thirteen states publish the full
cadastre openly; the three exceptions are content gaps at the source, not access barriers:

- **Bayern** — the *ALKIS-Parzellarkarte* is published as **raster only** (WMS/WMTS and
  GeoTIFF via Metalink). Open vector products are limited to *Tatsächliche Nutzung*
  (statewide GeoPackage, ~5 GB), *Hausumringe* (Shape per Regierungsbezirk) and
  *Verwaltungsgebiete*. Vector parcel geometry is sold through GeodatenOnline, which does
  require an account.
- **Rheinland-Pfalz** — publishes the **rasterised** Liegenschaftskarte (`lika`, ~20,500
  GeoTIFF tiles, ~31 GB) and *Hausumringe*, but no bulk vector ALKIS. Parcel geometry is
  reachable only per-query through the Flurstückssuche WFS.
- **Sachsen-Anhalt** — the LVermGeo open-data catalogue carries only ALKIS *derivatives*
  (digitale Verwaltungsgrenzen, Hausumringe, Hauskoordinaten). Parcels and cadastral
  attributes need a formal request.

Two portals do sit behind a login, but neither is the only route to their state's data:

- **Hessen** — the *Downloadcenter* on `gds.hessen.de` requires a free customer account for
  packaged files. The INSPIRE **OGC API Features** endpoint carries the same ALKIS oE
  content anonymously, so the downloader uses that instead.
- **Saarland** — `shop.lvgl.saarland.de` is a webshop with accounts, but LVGL also mirrors
  the statewide open datasets on a **password-less public Nextcloud share**, which is what
  the downloader reads.

Four states publish **services only** — no file packages exist, so a bulk copy means paging
a WFS or OGC API (`download_alkis.sh` does this automatically): Berlin, Bremen,
Niedersachsen, Hessen.

All ALKIS data above is in **ETRS89 / UTM** (EPSG:25832, EPSG:25833 in the east).
See `download_alkis.sh` for the downloader and `README.md` for usage.

## Complete coverage — the states where all four datasets are fetchable

The three sections above each answer one dataset at a time. This one answers the crossing
question: **for which states can we fetch point cloud *and* terrain *and* parcels *and*
building footprints?** Footprint sources are detailed in
[`hauskoordinaten-hausumringe.md`](hauskoordinaten-hausumringe.md).

**Five states: Brandenburg, Berlin, Mecklenburg-Vorpommern, Nordrhein-Westfalen, Sachsen.**

<img src="coverage_map.png" alt="Map of the 16 Bundesländer coloured by coverage: green (BB, BE, MV, NW, SN) for all four datasets, orange (BW, BY, NI, RP) for one missing, red (HB, HE, HH, SH, SL, ST, TH) for no bulk LiDAR" width="560">

Regenerate it with `./coverage_map.py all` after any coverage change — that script draws this
map and the [ALKIS one](#alkis--cadastral-open-data-per-state) below, reading `lidar_las`,
`lidar_dgm1`, `lidar_script` and `alkis` straight out of `bundeslaender.geojson`, so both
follow the data rather than these tables. Footprints are the one input it carries itself.
`coverage_map.svg` / `alkis_map.svg` are the same images as vector.

| ID | State | Point cloud | DTM (DGM1) | Plots (Flurstücke) | House structures |
|----|-------|-------------|------------|--------------------|------------------|
| **BB** | Brandenburg | ✅ `download_bb_lidar.sh` | ✅ same | ✅ `download_alkis.sh bb` — NAS/Shape, 18 Landkreise | ✅ inside that same ALKIS package |
| **BE** | Berlin | ✅ `download_be_lidar.sh` | ✅ same | ✅ `download_alkis.sh be flurstuecke` — WFS 2.0 | ✅ `… be gebaeude`; also an HK-DE-format ZIP |
| **MV** | Mecklenburg-Vorpommern | ✅ `download_mv_lidar.sh` | ✅ same | ✅ `download_alkis.sh mv` — NAS, ~750 Gemeinden | ✅ that package, plus a dedicated HU Atom ZIP |
| **NW** | Nordrhein-Westfalen | ✅ `download_nrw_lidar.sh` † | ✅ same | ✅ `download_alkis.sh nw` — NAS/GPKG, 53 Kreise | ✅ that package, plus `gru_vereinfacht` + `gebref` |
| **SN** | Sachsen | ✅ `download_sn_lidar.sh` | ✅ same | ✅ `download_alkis.sh sn` — NAS, one statewide ZIP | ✅ that package, plus standalone HU/HK ZIPs |

Footprints are never a separate fetch in these five: ALKIS carries `AX_Gebaeude`, so the
parcel download brings them along. The extra products in the last column are convenience —
smaller, simpler files than a full NAS package for anyone who wants only footprints.

Picking between them: **NW** is the strongest — every product carries a machine-readable
index, and DL-DE/Zero 2.0 means no attribution obligation. **BE** is the fastest to fetch
end to end (~0.2 GB of DGM1, 9 point-cloud packages, WFS cadastre) and also DL-DE/Zero, which
makes it the natural smoke test for a full four-dataset pipeline. **BB** carries one caveat:
its point cloud is still **partial** — 13,086 LAZ tiles against a complete 31,291-tile DGM1
grid, released campaign by campaign.

### Why the other eleven fall short

| ID | State | Missing | Detail |
|----|-------|---------|--------|
| **RP** | Rheinland-Pfalz | plots | Everything else is present and RP is the best-engineered source in the repo (Metalink-4 with SHA-256 for LiDAR *and* Hausumringe) — but the cadastre is published as a **rasterised** Liegenschaftskarte. No bulk vector parcels; geometry only per-query via the Flurstückssuche WFS. |
| **BY** | Bayern | plots | Same single gap: ALKIS-Parzellarkarte is raster-only, vector parcels are sold through GeodatenOnline. Hausumringe are open (CC BY 4.0); Hauskoordinaten are priced. |
| **BW** | Baden-Württemberg | point cloud | Full ALKIS + HU + HK, 125 GB of DGM1 — but the `3DM` point cloud is flagged inactive and every URL 404s. |
| **NI** | Niedersachsen | point cloud | STAC exposes `dgm1` only. Cadastre and footprints are fine (`gebaeude` WFS); the standalone HK/HU products are priced. |
| **TH**, **SH**, **ST**, **HE**, **HH**, **HB**, **SL** | — | point cloud + DTM | No anonymous bulk LiDAR endpoint found — portals, CAPTCHAs and order clients, not access restrictions. ST additionally has no open ALKIS at all. |

### Fetching all four today

There is no single command for it. `download_samples.sh` drives only the LiDAR side, because
`download_alkis.sh` has no `BBOX` support — parcels and footprints are per-state or
per-package until that lands. For one of the five states, the full set is:

```bash
./download_<key>_lidar.sh both ./samples/<key>    # point cloud + terrain
./download_alkis.sh <key>                         # parcels + building footprints
```

## Notes

- Area and population figures are rounded; population is roughly early-2020s.
- ISO codes are the `DE-xx` subdivision codes, commonly used in datasets and
  shapefiles (e.g. NUTS-1 regions map 1:1 onto the Bundesländer). Their two-letter suffix is
  [the ID](#the-state-id) this repo keys everything on.
- LiDAR tile counts and volumes are what the sources reported on 2026-07-28; the
  downloaders recompute them at runtime (`DRY_RUN=1`), so treat the table as indicative.
  Coverage grows as new flight campaigns are released — Brandenburg's point cloud in
  particular is still only partial.
- The ALKIS table's "Download" column answers one question only: can a script fetch the
  data without credentials? Licensing is separate — every state above still requires
  attribution.
