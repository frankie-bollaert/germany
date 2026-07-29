#!/usr/bin/env bash
#
# download_bw_lidar.sh — bulk-download the Baden-Württemberg (Germany) LiDAR open data.
#
# Source  : Landesamt für Geoinformation und Landentwicklung Baden-Württemberg (LGL BW)
#           Open GeoData portal https://opengeodata.lgl-bw.de
# License : Datenlizenz Deutschland – Namensnennung 2.0 (DL-DE/BY 2.0) — attribution REQUIRED:
#           "Datenquelle: LGL, www.lgl-bw.de"
# CRS     : ETRS89 / UTM Zone 32 (EPSG:25832); heights DHHN2016 (compound EPSG:7837).
# Tiling  : downloads are 2 km x 2 km ZIPs, each holding four 1 km x 1 km tiles.
#
# Datasets (verified live):
#   dgm1 — bare-earth terrain model, 1 m grid, ASCII **XYZ** text inside the ZIP
#          (one line per cell centre: easting northing height), plus a per-tile .csv
#          with acquisition date/accuracy. Statewide: ~9,370 ZIPs, ~134 GB.
#
# NOT available: BW publishes no open point cloud. The portal's 3DM / "Laserscandaten"
# product is flagged inactive and every 3dm_*.zip URL returns 404, so there is no BW
# equivalent of the RLP `las` dataset (see download_rlp_lidar.sh).
#
# Method  : BW publishes no manifest. The portal draws its 2x2 km download grid as Mapbox
#           vector tiles whose features carry a JSON blob with the per-tile download URL;
#           four tiles at zoom 7 cover the whole state. We decode those into an aria2c
#           input file — so the tile list is always current, never hard-coded.
#           No checksums are published (unlike RLP's Metalink), so downloads are resumable
#           and size-checked but not hash-verified.
#
# Usage   : ./download_bw_lidar.sh [dgm1] [output_dir]
#   ./download_bw_lidar.sh dgm1                  # ~134 GB into ./bw_lidar/dgm1
#   ./download_bw_lidar.sh dgm1 /mnt/big/bw      # mind your disk!
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   OUTDIR=<path>  write the files straight here, instead of <output_dir>/<dataset>.
#                  Single-dataset runs only — with "both" the two products would collide.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#   BBOX="minE,minN,maxE,maxN"   subset by UTM32 kilometre, e.g. BBOX="500,5400,520,5420"
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./bw_lidar}"
JOBS="${JOBS:-8}"          # concurrent tiles
CONN="${CONN:-4}"          # connections per tile
DRY_RUN="${DRY_RUN:-0}"    # set 1 to only print the tile-list summary
BBOX="${BBOX:-}"           # optional minE,minN,maxE,maxN in UTM32 km

BASE="https://opengeodata.lgl-bw.de"
GRID="$BASE/tiles/vts/2x2Gitter"   # 2x2 km download grid as vector tiles
GRID_ZOOM=7                        # grid layer's minzoom; 4 tiles cover BW at z7

# Map dataset key -> product type as named in the grid metadata (portable; macOS ships bash 3.2).
product_type() {
  case "$1" in
    dgm1) echo "DGM1" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" ptype dir="${OUTDIR:-$OUTROOT/$1}"
  ptype="$(product_type "$1")"
  echo "==> $key  (product $ptype)"
  echo "    grid: $GRID/$GRID_ZOOM/{x}/{y}.pbf"
  mkdir -p "$dir"

  # Always rebuild the tile list: coverage grows as new flight campaigns are published.
  local grid_dir="$dir/.grid"
  rm -rf "$grid_dir"; mkdir -p "$grid_dir"
  curl -fsS "$GRID/metadata.json" -o "$grid_dir/metadata.json"

  # Which z7 tiles cover the grid's own declared bounds?
  local tiles
  tiles="$(python3 - "$grid_dir/metadata.json" "$GRID_ZOOM" <<'PY'
import json, math, sys
meta = json.load(open(sys.argv[1], encoding="utf-8"))
z = int(sys.argv[2])
w, s, e, n = json.loads(meta["bounds"]) if isinstance(meta["bounds"], str) else meta["bounds"]
def xy(lon, lat):
    m = 2 ** z
    lat = max(min(lat, 85.05), -85.05)
    r = math.radians(lat)
    return (int((lon + 180) / 360 * m),
            int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * m))
x0, y0 = xy(w, n)
x1, y1 = xy(e, s)
print(" ".join(f"{x}/{y}" for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)))
PY
)"

  # A corner tile of the bounds box can legitimately be empty -> tolerate 404s here;
  # the decoder below fails loudly if the whole set yields no tiles.
  local t f
  for t in $tiles; do
    f="$grid_dir/${t//\//_}.pbf"
    curl -fsS "$GRID/$GRID_ZOOM/$t.pbf" -o "$f" || { rm -f "$f"; echo "    note: no grid tile at z$GRID_ZOOM $t"; }
  done

  # Decode the vector tiles -> aria2c input file (URL + out= per tile).
  local list="$dir/.tiles.aria2"
  python3 - "$grid_dir" "$ptype" "$BASE" "$list" "$BBOX" <<'PY'
