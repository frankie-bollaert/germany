# Hauskoordinaten (HK) & Hausumringe (HU) — source inventory

Building **addresses/points** (Hauskoordinaten) and building **footprint polygons**
(Hausumringe) for Germany: where they actually come from, and which ones a script can fetch.

All URLs below were probed live on **2026-07-28**. Status column says what was verified.

---

# 1. The federal products: HK-DE / HU-DE (BKG · AdV · ZSHH)

The nationwide datasets are assembled by the **ZSHH** (Zentrale Stelle Hauskoordinaten und
Hausumringe, hosted at the *Landesamt für Digitalisierung, Breitband und Vermessung* Bayern)
from the 16 state cadastres, and distributed by the **BKG**.

| | **HU-DE** | **HK-DE** |
|---|---|---|
| Product | Amtliche Hausumringe Deutschland | Amtliche Hauskoordinaten Deutschland |
| Content | building footprint polygons (no roofs, no underground, no design geometry) | addressed building points + admin attributes |
| Format | Shapefile, split per Bundesland | CSV, UTF-8, `;`-delimited, per Bundesland |
| CRS | UTM32s — **EPSG:25832** | UTM32s — **EPSG:25832** |
| Records | ~59.5 million | ~23.0 million |
| Size | 13.2 GB raw / 5.2 GB zipped | 3.8 GB raw / ~450 MB zipped |
| Fields | `AGS`, `ARS`, `OI`, `GFK` | address + Verwaltungszugehörigkeit + coords |
| Update | quarterly (Produktstand 2025-12) | ~annual (Produktstand 2025-10) |
| History | from 2011 | from 2006 |

## Access — not open data

Both are **€0.00 but licence-gated**. Eligibility is limited to federal authorities and
authorised parties under *V GeoBund*, and state authorities and authorised parties under
*V GeoLänder*. Everyone else is referred to the ZSHH.

Delivery is **order in the gdz.bkg.bund.de account → download link appears in that account
within 5–10 days**. There is no anonymous bulk endpoint, and specifically:

- `https://daten.gdz.bkg.bund.de/produkte/` holds only `aerial`, `basiskarten`, `dgm`, `dlm`,
  `dtk`, `sonstige`, `topplus_open`, `vg` — **no `hu`/`hk`**.
- The BKG INSPIRE Atom download service at `https://sg.geodatenzentrum.de/web_download/`
  lists 26 datasets — **zero** matching "haus".

So there is no `.meta4`-style manifest to hand to `aria2c` the way `download_rlp_lidar.sh` does.
**A BKG downloader can only ever be a credentialed one.**

Docs (public, no login):
- <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hu-de.pdf>
- <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hk-de.pdf>

---

# 2. Open-data equivalents, per Bundesland

Under the EU High-Value-Datasets rules the states publish their own ALKIS-derived building and
address data. Coverage is **good but not complete**, and every state does it differently.

| ID | Hausumringe (footprints) | Hauskoordinaten (addresses) | Licence | Packaging |
|----|--------------------------|------------------------------|---------|-----------|
| **BW** | ✅ direct ZIP | ✅ direct ZIP | DL-DE/BY 2.0 | statewide |
| **BY** | ✅ direct ZIP ×7 | ❌ **paid** | **CC BY 4.0** | Regierungsbezirk |
| **BE** | ⚠️ WFS only | ✅ direct ZIP (HK-DE format!) | **DL-DE/Zero 2.0** | statewide |
| **BB** | ⚠️ inside ALKIS pkg | ❌ none found | DL-DE/BY 2.0 | Landkreis ×18 |
| **HB** | ⚠️ WFS only | ❌ none found | CC BY 4.0 | statewide |
| **HH** | ⚠️ GML/WFS via portal | ⚠️ ALKIS Adressen dataset | DL-DE/BY 2.0 | statewide |
| **HE** | ⚠️ free, **account required** | ❌ not confirmed | n/a | statewide |
| **MV** | ✅ Atom → direct ZIP | ❌ none found | DL-DE/BY 2.0 | state + Landkreis |
| **NI** | ❌ **priced** | ❌ **priced** | — | — |
| **NW** | ✅ direct ZIP ×Kreis | ✅ direct ZIP (Gebäudereferenzen) | **DL-DE/Zero 2.0** | Kreis / statewide |
| **RP** | ✅ direct ZIP + `.meta4` | ✅ direct ZIP + `.meta4` | DL-DE/BY 2.0 | statewide |
| **SL** | ⚠️ WFS only | ❌ none found | CC BY 4.0 | statewide |
| **SN** | ✅ direct ZIP | ✅ direct ZIP | free download | statewide |
| **ST** | ✅ direct ZIP | ❌ on request / ZSHH | free download | statewide |
| **SH** | ⚠️ interactive client | ⚠️ interactive client | free | statewide |
| **TH** | ⚠️ **CAPTCHA-gated** | ⚠️ **CAPTCHA-gated** | DL-DE/BY 2.0 | statewide |

