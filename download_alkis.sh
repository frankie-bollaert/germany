#!/usr/bin/env bash
#
# download_alkis.sh — bulk-download the German states' ALKIS (cadastre) open data.
#
# ALKIS = Amtliches Liegenschaftskatasterinformationssystem: parcels (Flurstücke), building
# footprints (Gebäude), actual land use (Tatsächliche Nutzung), addresses. Every state runs
# its own cadastre, so every state publishes it differently — or not at all. What is open
# everywhere is the *ohne Eigentümer* (oE) variant: owner names are never open data.
#
# Coverage as verified live (2026-07). "login" = a user account is required, so this script
# cannot fetch it; "anon" = plain HTTP, no credentials:
#
#   key  state                    ALKIS open data          access  engine
#   ---  -----------------------  -----------------------  ------  ---------------------------
#   bw   Baden-Württemberg        full oE, per Gemarkung    anon    MVT grid -> zip (NAS/Shape)
#   by   Bayern                   PARTIAL — no vector       anon    static zip / GPKG
#                                 Flurstücke; TN, Hausum-
#                                 ringe, Verwaltung only
#   be   Berlin                   full oE                   anon    WFS 2.0 (no file dumps)
#   bb   Brandenburg              full oE, per Landkreis    anon    directory -> zip (NAS/Shape)
#   hb   Bremen                   full oE (Flurstücke)      anon    WFS 1.1 (no file dumps)
#   hh   Hamburg                  "ausgewählte Daten"       anon    CKAN -> quarterly GML zip
#   he   Hessen                   full oE                   anon*   OGC API Features
#                                                                   (*file packages on
#                                                                    gds.hessen.de need an
#                                                                    account — API does not)
#   mv   Mecklenburg-Vorpommern   full oE, per Gemeinde     anon    ATOM -> zip (NAS)
#   ni   Niedersachsen            full oE                   anon    WFS 2.0 NAS (no file dumps)
#   nw   Nordrhein-Westfalen      full oE, per Kreis        anon    listing -> zip (NAS/GPKG)
#   rp   Rheinland-Pfalz          PARTIAL — raster cadastral anon   Metalink -> GeoTIFF / zip
#                                 map + Hausumringe only
#   sl   Saarland                 full oE, per Landkreis    anon    WebDAV -> zip (NAS/Shape)
#   sn   Sachsen                  full oE, statewide        anon    single zip (NAS)
#   st   Sachsen-Anhalt           full oE (vereinfacht)     anon    WFS 2.0 (no file dumps)
#   sh   Schleswig-Holstein       full oE, statewide        anon    single GeoJSON
#   th   Thüringen                full oE, per Flur         anon    ATOM -> zip (Shape/NAS)
#
# No state requires a login for the data this script fetches. Two states are incomplete at
# the source (by, rp) — see README.md.
#
# Usage : ./download_alkis.sh <state> [dataset] [output_dir]
#   ./download_alkis.sh nw                  # NRW, NAS, -> ./alkis/nw
#   ./download_alkis.sh nw gpkg             # NRW, simplified GeoPackage
#   ./download_alkis.sh bw shape /mnt/big   # -> /mnt/big/bw
#   ./download_alkis.sh --list              # every state + its datasets
#
# Env vars (override defaults):
#   JOBS=8   CONN=4   DRY_RUN=1
#   OUTDIR=<path>  write the files straight here, instead of <output_dir>/<state>.
#                  download_all.sh uses this to lay every state out as <root>/<state>-<dataset>.
#   PAGE=10000       features per request for the WFS/OGC-API states (be, hb, he, ni)
#   MAX_PAGES=0      stop after N pages (0 = all); handy for sampling a big WFS
#
set -euo pipefail

JOBS="${JOBS:-8}"          # concurrent files
CONN="${CONN:-4}"          # connections per file
DRY_RUN="${DRY_RUN:-0}"    # 1 = print the plan, download nothing
PAGE="${PAGE:-10000}"      # WFS/OGC-API page size
MAX_PAGES="${MAX_PAGES:-0}"

