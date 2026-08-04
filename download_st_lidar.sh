#!/usr/bin/env bash
#
# download_st_lidar.sh — download the Sachsen-Anhalt (Germany) open LiDAR point cloud.
#
# Source  : Landesamt für Vermessung und Geoinformation Sachsen-Anhalt (LVermGeo ST)
#           Open Data · https://www.lvermgeo.sachsen-anhalt.de/de/gdp-open-data.html
# License : Datenlizenz Deutschland – Namensnennung – Version 2.0 (DL-DE/BY 2.0)
#           Attribution required: "© GeoBasis-DE / LVermGeo ST <year>, dl-de/by-2-0"
# CRS     : ETRS89 / UTM Zone 32 — EPSG:25832. Heights DHHN2016 (NHN).
#
# WHAT IS ACTUALLY OPEN — READ THIS FIRST
#
#   Sachsen-Anhalt does NOT publish its statewide point cloud as open data. The full
#   "3D-Messdaten" product is a priced, application-only product (190 € per Datensatz,
#   "auf Antrag" — see /de/gdp-3d-messdaten.html). No Atom feed, no WFS, no tile API
#   exposes it, and the DGM1/DOM1 map downloader caps manual selection at 5 tiles.
#
#   What IS free, anonymous and scriptable is exactly two published sample areas, and
#   that is all this script fetches:
#
#     hakel  Gebiet Hakel            11 tiles   2.9 GB   flown 2019
#     halle  Gemeinde Halle (Saale)  51 tiles  17.4 GB   flown 2017 (one tile 2021)
#
#   Together: 62 tiles, ~20 GB. That is roughly 0.1% of the state — two islands, not a
#   coverage layer. If you need Sachsen-Anhalt statewide, you have to order it.
#
# Datasets (verified live):
#   las  — classified ALS point cloud, .laz (LAS 1.2, PDRF 3)
#          2 km x 2 km tiles, named 3dm_32_<E_km>_<N_km>_2_st_<year>.laz
#          4-8 points/m², classified ground/non-ground, carries Intensity + RGB.
#
#   There is no open `dgm1` here. LVermGeo publishes DGM1 free of charge, but only
#   through the GeoCMS "Kartendownloader" widget, which hard-caps a selection at five
#   2 km tiles per request — a portal, not a bulk endpoint. Asking this script for
#   dgm1 is refused rather than half-implemented; see the README.
#
# Method  : The two areas are plain ZIPs on the LVermGeo webshare. Both are large, and
#           Halle is a ZIP64 archive, so this script does NOT download the archives
#           whole. It reads each ZIP's central directory over HTTP range requests,
#           builds a tile index, then range-fetches and inflates ONLY the tiles you
#           asked for, straight to .laz. Consequences worth knowing:
#             - BBOX works, and costs only the tiles it selects.
#             - No 20 GB of ZIP staged next to 20 GB of output — tiles land directly.
#             - Resume is per tile: a tile whose file already matches the size recorded
#               in the archive is skipped, a partial one is refetched.
#           The server honours Range on both archives (verified); if that ever stops
#           being true the script fails loudly rather than silently truncating.
#
#           The .meta sidecars inside Hakel.zip are fetched alongside their tile.
#           No checksums are published — size-checked against the ZIP directory, not
#           hash-verified.
#
# Usage   : ./download_st_lidar.sh [las] [output_dir]
#   ./download_st_lidar.sh                                  # both areas -> ./st_lidar/las
#   ./download_st_lidar.sh las /mnt/big/st                  # ~20 GB
#   AREAS=hakel ./download_st_lidar.sh                      # just the 2.9 GB one
#   DRY_RUN=1 ./download_st_lidar.sh                        # print the plan, fetch nothing
#   BBOX="658,5746,662,5750" AREAS=hakel ./download_st_lidar.sh
#
# Env vars (override defaults):
#   AREAS="hakel halle"   which published areas to take (default: both)
#   BBOX="minE,minN,maxE,maxN"   UTM32 kilometres, inclusive, on the tile's SW corner
#   JOBS=4    tiles fetched concurrently
#   DRY_RUN=1 list the tiles and their sizes, download nothing
#   OUTDIR=<path>  write the .laz straight here instead of <output_dir>/<dataset>.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#
set -euo pipefail

