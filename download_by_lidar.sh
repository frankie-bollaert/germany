#!/usr/bin/env bash
#
# download_by_lidar.sh — bulk-download the Bayern (Germany) LiDAR open data.
#
# Source : Landesamt für Digitalisierung, Breitband und Vermessung (LDBV Bayern)
#          OpenData portal https://geodaten.bayern.de/opengeodata/
# License : Datenlizenz Deutschland – Namensnennung 2.0 (DL-DE/BY 2.0) — attribution REQUIRED:
#           "Datenquelle: Bayerische Vermessungsverwaltung – www.geodaten.bayern.de, dl-de/by-2-0"
# CRS     : ETRS89 / UTM Zone 32 (EPSG:25832); heights DHHN2016.
# Tiling  : 1 km x 1 km, SW corner snapped to whole km — same grid origin as RLP/BW.
#
# Datasets (verified live):
#   las  — classified airborne laser point cloud ("Laserdaten"), .laz
#          statewide: ~70,000 tiles, multiple TB
#   dgm1 — bare-earth terrain model, 1 m grid, GeoTIFF
#          statewide: 71,979 tiles, ~217 GB
#
# Method  : the two products are published very differently.
#
#   dgm1 — an official Metalink-4 (.meta4) manifest for the whole state, carrying per-tile
#          size + SHA-256 + two mirror URLs. Fed straight to aria2c: parallel, resumable,
#          hash-verified. Identical handling to download_rlp_lidar.sh.
#
#   las  — NO statewide manifest exists. The point cloud is only served through the
#          "poly2metalink" polygon service, which is capped at 2000 km² per request. This
#          script therefore walks a grid of 40x40 km (=1600 km²) polygons over Bavaria,
#          POSTs each as EWKT, and merges the returned metalinks into one aria2 input file.
#          The resulting tile list is always current rather than hard-coded.
#          These metalinks carry URLs only — no sizes, no checksums — so LAS downloads are
#          resumable but NOT hash-verified (unlike dgm1).
#
# Usage   : ./download_by_lidar.sh [dgm1|las|both] [output_dir]
#   ./download_by_lidar.sh dgm1                 # ~217 GB into ./by_lidar/dgm1
#   ./download_by_lidar.sh las  /mnt/big/by     # multi-TB — mind your disk!
#   ./download_by_lidar.sh both
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   OUTDIR=<path>  write the files straight here, instead of <output_dir>/<dataset>.
#                  Single-dataset runs only — with "both" the two products would collide.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#   BBOX="minE,minN,maxE,maxN"   # UTM32 kilometres, subsets the las polygon sweep
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./by_lidar}"
JOBS="${JOBS:-8}"          # concurrent tiles
CONN="${CONN:-4}"          # connections per tile
DRY_RUN="${DRY_RUN:-0}"    # set 1 to only print the tile-list summary

DGM1_META4="https://geodaten.bayern.de/odd/a/dgm/dgm1/meta/metalink/09.meta4"
POLY2META="https://geoservices.bayern.de/services/poly2metalink/metalink/laser"

# Bavaria's extent in EPSG:25832 kilometres, rounded outward to the 40 km sweep step.
BY_MINE=560; BY_MAXE=960; BY_MINN=5230; BY_MAXN=5610
STEP=40                    # 40x40 km = 1600 km² < the service's 2000 km² cap

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

# ---------------------------------------------------------------- dgm1: statewide metalink
fetch_dgm1() {
  local dir="${OUTDIR:-$OUTROOT/dgm1}"
  echo "==> dgm1"
  echo "    manifest: $DGM1_META4"
  mkdir -p "$dir"

  # Always re-fetch: the manifest is regenerated as new campaigns land.
  local m4="$dir/.manifest.meta4"
  curl -fsS "$DGM1_META4" -o "$m4"

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

# ---------------------------------------------------------------- las: polygon sweep
fetch_las() {
  local dir="${OUTDIR:-$OUTROOT/las}"
  echo "==> las"
  echo "    service : $POLY2META  (2000 km²/request — swept in ${STEP}x${STEP} km polygons)"
  mkdir -p "$dir"

  local mine="$BY_MINE" minn="$BY_MINN" maxe="$BY_MAXE" maxn="$BY_MAXN"
  if [[ -n "${BBOX:-}" ]]; then
    IFS=, read -r mine minn maxe maxn <<<"$BBOX"
    echo "    BBOX    : $mine,$minn,$maxe,$maxn (UTM32 km)"
  fi

  local urls="$dir/.urls.txt"
  : >"$urls.tmp"

  # Sweep the bounding box; each cell is one POSTed EWKT polygon. Cells are clipped to the
  # box: without that, a cell always spans the full STEP, so a BBOX smaller than 40 km — a
  # sample square, say — would be silently widened to 40x40 km and return the whole area's
  # tiles. The service takes any polygon, so the last cell in each direction is simply short.
  local e n e2 n2 cells=0
  for (( e = mine; e < maxe; e += STEP )); do
    for (( n = minn; n < maxn; n += STEP )); do
      e2=$(( e + STEP )); (( e2 > maxe )) && e2=$maxe
      n2=$(( n + STEP )); (( n2 > maxn )) && n2=$maxn
      local ewkt="SRID=25832;MULTIPOLYGON((($((e*1000)) $((n*1000)), $((e2*1000)) $((n*1000)), $((e2*1000)) $((n2*1000)), $((e*1000)) $((n2*1000)), $((e*1000)) $((n*1000)))))"
      curl -fsS --max-time 180 -X POST --data-binary "$ewkt" "$POLY2META" \
        | grep -oE '<url>[^<]+</url>' | sed 's|<url>||;s|</url>||' >>"$urls.tmp" || true
      cells=$(( cells + 1 ))
      printf "\r    swept %d polygons, %d urls" "$cells" "$(wc -l <"$urls.tmp" | tr -d ' ')" >&2
    done
  done
  echo >&2

  # Cells overlap nothing, but a tile on a seam can be returned twice — dedupe.
  sort -u "$urls.tmp" >"$urls"
  rm -f "$urls.tmp"
  echo "    tiles: $(wc -l <"$urls" | tr -d ' ')  |  no sizes/checksums published — resumable but not hash-verified"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi

  aria2c \
    --input-file="$urls" \
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
  dgm1) fetch_dgm1 ;;
  las)  fetch_las ;;
  both) fetch_dgm1; fetch_las ;;
  *) echo "Usage: $0 [dgm1|las|both] [output_dir]" >&2; exit 2 ;;
esac

cat <<EOF

Attribution required (DL-DE/BY 2.0) — include in any product/publication:
  Datenquelle: Bayerische Vermessungsverwaltung – www.geodaten.bayern.de, dl-de/by-2-0
EOF
