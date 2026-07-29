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
#   be     be-flurstuecke    plots                                paged GML (WFS 2.0)
#   be     be-gebaeude       structures + versions                paged GML (WFS 2.0)
#   bw     bw-shape          plots + structures + versions        zipped Shapefile, per Gemarkung
#   by     by-hausumringe    structures + versions                zipped Shapefile, per Bezirk
#   nw     nw                plots + structures + versions        GeoPackage, per Kreis
#
# Not loaded, and why:
#   bw-nas   the same content as bw-shape in NAS/GML — needs a GFS schema mapping, and the
#            download is incomplete anyway (see .download_all.failures).
#   by-tn    Tatsächliche Nutzung: land use, neither parcels nor footprints.
#   st       empty — the Sachsen-Anhalt WFS dump has not been fetched.
#   Bayern publishes no open vector Flurstücke at all, so `by` contributes no plots.
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
# ---------------------------------------------------------------------------------------
DATASETS=(
  "be plots      be-flurstuecke  flurstuecke       gml     *.gml"
  "be structures be-gebaeude     gebaeude          gml     *.gml"
  "bw plots      bw-shape        flurstueck        zipshp  *.zip"
  "bw structures bw-shape        gebaeudeBauwerke  zipshp  *.zip"
  "by structures by-hausumringe  hausumringe       zipshp  *.zip"
  "nw plots      nw              Flurstueck        gpkg    *.gpkg"
  "nw structures nw              GebauedeBauwerk   gpkg    *.gpkg"
)

# Columns kept from each source. Everything not mapped to a table column ends up in
# plots.metadata; structures/structure_versions have no metadata column, so for those the
# list is only what the mapping actually reads.
fields_for() {
  case "$1" in
    be-plots)      echo "uuid,bezeich,afl,fsko,zae,nen,gmk,namgmk,fln,gdz,namgem,zde,dst,beg" ;;
    be-structures) echo "uuid,gfk,bezgfk,ofl,bezofl,aog,aug,hoh,bat,bezbat,nam,baw,bezbaw,zus,bezzus,gkn,des,bezdes,lag,namlag,hnr,pnr,lnr,bezeich,shape_area" ;;
    bw-plots)      echo "oid,aktualit,idflurst,flaeche,flstkennz,land,gemarkung,flur,flurstnr,gmdschl,regbezirk,kreis,gemeinde,lagebeztxt,tntxt" ;;
    bw-structures) echo "oid,aktualit,gebnutzbez,funktion,fktkurz,name,anzahlgs,lagebeztxt" ;;
    by-structures) echo "ags" ;;
    nw-plots)      echo "oid,aktualit,idflurst,flaeche,flstkennz,land,landschl,gemarkung,gemaschl,flur,flurschl,flstnrzae,flstnrnen,regbezirk,regbezschl,kreis,kreisschl,gemeinde,gmdschl,abwrecht,lagebeztxt,tntxt" ;;
    nw-structures) echo "oid,aktualit,gebnutzbez,funktion,gfkzshh,rellage,name,anzahlgs,gmdschl,lagebeztxt" ;;
    *) return 1 ;;
  esac
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
    *) return 1 ;;
  esac
}

structures_select() {
  case "$1" in
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
    nw) cat <<'EOF'
  oid                                                    AS local_id,
  coalesce(nullif(funktion, ''), nullif(gebnutzbez, ''), 'Gebäude')  AS type,
  aktualit                                               AS date_src
EOF
        ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------------------

# Echoes "state kind dir layer reader glob" for each dataset that is selected and has files.
selected_datasets() {
  local line state kind dir layer reader glob
  for line in "${DATASETS[@]}"; do
    read -r state kind dir layer reader glob <<<"$line"
    [[ -n "${STATES:-}" ]] && [[ " $STATES " != *" $state "* ]] && continue
    [[ -n "${KINDS:-}"  ]] && [[ " $KINDS "  != *" $kind "*  ]] && continue
    [[ -d "$ALKIS_DIR/$dir" ]] || continue
    compgen -G "$ALKIS_DIR/$dir/$glob" >/dev/null || continue
    echo "$state $kind $dir $layer $reader $glob"
  done
}

