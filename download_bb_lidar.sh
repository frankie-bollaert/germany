#!/usr/bin/env bash
#
# download_bb_lidar.sh — bulk-download the Brandenburg (Germany) LiDAR open data.
#
# Source : Landesvermessung und Geobasisinformation Brandenburg (LGB)
#          OpenGeodata.Brandenburg · https://data.geobasis-bb.de/geobasis/daten/
# License : Datenlizenz Deutschland – Namensnennung 2.0 (DL-DE/BY 2.0) — attribution REQUIRED:
#           "© GeoBasis-DE/LGB <year>, dl-de/by-2-0"
# CRS     : ETRS89 / UTM Zone 33 — EPSG:25833 (NOT 25832 like RLP/BW/BY/NRW —
#           Brandenburg sits east of the 12°E zone boundary); heights DHHN2016.
# Tiling  : 1 km x 1 km for both products, SW corner snapped to whole km.
#           Tile key in the filename is "33<E_km>-<N_km>", e.g. dgm_33250-5888.zip.
#
# Datasets (verified live):
#   las  — Laserscandaten, classified point cloud, one .laz per tile inside a .zip
#          ~13,086 tiles, ~100 MB/tile => on the order of 1.4 TB
#          NOTE: ALS coverage is partial and rolls out campaign by campaign — it is
#          markedly smaller than the dgm1 grid, which is complete statewide.
#   dgm1 — bare-earth terrain model, 1 m grid, GeoTIFF inside a .zip
#          ~31,291 tiles, ~1.3 MB/tile => on the order of 41 GB
#
# Method  : LGB serves both products from a plain indexed directory. The script parses the
#           Apache index, writes an aria2c input file, and downloads: parallel, resumable.
#           The tile list is rebuilt on every run, so new campaigns are picked up.
#
#           No checksums are published — downloads are size-checked, not hash-verified.
#
# Usage   : ./download_bb_lidar.sh [dgm1|las|both] [output_dir]
#   ./download_bb_lidar.sh dgm1                 # ~41 GB into ./bb_lidar/dgm1
#   ./download_bb_lidar.sh las  /mnt/big/bb     # ~1.4 TB — mind your disk!
#   ./download_bb_lidar.sh both
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   OUTDIR=<path>  write the files straight here, instead of <output_dir>/<dataset>.
#                  Single-dataset runs only — with "both" the two products would collide.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#   BBOX="minE,minN,maxE,maxN"   # UTM33 kilometres, inclusive
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./bb_lidar}"
JOBS="${JOBS:-8}"
CONN="${CONN:-4}"
DRY_RUN="${DRY_RUN:-0}"

# Map dataset key -> directory URL (portable; macOS ships bash 3.2).
dir_url() {
  case "$1" in
    las)  echo "https://data.geobasis-bb.de/geobasis/daten/als/laz/" ;;
    dgm1) echo "https://data.geobasis-bb.de/geobasis/daten/dgm/tif/" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" url dir="${OUTDIR:-$OUTROOT/$1}"
  url="$(dir_url "$1")"
  echo "==> $key"
  echo "    listing: $url"
  mkdir -p "$dir"

  local listing="$dir/.index.html"
  curl -fsS "$url" -o "$listing"

  local input="$dir/.aria2.input"
  python3 - "$listing" "$url" "$input" "${BBOX:-}" <<'PY'
import sys, re, html

listing, base, out, bbox = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(listing, encoding="utf-8", errors="replace").read()

box = None
if bbox:
    mine, minn, maxe, maxn = (int(v) for v in bbox.split(","))
    box = (mine, minn, maxe, maxn)

# Apache fancy index rows: <a href="dgm_33250-5888.zip">…</a> … <td class="indexcolsize">1.3M</td>
row_re = re.compile(
    r'<a href="((?:dgm|als)_33(\d{3})-(\d{4})\.zip)">.*?'
    r'<td class="indexcolsize">\s*([0-9.]+)([KMGT]?)\s*</td>',
    re.S)

UNIT = {"": 1, "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12}

n = 0
approx = 0.0
seen = set()
with open(out, "w", encoding="utf-8") as fh:
    for name, e, nn, num, unit in row_re.findall(s):
        name = html.unescape(name)
        if name in seen:
            continue
        seen.add(name)
        if box:
            e_i, n_i = int(e), int(nn)
            if not (box[0] <= e_i <= box[2] and box[1] <= n_i <= box[3]):
                continue
        fh.write(f"{base}{name}\n  out={name}\n")
        n += 1
        approx += float(num) * UNIT[unit]

print(f"    tiles: {n}  |  total: ~{approx/1e9:.1f} GB (from the index's rounded sizes)")
print(f"    no checksums published — resumable and size-checked, not hash-verified")
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

Attribution required (DL-DE/BY 2.0) — include in any product/publication:
  © GeoBasis-DE/LGB $(date +%Y), dl-de/by-2-0
EOF