import glob, gzip, json, os, struct, sys

grid_dir, ptype, base, out_path, bbox = sys.argv[1:6]

# --- minimal Mapbox Vector Tile reader (stdlib only; we only need feature properties) ---
def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1
        r |= (c & 0x7F) << s
        if not c & 0x80:
            return r, i
        s += 7

def fields(b):
    i, n = 0, len(b)
    while i < n:
        k, i = varint(b, i)
        wt = k & 7
        if wt == 0:   v, i = varint(b, i)
        elif wt == 2: l, i = varint(b, i); v = b[i:i + l]; i += l
        elif wt == 5: v = b[i:i + 4]; i += 4
        elif wt == 1: v = b[i:i + 8]; i += 8
        else: raise ValueError(f"bad wire type {wt}")
        yield k >> 3, v

def value(b):
    for f, v in fields(b):
        if f == 1: return v.decode("utf-8")
        if f == 2: return struct.unpack("<f", v)[0]
        if f == 3: return struct.unpack("<d", v)[0]
        if f == 6: return (v >> 1) ^ -(v & 1)
        if f == 7: return bool(v)
        return v
    return None

def packed(b):
    i, out = 0, []
    while i < len(b):
        v, i = varint(b, i); out.append(v)
    return out

def properties(tile):
    for f, layer in fields(tile):
        if f != 3:
            continue
        keys, vals, feats = [], [], []
        for lf, lv in fields(layer):
            if lf == 2:   feats.append(lv)
            elif lf == 3: keys.append(lv.decode("utf-8"))
            elif lf == 4: vals.append(value(lv))
        for fe in feats:
            for ff, fv in fields(fe):
                if ff == 2:
                    t = packed(fv)
                    yield {keys[t[j]]: vals[t[j + 1]] for j in range(0, len(t) - 1, 2)}

box = [float(v) for v in bbox.split(",")] if bbox else None
if box and len(box) != 4:
    sys.exit("ERROR: BBOX must be minE,minN,maxE,maxN in UTM32 km")

tiles = {}
for path in sorted(glob.glob(os.path.join(grid_dir, "*.pbf"))):
    raw = open(path, "rb").read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    for props in properties(raw):
        meta = json.loads(props["metadata"])
        name = meta["name"]                     # "<easting_km>-<northing_km>" of the SW corner
        if box:
            east, north = (float(v) for v in name.split("-"))
            if not (box[0] <= east <= box[2] and box[1] <= north <= box[3]):
                continue
        for product in meta["products"]:
            for t in product["types"]:
                if t["type"] == ptype:
                    tiles[t["fileName"]] = t["downloadURL"]

if not tiles:
    sys.exit(f"ERROR: no {ptype} tiles found" + (f" in BBOX {bbox}" if bbox else ""))

with open(out_path, "w", encoding="utf-8") as fh:
    for fn, url in sorted(tiles.items()):
        fh.write(f"{base}{url}\n  out={fn}\n")
print(f"    tiles: {len(tiles)}" + (f"  |  BBOX {bbox}" if bbox else "  |  statewide"))
PY

  if [[ "$DRY_RUN" == "1" ]]; then
    # No published sizes — sample a few tiles with HEAD and extrapolate.
    python3 - "$list" <<'PY'
import subprocess, sys
urls = [l.strip() for l in open(sys.argv[1], encoding="utf-8") if not l.startswith("  ")]
sample = urls[:: max(1, len(urls) // 5)][:5]
sizes = []
for u in sample:
    out = subprocess.run(["curl", "-fsSI", "-m", "30", u], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.lower().startswith("content-length:"):
            sizes.append(int(line.split(":")[1]))
if sizes:
    avg = sum(sizes) / len(sizes)
    print(f"    est. total: {avg * len(urls) / 1e9:.1f} GB  ({len(sizes)} tiles sampled, avg {avg/1e6:.1f} MB)")
PY
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi

  # No SHA-256 is published for BW, so --check-integrity is not available; --continue resumes.
  aria2c \
    --input-file="$list" \
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
  dgm1) fetch_one "$DATASET" ;;
  las|3dm)
    echo "ERROR: Baden-Württemberg publishes no open point cloud." >&2
    echo "       The portal's 3DM/Laserscandaten product is inactive (every 3dm_*.zip 404s)." >&2
    echo "       Use 'dgm1' here, or download_rlp_lidar.sh las for Rheinland-Pfalz." >&2
    exit 2 ;;
  *) echo "Usage: $0 [dgm1] [output_dir]" >&2; exit 2 ;;
esac

cat <<EOF

Attribution required (DL-DE/BY 2.0) — include in any product/publication:
  Datenquelle: LGL, www.lgl-bw.de  ·  dl-de/by-2-0
EOF
