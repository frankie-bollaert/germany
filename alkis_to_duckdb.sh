#!/usr/bin/env bash
#
# alkis_to_duckdb.sh — load the downloaded ALKIS data into a DuckDB database.
#
# Reads whatever ./download_alkis.sh (or ./download_all.sh alkis) has already put under
# ./alkis and populates three tables: plots, structures, structure_versions. Nothing is
# downloaded here — this script only reads what is on disk.
#
#   plots               one row per Flurstück (parcel)
#   structures          one row per building footprint identity
#   structure_versions  one row per footprint geometry, pointing at its structure
#
# Every source is a different format in a different CRS, so each one is staged through
# ogr2ogr into GeoParquet (EPSG:4326, WKB, MULTIPOLYGON) and then read by DuckDB as a glob.
# Staging is what makes the run resumable: a staged .parquet is never rebuilt, so an
# interrupted run picks up where it stopped.
#
#   state  source dir        what it yields                       format
#   -----  ----------------  -----------------------------------  --------------------------
#   bb     bb-shape          plots + structures + versions        zipped Shapefile, per Landkreis
#   be     be-flurstuecke    plots                                paged GML (WFS 2.0)
#   be     be-gebaeude       structures + versions                paged GML (WFS 2.0)
#   bw     bw-shape          plots + structures + versions        zipped Shapefile, per Gemarkung
#   by     by-hausumringe    structures + versions                zipped Shapefile, per Bezirk
#   mv     mv-nas            plots + structures + versions        zipped Shapefile, per Gemeinde
#   nw     nw                plots + structures + versions        GeoPackage, per Kreis
#   sn     sn / sn-nas       plots + structures + versions        NAS/GML in a nested zip
#
# Not loaded, and why:
#   bb-nas   the same content as bb-shape, one zip per Landkreis either way. The Shapefile
#            half is the ALKIS *vereinfacht* profile — the same attributes MV and NW publish
#            — so it needs no NAS reader and no schema pinning.
#   bw-nas   the same content as bw-shape, which is already loaded from the easier format.
#            The `nas` reader added for Sachsen would now handle it, but the download is
#            incomplete (see .download_all.failures).
#   by-tn    Tatsächliche Nutzung: land use, neither parcels nor footprints.
#   st       empty — the Sachsen-Anhalt WFS dump has not been fetched.
#   Bayern publishes no open vector Flurstücke at all, so `by` contributes no plots.
#   mv-nas   the NAS half of MV's directory: every Gemeinde is published twice, and the
#            Shapefile half carries the same content in a format that needs no NAS reader.
#   The other fetched states (hb, he, hh, ni, rp, sh, sl, th) have no entry in
#   DATASETS yet — downloads have run ahead of this loader.
#
# ---------------------------------------------------------------------------------------
# The `nas` reader (Sachsen)
# ---------------------------------------------------------------------------------------
# Sachsen publishes one statewide NAS Bestandsdatenauszug instead of per-region files, and
# it needs three things none of the other sources do. Measured on the 2026-07 export:
#
#  1. It is a zip inside a zip: alkis_sn.zip -> E_<auftrag>.zip -> 1,596 XML parts, ~95 GB
#     unzipped. Reading a part through nested /vsizip costs 88 s because a deflate member
#     cannot seek backwards -- the GML driver's rewinds restart decompression from the top,
#     twice over. The same part as a plain file parses in 0.4 s. So the inner zip is
#     unwrapped once into the staging dir (2.4 GB, cached across runs) and each part is
#     extracted to a temp file, converted, and deleted. Peak extra disk is JOBS x ~60 MB,
#     not the 95 GB a full extraction would cost.
#
#  2. The parts are split by object type, and no part holds both of the types we want:
#     AX_Flurstueck is in 569 parts, AX_Gebaeude in a disjoint 508, and 519 parts hold
#     neither. Converting all 1,596 twice would waste two thirds of the work, so the
#     archive is indexed once (parts.index, ~30 s) and each dataset visits only its own.
#
#  3. The parts do not share a schema. AX_Flurstueck comes in 3 variants and AX_Gebaeude in
#     8; zeitpunktDerEntstehung is absent from 25 of the 569 parcel parts and
#     gebaeudekennzeichen from 103 of the 508 building parts. ogr2ogr -select is fatal on a
#     field the source lacks, so a fixed .gfs -- generated once from a part that carries the
#     full field list -- is placed next to every extracted part. That pins one schema for
#     the whole dataset and turns a missing field into NULL instead of an aborted run.
#
# Two smaller NAS quirks, both handled in stage_one:
#   · srsName is the AdV URN "urn:adv:crs:ETRS89_UTM33", which GDAL does not resolve, so the
#     layer reports no SRS. srs_for() supplies -s_srs EPSG:25833 explicitly.
#   · Geometry is CurvePolygon: ALKIS uses circular arcs. -nlt MULTIPOLYGON linearises them.
#
# Usage : ./alkis_to_duckdb.sh [db_path]
#   ./alkis_to_duckdb.sh                       # -> ./alkis.duckdb, every state on disk
#   ./alkis_to_duckdb.sh /mnt/big/germany.duckdb
#   STATES="be nw" ./alkis_to_duckdb.sh        # two states only
#   ./alkis_to_duckdb.sh --list                # what is on disk and what it would produce
#
# Env vars (override defaults):
#   ALKIS_DIR=./alkis      where the downloaders wrote their output
#   STAGE_DIR=<alkis>/.duckdb-stage   GeoParquet staging (resume state lives here)
#   STATES="be bw by nw"   restrict to these states
#   KINDS="plots structures"          restrict to one of the two table groups
#   JOBS=4                 concurrent ogr2ogr processes
#   DRY_RUN=1              print the plan, touch nothing
#   KEEP_STAGE=1           0 = delete each dataset's staging once it has loaded
#   FALLBACK_DATE=         valid_from for rows whose source carries no date (default: the
#                          newest source file's mtime for that dataset)
#   MEMORY_LIMIT=          passed to DuckDB's memory_limit, e.g. 8GB
#
set -euo pipefail

ALKIS_DIR="${ALKIS_DIR:-./alkis}"
STAGE_DIR="${STAGE_DIR:-$ALKIS_DIR/.duckdb-stage}"
JOBS="${JOBS:-4}"
DRY_RUN="${DRY_RUN:-0}"
KEEP_STAGE="${KEEP_STAGE:-1}"
FALLBACK_DATE="${FALLBACK_DATE:-}"
MEMORY_LIMIT="${MEMORY_LIMIT:-}"

usage() {
  cat >&2 <<'EOF'
Usage: ./alkis_to_duckdb.sh [db_path]

  db_path  DuckDB file to create or extend (default ./alkis.duckdb)

Env: ALKIS_DIR=./alkis STATES="be nw" KINDS="plots structures" JOBS=4 DRY_RUN=1 KEEP_STAGE=1
EOF
  exit 2
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: $1 not found. Install it:  brew install $2  (macOS)  |  apt install $2 (Debian/Ubuntu)" >&2
    exit 1
  }
}

