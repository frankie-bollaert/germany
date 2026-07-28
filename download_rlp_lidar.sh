#!/usr/bin/env bash
#
# download_rlp_lidar.sh — bulk-download the Rheinland-Pfalz (Germany) LiDAR open data.
#
# Source : Landesamt für Vermessung und Geobasisinformation Rheinland-Pfalz (LVermGeo RLP)
#          GeoShop https://geoshop.rlp.de  ·  files on https://geobasis-rlp.de
# License : Datenlizenz Deutschland – Namensnennung 2.0 (DL-DE/BY 2.0) — attribution REQUIRED:
#           "©GeoBasis-DE / LVermGeoRP <year>, dl-de/by-2-0, www.lvermgeo.rlp.de"
# CRS     : ETRS89 / UTM Zone 32 (EPSG:25832); LAZ vertical may be compound EPSG:5555.
# Tiling  : 1 km x 1 km, SW corner snapped to whole km.
#
# Datasets (verified live):
#   las  — classified point cloud, combined surface+terrain (LPO+LPG), .laz
#          statewide: ~21,207 tiles, ~5.18 TB
#   dgm1 — bare-earth terrain model, 1 m grid, GeoTIFF
#          statewide: ~21,082 tiles, ~32.8 GB
#
# Method  : official Metalink-4 (.meta4) manifests fed to aria2c. The manifest carries
#           per-tile size + SHA-256, so downloads are parallel, resumable and verified.
#
# Usage   : ./download_rlp_lidar.sh [dgm1|las|both] [output_dir]
#   ./download_rlp_lidar.sh dgm1                 # ~33 GB into ./rlp_lidar/dgm1
#   ./download_rlp_lidar.sh las  /mnt/big/rlp    # ~5.2 TB — mind your disk!
#   ./download_rlp_lidar.sh both
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./rlp_lidar}"
JOBS="${JOBS:-8}"          # concurrent tiles
CONN="${CONN:-4}"          # connections per tile
DRY_RUN="${DRY_RUN:-0}"    # set 1 to only print the manifest summary

# Map dataset key -> statewide Metalink-4 manifest URL (portable; macOS ships bash 3.2).
meta_url() {
  case "$1" in
    las)  echo "https://geobasis-rlp.de/data/las/current/meta4/las_las_07.meta4" ;;
    dgm1) echo "https://geobasis-rlp.de/data/dgm1/current/meta4/dgm1_tif_07.meta4" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" url dir="$OUTROOT/$1"
  url="$(meta_url "$1")"
  echo "==> $key"
  echo "    manifest: $url"
  mkdir -p "$dir"

  # Always re-fetch the manifest: data lives under /current/ and is regenerated as coverage updates.
  local m4="$dir/.manifest.meta4"
  curl -fsS "$url" -o "$m4"

  # Report what we're about to pull.
  python3 - "$m4" <<'PY'
import sys, re
x = open(sys.argv[1], encoding="utf-8", errors="replace").read()
n = len(re.findall(r'<file ', x))
tot = sum(int(s) for s in re.findall(r'<size>(\d+)</size>', x))
print(f"    tiles: {n}  |  total: {tot/1e9:.1f} GB  |  manifest carries SHA-256 per tile")
PY

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi

  # aria2c reads .meta4 natively: parallel, --continue resumes, --check-integrity verifies SHA-256.
  aria2c \
    --metalink-file="$m4" \
    --dir="$dir" \
    --max-concurrent-downloads="$JOBS" \
    --max-connection-per-server="$CONN" \
    --split="$CONN" \
    --continue=true \
    --check-integrity=true \
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
  ©GeoBasis-DE / LVermGeoRP $(date +%Y), dl-de/by-2-0, www.lvermgeo.rlp.de
EOF