# Set by each plan_* function.
ENGINE=""        # aria2 | wfs2 | wfs1 | ogcapi
SRC_URL=""       # service endpoint (wfs*/ogcapi)
SRC_TYPE=""      # typename / collection id
ATTRIB=""        # attribution string printed at the end

usage() {
  cat >&2 <<'EOF'
Usage: ./download_alkis.sh <state> [dataset] [output_dir]

  state    bw by be bb hb hh he mv ni nw rp sl sn st sh th
  dataset  state-specific; run ./download_alkis.sh --list

Env: JOBS=8 CONN=4 DRY_RUN=1 PAGE=10000 MAX_PAGES=0
EOF
  exit 2
}

list_states() {
  cat <<'EOF'
state  datasets (default first)      what you get
-----  ----------------------------  --------------------------------------------------
bw     nas, shape                    full ALKIS oE, one zip per Gemarkung (~3.4k)
by     tn, hausumringe, verwaltung   NO vector Flurstücke — land use / footprints only
be     flurstuecke, gebaeude         WFS 2.0 dump, paged GML
bb     nas, shape                    full ALKIS oE, one zip per Landkreis (18)
hb     flurstuecke                   WFS 1.1 dump, single GML
hh     gml                           newest quarterly "ausgewählte Daten" zip
he     flurstuecke, zoning           OGC API Features dump, paged GeoJSON
mv     nas                           full ALKIS oE, one zip per Gemeinde (~750)
ni     flurstueck, gebaeude          WFS 2.0 NAS dump, paged GML
nw     nas, gpkg                     full ALKIS oE, one zip per Kreis (53)
rp     lika, hu                      raster cadastral map / Hausumringe (no vector ALKIS)
sl     nas, shape                    full ALKIS oE, one zip per Landkreis (7)
sn     nas                           full ALKIS oE, one statewide zip
sh     geojson                       statewide Massendownload GeoJSON (~243 MB)
th     shape, nas                    full ALKIS oE, one zip per Flur (~9k)
st     flurstueck, gebaeude,         ALKIS-vereinfacht WFS, statewide (~2.7 M parcels)
       nutzung
EOF
  exit 0
}

[[ "${1:-}" == "--list" ]] && list_states
[[ $# -ge 1 ]] || usage

STATE="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
DATASET="${2:-}"
OUTROOT="${3:-./alkis}"
DIR="${OUTDIR:-$OUTROOT/$STATE}"
LIST="$DIR/.files.aria2"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: $1 not found. Install it:  brew install $1  (macOS)  |  apt install $1 (Debian/Ubuntu)" >&2
    exit 1
  }
}
need python3
need curl

# ---------------------------------------------------------------------------- helpers

# Emit one aria2c input record: URL + the filename to save it as.
emit() { printf '%s\n  out=%s\n' "$1" "$2" >>"$LIST"; }

# Decode a Mapbox vector tile pyramid into {fileName: downloadURL} for one product/type.
# BW draws every download grid (LiDAR 2x2 km, ALKIS Gemarkungen) this way, so the same
# reader serves both — see download_bw_lidar.sh for the LiDAR use of it.
mvt_products() {
  local grid="$1" zoom="$2" product="$3" ptype="$4" base="$5" cache="$DIR/.grid"
  rm -rf "$cache"; mkdir -p "$cache"
  curl -fsS "$grid/metadata.json" -o "$cache/metadata.json"

  local tiles t f
  tiles="$(python3 - "$cache/metadata.json" "$zoom" <<'PY'
import json, math, sys
meta = json.load(open(sys.argv[1], encoding="utf-8"))
z = int(sys.argv[2])
b = meta["bounds"]
w, s, e, n = json.loads(b) if isinstance(b, str) else b
def xy(lon, lat):
    m = 2 ** z
    lat = max(min(lat, 85.05), -85.05)
    r = math.radians(lat)
    return (int((lon + 180) / 360 * m),
            int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * m))
x0, y0 = xy(w, n); x1, y1 = xy(e, s)
print(" ".join(f"{x}/{y}" for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)))
PY
)"
  # A corner tile of the bounds box can legitimately be empty -> tolerate 404s.
  for t in $tiles; do
    f="$cache/${t//\//_}.pbf"
    curl -fsS "$grid/$zoom/$t.pbf" -o "$f" || rm -f "$f"
  done

  python3 - "$cache" "$product" "$ptype" "$base" "$LIST" <<'PY'
