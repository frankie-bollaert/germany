#!/usr/bin/env bash
#
# download_all.sh — drive every per-state downloader in this repo from one command.
#
# The individual scripts each take one state and one dataset. This one walks the whole
# matrix — 29 ALKIS combinations across 16 states, 20 LiDAR combinations across 12 — and
# lays the result out under a single predictable tree:
#
#     <root>/alkis/<state>-<dataset>/     e.g. ./alkis/nw-nas, ./alkis/bw-shape
#     <root>/lidar/<state>-<dataset>/     e.g. ./lidar/nw-dgm1, ./lidar/rp-las
#
# State-major grouping, one flat directory per product. That layout matters for more than
# tidiness: the WFS/OGC-API states page their output into part-00001.gml regardless of which
# dataset was asked for, so be/he/ni/st would silently overwrite themselves if two of their
# datasets shared a directory. The per-dataset leaf makes that impossible.
#
# The sub-scripts normally append their own subdirectory (<out>/<state> for ALKIS,
# <out>/<dataset> for LiDAR). This script sets OUTDIR= instead, which tells them to write
# straight into the path given — that is the only change it makes to their behaviour.
#
# States are keyed by the repo-wide two-letter ID (nw, rp), not by the legacy filenames
# download_nrw_lidar.sh / download_rlp_lidar.sh — see README.md "Naming".
#
# Usage : ./download_all.sh [group] [root]
#   ./download_all.sh alkis            # 29 ALKIS combinations   -> ./alkis/<state>-<dataset>
#   ./download_all.sh cadastre         # only what holds parcels or building footprints
#   ./download_all.sh dgm1             # 10 terrain models       -> ./lidar/<state>-dgm1
#   ./download_all.sh las              # 10 point clouds         -> ./lidar/<state>-las
#   ./download_all.sh lidar            # dgm1 + las
#   ./download_all.sh all /mnt/big     # everything, somewhere with room
#   ./download_all.sh --list           # print the matrix and the size estimates, do nothing
#
# Env vars:
#   ONLY=nw,bw,rp    restrict to these states (repo IDs, comma-separated)
#   SKIP=rp,by       drop these states
#   WANT=parcels,buildings
#                    keep only products holding one of these: parcels, buildings, landuse,
#                    admin, zoning, raster, terrain, pointcloud. `cadastre` is shorthand for
#                    the ALKIS group with WANT=parcels,buildings. A product that bundles
#                    every object class survives any of these — see the matrix below.
#   FORMAT=simple    where a state offers both, take one: `nas` (full exchange format) or
#                    `simple` (vereinfacht/Shape/GPKG). Unset takes both, which downloads
#                    the same content twice for bw, bb, nw, sl and th.
#   DRY_RUN=1        passed through — every sub-script prints its plan and downloads nothing
#   JOBS=8 CONN=4    passed through
#   PAGE, MAX_PAGES  passed through to the ALKIS WFS/OGC-API states
#   KEEP_GOING=1     default; set to 0 to stop at the first failing combination
#
# A failure never aborts the run by default: the combination is logged to
# <root>/.download_all.failures and the walk continues. Re-running the same command resumes
# — aria2c picks up part-files, the paging engines refetch only what is missing.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_GOING="${KEEP_GOING:-1}"
DRY_RUN="${DRY_RUN:-0}"

