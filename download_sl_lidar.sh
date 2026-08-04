#!/usr/bin/env bash
#
# download_sl_lidar.sh — download the Saarland (Germany) open LiDAR point cloud and terrain.
#
# Source  : Landesamt für Vermessung, Geoinformation und Landentwicklung (LVGL) des Saarlandes
#           Open Data · https://www.shop.lvgl.saarland.de/index.php?option=com_content&view=article&id=18
#           Statewide datasets live in the LVGL Nextcloud share that page links as
#           "Landesweite Datensätze": https://www.shop.lvgl.saarland.de/cloud/freiegeobasisdaten
# License : Datenlizenz Deutschland – Namensnennung – Version 2.0 (DL-DE/BY 2.0)
#           http://www.govdata.de/dl-de/by-2-0 — the licensor's required source note, verbatim
#           from that page: "© GeoBasis DE/LVGL-SL (Jahr der Bereitstellung)"
# CRS     : ETRS89 / UTM Zone 32 — EPSG:25832.
#
# This state was listed in the README as having no open bulk LiDAR until 2026-08-03. It does:
# the whole 2025 airborne laser scan is in that share, 115.7 GB of it, alongside DGM1, DOM1,
# Hausumringe, LoD2 building models and TrueDOP20. The catalogue entry that says "contact
# sales to get the dataset on disk" describes the 2016 campaign, not this one.
#
# Datasets (verified live 2026-08-03):
#   las  — classified ALS point cloud, .laz, flown 2025
#          1 km x 1 km tiles named 3dm_32_<E_km>_<N_km>_1_SL_2025_050.laz, ~38 MB each
#          packaged as one ZIP per Landkreis:
#
#            MZG  Merzig-Wadern                26.2 GB    649 tiles
#            NK   Neunkirchen                  12.5 GB    310 tiles  (the smallest)
#            SB   Regionalverband Saarbrücken  20.6 GB    499 tiles
#            SLS  Saarlouis                    21.6 GB    547 tiles
#            SPK  Saarpfalz-Kreis              20.6 GB    509 tiles
#            WND  St. Wendel                   22.7 GB    562 tiles
#
#          Six of six districts: 3,076 tiles, ~124 GB, spanning E 308-384 / N 5441-5500 in
#          UTM32 km. Full state coverage, one campaign, no vintages to choose between.
#
#   dgm1 — bare-earth terrain model, 1 m grid, derived from that same 2025 scan
#          tiles named dgm1_32_<E_km>_<N_km>_1_SL_2025.<tif|laz>, one per km²
#          GeoTIFF 4.0 MB/tile (5.5 GB statewide) · LAZ ~0.7 MB/tile (2.1 GB statewide)
#
#   dom1 — surface model (first return), same grid, same naming with a dom1_ prefix
#          GeoTIFF 6.2 GB statewide · LAZ 2.8 GB
#
#          All three carry the same 3,076-tile grid, packaged one ZIP per Landkreis, so
#          BBOX and KREISE behave identically across them.
#
#   FORMAT=tif (default) or FORMAT=laz picks the encoding for dgm1/dom1. GeoTIFF is the
#   default because convert_to_cloud_optimized.sh takes it straight; the LAZ variants are the
#   same grid as a point-per-cell cloud, at roughly a third of the bytes. `las` is published
#   only as LAZ, so FORMAT does not apply to it.
#
# Method  : The share is Nextcloud. Its public WebDAV endpoint serves the ZIPs anonymously and
#           honours Range, so this script does NOT download the archives whole: it reads each
#           ZIP's central directory over HTTP ranges, builds a tile index, then range-fetches
#           and inflates ONLY the tiles you asked for, straight to .laz. Same technique as
#           download_st_lidar.sh, and the same consequences:
#             - BBOX works, and costs only the tiles it selects.
#             - No 12-26 GB of ZIP staged next to the output — tiles land directly.
#             - Resume is per tile: a tile matching the size recorded in the archive is
#               skipped, a partial one is refetched.
#           Every archive is ZIP64 (all six are over 4 GB) and every .laz entry is deflated.
#
#           The share token is discovered by following the /cloud/freiegeobasisdaten alias
#           rather than hard-coded, and the ZIP list comes from a PROPFIND rather than a
#           baked-in filename list — so a re-share or a 2026 campaign shows up on its own.
#
#           A tile that fails is retried up to three times with backoff: the share sits behind
#           a proxy that returns the occasional 502 under load (one tile in 310 on the first
#           full district run). Whatever still fails is listed at the end, and re-running
#           fetches only those — completed tiles are skipped on size.
#
#           No checksums are published — sizes are checked against the ZIP directory, not
#           hash-verified.
#
# Usage   : ./download_sl_lidar.sh [las|dgm1|dom1|both] [output_dir]
#   ./download_sl_lidar.sh                                  # all six districts, ~124 GB
#   ./download_sl_lidar.sh las /mnt/big/sl                  # same, somewhere with room
#   ./download_sl_lidar.sh dgm1                             # terrain only, 5.5 GB GeoTIFF
#   ./download_sl_lidar.sh both                             # las + dgm1, ~130 GB
#   FORMAT=laz ./download_sl_lidar.sh dgm1                  # terrain as LAZ instead, 2.1 GB
#   KREISE=NK ./download_sl_lidar.sh                        # one district, 12.5 GB
#   DRY_RUN=1 ./download_sl_lidar.sh                        # list the tiles, fetch nothing
#   BBOX="320,5484,324,5488" ./download_sl_lidar.sh         # the repo's Mettlach square
#
# Env vars (override defaults):
#   KREISE="MZG NK SB SLS SPK WND"   which district archives to read (default: all six)
#   BBOX="minE,minN,maxE,maxN"       UTM32 kilometres, inclusive, on the tile's SW corner
#   FORMAT=tif|laz                   encoding for dgm1/dom1 (default tif; las is LAZ-only)
#   JOBS=4     tiles fetched concurrently
#   DRY_RUN=1  list the tiles and their sizes, download nothing
#   OUTDIR=<path>  write the tiles straight here instead of <output_dir>/<dataset>.
#                  Single-dataset runs only — with "both" the two products would collide.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#
set -euo pipefail

