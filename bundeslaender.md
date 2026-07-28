# Bundesländer (German Federal States)

Germany is composed of 16 federal states (*Bundesländer*), including three
city-states (*Stadtstaaten*): Berlin, Bremen, and Hamburg.

| # | State (German) | English | ISO 3166-2 | Capital | Area (km²) | Population (approx.) |
|---|----------------|---------|------------|---------|-----------:|---------------------:|
| 1 | Baden-Württemberg | Baden-Württemberg | DE-BW | Stuttgart | 35,748 | 11.3 M |
| 2 | Bayern | Bavaria | DE-BY | München (Munich) | 70,542 | 13.4 M |
| 3 | Berlin | Berlin | DE-BE | Berlin | 891 | 3.8 M |
| 4 | Brandenburg | Brandenburg | DE-BB | Potsdam | 29,654 | 2.6 M |
| 5 | Bremen | Bremen | DE-HB | Bremen | 419 | 0.7 M |
| 6 | Hamburg | Hamburg | DE-HH | Hamburg | 755 | 1.9 M |
| 7 | Hessen | Hesse | DE-HE | Wiesbaden | 21,116 | 6.4 M |
| 8 | Mecklenburg-Vorpommern | Mecklenburg-Western Pomerania | DE-MV | Schwerin | 23,295 | 1.6 M |
| 9 | Niedersachsen | Lower Saxony | DE-NI | Hannover | 47,710 | 8.1 M |
| 10 | Nordrhein-Westfalen | North Rhine-Westphalia | DE-NW | Düsseldorf | 34,113 | 18.1 M |
| 11 | Rheinland-Pfalz | Rhineland-Palatinate | DE-RP | Mainz | 19,858 | 4.2 M |
| 12 | Saarland | Saarland | DE-SL | Saarbrücken | 2,571 | 1.0 M |
| 13 | Sachsen | Saxony | DE-SN | Dresden | 18,450 | 4.1 M |
| 14 | Sachsen-Anhalt | Saxony-Anhalt | DE-ST | Magdeburg | 20,459 | 2.2 M |
| 15 | Schleswig-Holstein | Schleswig-Holstein | DE-SH | Kiel | 15,804 | 2.9 M |
| 16 | Thüringen | Thuringia | DE-TH | Erfurt | 16,202 | 2.1 M |

## LiDAR / elevation open data

Status as surveyed 2026-07-28. **No state gates its LiDAR behind a login** — every one of the
16 publishes it as open data. The dividing line is whether an anonymous *bulk* endpoint exists
that a script can drive, or whether you have to click through an interactive portal.

Legend: ✅ available and scripted · ⚠️ open but no bulk endpoint found · ❌ not published.

| State | Point cloud | DTM (DGM1) | Bulk downloader | CRS | Licence |
|-------|:-----------:|:----------:|-----------------|-----|---------|
| Baden-Württemberg | ❌ | ✅ | `download_bw_lidar.sh` | 25832 | DL-DE/BY 2.0 |
| Bayern | ✅ | ✅ | `download_by_lidar.sh` | 25832 | DL-DE/BY 2.0 |
| Berlin | ✅ | ✅ | `download_be_lidar.sh` | 25833 | DL-DE/Zero 2.0 |
| Brandenburg | ✅ | ✅ | `download_bb_lidar.sh` | 25833 | DL-DE/BY 2.0 |
| Bremen | ⚠️ | ⚠️ | — | — | — |
| Hamburg | ❌ | ⚠️ | — | 25832 | open (Transparenzportal) |
| Hessen | ⚠️ | ⚠️ | — | 25832 | open, no conditions (since 2022) |
| Mecklenburg-Vorpommern | ✅ | ✅ | `download_mv_lidar.sh` | 25833 | open, attribution required |
| Niedersachsen | ❌ | ✅ | `download_ni_lidar.sh` | 25832 | CC BY 4.0 |
| Nordrhein-Westfalen | ✅ | ✅ | `download_nrw_lidar.sh` | 25832 | DL-DE/Zero 2.0 |
| Rheinland-Pfalz | ✅ | ✅ | `download_rlp_lidar.sh` | 25832 | DL-DE/BY 2.0 |
| Saarland | ⚠️ | ⚠️ | — | — | — |
| Sachsen | ✅ | ✅ | `download_sn_lidar.sh` | 25833 | DL-DE/Zero 2.0 |
| Sachsen-Anhalt | ⚠️ | ⚠️ | — | 25832 | DL-DE/BY 2.0 (since 2023) |
| Schleswig-Holstein | ❌ | ⚠️ | — | 25832 | open |
| Thüringen | ⚠️ | ⚠️ | — | 25832 | DL-DE/BY 2.0 |

**9 of 16 states are scripted** — covering roughly two thirds of Germany's land area and,
between them, well over 10 TB of point cloud.

### Volumes for the scripted states