✅ = scriptable direct URL, verified · ⚠️ = open but needs a service call, session or login ·
❌ = not available as open data · IDs are ISO 3166-2 without `DE-`, as everywhere else in this
repo — see [The state ID](bundeslaender.md#the-state-id)

**Scriptable today: 9 states for HU, 5 states for HK.**

---

## Baden-Württemberg — LGL

Catalogue JSON (the portal reads it itself, same file `download_bw_lidar.sh` conventions use):
<https://opengeodata.lgl-bw.de/assets/config/local/odp-products.json>

| | URL | Verified |
|---|---|---|
| HU | `https://opengeodata.lgl-bw.de/data/hu/hu_bw.zip` | 200, 511,246,278 B, 2026-03-23 |
| HK | `https://opengeodata.lgl-bw.de/data/hk/hk_bw.zip` | 200, 72,671,008 B, 2026-03-17 |

- HU: Shape, ETRS89/UTM32, **~5.9 M** polygons, 2×/year.
- HK: TXT, ETRS89/UTM32, **~2.9 M** points, 2×/year — **without postal fields**
  ("landesweit ohne postalische Angaben").

## Bayern — LDBV

Catalogue JSON: <https://geodaten.bayern.de/opengeodata/json/opengeodata_produkte.json>

**HU only.** Hauskoordinaten remain a priced LDBV product — Bayern is the outlier here.

The portal drives downloads off a KML index:
`https://geodaten.bayern.de/odd/m/3/daten/hausumringe/bezirk/kml/HU_regierungsbezirk.kml?service=kml`
→ 7 ZIPs, one per Regierungsbezirk:

```
https://geodaten.bayern.de/odd/m/3/daten/hausumringe/bezirk/data/091_Oberbayern_Hausumringe.zip
  …/092_Niederbayern_… 093_Oberpfalz_… 094_Oberfranken_…
  …/095_Mittelfranken_… 096_Unterfranken_… 097_Schwaben_Hausumringe.zip
```

Shape, EPSG:25832, quarterly, **CC BY 4.0** (the only state not on a DL-DE licence).
Verified: `091_Oberbayern` = 173,938,904 B.

## Berlin — Geoportal Berlin / gdi.berlin.de

**Berlin ships genuine HK-DE-format data** — the Atom feed carries
`Datenformatbeschreibung_HK_DE.pdf` next to the ZIP.

| | URL | Verified |
|---|---|---|
| HK | `https://gdi.berlin.de/data/adressen_berlin/atom/HKO_EPSG25833.zip` | 200, 10,034,237 B |
| HK (INSPIRE AD) | `https://gdi.berlin.de/data/ad_hko/atom/AD_AdressenBerlin.zip` | 200 |
| HU | WFS `https://gdi.berlin.de/services/wfs/alkis_gebaeude` | 200, FeatureType `alkis_gebaeude:gebaeude` |

- **CRS is EPSG:25833** (UTM 33), not 25832 — Berlin/Brandenburg/MV/Sachsen sit in zone 33.
- Licence **DL-DE/Zero 2.0** — no attribution obligation at all.
- Atom entry point: `https://gdi.berlin.de/data/adressen_berlin/atom/0.atom`
- No bulk footprint file; dump via WFS `GetFeature` (offers 25832/25833/3857/4258/4326).

## Brandenburg — LGB

No dedicated HU/HK product. Footprints ride inside the **AdV-ALKIS-Shape ohne Eigentümer**
packages, one per Landkreis (18 files, 16–132 MB, all stamped 2026-07-02):

```
https://data.geobasis-bb.de/geobasis/daten/alkis/Vektordaten/shape/alkis_shape_<kreis>.zip
   kreis ∈ bar brb cb ee ff hvl lds los mol ohv opr osl p pm pr spn tf um
```

Also `…/Vektordaten/nas/` for full NAS/GML. Licence DL-DE/BY 2.0 (GeoBasis-DE/LGB).
CRS is zone 33.

## Bremen — LGeoBremen

HU via WFS only: `https://geodienste.bremen.de/wfs_alkis_hausumringe` (GetCapabilities → 200,
27 KB). CC BY 4.0, attribution "Landesamt GeoInformation Bremen". No HK bulk found.

## Hamburg — LGV

ALKIS buildings and **ALKIS Adressen** are open (DL-DE/BY 2.0) but published through the
transparency portal as INSPIRE GML snapshots + WFS rather than a stable product URL:
<https://suche.transparenz.hamburg.de> (CKAN API at `/api/3/action/package_search`).
A stable direct bulk URL was **not** pinned down in this pass — the archive URLs are
snapshot-versioned (`…_49764_snap_1.GML`).

## Hessen — HVBG

HU is free but sits behind the **Geodaten-online Downloadcenter, which requires a (free)
account**: <https://gds.hessen.de> → `ViewDownloadcenter-Start` redirects to `ViewRegistration`.
Shape, ETRS89/UTM32N, updated annually. HK not confirmed as open.

## Mecklenburg-Vorpommern — LAiV

INSPIRE Atom service, two datasets (statewide + per-Landkreis):

```
service feed : https://www.geodaten-mv.de/dienste/hausumringe_atom
dataset feed : …/hausumringe_atom?type=dataset&id=0197abd8-b048-4456-bf4a-0fb13f19bef6
file         : https://www.geodaten-mv.de/dienste/hausumringe_download
                 ?index=0&dataset=0197abd8-b048-4456-bf4a-0fb13f19bef6&file=hu-mv.zip
```

Verified 200, 117,987,716 B. Shape, **EPSG:25833**. Attribution required (© GeoBasis-DE/M-V).
No Hauskoordinaten Atom service exists (`hauskoordinaten_atom`, `hk_atom` → 404).

## Niedersachsen — LGLN

**Not open.** HK and HU are priced LGLN products. OpenGeoData.NI carries only LoD1/LoD2 3D
building models (footprints are derivable from those) — the portal bundle contains no
"Hausumring"/"Hauskoordinate" reference at all.

## Nordrhein-Westfalen — Geobasis NRW

Best-documented open source of the lot, **DL-DE/Zero 2.0**, with JSON/XML directory indexes.

| | URL | Verified |
|---|---|---|
| HK-equivalent | `https://www.opengeodata.nrw.de/produkte/geobasis/lk/akt/gebref_txt/gebref_EPSG25832_ASCII.zip` | 200, 96,902,046 B, 2026-03-11 |
| HU-equivalent | `…/lk/akt/gru_vereinfacht_gpkg/gru_vereinf_<AGS>_<Name>_EPSG25832_GeoPackage.zip` | 200, index listed |

- "Gebäudereferenzen" (`gebref`) = NW's Hauskoordinaten analogue, ASCII, statewide, EPSG:25832.
- "Grundrissdaten vereinfacht" = simplified footprints, GeoPackage, **one ZIP per Kreis /
  kreisfreie Stadt** (e.g. `gru_vereinf_05711000_Bielefeld_EPSG25832_GeoPackage.zip`, 74 MB).
- Full ALKIS NAS at `…/lk/akt/gru_xml/`.
- Each directory returns a machine-readable index: JSON for `gebref_txt`, XML for
  `gru_vereinfacht_gpkg` — so a downloader never has to hard-code the file list.

## Rheinland-Pfalz — LVermGeo

**The cleanest match to this repo's existing pattern** — same `geobasis-rlp.de` tree and same
Metalink-4 manifests as `download_rlp_lidar.sh`.

| | ZIP | Manifest |
|---|---|---|
| HU | `https://geobasis-rlp.de/data/hu/current/zip/HAUSUMRINGE_RP.zip` (243 MB, 2026-01-16) | `…/hu/current/meta4/hu_zip_07.meta4` |
| HK | `https://geobasis-rlp.de/data/hk/current/zip/HAUSKOORDINATEN_RP.zip` (25 MB, 2026-06-19) | `…/hk/current/meta4/hk_zip_07.meta4` |

DL-DE/BY 2.0, attribution `©GeoBasis-DE / LVermGeoRP <year>, dl-de/by-2-0, www.lvermgeo.rlp.de`.
The `.meta4` files carry size + SHA-256, so `aria2c --metalink-file=…` works exactly as for the
LiDAR products.

## Saarland

HU via INSPIRE WFS only, CC BY 4.0:

```
https://geoportal.saarland.de/mapbender/php/wfs.php
  ?INSPIRE=1&FEATURETYPE_ID=2058&REQUEST=GetCapabilities&SERVICE=WFS&VERSION=2.0.0
```

Verified 200, 16.5 KB capabilities. No HK bulk found.

## Sachsen — GeoSN

Served from a Nextcloud public share. **`HEAD` returns 401 — use `GET`** (range request
returns 206); any downloader must not probe with `HEAD` here.

| | URL | Verified |
|---|---|---|
| HK | `https://geocloud.landesvermessung.sachsen.de/public.php/dav/files/B3HnXbDDgAkw69a/hk_sn_ascii.zip` | 206 on ranged GET, ~20 MB, CSV |
| HU | `https://geocloud.landesvermessung.sachsen.de/public.php/dav/files/AcAqRn4k9Sz8ZZx/hu_sn_shape.zip` | 206 on ranged GET, ~210 MB, Shape |

Quarterly. Landing pages: `geodaten.sachsen.de/downloadbereich-hauskoordinaten-4172.html`,
`…-hausumringe-4174.html`. The share tokens are embedded in those pages — **re-scrape the
landing page rather than hard-coding the token**, in case GeoSN re-shares.

## Sachsen-Anhalt — LVermGeo LSA

```
HU: https://www.geodatenportal.sachsen-anhalt.de/gfds_webshare/download/LVermGeo/Geodatenportal/content/Hausumringe.zip
```

Verified 200, 141,904,618 B. Shape, EPSG:25832, **>1.6 M** records, 2×/year.
`Hauskoordinaten.zip` at the same path → 404: HK is issued on request (68 €/200 objects) or
via the ZSHH, **not** as a self-service file.

## Schleswig-Holstein — LVermGeo SH

Both HU and HK are free, but only through an interactive **gaialight Downloadclient**:

- `https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/dl-hu_alkis.html`
- `https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/dl-hk_alkis.html`
  ("Hauskoordinaten aus ALKIS **ohne PLZ-Abgleich**")

The client posts selections to `multi.php` and builds a ZIP per order; object type is
`hu_alkis` / `hk_alkis`, download params `type`/`file`/`id`. `rss.php?type=hu_alkis` rejected
every type spelling tried, so the file list could not be enumerated headlessly in this pass.
Note `https://opengeodata.schleswig-holstein.de/` returns **403 to any non-browser client**.

## Thüringen — TLBG

HU and HK have been open since 2017 under DL-DE/BY 2.0 via `geoportal-th.de`. The download
endpoint exists (`https://geoportal.thueringen.de/gaialight-th/_apps/dladownload/dl-hu.php`
→ 200) but every response is a **Link11 CAPTCHA page**, so scripted access is blocked.

---

# 3. What this means for a downloader

1. **Nine states can be scripted for footprints today** (BW, BY, MV, NW, RP, SN, ST + BB via
   the ALKIS packages, HB/SL via WFS dump) and **five for addresses** (BW, BE, NW, RP, SN).
2. **Mind the CRS split.** HU-DE/HK-DE are uniformly EPSG:25832, but BE, BB, MV and SN publish
   in **EPSG:25833**. Anything nationwide has to reproject.
3. **Schemas do not match.** Only Berlin ships documented HK-DE format. NW calls it
   Gebäudereferenzen, BW drops the postal fields, SH drops the PLZ-Abgleich. A normalised
   `AGS/ARS/OI/GFK` table is real work, not a `cat`.
4. **Three access patterns beyond plain HTTP:** account login (HE), CAPTCHA (TH), interactive
   order client (SH). None of these can be automated cleanly; they'd stay manual, or come from
   the BKG product if you're eligible.
5. **Two traps worth encoding:** Sachsen rejects `HEAD` (401) — use ranged `GET`; and
   Schleswig-Holstein's opengeodata host 403s any non-browser User-Agent.
6. **NW and RP are the models to copy** — both publish machine-readable indexes
   (JSON/XML directory listings, Metalink-4 with SHA-256), so the tile list is never
   hard-coded, exactly like the existing LiDAR scripts.

---

# Sources

**Federal (BKG / AdV / ZSHH)**
- HU-DE product page: <https://gdz.bkg.bund.de/index.php/default/amtliche-hausumringe-deutschland-hu-de.html>
- HK-DE product page: <https://gdz.bkg.bund.de/index.php/default/amtliche-hauskoordinaten-deutschland-hk-de.html>
- HU-DE documentation (PDF): <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hu-de.pdf>
- HK-DE documentation (PDF): <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hk-de.pdf>
- BKG open-data tree: <https://daten.gdz.bkg.bund.de/produkte/> · INSPIRE Atom: <https://sg.geodatenzentrum.de/web_download/>
- ZSHH / AdV product sheets: <https://www.adv-online.de/AdV-Produkte/Standards-und-Produktblaetter/ZSHH/>
- HU-DE metadata record: <https://gdk.gdi-de.org/geonetwork/srv/api/records/1B659395-6014-4B90-9B48-ACCDECF27518>

**States**
- BW: <https://opengeodata.lgl-bw.de> · <https://www.lgl-bw.de/Produkte/Liegenschaftskataster/Hausumringe/index.html>
- BY: <https://geodaten.bayern.de/opengeodata/OpenDataDetail.html?pn=hausumringe> · <https://www.ldbv.bayern.de/produkte/liegenschaftsinformationen/hausumringe.html>
- BE: <https://daten.berlin.de/datensaetze/alkis-berlin-gebaude-wfs-728b368a> · <https://gdi.berlin.de>
- BB: <https://data.geobasis-bb.de/geobasis/daten/alkis/>
- HB: <https://metaver.de/trefferanzeige?docuuid=3B7D90CD-9CF7-46B5-BB9D-B290F2EAEF8A> · <https://www.govdata.de/suche/daten/alkis-hausumringe-land-bremen>
- HH: <https://suche.transparenz.hamburg.de>
- HE: <https://hvbg.hessen.de/liegenschaftskataster/amtliche-hausumringe-deutschland> · <https://gds.hessen.de>
- MV: <https://www.geoportal-mv.de/portal/Suche/Metadatenuebersicht/Details/Downloaddienst%20Hausumringe%20MV%20(ATOM_MV_HU)/e95190f3-1fb7-4416-8f66-2cb5311e2816>
- NI: <https://www.lgln.niedersachsen.de/startseite/geodaten_karten/liegenschaftsinformationen_aus_alkis/hauskoordinaten_hausumringe/hauskoordinaten-und-hausumringe-90177.html> · <https://opengeodata.lgln.niedersachsen.de/>
- NW: <https://www.opengeodata.nrw.de/produkte/geobasis/lk/> · <https://open.nrw/dataset/407373a2-422c-469c-a7e9-06a62b4d7d9a>
- RP: <https://geobasis-rlp.de/data/> · <https://lvermgeo.rlp.de/geodaten-geoshop/open-data>
- SL: <https://gdk.gdi-de.org/geonetwork/srv/api/records/3214c97e-5ff5-1ec1-50dc-713f84af0ecd>
- SN: <https://www.geodaten.sachsen.de/downloadbereich-hauskoordinaten-4172.html> · <https://www.geodaten.sachsen.de/downloadbereich-hausumringe-4174.html>
- ST: <https://www.lvermgeo.sachsen-anhalt.de/de/gdp-hausumringe.html> · <https://www.lvermgeo.sachsen-anhalt.de/de/gdp-amtliche-hauskoordinaten-lsa.html>
- SH: <https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/> · <https://www.schleswig-holstein.de/DE/landesregierung/ministerien-behoerden/LVERMGEOSH/Service/serviceGeobasisdaten/geodatenService_Geobasisdaten_sonstigeDaten>
- TH: <https://geomis.geoportal-th.de/geonetwork/srv/api/records/dd467a9a-c5a7-400e-90b0-aeb1cba90eda> · <https://geoportal.thueringen.de/gdi-th/download-offene-geodaten>

**Background**
- WIK study, open cadastral data in Germany: <https://www.wik.org/fileadmin/files/_migrated/news_files/WIK-Kurzstudie_Offene-Katasterdaten.pdf>
