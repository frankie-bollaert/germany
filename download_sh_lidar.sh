#!/usr/bin/env bash
#
# download_sh_lidar.sh — bulk-download the Schleswig-Holstein (Germany) open DGM1.
#
# Source  : Landesamt für Vermessung und Geoinformation Schleswig-Holstein (LVermGeo SH)
#           OpenGBD-Downloadportal · https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/dl-dgm1.html
#           Tile index (GeoJSON)   · .../single.php?file=DGM1_SH__Massendownload.geojson&id=4
# License : Creative Commons Attribution 4.0 International (CC BY 4.0)
#           .../dladownload/lizenz.html — the licensor's required source note, verbatim:
#             "©GeoBasis-DE/LVermGeo SH/CC BY 4.0"
#           and when the data has been altered, the same note with "(Quelle verändert)".
# CRS     : ETRS89 / UTM Zone 32 — EPSG:25832 (declared by the index's `crs` member).
# Tiling  : 1 km x 1 km, SW corner snapped to whole km — the same grid as NI/RLP/BW/BY/NRW.
#
# This state was listed in the README as "gaialight app returns an empty FeatureCollection"
# until 2026-08-03. It does not: the index carries 18,685 tiles, each with a direct download
# link, and the tiles fetch anonymously. Statewide coverage, 424-650 E / 5912-6102 N.
#
# Datasets (verified live 2026-08-03):
#   dgm1 — bare-earth terrain model, 1 m grid, **ASCII XYZ** (not GeoTIFF, not LAS)
#          one file per km², 1,000,000 records of "<easting> <northing> <height>", ~27.5 MB
#          statewide: 18,685 tiles, ~515 GB
#
#          Vintages run 2005-2025 and the index holds exactly ONE tile per km² — a reflown
#          km² replaces its predecessor rather than being added alongside it, so there is no
#          "latest campaign" filter to apply (contrast download_ni_lidar.sh, where LATEST=1
#          exists precisely because NI keeps every campaign). The mix is uneven, though:
#          3,550 tiles are still 2005 and 3,963 are 2025, so MINYEAR is offered below for
#          anyone who would rather have a hole than twenty-year-old heights.
#
#   las  — NOT AVAILABLE. LVermGeo SH publishes no open point cloud: the download portal
#          serves dl-dgm1.html and nothing else (dl-las / dl-dom1 / dl-lidar all 404).
#
# Method  : Fetch the GeoJSON index (~9 MB), read each feature's `link_data`, then pull the
#           tiles with a thread pool. Three properties of this endpoint shape the design:
#
#           1. It ignores Range and sends no Content-Length (PHP streams the body chunked),
#              so aria2c cannot resume a partial tile and a size check is impossible before
#              the fact. Tiles are therefore all-or-nothing: .part file, validated, renamed.
#           2. Every response has ~759 bytes of HTML navigation markup appended AFTER the
#              last data record. Left in place it corrupts the XYZ for every downstream
#              reader, so it is stripped. Its presence doubles as the completeness signal —
#              a truncated response cannot contain the closing markup.
#           3. Some index entries are dead. The server answers those with HTTP 200 and a
#              German error body ("Die verwendete Massendownload-Datei ist veraltet"), which
#              a naive downloader happily writes out as a 962-byte .xyz. Those are detected,
#              skipped and listed at the end. Measured 2026-08-03: ~1.7% of a 60-tile sample,
#              all of it in the 2005 vintage.
#
#           Each tile is validated before it is renamed into place: the closing markup must
#           be present, and the first and last records must equal the tile's NW and SE corner
#           coordinates as computed from its name. That catches truncation and mis-served
#           tiles alike. Re-running skips any tile whose last record already matches its SE
#           corner, so a failed run costs only the tiles it did not finish.
#
#           No checksums are published — tiles are structurally validated, not hash-verified.
#
#           No gzip: the server does not honour Accept-Encoding, so ~515 GB is the wire
#           volume as well as the disk volume. XYZ is roughly 7x the size of the equivalent
#           GeoTIFF — see the note at the bottom about converting.
#
# Usage   : ./download_sh_lidar.sh [dgm1] [output_dir]
#   ./download_sh_lidar.sh                                  # statewide, ~515 GB
#   ./download_sh_lidar.sh dgm1 /mnt/big/sh                 # same, somewhere with room
#   DRY_RUN=1 ./download_sh_lidar.sh                        # list the tiles, fetch nothing
#   BBOX="424,6000,428,6004" ./download_sh_lidar.sh         # one 4x4 km corner
#   MINYEAR=2020 ./download_sh_lidar.sh                     # skip the older vintages
#
# Env vars (override defaults):
#   BBOX="minE,minN,maxE,maxN"   UTM32 kilometres, inclusive, on the tile's SW corner
#   MINYEAR=2005                 drop tiles flown before this year (default: keep all)
#   JOBS=4     tiles fetched concurrently — the portal is a single PHP host, be polite
#   DRY_RUN=1  list the tiles, download nothing
#   OUTDIR=<path>  write the .xyz straight here instead of <output_dir>/<dataset>.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#
set -euo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./sh_lidar}"
JOBS="${JOBS:-4}"
DRY_RUN="${DRY_RUN:-0}"