DATASET="${1:-las}"
OUTROOT="${2:-./sl_lidar}"
JOBS="${JOBS:-4}"
DRY_RUN="${DRY_RUN:-0}"
KREISE="${KREISE:-MZG NK SB SLS SPK WND}"
FORMAT="${FORMAT:-tif}"

case "$DATASET" in
  las|dgm1|dom1) DATASETS="$DATASET" ;;
  both)          DATASETS="las dgm1" ;;
  *) echo "Usage: $0 [las|dgm1|dom1|both] [output_dir]" >&2; exit 2 ;;
esac

case "$FORMAT" in
  tif|laz) ;;
  *) echo "ERROR: FORMAT must be tif or laz, got '$FORMAT'" >&2; exit 2 ;;
esac

if [[ -n "${OUTDIR:-}" && "$DATASET" == "both" ]]; then
  echo "ERROR: OUTDIR is for single-dataset runs — las and dgm1 would collide in one folder." >&2
  exit 2
fi

fetch_one() {
  local dataset="$1" folder ext label

  # The share names every folder OD_<product>_<year>_<encoding>_<unit>. `las` exists only as
  # LAZ; dgm1/dom1 come in both encodings and FORMAT picks one.
  case "$dataset" in
    las)  folder="OD_LIDAR_Punktwolke_2025_laz_LK"; ext=".laz"
          label="airborne laser scan 2025, classified point cloud" ;;
    dgm1) folder="OD_DGM1_2025_${FORMAT}_LK";       ext=".$FORMAT"
          label="terrain model 2025, 1 m grid, $FORMAT" ;;
    dom1) folder="OD_DOM1_2025_${FORMAT}_LK";       ext=".$FORMAT"
          label="surface model 2025, 1 m grid, $FORMAT" ;;
  esac

  local DIR="${OUTDIR:-$OUTROOT/$dataset}"
  mkdir -p "$DIR"

  echo "==> SL $dataset  (Saarland $label)"
  echo "    districts : $KREISE"
  echo "    out       : $DIR"

  FOLDER="$folder" EXT="$ext" \
  KREISE="$KREISE" BBOX="${BBOX:-}" JOBS="$JOBS" DRY_RUN="$DRY_RUN" python3 - "$DIR" <<'PY'