# ---------------------------------------------------------------------------------------
# The dataset table. One line per (state, kind, source directory, layer, reader).
#
# The reader decides how a source file becomes an OGR datasource:
#   gml     the file itself
#   gpkg    the file itself, layer given
#   zipshp  /vsizip/<file>/<layer>.shp
#   nas     one XML part of a nested-zip NAS archive, extracted on the fly (see above)
#
# The source dir may list alternatives separated by `|`; the first one that exists and has
# matching files wins. Sachsen needs this because the two downloaders disagree on where it
# lands: ./download_alkis.sh sn writes alkis/sn, while download_all.sh sets OUTDIR and
# writes alkis/sn-nas. Accepting both is what stops SN from being silently skipped.
# ---------------------------------------------------------------------------------------
DATASETS=(
  "bb plots      bb-shape        Flurstueck        zipshp  *.zip"
  "bb structures bb-shape        GebauedeBauwerk   zipshp  *.zip"
  "be plots      be-flurstuecke  flurstuecke       gml     *.gml"
  "be structures be-gebaeude     gebaeude          gml     *.gml"
  "bw plots      bw-shape        flurstueck        zipshp  *.zip"
  "bw structures bw-shape        gebaeudeBauwerke  zipshp  *.zip"
  "by structures by-hausumringe  hausumringe       zipshp  *.zip"
  # MV ships every Gemeinde twice, once as NAS and once as Shapefile, into the same
  # directory. The glob has to say _SHP_ or the 724 NAS zips are picked up as well and
  # every one of them fails: /vsizip/<nas>.zip/Flurstueck.shp does not exist.
  "mv plots      mv-nas          Flurstueck        zipshp  *_SHP_*.zip"
  "mv structures mv-nas          GebaeudeBauwerk   zipshp  *_SHP_*.zip"
  "nw plots      nw              Flurstueck        gpkg    *.gpkg"
  "nw structures nw              GebauedeBauwerk   gpkg    *.gpkg"
  "sn plots      sn|sn-nas       AX_Flurstueck     nas     *.zip"
  "sn structures sn|sn-nas       AX_Gebaeude       nas     *.zip"
)

# Source CRS, for the readers whose driver cannot work it out. Only NAS needs this: its
# srsName is an AdV URN that GDAL does not resolve, leaving the layer with no SRS at all.
# Everything else reports its own CRS and must be left alone.
srs_for() {
  case "$1" in
    sn) echo "EPSG:25833" ;;
    *)  echo "" ;;
  esac
}

# ---------------------------------------------------------------------------------------
# Repairing text the publisher truncated mid-character
# ---------------------------------------------------------------------------------------
# A DBF text field is at most 254 bytes, and a publisher cutting long values to fit does not
# always respect character boundaries. One value in MV ends "Forstwirtschaftsfl\xC3" — the
# lead byte of "ä" with its continuation byte lopped off. GDAL copies the bytes through
# happily; DuckDB refuses the whole Parquet file with "Invalid string encoding", so a single
# Gemeinde takes the entire state's load down with it. Measured over all 724 MV packages:
# 1 file, 1 column, but that is enough.
#
# The repair drops the last character from any value sitting at the 254-byte cap — those are
# the only ones that can have been cut, and they were already truncated by the publisher, so
# one more character is no further loss. Values below the cap are passed through untouched,
# which is why it is applied to every 254-wide field of an affected source rather than just
# the one known to be broken today: same defect, same fix, no guessing about which field
# breaks next.
#
# It is listed per source, not applied everywhere, because it costs the SQLITE dialect (OGR
# SQL has no BLOB cast to measure bytes with) and most sources do not need it. BW and BB are
# Shapefiles hitting the same 254-byte cap, but both load clean, so neither is listed. Add a
# source here when DuckDB rejects its Parquet with "Invalid string encoding".
capped_text_for() {  # state-kind -> space-separated field names, or empty
  case "$1" in
    mv-plots)      echo "land gemarkung flur regbezirk kreis gemeinde abwrecht lagebeztxt tntxt" ;;
    mv-structures) echo "gebnutzbez funktion rellage name lagebeztxt" ;;
    *)             echo "" ;;
  esac
}

# Emits "<expr> AS <field>" for each capped field, and a bare name for everything else.
capped_select_list() {  # all-fields capped-fields
  local all="$1" capped="$2" f first=1
  for f in ${all//,/ }; do
    ((first)) || printf ', '
    first=0
    if [[ " $capped " == *" $f "* ]]; then
      printf 'CASE WHEN length(CAST(%s AS BLOB)) >= 254 THEN substr(%s, 1, length(%s) - 1) ELSE %s END AS %s' \
             "$f" "$f" "$f" "$f" "$f"
    else
      printf '%s' "$f"
    fi
  done
}

# Non-empty only where a dataset needs SQL instead of a plain -select.
sql_for() {  # state-kind layer
  local capped
  capped="$(capped_text_for "$1")"
  [[ -n "$capped" ]] || { echo ""; return 0; }
  echo "SELECT $(capped_select_list "$(fields_for "$1")" "$capped"), GEOMETRY FROM $2"
}

# Columns kept from each source. Everything not mapped to a table column ends up in
# plots.metadata; structures/structure_versions have no metadata column, so for those the
# list is only what the mapping actually reads.
fields_for() {
  case "$1" in
    # BB ships the same vereinfacht profile as MV and NW, with two differences: the land-use
    # text is `tntext` rather than `tntxt`, and there is an extra `flurstnr` (the parcel
    # number as one string, where zaehler/nenner are the split halves).
    bb-plots)      echo "oid,aktualit,idflurst,flaeche,flstkennz,land,landschl,gemarkung,gemaschl,flur,flurschl,flstnrzae,flstnrnen,regbezirk,regbezschl,kreis,kreisschl,gemeinde,gmdschl,abwrecht,lagebeztxt,tntext,flurstnr" ;;
    bb-structures) echo "oid,aktualit,gebnutzbez,funktion,gfkzshh,rellage,name,anzahlgs,gmdschl,lagebeztxt" ;;
    be-plots)      echo "uuid,bezeich,afl,fsko,zae,nen,gmk,namgmk,fln,gdz,namgem,zde,dst,beg" ;;
    be-structures) echo "uuid,gfk,bezgfk,ofl,bezofl,aog,aug,hoh,bat,bezbat,nam,baw,bezbaw,zus,bezzus,gkn,des,bezdes,lag,namlag,hnr,pnr,lnr,bezeich,shape_area" ;;
    bw-plots)      echo "oid,aktualit,idflurst,flaeche,flstkennz,land,gemarkung,flur,flurstnr,gmdschl,regbezirk,kreis,gemeinde,lagebeztxt,tntxt" ;;
    bw-structures) echo "oid,aktualit,gebnutzbez,funktion,fktkurz,name,anzahlgs,lagebeztxt" ;;
    by-structures) echo "ags" ;;
    # MV and NW both publish the ALKIS *vereinfacht* profile, so their attributes are the
    # same names in the same order — only the container differs (Shapefile vs GeoPackage).
    mv-plots)      echo "oid,aktualit,idflurst,flaeche,flstkennz,land,landschl,gemarkung,gemaschl,flur,flurschl,flstnrzae,flstnrnen,regbezirk,regbezschl,kreis,kreisschl,gemeinde,gmdschl,abwrecht,lagebeztxt,tntxt" ;;
    mv-structures) echo "oid,aktualit,gebnutzbez,funktion,gfkzshh,rellage,name,anzahlgs,gmdschl,lagebeztxt" ;;
    nw-plots)      echo "oid,aktualit,idflurst,flaeche,flstkennz,land,landschl,gemarkung,gemaschl,flur,flurschl,flstnrzae,flstnrnen,regbezirk,regbezschl,kreis,kreisschl,gemeinde,gmdschl,abwrecht,lagebeztxt,tntxt" ;;
    nw-structures) echo "oid,aktualit,gebnutzbez,funktion,gfkzshh,rellage,name,anzahlgs,gmdschl,lagebeztxt" ;;
    # NAS: safe only because the fixed .gfs declares all of these for every part. Two are
    # genuinely absent from some parts (zeitpunktDerEntstehung 544/569,
    # abweichenderRechtszustand 397/569) and arrive as NULL there rather than aborting.
    sn-plots)      echo "identifier,flurstueckskennzeichen,amtlicheFlaeche,land,gemarkungsnummer,zaehler,nenner,zeitpunktDerEntstehung,beginnt,regierungsbezirk,kreis,gemeinde,abweichenderRechtszustand" ;;
    sn-structures) echo "identifier,gebaeudefunktion,beginnt" ;;
    *) return 1 ;;
  esac
}

