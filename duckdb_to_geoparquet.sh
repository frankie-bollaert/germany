#!/usr/bin/env bash
#
# duckdb_to_geoparquet.sh — export the DuckDB tables that alkis_to_duckdb.sh built
# to (Geo)Parquet.
#
# DuckDB writes GeoParquet 1.0 natively: with the spatial extension loaded, a plain
# `COPY ... (FORMAT PARQUET)` emits the "geo" metadata key that GDAL, QGIS and GeoPandas
# read. There is no separate format name for it, and the FORMAT GDAL route is not an
# option here — DuckDB's bundled GDAL has no Parquet driver.
#
# The export always opens the database read-only, so it is safe to run while the file is
# open in QGIS. QGIS holds a write lock; without -readonly DuckDB refuses to attach.
#
#   table               geometry  partitioned by   what it is
#   ------------------  --------  ---------------  ------------------------------------
#   plots               yes       region           Flurstücke, one row each
#   structures          NO        local_id_region  footprint identity only, no geometry
#   structure_versions  yes       —                footprint geometry + structure_id FK
#   footprints          yes       local_id_region  derived: the two above joined flat
#
# `footprints` is not a table. It is the structures/structure_versions join collapsed into
# one self-contained spatial layer, which is usually what a downstream GIS actually wants —
# the split into identity and version is a database concern, not a file-format one. Ask for
# it by name; it is not in the default set, because it is the same data as
# structure_versions in a second shape.
#
# CRS: everything alkis_to_duckdb.sh loads is EPSG:4326 in longitude/latitude order. DuckDB
# writes no explicit "crs" key, which per the GeoParquet spec means the default OGC:CRS84 —
# the same thing. GDAL resolves it back to EPSG:4326.
#
# Usage : ./duckdb_to_geoparquet.sh [db_path] [output_dir]
#   ./duckdb_to_geoparquet.sh                         # ./alkis.duckdb -> ./export
#   ./duckdb_to_geoparquet.sh alkis.duckdb /mnt/out
#   TABLES="plots footprints" ./duckdb_to_geoparquet.sh
#   PARTITION=0 ./duckdb_to_geoparquet.sh             # one flat file per table
#   DRY_RUN=1 ./duckdb_to_geoparquet.sh               # print the plan, write nothing
#
# Env vars (override defaults):
#   TABLES="plots structures structure_versions"   which to export; add `footprints`
#   PARTITION=1        0 = one flat file per table instead of a hive-partitioned directory
#   COMPRESSION=ZSTD   ZSTD | SNAPPY | GZIP | NONE
#   VERIFY=1           0 = skip reading each export back to count its rows
#
set -euo pipefail

DB="${1:-./alkis.duckdb}"
OUT="${2:-./export}"
TABLES="${TABLES:-plots structures structure_versions}"
PARTITION="${PARTITION:-1}"
COMPRESSION="${COMPRESSION:-ZSTD}"
VERIFY="${VERIFY:-1}"
DRY_RUN="${DRY_RUN:-0}"

usage() {
  cat >&2 <<'EOF'
Usage: ./duckdb_to_geoparquet.sh [db_path] [output_dir]

  db_path     DuckDB file to read (default ./alkis.duckdb)
  output_dir  where to write (default ./export)

Env: TABLES="plots structures structure_versions footprints" PARTITION=1
     COMPRESSION=ZSTD VERIFY=1 DRY_RUN=1
EOF
  exit 2
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage

command -v duckdb >/dev/null 2>&1 || {
  echo "ERROR: duckdb not found. Install it:  brew install duckdb  (macOS)  |  apt install duckdb" >&2
  exit 1
}
[[ -f "$DB" ]] || { echo "ERROR: $DB not found — run ./alkis_to_duckdb.sh first." >&2; exit 1; }

# Always read-only: the export never writes to the database, and this is what lets it run
# while QGIS (or anything else) holds the write lock.
duck() { duckdb -readonly "$DB" -c "LOAD spatial; $1"; }

# Same, but for a single value: -noheader -list strips the box drawing and the type row,
# which otherwise contribute their own digits ("int64") to anything parsing the output.
duck_scalar() { duckdb -readonly -noheader -list "$DB" -c "LOAD spatial; $1"; }

# The column each table is partitioned on, empty where there is nothing sensible to split
# by. structure_versions carries no region of its own — it reaches one only through
# structures, which is exactly what `footprints` resolves.
partition_col() {
  case "$1" in
    plots)              echo "region" ;;
    structures)         echo "local_id_region" ;;
    footprints)         echo "local_id_region" ;;
    structure_versions) echo "" ;;
    *)                  echo "" ;;
  esac
}

