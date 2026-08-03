# German cadastre products — parcels, buildings, addresses

Everything ALKIS-derived that you might want as a file: parcel polygons (**Flurstücke**),
building footprint polygons (**Hausumringe**) and addressed building points
(**Hauskoordinaten**). Where each one actually comes from, which ones a script can fetch, and
what the paid routes cost.

All URLs and figures below were probed live: the state sources and HK/HU on **2026-07-28**,
the federal and commercial ones on **2026-07-29**. Status columns say what was verified.

**The short version.** The same office — the **ZSHH** at the LDBV Bayern — assembles all three
nationwide products, but they are not sold on the same terms. **HU-DE** and **HK-DE** are
**€0.00 and licence-gated**; **FS-DE** (parcels) is **priced**, *ab* €27,000 for 15 states,
plus €56,000 for Bayern as **FS-BY**, so roughly **€83,000** for all 16. Do not read the free
fee across from one to the other. None of the three has a download endpoint of any kind.

Meanwhile the states publish their own ALKIS-derived data under the EU High-Value-Datasets
rules: **14 states** for vector parcels, **9** for footprints, **5** for addresses, all
scriptable today. Around both sits a private market — bulk enriched datasets, area-of-interest
procurement at official fees, and per-object retail — mapped in
[§4](#4-the-commercial-provider-landscape).

---

# 1. The three products and their routes

| | **Flurstücke** (parcels) | **Hausumringe** (footprints) | **Hauskoordinaten** (addresses) |
|---|---|---|---|
| Open, per state | ✅ **14 states** vector — `download_alkis.sh <id>` | ✅ **9 states** scriptable | ✅ **5 states** scriptable |
| Federal product | **FS-DE** | **HU-DE** | **HK-DE** |
| Federal fee | **ab €27.000** (+ €56.000 Bayern) | **€0.00**, licence-gated | **€0.00**, licence-gated |
| Federal delivery | physical media, posted | gdz.bkg.bund.de account, 5–10 days | gdz.bkg.bund.de account, 5–10 days |
| Automatable? | ❌ never | ❌ credentialed only | ❌ credentialed only |

The open route is the only one a downloader can use, for any of the three. Everything federal
is an order, not a URL — [§2.5](#25-no-endpoint-either-way).

## What the parcel money actually buys

Only two parcel gaps remain in the open route — BY and RP, see
[The two content gaps](README_download.md#the-two-content-gaps).

| | Open (`download_alkis.sh`) | FS-DE (ZSHH) | FS-BY (LDBV) |
|---|---|---|---|
| States | 14 vector + BY/RP raster | **15** — all but Bayern | Bayern only |
| Fills **RP** | ❌ raster only | ✅ | — |
| Fills **BY** | ❌ raster only | ❌ | ✅ |
| Cost | €0 | **from €27,000** | **€56,000** |

The table compares the two *official* routes. There is a third for RP: the CISS-Shop sells RP
vector ALKIS for a chosen polygon at official state fees, far below a statewide licence —
[§4.2](#42-area-of-interest-procurement--the-model-closest-to-this-repo).

So the €27,000 buys one state's worth of new geometry — Rheinland-Pfalz — on top of 14 that are
already free. **Sachsen-Anhalt used to be counted here as a second gap and is not one**: it
publishes an open ALKIS WFS, verified 2026-07-29. Bayern is the expensive one: **40% of the
total bill for ~17% of the parcels**, and the single state no route makes free.

What you also buy, for the 14 states you could have fetched yourself: one schema instead of
fifteen, one CRS decision, one quarterly cycle, and no [NAS](README_download.md#nas--the-exchange-format)
parsing. That is the real product — convenience, not coverage.

---

# 2. The federal channel: AdV · ZSHH · BKG

All three nationwide datasets are assembled by the **ZSHH** (*Zentrale Stelle Hauskoordinaten
und Hausumringe*, hosted at the *Landesamt für Digitalisierung, Breitband und Vermessung*
Bayern) from the state cadastres, and distributed by the **BKG**. AdV set the arrangement up so
buyers sign one contract instead of negotiating with 16 state agencies.

One office, one model — but **two different commercial regimes**, which is the trap:

| | HU-DE / HK-DE | **FS-DE** |
|---|---|---|
| Fee | **€0.00**, licence-gated (V GeoBund / V GeoLänder) | **ab €27.000** — 15 states, no Bayern |
| Bayern | included | sold separately as **FS-BY**, **€56.000** (LDBV) |
| Delivery | gdz.bkg.bund.de account → download link, 5–10 days | **physical media**, posted |
| Licence | V GeoBund / V GeoLänder eligibility | AdV-GR + AGNB |

The €0.00 on the HK/HU pages is a *licence gate*, not a price list that extends across the ZSHH
catalogue.

## 2.1 HU-DE / HK-DE — free, licence-gated

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

Both are **€0.00 but licence-gated**. Eligibility is limited to federal authorities and
authorised parties under *V GeoBund*, and state authorities and authorised parties under
*V GeoLänder*. Everyone else is referred to the ZSHH.

Delivery is **order in the gdz.bkg.bund.de account → download link appears in that account
within 5–10 days**.

Docs (public, no login):
- <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hu-de.pdf>
- <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hk-de.pdf>

## 2.2 FS-DE / FS-BY — priced

**FS-DE** — *Amtliche Flurstücksinformationen Deutschland*. The AdV parcel product.

| | |
|---|---|
| Content | georeferenced Umringpolygone of all Flurstücke — **geometry only** |
| Records | ~54 million |
| Coverage | 15 states — BW, BE, BB, HB, HH, HE, MV, NI, NW, **RP**, SL, SN, ST, SH, TH. **No Bayern** |
| Attributes | Objektidentifikator · ALKIS-Flurstückskennzeichen · Gemarkung + Flurstücksnummer · AGS · textual Lagebezeichnung |
| Not included | **owners** (as everywhere), **tatsächliche Nutzung**, Grenzpunkte — the polygons carry no boundary points |
| Format | Shapefile |
| CRS | ETRS89 / UTM **zone 32 or 33** (per state, same split as the open data) |
| Update | quarterly |
| Spec | FS-DE DFB V 1.2.1, DE + EN PDFs on the ZSHH page |
| Fee | **ab 27.000 €** — the page says only "from", and invites a conversation |
| Licence | AdV-Gebührenrichtlinie (**AdV-GR**) + **AGNB** |
| Order | zshh@ldbv.bayern.de · +49 89 2129-1299 |

**Test data is free.** The ZSHH page carries an `FS-DE-2026` sample Shapefile (~1.7 MB zip) —
enough to check the schema against what `download_alkis.sh` already produces before contacting
anyone.

Two things the sources do not say, and which have to be asked:

- **Whether €27,000 is annual or one-off.** The page states a figure and an update cycle, not
  a term.
- **Redistribution.** Governed by the AGNB, not summarised on the product page. Assume a
  derivative you publish needs its own clearance.

**FS-BY** — Bayern does not enter FS-DE. Its parcels are a standalone LDBV product on the same
technical terms and a much steeper fee.

| | |
|---|---|
| Content | Umringpolygone of all Flurstücke in Bayern |
| Format | Shapefile, ETRS89/UTM32 **and** UTM33 (delivered without zone number) |
| Update | quarterly |
| Fee | **56.000,00 €** statewide — Bayerische Vermessungsverwaltung GebPL, Teil B Nr. 7.8 |
| Order | service@geodaten.bayern.de |

This is the same wall the repo already hits from the open side: Bayern publishes the
*ALKIS-Parzellarkarte* as raster, and vector parcels are a sale — GeodatenOnline retail, or
FS-BY in bulk. Bayern is also the outlier for addresses: its Hausumringe are open, its
Hauskoordinaten are not — [§3](#3-open-data-equivalents-per-bundesland).

## 2.3 Why "65 million" appears everywhere

[AdV's FS-DE page](https://www.adv-online.de/AdV-Produkte/Liegenschaftskataster/Amtliche-Folgeprodukte/Amtliche-Flurstuecksinformationen/)
advertises *"rund 65 Mio. FS-DE ... deutschlandweit flächendeckend"*, while the ZSHH product
page states ~54 million and excludes Bayern. **54M + Bavaria's ~11M ≈ 65M** — AdV is
describing the product family, ZSHH the actual deliverable. That reconciliation is an
inference from the two figures; neither page states it. Take 65 million as a marketing total
covering two separate invoices.

## 2.4 What the BKG channel adds

[BKG sells FS-DE too](https://gdz.bkg.bund.de/index.php/default/flurstuecksinformationen-deutschland-fs-de.html),
except it does not sell it:

> Bereitstellung für Bundesbehörden und Nutzungsberechtigte nach V GeoBund

Federal authorities and V-GeoBund-authorised parties only, official duties, no resale, no
relicensing. Attribution `Geobasis-DE / BKG (Jahr des letzten Datenbezugs)`. Everyone else is
referred to the ZSHH — **exactly the HK-DE/HU-DE pattern**, which is why the two halves of this
document share an access story.

Worth recording because the BKG listing is the more informative of the two pages:

| | |
|---|---|
| Formats | **SHAPE 10 GB · Esri FileGDB 20 GB · GeoPackage 34 GB** (uncompressed) |
| CRS | the BKG page says UTM32 only, where ZSHH says 32 *or* 33 — resolve before ordering |
| Stand | März 2026, quarterly |
| Delivery | **physical USB drive, posted, 5–10 days — and returned to BKG afterwards** |

## 2.5 No endpoint, either way

Neither the free products nor the paid one is reachable by script. The same two negative
searches cover all three:

- `https://daten.gdz.bkg.bund.de/produkte/` holds only `aerial`, `basiskarten`, `dgm`, `dlm`,
  `dtk`, `sonstige`, `topplus_open`, `vg` — **no `hu`/`hk`, and no cadastre**. Searching the
  107-product open-data catalogue for ALKIS returns DLM and landcover products, never a
  cadastre.
- The BKG INSPIRE Atom download service at `https://sg.geodatenzentrum.de/web_download/`
  lists 26 datasets — **zero** matching "haus".

So there is no `.meta4`-style manifest to hand to `aria2c` the way `download_rlp_lidar.sh` does.
**A BKG downloader can only ever be a credentialed one**, and for FS-DE not even that — it
arrives by post, so **no downloader can ever be written against it**, credentialed or not.

---

# 3. Open-data equivalents, per Bundesland

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
repo — see [The state ID](README_download.md#the-state-id)

**Scriptable today: 9 states for HU, 5 states for HK.** For parcels it is 14 — see
`download_alkis.sh`.

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

**HU only.** Hauskoordinaten remain a priced LDBV product — Bayern is the outlier here, as it
is for parcels ([§2.2](#22-fs-de--fs-by--priced)).

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

Note the asymmetry: RP is generous with buildings and addresses, and is one of the two
**parcel** gaps — its vector Flurstücke are sold, not published
([§4.2](#42-area-of-interest-procurement--the-model-closest-to-this-repo)).

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

Second route, added 2026-07-29: `ave:GebaeudeBauwerk` (~1.7 M) in the open ALKIS WFS —
`./download_alkis.sh st gebaeude`. The ZIP is still the faster fetch; the WFS wins if you want
footprints and parcels from one source with matching keys. That same WFS is why ST is no longer
counted as a parcel gap.

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

# 4. The commercial provider landscape

Beyond the AdV channel there is a real market, surveyed **2026-07-29**. Four business models.
Only the first sells you a nationwide file, and **not one of them publishes a price**. Almost
every vendor sells parcels and buildings together, which is why this survey covers both.

## 4.1 Bulk value-added datasets — one purchase, one file

The polygons underneath are the same AdV geometry. What you pay for is the join, the derived
attributes and a simpler licence.

| Provider | Product | Scale | What is actually new in it |
|---|---|---|---|
| **geomer** (Heidelberg) | `fullHAUSde` | **57.5 M buildings**, updated **annually** | Outline geometry *plus* ~18 derived attributes: Basishöhe, Dachform, Gebäudehöhe/-volumen/-oberfläche, Gebäudealtersklasse, Gebäudetyp, Nutzung, Stockwerksanzahl, Heizungsart, Energieträger, Energiebezugsfläche, Wohnfläche, Einwohnerzahl, Vermögenswert, eindeutige Gebäude-ID |
| **infas 360** (Bonn) | `CASA Flurstücke` + Gebäudedaten | **65 M parcels** — nationwide **incl. Bayern** | The only vendor found selling parcels *and* buildings on one key system. Parcels pre-joined to Hauskoordinaten, building references and tatsächliche Nutzung; buildings carry Baujahrsklasse, Energieeffizienz, Haushaltszahl, Dach- und Höheninformationen |
| **Nexiga** (Bonn) | Hausdatenbank | **28 M houses** | Different provenance entirely — built from physical on-site surveys begun in the 1980s and repeated through the 1990s. Nine base attributes: Gebäudealter, Bauweise, Gartenart/-größe, Gebäudetyp, Lage im Ort, Wohnlage, Straßenart, Gestaltung, Pflegezustand |
| **microm** | Geomarketing data | address-level | Zielgruppenmodelle, Konsumenten-, Lage- und Standortdaten with building typology attached. Not a parcel source |

**Nexiga is the one that is not a repackaging of ALKIS.** Condition, garden, street character
and Wohnlage are survey judgements; no amount of open data reproduces them. geomer's energy
and volume fields are modelled, but modelled *once*, statewide, which is the expensive part.

## 4.2 Area-of-interest procurement — the model closest to this repo

**CISS TDI GmbH** (Sinzig) runs the **CISS-Shop**: define an area, get official ALKIS back.

- Area by **drawn polygon**, by **uploaded coordinate list**, or by naming **Flurstücke with a
  buffer along them** — deliberately independent of Gemarkung and municipal boundaries
- Output as **DXF, Shape, or raw NAS/XML** from the official interface
- **Price is the official state fee**, computed from area / object count and shown before you
  order — not a vendor licence. Adjust the polygon, watch the number move
- States live today: **RP, BB, NI, HH, NW, BE, TH**; cross-state orders accepted; more "will
  follow"
- **Hausumringe and Hauskoordinaten nationwide** through the same shop. Their HK is enriched
  with extra address fields from Deutsche Post Direkt
- Tooling sold alongside: `CISS.Konverter2go` (GeoInfoDok 7 ALKIS → DXF/SHP into a
  Geodata-Warehouse), `CISS.Map2go` (nationwide WMS/WFS of Flurstücke, Hausumringe,
  Siedlungsflächen), `CISS.Geo2go`, `CITRA`

**This is the route to Rheinland-Pfalz vector parcels.** RP holds vector ALKIS and sells it
under its official fee schedule; only the *open-data* publication is rasterised. So RP's gap is
a per-area purchase at state fees, not the €27,000 FS-DE licence — see
[§5](#5-what-this-means-for-this-repo). It is also the one commercial route that answers the
priced HU/HK states, NI and BY, without a statewide licence.

## 4.3 Data-as-a-Service and per-object retail

Billed per lookup. Right for hundreds of parcels, wrong shape for a bulk pipeline.

| Provider | Model |
|---|---|
| **datenservice.plus** | DaaS for insurers, banks and real estate. Claims **65 M Flurstücke, 57 M Gebäudedaten, 25 M queries** served, via API and web app |
| **geoindex.io** | Parcel search engine, **all 16 states**. Search by address, Flurstück, coordinates or an uploaded Google Earth KMZ; returns Liegenschaftskarte (Katasterauszug) or Flurstücksgeometrie immediately |
| **on-geo** (München) | `geoport` — the largest German-language webshop for property data and documents (Grundbuch, Flurkarten). Also `Lora` (Beleihungswert), `Accumate` (AVM) |
| **Sprengnetter** | Valuation ecosystem and Marktdatenportal, BaFin/EBA-oriented; data arrives as part of the AVM rather than as a dataset |
| **grundbuchplus.de**, **flurcheck.de** | Same per-object retail model |

## 4.4 3D building models

**virtualcitySYSTEMS** (`vc.systems`, founded Chemnitz 2005) is the leading German name here,
but they sell **software and services** around digital twins — they build on the states'
official LoD2, they do not license a nationwide building dataset.

Worth knowing before paying anyone for 3D: the BKG open-data catalogue already carries
**3D Tiles basemap.de 3D Gebäude** and **3D Gelände** as open data. Nationwide 3D buildings
need no vendor at all. Niedersachsen's own LoD1/LoD2 is also the back door to NI footprints,
which are otherwise priced.

---

# 5. What this means for this repo

## Downloaders

1. **Nine states can be scripted for footprints today** (BW, BY, MV, NW, RP, SN, ST + BB via
   the ALKIS packages, HB/SL via WFS dump) and **five for addresses** (BW, BE, NW, RP, SN).
   Parcels are further along at 14 — `download_alkis.sh`.
2. **Mind the CRS split.** HU-DE/HK-DE are uniformly EPSG:25832, but BE, BB, MV and SN publish
   in **EPSG:25833**, and FS-DE ships zone 32 *or* 33 per state. Anything nationwide has to
   reproject.
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

## Money

7. **Nothing paid changes the open picture.** No product unlocks a download endpoint; FS-DE is
   strictly *less* automatable than the 15 state sources, because it arrives by post.
8. **The BY gap has a price now: €56,000.** That is the honest answer to "can we complete
   Bayern" — not a scripting problem, a purchase order.
9. **Rheinland-Pfalz does not need FS-DE at all.** RP vector ALKIS is orderable from the
   CISS-Shop for a chosen polygon at **official state fees** — the state has the vectors, it
   just publishes only the raster openly. For an area of interest rather than the whole state
   this is one or two orders of magnitude below the €27,000 licence, and it arrives as
   DXF/Shape/NAS rather than by post. Check CISS before assuming the AdV route.
10. **If a whole state really is the goal**, FS-DE is still the only single-invoice way to get
    RP in bulk — ask the ZSHH about a subset price before paying for all 15.
11. **Grab the free FS-DE test Shapefile** before any of the above. Comparing its schema with
    `download_alkis.sh` output for the same area is the cheapest way to learn what the paid
    normalisation is actually worth — and it is 1.7 MB.
12. **The nationwide-single-file itch is a normalisation project, not a purchase.** Fourteen
    states already give you the geometry; what FS-DE sells on top is one schema and one CRS
    policy. That is buildable here, and the DFB V 1.2.1 spec is public — using FS-DE's field
    names as the target schema costs nothing.

---

# Sources

**Federal — HU-DE / HK-DE (BKG · AdV · ZSHH)**
- HU-DE product page: <https://gdz.bkg.bund.de/index.php/default/amtliche-hausumringe-deutschland-hu-de.html>
- HK-DE product page: <https://gdz.bkg.bund.de/index.php/default/amtliche-hauskoordinaten-deutschland-hk-de.html>
- HU-DE documentation (PDF): <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hu-de.pdf>
- HK-DE documentation (PDF): <https://sg.geodatenzentrum.de/web_public/gdz/dokumentation/deu/hk-de.pdf>
- HU-DE metadata record: <https://gdk.gdi-de.org/geonetwork/srv/api/records/1B659395-6014-4B90-9B48-ACCDECF27518>
- ZSHH / AdV product sheets: <https://www.adv-online.de/AdV-Produkte/Standards-und-Produktblaetter/ZSHH/>

**Federal — FS-DE / FS-BY (AdV · ZSHH · LDBV)**
- ZSHH product page (fee, ~54 M, test data, DFB spec): <https://www.ldbv.bayern.de/vermessung/zshh/fs-de.html>
- ZSHH overview: <https://www.ldbv.bayern.de/vermessung/zshh/>
- AdV product page (DE): <https://www.adv-online.de/AdV-Produkte/Liegenschaftskataster/Amtliche-Folgeprodukte/Amtliche-Flurstuecksinformationen/>
- AdV product page (EN): <https://www.adv-online.de/Products/Real-Estate-Cadastre/Land-Parcel-Information/>
- FS-BY product page (56.000 €): <https://www.ldbv.bayern.de/produkte/liegenschaftsinformationen/flurstuecksinfo.html>
- Bayerische Vermessungsverwaltung Gebühren- und Preisliste (GebPL, PDF): <https://www.dillingen.bayernlab.bayern.de/mam/ldbv/dateien/gebuehren_und_preisliste.pdf>

**Federal — BKG channel and open-data tree**
- FS-DE product page: <https://gdz.bkg.bund.de/index.php/default/flurstuecksinformationen-deutschland-fs-de.html>
- FS-DE announcement: <https://www.bkg.bund.de/SharedDocs/Produktinformationen/BKG/DE/P-2025/250704_FS-DE.html>
- Open-data catalogue (107 products, no cadastre): <https://gdz.bkg.bund.de/index.php/default/open-data.html>
- Open download tree (8 categories, no cadastre, no `hu`/`hk`): <https://daten.gdz.bkg.bund.de/produkte/>
- INSPIRE Atom download service (26 datasets, zero "haus"): <https://sg.geodatenzentrum.de/web_download/>

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

**Commercial providers** (surveyed 2026-07-29)
- infas 360 — CASA Flurstücke: <https://www.infas360.de/blog-flurstuecke/> · <https://www.infas360.de/casa-plus-flurstuecke-und-mehr/> · Gebäudedaten: <https://www.infas360.de/gebaeudedaten/>
- geomer — fullHAUSde: <https://www.geomer.de/geodaten-dienste/fullhausde.html>
- Nexiga — Gebäudedaten: <https://nexiga.com/gebaeudedaten/> · Geodaten: <https://nexiga.com/daten/geodaten/>
- microm: <https://www.microm.de/daten/>
- CISS TDI — ALKIS shop: <https://www.ciss.de/geodaten-online-beschaffung/alkis/> · HU/HK: <https://www.ciss.de/geodaten-online-beschaffung/hausumringe_koordinaten/> · tools: <https://www.ciss.de/geodaten-software-und-tools/>
- datenservice.plus: <https://datenservice.plus/>
- geoindex.io: <https://geoindex.io/>
- on-geo (geoport): <https://www.on-geo.de/>
- Sprengnetter: <https://www.sprengnetter.de/>
- virtualcitySYSTEMS: <https://vc.systems/>
- Directory used to find them: <https://immobiliendatenliste.de/>

**Background**
- WIK study, open cadastral data in Germany: <https://www.wik.org/fileadmin/files/_migrated/news_files/WIK-Kurzstudie_Offene-Katasterdaten.pdf>