# AX_Gebaeude.gebaeudefunktion is a numeric AdV code, where every other state ships resolved
# text. Left raw it would put "1000" in structure_versions.type next to NW's "Wohnhaus", so
# it is translated here. These are the 59 codes that actually occur in the SN export (all
# 2,539,965 buildings scanned, not sampled), with names from the AdV code list at
# repository.gdi-de.org/schemas/adv/citygml/Codelisten/BuildingFunctionTypeAdV.xml.
# A code outside this set keeps its number, tagged, so it shows up rather than hiding in a
# generic bucket — which is also how the next export's new codes will announce themselves.
#
# The CASE is wrapped in coalesce because `WHEN NULL` can never match in SQL and the ELSE
# branch concatenates, so a null code would yield NULL and be rejected by type NOT NULL.
# Every one of the 2,539,965 buildings in this export does carry a code; the guard is for
# the next one.
gebaeudefunktion_case() {
  cat <<'EOF'
  coalesce(CASE gebaeudefunktion
    WHEN 1000 THEN 'Wohngebäude'
    WHEN 1100 THEN 'Gemischt genutztes Gebäude mit Wohnen'
    WHEN 2000 THEN 'Gebäude für Wirtschaft oder Gewerbe'
    WHEN 2010 THEN 'Gebäude für Handel und Dienstleistungen'
    WHEN 2060 THEN 'Messehalle'
    WHEN 2070 THEN 'Gebäude für Beherbergung'
    WHEN 2080 THEN 'Gebäude für Bewirtung'
    WHEN 2090 THEN 'Freizeit- und Vergnügungsstätte'
    WHEN 2100 THEN 'Gebäude für Gewerbe und Industrie'
    WHEN 2211 THEN 'Windmühle'
    WHEN 2213 THEN 'Schöpfwerk'
    WHEN 2460 THEN 'Gebäude zum Parken'
    WHEN 2463 THEN 'Garage'
    WHEN 2500 THEN 'Gebäude zur Versorgung'
    WHEN 2600 THEN 'Gebäude zur Entsorgung'
    WHEN 2700 THEN 'Gebäude für Land- und Forstwirtschaft'
    WHEN 2740 THEN 'Treibhaus, Gewächshaus'
    WHEN 3000 THEN 'Gebäude für öffentliche Zwecke'
    WHEN 3010 THEN 'Verwaltungsgebäude'
    WHEN 3011 THEN 'Parlament'
    WHEN 3012 THEN 'Rathaus'
    WHEN 3014 THEN 'Zollamt'
    WHEN 3015 THEN 'Gericht'
    WHEN 3016 THEN 'Botschaft, Konsulat'
    WHEN 3019 THEN 'Finanzamt'
    WHEN 3020 THEN 'Gebäude für Bildung und Forschung'
    WHEN 3021 THEN 'Allgemein bildende Schule'
    WHEN 3022 THEN 'Berufsbildende Schule'
    WHEN 3023 THEN 'Hochschulgebäude (Fachhochschule, Universität)'
    WHEN 3024 THEN 'Forschungsinstitut'
    WHEN 3030 THEN 'Gebäude für kulturelle Zwecke'
    WHEN 3031 THEN 'Schloss'
    WHEN 3032 THEN 'Theater, Oper'
    WHEN 3034 THEN 'Museum'
    WHEN 3035 THEN 'Rundfunk, Fernsehen'
    WHEN 3037 THEN 'Bibliothek, Bücherei'
    WHEN 3038 THEN 'Burg, Festung'
    WHEN 3040 THEN 'Gebäude für religiöse Zwecke'
    WHEN 3041 THEN 'Kirche'
    WHEN 3042 THEN 'Synagoge'
    WHEN 3043 THEN 'Kapelle'
    WHEN 3046 THEN 'Moschee'
    WHEN 3047 THEN 'Tempel'
    WHEN 3048 THEN 'Kloster'
    WHEN 3050 THEN 'Gebäude für Gesundheitswesen'
    WHEN 3051 THEN 'Krankenhaus'
    WHEN 3060 THEN 'Gebäude für soziale Zwecke'
    WHEN 3065 THEN 'Kinderkrippe, Kindergarten, Kindertagesstätte'
    WHEN 3070 THEN 'Gebäude für Sicherheit und Ordnung'
    WHEN 3071 THEN 'Polizei'
    WHEN 3072 THEN 'Feuerwehr'
    WHEN 3073 THEN 'Kaserne'
    WHEN 3075 THEN 'Justizvollzugsanstalt'
    WHEN 3200 THEN 'Gebäude für Erholungszwecke'
    WHEN 3210 THEN 'Gebäude für Sportzwecke'
    WHEN 3211 THEN 'Sport-, Turnhalle'
    WHEN 3221 THEN 'Hallenbad'
    WHEN 3240 THEN 'Gebäude für Kurbetrieb'
    WHEN 9998 THEN 'Nach Quellenlage nicht zu spezifizieren'
    ELSE 'Gebäudefunktion ' || CAST(gebaeudefunktion AS VARCHAR)
  END, 'Gebäude')
EOF
}