case "$DATASET" in
  dgm1) ;;
  las)
    cat >&2 <<'EOF'
Schleswig-Holstein publishes no open airborne laser point cloud.
The OpenGBD download portal serves dl-dgm1.html only — dl-las.html, dl-dom1.html and
dl-lidar.html all 404. Use `dgm1`, which is the 1 m terrain model derived from those flights.
EOF
    exit 3 ;;
  both)
    echo "note: SH has no point cloud — running dgm1 only." >&2
    DATASET=dgm1 ;;
  *) echo "Usage: $0 [dgm1] [output_dir]" >&2; exit 2 ;;
esac

DIR="${OUTDIR:-$OUTROOT/$DATASET}"
mkdir -p "$DIR"

echo "==> SH dgm1  (Schleswig-Holstein terrain model, 1 m grid, ASCII XYZ)"
echo "    out       : $DIR"

BBOX="${BBOX:-}" MINYEAR="${MINYEAR:-0}" JOBS="$JOBS" DRY_RUN="$DRY_RUN" python3 - "$DIR" <<'PY'
import json, os, re, sys, threading, time, urllib.error, urllib.request
from queue import Queue

OUT     = sys.argv[1]
BBOX    = os.environ.get("BBOX", "").strip()
MINYEAR = int(os.environ["MINYEAR"])
JOBS    = int(os.environ["JOBS"])
DRY     = os.environ["DRY_RUN"] == "1"

BASE  = "https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload"
INDEX = f"{BASE}/single.php?file=DGM1_SH__Massendownload.geojson&id=4"
UA    = {"User-Agent": "download_sh_lidar.sh"}

# The HTML the server staples onto every tile, and the body it sends instead of a tile when
# the index entry has gone stale. Both arrive with HTTP 200.
HTML_MARK  = b"<!DOCTYPE html>"
STALE_MARK = b"konnte nicht heruntergeladen werden"

def fetch_url(url, timeout=600):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout)

# The index is re-fetched every run rather than cached: it is only ~9 MB, and a cached copy is
# exactly what produces the "veraltet" errors above. A copy is kept next to the tiles so a run
# can be audited after the fact.
print(f"    index     : {INDEX}")
with fetch_url(INDEX, timeout=300) as r:
    raw = r.read()
with open(os.path.join(OUT, ".dgm1_index.geojson"), "wb") as fh:
    fh.write(raw)
doc = json.loads(raw)
feats = doc.get("features", [])
if not feats:
    raise SystemExit("the index came back with no features — the portal layout changed")