# One path per line. A download may still be running — download_all.sh writes into the same
# tree — so two kinds of half-written file are skipped rather than fed to ogr2ogr:
# anything aria2c still holds a .aria2 control file for, and anything touched in the last
# SETTLE seconds, which is how the WFS pagers' part-NNNNN.gml appear while being written.
SETTLE="${SETTLE:-60}"
source_files() {  # dir glob
  local f now age
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
  local state kind dir layer reader glob n sz
  while read -r state kind dir layer reader glob; do
    n=$(source_files "$dir" "$glob" | wc -l | tr -d ' ')
    sz=$(du -sh "$ALKIS_DIR/$dir" 2>/dev/null | cut -f1)
    printf '%-3s %-11s %-16s %-17s %8s %10s\n' "$state" "$kind" "$dir" "$layer" "$n" "${sz:-?}"
  done < <(selected_datasets)
  echo
  echo "Not loaded: bw-nas (same content as bw-shape, needs a GFS mapping), by-tn (land use),"
  echo "            st (empty). Bayern publishes no open vector Flurstücke, so it has no plots."
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
  local ds tmp
  ds="$(datasource_for "$reader" "$src" "$layer")"
  tmp="$out.partial"
  rm -f "$tmp"
  # GEOMETRY_NAME normalises what each driver calls its geometry column (GML says geom, the
  # GeoPackage says geometrie, Shapefile says geometry) so the load SQL is source-agnostic.
  # GDAL_PAM_ENABLED=NO: otherwise every conversion drops a .aux.xml sidecar next to its
  # output, which nothing here reads and which the .partial rename would leave behind.
  if ! ogr2ogr -f Parquet "$tmp" "$ds" "$layer" \
        -select "$fields" \
        -nlt MULTIPOLYGON -t_srs EPSG:4326 \
        -lco GEOMETRY_ENCODING=WKB -lco GEOMETRY_NAME=geom -lco COMPRESSION=ZSTD \
        -lco FID=ogc_fid -lco WRITE_COVERING_BBOX=NO \
        --config GDAL_PAM_ENABLED NO \
        2> >(grep -v 'Warning' >&2 || true); then
    rm -f "$tmp" "$tmp.aux.xml"
    echo "  ! failed: $src" >&2
    return 1
  fi
  rm -f "$tmp.aux.xml"
  mv "$tmp" "$out"
}
export -f stage_one datasource_for

stage_dataset() {  # state kind dir layer reader glob -> stage dir on stdout
  local state="$1" kind="$2" dir="$3" layer="$4" reader="$5" glob="$6"
  local sd="$STAGE_DIR/$state-$kind" src out todo=0 have=0 jobfile
  mkdir -p "$sd"

  export STAGE_LAYER="$layer" STAGE_READER="$reader"
  STAGE_FIELDS="$(fields_for "$state-$kind")"; export STAGE_FIELDS

  jobfile="$sd/.jobs"
  : > "$jobfile"
  while IFS= read -r src; do
    out="$sd/$(basename "${src%.*}").parquet"
    if [[ -s "$out" && "$out" -nt "$src" ]]; then have=$((have + 1)); continue; fi
    printf '%s\0%s\0' "$src" "$out" >> "$jobfile"   # NUL-separated: paths carry umlauts
    todo=$((todo + 1))
  done < <(source_files "$dir" "$glob")

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
if [[ "${1:-}" == "--list" ]]; then list_plan; fi

DB="${1:-./alkis.duckdb}"

need ogr2ogr gdal
need duckdb duckdb

[[ -d "$ALKIS_DIR" ]] || { echo "ERROR: $ALKIS_DIR not found — run ./download_all.sh alkis first." >&2; exit 1; }

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

for line in "${PLAN[@]}"; do
  read -r state kind dir layer reader glob <<<"$line"
  echo "== $state-$kind  ($dir / $layer)"
  sd="$(stage_dataset "$state" "$kind" "$dir" "$layer" "$reader" "$glob")"
  compgen -G "$sd/*.parquet" >/dev/null || { echo "  ! nothing staged, skipping" >&2; continue; }
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
echo "Done. Query it with:  duckdb $DB -c \"LOAD spatial; SELECT * FROM plots LIMIT 5;\""