| State | Point cloud | DTM |
|-------|-------------|-----|
| Bayern | ~69,546 tiles (1 km), multi-TB | 71,979 tiles, 217 GB |
| Berlin | 9 region packages | 297 tiles (2 km), ~0.2 GB |
| Brandenburg | 13,086 tiles (1 km), ~1.35 TB | 31,291 tiles (1 km), ~36 GB |
| Mecklenburg-Vorpommern | 25,466 tiles (1 km) | 6,407 tiles (2 km) |
| Niedersachsen | — | 49,708 tiles (1 km), already COG |
| Nordrhein-Westfalen | 35,860 tiles (1 km), 3.49 TB | 35,860 tiles (1 km), 78.8 GB |
| Rheinland-Pfalz | ~21,207 tiles (1 km), 5.18 TB | ~21,082 tiles (1 km), 32.8 GB |
| Sachsen | 4,981 tiles (2 km) | 4,981 tiles (2 km) |
| Baden-Württemberg | — | 9,370 zips (2 km), ~125 GB |

### Why the other seven have no script

| State | Blocker |
|-------|---------|
| Thüringen | Publishes DGM, DOM **and LAZ**, but delivery runs through the `gaialight` map app, whose query API needs an internal `type` key not derivable from the client config. The public RSS is a change log, not an inventory. |
| Schleswig-Holstein | Same `gaialight` app; its `overview.php` returns an empty result set without the app's internal filter state. DGM1 only — the open-data catalogue lists no point cloud. |
| Sachsen-Anhalt | Open since 2023-07-01 *including* classified laser scan results, and Atom feeds are advertised, but the endpoint was not locatable under the documented host. The web UI caps manual selection at 5 tiles. |
| Hessen | Open with no usage conditions since 2022-02-01, DGM1 free in the Downloadcenter — but delivery is an Intershop storefront with no static index or feed. |
| Hamburg | DGM1 published via the Transparenzportal, but `daten-hamburg.de` returns 403 on directory listings, so tiles are reachable only by exact known URL. |
| Bremen, Saarland | No open LiDAR bulk product identified. |

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

Status verified live in July 2026. **"Login"** means a user account is needed to get the
data; **"anonymous"** means plain HTTP with no credentials.

| # | State | ALKIS as open data | Download | How | Format · unit | License |
|---|-------|--------------------|----------|-----|---------------|---------|
| 1 | Baden-Württemberg | ✅ full (oE) | **anonymous** | vector-tile grid → ZIP | NAS, Shape · Gemarkung (~3,400) | DL-DE/BY 2.0 |
| 2 | Bayern | ⚠️ **partial** | **anonymous** | static ZIP / GPKG | no vector Flurstücke — see notes | CC BY 4.0 |
| 3 | Berlin | ✅ full (oE) | **anonymous** | WFS 2.0 only | GML · statewide (~403k parcels) | DL-DE/Zero 2.0 |
| 4 | Brandenburg | ✅ full (oE) | **anonymous** | directory listing | NAS, Shape · Landkreis (18) | DL-DE/BY 2.0 |
| 5 | Bremen | ✅ full (oE) | **anonymous** | WFS 1.1 only | GML · statewide | CC BY 4.0 |
| 6 | Hamburg | ✅ "ausgewählte Daten" | **anonymous** | CKAN API → ZIP | GML · statewide, quarterly | DL-DE/BY 2.0 |
| 7 | Hessen | ✅ full (oE) | **anonymous** via API<br>**login** for file packages | OGC API Features / WFS | GeoJSON, GML · statewide (~5.0 M parcels) | DL-DE/Zero 2.0 |
| 8 | Mecklenburg-Vorpommern | ✅ full (oE) | **anonymous** | INSPIRE ATOM feed | NAS · Gemeinde (~750) | CC BY 4.0 |
| 9 | Niedersachsen | ✅ full (oE) | **anonymous** | WFS 2.0 (NAS) only | GML · statewide (~6.3 M parcels) | DL-DE/BY 2.0 |
| 10 | Nordrhein-Westfalen | ✅ full (oE) | **anonymous** | XML index → ZIP | NAS, simplified GPKG · Kreis (53) | DL-DE/Zero 2.0 |
| 11 | Rheinland-Pfalz | ⚠️ **raster only** | **anonymous** | Metalink-4 | GeoTIFF cadastral map · 1 km tile | DL-DE/BY 2.0 |
| 12 | Saarland | ✅ full (oE) | **anonymous** | public WebDAV share | NAS, Shape · Landkreis (7) | DL-DE/BY 2.0 |
| 13 | Sachsen | ✅ full (oE) | **anonymous** | single ZIP | NAS · statewide | DL-DE/BY 2.0 |
| 14 | Sachsen-Anhalt | ❌ **not open** | — | (formal request to LVermGeo) | — | — |
| 15 | Schleswig-Holstein | ✅ full (oE) | **anonymous** | single file | GeoJSON · statewide (~243 MB) | CC BY 4.0 |
| 16 | Thüringen | ✅ full (oE) | **anonymous** | INSPIRE ATOM feed | Shape, NAS · Flur (~16,500) | DL-DE/BY 2.0 |

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

## Notes

- Area and population figures are rounded; population is roughly early-2020s.
- ISO codes are the `DE-xx` subdivision codes, commonly used in datasets and
  shapefiles (e.g. NUTS-1 regions map 1:1 onto the Bundesländer).
- LiDAR tile counts and volumes are what the sources reported on 2026-07-28; the
  downloaders recompute them at runtime (`DRY_RUN=1`), so treat the table as indicative.
  Coverage grows as new flight campaigns are released — Brandenburg's point cloud in
  particular is still only partial.
- The ALKIS table's "Download" column answers one question only: can a script fetch the
  data without credentials? Licensing is separate — every state above still requires
  attribution.
