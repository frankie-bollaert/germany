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
- The ALKIS table's "Download" column answers one question only: can a script fetch the
  data without credentials? Licensing is separate — every state above still requires
  attribution.