import glob, gzip, json, os, struct, sys

cache, product, ptype, base, out_path = sys.argv[1:6]

# --- minimal Mapbox Vector Tile reader (stdlib only; feature properties are all we need) ---
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

files = {}
for path in sorted(glob.glob(os.path.join(cache, "*.pbf"))):
    raw = open(path, "rb").read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    for props in properties(raw):
        meta = json.loads(props["metadata"])
        for p in meta.get("products", []):
            if p["name"] != product:
                continue
            for t in p["types"]:
                if t["type"] == ptype:
                    files[t["fileName"]] = t["downloadURL"]

if not files:
    sys.exit(f"ERROR: no {product}/{ptype} entries in the download grid")

with open(out_path, "a", encoding="utf-8") as fh:
    for fn, url in sorted(files.items()):
        fh.write(f"{url if url.startswith('http') else base + url}\n  out={fn}\n")
PY
}

# Pull every href matching a regex out of a page (directory listing, ATOM feed, KML, ...).
# The page is spooled to a file first: a heredoc-supplied python program owns stdin, so a
# curl|python3 pipe would silently hand the parser an empty document.
hrefs_matching() {
  local tmp="$DIR/.fetch.$$"
  curl -fsSL "$1" -o "$tmp"
  python3 - "$2" "${3:-}" "$tmp" <<'PY'
import html, re, sys
from urllib.parse import urljoin
pat, basestr, path = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8", errors="replace").read()
seen = []
for m in re.finditer(r'href="([^"]+)"', text):
    u = html.unescape(m.group(1))
    if re.search(pat, u):
        full = urljoin(basestr, u) if basestr else u
        if full not in seen:
            seen.append(full)
print("\n".join(seen))
PY
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------- per-state plans

plan_bw() {
  DATASET="${DATASET:-nas}"
  local ptype
  case "$DATASET" in
    nas)   ptype="NAS" ;;
    shape) ptype="Shape" ;;
    *) echo "ERROR: bw datasets are: nas, shape" >&2; exit 2 ;;
  esac
  ENGINE=aria2
  ATTRIB="Datenquelle: LGL, www.lgl-bw.de  ·  dl-de/by-2-0"
  echo "    grid: https://opengeodata.lgl-bw.de/tiles/vts/Gemarkungen (one zip per Gemarkung)"
  mvt_products "https://opengeodata.lgl-bw.de/tiles/vts/Gemarkungen" 7 ALKIS "$ptype" "https://opengeodata.lgl-bw.de"
}

plan_by() {
  DATASET="${DATASET:-tn}"
  ENGINE=aria2
  ATTRIB="© Bayerische Vermessungsverwaltung, CC BY 4.0"
  echo "    NOTE: Bayern publishes NO open vector Flurstücke. The ALKIS-Parzellarkarte is"
  echo "          raster only (WMS/WMTS + GeoTIFF); full vector ALKIS is sold via GeodatenOnline."
  case "$DATASET" in
    tn)  # Tatsächliche Nutzung, statewide GeoPackage (~5 GB)
      emit "https://geodaten.bayern.de/odd/m/3/daten/tn/Nutzung_kreis.gpkg" "Nutzung_kreis.gpkg" ;;
    hausumringe)  # building footprints, one Shape zip per Regierungsbezirk
      local u
      while read -r u; do
        [[ -n "$u" ]] && emit "$u" "${u##*/}"
      done < <(hrefs_matching "https://geodaten.bayern.de/odd/m/3/daten/hausumringe/bezirk/kml/HU_regierungsbezirk.kml?service=kml" '_Hausumringe\.zip$')
      # The KML carries the links inside <href> too; fall back to a raw scrape if empty.
      [[ -s "$LIST" ]] || curl -fsSL "https://geodaten.bayern.de/odd/m/3/daten/hausumringe/bezirk/kml/HU_regierungsbezirk.kml?service=kml" \
        | grep -oE 'https?://[^<"]*_Hausumringe\.zip' | sort -u \
        | while read -r u; do emit "$u" "${u##*/}"; done ;;
    verwaltung)
      emit "https://geodaten.bayern.de/odd/m/4/verwaltung/alkis-verwaltung.zip"     "alkis-verwaltung.zip"
      emit "https://geodaten.bayern.de/odd/m/4/verwaltung/alkis-katasterbezirk.zip" "alkis-katasterbezirk.zip" ;;
    *) echo "ERROR: by datasets are: tn, hausumringe, verwaltung" >&2; exit 2 ;;
  esac
}

