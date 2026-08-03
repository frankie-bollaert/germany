#!/usr/bin/env bash
#
# download_by_parzellarkarte.sh — bulk-download the Bayern ALKIS-Parzellarkarte (raster).
#
# Source : Landesamt für Digitalisierung, Breitband und Vermessung (LDBV Bayern)
#          OpenData portal https://geodaten.bayern.de/opengeodata/  (pn=parzellarkarte)
# License : CC BY 4.0 — attribution REQUIRED:
#           "Datenquelle: Bayerische Vermessungsverwaltung – www.geodaten.bayern.de"
# CRS     : ETRS89 / UTM Zone 32 (EPSG:25832)
# Tiling  : 1 km x 1 km, SW corner snapped to whole km — same grid as download_by_lidar.sh.
#
# What this is, and what it is NOT
# ---------------------------------------------------------------------------------------
# The Parzellarkarte is the cadastral map as a PICTURE. It carries Flurkarte objects —
# parcel boundaries, buildings, Lagebezeichnungen, TN objects — but per LDBV's own product
# text "keine Flurstücksnummern und keine Grenzzeichen", and every parcel boundary is drawn
# as a uniform solid line. The numbers you can read on it are HOUSE numbers, not parcel
# numbers.
#
# So it shows you where Bavaria's parcels are, and it is the only open product that does,
# but it is raster: no geometry, no identifiers, no attributes. It cannot fill `plots`, and
# it is not a substitute for the vector Flurstücke LDBV sells through GeodatenOnline. See
# README.md, "The two content gaps".
#
# Method  : same poly2metalink polygon service download_by_lidar.sh uses for `las`, but this
#           product is capped at 10 km² per request, not 2000 — so the sweep steps in 3x3 km
#           (9 km²) cells. Each returned <file> is one 1 km² tile whose <url> is a WMS GetMap
#           call at 300 DPI: 11811 x 11811 px, ~8.5 cm/px, LZW RGB GeoTIFF, ~22 MB.
#
#           Those tiles are RENDERED ON DEMAND (the service reports type "wms"), not served
#           from a pre-built store. One tile costs the server ~20 s. That is why the cap is
#           10 km² and why JOBS defaults to 4 rather than the 8 the other downloaders use:
#           this is a renderer, not a file store, and it should not be hammered.
#
#           The metalink carries names and URLs only — no sizes, no checksums — so downloads
#           are resumable but NOT hash-verified.
#
# Scale   : ~22 MB per km², in town and in open country alike (LZW on 139 megapixels lands in
#           the same place either way). Bavaria is ~70,550 km²: about 1.5 TB and ~400 hours
#           of server-side rendering, requested through ~7,800 POSTs. That is not a sensible
#           thing to do to a live renderer, so a statewide run is refused unless you insist
#           with ALLOW_STATEWIDE=1. Pass a BBOX.
#
# Usage   : ./download_by_parzellarkarte.sh [output_dir]
#   BBOX="656,5260,661,5265" ./download_by_parzellarkarte.sh        # Garmisch, 25 tiles
#   BBOX="690,5334,693,5337" ./download_by_parzellarkarte.sh /mnt/big/by
#   DRY_RUN=1 BBOX=... ./download_by_parzellarkarte.sh              # plan only
#
# Env vars (override defaults):
#   BBOX="minE,minN,maxE,maxN"   # UTM32 kilometres, inclusive of minE/minN, exclusive of max
#   JOBS=4   CONN=2   DRY_RUN=1
#   OUTDIR=<path>       write the files straight here, instead of <output_dir>/parzellarkarte
#   ALLOW_STATEWIDE=1   permit a run with no BBOX (~1.5 TB — see above)
#
set -euo pipefail

OUTROOT="${1:-./by_parzellarkarte}"
JOBS="${JOBS:-4}"          # concurrent tiles — deliberately low, these are rendered live
CONN="${CONN:-2}"          # connections per tile
DRY_RUN="${DRY_RUN:-0}"

POLY2META="https://geoservices.bayern.de/services/poly2metalink/metalink/parzellarkarte"
LIMITS_URL="https://geoservices.bayern.de/services/poly2metalink/datasets/parzellarkarte"

# Bavaria's extent in EPSG:25832 kilometres, rounded outward to the sweep step.
BY_MINE=560; BY_MAXE=960; BY_MINN=5230; BY_MAXN=5610
STEP=3                     # 3x3 km = 9 km² < the service's 10 km² cap

command -v aria2c >/dev/null 2>&1 || {
  echo "ERROR: aria2c not found. Install it:  brew install aria2  (macOS)  |  apt install aria2 (Debian/Ubuntu)" >&2
  exit 1
}

dir="${OUTDIR:-$OUTROOT/parzellarkarte}"
echo "==> parzellarkarte"
echo "    service : $POLY2META  (10 km²/request — swept in ${STEP}x${STEP} km polygons)"

