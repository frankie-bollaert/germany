#!/usr/bin/env bash
#
# download_th_lidar.sh — bulk-download the Thüringen (Germany) LiDAR / elevation open data.
#
# Source  : Thüringer Landesamt für Bodenmanagement und Geoinformation (TLBG), through the
#           Kompetenzzentrum GDI-Th · INSPIRE Atom download services
#           https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_{las,dgm,dom}
# License : Datenlizenz Deutschland – Namensnennung – Version 2.0 (DL-DE/BY 2.0), stated in
#           each feed's <rights>. Attribution required: "© GDI-Th, Freistaat Thüringen".
# CRS     : ETRS89 / UTM Zone 32 — EPSG:25832.
#           Heights: DHHN2016 / GCG2016 (EPSG:7837) from the 2014-2019 vintage on;
#                    DHHN92 / GCG2005 (EPSG:5783) in the 2010-2013 vintage.
#
# Why this exists, when the README used to say Thüringen was not scriptable
# ---------------------------------------------------------------------------------------
# The `gaialight` map app (dl-dhm.html) is a portal: its overview.php/details.php need an
# internal filter state, which is where the earlier attempt stopped. But the same page links
# three standard INSPIRE Atom services at the bottom, and those ARE a complete inventory —
# service feed -> one dataset feed -> one <link rel="section"> per tile, each with a direct
# .zip URL and a WGS84 bbox. No login, no CAPTCHA, no token. This script uses those.
#
# Datasets (verified live 2026-08-03):
#   las   — classified ALS point cloud, .laz inside a per-tile .zip (with a .meta sidecar)
#   dgm1  — bare-earth terrain model: GeoTIFF + ASCII .xyz + .meta, per-tile .zip
#   dom1  — surface model, same packaging as dgm1
#
#   All three are on the SAME 1 km x 1 km grid, and each is published in three vintages:
#
#     vintage     tiles    las        dgm1      dom1
#     2010-2013   17,127   ~443 GB    ~19 GB    ~19 GB
#     2014-2019   17,127   ~975 GB    ~73 GB    ~76 GB
#     2020-2025   16,945   ~1.52 TB   ~127 GB   ~131 GB
#
#   Sizes are a 32-tile HEAD sample per combination (2026-08-03), extrapolated by the mean.
#   Point-cloud tiles are heavily right-skewed — a forested Eisenach tile is 270 MB against a
#   65 MB median — so read them as an order of magnitude, not a promise.
#
#   VINTAGE selects one; the default is the newest. The 2020-2025 grid is 182 tiles smaller
#   than the older two, and those 182 are a strict subset of the older grid — that vintage is
#   missing them, it does not add anything new.
#
#   CAREFUL — "dgm1" is the repo-wide key for a terrain model, not a promise of a 1 m grid:
#   the 2010-2013 vintage is a 2 METRE grid and its files are named dgm2_*/dom2_*. The script
#   says so at run time rather than handing back a coarser product silently. 2014-2019 and
#   2020-2025 are 1 m.
#
#   Also worth knowing before you size a disk: in the dgm/dom zips the ASCII .xyz is ten
#   times the GeoTIFF (29 MB vs 2.9 MB for a 1 m tile). Both are shipped in the same zip and
#   there is no way to ask for one of them, so a "115 GB" DGM run is mostly ASCII.
#
# Method  : service feed -> dataset feed -> tile links, then an input file for aria2c:
#           parallel, resumable, rebuilt on every run. The dataset UUID is discovered from
#           the service feed rather than hard-coded.
#
#           The dataset feeds are large (~13 MB, 17k links each) — expect a short pause while
#           the tile list is built. The vintage is read off each tile's URL path, so a fourth
#           vintage appearing upstream shows up in the "known vintages" list on its own.
#
#           The published unit is the .zip; it is left as downloaded, like sn/bb. No checksums
#           are published — downloads are size-checked and resumable, not hash-verified.
#
# Usage   : ./download_th_lidar.sh [dgm1|las|dom1|both] [output_dir]
#   ./download_th_lidar.sh dgm1                      # -> ./th_lidar/dgm1, ~127 GB
#   ./download_th_lidar.sh las /mnt/big/th           # ~1.5 TB — mind your disk!
#   ./download_th_lidar.sh both                      # dgm1 + las (repo convention)
#   VINTAGE=2014-2019 ./download_th_lidar.sh dgm1    # an older flight campaign
#   DRY_RUN=1 BBOX="591,5646,595,5650" ./download_th_lidar.sh las    # the Eisenach square
#
# Env vars (override defaults):
#   VINTAGE=2020-2025            which campaign to take (default: the newest published)
#   BBOX="minE,minN,maxE,maxN"   UTM32 kilometres, inclusive, on the tile's SW corner
#   JOBS=8   CONN=4              aria2c parallelism
#   DRY_RUN=1                    print the plan and a size estimate, transfer nothing
#   OUTDIR=<path>                write the zips straight here, instead of <output_dir>/<dataset>.
#                                Single-dataset runs only — with "both" the two would collide.
#                                download_all.sh uses this for <root>/<state>-<dataset>.
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./th_lidar}"
JOBS="${JOBS:-8}"
CONN="${CONN:-4}"
DRY_RUN="${DRY_RUN:-0}"

