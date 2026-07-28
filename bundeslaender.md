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

## Notes

- Area and population figures are rounded; population is roughly early-2020s.
- ISO codes are the `DE-xx` subdivision codes, commonly used in datasets and
  shapefiles (e.g. NUTS-1 regions map 1:1 onto the Bundesländer).
- LiDAR tile counts and volumes are what the sources reported on 2026-07-28; the
  downloaders recompute them at runtime (`DRY_RUN=1`), so treat the table as indicative.
  Coverage grows as new flight campaigns are released — Brandenburg's point cloud in
  particular is still only partial.
