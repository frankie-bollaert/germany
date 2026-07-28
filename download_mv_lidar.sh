#!/usr/bin/env bash
#
# download_mv_lidar.sh — bulk-download the Mecklenburg-Vorpommern (Germany) LiDAR open data.
#
# Source : Landesamt für innere Verwaltung M-V, Amt für Geoinformation (LAiV M-V)
#          INSPIRE Atom download services · https://www.geodaten-mv.de/dienste/
# License : Open data, but attribution REQUIRED — the feeds' <rights> demand a visible
#           source note on every publication or derived work:
#           "© GeoBasis-DE/M-V <year of last data delivery>"
# CRS     : ETRS89 / UTM Zone 33 — EPSG:25833 (like Brandenburg/Berlin/Sachsen).
#
# Datasets (verified live):
#   las  — Airborne Laserscandaten (ALS), classified point cloud, .laz
#          1 km x 1 km tiles, ~25,466 tiles, named 3dm_33_<E_km>_<N_km>_1.laz
#   dgm1 — bare-earth terrain model, 1 m grid, Float32 GeoTIFF
#          2 km x 2 km tiles, 6,407 tiles, named dgm1_33_<E_km>_<N_km>_2_gtiff.tif
#
#          NOTE the two products are on DIFFERENT tile sizes (las 1 km, dgm1 2 km), so a
#          BBOX cuts them at different granularities.
#
#          CAREFUL — the DGM feed offers each of the 6,407 tiles in six variants, and only
#          one of them is elevation data:
#             _gtiff.tif  Float32 elevation  <-- the DTM; what this script takes
#             _mix.tif    8-bit RGB rendering (a picture of the terrain, not heights)
#             _zcode.tif  8-bit palette height-colour image
#             _schum_NW.tif  hillshade
#             _xyz.zip    ASCII XYZ of the same grid
#             _isoli.zip  derived contour lines
#          Taking the feed at face value yields 38,442 "tiles" — six copies of the state,
#          mostly not elevation. Override with VARIANT= if you want one of the others.
#
# Method  : LAiV publishes an INSPIRE service feed per product; each links one or more
#           dataset feeds, and the dataset feed lists every tile as an enclosure. The script
#           resolves the service feed -> the DGM1 (resp. ALS) dataset feed -> the tile links,
#           then hands an input file to aria2c: parallel, resumable. Rebuilt on every run,
#           and the dataset UUID is discovered rather than hard-coded.
#
#           The dataset feeds are large (dgm1 ~15 MB, als ~10 MB) — expect a short pause
#           while the tile list is built.
#
#           No checksums are published — downloads are size-checked, not hash-verified.
#
# Usage   : ./download_mv_lidar.sh [dgm1|las|both] [output_dir]
#   ./download_mv_lidar.sh dgm1                 # -> ./mv_lidar/dgm1
#   ./download_mv_lidar.sh las  /mnt/big/mv     # point cloud — mind your disk!
#   ./download_mv_lidar.sh both
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   BBOX="minE,minN,maxE,maxN"   # UTM33 kilometres, inclusive
#   VARIANT=_gtiff.tif           # dgm1 only — pick a different published variant,
#                                # e.g. VARIANT=_xyz.zip or VARIANT=_schum_NW.tif
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./mv_lidar}"
JOBS="${JOBS:-8}"
CONN="${CONN:-4}"
DRY_RUN="${DRY_RUN:-0}"

# Map dataset key -> service feed + the dataset title prefix to pick out of it.
service_feed() {
  case "$1" in
    las)  echo "https://www.geodaten-mv.de/dienste/als_atom" ;;
    dgm1) echo "https://www.geodaten-mv.de/dienste/dgm_atom" ;;
    *)    return 1 ;;
  esac
}
dataset_match() {
  case "$1" in
    las)  echo "Airborne Laserscandaten" ;;   # the ALS feed carries a single dataset
    dgm1) echo "DGM1" ;;                      # the DGM feed also holds DGM5 and DGM25
    *)    return 1 ;;
  esac
}
# Which of the published per-tile variants to take (see the header note).
variant_suffix() {
  case "$1" in
    las)  echo ".laz" ;;
    dgm1) echo "${VARIANT:-_gtiff.tif}" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" svc match suffix dir="$OUTROOT/$1"
  svc="$(service_feed "$1")"
  match="$(dataset_match "$1")"
  suffix="$(variant_suffix "$1")"
  echo "==> $key"
  echo "    service feed: $svc"
  echo "    variant     : *$suffix"
  mkdir -p "$dir"

  local input="$dir/.aria2.input"
  python3 - "$svc" "$match" "$input" "${BBOX:-}" "$suffix" <<'PY'
import sys, re, html, urllib.request

svc, match, out, bbox, suffix = sys.argv[1:6]


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "download_mv_lidar.sh"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read().decode("utf-8", "replace")


service = get(svc)

# Each <entry> is one dataset; its dataset feed is the link carrying type=dataset.
dataset_url = None
for m in re.finditer(r"(?s)<entry>(.*?)</entry>", service):
    entry = m.group(1)
    title = re.search(r"<title[^>]*>([^<]*)", entry)
    title = html.unescape(title.group(1)).strip() if title else ""
    if not title.startswith(match):
        continue
    for href in re.findall(r'href="([^"]+)"', entry):
        href = html.unescape(href)
        if "type=dataset" in href:
            dataset_url = href
            break
    if dataset_url:
        print(f"    dataset: {title}")
        break

if not dataset_url:
    raise SystemExit(f"no dataset entry titled {match!r} in {svc}")

doc = get(dataset_url)

box = None
if bbox:
    mine, minn, maxe, maxn = (int(v) for v in bbox.split(","))
    box = (mine, minn, maxe, maxn)

# Tile names embed the SW corner in km: dgm1_33_206_5920_2_mix.tif / 3dm_33_206_5920_1.laz
tile_re = re.compile(r"_33_(\d+)_(\d+)_")

n = 0
other = 0
seen = set()
with open(out, "w", encoding="utf-8") as fh:
    for href in re.findall(r'href="([^"]*_download\?[^"]+)"', doc):
        href = html.unescape(href)
        fname = re.search(r"[?&]file=([^&]+)", href)
        if not fname:
            continue
        name = fname.group(1)
        # The feed serves the same tile in several variants, each on its own `index=`.
        # Keep the href and its index together and take only the requested variant.
        if not name.endswith(suffix):
            other += 1
            continue
        if name in seen:
            continue
        seen.add(name)
        if box:
            m = tile_re.search(name)
            if not m:
                continue
            e, nn = int(m.group(1)), int(m.group(2))
            if not (box[0] <= e <= box[2] and box[1] <= nn <= box[3]):
                continue
        fh.write(f"{href}\n  out={name}\n")
        n += 1

if n == 0:
    raise SystemExit(f"no tile matched variant {suffix!r} — the feed offers "
                     f"{other} entries in other variants; check VARIANT=")
print(f"    tiles: {n}  ({other} entries in other variants skipped)")
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

Attribution required — include a visible source note in any product/publication:
  © GeoBasis-DE/M-V $(date +%Y)
EOF
