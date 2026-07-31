#!/usr/bin/env bash
#
# download_be_lidar.sh — bulk-download the Berlin (Germany) LiDAR open data.
#
# Source : Geodateninfrastruktur Berlin (GDI Berlin), Senatsverwaltung für Stadtentwicklung
#          INSPIRE Atom download services · https://gdi.berlin.de/data/
# License : Datenlizenz Deutschland – Zero 2.0 (declared in the feeds' <rights>) —
#           no attribution obligation; "© GDI Berlin" is a courtesy credit.
# CRS     : ETRS89 / UTM Zone 33 — EPSG:25833 (Berlin is east of the 12°E zone boundary).
#
# Datasets (verified live):
#   las  — Airborne Laserscanning (ALS), primary 3D laser scan data
#          packaged as 9 city-region ZIPs rather than a tile grid, so a region is the
#          smallest thing that can be asked for — BBOX cannot cut it, REGIONS picks
#          whole ones. Measured 2026-07-30, 232.3 GB for the city:
#            Suedost 47.7   Sued 35.6   Mitte 34.2   Nord 29.8   Suedwest 29.3
#            West 25.1      Nordwest 15.0   Ost 14.7   Nordost 0.9
#          Nordost is the outlier that makes a usable sample: 0.9 GB zipped, 11 las
#          tiles on the 1 km grid (E 400-403, N 5826-5834 — Buch/Karow, the city's
#          northeast edge), 2.4 GB unzipped. Note it is ~25 km from the Berlin-Mitte
#          sample square, so the las and dgm1 samples do not overlap.
#   dgm1 — ATKIS DGM, 1 m grid, 2 km x 2 km tiles named DGM1_<E_km>_<N_km>.zip
#          297 tiles, ~0.7 MB each => roughly 0.2 GB for the whole city
#
# Method  : both products are published as INSPIRE "predefined dataset" Atom feeds. The
#           script reads the dataset-level feed (`0.atom`), collects every enclosure link,
#           and writes an aria2c input file: parallel, resumable. Rebuilt on every run.
#
#           No checksums are published — downloads are size-checked, not hash-verified.
#
# Usage   : ./download_be_lidar.sh [dgm1|las|both] [output_dir]
#   ./download_be_lidar.sh dgm1                 # ~0.2 GB into ./be_lidar/dgm1
#   ./download_be_lidar.sh las                  # all 9 regions — 232 GB
#   REGIONS=Nordost ./download_be_lidar.sh las  # one region — 0.9 GB
#   ./download_be_lidar.sh both
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   OUTDIR=<path>  write the files straight here, instead of <output_dir>/<dataset>.
#                  Single-dataset runs only — with "both" the two products would collide.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#   BBOX="minE,minN,maxE,maxN"   # UTM33 kilometres, inclusive — dgm1 only
#                                # (las packages are regions, not tiles, so BBOX can't cut them)
#   REGIONS="Nordost Ost"        # las only — city regions to fetch, space- or comma-separated.
#                                # Unset means all nine. A name the feed does not offer is an
#                                # error, not an empty download.
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./be_lidar}"
JOBS="${JOBS:-8}"
CONN="${CONN:-4}"
DRY_RUN="${DRY_RUN:-0}"

# Map dataset key -> INSPIRE Atom dataset feed (portable; macOS ships bash 3.2).
feed_url() {
  case "$1" in
    las)  echo "https://gdi.berlin.de/data/a_als/atom/0.atom" ;;
    dgm1) echo "https://gdi.berlin.de/data/dgm1/atom/0.atom" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" url dir="${OUTDIR:-$OUTROOT/$1}"
  url="$(feed_url "$1")"
  echo "==> $key"
  echo "    feed: $url"
  mkdir -p "$dir"

  local feed="$dir/.feed.atom"
  curl -fsS "$url" -o "$feed"

  local input="$dir/.aria2.input"
  python3 - "$feed" "$input" "$key" "${BBOX:-}" "${REGIONS:-}" <<'PY'
import sys, re, html

feed, out, key, bbox, regions = sys.argv[1:6]
s = open(feed, encoding="utf-8", errors="replace").read()

box = None
if bbox:
    if key != "dgm1":
        print("    note: BBOX ignored — las is packaged as whole city regions, not tiles;"
              " pick them with REGIONS")
    else:
        mine, minn, maxe, maxn = (int(v) for v in bbox.split(","))
        box = (mine, minn, maxe, maxn)

want = None
if regions:
    if key != "las":
        print("    note: REGIONS ignored — dgm1 is a tile grid; cut it with BBOX")
    else:
        want = set(regions.replace(",", " ").split())

# The feed links some enclosures more than once, so collect before filtering: the region
# names have to be known in full to tell a typo from a region that simply was not asked for.
entries, seen = [], set()
for href in re.findall(r'href="([^"]+\.zip)"', s):
    href = html.unescape(href)
    name = href.rsplit("/", 1)[-1]
    if name not in seen:
        seen.add(name)
        entries.append((name, href))

# A misspelt region would otherwise select nothing and still report success, which reads
# exactly like a finished download. Refuse, and say what the feed actually offers.
if want is not None:
    have = {n[:-4] for n, _ in entries}
    unknown = sorted(want - have)
    if unknown:
        sys.exit("    ERROR: no such region: %s\n    feed offers: %s"
                 % (", ".join(unknown), ", ".join(sorted(have))))

# DGM1 tiles carry their SW corner in the filename: DGM1_368_5808.zip
tile_re = re.compile(r'DGM1_(\d+)_(\d+)\.zip$')

n = 0
with open(out, "w", encoding="utf-8") as fh:
    for name, href in entries:
        if want is not None and name[:-4] not in want:
            continue
        if box:
            m = tile_re.search(name)
            if not m:
                continue
            e, nn = int(m.group(1)), int(m.group(2))
            if not (box[0] <= e <= box[2] and box[1] <= nn <= box[3]):
                continue
        fh.write(f"{href}\n  out={name}\n")
        n += 1

label = "region packages" if key == "las" else "tiles"
print(f"    {label}: {n}")
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

License: Datenlizenz Deutschland – Zero 2.0 (no attribution required).
Courtesy credit:  © GDI Berlin $(date +%Y)
EOF
