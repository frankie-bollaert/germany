#!/usr/bin/env bash
#
# download_ni_lidar.sh — bulk-download the Niedersachsen (Germany) LiDAR open data.
#
# Source : Landesamt für Geoinformation und Landesvermessung Niedersachsen (LGLN)
#          OpenGeoData.NI · https://opengeodata.lgln.niedersachsen.de
#          STAC API        · https://dgm.stac.lgln.niedersachsen.de
# License : CC-BY 4.0 (as declared by the STAC collection) — attribution REQUIRED:
#           "© LGLN <year>, CC BY 4.0"
# CRS     : ETRS89 / UTM Zone 32 (EPSG:25832); heights DHHN2016.
# Tiling  : 1 km x 1 km, SW corner snapped to whole km — same grid origin as RLP/BW/BY/NRW.
#
# Datasets (verified live):
#   dgm1 — bare-earth terrain model, 1 m grid, **already Cloud Optimized GeoTIFF**
#          statewide: on the order of 47,000 tiles
#
#   las  — NOT AVAILABLE. LGLN publishes no open airborne laser point cloud: the STAC
#          catalogue exposes only the `dgm1` collection (a sibling `dom` service covers the
#          surface model, also raster). `./download_ni_lidar.sh las` says so and exits.
#
# Method  : LGLN runs a STAC API. The script walks the paged item list, pulls each item's
#           `dgm1-tif` asset href, and writes an aria2c input file: parallel, resumable.
#           The tile list is rebuilt on every run, so new campaigns are picked up.
#
#           No checksums are published — downloads are size-checked, not hash-verified.
#
#           Because the tiles are already COGs, `convert_to_cloud_optimized.sh` is NOT
#           needed for this state — the download is the finished product.
#
# Usage   : ./download_ni_lidar.sh [dgm1] [output_dir]
#   ./download_ni_lidar.sh dgm1                 # -> ./ni_lidar/dgm1
#   ./download_ni_lidar.sh dgm1 /mnt/big/ni
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   BBOX="minLon,minLat,maxLon,maxLat"   # WGS84 degrees — the STAC API's own filter,
#                                        # NOT the UTM-km BBOX the other state scripts take
#   LATEST=0                             # keep EVERY campaign year (see below); default 1
#
# Campaign years: the catalogue holds ~70,000 items for ~48,000 km² because a km² that has
# been reflown appears once per campaign (dgm1_32_554_5802_1_ni_2016 and
# dgm1_32_597_5909_1_ni_2025 are both items). By default this script keeps only the newest
# year per tile coordinate, which is what you want for a seamless statewide DTM. Set
# LATEST=0 to mirror the full multi-temporal archive instead.
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./ni_lidar}"
JOBS="${JOBS:-8}"
CONN="${CONN:-4}"
DRY_RUN="${DRY_RUN:-0}"

STAC="https://dgm.stac.lgln.niedersachsen.de"

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_dgm1() {
  local dir="$OUTROOT/dgm1"
  echo "==> dgm1"
  echo "    STAC: $STAC/collections/dgm1/items"
  mkdir -p "$dir"

  local input="$dir/.aria2.input"
  python3 - "$STAC" "$input" "${BBOX:-}" "${LATEST:-1}" <<'PY'
import sys, json, re, urllib.request, urllib.parse

stac, out, bbox, latest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] != "0"

params = {"limit": "500"}
if bbox:
    params["bbox"] = bbox
url = f"{stac}/collections/dgm1/items?" + urllib.parse.urlencode(params)

# dgm1_32_554_5802_1_ni_2016.tif -> tile key (554, 5802), campaign year 2016
name_re = re.compile(r"_32_(\d+)_(\d+)_1_ni_(\d{4})\.")

found = []       # (href, name)
best = {}        # (e, n) -> (year, index into found)
pages = 0
while url:
    with urllib.request.urlopen(url, timeout=120) as r:
        doc = json.load(r)
    for feat in doc.get("features", []):
        asset = feat.get("assets", {}).get("dgm1-tif")
        if not asset or not asset.get("href"):
            continue
        href = asset["href"]
        name = href.rsplit("/", 1)[-1]
        idx = len(found)
        found.append((href, name))
        m = name_re.search(name)
        if not m:
            best[("raw", idx)] = (0, idx)       # unparseable name: always keep
            continue
        e, n_, year = int(m.group(1)), int(m.group(2)), int(m.group(3))
        prev = best.get((e, n_))
        if prev is None or year > prev[0]:
            best[(e, n_)] = (year, idx)
    pages += 1
    print(f"\r    paged {pages} page(s), {len(found)} items", end="", file=sys.stderr)
    url = next((l["href"] for l in doc.get("links", []) if l.get("rel") == "next"), None)
print("", file=sys.stderr)

keep = sorted(i for _, i in best.values()) if latest else range(len(found))

n = 0
with open(out, "w", encoding="utf-8") as fh:
    for i in keep:
        href, name = found[i]
        fh.write(f"{href}\n  out={name}\n")
        n += 1

dropped = len(found) - n
print(f"    tiles: {n}  |  already Cloud Optimized GeoTIFF — no conversion step needed")
if latest:
    print(f"    LATEST=1: kept the newest campaign per tile, dropped {dropped} older item(s)")
else:
    print(f"    LATEST=0: keeping all {n} items including older campaigns")
print("    no checksums published — resumable and size-checked, not hash-verified")
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
  dgm1) fetch_dgm1 ;;
  las)
    cat >&2 <<'EOF'
Niedersachsen publishes no open airborne laser point cloud.
The LGLN STAC catalogue exposes only the `dgm1` collection (plus a raster `dom` service);
there is no NI counterpart to RLP's / NRW's `las`. Use `dgm1`.
EOF
    exit 3 ;;
  both)
    echo "note: NI has no point cloud — running dgm1 only." >&2
    fetch_dgm1 ;;
  *) echo "Usage: $0 [dgm1] [output_dir]" >&2; exit 2 ;;
esac

cat <<EOF

Attribution required (CC BY 4.0) — include in any product/publication:
  © LGLN $(date +%Y), CC BY 4.0
EOF
