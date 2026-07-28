#!/usr/bin/env bash
#
# download_sn_lidar.sh — bulk-download the Sachsen (Germany) LiDAR open data.
#
# Source : Staatsbetrieb Geobasisinformation und Vermessung Sachsen (GeoSN)
#          Offene Geodaten · https://www.geodaten.sachsen.de
# License : Datenlizenz Deutschland – Zero 2.0 for the Geobasisdaten (GeoSN publishes these
#           without an attribution obligation); crediting "© GeoSN" remains good practice.
#           Confirm on https://www.geodaten.sachsen.de before redistributing.
# CRS     : ETRS89 / UTM Zone 33 — EPSG:25833 (like Brandenburg, not 25832);
#           heights DHHN2016 (compound EPSG:7837).
# Tiling  : 2 km x 2 km, SW corner snapped to an even km.
#
# Datasets (verified live):
#   las  — Laserscandaten (LSC), classified point cloud, .laz inside a .zip
#   dgm1 — bare-earth terrain model, 1 m grid, GeoTIFF inside a .zip
#          ~4,989 two-km tiles statewide for each product
#
# Method  : GeoSN publishes no manifest and no directory index. Its "Batch Download" page
#           embeds the authoritative inventory as JavaScript: a per-municipality, run-length
#           encoded list of 1 km grid cells, plus a per-product Nextcloud public share id.
#           This script fetches that page, decodes the grid with a small stdlib-only parser,
#           aggregates the 1 km cells to the product's 2 km packaging, subtracts the
#           product's "computed_not_existing" holes, and writes an aria2c input file.
#           The tile list is therefore always current rather than hard-coded.
#
#           Files are served from a Nextcloud public share over WebDAV. Anonymous GET works
#           (no credentials); directory listing (PROPFIND) does not, which is why the tile
#           list has to come from the batch page.
#
#           No checksums are published — downloads are size-checked, not hash-verified.
#
# Usage   : ./download_sn_lidar.sh [dgm1|las|both] [output_dir]
#   ./download_sn_lidar.sh dgm1                 # -> ./sn_lidar/dgm1
#   ./download_sn_lidar.sh las  /mnt/big/sn     # point cloud — mind your disk!
#   ./download_sn_lidar.sh both
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   BBOX="minE,minN,maxE,maxN"   # UTM33 kilometres, inclusive
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./sn_lidar}"
JOBS="${JOBS:-8}"
CONN="${CONN:-4}"
DRY_RUN="${DRY_RUN:-0}"

BATCH_PAGE="https://www.geodaten.sachsen.de/batch-download-4719.html"
DAV_BASE="https://geocloud.landesvermessung.sachsen.de/public.php/dav/files"

# Map dataset key -> the product key used inside the batch page's config.
product_key() {
  case "$1" in
    las)  echo "LSC" ;;
    dgm1) echo "DGM1_TIFF_2km" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" prod dir="$OUTROOT/$1"
  prod="$(product_key "$1")"
  echo "==> $key  (product $prod)"
  echo "    inventory: $BATCH_PAGE"
  mkdir -p "$dir"

  # Always re-fetch: the embedded inventory changes as new campaigns are released.
  local page="$dir/.batch.html"
  curl -fsS "$BATCH_PAGE" -o "$page"

  local input="$dir/.aria2.input"
  python3 - "$page" "$prod" "$DAV_BASE" "$input" "${BBOX:-}" <<'PY'
import sys, json, re

page, prod, dav, out, bbox = sys.argv[1:6]
s = open(page, encoding="utf-8", errors="replace").read()


def grab_object(marker):
    """Extract the balanced {...} literal assigned right after `marker`."""
    i = s.index(marker) + len(marker)
    depth = 0
    for j in range(i, len(s)):
        if s[j] == "{":
            depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0:
                return json.loads(s[i:j + 1])
    raise SystemExit(f"could not parse {marker!r} out of the batch page")


products = grab_object("batchConfig.products=")
mapping = grab_object("batchConfig.mapping=")

if prod not in products:
    raise SystemExit(f"product {prod!r} is gone from the batch page — available: {sorted(products)}")
cfg = products[prod]
share = cfg["share_id"]
if not share:
    raise SystemExit(f"product {prod!r} carries no share id — not offered for batch download")

resolution = int(cfg["packagesize"]) // 1000          # 2 km packaging
fname_tpl = cfg["filename"]


def uncompress(lst, increment=1):
    """Run-length pairs (start, count) -> explicit cell ids."""
    out_ = []
    for k in range(0, len(lst), 2):
        start, count = lst[k], lst[k + 1]
        out_.extend(start + n * increment for n in range(count))
    return out_


def split_cell(cell):
    """Cell id 3215637 -> (321 km east, 5637 km north)."""
    t = str(cell)
    return int(t[:3]), int(t[3:7])


# Every 1 km cell that belongs to some municipality, floored to the 2 km packaging grid.
tiles = set()
for entry in mapping.values():
    for cell in uncompress(entry["grid_id"]):
        e, n = split_cell(cell)
        tiles.add((e // resolution * resolution, n // resolution * resolution))

# Cells the portal knows are computed but not actually present as files.
holes = set()
for hole in uncompress(cfg.get("computed_not_existing", []), resolution):
    holes.add(split_cell(hole))
tiles -= holes

box = None
if bbox:
    mine, minn, maxe, maxn = (int(v) for v in bbox.split(","))
    box = (mine, minn, maxe, maxn)

n = 0
with open(out, "w", encoding="utf-8") as fh:
    for e, nn in sorted(tiles):
        if box and not (box[0] <= e <= box[2] and box[1] <= nn <= box[3]):
            continue
        name = fname_tpl.replace("$Rechtswert$", str(e)).replace("$Hochwert$", str(nn))
        fh.write(f"{dav}/{share}/{name}\n  out={name}\n")
        n += 1

print(f"    tiles: {n}  ({resolution} km packaging"
      + (f", {len(holes)} known gap(s) skipped" if holes else "") + ")")
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
  las|dgm1) fetch_one "$DATASET" ;;
  both)     fetch_one dgm1; fetch_one las ;;
  *) echo "Usage: $0 [dgm1|las|both] [output_dir]" >&2; exit 2 ;;
esac

cat <<EOF

Courtesy credit:  © GeoSN $(date +%Y)  ·  https://www.geodaten.sachsen.de
EOF