import os, re, struct, sys, threading, time, urllib.error, urllib.parse, urllib.request, zlib
from queue import Queue

OUT    = sys.argv[1]
KREISE = os.environ["KREISE"].split()
BBOX   = os.environ.get("BBOX", "").strip()
JOBS   = int(os.environ["JOBS"])
DRY    = os.environ["DRY_RUN"] == "1"

HOST  = "https://www.shop.lvgl.saarland.de"
ALIAS = f"{HOST}/cloud/freiegeobasisdaten"
FOLDER = os.environ["FOLDER"]
EXT    = os.environ["EXT"]
UA = {"User-Agent": "download_sl_lidar.sh"}

def get(url, start=None, end=None, method="GET", extra=None):
    h = dict(UA)
    if start is not None:
        h["Range"] = f"bytes={start}-{end}"
    if extra:
        h.update(extra)
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=h, method=method), timeout=600)

def rng(url, a, b):
    with get(url, a, b) as r:
        return r.read()

# The share is reached through a human-friendly alias that redirects to /index.php/s/<token>.
# The token is what the public WebDAV endpoint wants, so take it from the redirect rather
# than pinning it here — a re-share would otherwise 404 with no explanation.
#
# Read it from the FIRST Location header, not from the end of the chain: the alias redirects
# to an http:// URL, and the site's http->https rule sends that to the site ROOT rather than
# to the same path. Following the chain therefore lands on a Joomla shop front page with no
# token in sight, which is exactly what the "share layout changed" error used to report.
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None

try:
    with urllib.request.build_opener(_NoRedirect).open(
            urllib.request.Request(ALIAS, headers=UA), timeout=120) as r:
        location = r.geturl()
except urllib.error.HTTPError as exc:
    location = exc.headers.get("Location", "") or ""
m = re.search(r"/s/([A-Za-z0-9]+)", location)
if not m:
    raise SystemExit(f"no share token in the redirect from {ALIAS} (got {location!r}) — "
                     f"the share layout changed")
token = m.group(1)
final = f"{HOST}/cloud/index.php/s/{token}"
dav = f"{HOST}/cloud/public.php/dav/files/{token}/"
print(f"    share     : {final}")

# PROPFIND the point-cloud folder: one <d:response> per file, carrying href and size. The
# archive list is read here rather than hard-coded, so a new campaign appears on its own.
body = get(dav + urllib.parse.quote(FOLDER) + "/",
           method="PROPFIND", extra={"Depth": "1"}).read().decode("utf-8", "replace")
archives = []
for resp in re.findall(r"<d:response>(.*?)</d:response>", body, re.S):
    href = urllib.parse.unquote(re.search(r"<d:href>([^<]*)</d:href>", resp).group(1))
    size = re.search(r"<d:getcontentlength>(\d+)</d:getcontentlength>", resp)
    name = href.rstrip("/").rsplit("/", 1)[-1]
    if size and name.lower().endswith(".zip"):
        archives.append((name, HOST + urllib.parse.quote(href), int(size.group(1))))
if not archives:
    raise SystemExit(f"no ZIP listed in {FOLDER} — the share layout changed")

# LIDAR_laz_<district>_EPSG-25832_Entstehung-2025.zip, and the same shape for the models:
# DGM1_tif_<district>_..., DOM1_laz_<district>_...  Anchoring on _EPSG keeps the district
# group from swallowing it.
def district_of(name):
    m = re.search(r"_(?:laz|tif)_([A-Z]+)_EPSG", name)
    return m.group(1) if m else None

known = {district_of(a[0]) for a in archives} - {None}
unknown = [k for k in KREISE if k not in known]
if unknown:
    raise SystemExit(f"unknown KREISE {unknown} — this share publishes: {', '.join(sorted(known))}")
wanted = [a for a in archives if district_of(a[0]) in KREISE]