print(f"    tiles     : {len(feats)} in the index  ({len(raw) / 1e6:.1f} MB of GeoJSON)")

# dgm1_32_424_6002_1_sh_2005.xyz -> tile key (424, 6002), vintage 2005
NAME = re.compile(r"file=(dgm1_32_(\d+)_(\d+)_1_sh_(\d{4})\.xyz)")

box = None
if BBOX:
    vals = BBOX.split(",")
    if len(vals) != 4:
        raise SystemExit(f"BBOX needs four values, got {len(vals)}")
    box = [int(float(v)) for v in vals]

plan, skipped_box, skipped_year, unparseable = [], 0, 0, 0
for f in feats:
    link = (f.get("properties") or {}).get("link_data") or ""
    m = NAME.search(link)
    if not m:
        unparseable += 1
        continue
    name, e_km, n_km, year = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))
    if box and not (box[0] <= e_km <= box[2] and box[1] <= n_km <= box[3]):
        skipped_box += 1
        continue
    if year < MINYEAR:
        skipped_year += 1
        continue
    plan.append((link, name, e_km, n_km))

plan.sort(key=lambda p: p[1])

# No Content-Length anywhere, so the total is an estimate from the observed mean tile size.
print(f"    selected  : {len(plan)}  ~{len(plan) * 27.5 / 1000:.1f} GB estimated"
      + (f"  ({skipped_box} outside BBOX)" if box else "")
      + (f"  ({skipped_year} before {MINYEAR})" if MINYEAR else ""))
if unparseable:
    print(f"    note      : {unparseable} index entr(ies) had no parseable tile name — skipped")
print("    no checksums published — tiles are structurally validated, not hash-verified")

if not plan:
    if box:
        # An empty BBOX is a coverage question, not a failure: exit 0 so download_samples.sh
        # reports it as a gap rather than a failed download. SH spans E 424-650 / N 5912-6102.
        print("    this square selected no tile — Schleswig-Holstein's grid spans "
              "E 424-650 / N 5912-6102 in UTM32 km")
        raise SystemExit(0)
    raise SystemExit("no tile selected — check BBOX/MINYEAR")

if DRY:
    for _, name, _, _ in plan[:10]:
        print(f"      {name}")
    if len(plan) > 10:
        print(f"      … and {len(plan) - 10} more")
    print("    DRY_RUN=1 — skipping download.")
    raise SystemExit(0)

def corners(e_km, n_km):
    """The first and last record of a full tile, as the server formats them.

    Rows run north to south, columns west to east, on 1 m cell centres — so the first record
    is the NW cell centre and the last is the SE one.
    """
    nw = (f"{e_km * 1000 + 0.5:.2f}", f"{n_km * 1000 + 999.5:.2f}")
    se = (f"{e_km * 1000 + 999.5:.2f}", f"{n_km * 1000 + 0.5:.2f}")
    return nw, se

def last_record(path, window=256):
    """Last non-empty line of a file, read from the tail — used for the resume check."""
    with open(path, "rb") as fh:
        fh.seek(0, os.SEEK_END)
        size = fh.tell()
        fh.seek(max(0, size - window))
        tail = fh.read()
    lines = [l for l in tail.replace(b"\r\n", b"\n").split(b"\n") if l.strip()]
    return lines[-1] if lines else b""

class Stale(Exception):
    """The index entry is dead — retrying will not help."""

def fetch(link, name, e_km, n_km, attempts=4):
    for attempt in range(1, attempts + 1):
        try:
            return _fetch(link, name, e_km, n_km)
        except Stale:
            raise
        except Exception as exc:
            if attempt == attempts:
                raise
            with lock:
                print(f"      ~ {name}: {exc} — retry {attempt}/{attempts - 1}", flush=True)
            time.sleep(2 ** attempt)