# What to SELECT. Real tables export as themselves; `footprints` is the join.
source_sql() {
  case "$1" in
    footprints) cat <<'EOF'
SELECT s.local_id, s.local_id_region, v.type, v.valid_from, v.valid_to, v.geometry
FROM structure_versions v
JOIN structures s ON s.id = v.structure_id
EOF
      ;;
    *) echo "SELECT * FROM $1" ;;
  esac
}

# `footprints` is derived, so it needs both of the tables it joins.
have_tables() {  # one or more table names
  local want=0 got
  for _ in "$@"; do want=$((want + 1)); done
  got=$(duck_scalar "SELECT count(*) FROM duckdb_tables() WHERE table_name IN ('$(printf '%s' "$1")'$(shift; for t in "$@"; do printf ", '%s'" "$t"; done));" 2>/dev/null | tr -dc '0-9')
  [[ "${got:-0}" -eq "$want" ]]
}

table_exists() {
  case "$1" in
    footprints) have_tables structures structure_versions ;;
    *)          have_tables "$1" ;;
  esac
}

echo "Database : $DB (read-only)"
echo "Output   : $OUT"
echo "Tables   : $TABLES"
echo "Layout   : $([[ "$PARTITION" == "1" ]] && echo 'hive-partitioned directories' || echo 'one flat file each'), $COMPRESSION"
echo

if [[ "$DRY_RUN" != "1" ]]; then
  mkdir -p "$OUT"
fi

for t in $TABLES; do
  if ! table_exists "$t"; then
    echo "== $t — not in this database, skipping" >&2
    continue
  fi

  pcol="$(partition_col "$t")"
  [[ "$PARTITION" == "1" ]] || pcol=""

  if [[ -n "$pcol" ]]; then
    dest="$OUT/$t"
    opts="FORMAT PARQUET, PARTITION_BY ($pcol), COMPRESSION $COMPRESSION, OVERWRITE"
    shape="partitioned by $pcol"
  else
    dest="$OUT/$t.parquet"
    opts="FORMAT PARQUET, COMPRESSION $COMPRESSION"
    shape="single file"
  fi

  echo "== $t -> $dest  ($shape)"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "   COPY ($(source_sql "$t" | tr '\n' ' ')) TO '$dest' ($opts);"
    continue
  fi

  duck "COPY ($(source_sql "$t")) TO '$dest' ($opts);"

  if [[ "$VERIFY" == "1" ]]; then
    if [[ -n "$pcol" ]]; then
      read_expr="read_parquet('$dest/**/*.parquet', hive_partitioning = true)"
    else
      read_expr="read_parquet('$dest')"
    fi
    n=$(duck_scalar "SELECT count(*) FROM $read_expr;" 2>/dev/null | tr -dc '0-9' || true)
    sz=$(du -sh "$dest" 2>/dev/null | cut -f1)
    printf "   %s rows, %s\n" "${n:-?}" "${sz:-?}"
  fi
done

[[ "$DRY_RUN" == "1" ]] && exit 0

echo
echo "== Wrote"
du -sh "$OUT"/* 2>/dev/null || true
cat <<EOF

Read it back:
  duckdb -c "LOAD spatial; SELECT * FROM read_parquet('$OUT/plots/**/*.parquet', hive_partitioning = true) LIMIT 5;"
  ogrinfo -so -nomd $OUT/plots/region=be/data_0.parquet

A partitioned column lives in the directory name, not the data — pass
hive_partitioning = true to get it back, or set PARTITION=0 to keep it inline.
EOF
