#!/usr/bin/env bash
#
# download_hh_lidar.sh — download the Hamburg (Germany) open elevation models.
#
# Source  : Freie und Hansestadt Hamburg, Landesbetrieb Geoinformation und Vermessung (LGV)
#           Transparenzportal · https://suche.transparenz.hamburg.de/dataset/digitales-hoehenmodell-hamburg-dgm-16
#           Files             · https://daten-hamburg.de/geographie_geologie_geobasisdaten/…
# License : Datenlizenz Deutschland – Namensnennung – Version 2.0 (dl-de/by-2-0)
#           http://www.govdata.de/dl-de/by-2-0 — required source note:
#             "Freie und Hansestadt Hamburg, Landesbetrieb Geoinformation und Vermessung (LGV)"
# CRS     : ETRS89 / UTM Zone 32 — EPSG:25832.
# Tiling  : 1 km x 1 km, SW corner snapped to whole km — the same grid as the other states.
#           (The older archives are named "2x2km"; their entries are 1 km tiles regardless.)
#
# The README recorded this state as "published, but daten-hamburg.de 403s directory listings".
# The listings do 403 — the files do not. Every archive is a plain anonymous HTTPS GET with
# Content-Length and Range support; what was missing was the file list, and that comes from
# the Transparenzportal's CKAN API rather than from a directory index.
#
# Datasets (verified live 2026-08-03):
#   dgm1 — bare-earth terrain model, 1 m grid, statewide (~880 tiles for Hamburg's 755 km²)
#          9 vintages, 2013 through 2022-04-30, one ZIP each
#          2013-2021 are ASCII XYZ (2.1-3.2 GB) · 2022-04-30 is GeoTIFF (1.3 GB)
#
#   dom1 — bildbasiertes Digitales Oberflächenmodell (bDOM): a surface model derived
#          photogrammetrically from aerial imagery, NOT from laser. 1 m grid, excludes the
#          Hamburg Wattenmeer. 4 vintages, 2018 through 2022-11-21.
#
#   las  — NOT AVAILABLE. Hamburg publishes no open airborne laser point cloud; the elevation
#          models above are the whole of what the LGV gives away.
#
# CAVEAT — the portal's own format labels are wrong for the newest DGM1. The Transparenzportal
# lists dgm1_hh_2022-04-30.zip as "PNG"; the archive contains GeoTIFF (.tif). This script
# reads the actual entry names out of each archive instead of trusting the catalogue, so the
# extension you get is whatever is really in there.
#
# Method  : Two steps, neither of which needs a directory listing.
#           1. Ask the CKAN API for the elevation-model packages, keep the resources that live
#              on daten-hamburg.de under the right product path, and read the vintage out of
#              each filename. So a new annual edition is picked up without editing this file.
#           2. Fetch tiles out of the chosen archive over HTTP ranges — read its central
#              directory, then range-fetch and inflate only the tiles selected, straight to
#              disk. Same technique as download_sl_lidar.sh / download_st_lidar.sh:
#                - BBOX works, and costs only the tiles it selects.
#                - No 1.3-3.2 GB of ZIP staged next to the output.
#                - Resume is per tile, size-checked against the ZIP directory.
#
#           No checksums are published — sizes are checked against the ZIP directory, not
#           hash-verified.
#
# Usage   : ./download_hh_lidar.sh [dgm1|dom1|both] [output_dir]
#   ./download_hh_lidar.sh                                  # newest DGM1 (2022 GeoTIFF), 1.3 GB
#   ./download_hh_lidar.sh dgm1 /mnt/big/hh                 # same, somewhere else
#   ./download_hh_lidar.sh both                             # DGM1 + bDOM
#   LIST=1 ./download_hh_lidar.sh dgm1                      # show the vintages, fetch nothing
#   VINTAGE=2021 ./download_hh_lidar.sh dgm1                # an older edition (XYZ, not TIFF)
#   BBOX="565,5930,570,5935" ./download_hh_lidar.sh         # central Hamburg only
#
# Env vars (override defaults):
#   VINTAGE=<prefix>  pick an edition by date prefix ("2021", "2022-04"); default: the newest
#   BBOX="minE,minN,maxE,maxN"  UTM32 kilometres, inclusive, on the tile's SW corner
#   LIST=1     list the available vintages and exit
#   JOBS=4     tiles fetched concurrently
#   DRY_RUN=1  list the tiles and their sizes, download nothing
#   OUTDIR=<path>  write the tiles straight here instead of <output_dir>/<dataset>.
#                  Single-dataset runs only — with "both" the two products would collide.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./hh_lidar}"
JOBS="${JOBS:-4}"
DRY_RUN="${DRY_RUN:-0}"