box = None
if BBOX:
    mine, minn, maxe, maxn = (int(v) for v in BBOX.split(","))
    box = (mine, minn, maxe, maxn)

def zip64_extra(extra, need):
    """Pull the fields flagged 0xFFFFFFFF out of the ZIP64 extra block, in spec order."""
    p = 0
    while p + 4 <= len(extra):
        hid, hsz = struct.unpack("<HH", extra[p:p + 4])
        chunk = extra[p + 4:p + 4 + hsz]
        if hid == 0x0001:
            vals, q = [], 0
            for _ in range(need):
                if q + 8 > len(chunk):
                    break
                vals.append(struct.unpack("<Q", chunk[q:q + 8])[0])
                q += 8
            return vals
        p += 4 + hsz
    return []

def index(url, total):
    """Read the central directory over ranges -> [(name, local_hdr_off, method, csize, usize)]."""
    tail = rng(url, max(0, total - 70000), total - 1)
    loc = tail.rfind(b"PK\x06\x07")
    if loc != -1:                                    # ZIP64 — all six archives are
        off = struct.unpack("<Q", tail[loc + 8:loc + 16])[0]
        eocd = rng(url, off, off + 55)
        cdsize, cdoff = struct.unpack("<QQ", eocd[40:56])
    else:
        e = tail.rfind(b"PK\x05\x06")
        if e == -1:
            raise SystemExit(f"no ZIP end-of-central-directory found in {url}")
        cdsize, cdoff = struct.unpack("<II", tail[e + 12:e + 20])

    cd = rng(url, cdoff, cdoff + cdsize - 1)
    out, p = [], 0
    while p + 46 <= len(cd) and cd[p:p + 4] == b"PK\x01\x02":
        method, = struct.unpack("<H", cd[p + 10:p + 12])
        csz, usz = struct.unpack("<II", cd[p + 20:p + 28])
        nl, el, cl = struct.unpack("<HHH", cd[p + 28:p + 34])
        lho = struct.unpack("<I", cd[p + 42:p + 46])[0]
        name = cd[p + 46:p + 46 + nl].decode("utf-8", "replace")
        extra = cd[p + 46 + nl:p + 46 + nl + el]

        # ZIP64: whichever of usize/csize/offset are saturated live in the extra block, in
        # that fixed order. Needed here — every archive is past 4 GB.
        need = [usz == 0xFFFFFFFF, csz == 0xFFFFFFFF, lho == 0xFFFFFFFF]
        if any(need):
            vals = iter(zip64_extra(extra, sum(need)))
            if need[0]: usz = next(vals, usz)
            if need[1]: csz = next(vals, csz)
            if need[2]: lho = next(vals, lho)

        if not name.endswith("/"):
            out.append((name, lho, method, csz, usz))
        p += 46 + nl + el + cl
    return out

# Tile names carry the SW corner in km, in the same two positions for every product:
#   3dm_32_349_5473_1_SL_2025_050.laz   dgm1_32_349_5473_1_SL_2025.tif
TILE = re.compile(r"_32_(\d+)_(\d+)_1_SL_")

plan, skipped_box = [], 0
for name, url, total in sorted(wanted):
    d = district_of(name)
    print(f"    {d}: {name}  ({total / 1e9:.1f} GB archive)")
    tiles = [e for e in index(url, total) if e[0].endswith(EXT)]
    took = 0
    for entry_name, lho, method, csz, usz in tiles:
        base = os.path.basename(entry_name)
        if box:
            m = TILE.search(base)
            if not m:
                continue
            e_km, n_km = int(m.group(1)), int(m.group(2))
            if not (box[0] <= e_km <= box[2] and box[1] <= n_km <= box[3]):
                skipped_box += 1
                continue
        plan.append((url, base, lho, method, csz, usz))
        took += 1
    print(f"      {took}/{len(tiles)} tiles selected")

total_bytes = sum(p[5] for p in plan)
print(f"    tiles: {len(plan)}  ~{total_bytes / 1e9:.1f} GB"
      + (f"  ({skipped_box} outside BBOX)" if box else ""))
print("    no checksums published — size-checked against the ZIP directory, not hash-verified")