mine="$BY_MINE"; minn="$BY_MINN"; maxe="$BY_MAXE"; maxn="$BY_MAXN"
if [[ -n "${BBOX:-}" ]]; then
  IFS=, read -r mine minn maxe maxn <<<"$BBOX"
  echo "    BBOX    : $mine,$minn,$maxe,$maxn (UTM32 km)"
elif [[ "${ALLOW_STATEWIDE:-0}" != "1" ]]; then
  # Refusing loudly beats quietly starting a 1.5 TB job against a live renderer. Same
  # reasoning as download_samples.sh: a run that cannot stay a sample should say so.
  cat >&2 <<EOF
ERROR: no BBOX given — that means all of Bavaria: ~70,550 tiles, ~1.5 TB, and roughly
       400 hours of on-demand rendering spread over ~7,800 POSTs to a live service.
       Pass BBOX="minE,minN,maxE,maxN" in UTM32 km, or ALLOW_STATEWIDE=1 to insist.
       The repo's Bayern sample square is BBOX="656,5260,661,5265" (Garmisch, 25 tiles).
EOF
  exit 2
fi

(( maxe > mine && maxn > minn )) || { echo "ERROR: empty BBOX $mine,$minn,$maxe,$maxn" >&2; exit 2; }

mkdir -p "$dir"

# The cap is served by the API rather than hard-coded here, so a change upstream shows up as
# a mismatch instead of as a wall of rejected polygons.
limit_qkm="$(curl -fsS --max-time 30 "$LIMITS_URL" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("areaLimitQkm",""))' 2>/dev/null || true)"
if [[ -n "$limit_qkm" ]] && (( STEP * STEP > limit_qkm )); then
  echo "ERROR: service now caps requests at ${limit_qkm} km², below this script's ${STEP}x${STEP} km cell." >&2
  exit 1
fi

input="$dir/.aria2.input"
: >"$input.tmp"

# Sweep the box in STEP-sized cells, clipped to it. Clipping matters: an unclipped cell always
# spans the full STEP, so a BBOX narrower than STEP would be silently widened and pull tiles
# outside what was asked for.
cells=0
for (( e = mine; e < maxe; e += STEP )); do
  for (( n = minn; n < maxn; n += STEP )); do
    e2=$(( e + STEP )); (( e2 > maxe )) && e2=$maxe
    n2=$(( n + STEP )); (( n2 > maxn )) && n2=$maxn
    ewkt="SRID=25832;MULTIPOLYGON((($((e*1000)) $((n*1000)), $((e2*1000)) $((n*1000)), $((e2*1000)) $((n2*1000)), $((e*1000)) $((n2*1000)), $((e*1000)) $((n*1000)))))"
    # <file name=…> carries the tile name; the <url> is a GetMap query string, so aria2 has
    # to be told the output name explicitly or every tile lands as "parzellarkarte".
    curl -fsS --max-time 180 -X POST --data-binary "$ewkt" "$POLY2META" \
      | python3 -c '
import sys, xml.etree.ElementTree as ET
ns = {"m": "urn:ietf:params:xml:ns:metalink"}
try:
    root = ET.fromstring(sys.stdin.read())
except ET.ParseError:
    sys.exit(0)          # service returned a plain-text refusal, not a metalink
for f in root.findall(".//m:file", ns):
    url = f.find("m:url", ns)
    if url is not None and url.text:
        print(url.text.strip())
        print("  out=" + f.get("name"))
' >>"$input.tmp" || true
    cells=$(( cells + 1 ))
    printf "\r    swept %d polygons, %d tiles" "$cells" "$(( $(wc -l <"$input.tmp") / 2 ))" >&2
  done
done
echo >&2

# A tile on a cell seam can be returned twice — dedupe on the url/out pair.
python3 - "$input.tmp" "$input" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
seen, out = set(), []
lines = open(src).read().splitlines()
for i in range(0, len(lines) - 1, 2):
    url, name = lines[i], lines[i + 1]
    if name in seen:
        continue
    seen.add(name)
    out.append(url); out.append(name)
open(dst, "w").write("\n".join(out) + ("\n" if out else ""))
print(f"    tiles: {len(seen)}  |  ~{len(seen) * 22 / 1024:.1f} GB at ~22 MB/tile")
print("    no sizes or checksums published — resumable, not hash-verified")
print("    tiles are rendered on demand: expect ~20 s of server time each")
PY
rm -f "$input.tmp"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "    DRY_RUN=1 — skipping download."
  exit 0
fi

[[ -s "$input" ]] || { echo "    nothing to download — the BBOX planned 0 tiles." >&2; exit 1; }

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

cat <<EOF

Attribution required (CC BY 4.0) — include in any product/publication:
  Datenquelle: Bayerische Vermessungsverwaltung – www.geodaten.bayern.de
EOF