# ---------------------------------------------------------------------------------------
# Per-dataset SQL. Each emits the expressions the load step selects from the staged
# parquet. `g` is the already-reprojected geometry column, `snapdate` the dataset-level
# fallback date.
#
# local_id is the AAA object identifier exactly as the state publishes it — `oid` in NW and
# BW (16-char id plus a 2-char object-type suffix, FL for Flurstück, BL for Bauwerk),
# `uuid` in BE. Bayern's Hausumringe carry no identifier at all, so one is synthesised from
# the source file stem and the feature id; it is stable as long as the source file is.
# local_id_region and region are both the state ID, which makes the pair unique nationwide.
# ---------------------------------------------------------------------------------------

plots_select() {
  case "$1" in
    # Like mv below — same profile, same "2024-06-04Z" text date needing the cast. Brandenburg
    # has no Regierungsbezirke, so regbezirk is null throughout and only its key (120) is set;
    # both are carried anyway so the metadata shape matches MV and NW.
    bb) cat <<'EOF'
  oid                                                    AS local_id,
  flaeche                                                AS area_src,
  try_cast(nullif(aktualit, '') AS DATE)                 AS date_src,
  to_json({
    'aaa_id': idflurst, 'flurstueckskennzeichen': flstkennz,
    'land': land, 'landschluessel': landschl,
    'gemarkung': gemarkung, 'gemarkungsschluessel': gemaschl,
    'flur': flur, 'flurschluessel': flurschl,
    'flurstuecksnummer': flurstnr, 'zaehler': flstnrzae, 'nenner': flstnrnen,
    'regierungsbezirk': regbezirk, 'regierungsbezirkschluessel': regbezschl,
    'kreis': kreis, 'kreisschluessel': kreisschl,
    'gemeinde': gemeinde, 'gemeindeschluessel': gmdschl,
    'abweichendes_rechtsverhaeltnis': abwrecht,
    'lagebezeichnung': lagebeztxt, 'nutzung': tntext,
    'quelle': 'ALKIS BB vereinfacht Shape'
  })                                                     AS metadata
EOF
        ;;
    be) cat <<'EOF'
  uuid                                                   AS local_id,
  afl                                                    AS area_src,
  beg                                                    AS date_src,
  to_json({
    'bezeich': bezeich, 'flurstueckskennzeichen': fsko, 'zaehler': zae, 'nenner': nen,
    'gemarkungsschluessel': gmk, 'gemarkung': namgmk, 'flur': fln,
    'gemeindeschluessel': gdz, 'gemeinde': namgem,
    'entstehung': zde, 'zustaendige_stelle': dst, 'quelle': 'ALKIS BE WFS 2.0'
  })                                                     AS metadata
EOF
        ;;
    bw) cat <<'EOF'
  oid                                                    AS local_id,
  flaeche                                                AS area_src,
  try_cast(nullif(aktualit, '') AS DATE)                 AS date_src,
  to_json({
    'aaa_id': idflurst, 'flurstueckskennzeichen': flstkennz, 'land': land,
    'gemarkung': gemarkung, 'flur': flur, 'flurstuecksnummer': flurstnr,
    'gemeindeschluessel': gmdschl, 'regierungsbezirk': regbezirk, 'kreis': kreis,
    'gemeinde': gemeinde, 'lagebezeichnung': lagebeztxt, 'nutzung': tntxt,
    'quelle': 'ALKIS BW Shape'
  })                                                     AS metadata
EOF
        ;;
    # Same field names as nw below — the vereinfacht profile — but the Shapefile carries
    # `aktualit` as text ("2024-04-22Z"), not as a date, so it needs the cast that nw does
    # not. DuckDB parses the trailing Z itself; only the empty string has to be guarded.
    mv) cat <<'EOF'
  oid                                                    AS local_id,
  flaeche                                                AS area_src,
  try_cast(nullif(aktualit, '') AS DATE)                 AS date_src,
  to_json({
    'aaa_id': idflurst, 'flurstueckskennzeichen': flstkennz,
    'land': land, 'landschluessel': landschl,
    'gemarkung': gemarkung, 'gemarkungsschluessel': gemaschl,
    'flur': flur, 'flurschluessel': flurschl,
    'zaehler': flstnrzae, 'nenner': flstnrnen,
    'regierungsbezirk': regbezirk, 'regierungsbezirkschluessel': regbezschl,
    'kreis': kreis, 'kreisschluessel': kreisschl,
    'gemeinde': gemeinde, 'gemeindeschluessel': gmdschl,
    'abweichendes_rechtsverhaeltnis': abwrecht,
    'lagebezeichnung': lagebeztxt, 'nutzung': tntxt,
    'quelle': 'ALKIS MV vereinfacht Shape'
  })                                                     AS metadata
EOF
        ;;
    nw) cat <<'EOF'
  oid                                                    AS local_id,
  flaeche                                                AS area_src,
  aktualit                                               AS date_src,
  to_json({
    'aaa_id': idflurst, 'flurstueckskennzeichen': flstkennz,
    'land': land, 'landschluessel': landschl,
    'gemarkung': gemarkung, 'gemarkungsschluessel': gemaschl,
    'flur': flur, 'flurschluessel': flurschl,
    'zaehler': flstnrzae, 'nenner': flstnrnen,
    'regierungsbezirk': regbezirk, 'regierungsbezirkschluessel': regbezschl,
    'kreis': kreis, 'kreisschluessel': kreisschl,
    'gemeinde': gemeinde, 'gemeindeschluessel': gmdschl,
    'abweichendes_rechtsverhaeltnis': abwrecht,
    'lagebezeichnung': lagebeztxt, 'nutzung': tntxt,
    'quelle': 'ALKIS NW gru_vereinfacht GPKG'
  })                                                     AS metadata
EOF
        ;;
    # zeitpunktDerEntstehung is when the parcel came into existence and is the honest
    # valid_from, but it is null in a quarter of the rows; `beginnt` (when this object
    # version became current) is always there, so it is the second choice ahead of the
    # dataset-level snapshot date.
    sn) cat <<'EOF'
  identifier                                             AS local_id,
  amtlicheFlaeche                                        AS area_src,
  coalesce(zeitpunktDerEntstehung, CAST(beginnt AS DATE)) AS date_src,
  to_json({
    'flurstueckskennzeichen': flurstueckskennzeichen,
    'land': land, 'gemarkungsnummer': gemarkungsnummer,
    'zaehler': zaehler, 'nenner': nenner,
    'regierungsbezirk': regierungsbezirk, 'kreis': kreis, 'gemeinde': gemeinde,
    'abweichendes_rechtsverhaeltnis': abweichenderRechtszustand,
    'quelle': 'ALKIS SN NAS (Bestandsdatenauszug)'
  })                                                     AS metadata
EOF
        ;;
    *) return 1 ;;
  esac
}

structures_select() {
  case "$1" in
    bb) cat <<'EOF'
  oid                                                    AS local_id,
  coalesce(nullif(funktion, ''), nullif(gebnutzbez, ''), 'Gebäude')  AS type,
  try_cast(nullif(aktualit, '') AS DATE)                 AS date_src
EOF
        ;;
    be) cat <<'EOF'
  uuid                                                   AS local_id,
  coalesce(nullif(bezgfk, ''), 'Gebäude')                AS type,
  CAST(NULL AS DATE)                                     AS date_src