case "$DATASET" in
  dgm1|dom1) DATASETS="$DATASET" ;;
  both)      DATASETS="dgm1 dom1" ;;
  las)
    cat >&2 <<'EOF'
Hamburg publishes no open airborne laser point cloud.
What the LGV gives away is the derived elevation models: `dgm1` (terrain) and `dom1` (bDOM,
a surface model computed from aerial imagery rather than from laser returns).
EOF
    exit 3 ;;
  *) echo "Usage: $0 [dgm1|dom1|both] [output_dir]" >&2; exit 2 ;;
esac

if [[ -n "${OUTDIR:-}" && "$DATASET" == "both" ]]; then
  echo "ERROR: OUTDIR is for single-dataset runs — dgm1 and dom1 would collide in one folder." >&2
  exit 2
fi

fetch_one() {
  local dataset="$1"
  local DIR="${OUTDIR:-$OUTROOT/$dataset}"
  mkdir -p "$DIR"

  echo "==> HH $dataset"
  echo "    out       : $DIR"

  DATASET="$dataset" BBOX="${BBOX:-}" VINTAGE="${VINTAGE:-}" LIST="${LIST:-0}" \
  JOBS="$JOBS" DRY_RUN="$DRY_RUN" python3 - "$DIR" <<'PY'
import json, os, re, struct, sys, threading, time, urllib.parse, urllib.request, zlib
from queue import Queue

OUT     = sys.argv[1]
DATASET = os.environ["DATASET"]
BBOX    = os.environ.get("BBOX", "").strip()
VINTAGE = os.environ.get("VINTAGE", "").strip()
LIST    = os.environ["LIST"] == "1"
JOBS    = int(os.environ["JOBS"])
DRY     = os.environ["DRY_RUN"] == "1"

CKAN = "https://suche.transparenz.hamburg.de/api/3/action/package_search"
UA   = {"User-Agent": "download_hh_lidar.sh"}

# Which resources belong to which product. The catalogue holds dozens of near-duplicate
# packages (snapshot copies, re-registrations), so resources are selected by their file URL
# rather than by package name: the path segment is what actually distinguishes the products.
PRODUCTS = {
    "dgm1": {"query": "Digitales Höhenmodell Hamburg DGM 1",
             "path": "/digitales_hoehenmodell/dgm1/",
             "label": "terrain model, 1 m grid"},
    "dom1": {"query": "bDOM",
             "path": "/digitales_hoehenmodell_bdom/",
             "label": "bDOM surface model, 1 m grid, image-derived"},
}
prod = PRODUCTS[DATASET]

def get(url, start=None, end=None, timeout=600):
    h = dict(UA)
    if start is not None:
        h["Range"] = f"bytes={start}-{end}"
    return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=timeout)

def rng(url, a, b):
    with get(url, a, b) as r:
        return r.read()

# ---- 1. discover the editions -------------------------------------------------------------
# Filenames carry the vintage in three different shapes across the years:
#   DGM1_2x2KM_XYZ_HH_2014.zip · DGM1_2x2KM_XYZ_HH_2016-01-04.zip
#   dgm1_2x2km_XYZ_hh_2021_04_01.zip · dgm1_hh_2022-04-30.zip
# Normalising the separators makes them sort chronologically as plain strings.
DATE = re.compile(r"(\d{4})(?:[-_](\d{2}))?(?:[-_](\d{2}))?\.zip$", re.I)

url = f"{CKAN}?q={urllib.parse.quote(prod['query'])}&rows=50"
with get(url, timeout=180) as r:
    results = json.load(r)["result"]["results"]

editions = {}
for pkg in results:
    for res in pkg.get("resources", []):
        u = res.get("url") or ""
        if "daten-hamburg.de" not in u.lower() or prod["path"] not in u.lower():
            continue
        m = DATE.search(u)
        if not m:
            continue
        vintage = "-".join(g for g in m.groups() if g)
        # https, and prefer the first URL seen for a vintage — duplicates are byte-identical
        # copies registered under several packages.
        editions.setdefault(vintage, u.replace("http://", "https://", 1))

if not editions:
    raise SystemExit(f"no {DATASET} archive found on daten-hamburg.de — "
                     f"the Transparenzportal catalogue changed")