DATASET="${1:-las}"
OUTROOT="${2:-./st_lidar}"
JOBS="${JOBS:-4}"
DRY_RUN="${DRY_RUN:-0}"
AREAS="${AREAS:-hakel halle}"

case "$DATASET" in
  las) ;;
  dgm1|dom1|both)
    cat >&2 <<'EOF'
ERROR: Sachsen-Anhalt publishes no bulk DGM1/DOM1 endpoint — only the GeoCMS
       "Kartendownloader" widget, which caps a selection at 5 tiles per request:
         https://www.lvermgeo.sachsen-anhalt.de/de/gdp-dgm1.html
       Statewide, DGM and DOM are sold: they are derived from the 3D-Messdaten and
       priced alongside it (190 € je Datensatz, auf Antrag). No endpoint either way.
       This script covers the open sample point cloud only:  ./download_st_lidar.sh las
       (A statewide DGM5 raster IS a single free ZIP, if that is enough for you:
        https://www.geodatenportal.sachsen-anhalt.de/gfds_webshare/download/LVermGeo/Geodatenportal/Online-Bereitstellung-LVermGeo/DGM/DGM5.zip)
EOF
    exit 2 ;;
  *) echo "Usage: $0 [las] [output_dir]" >&2; exit 2 ;;
esac

DIR="${OUTDIR:-$OUTROOT/$DATASET}"
mkdir -p "$DIR"

echo "==> ST las  (Sachsen-Anhalt open 3D-Messdaten)"
echo "    areas : $AREAS"
echo "    out   : $DIR"

AREAS="$AREAS" BBOX="${BBOX:-}" JOBS="$JOBS" DRY_RUN="$DRY_RUN" python3 - "$DIR" <<'PY'
import os, re, struct, sys, threading, urllib.request, zlib
from queue import Queue

OUT   = sys.argv[1]
AREAS = os.environ["AREAS"].split()
BBOX  = os.environ.get("BBOX", "").strip()
JOBS  = int(os.environ["JOBS"])
DRY   = os.environ["DRY_RUN"] == "1"

BASE = ("https://www.geodatenportal.sachsen-anhalt.de/gfds_webshare/download/"
        "LVermGeo/Geodatenportal/externedaten/")
ARCHIVES = {
    "hakel": ("Hakel.zip",              "Gebiet Hakel, flown 2019"),
    "halle": ("Gemeinde_HalleSaale.zip", "Gemeinde Halle (Saale), flown 2017"),
}
UA = {"User-Agent": "download_st_lidar.sh"}

unknown = [a for a in AREAS if a not in ARCHIVES]
if unknown:
    raise SystemExit(f"unknown AREAS {unknown} — known: {', '.join(ARCHIVES)}")

box = None
if BBOX:
    mine, minn, maxe, maxn = (int(v) for v in BBOX.split(","))
    box = (mine, minn, maxe, maxn)

def get(url, start=None, end=None):
    h = dict(UA)
    if start is not None:
        h["Range"] = f"bytes={start}-{end}"
    return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=600)

def size_of(url):
    r = urllib.request.Request(url, headers=UA, method="HEAD")
    return int(urllib.request.urlopen(r, timeout=120).headers["Content-Length"])

def rng(url, a, b):
    with get(url, a, b) as r:
        return r.read()

def zip64_extra(extra, need):
    """Pull the fields flagged 0xFFFFFFFF out of the ZIP64 extra block, in spec order."""
    p = 0
    while p + 4 <= len(extra):
        hid, hsz = struct.unpack("<HH", extra[p:p + 4])
        body = extra[p + 4:p + 4 + hsz]
        if hid == 0x0001:
            vals, q = [], 0
            for _ in range(need):
                if q + 8 > len(body):
                    break
                vals.append(struct.unpack("<Q", body[q:q + 8])[0])
                q += 8
            return vals
        p += 4 + hsz
    return []