EOF
        ;;
    bw) cat <<'EOF'
  oid                                                    AS local_id,
  coalesce(nullif(funktion, ''), nullif(gebnutzbez, ''), 'Gebäude')  AS type,
  try_cast(nullif(aktualit, '') AS DATE)                 AS date_src
EOF
        ;;
    by) cat <<'EOF'
  parse_filename(filename, true) || ':' || CAST(ogc_fid AS VARCHAR)  AS local_id,
  'Hausumring'                                           AS type,
  CAST(NULL AS DATE)                                     AS date_src
EOF
        ;;
    mv) cat <<'EOF'
  oid                                                    AS local_id,
  coalesce(nullif(funktion, ''), nullif(gebnutzbez, ''), 'Gebäude')  AS type,
  try_cast(nullif(aktualit, '') AS DATE)                 AS date_src
EOF
        ;;
    nw) cat <<'EOF'
  oid                                                    AS local_id,
  coalesce(nullif(funktion, ''), nullif(gebnutzbez, ''), 'Gebäude')  AS type,
  aktualit                                               AS date_src
EOF
        ;;
    sn) cat <<EOF
  identifier                                             AS local_id,
$(gebaeudefunktion_case)                                 AS type,
  CAST(beginnt AS DATE)                                  AS date_src
EOF
        ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------------------

# A dataset's dir field may be `a|b`; echo the first alternative that exists and has files.
resolve_dir() {  # dir-spec glob
  local cand
  local IFS='|'
  for cand in $1; do
    [[ -d "$ALKIS_DIR/$cand" ]] || continue
    compgen -G "$ALKIS_DIR/$cand/$2" >/dev/null || continue
    echo "$cand"; return 0
  done
  return 1
}

# Echoes "state kind dir layer reader glob" for each dataset that is selected and has files.
selected_datasets() {
  local line state kind dir layer reader glob real
  for line in "${DATASETS[@]}"; do
    read -r state kind dir layer reader glob <<<"$line"
    [[ -n "${STATES:-}" ]] && [[ " $STATES " != *" $state "* ]] && continue
    [[ -n "${KINDS:-}"  ]] && [[ " $KINDS "  != *" $kind "*  ]] && continue
    real="$(resolve_dir "$dir" "$glob")" || continue
    echo "$state $kind $real $layer $reader $glob"
  done
}

# ---------------------------------------------------------------------------------------
# NAS archives: unwrap once, index once, then serve parts
# ---------------------------------------------------------------------------------------

nas_workdir() { echo "$STAGE_DIR/.nas/$1"; }

# The outer zip holds a single member. If that member is itself a zip (Sachsen: alkis_sn.zip
# -> E_<auftrag>.zip) the parts live one level deeper, so unwrap it; otherwise the outer zip
# already is the part archive. Unwrapping costs 2.4 GB of staging, which buys the 200x
# speedup over reading parts through nested /vsizip — see the note at the top of this file.
nas_inner() {  # dir -> path to the zip whose members are the XML parts
  local dir="$1" work archive inner member
  work="$(nas_workdir "$dir")"
  inner="$work/inner.zip"
  archive="$(source_files "$dir" '*.zip' | head -1)"
  [[ -n "$archive" ]] || { echo "ERROR: no .zip under $ALKIS_DIR/$dir" >&2; return 1; }

  if [[ -s "$inner" && "$inner" -nt "$archive" ]]; then echo "$inner"; return 0; fi

  mkdir -p "$work"
  member="$(unzip -Z1 "$archive" | head -1)"
  if [[ "$member" != *.zip ]]; then echo "$archive"; return 0; fi

  echo "  unwrapping $(basename "$archive") -> $member (once; cached in staging)" >&2
  if ! unzip -p "$archive" "$member" > "$inner.partial"; then
    rm -f "$inner.partial"; echo "ERROR: could not unwrap $archive" >&2; return 1
  fi
  mv "$inner.partial" "$inner"
  echo "$inner"
}

# parts.index: one line per part, "<part> <TYPE> <TYPE> ...". Built once per archive because
# the parts are split by object type and most hold neither of the types we want — without it
# every dataset would convert all 1,596 instead of its own 569 or 508.
nas_index() {  # dir -> path to parts.index
  local dir="$1" work inner idx
  work="$(nas_workdir "$dir")"
  idx="$work/parts.index"
  inner="$(nas_inner "$dir")" || return 1
  if [[ -s "$idx" && "$idx" -nt "$inner" ]]; then echo "$idx"; return 0; fi

  echo "  indexing NAS parts by object type (once; ~30 s) ..." >&2
  local list="$work/.members" n
  unzip -Z1 "$inner" | grep -i '\.xml$' | sort > "$list"
  n=$(wc -l < "$list" | tr -d ' ')

  # Each worker emits exactly one short line, which write(2) delivers atomically, so the
  # shared pipe is safe here. It is not safe in general — building this index the obvious
  # way, with workers streaming many lines into one pipe, spliced lines together and
  # invented object types that do not exist. Hence one echo per part, and the count check.
  # Match the element start exactly: `<AX_Flurstueck ` must not also count
  # `<AX_Flurstuecksnummer`, which appears in every parcel part.
  NAS_INNER="$inner" xargs -P "$JOBS" -I{} bash -c '
      types=$(unzip -p "$NAS_INNER" "$1" 2>/dev/null \
        | LC_ALL=C grep -oE "<AX_[A-Za-z]+[ >]" \
        | LC_ALL=C sed "s/^<//; s/[ >]$//" | LC_ALL=C sort -u | tr "\n" " ")
      echo "$1 $types"' _ {} < "$list" > "$idx.partial"

  if [[ "$(wc -l < "$idx.partial" | tr -d ' ')" != "$n" ]]; then
    rm -f "$idx.partial"
    echo "ERROR: indexed $(wc -l < "$idx.partial" 2>/dev/null || echo 0) of $n parts — index is incomplete" >&2
    return 1
  fi
  sort "$idx.partial" > "$idx"
  rm -f "$idx.partial" "$list"
  echo "  indexed $n parts" >&2
  echo "$idx"
}

# The parts carrying one layer. Read-only: never builds the index, so --list stays cheap.
nas_parts() {  # dir layer
  local idx; idx="$(nas_workdir "$1")/parts.index"
  [[ -s "$idx" ]] || return 0
  awk -v want="$2" '{for (i = 2; i <= NF; i++) if ($i == want) { print $1; break }}' "$idx"
}