# ---------------------------------------------------------------------------- the matrix
#
# family  state  dataset  size  content  format
#
# size    verified 2026-07; "?" = the source publishes no Content-Length, so it cannot be
#         estimated without downloading. ALKIS sizes are bytes on disk for the file-based
#         states and feature counts for the five service-only states (be, hb, he, ni, st),
#         which stream from a WFS or OGC API rather than shipping files.
#
# content what the product actually holds, for WANT=. Only nine of the sixteen ALKIS states
#         let you ask for parcels or buildings on their own — the rest ship every object
#         class in one package, marked "more", and can only be narrowed after download.
#         Verified by inspection, not inferred from the portal wording: the NRW GeoPackage
#         carries Flurstueck, GebauedeBauwerk, Nutzung, KatasterBezirk, VerwaltungsEinheit.
#
# format  nas = the full exchange format; simple = a vereinfacht/Shape/GPKG export of the
#         same content, smaller and easier to read but with attributes and history dropped
#         (see README "Full NAS vs. vereinfacht"). "-" = the state offers no choice.
#
MATRIX="$(cat <<'EOF'
alkis bw nas          22.7G       parcels,buildings,more  nas
alkis bw shape        20.4G       parcels,buildings,more  simple
alkis by tn            5.4G       landuse                 -
alkis by hausumringe   0.7G       buildings               -
alkis by verwaltung    0.1G       admin                   -
alkis be flurstuecke   403k_feat  parcels                 -
alkis be gebaeude      784k_feat  buildings               -
alkis bb nas           4.0G       parcels,buildings,more  nas
alkis bb shape         1.6G       parcels,buildings,more  simple
alkis hb flurstuecke   small      parcels                 -
alkis hh gml           0.5G       parcels,buildings,more  -
alkis he flurstuecke   5.0M_feat  parcels                 -
alkis he zoning         43k_feat  zoning                  -
alkis mv nas           1448_files parcels,buildings,more  -
alkis ni flurstueck    6.3M_feat  parcels                 -
alkis ni gebaeude      6.5M_feat  buildings               -
alkis nw nas          25.3G       parcels,buildings,more  nas
alkis nw gpkg          8.9G       parcels,buildings,more  simple
alkis rp lika         30.7G       raster                  -
alkis rp hu            1.6G       buildings               -
alkis sl nas           2.1G       parcels,buildings,more  nas
alkis sl shape         0.5G       parcels,buildings,more  simple
alkis sn nas           ?          parcels,buildings,more  -
alkis sh geojson       0.24G      parcels,buildings       -
alkis st flurstueck    2.7M_feat  parcels                 -
alkis st gebaeude      1.7M_feat  buildings               -
alkis st nutzung       2.3M_feat  landuse                 -
alkis th shape         1.2G       parcels,buildings,more  simple
alkis th nas           6.5G       parcels,buildings,more  nas
lidar bb dgm1           41G       terrain                 -
lidar bb las           1.4T       pointcloud              -
lidar be dgm1          0.2G       terrain                 -
lidar be las           ?          pointcloud              -
lidar bw dgm1          134G       terrain                 -
lidar by dgm1          217G       terrain                 -
lidar by las           ?T         pointcloud              -
lidar mv dgm1          ?          terrain                 -
lidar mv las           ?          pointcloud              -
lidar ni dgm1          ?          terrain                 -
lidar nw dgm1           79G       terrain                 -
lidar nw las           3.5T       pointcloud              -
lidar rp dgm1           33G       terrain                 -
lidar rp las           5.2T       pointcloud              -
lidar sl las           124G       pointcloud              -
lidar sn dgm1          ?          terrain                 -
lidar sn las           ?          pointcloud              -
lidar st las          20.4G       pointcloud              -
lidar th dgm1          127G       terrain                 -
lidar th las           1.5T       pointcloud              -
EOF
)"

# Warnings that only make sense once a combination has actually been selected.
note_for() {  # note_for <state> <dataset> <content>
  case "$1 $2" in
    "sh geojson")
      echo "ALKIS_SH_Massendownload.geojson is an INDEX, not the cadastre: one polygon per Flur,"
      echo "each carrying a LINK_DATA URL to that Flur's NAS .xml.gz. The parcels and buildings"
      echo "are behind those links — this fetches the index only. See README, Schleswig-Holstein."
      return ;;
    "st las")
      echo "Sachsen-Anhalt's OPEN point cloud is two sample areas — Gebiet Hakel (11 tiles) and"
      echo "Gemeinde Halle/Saale (51 tiles), ~0.1% of the state, NOT statewide coverage. The"
      echo "full 3D-Messdaten product is priced and on request. See README, Sachsen-Anhalt."
      return ;;
    "sl las")
      echo "Saarland's DGM1 and DOM1 are open too, in the same LVGL share, but only the point"
      echo "cloud is wired into a script, so a full run fetches no SL terrain. See README, Saarland."
      return ;;
    "th dgm1"|"th las")
      echo "Thüringen publishes three flight campaigns on the same grid; this takes the newest"
      echo "(2020-2025) unless VINTAGE= says otherwise. The dgm1/dom1 zips carry the same grid"
      echo "twice — GeoTIFF plus an ASCII .xyz ten times its size — and cannot be split."
      return ;;
  esac
  case "$3" in
    *,more)
      echo "bundled: the source ships every ALKIS object class in one package, so parcels and"
      echo "buildings cannot be requested on their own. Narrow it after download instead —"
      echo "e.g. ogr2ogr -f GPKG out.gpkg in.gpkg Flurstueck GebauedeBauwerk" ;;
  esac
}