plan_be() {
  DATASET="${DATASET:-flurstuecke}"
  ENGINE=wfs2
  ATTRIB="Geoportal Berlin / ALKIS Berlin, dl-de/zero-2-0"
  case "$DATASET" in
    flurstuecke) SRC_URL="https://gdi.berlin.de/services/wfs/alkis_flurstuecke"; SRC_TYPE="alkis_flurstuecke:flurstuecke" ;;
    gebaeude)    SRC_URL="https://gdi.berlin.de/services/wfs/alkis_gebaeude";    SRC_TYPE="alkis_gebaeude:gebaeude" ;;
    *) echo "ERROR: be datasets are: flurstuecke, gebaeude" >&2; exit 2 ;;
  esac
  echo "    NOTE: Berlin publishes ALKIS as services only — this dumps the WFS page by page."
}

plan_bb() {
  DATASET="${DATASET:-nas}"
  local sub
  case "$DATASET" in
    nas)   sub="nas" ;;
    shape) sub="shape" ;;
    *) echo "ERROR: bb datasets are: nas, shape" >&2; exit 2 ;;
  esac
  ENGINE=aria2
  ATTRIB="© GeoBasis-DE/LGB, dl-de/by-2-0"
  local base="https://data.geobasis-bb.de/geobasis/daten/alkis/Vektordaten/$sub/" u
  echo "    listing: $base"
  while read -r u; do
    [[ -n "$u" ]] && emit "$u" "${u##*/}"
  done < <(hrefs_matching "$base" '\.zip$' "$base")
}

plan_hb() {
  DATASET="${DATASET:-flurstuecke}"
  [[ "$DATASET" == "flurstuecke" ]] || { echo "ERROR: hb dataset is: flurstuecke" >&2; exit 2; }
  ENGINE=wfs1
  SRC_URL="https://geodienste.bremen.de/wfs_hduk2958loah3976niun"
  SRC_TYPE="app:flurstuecke"
  ATTRIB="Landesamt GeoInformation Bremen, CC BY 4.0"
  echo "    NOTE: Bremen publishes ALKIS as a WFS only — this dumps it in one GetFeature."
}

plan_hh() {
  DATASET="${DATASET:-gml}"
  [[ "$DATASET" == "gml" ]] || { echo "ERROR: hh dataset is: gml" >&2; exit 2; }
  ENGINE=aria2
  ATTRIB="Freie und Hansestadt Hamburg, LGV, dl-de/by-2-0"
  # The transparency portal keeps every quarterly snapshot; take the newest by filename date.
  local newest
  newest="$(curl -fsSL 'https://suche.transparenz.hamburg.de/api/3/action/package_search?q=title:ALKIS%20Liegenschaftskarte&rows=20' \
    | python3 -c "
import json, re, sys
best = None
for p in json.load(sys.stdin)['result']['results']:
    for r in p.get('resources', []):
        u = r.get('url') or ''
        m = re.search(r'(\d{4}-\d{2}-\d{2})[^/]*\.zip$', u)
        if m and (best is None or m.group(1) > best[0]):
            best = (m.group(1), u)
print(best[1] if best else '')
")"
  [[ -n "$newest" ]] || { echo "ERROR: no ALKIS zip found in the Hamburg transparency portal" >&2; exit 1; }
  echo "    newest snapshot: ${newest##*/}"
  emit "$newest" "${newest##*/}"
}