# One .gfs pinned for the whole dataset, so every part reports the same columns and a field
# a given part happens to lack comes back NULL instead of killing ogr2ogr. Generated from a
# real part rather than hand-written, but not from just the first one: parts differ, and a
# part with a reduced schema would pin a .gfs missing the very fields we select. So walk
# parts until one declares every field in fields_for, and fail loudly if none does — which
# is also the signal that the state changed its export.
nas_gfs() {  # dir layer fields -> path to reference .gfs
  local dir="$1" layer="$2" fields="$3"
  local work inner gfs tmp part tries=0 f ok
  work="$(nas_workdir "$dir")"
  gfs="$work/$layer.gfs"
  inner="$(nas_inner "$dir")" || return 1
  [[ -s "$gfs" && "$gfs" -nt "$inner" ]] && { echo "$gfs"; return 0; }

  tmp="$work/.gfsprobe"
  while read -r part; do
    ((tries++ >= 25)) && break
    rm -rf "$tmp"; mkdir -p "$tmp"
    unzip -p "$inner" "$part" > "$tmp/p.xml" 2>/dev/null || continue
    ogrinfo -ro -so "$tmp/p.xml" "$layer" >/dev/null 2>&1 || continue
    [[ -s "$tmp/p.gfs" ]] || continue
    ok=1
    for f in ${fields//,/ }; do
      grep -q "<Name>$f</Name>" "$tmp/p.gfs" || { ok=0; break; }
    done
    if ((ok)); then
      mv "$tmp/p.gfs" "$gfs"; rm -rf "$tmp"
      echo "  schema pinned from $part" >&2
      echo "$gfs"; return 0
    fi
  done < <(nas_parts "$dir" "$layer")

  rm -rf "$tmp"
  echo "ERROR: no $layer part in $dir declares all of: $fields" >&2
  echo "       the export's schema has changed — update fields_for()" >&2
  return 1
}

# One path per line. A download may still be running — download_all.sh writes into the same
# tree — so two kinds of half-written file are skipped rather than fed to ogr2ogr:
# anything aria2c still holds a .aria2 control file for, and anything touched in the last
# SETTLE seconds, which is how the WFS pagers' part-NNNNN.gml appear while being written.
#
# With a reader and layer given, a `nas` dataset yields its XML part names instead of files
# on disk — stage_one extracts each one. Callers that want the archive itself (snapshot_date
# takes its mtime) simply omit those two arguments.
SETTLE="${SETTLE:-60}"
source_files() {  # dir glob [reader] [layer]
  local f now age
  if [[ "${3:-}" == "nas" ]]; then nas_parts "$1" "$4"; return 0; fi
  now=$(date +%s)
  while IFS= read -r f; do
    [[ -s "$f" ]] || continue
    [[ -e "$f.aria2" ]] && continue
    # BSD stat, then GNU stat; if neither answers, treat the file as old enough to use.
    age=$(( now - $(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null || echo 0) ))
    ((age < SETTLE)) && continue
    echo "$f"
  done < <(compgen -G "$ALKIS_DIR/$1/$2" || true)
}

datasource_for() {  # reader file layer -> OGR datasource path
  case "$1" in
    zipshp) echo "/vsizip/$2/$3.shp" ;;
    *)      echo "$2" ;;
  esac
}

list_plan() {
  printf '%-3s %-11s %-16s %-17s %8s %10s\n' state kind source layer files size
  printf '%-3s %-11s %-16s %-17s %8s %10s\n' --- ----------- ---------------- ----------------- -------- ----------
  local state kind dir layer reader glob n sz nas_pending=0
  while read -r state kind dir layer reader glob; do
    n=$(source_files "$dir" "$glob" "$reader" "$layer" | wc -l | tr -d ' ')
    # A NAS archive only knows its part count once indexed, and the index is built on the
    # first real run. Print "?" rather than 0, which would read as "nothing to load".
    if [[ "$reader" == "nas" ]] && ((n == 0)); then n="?"; nas_pending=1; fi
    sz=$(du -sh "$ALKIS_DIR/$dir" 2>/dev/null | cut -f1)
    printf '%-3s %-11s %-16s %-17s %8s %10s\n' "$state" "$kind" "$dir" "$layer" "$n" "${sz:-?}"
  done < <(selected_datasets)
  echo
  ((nas_pending)) && echo "? = NAS archive not indexed yet; the part count is known after the first run."
  echo "Not loaded: bw-nas (same content as bw-shape, already loaded), by-tn (land use),"
  echo "            st (empty). Bayern publishes no open vector Flurstücke, so it has no plots."
  echo "            mv-nas (the NAS half of MV; the Shapefile half is loaded instead)."
  echo "            bb-nas (the NAS half of BB; the Shapefile half is loaded instead)."
  echo "            hb, he, hh, ni, rp, sh, sl, th are downloaded but not yet mapped."
  exit 0
}

# ---------------------------------------------------------------------------------------
# Staging: source file -> GeoParquet in EPSG:4326
# ---------------------------------------------------------------------------------------

# Runs in a subshell via xargs, one call per source file. Only the two per-file values are
# passed as arguments; the layer, reader and (long) field list travel in the environment,
# because inlining them blows xargs' command-line limit on the wider datasets.
stage_one() {
  local src="$1" out="$2"
  local layer="$STAGE_LAYER" reader="$STAGE_READER" fields="$STAGE_FIELDS"
  local ds tmp work=""
  # NAS: `src` is a part name inside the archive, not a path. Extract it, drop the pinned
  # .gfs beside it so the schema matches every other part, convert, then throw both away —
  # keeping all 1,596 parts on disk would cost ~95 GB.
  if [[ "$reader" == "nas" ]]; then
    work="$(mktemp -d "$STAGE_NAS_TMP/part.XXXXXX")" || return 1
    if ! unzip -p "$STAGE_NAS_INNER" "$src" > "$work/p.xml" 2>/dev/null; then
      rm -rf "$work"; echo "  ! could not extract $src" >&2; return 1
    fi
    [[ -n "${STAGE_NAS_GFS:-}" ]] && cp "$STAGE_NAS_GFS" "$work/p.gfs"
    ds="$work/p.xml"
  else
    ds="$(datasource_for "$reader" "$src" "$layer")"
  fi
  tmp="$out.partial"
  rm -f "$tmp"
  # Either a plain column pick, or -sql when the source needs repairing on the way through.
  # With -sql the layer must NOT also be passed positionally, hence the two arrays.
  local -a pick=() lyr=("$layer")
  if [[ -n "${STAGE_SQL:-}" ]]; then
    pick=(-dialect SQLITE -sql "$STAGE_SQL"); lyr=()
  else
    pick=(-select "$fields")
  fi
  # GEOMETRY_NAME normalises what each driver calls its geometry column (GML says geom, the
  # GeoPackage says geometrie, Shapefile says geometry) so the load SQL is source-agnostic.
  # GDAL_PAM_ENABLED=NO: otherwise every conversion drops a .aux.xml sidecar next to its
  # output, which nothing here reads and which the .partial rename would leave behind.
  if ! ogr2ogr -f Parquet "$tmp" "$ds" "${lyr[@]}" \
        "${pick[@]}" \
        -nlt MULTIPOLYGON ${STAGE_SSRS:+-s_srs "$STAGE_SSRS"} -t_srs EPSG:4326 \
        -lco GEOMETRY_ENCODING=WKB -lco GEOMETRY_NAME=geom -lco COMPRESSION=ZSTD \
        -lco FID=ogc_fid -lco WRITE_COVERING_BBOX=NO \
        --config GDAL_PAM_ENABLED NO \
        2> >(grep -v 'Warning' >&2 || true); then
    rm -f "$tmp" "$tmp.aux.xml"; [[ -n "$work" ]] && rm -rf "$work"
    echo "  ! failed: $src" >&2
    return 1
  fi
  rm -f "$tmp.aux.xml"
  [[ -n "$work" ]] && rm -rf "$work"
  mv "$tmp" "$out"
}
export -f stage_one datasource_for

