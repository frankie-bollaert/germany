#!/usr/bin/env bash
#
# convert_to_cloud_optimized.sh — convert downloaded LiDAR tiles to cloud-optimized formats.
#
#   dgm1 GeoTIFF   ->  COG  (Cloud Optimized GeoTIFF)   via GDAL   [rlp]
#   dgm1 XYZ .zip  ->  COG  (Cloud Optimized GeoTIFF)   via GDAL   [bw — unzips 4 tiles per zip]
#   las  .laz      ->  COPC (.copc.laz)                 via PDAL   [rlp only]
#
# Recipes (validated on RLP and BW sample tiles):
#   COG : Float32 DEM, ZSTD + PREDICTOR=3 (floating-point), AVERAGE overviews, 512 blocks.
#         (LERC would be ideal but this GDAL build lacks the codec; ZSTD p3 is the best available
#          and universally readable. Override with COG_COMPRESS / COG_PRED if your GDAL has LERC.)
#         BW ships ASCII XYZ without a CRS, so its tiles get -a_srs EPSG:25832 stamped on.
#         (29 MB XYZ -> ~1.8 MB COG, 1000x1000 px @ 1 m.)
#   COPC: pdal translate -> .copc.laz (octree-indexed, cloud-streamable). ~189MB LAZ -> ~144MB COPC.
#
# Output layout (under <output_base>, default "."):
#   dgm1 (DTM)         -> dtm/de/<state>/*.tif
#   las  (point cloud) -> point-cloud/de/<state>/*.copc.laz
#
# Usage : ./convert_to_cloud_optimized.sh [rlp|bw] [dgm1|las|both] [input_base] [output_base]
#   ./convert_to_cloud_optimized.sh dgm1                    # ./rlp_lidar/dgm1 -> ./dtm/de/rlp
#   ./convert_to_cloud_optimized.sh las ./rlp_lidar /data   # -> /data/point-cloud/de/rlp
#   ./convert_to_cloud_optimized.sh bw dgm1                 # ./bw_lidar/dgm1  -> ./dtm/de/bw
#   ./convert_to_cloud_optimized.sh both
#
# The state token is optional and defaults to rlp, so existing invocations keep working.
#
# Env vars:
#   JOBS=<n>        parallel conversions (default: CPU count)
#   COG_COMPRESS    default ZSTD     COG_PRED  default 3     COG_LEVEL default 22
#   KEEP=0          delete each source file after a verified conversion (default 1 = keep)
#   DRY_RUN=1       list what would be converted, do nothing
#
set -euo pipefail

# ---- hidden per-file worker modes (so xargs can re-invoke this script; bash 3.2 safe) ----
if [ "${1:-}" = "__cog" ]; then
  src="$2"; dst="$3"
  [ -s "$dst" ] && [ "$dst" -nt "$src" ] && { echo "skip  $(basename "$dst")"; exit 0; }
  tmp="$dst.part"
  gdal_translate "$src" "$tmp" -of COG \
    -co COMPRESS="${COG_COMPRESS:-ZSTD}" -co PREDICTOR="${COG_PRED:-3}" -co LEVEL="${COG_LEVEL:-22}" \
    -co RESAMPLING=AVERAGE -co OVERVIEWS=AUTO -co BLOCKSIZE=512 \
    -co NUM_THREADS=ALL_CPUS -co BIGTIFF=IF_SAFER -q \
    && mv -f "$tmp" "$dst" && echo "COG   $(basename "$dst")" \
    || { rm -f "$tmp"; echo "FAIL  $(basename "$src")" >&2; exit 1; }
  [ "${KEEP:-1}" = "0" ] && rm -f "$src"
  exit 0