if not plan:
    if box:
        # An empty BBOX is a coverage question, not a failure: exit 0 with "tiles: 0" already
        # printed, so download_samples.sh reports it as a gap rather than a failed download.
        # Measured across all six archives 2026-08-03: 3,076 tiles, E 308-384, N 5441-5500.
        print("    this square selected no tile — Saarland's grid spans "
              "E 308-384 / N 5441-5500 in UTM32 km, and a square inside it may still miss "
              "if the district holding it is not in KREISE")
        raise SystemExit(0)
    raise SystemExit("no tile selected — check KREISE")

if DRY:
    for _, base, _, _, _, usz in plan[:10]:
        print(f"      {base}  {usz / 1e6:.0f} MB")
    if len(plan) > 10:
        print(f"      … and {len(plan) - 10} more")
    print("    DRY_RUN=1 — skipping download.")
    raise SystemExit(0)

def fetch(url, base, lho, method, csz, usz, attempts=4):
    """One tile, with a bounded retry.

    The share sits behind a proxy that returns the occasional 502 under load — one tile in
    310 on the first full district run. Without a retry that tile is simply lost and the run
    exits 1, which turns a two-second hiccup into "re-run the whole thing". Backoff is
    2/4/8 s; anything still failing after that is reported and the other tiles carry on.
    """
    for attempt in range(1, attempts + 1):
        try:
            return _fetch(url, base, lho, method, csz, usz)
        except Exception as exc:
            if attempt == attempts:
                raise
            with lock:
                print(f"      ~ {base}: {exc} — retry {attempt}/{attempts - 1}", flush=True)
            time.sleep(2 ** attempt)

def _fetch(url, base, lho, method, csz, usz):
    dest = os.path.join(OUT, base)
    if os.path.exists(dest) and os.path.getsize(dest) == usz:
        return f"      = {base} (already complete)"

    lh = rng(url, lho, lho + 29)
    if lh[:4] != b"PK\x03\x04":
        raise RuntimeError(f"{base}: bad local header — server ignored Range?")
    nl, el = struct.unpack("<HH", lh[26:30])
    start = lho + 30 + nl + el

    tmp = dest + ".part"
    # Every tile entry is deflated (method 8) in all three products, but stored (0) costs one
    # branch to support and saves a silent corruption if LVGL ever repackages.
    dec = zlib.decompressobj(-15) if method == 8 else None
    got = 0
    with get(url, start, start + csz - 1) as r, open(tmp, "wb") as fh:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            block = dec.decompress(chunk) if dec else chunk
            fh.write(block)
            got += len(block)
        if dec:
            block = dec.flush()
            fh.write(block)
            got += len(block)

    if got != usz:
        os.remove(tmp)
        raise RuntimeError(f"{base}: got {got} bytes, archive says {usz}")
    os.replace(tmp, dest)
    return f"      + {base}  {usz / 1e6:.0f} MB"

q = Queue()
for item in plan:
    q.put(item)
errors = []
lock = threading.Lock()

def worker():
    while True:
        try:
            item = q.get_nowait()
        except Exception:
            return
        try:
            msg = fetch(*item)
            with lock:
                print(msg, flush=True)
        except Exception as exc:                      # keep going; report at the end
            with lock:
                errors.append(f"{item[1]}: {exc}")
                print(f"      ! {item[1]}: {exc}", flush=True)
        finally:
            q.task_done()

threads = [threading.Thread(target=worker, daemon=True) for _ in range(max(1, JOBS))]
for t in threads:
    t.start()
for t in threads:
    t.join()

if errors:
    print(f"\n    {len(errors)} file(s) failed — rerun to retry just those:", file=sys.stderr)
    for e in errors:
        print(f"      {e}", file=sys.stderr)
    raise SystemExit(1)
PY

  echo "    done -> $DIR"
}

for ds in $DATASETS; do
  fetch_one "$ds"
done

cat <<EOF

Attribution required — include a visible source note in any product/publication:
  © GeoBasis DE/LVGL-SL $(date +%Y)
  Datenlizenz Deutschland – Namensnennung – Version 2.0 (http://www.govdata.de/dl-de/by-2-0)
EOF