# LiDAR is scripted for 12 states, and two of those publish no point cloud at all:
# Baden-Württemberg's 3DM product is flagged inactive (every URL 404s) and Niedersachsen's
# STAC catalogue exposes raster only. Those combinations are absent from the matrix above
# rather than left to fail at runtime.

# Repo ID -> LiDAR script filename. Two predate the naming rule and keep their old names.
lidar_script() {
  case "$1" in
    nw) echo "download_nrw_lidar.sh" ;;
    rp) echo "download_rlp_lidar.sh" ;;
    *)  echo "download_$1_lidar.sh" ;;
  esac
}

# ---------------------------------------------------------------------------- selection

in_csv() {  # in_csv <needle> <csv>   — empty csv never matches
  local n="$1" c="$2" x parts
  [[ -z "$c" ]] && return 1
  IFS=, read -r -a parts <<<"$c"
  for x in "${parts[@]}"; do [[ "$x" == "$n" ]] && return 0; done
  return 1
}

overlaps() {  # overlaps <csv-a> <csv-b> — true if they share any element
  local x parts
  IFS=, read -r -a parts <<<"$1"
  for x in "${parts[@]}"; do in_csv "$x" "$2" && return 0; done
  return 1
}

selected() {  # selected <family> <state> <dataset> <content> <format>
  local fam="$1" st="$2" ds="$3" content="$4" fmt="$5"
  case "$GROUP" in
    alkis|cadastre) [[ "$fam" == "alkis" ]] || return 1 ;;
    lidar) [[ "$fam" == "lidar" ]] || return 1 ;;
    dgm1)  [[ "$fam" == "lidar" && "$ds" == "dgm1" ]] || return 1 ;;
    las)   [[ "$fam" == "lidar" && "$ds" == "las"  ]] || return 1 ;;
    all)   : ;;
  esac
  in_csv "$st" "${SKIP:-}" && return 1
  [[ -n "${ONLY:-}" ]] && { in_csv "$st" "$ONLY" || return 1; }
  # Keep a product if it holds any of what was asked for. A bundle holds parcels and
  # buildings among other things, so it survives WANT=parcels — there is no finer choice.
  [[ -n "$WANT" ]] && { overlaps "$content" "$WANT" || return 1; }
  # "-" means the state offers no format choice, so it is never filtered out by FORMAT.
  [[ -n "${FORMAT:-}" && "$fmt" != "-" && "$fmt" != "$FORMAT" ]] && return 1
  return 0
}

usage() {
  sed -n '/^# Usage : /,/^set /p' "$0" | sed '$d;s/^# \{0,1\}//' >&2
  exit 2
}

# Arguments in any order, so that a stray --list can never be mistaken for the output root
# and start a multi-terabyte download into a directory named "--list".
GROUP=""
ROOT=""
LIST_ONLY=0
for a in "$@"; do
  case "$a" in
    --list) LIST_ONLY=1 ;;
    -*)     echo "ERROR: unknown option '$a'" >&2; usage ;;
    *)      if [[ -z "$GROUP" ]]; then GROUP="$a"; elif [[ -z "$ROOT" ]]; then ROOT="$a"
            else echo "ERROR: unexpected argument '$a'" >&2; usage; fi ;;
  esac
done
ROOT="${ROOT:-.}"
# --list with no group lists every family; it matches no case in selected(), so nothing is cut.
[[ "$LIST_ONLY" == 1 && -z "$GROUP" ]] && GROUP="--list"

case "$GROUP" in
  alkis|lidar|dgm1|las|all) : ;;
  cadastre) : ;;   # shorthand: ALKIS, restricted to what holds parcels or building footprints
  --list) : ;;
  *) usage ;;
esac

WANT="${WANT:-}"
[[ "$GROUP" == "cadastre" && -z "$WANT" ]] && WANT="parcels,buildings"

# ---------------------------------------------------------------------------- walk

PLAN=""
N=0
while read -r FAM ST DS SIZE CONTENT FMT; do
  [[ -n "$FAM" ]] || continue
  # --list matches no family case below, so it lists everything — but still honours the filters.
  selected "$FAM" "$ST" "$DS" "$CONTENT" "$FMT" || continue
  PLAN="$PLAN$FAM $ST $DS $SIZE $CONTENT $FMT"$'\n'
  N=$((N + 1))