plan_he() {
  DATASET="${DATASET:-flurstuecke}"
  ENGINE=ogcapi
  SRC_URL="https://www.geoportal.hessen.de/spatial-objects/710"
  ATTRIB="© Hessische Verwaltung für Bodenmanagement und Geoinformation, dl-de/zero-2-0"
  case "$DATASET" in
    flurstuecke) SRC_TYPE="cp:CadastralParcel" ;;
    zoning)      SRC_TYPE="cp:CadastralZoning" ;;
    *) echo "ERROR: he datasets are: flurstuecke, zoning" >&2; exit 2 ;;
  esac
  echo "    NOTE: the gds.hessen.de Downloadcenter needs a free account; this OGC API does not."
}

plan_mv() {
  DATASET="${DATASET:-nas}"
  [[ "$DATASET" == "nas" ]] || { echo "ERROR: mv dataset is: nas" >&2; exit 2; }
  ENGINE=aria2
  ATTRIB="© GeoBasis-DE/M-V, CC BY 4.0"
  local feed="https://www.geodaten-mv.de/dienste/alkis_nas_atom" ds u
  ds="$(hrefs_matching "$feed" 'type=dataset' | head -1)"
  [[ -n "$ds" ]] || { echo "ERROR: no dataset feed in $feed" >&2; exit 1; }
  echo "    feed: $ds"
  while read -r u; do
    [[ -n "$u" ]] && emit "$u" "$(python3 -c "
import sys, urllib.parse as p
print(p.parse_qs(p.urlparse(sys.argv[1]).query).get('file', ['alkis.zip'])[0])" "$u")"
  done < <(hrefs_matching "$ds" 'alkis_nas_download\?')
}

plan_ni() {
  DATASET="${DATASET:-flurstueck}"
  ENGINE=wfs2
  SRC_URL="https://opendata.lgln.niedersachsen.de/doorman/noauth/alkis_wfs_nas"
  ATTRIB="© LGLN, dl-de/by-2-0"
  case "$DATASET" in
    flurstueck) SRC_TYPE="adv:AX_Flurstueck" ;;
    gebaeude)   SRC_TYPE="adv:AX_Gebaeude" ;;
    *) echo "ERROR: ni datasets are: flurstueck, gebaeude" >&2; exit 2 ;;
  esac
  echo "    NOTE: Niedersachsen publishes ALKIS as a NAS WFS — this dumps it page by page."
}

plan_nw() {
  DATASET="${DATASET:-nas}"
  local sub
  case "$DATASET" in
    nas)  sub="gru_xml" ;;
    gpkg) sub="gru_vereinfacht_gpkg" ;;
    *) echo "ERROR: nw datasets are: nas, gpkg" >&2; exit 2 ;;
  esac
  ENGINE=aria2
  ATTRIB="© GeoBasis NRW, dl-de/zero-2-0"
  local base="https://www.opengeodata.nrw.de/produkte/geobasis/lk/akt/$sub/"
  echo "    listing: $base"
  # The portal serves a machine-readable XML index per product folder.
  curl -fsSL "$base" -o "$DIR/.index.xml"
  python3 - "$base" "$LIST" "$DIR/.index.xml" <<'PY'
import re, sys
base, out, path = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8", errors="replace").read()
names = re.findall(r'<file\s+name="([^"]+)"', text)
if not names:
    sys.exit(f"ERROR: no <file> entries at {base}")
with open(out, "a", encoding="utf-8") as fh:
    for n in sorted(names):
        fh.write(f"{base}{n}\n  out={n}\n")
PY
}

plan_rp() {
  DATASET="${DATASET:-lika}"
  ENGINE=aria2
  ATTRIB="©GeoBasis-DE / LVermGeoRP $(date +%Y), dl-de/by-2-0, www.lvermgeo.rlp.de"
  echo "    NOTE: RLP publishes no open vector ALKIS. 'lika' is the rasterised cadastral map;"
  echo "          parcel geometry is query-only via the Flurstückssuche WFS."
  local m4
  case "$DATASET" in
    lika) m4="https://geobasis-rlp.de/data/lika/current/meta4/lika_tif_07.meta4" ;;
    hu)   m4="https://geobasis-rlp.de/data/hu/current/meta4/hu_zip_07.meta4" ;;
    *) echo "ERROR: rp datasets are: lika, hu" >&2; exit 2 ;;
  esac
  # Metalink-4 carries size + SHA-256 per file; hand it to aria2c directly.
  ENGINE=metalink
  SRC_URL="$m4"
  echo "    manifest: $m4"
}