def _fetch(link, name, e_km, n_km):
    dest = os.path.join(OUT, name)
    nw, se = corners(e_km, n_km)

    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        fields = last_record(dest).split()
        if len(fields) >= 2 and (fields[0].decode(), fields[1].decode()) == se:
            return f"      = {name} (already complete)"

    tmp = dest + ".part"
    with fetch_url(link) as r, open(tmp, "wb") as fh:
        head = r.read(len(STALE_MARK) + 200)
        if STALE_MARK in head:
            fh.close()
            os.remove(tmp)
            raise Stale(name)
        fh.write(head)
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            fh.write(chunk)

    # The appended markup is the only proof the response ran to completion — the server sends
    # no length, so a connection cut mid-stream is otherwise indistinguishable from a full one.
    with open(tmp, "rb") as fh:
        fh.seek(0, os.SEEK_END)
        size = fh.tell()
        fh.seek(max(0, size - 4096))
        tail = fh.read()
    cut = tail.find(HTML_MARK)
    if cut == -1:
        os.remove(tmp)
        raise RuntimeError(f"{name}: response ended without the portal's closing markup — truncated")

    # Truncate the markup off, then normalise to one trailing CRLF.
    keep = max(0, size - 4096) + cut
    with open(tmp, "r+b") as fh:
        fh.seek(max(0, keep - 64))
        run = fh.read(64).rstrip(b"\r\n \t")
        fh.truncate(max(0, keep - 64) + len(run))
        fh.seek(0, os.SEEK_END)
        fh.write(b"\r\n")

    first = open(tmp, "rb").readline().split()
    last = last_record(tmp).split()
    got_first = (first[0].decode(), first[1].decode()) if len(first) >= 2 else ("", "")
    got_last = (last[0].decode(), last[1].decode()) if len(last) >= 2 else ("", "")
    if got_first != nw or got_last != se:
        os.remove(tmp)
        raise RuntimeError(f"{name}: corners are {got_first}..{got_last}, expected {nw}..{se}")

    # Counted on the finished file rather than on the stream, so the stapled markup's own
    # newlines cannot inflate it. A full tile is 1000x1000 cells; anything else is served
    # data and worth flagging, but not worth rejecting — the corner check above already
    # proved the tile spans its full kilometre.
    records = 0
    with open(tmp, "rb") as fh:
        while True:
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            records += chunk.count(b"\n")

    os.replace(tmp, dest)
    mb = os.path.getsize(dest) / 1e6
    warn = "" if records == 1_000_000 else f"  (!{records} records, expected 1,000,000)"
    return f"      + {name}  {mb:.0f} MB{warn}"

q = Queue()
for item in plan:
    q.put(item)
errors, stale = [], []
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
        except Stale:
            with lock:
                stale.append(item[1])
                print(f"      · {item[1]}: index entry is stale, the portal has no such tile",
                      flush=True)
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

if stale:
    print(f"\n    {len(stale)} tile(s) are indexed but not served — the portal calls the index "
          f"entry 'veraltet'. Re-running will not help; these are holes in SH's own catalogue:")
    for s in stale[:20]:
        print(f"      {s}")
    if len(stale) > 20:
        print(f"      … and {len(stale) - 20} more")

if errors:
    print(f"\n    {len(errors)} tile(s) failed — rerun to retry just those:", file=sys.stderr)
    for e in errors:
        print(f"      {e}", file=sys.stderr)
    raise SystemExit(1)
PY

echo "    done -> $DIR"

cat <<EOF

XYZ, not raster: these are ASCII point grids. To get a GeoTIFF per tile (about a seventh of
the bytes, and what convert_to_cloud_optimized.sh expects):
  gdal_translate -a_srs EPSG:25832 -of GTiff tile.xyz tile.tif

Attribution required (CC BY 4.0) — include in any product/publication:
  ©GeoBasis-DE/LVermGeo SH/CC BY 4.0
  and when the data has been altered:  ©GeoBasis-DE/LVermGeo SH/CC BY 4.0 (Quelle verändert)
EOF
