# Nationwide Flurstücke — the paid routes

Vector parcel geometry for all of Germany in one purchase: what exists, what it costs, and
what it buys over the open per-state route in [`download_alkis.sh`](download_alkis.sh).

All URLs and figures below were probed live on **2026-07-29**.

**The short version.** There is exactly one official nationwide parcel product, **FS-DE**, and
it is sold in two pieces — *ab* €27,000 for 15 states from the ZSHH, plus €56,000 for Bayern
from the LDBV. Roughly **€83,000 for all 16 states**. Nothing about it is open data, and
there is no download endpoint of any kind: FS-DE ships on physical media.

Around that sits a private market — bulk enriched datasets, area-of-interest procurement at
official fees, and per-object retail. [§5](#5-the-commercial-provider-landscape) maps it, and
covers **building** data too, since almost every vendor sells parcels and buildings together.

---

# 1. What the money actually buys

The open route already delivers full vector ALKIS for **13 states**. The three gaps — BY, RP,
ST, see [The three content gaps](README.md#the-three-content-gaps) — are exactly what the paid
route closes, and it is the only thing that closes them.

| | Open (`download_alkis.sh`) | FS-DE (ZSHH) | FS-BY (LDBV) |
|---|---|---|---|
| States | 13 vector + BY/RP raster | **15** — all but Bayern | Bayern only |
| Fills **RP** | ❌ raster only | ✅ | — |
| Fills **ST** | ❌ not published | ✅ | — |
| Fills **BY** | ❌ raster only | ❌ | ✅ |
| Cost | €0 | **from €27,000** | **€56,000** |

The table compares the two *official* routes. There is a third for RP: the CISS-Shop sells RP
vector ALKIS for a chosen polygon at official state fees, far below a statewide licence —
[§5.2](#52-area-of-interest-procurement--the-model-closest-to-this-repo).

So the €27,000 is mostly paying again for data 13 states already give away — what is *new* in
it is Rheinland-Pfalz and Sachsen-Anhalt. Bayern is the expensive one: **40% of the total bill
for ~17% of the parcels**, and the single state no route makes free.

What you also buy, for the 13 states you could have fetched yourself: one schema instead of
fifteen, one CRS decision, one quarterly cycle, and no NAS parsing. That is the real product —
convenience, not coverage.

---

# 2. FS-DE — Amtliche Flurstücksinformationen Deutschland

The AdV product. Assembled by the **ZSHH** (*Zentrale Stelle Hauskoordinaten und Hausumringe*,
hosted at the LDBV Bayern) from the state cadastres — the same office and the same model as
HK-DE/HU-DE in [`hauskoordinaten-hausumringe.md`](hauskoordinaten-hausumringe.md). AdV set it
up so buyers sign one contract instead of negotiating with 16 state agencies.

| | |
|---|---|
| Content | georeferenced Umringpolygone of all Flurstücke — **geometry only** |
| Records | ~54 million |
| Coverage | 15 states — BW, BE, BB, HB, HH, HE, MV, NI, NW, **RP**, SL, SN, **ST**, SH, TH. **No Bayern** |
| Attributes | Objektidentifikator · ALKIS-Flurstückskennzeichen · Gemarkung + Flurstücksnummer · AGS · textual Lagebezeichnung |
| Not included | **owners** (as everywhere), **tatsächliche Nutzung**, Grenzpunkte — the polygons carry no boundary points |
| Format | Shapefile |
| CRS | ETRS89 / UTM **zone 32 or 33** (per state, same split as the open data) |
| Update | quarterly |
| Spec | FS-DE DFB V 1.2.1, DE + EN PDFs on the ZSHH page |

## Buying it

| | |
|---|---|
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

---

# 3. FS-BY — Bayern, sold separately

Bayern does not enter FS-DE. Its parcels are a standalone LDBV product on the same technical
terms and a much steeper fee.

| | |
|---|---|
| Content | Umringpolygone of all Flurstücke in Bayern |
| Format | Shapefile, ETRS89/UTM32 **and** UTM33 (delivered without zone number) |
| Update | quarterly |
| Fee | **56.000,00 €** statewide — Bayerische Vermessungsverwaltung GebPL, Teil B Nr. 7.8 |
| Order | service@geodaten.bayern.de |

This is the same wall the repo already hits from the open side: Bayern publishes the
*ALKIS-Parzellarkarte* as raster, and vector parcels are a sale — GeodatenOnline retail, or
FS-BY in bulk.

## Why "65 million" appears everywhere

[AdV's FS-DE page](https://www.adv-online.de/AdV-Produkte/Liegenschaftskataster/Amtliche-Folgeprodukte/Amtliche-Flurstuecksinformationen/)
advertises *"rund 65 Mio. FS-DE ... deutschlandweit flächendeckend"*, while the ZSHH product
page states ~54 million and excludes Bayern. **54M + Bavaria's ~11M ≈ 65M** — AdV is
describing the product family, ZSHH the actual deliverable. That reconciliation is an
inference from the two figures; neither page states it. Take 65 million as a marketing total
covering two separate invoices.

---

# 4. The BKG channel — same data, no invoice, no eligibility

[BKG sells FS-DE too](https://gdz.bkg.bund.de/index.php/default/flurstuecksinformationen-deutschland-fs-de.html),
except it does not sell it:

> Bereitstellung für Bundesbehörden und Nutzungsberechtigte nach V GeoBund

Federal authorities and V-GeoBund-authorised parties only, official duties, no resale, no
relicensing. Attribution `Geobasis-DE / BKG (Jahr des letzten Datenbezugs)`. Everyone else is
referred to the ZSHH — exactly the HK-DE/HU-DE pattern.

Worth recording because the BKG listing is the more informative of the two pages:

| | |
|---|---|
| Formats | **SHAPE 10 GB · Esri FileGDB 20 GB · GeoPackage 34 GB** (uncompressed) |
| CRS | the BKG page says UTM32 only, where ZSHH says 32 *or* 33 — resolve before ordering |
| Stand | März 2026, quarterly |
| Delivery | **physical USB drive, posted, 5–10 days — and returned to BKG afterwards** |

That last row is the whole story on automation. FS-DE has no WFS, no Atom feed, no
`daten.gdz.bkg.bund.de` path — the open tree there holds only `aerial`, `basiskarten`, `dgm`,
`dlm`, `dtk`, `sonstige`, `topplus_open`, `vg`, and searching the 107-product open-data
catalogue for ALKIS returns DLM and landcover products, never a cadastre. **No downloader can
ever be written against FS-DE**, credentialed or not.

---

# 5. The commercial provider landscape

Beyond the AdV channel there is a real market, surveyed **2026-07-29**. Four business models.
Only the first sells you a nationwide file, and **not one of them publishes a price**.

## 5.1 Bulk value-added datasets — one purchase, one file

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

## 5.2 Area-of-interest procurement — the model closest to this repo

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
[§6](#6-what-this-means-for-this-repo).

## 5.3 Data-as-a-Service and per-object retail

Billed per lookup. Right for hundreds of parcels, wrong shape for a bulk pipeline.

| Provider | Model |
|---|---|
| **datenservice.plus** | DaaS for insurers, banks and real estate. Claims **65 M Flurstücke, 57 M Gebäudedaten, 25 M queries** served, via API and web app |
| **geoindex.io** | Parcel search engine, **all 16 states**. Search by address, Flurstück, coordinates or an uploaded Google Earth KMZ; returns Liegenschaftskarte (Katasterauszug) or Flurstücksgeometrie immediately |
| **on-geo** (München) | `geoport` — the largest German-language webshop for property data and documents (Grundbuch, Flurkarten). Also `Lora` (Beleihungswert), `Accumate` (AVM) |
| **Sprengnetter** | Valuation ecosystem and Marktdatenportal, BaFin/EBA-oriented; data arrives as part of the AVM rather than as a dataset |
| **grundbuchplus.de**, **flurcheck.de** | Same per-object retail model |

## 5.4 3D building models

**virtualcitySYSTEMS** (`vc.systems`, founded Chemnitz 2005) is the leading German name here,
but they sell **software and services** around digital twins — they build on the states'
official LoD2, they do not license a nationwide building dataset.

Worth knowing before paying anyone for 3D: the BKG open-data catalogue already carries
**3D Tiles basemap.de 3D Gebäude** and **3D Gelände** as open data. Nationwide 3D buildings
need no vendor at all.

---

# 6. What this means for this repo

1. **Nothing here changes the open picture.** No paid product unlocks a download endpoint;
   FS-DE is strictly less automatable than the 15 state sources, because it arrives by post.
2. **The BY gap has a price now: €56,000.** That is the honest answer to "can we complete
   Bayern" — not a scripting problem, a purchase order.
3. **Rheinland-Pfalz does not need FS-DE at all.** RP vector ALKIS is orderable from the
   CISS-Shop for a chosen polygon at **official state fees** — the state has the vectors, it
   just publishes only the raster openly. For an area of interest rather than the whole state
   this is one or two orders of magnitude below the €27,000 licence, and it arrives as
   DXF/Shape/NAS rather than by post. Check CISS before assuming the AdV route.
4. **If a whole state really is the goal**, FS-DE is still the only single-invoice way to get
   RP in bulk — ask the ZSHH about a subset price before paying for all 15.
5. **Grab the free FS-DE test Shapefile** before any of the above. Comparing its schema with
   `download_alkis.sh` output for the same area is the cheapest way to learn what the paid
   normalisation is actually worth — and it is 1.7 MB.
6. **The nationwide-single-file itch is a normalisation project, not a purchase.** Thirteen
   states already give you the geometry; what FS-DE sells on top is one schema and one CRS
   policy. That is buildable here, and the DFB V 1.2.1 spec is public — using FS-DE's field
   names as the target schema costs nothing.

---

# Sources

**FS-DE / FS-BY (AdV · ZSHH · LDBV)**
- ZSHH product page (fee, ~54 M, test data, DFB spec): <https://www.ldbv.bayern.de/vermessung/zshh/fs-de.html>
- ZSHH overview: <https://www.ldbv.bayern.de/vermessung/zshh/>
- AdV product page (DE): <https://www.adv-online.de/AdV-Produkte/Liegenschaftskataster/Amtliche-Folgeprodukte/Amtliche-Flurstuecksinformationen/>
- AdV product page (EN): <https://www.adv-online.de/Products/Real-Estate-Cadastre/Land-Parcel-Information/>
- FS-BY product page (56.000 €): <https://www.ldbv.bayern.de/produkte/liegenschaftsinformationen/flurstuecksinfo.html>
- Bayerische Vermessungsverwaltung Gebühren- und Preisliste (GebPL, PDF): <https://www.dillingen.bayernlab.bayern.de/mam/ldbv/dateien/gebuehren_und_preisliste.pdf>

**BKG**
- FS-DE product page: <https://gdz.bkg.bund.de/index.php/default/flurstuecksinformationen-deutschland-fs-de.html>
- Product announcement: <https://www.bkg.bund.de/SharedDocs/Produktinformationen/BKG/DE/P-2025/250704_FS-DE.html>
- Open-data catalogue (107 products, no cadastre): <https://gdz.bkg.bund.de/index.php/default/open-data.html>
- Open download tree (8 categories, no cadastre): <https://daten.gdz.bkg.bund.de/produkte/>

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