order = sorted(editions)
if LIST:
    print(f"    vintages ({prod['label']}):")
    for v in order:
        print(f"      {v}  {editions[v].rsplit('/', 1)[-1]}")
    raise SystemExit(0)

if VINTAGE:
    matches = [v for v in order if v.startswith(VINTAGE)]
    if not matches:
        raise SystemExit(f"VINTAGE={VINTAGE} matches none of: {', '.join(order)}")
    chosen = matches[-1]
else:
    chosen = order[-1]

archive = editions[chosen]
with get(archive, 0, 0) as r:                       # a 1-byte range, just for the length
    total = int(r.headers["Content-Range"].split("/")[-1])
print(f"    vintage   : {chosen}  ({len(order)} available: {', '.join(order)})")
print(f"    archive   : {archive.rsplit('/', 1)[-1]}  ({total / 1e9:.2f} GB)")

# ---- 2. read the archive's central directory over ranges -----------------------------------
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
    """-> [(name, local_hdr_off, method, csize, usize)]"""
    tail = rng(url, max(0, total - 70000), total - 1)
    loc = tail.rfind(b"PK\x06\x07")
    if loc != -1:                                    # ZIP64 locator
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

entries = index(archive, total)

# The extension is read off the archive rather than assumed: 2013-2021 are .xyz, 2022 is .tif,
# and the portal's own metadata calls the 2022 one "PNG", which it is not.
tiles = [e for e in entries if e[0].lower().endswith((".tif", ".xyz"))]
if not tiles:
    raise SystemExit(f"no .tif/.xyz entries in {archive} — packaging changed")
ext = os.path.splitext(tiles[0][0])[1].lower()
skipped_meta = len(entries) - len(tiles)

# dgm1_32_566_5934_1_hh_2022.tif / dgm1_32_548_5934_1_hh.xyz -> tile key (566, 5934)
TILE = re.compile(r"_32_(\d+)_(\d+)_1_hh", re.I)

box = None
if BBOX:
    vals = BBOX.split(",")
    if len(vals) != 4:
        raise SystemExit(f"BBOX needs four values, got {len(vals)}")
    box = [int(float(v)) for v in vals]

plan, skipped_box = [], 0
for name, lho, method, csz, usz in tiles:
    base = os.path.basename(name)
    if box:
        m = TILE.search(base)
        if not m:
            continue
        e_km, n_km = int(m.group(1)), int(m.group(2))
        if not (box[0] <= e_km <= box[2] and box[1] <= n_km <= box[3]):
            skipped_box += 1
            continue
    plan.append((archive, base, lho, method, csz, usz))

print(f"    tiles     : {len(plan)}/{len(tiles)} selected, {ext}  "
      f"~{sum(p[5] for p in plan) / 1e9:.2f} GB"
      + (f"  ({skipped_box} outside BBOX)" if box else ""))
if skipped_meta:
    print(f"    note      : {skipped_meta} non-tile entr(ies) in the archive skipped "
          f"(the LGV's own tile-index CSV)")
print("    no checksums published — size-checked against the ZIP directory, not hash-verified")

if not plan:
    if box:
        # An empty BBOX is a coverage question, not a failure: exit 0 so download_samples.sh
        # reports it as a gap. Hamburg spans roughly E 543-568 / N 5916-5957 in UTM32 km.
        print("    this square selected no tile — Hamburg's grid spans roughly "
              "E 543-568 / N 5916-5957 in UTM32 km")
        raise SystemExit(0)
    raise SystemExit("no tile selected")

if DRY:
    for _, base, _, _, _, usz in plan[:10]:
        print(f"      {base}  {usz / 1e6:.1f} MB")
    if len(plan) > 10:
        print(f"      … and {len(plan) - 10} more")
    print("    DRY_RUN=1 — skipping download.")
    raise SystemExit(0)

# ---- 3. range-fetch the selected tiles ------------------------------------------------------
def fetch(url, base, lho, method, csz, usz, attempts=4):
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
    return f"      + {base}  {usz / 1e6:.1f} MB"

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

  [[ "${LIST:-0}" == "1" ]] || echo "    done -> $DIR"
}

for ds in $DATASETS; do
  fetch_one "$ds"
done

cat <<EOF

Attribution required — include a visible source note in any product/publication:
  Freie und Hansestadt Hamburg, Landesbetrieb Geoinformation und Vermessung (LGV)
  Datenlizenz Deutschland – Namensnennung – Version 2.0 (http://www.govdata.de/dl-de/by-2-0)
EOF
