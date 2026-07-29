#!/usr/bin/env bash
#
# download_nrw_lidar.sh — bulk-download the Nordrhein-Westfalen (Germany) LiDAR open data.
#
# Source : Geobasis NRW (Bezirksregierung Köln) · https://www.opengeodata.nrw.de
# License : Datenlizenz Deutschland – Zero 2.0 (DL-DE/Zero-2-0) — no attribution obligation,
#           but crediting "© Geobasis NRW <year>" is good practice.
# CRS     : ETRS89 / UTM Zone 32 (EPSG:25832); heights DHHN2016.
# Tiling  : 1 km x 1 km, SW corner snapped to whole km — same grid origin as RLP/BW/BY.
#
# Datasets (verified live):
#   las  — 3D-Messdaten Laserscanning, classified point cloud, .laz
#          statewide: 35,860 tiles, ~3.49 TB
#   dgm1 — bare-earth terrain model, 1 m grid, GeoTIFF
#          statewide: 35,860 tiles, ~78.8 GB
#
# Method  : NRW publishes a machine-readable index.json per product listing every tile with
#           its byte size and timestamp. The script fetches that index, writes an aria2c
#           input file with an explicit --out per tile, and lets aria2c do the transfer:
#           parallel, resumable, size-checked. The tile list is rebuilt on every run.
#
#           No checksums are published, so downloads are size-verified but NOT hash-verified
#           (unlike RLP and BY dgm1).
#
# Usage   : ./download_nrw_lidar.sh [dgm1|las|both] [output_dir]
#   ./download_nrw_lidar.sh dgm1                  # ~79 GB into ./nrw_lidar/dgm1
#   ./download_nrw_lidar.sh las  /mnt/big/nrw     # ~3.5 TB — mind your disk!
#   ./download_nrw_lidar.sh both
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   OUTDIR=<path>  write the files straight here, instead of <output_dir>/<dataset>.
#                  Single-dataset runs only — with "both" the two products would collide.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#   BBOX="minE,minN,maxE,maxN"   # UTM32 kilometres, inclusive, subsets the tile list
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./nrw_lidar}"
JOBS="${JOBS:-8}"
CONN="${CONN:-4}"
DRY_RUN="${DRY_RUN:-0}"

BASE="https://www.opengeodata.nrw.de/produkte/geobasis/hm"

# Map dataset key -> product folder (portable; macOS ships bash 3.2).
product_dir() {
  case "$1" in
    las)  echo "3dm_l_las" ;;
    dgm1) echo "dgm1_tiff" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" prod dir="${OUTDIR:-$OUTROOT/$1}"
  prod="$(product_dir "$1")"
  local index="$BASE/$prod/$prod/index.json"
  echo "==> $key"
  echo "    index: $index"
  mkdir -p "$dir"

  # Always re-fetch the index — coverage grows as new campaigns are published.
  local idx="$dir/.index.json"
  curl -fsS "$index" -o "$idx"

  local input="$dir/.aria2.input"
  python3 - "$idx" "$BASE/$prod/$prod" "$input" "${BBOX:-}" <<'PY'
import sys, json, re

idx, base, out, bbox = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
data = json.load(open(idx, encoding="utf-8"))

box = None
if bbox:
    mine, minn, maxe, maxn = (int(v) for v in bbox.split(","))
    box = (mine, minn, maxe, maxn)

# Tile names embed the SW corner in km: dgm1_32_280_5652_1_nw_2022.tif / 3dm_32_280_5652_1_nw.laz
tile_re = re.compile(r'_32_(\d+)_(\d+)_')

n = tot = skipped = 0
with open(out, "w", encoding="utf-8") as fh:
    for ds in data.get("datasets", []):
        for f in ds.get("files", []):
            name = f["name"]
            if box:
                m = tile_re.search(name)
                if not m:
                    skipped += 1
                    continue
                e, nn = int(m.group(1)), int(m.group(2))
                if not (box[0] <= e <= box[2] and box[1] <= nn <= box[3]):
                    continue
            fh.write(f"{base}/{name}\n  out={name}\n")
            n += 1
            tot += int(f["size"])

print(f"    tiles: {n}  |  total: {tot/1e9:.1f} GB  |  no checksums published (size-checked only)")
if skipped:
    print(f"    note: {skipped} file(s) had no parseable tile coordinate and were dropped by BBOX")
PY

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi

  aria2c \
    --input-file="$input" \
    --dir="$dir" \
    --max-concurrent-downloads="$JOBS" \
    --max-connection-per-server="$CONN" \
    --split="$CONN" \
    --continue=true \
    --auto-file-renaming=false \
    --conditional-get=true \
    --console-log-level=warn \
    --summary-interval=30 \
    --save-session="$dir/.aria2.session" \
    --log="$dir/.aria2.log"

  echo "    done -> $dir"
}

case "$DATASET" in
  las|dgm1) fetch_one "$DATASET" ;;
  both)     fetch_one dgm1; fetch_one las ;;
  *) echo "Usage: $0 [dgm1|las|both] [output_dir]" >&2; exit 2 ;;
esac

cat <<EOF

License: Datenlizenz Deutschland – Zero 2.0 (no attribution required).
Courtesy credit:  © Geobasis NRW $(date +%Y)
EOF