stage_dataset() {  # state kind dir layer reader glob -> stage dir on stdout
  local state="$1" kind="$2" dir="$3" layer="$4" reader="$5" glob="$6"
  local sd="$STAGE_DIR/$state-$kind" src out todo=0 have=0 jobfile ref=""
  mkdir -p "$sd"

  export STAGE_LAYER="$layer" STAGE_READER="$reader"
  STAGE_FIELDS="$(fields_for "$state-$kind")"; export STAGE_FIELDS
  STAGE_SSRS="$(srs_for "$state")"; export STAGE_SSRS
  STAGE_SQL="$(sql_for "$state-$kind" "$layer")"; export STAGE_SQL

  # NAS needs the archive unwrapped, indexed and its schema pinned before any part converts.
  # `ref` is what a staged parquet is compared against for freshness: a part has no mtime of
  # its own, so the archive it came out of stands in for it.
  export STAGE_NAS_INNER="" STAGE_NAS_GFS="" STAGE_NAS_TMP=""
  if [[ "$reader" == "nas" ]]; then
    STAGE_NAS_INNER="$(nas_inner "$dir")"   || return 1
    nas_index "$dir" >/dev/null             || return 1
    STAGE_NAS_GFS="$(nas_gfs "$dir" "$layer" "$STAGE_FIELDS")" || return 1
    STAGE_NAS_TMP="$STAGE_DIR/.nas/tmp"; mkdir -p "$STAGE_NAS_TMP"
    ref="$(source_files "$dir" "$glob" | head -1)"
  fi

  jobfile="$sd/.jobs"
  : > "$jobfile"
  while IFS= read -r src; do
    out="$sd/$(basename "${src%.*}").parquet"
    if [[ -s "$out" && "$out" -nt "${ref:-$src}" ]]; then have=$((have + 1)); continue; fi
    printf '%s\0%s\0' "$src" "$out" >> "$jobfile"   # NUL-separated: paths carry umlauts
    todo=$((todo + 1))
  done < <(source_files "$dir" "$glob" "$reader" "$layer")

  echo "  staging $state-$kind: $todo to convert, $have already staged" >&2
  if ((todo > 0)); then
    xargs -0 -P "$JOBS" -n 2 bash -c 'stage_one "$0" "$1"' < "$jobfile" \
      || echo "  ! some files failed to stage — re-run to retry them" >&2
  fi
  rm -f "$jobfile"
  echo "$sd"
}

# The date a dataset was published, used where the source carries no per-feature date
# (Berlin's gebaeude layer, Bayern's Hausumringe). Newest source file mtime, which for a
# fresh download is when the state served it.
snapshot_date() {  # dir glob
  local f newest=""
  if [[ -n "$FALLBACK_DATE" ]]; then echo "$FALLBACK_DATE"; return; fi
  newest=$(source_files "$1" "$2" | xargs -I{} stat -f '%m' {} 2>/dev/null | sort -rn | head -1) || true
  [[ -z "$newest" ]] && newest=$(source_files "$1" "$2" | xargs -I{} stat -c '%Y' {} 2>/dev/null | sort -rn | head -1) || true
  [[ -z "$newest" ]] && { echo "1900-01-01"; return; }
  date -u -r "$newest" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$newest" '+%Y-%m-%d'
}

# ---------------------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------------------
#
# The DuckDB translation of the PostGIS schema:
#   geometry(Polygon,4326) -> GEOMETRY. DuckDB's spatial type carries no typmod, so the
#     Polygon/4326 part is enforced by this script instead: every geometry is reprojected
#     to EPSG:4326 by ogr2ogr, and single-part MULTIPOLYGONs are unwrapped to POLYGON.
#     Genuinely multi-part parcels stay MULTIPOLYGON and are counted in the summary.
#   jsonb -> JSON.
#   The structures table's tableoid/cmax/xmax/cmin/xmin/ctid columns are PostgreSQL system
#     columns that leaked into the dump — they have no DuckDB equivalent and are omitted.
#   Two UNIQUE constraints are added that the dump does not have: structures
#     (local_id, local_id_region), needed to look a structure up when attaching its
#     versions, and structure_versions (structure_id, valid_from), which is what makes a
#     re-run idempotent rather than duplicating every version row.
schema_sql() {
  cat <<'EOF'
INSTALL spatial; LOAD spatial;

CREATE TABLE IF NOT EXISTS plots (
    id              UUID      DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    local_id        TEXT                                NOT NULL,
    local_id_region TEXT                                NOT NULL,
    region          TEXT                                NOT NULL,
    geometry        GEOMETRY                            NOT NULL,
    area            DOUBLE                              NOT NULL,
    metadata        JSON                                NOT NULL,
    valid_from      DATE                                NOT NULL,
    valid_to        DATE,
    created_at      TIMESTAMP DEFAULT now()             NOT NULL,
    updated_at      TIMESTAMP DEFAULT now()             NOT NULL,
    CONSTRAINT plots_local_id_local_id_region_unique UNIQUE (local_id, local_id_region)
);

CREATE TABLE IF NOT EXISTS structures (
    id              UUID      DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    local_id        TEXT                                NOT NULL,
    local_id_region TEXT                                NOT NULL,
    created_at      TIMESTAMP DEFAULT now()             NOT NULL,
    updated_at      TIMESTAMP DEFAULT now()             NOT NULL,
    CONSTRAINT structures_local_id_local_id_region_unique UNIQUE (local_id, local_id_region)
);

CREATE TABLE IF NOT EXISTS structure_versions (
    id           UUID      DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    geometry     GEOMETRY                            NOT NULL,
    type         TEXT                                NOT NULL,
    valid_from   DATE                                NOT NULL,
    valid_to     DATE,
    created_at   TIMESTAMP DEFAULT now()             NOT NULL,
    updated_at   TIMESTAMP DEFAULT now()             NOT NULL,
    structure_id UUID                                NOT NULL REFERENCES structures(id),
    CONSTRAINT structure_versions_structure_id_valid_from_unique UNIQUE (structure_id, valid_from)
);

CREATE TABLE IF NOT EXISTS ingest_log (
    dataset     TEXT PRIMARY KEY,
    source_dir  TEXT NOT NULL,
    layer       TEXT NOT NULL,
    rows_read   BIGINT NOT NULL,
    rows_kept   BIGINT NOT NULL,
    multipart   BIGINT NOT NULL,
    ingested_at TIMESTAMP DEFAULT now() NOT NULL
);
EOF
}

duck() {  # run SQL against the database
  # geometry_always_xy: everything staged here is EPSG:4326 in longitude/latitude order, so
  # ST_Area_Spheroid must read X as longitude rather than guess.
  local pre="SET geometry_always_xy = true;"
  [[ -n "$MEMORY_LIMIT" ]] && pre="$pre SET memory_limit='$MEMORY_LIMIT';"
  duckdb "$DB" -c "LOAD spatial; $pre $1"
}