# Repo dataset key -> the Atom service feed, and the filename prefix that identifies the
# product inside it. TLBG names the terrain files by GRID (dgm1_*, dgm2_*) rather than by
# product, so the prefix is matched loosely and the actual grid is reported per vintage.
service_feed() {
  case "$1" in
    las)  echo "https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_las" ;;
    dgm1) echo "https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_dgm" ;;
    dom1) echo "https://geoportal.geoportal-th.de/dienste/atom_th_hoehendaten_dom" ;;
    *)    return 1 ;;
  esac
}

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

fetch_one() {
  local key="$1" svc dir="${OUTDIR:-$OUTROOT/$1}"
  svc="$(service_feed "$key")"
  echo "==> $key"
  echo "    service feed: $svc"
  mkdir -p "$dir"

  local input="$dir/.aria2.input"
  VINTAGE="${VINTAGE:-}" BBOX="${BBOX:-}" DRY_RUN="$DRY_RUN" \
    python3 - "$svc" "$input" "$dir" <<'PY'
import html, os, re, statistics, sys, urllib.request

svc, out, dirpath = sys.argv[1:4]
want_vintage = os.environ.get("VINTAGE", "").strip()
bbox = os.environ.get("BBOX", "").strip()
dry = os.environ.get("DRY_RUN") == "1"
UA = {"User-Agent": "download_th_lidar.sh"}


def get(url, timeout=300):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


# The service feed carries one dataset; its feed is the link with type=dataset. Discovered
# rather than hard-coded, so a re-issued UUID upstream does not break the script.
service = get(svc)
dataset_url = None
for href in re.findall(r'href="([^"]+)"', service):
    href = html.unescape(href)
    if "type=dataset" in href:
        dataset_url = href
        break
if not dataset_url:
    raise SystemExit(f"no dataset feed linked from {svc}")

doc = get(dataset_url, timeout=600)
with open(os.path.join(dirpath, ".dataset.atom"), "w", encoding="utf-8") as fh:
    fh.write(doc)

# Every tile is a <link rel="section"> with a direct .zip URL. The dataset feed splits them
# across one <entry> per vintage, but the entries carry no title — only "#1/#2/#3" — so the
# vintage is taken from the URL path (.../LAS/las_2020-2025/las_32_591_5646_1_th_2020-2025.zip)
# instead of from the entry order, which nothing upstream promises to keep.
VINTAGE_RE = re.compile(r"/(?:las|dgm|dom)_(\d{4}-\d{4})/")
by_vintage = {}
for href in re.findall(r'<link rel="section" href="([^"]+)"', doc):
    href = html.unescape(href)
    m = VINTAGE_RE.search(href)
    if not m:
        continue
    by_vintage.setdefault(m.group(1), []).append(href)

if not by_vintage:
    raise SystemExit(f"no tile links in {dataset_url} — the feed layout changed")

known = sorted(by_vintage)
vintage = want_vintage or known[-1]
if vintage not in by_vintage:
    raise SystemExit(f"unknown VINTAGE {vintage!r} — this feed publishes: {', '.join(known)}")

links = by_vintage[vintage]
print(f"    vintage : {vintage}  (published: {', '.join(known)})")

# The grid is a property of the campaign, not of the dataset key: 2010-2013 is a 2 m model
# published as dgm2_*/dom2_*. Say so rather than hand back a coarser product as "dgm1".
grid = os.path.basename(links[0]).split("_")[0]
if grid.endswith("2"):
    print(f"    NOTE: this vintage is a 2 m grid ({grid}_*), not 1 m — the 1 m models start "
          f"at 2014-2019")

box = None
if bbox:
    mine, minn, maxe, maxn = (int(v) for v in bbox.split(","))
    box = (mine, minn, maxe, maxn)

# Tile names embed the SW corner in km. The newest vintage inserts the UTM zone, the older
# two do not: las_591_5646_1_th_2014-2019.zip / las_32_591_5646_1_th_2020-2025.zip
TILE = re.compile(r"_(?:32_)?(\d{3})_(\d{4})_1_th_")

kept, outside = [], 0
seen = set()
for href in links:
    name = os.path.basename(href)
    if name in seen:
        continue
    seen.add(name)
    if box:
        m = TILE.search(name)
        if not m:
            continue
        e_km, n_km = int(m.group(1)), int(m.group(2))
        if not (box[0] <= e_km <= box[2] and box[1] <= n_km <= box[3]):
            outside += 1
            continue
    kept.append((href, name))

with open(out, "w", encoding="utf-8") as fh:
    for href, name in kept:
        fh.write(f"{href}\n  out={name}\n")

# The feed publishes no sizes, so estimate from a HEAD sample, spread evenly over the
# selection rather than taken off the front (the tiles are in grid order, so the first N are
# one corner of the state). The total uses the MEAN, not the median: point-cloud tile size is
# heavily right-skewed by terrain cover — forest tiles run 3-4x a field — and a sum is
# n * mean, so a median would understate it by a third. The median is printed too, because it
# is the better answer to "how big is a tile".
est = ""
if kept:
    sample = kept[:: max(1, len(kept) // 24)][:24]
    sizes = []
    for href, _ in sample:
        try:
            req = urllib.request.Request(href, headers=UA, method="HEAD")
            with urllib.request.urlopen(req, timeout=60) as r:
                sizes.append(int(r.headers.get("Content-Length", 0)))
        except Exception:
            pass
    if sizes:
        total = statistics.mean(sizes) * len(kept)
        est = (f"  ~{total / 1e12:.2f} TB est" if total > 1e12
               else f"  ~{total / 1e9:.1f} GB est")
        est += (f" (from {len(sizes)} sampled tiles, median {statistics.median(sizes) / 1e6:.0f}"
                f" MB each)")

print(f"    tiles: {len(kept)}" + (f"  ({outside} outside BBOX)" if box else "") + est)
print("    no checksums published — resumable and size-checked, not hash-verified")

if not kept:
    # An empty BBOX is a coverage question, not a failure: exit 0 with "tiles: 0" already
    # printed, so download_samples.sh reports it as a gap rather than a failed download.
    if box:
        print("    this square selected no tile — Thüringen spans roughly "
              "560-720 E / 5560-5720 N in UTM32 km")
        raise SystemExit(0)
    raise SystemExit("no tile in the feed — the layout changed")

if dry:
    for _, name in kept[:10]:
        print(f"      {name}")
    if len(kept) > 10:
        print(f"      … and {len(kept) - 10} more (full list in {out})")
PY

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi
  # A BBOX that matched nothing leaves an empty input file; aria2c would exit 1 on it.
  [[ -s "$input" ]] || { echo "    nothing to fetch."; return 0; }

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
  las|dgm1|dom1) fetch_one "$DATASET" ;;
  both)          fetch_one dgm1; fetch_one las ;;
  *) echo "Usage: $0 [dgm1|las|dom1|both] [output_dir]" >&2; exit 2 ;;
esac

cat <<EOF

Attribution required — include a visible source note in any product/publication:
  © GDI-Th, Freistaat Thüringen $(date +%Y), dl-de/by-2-0

Each tile is a .zip: las carries .laz + .meta, dgm1/dom1 carry .tif + .xyz + .meta.
EOF