plan_sl() {
  DATASET="${DATASET:-nas}"
  local sub
  case "$DATASET" in
    nas)   sub="OD_ALKIS_nas_LK" ;;
    shape) sub="OD_ALKIS_shp_LK" ;;
    *) echo "ERROR: sl datasets are: nas, shape" >&2; exit 2 ;;
  esac
  ENGINE=aria2
  ATTRIB="© GeoBasis DE/LVGL-SL $(date +%Y), dl-de/by-2-0"
  # LVGL serves its statewide open data from a public (password-less) Nextcloud share.
  local dav="https://www.shop.lvgl.saarland.de/cloud/public.php/dav/files/NK8ndP55qAqGEZD"
  echo "    share: $dav/$sub"
  curl -fsS -X PROPFIND -H "Depth: 1" "$dav/$sub/" -o "$DIR/.propfind.xml"
  python3 - "$dav" "$sub" "$LIST" "$DIR/.propfind.xml" <<'PY'
import re, sys
from urllib.parse import unquote
dav, sub, out, path = sys.argv[1:5]
text = open(path, encoding="utf-8", errors="replace").read()
hrefs = [h for h in re.findall(r'<d:href>([^<]+)</d:href>', text) if h.lower().endswith('.zip')]
if not hrefs:
    sys.exit(f"ERROR: no zips in the {sub} share")
host = dav.split('/cloud/')[0]
with open(out, "a", encoding="utf-8") as fh:
    for h in sorted(hrefs):
        fh.write(f"{host}{h}\n  out={unquote(h.rsplit('/', 1)[-1])}\n")
PY
}

plan_sn() {
  DATASET="${DATASET:-nas}"
  [[ "$DATASET" == "nas" ]] || { echo "ERROR: sn dataset is: nas" >&2; exit 2; }
  ENGINE=aria2
  ATTRIB="© Staatsbetrieb Geobasisinformation und Vermessung Sachsen (GeoSN), dl-de/by-2-0"
  echo "    statewide NAS package (without Punktinformationen)"
  emit "https://geocloud.landesvermessung.sachsen.de/public.php/dav/files/kSCYk4FYbdj558d/alkis_sn.zip" "alkis_sn.zip"
}

plan_st() {
  DATASET="${DATASET:-flurstueck}"
  ENGINE=wfs2
  # The service is the "vereinfacht" ALKIS schema (ALKIS-vereinfacht 2.0), not full NAS —
  # geometry plus the core cadastral keys, no Punktinformationen and no Eigentümer.
  SRC_URL="https://www.geodatenportal.sachsen-anhalt.de/wss/service/ST_LVermGeo_ALKIS_WFS_OpenData/guest"
  ATTRIB="© GeoBasis-DE / LVermGeo LSA, dl-de/by-2-0"
  case "$DATASET" in
    flurstueck) SRC_TYPE="ave:Flurstueck" ;;
    gebaeude)   SRC_TYPE="ave:GebaeudeBauwerk" ;;
    nutzung)    SRC_TYPE="ave:Nutzung" ;;
    *) echo "ERROR: st datasets are: flurstueck, gebaeude, nutzung" >&2; exit 2 ;;
  esac
  echo "    NOTE: Sachsen-Anhalt publishes ALKIS as a service only — this dumps the WFS page by page."
}

plan_sh() {
  DATASET="${DATASET:-geojson}"
  [[ "$DATASET" == "geojson" ]] || { echo "ERROR: sh dataset is: geojson" >&2; exit 2; }
  ENGINE=aria2
  ATTRIB="© GeoBasis-DE/LVermGeo SH, CC BY 4.0"
  echo "    statewide Massendownload (~243 MB GeoJSON)"
  emit "https://geodaten.schleswig-holstein.de/gaialight-sh/_apps/dladownload/single.php?file=ALKIS_SH_Massendownload.geojson&id=4" \
       "ALKIS_SH_Massendownload.geojson"
}