# ---------------------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------------------

# `norm` is the geometry normalisation shared by both tables: reject empties, unwrap a
# single-part MULTIPOLYGON to POLYGON, leave genuine multi-part geometry alone.
NORM_GEOM="CASE WHEN ST_GeometryType(geom) = 'MULTIPOLYGON' AND ST_NumGeometries(geom) = 1
                THEN ST_Dump(geom)[1].geom ELSE geom END"

load_plots() {  # state stagedir snapdate
  local state="$1" sd="$2" snap="$3"
  duck "
BEGIN;
CREATE OR REPLACE TEMP VIEW staged AS
SELECT * FROM read_parquet('$sd/*.parquet', filename = true, union_by_name = true);

CREATE OR REPLACE TEMP TABLE norm AS
SELECT * FROM (
  SELECT
$(plots_select "$state"),
    $NORM_GEOM AS g
  FROM staged
  WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
) QUALIFY row_number() OVER (PARTITION BY local_id) = 1;

INSERT INTO plots (local_id, local_id_region, region, geometry, area, metadata, valid_from)
SELECT
  local_id,
  '$state',
  '$state',
  g,
  coalesce(nullif(area_src, 0), ST_Area_Spheroid(g)),
  metadata,
  coalesce(date_src, DATE '$snap')
FROM norm
ON CONFLICT (local_id, local_id_region) DO NOTHING;

INSERT INTO ingest_log (dataset, source_dir, layer, rows_read, rows_kept, multipart)
SELECT '$state-plots', '$sd', 'plots',
       (SELECT count(*) FROM staged),
       (SELECT count(*) FROM norm),
       (SELECT count(*) FROM norm WHERE ST_GeometryType(g) = 'MULTIPOLYGON')
ON CONFLICT (dataset) DO UPDATE SET
  rows_read = excluded.rows_read, rows_kept = excluded.rows_kept,
  multipart = excluded.multipart, ingested_at = now();
COMMIT;
"
}

load_structures() {  # state stagedir snapdate
  local state="$1" sd="$2" snap="$3"
  duck "
BEGIN;
CREATE OR REPLACE TEMP VIEW staged AS
SELECT * FROM read_parquet('$sd/*.parquet', filename = true, union_by_name = true);

CREATE OR REPLACE TEMP TABLE norm AS
SELECT * FROM (
  SELECT
$(structures_select "$state"),
    $NORM_GEOM AS g
  FROM staged
  WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
) QUALIFY row_number() OVER (PARTITION BY local_id) = 1;

INSERT INTO structures (local_id, local_id_region)
SELECT local_id, '$state' FROM norm
ON CONFLICT (local_id, local_id_region) DO NOTHING;

INSERT INTO structure_versions (geometry, type, valid_from, structure_id)
SELECT n.g, n.type, coalesce(n.date_src, DATE '$snap'), s.id
FROM norm n
JOIN structures s ON s.local_id = n.local_id AND s.local_id_region = '$state'
ON CONFLICT (structure_id, valid_from) DO NOTHING;

INSERT INTO ingest_log (dataset, source_dir, layer, rows_read, rows_kept, multipart)
SELECT '$state-structures', '$sd', 'structures',
       (SELECT count(*) FROM staged),
       (SELECT count(*) FROM norm),
       (SELECT count(*) FROM norm WHERE ST_GeometryType(g) = 'MULTIPOLYGON')
ON CONFLICT (dataset) DO UPDATE SET
  rows_read = excluded.rows_read, rows_kept = excluded.rows_kept,
  multipart = excluded.multipart, ingested_at = now();
COMMIT;
"
}

# ---------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage

# Checked before --list, not after. A missing source tree used to print an empty table and
# exit 0, which reads as "there is nothing to load" rather than "I looked in the wrong place"
# — the same silent-zero this script works hard to avoid everywhere else.
[[ -d "$ALKIS_DIR" ]] || {
  echo "ERROR: $ALKIS_DIR not found." >&2
  echo "       Run ./download_all.sh alkis, or point ALKIS_DIR= at the tree if it has moved." >&2
  exit 1
}

if [[ "${1:-}" == "--list" ]]; then list_plan; fi

DB="${1:-./alkis.duckdb}"

need ogr2ogr gdal
need duckdb duckdb

PLAN=()   # no mapfile: macOS ships bash 3.2
while IFS= read -r line; do PLAN+=("$line"); done < <(selected_datasets)
((${#PLAN[@]})) || { echo "Nothing to load: no matching source directories under $ALKIS_DIR." >&2; exit 1; }

echo "Database : $DB"
echo "Sources  : $ALKIS_DIR"
echo "Staging  : $STAGE_DIR"
echo "Datasets : ${#PLAN[@]}"
echo

if [[ "$DRY_RUN" == "1" ]]; then
  list_plan
fi

mkdir -p "$STAGE_DIR"
duck "$(schema_sql)" >/dev/null

FAILED=0
for line in "${PLAN[@]}"; do
  read -r state kind dir layer reader glob <<<"$line"
  echo "== $state-$kind  ($dir / $layer)"
  # A dataset that cannot even be prepared (NAS schema drift, unreadable archive) must not
  # look like one that simply had nothing new. Note the empty-sd guard: without it the
  # glob below would be "/*.parquet" and go looking in the filesystem root.
  if ! sd="$(stage_dataset "$state" "$kind" "$dir" "$layer" "$reader" "$glob")" || [[ -z "$sd" ]]; then
    echo "  ! could not stage $state-$kind — skipping" >&2
    FAILED=$((FAILED + 1)); continue
  fi
  compgen -G "$sd/*.parquet" >/dev/null || { echo "  ! nothing staged, skipping" >&2; FAILED=$((FAILED + 1)); continue; }
  snap="$(snapshot_date "$dir" "$glob")"
  echo "  loading (snapshot date $snap) ..."
  if [[ "$kind" == "plots" ]]; then load_plots "$state" "$sd" "$snap"
  else                              load_structures "$state" "$sd" "$snap"; fi
  [[ "$KEEP_STAGE" == "1" ]] || rm -rf "$sd"
done

echo
echo "== Summary"
duck "
SELECT dataset, rows_read, rows_kept, multipart, ingested_at FROM ingest_log ORDER BY dataset;
SELECT 'plots' AS tbl, region, count(*) AS rows, round(sum(area) / 1e6, 1) AS km2
  FROM plots GROUP BY region
UNION ALL
SELECT 'structures', local_id_region, count(*), NULL FROM structures GROUP BY local_id_region
ORDER BY 1, 2;
"
echo
if ((FAILED > 0)); then
  echo "Done, but $FAILED dataset(s) did not load — see the messages above."
else
  echo "Done. Query it with:  duckdb $DB -c \"LOAD spatial; SELECT * FROM plots LIMIT 5;\""
fi
exit $(( FAILED > 0 ? 1 : 0 ))