def index(url):
    """Read the central directory over ranges -> [(name, local_hdr_off, csize, usize)]."""
    total = size_of(url)
    tail = rng(url, max(0, total - 70000), total - 1)

    loc = tail.rfind(b"PK\x06\x07")
    if loc != -1:                                    # ZIP64
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
        csz, usz = struct.unpack("<II", cd[p + 20:p + 28])
        nl, el, cl = struct.unpack("<HHH", cd[p + 28:p + 34])
        lho = struct.unpack("<I", cd[p + 42:p + 46])[0]
        name = cd[p + 46:p + 46 + nl].decode("utf-8", "replace")
        extra = cd[p + 46 + nl:p + 46 + nl + el]

        # ZIP64: whichever of usize/csize/offset are saturated live in the extra block,
        # in that fixed order. Halle.zip needs this — it is over 4 GB.
        need = [usz == 0xFFFFFFFF, csz == 0xFFFFFFFF, lho == 0xFFFFFFFF]
        if any(need):
            vals = zip64_extra(extra, sum(need))
            it = iter(vals)
            if need[0]: usz = next(it, usz)
            if need[1]: csz = next(it, csz)
            if need[2]: lho = next(it, lho)

        if not name.endswith("/"):
            out.append((name, lho, csz, usz))
        p += 46 + nl + el + cl
    return out

# Tile names carry the SW corner in km: 3dm_32_658_5746_2_st_2019.laz
TILE = re.compile(r"3dm_32_(\d+)_(\d+)_")

plan, skipped_box = [], 0
for area in AREAS:
    fname, label = ARCHIVES[area]
    url = BASE + fname
    print(f"    {area}: {label}")
    entries = index(url)
    laz = [e for e in entries if e[0].endswith(".laz")]
    meta = {os.path.basename(e[0])[:-5]: e for e in entries if e[0].endswith(".meta")}
    took = 0
    for name, lho, csz, usz in laz:
        base = os.path.basename(name)
        if box:
            m = TILE.search(base)
            if not m:
                continue
            e_km, n_km = int(m.group(1)), int(m.group(2))
            if not (box[0] <= e_km <= box[2] and box[1] <= n_km <= box[3]):
                skipped_box += 1
                continue
        plan.append((url, base, lho, csz, usz))
        took += 1
        side = meta.get(base[:-4])
        if side:
            plan.append((url, os.path.basename(side[0]), side[1], side[2], side[3]))
    print(f"      {took}/{len(laz)} tiles selected")

laz_plan = [p for p in plan if p[1].endswith(".laz")]
total_bytes = sum(p[4] for p in laz_plan)
print(f"    tiles: {len(laz_plan)}  ~{total_bytes / 1e9:.1f} GB uncompressed"
      + (f"  ({skipped_box} outside BBOX)" if box else ""))
print("    no checksums published — size-checked against the ZIP directory, not hash-verified")

if not laz_plan:
    if box:
        # A BBOX that matches nothing is the normal case here, not an error: the open data
        # is two islands, so most of Sachsen-Anhalt has no open tile to hand back. Exit 0
        # with "tiles: 0" already printed above, so download_samples.sh reports it as a
        # coverage gap rather than a failed download.
        print("    this square lies outside the two published areas "
              "(Hakel ~656-664/5746-5752, Halle ~698-714/5698-5714, UTM32 km)")
        raise SystemExit(0)
    raise SystemExit("no tile selected — check AREAS (BBOX is UTM32 kilometres)")

if DRY:
    for _, base, _, _, usz in laz_plan:
        print(f"      {base}  {usz / 1e6:.0f} MB")
    print("    DRY_RUN=1 — skipping download.")
    raise SystemExit(0)

def fetch(url, base, lho, csz, usz):
    dest = os.path.join(OUT, base)
    if os.path.exists(dest) and os.path.getsize(dest) == usz:
        return f"      = {base} (already complete)"

    lh = rng(url, lho, lho + 29)
    if lh[:4] != b"PK\x03\x04":
        raise RuntimeError(f"{base}: bad local header — server ignored Range?")
    nl, el = struct.unpack("<HH", lh[26:30])
    start = lho + 30 + nl + el

    tmp = dest + ".part"
    dec = zlib.decompressobj(-15)
    got = 0
    with get(url, start, start + csz - 1) as r, open(tmp, "wb") as fh:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            block = dec.decompress(chunk)
            fh.write(block)
            got += len(block)
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

cat <<EOF

Attribution required — include a visible source note in any product/publication:
  © GeoBasis-DE / LVermGeo ST $(date +%Y), dl-de/by-2-0

Note: this is Sachsen-Anhalt's OPEN point cloud — two sample areas (~0.1% of the state),
not statewide coverage. The full 3D-Messdaten product is priced and application-only:
  https://www.lvermgeo.sachsen-anhalt.de/de/gdp-3d-messdaten.html
EOF