done <<<"$MATRIX"

if [[ "$LIST_ONLY" == 1 || "$GROUP" == "--list" ]]; then
  printf '%-6s %-5s %-12s %-10s %-22s %-6s %s\n' family state dataset size content format destination
  printf '%-6s %-5s %-12s %-10s %-22s %-6s %s\n' ------ ----- ------------ ---------- ---------------------- ------ -----------
  while read -r FAM ST DS SIZE CONTENT FMT; do
    [[ -n "$FAM" ]] || continue
    printf '%-6s %-5s %-12s %-10s %-22s %-6s %s\n' \
      "$FAM" "$ST" "$DS" "${SIZE//_/ }" "$CONTENT" "$FMT" "$ROOT/$FAM/$ST-$DS"
  done <<<"$PLAN"
  # Total only what is actually measurable: "?" and feature counts are reported separately
  # rather than folded in as zero, which would understate the selection.
  echo "$PLAN" | awk '
    /^[a-z]/ {
      n++
      if ($4 ~ /G$/)      { gb += $4 + 0 }
      else if ($4 ~ /T$/) { gb += ($4 + 0) * 1024 }
      else                { unmeasured++ }
    }
    END {
      printf "\n%d product(s) selected", n
      if (gb)         printf ", ~%.1f GB of files", gb
      if (unmeasured) printf ", plus %d streamed or unmeasured source(s)", unmeasured
      printf "\n"
    }'
  cat <<'EOF'
Sizes were measured live in 2026-07. "?" means the source serves no Content-Length; feature
counts mark the ALKIS states that publish a service rather than files.

"parcels,buildings,more" is a bundle — every ALKIS object class in one package. It cannot be
narrowed at the source, only after download.
EOF
  exit 0
fi

[[ "$N" -gt 0 ]] || { echo "nothing selected (group=$GROUP ONLY=${ONLY:-} SKIP=${SKIP:-})" >&2; exit 1; }

mkdir -p "$ROOT"
FAILLOG="$ROOT/.download_all.failures"
: >"$FAILLOG"

echo "==> $GROUP: $N combination(s) -> $ROOT/{alkis,lidar}/<state>-<dataset>"
if [[ "$GROUP" == "las" || "$GROUP" == "all" || "$GROUP" == "lidar" ]] && [[ "$DRY_RUN" != "1" ]]; then
  echo "    the point clouds alone run to 12 TB+ — check your disk before this gets far in"
fi

OK=0
FAILED=0
i=0
while read -r FAM ST DS SIZE CONTENT FMT; do
  [[ -n "$FAM" ]] || continue
  i=$((i + 1))
  dest="$ROOT/$FAM/$ST-$DS"
  if [[ "$FAM" == "alkis" ]]; then
    script="download_alkis.sh"; set -- "$ST" "$DS"
  else
    script="$(lidar_script "$ST")"; set -- "$DS"
  fi

  echo
  echo "--- [$i/$N] $FAM $ST $DS  (~${SIZE//_/ }, $CONTENT)  -> $dest"
  note_for "$ST" "$DS" "$CONTENT" | sed 's/^/    NOTE: /' 
  if [[ ! -x "$HERE/$script" ]]; then
    echo "    MISSING: $HERE/$script" | tee -a "$FAILLOG"
    FAILED=$((FAILED + 1)); continue
  fi

  mkdir -p "$dest"
  if OUTDIR="$dest" DRY_RUN="$DRY_RUN" "$HERE/$script" "$@"; then
    OK=$((OK + 1))
  else
    rc=$?
    echo "$FAM $ST $DS (exit $rc)" >>"$FAILLOG"
    echo "    FAILED (exit $rc) — logged, continuing"
    FAILED=$((FAILED + 1))
    [[ "$KEEP_GOING" == "1" ]] || { echo "KEEP_GOING=0 — stopping." >&2; break; }
  fi
done <<<"$PLAN"

echo
echo "==> $OK ok, $FAILED failed, of $N"
if [[ "$FAILED" -gt 0 ]]; then
  echo "    failures listed in $FAILLOG:"
  sed 's/^/      /' "$FAILLOG"
  echo "    re-running the same command retries them; finished files are skipped or resumed."
  exit 1
fi