plan_th() {
  DATASET="${DATASET:-shape}"
  local want
  case "$DATASET" in
    shape) want='/ALKIS/Shape/' ;;
    nas)   want='/ALKIS/NAS/' ;;
    *) echo "ERROR: th datasets are: shape, nas" >&2; exit 2 ;;
  esac
  ENGINE=aria2
  ATTRIB="© GDI-Th, Freistaat Thüringen, dl-de/by-2-0"
  local feed="https://geoportal.geoportal-th.de/dienste/atom_th_alkis" ds u
  ds="$(hrefs_matching "$feed" 'type=dataset' | head -1)"
  [[ -n "$ds" ]] || { echo "ERROR: no dataset feed in $feed" >&2; exit 1; }
  echo "    feed: $ds"
  while read -r u; do
    [[ -n "$u" ]] && emit "$u" "${u##*/}"
  done < <(hrefs_matching "$ds" "${want}.*\.zip\$")
}

# ---------------------------------------------------------------------------- engines

run_aria2() {
  need aria2c
  local n
  n="$(grep -c '^  out=' "$LIST" || true)"
  [[ "$n" -gt 0 ]] || { echo "ERROR: nothing to download" >&2; exit 1; }
  echo "    files: $n"

  if [[ "$DRY_RUN" == "1" ]]; then
    # No sizes are published for most of these — sample a few with HEAD and extrapolate.
    python3 - "$LIST" <<'PY'
import subprocess, sys
urls = [l.strip() for l in open(sys.argv[1], encoding="utf-8") if not l.startswith("  ")]
sample = urls[:: max(1, len(urls) // 5)][:5]
sizes = []
for u in sample:
    out = subprocess.run(["curl", "-fsSIL", "-m", "30", u], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.lower().startswith("content-length:"):
            sizes.append(int(line.split(":")[1]))
if sizes:
    avg = sum(sizes) / len(sizes)
    print(f"    est. total: {avg * len(urls) / 1e9:.2f} GB  ({len(sizes)} sampled, avg {avg/1e6:.1f} MB)")
else:
    print("    est. total: unknown (no Content-Length on the sampled URLs)")
PY
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi

  aria2c \
    --input-file="$LIST" \
    --dir="$DIR" \
    --max-concurrent-downloads="$JOBS" \
    --max-connection-per-server="$CONN" \
    --split="$CONN" \
    --continue=true \
    --auto-file-renaming=false \
    --conditional-get=true \
    --console-log-level=warn \
    --summary-interval=30 \
    --save-session="$DIR/.aria2.session" \
    --log="$DIR/.aria2.log"
}

run_metalink() {
  need aria2c
  local m4="$DIR/.manifest.meta4"
  curl -fsS "$SRC_URL" -o "$m4"
  python3 - "$m4" <<'PY'
import re, sys
x = open(sys.argv[1], encoding="utf-8", errors="replace").read()
n = len(re.findall(r'<file ', x))
tot = sum(int(s) for s in re.findall(r'<size>(\d+)</size>', x))
print(f"    files: {n}  |  total: {tot/1e9:.2f} GB  |  manifest carries SHA-256 per file")
PY
  if [[ "$DRY_RUN" == "1" ]]; then echo "    DRY_RUN=1 — skipping download."; return 0; fi
  aria2c \
    --metalink-file="$m4" \
    --dir="$DIR" \
    --max-concurrent-downloads="$JOBS" \
    --max-connection-per-server="$CONN" \
    --split="$CONN" \
    --continue=true \
    --check-integrity=true \
    --auto-file-renaming=false \
    --conditional-get=true \
    --console-log-level=warn \
    --summary-interval=30 \
    --save-session="$DIR/.aria2.session" \
    --log="$DIR/.aria2.log"
}

# WFS 2.0: page with count/startIndex, one GML file per page. Stops when a page comes back
# with fewer features than asked for (or empty).
run_wfs2() {
  echo "    service: $SRC_URL"
  echo "    typename: $SRC_TYPE  (page size $PAGE)"
  if [[ "$DRY_RUN" == "1" ]]; then
    local hits
    hits="$(curl -fsSL "$SRC_URL?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=$SRC_TYPE&RESULTTYPE=hits" \
      | grep -oE 'numberMatched="[^"]*"' | head -1 | sed 's/.*="//;s/"//')"
    echo "    features: ${hits:-unknown}"
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi
  local i=0 start=0 out got
  while :; do
    i=$((i + 1))
    out="$(printf '%s/part-%05d.gml' "$DIR" "$i")"
    curl -fsSL -o "$out" \
      "$SRC_URL?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&TYPENAMES=$SRC_TYPE&COUNT=$PAGE&STARTINDEX=$start"
    got="$(grep -oE 'numberReturned="[^"]*"' "$out" | head -1 | sed 's/.*="//;s/"//')"
    got="${got:-0}"
    echo "    page $i: $got features -> ${out##*/}"
    if [[ "$got" -lt "$PAGE" ]]; then
      [[ "$got" == "0" ]] && rm -f "$out"
      break
    fi
    start=$((start + PAGE))
    if [[ "$MAX_PAGES" -gt 0 && "$i" -ge "$MAX_PAGES" ]]; then
      echo "    stopped at MAX_PAGES=$MAX_PAGES"
      break
    fi
  done
}

# WFS 1.1 has no standard paging — Bremen is small enough to take in one request.
run_wfs1() {
  echo "    service: $SRC_URL"
  echo "    typename: $SRC_TYPE (single GetFeature)"
  if [[ "$DRY_RUN" == "1" ]]; then echo "    DRY_RUN=1 — skipping download."; return 0; fi
  local out="$DIR/${SRC_TYPE##*:}.gml"
  curl -fsSL -o "$out" \
    "$SRC_URL?SERVICE=WFS&VERSION=1.1.0&REQUEST=GetFeature&TYPENAME=$SRC_TYPE&SRSNAME=EPSG:25832"
  echo "    -> ${out##*/} ($(wc -c <"$out" | tr -d ' ') bytes)"
}

# OGC API Features: follow rel="next" until it stops, one GeoJSON file per page.
run_ogcapi() {
  echo "    service: $SRC_URL"
  echo "    collection: $SRC_TYPE  (page size $PAGE)"
  if [[ "$DRY_RUN" == "1" ]]; then
    curl -fsSL "$SRC_URL/collections/$SRC_TYPE/items?limit=1&f=json" \
      | python3 -c "import json,sys;d=json.load(sys.stdin);print('    features:', d.get('numberMatched','unknown'))" || true
    echo "    DRY_RUN=1 — skipping download."
    return 0
  fi
  local url="$SRC_URL/collections/$SRC_TYPE/items?limit=$PAGE&f=json" i=0 out
  while [[ -n "$url" ]]; do
    i=$((i + 1))
    out="$(printf '%s/part-%05d.geojson' "$DIR" "$i")"
    curl -fsSL -o "$out" "$url"
    url="$(python3 - "$out" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print(""); raise SystemExit
n = len(d.get("features", []))
nxt = next((l["href"] for l in d.get("links", []) if l.get("rel") == "next"), "")
print(nxt if n else "")
PY
)"
    echo "    page $i -> ${out##*/}"
    if [[ "$MAX_PAGES" -gt 0 && "$i" -ge "$MAX_PAGES" ]]; then
      echo "    stopped at MAX_PAGES=$MAX_PAGES"
      break
    fi
  done
}

# ---------------------------------------------------------------------------- main

case "$STATE" in
  bw|by|be|bb|hb|hh|he|mv|ni|nw|rp|sl|sn|st|sh|th) : ;;
  *) echo "ERROR: unknown state '$STATE'" >&2; usage ;;
esac

echo "==> $STATE  ALKIS${DATASET:+ ($DATASET)}"
mkdir -p "$DIR"
: >"$LIST"

"plan_$STATE"

case "$ENGINE" in
  aria2)    run_aria2 ;;
  metalink) run_metalink ;;
  wfs2)     run_wfs2 ;;
  wfs1)     run_wfs1 ;;
  ogcapi)   run_ogcapi ;;
  *) echo "ERROR: no engine set for $STATE" >&2; exit 1 ;;
esac

[[ "$DRY_RUN" == "1" ]] || echo "    done -> $DIR"

cat <<EOF

Attribution required — include in any product or publication:
  $ATTRIB

Owner names (Eigentümerangaben) are never part of ALKIS open data.
EOF