fi
if [ "${1:-}" = "__cogzip" ]; then
  # BW: one 2x2 km zip holds four 1x1 km ASCII-XYZ tiles (+ .csv metadata we don't convert).
  src="$2"; out="$3"
  members="$(unzip -Z1 "$src" '*.xyz' 2>/dev/null || true)"
  [ -n "$members" ] || { echo "FAIL  $(basename "$src") (no .xyz inside)" >&2; exit 1; }
  # Cheap skip: every output already there and newer than the zip -> don't even unpack.
  stale=0
  for m in $members; do
    b="$(basename "$m" .xyz)"
    { [ -s "$out/$b.tif" ] && [ "$out/$b.tif" -nt "$src" ]; } || stale=1
  done
  [ "$stale" = "0" ] && { echo "skip  $(basename "$src")"; exit 0; }
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/cogzip.XXXXXX")"
  trap 'rm -rf "$tmpd"' EXIT
  unzip -q -j -o "$src" '*.xyz' -d "$tmpd"
  rc=0
  for f in "$tmpd"/*.xyz; do
    b="$(basename "$f" .xyz)"; dst="$out/$b.tif"; tmp="$dst.part"
    # XYZ carries no CRS/type: stamp ETRS89/UTM32 and force Float32 heights.
    gdal_translate "$f" "$tmp" -of COG -a_srs EPSG:25832 -ot Float32 \
      -co COMPRESS="${COG_COMPRESS:-ZSTD}" -co PREDICTOR="${COG_PRED:-3}" -co LEVEL="${COG_LEVEL:-22}" \
      -co RESAMPLING=AVERAGE -co OVERVIEWS=AUTO -co BLOCKSIZE=512 \
      -co NUM_THREADS=ALL_CPUS -co BIGTIFF=IF_SAFER -q \
      && mv -f "$tmp" "$dst" && echo "COG   $b.tif" \
      || { rm -f "$tmp"; echo "FAIL  $b" >&2; rc=1; }
  done
  [ "$rc" = "0" ] && [ "${KEEP:-1}" = "0" ] && rm -f "$src"
  exit "$rc"
fi
if [ "${1:-}" = "__copc" ]; then
  src="$2"; dst="$3"
  [ -s "$dst" ] && [ "$dst" -nt "$src" ] && { echo "skip  $(basename "$dst")"; exit 0; }
  tmp="$dst.part.copc.laz"
  pdal translate "$src" "$tmp" --writers.copc.filename="$tmp" >/dev/null 2>&1 \
    && mv -f "$tmp" "$dst" && echo "COPC  $(basename "$dst")" \
    || { rm -f "$tmp"; echo "FAIL  $(basename "$src")" >&2; exit 1; }
  [ "${KEEP:-1}" = "0" ] && rm -f "$src"
  exit 0
fi

# ---- main ----
# Optional leading state token; defaults to rlp so the original CLI is unchanged.
STATE="rlp"
case "${1:-}" in rlp|bw) STATE="$1"; shift ;; esac

DATASET="${1:-dgm1}"
INROOT="${2:-./${STATE}_lidar}"
OUTBASE="${3:-.}"
# ISO-style output trees, keyed by product type (country de / subdivision rlp|bw).
OUT_DTM="$OUTBASE/dtm/de/$STATE"
OUT_PC="$OUTBASE/point-cloud/de/$STATE"
JOBS="${JOBS:-$( (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4 )}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found — $2" >&2; exit 1; }; }

convert_dgm1() {
  need gdal_translate "brew install gdal"
  local in="$INROOT/dgm1" out="$OUT_DTM"
  [ -d "$in" ] || { echo "no input dir: $in (run the downloader first)"; return 0; }
  mkdir -p "$out"

  if [ "$STATE" = "bw" ]; then
    # BW ships zipped ASCII XYZ: 1 zip (2x2 km) -> 4 COGs (1x1 km).
    need unzip "it ships with macOS; apt install unzip"
    local n; n=$(find "$in" -maxdepth 1 -type f -name '*.zip' | wc -l | tr -d ' ')
    echo "==> dgm1 -> COG  | $n zips (~$((n * 4)) tiles) | $JOBS parallel | $in -> $out"
    [ "${DRY_RUN:-0}" = "1" ] && { find "$in" -maxdepth 1 -type f -name '*.zip' | head; echo "...(DRY_RUN)"; return 0; }
    find "$in" -maxdepth 1 -type f -name '*.zip' -print0 \
      | xargs -0 -P "$JOBS" -I{} bash -c 'exec "$0" __cogzip "{}" "$1"' "$SELF" "$out"
    return 0
  fi

  local n; n=$(find "$in" -maxdepth 1 -type f -name '*.tif' | wc -l | tr -d ' ')
  echo "==> dgm1 -> COG  | $n GeoTIFFs | $JOBS parallel | $in -> $out"
  [ "${DRY_RUN:-0}" = "1" ] && { find "$in" -maxdepth 1 -type f -name '*.tif' | head; echo "...(DRY_RUN)"; return 0; }
  find "$in" -maxdepth 1 -type f -name '*.tif' -print0 \
    | xargs -0 -P "$JOBS" -I{} bash -c 'b=$(basename "{}"); exec "$0" __cog "{}" "$1/$b"' "$SELF" "$out"
}

convert_las() {
  if [ "$STATE" = "bw" ]; then
    echo "==> las: skipped — nothing downloaded; BW's ALS_2 ships on a paid LGL order."
    return 0
  fi
  need pdal "brew install pdal"
  local in="$INROOT/las" out="$OUT_PC"
  [ -d "$in" ] || { echo "no input dir: $in (run the downloader first)"; return 0; }
  mkdir -p "$out"
  local n; n=$(find "$in" -maxdepth 1 -type f -name '*.laz' ! -name '*.copc.laz' | wc -l | tr -d ' ')
  echo "==> las -> COPC  | $n LAZ tiles | $JOBS parallel | $in -> $out"
  echo "    note: COPC is CPU-heavy (~20-30s/tile); full state is ~21k tiles."
  [ "${DRY_RUN:-0}" = "1" ] && { find "$in" -maxdepth 1 -type f -name '*.laz' ! -name '*.copc.laz' | head; echo "...(DRY_RUN)"; return 0; }
  find "$in" -maxdepth 1 -type f -name '*.laz' ! -name '*.copc.laz' -print0 \
    | xargs -0 -P "$JOBS" -I{} bash -c 'b=$(basename "{}" .laz); exec "$0" __copc "{}" "$1/$b.copc.laz"' "$SELF" "$out"
}

case "$DATASET" in
  dgm1) convert_dgm1 ;;
  las)  convert_las ;;
  both) convert_dgm1; convert_las ;;
  *) echo "Usage: $0 [rlp|bw] [dgm1|las|both] [input_base] [output_base]" >&2; exit 2 ;;
esac
echo "done."
