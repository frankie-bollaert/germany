#!/usr/bin/env bash
#
# download_all.sh — drive every per-state downloader in this repo from one command.
#
# The individual scripts each take one state and one dataset. This one walks the whole
# matrix — 29 ALKIS combinations across 16 states, 16 LiDAR combinations across 9 — and
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
#   ./download_all.sh dgm1             # 9 terrain models        -> ./lidar/<state>-dgm1
#   ./download_all.sh las              # 7 point clouds          -> ./lidar/<state>-las
#   ./download_all.sh lidar            # dgm1 + las
#   ./download_all.sh all /mnt/big     # everything, somewhere with room
#   ./download_all.sh --list           # print the matrix and the size estimates, do nothing
#
# Env vars:
#   ONLY=nw,bw,rp    restrict to these states (repo IDs, comma-separated)
#   SKIP=rp,by       drop these states
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
GROUP="${1:-}"
ROOT="${2:-.}"
KEEP_GOING="${KEEP_GOING:-1}"
DRY_RUN="${DRY_RUN:-0}"

# ---------------------------------------------------------------------------- the matrix
#
# family  state  dataset  rough size (verified 2026-07; "?" = the source publishes no
#                         Content-Length, so it cannot be estimated without downloading)
#
# ALKIS sizes are bytes on disk for the file-based states, feature counts for the five
# service-only states (be, hb, he, ni, st) which stream from a WFS or OGC API instead.
#
MATRIX="$(cat <<'EOF'
alkis bw nas          22.7G
alkis bw shape        20.4G
alkis by tn            5.4G
alkis by hausumringe   0.7G
alkis by verwaltung    0.1G
alkis be flurstuecke   403k_feat
alkis be gebaeude      784k_feat
alkis bb nas           4.0G
alkis bb shape         1.6G
alkis hb flurstuecke   small
alkis hh gml           0.5G
alkis he flurstuecke   5.0M_feat
alkis he zoning         43k_feat
alkis mv nas           1448_files
alkis ni flurstueck    6.3M_feat
alkis ni gebaeude      6.5M_feat
alkis nw nas          25.3G
alkis nw gpkg          8.9G
alkis rp lika         30.7G
alkis rp hu            1.6G
alkis sl nas           2.1G
alkis sl shape         0.5G
alkis sn nas           ?
alkis sh geojson       0.24G
alkis st flurstueck    2.7M_feat
alkis st gebaeude      1.7M_feat
alkis st nutzung       2.3M_feat
alkis th shape         1.2G
alkis th nas           6.5G
lidar bb dgm1           41G
lidar bb las           1.4T
lidar be dgm1          0.2G
lidar be las           ?
lidar bw dgm1          134G
lidar by dgm1          217G
lidar by las           ?T
lidar mv dgm1          ?
lidar mv las           ?
lidar ni dgm1          ?
lidar nw dgm1           79G
lidar nw las           3.5T
lidar rp dgm1           33G
lidar rp las           5.2T
lidar sn dgm1          ?
lidar sn las           ?
EOF
)"

# LiDAR is only published by 9 states, and two of those publish no point cloud at all:
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

selected() {  # selected <family> <state> <dataset>
  local fam="$1" st="$2" ds="$3"
  case "$GROUP" in
    alkis) [[ "$fam" == "alkis" ]] || return 1 ;;
    lidar) [[ "$fam" == "lidar" ]] || return 1 ;;
    dgm1)  [[ "$fam" == "lidar" && "$ds" == "dgm1" ]] || return 1 ;;
    las)   [[ "$fam" == "lidar" && "$ds" == "las"  ]] || return 1 ;;
    all)   : ;;
  esac
  in_csv "$st" "${SKIP:-}" && return 1
  [[ -n "${ONLY:-}" ]] && { in_csv "$st" "$ONLY" || return 1; }
  return 0
}

usage() {
  sed -n '/^# Usage : /,/^set /p' "$0" | sed '$d;s/^# \{0,1\}//' >&2
  exit 2
}

case "$GROUP" in
  alkis|lidar|dgm1|las|all) : ;;
  --list) : ;;
  *) usage ;;
esac

# ---------------------------------------------------------------------------- walk

PLAN=""
N=0
while read -r FAM ST DS SIZE; do
  [[ -n "$FAM" ]] || continue
  # --list matches no family case below, so it lists everything — but still honours ONLY/SKIP.
  selected "$FAM" "$ST" "$DS" || continue
  PLAN="$PLAN$FAM $ST $DS $SIZE"$'\n'
  N=$((N + 1))
done <<<"$MATRIX"

if [[ "$GROUP" == "--list" ]]; then
  printf '%-6s %-5s %-12s %-10s %s\n' family state dataset size destination
  printf '%-6s %-5s %-12s %-10s %s\n' ------ ----- ------------ ---------- -----------
  while read -r FAM ST DS SIZE; do
    [[ -n "$FAM" ]] || continue
    printf '%-6s %-5s %-12s %-10s %s\n' "$FAM" "$ST" "$DS" "${SIZE//_/ }" "$ROOT/$FAM/$ST-$DS"
  done <<<"$PLAN"
  cat <<'EOF'

Sizes are as measured live in 2026-07. "?" means the source serves no Content-Length.
Feature counts mark the five ALKIS states that publish services, not files.

Roughly: alkis ~132 GB + 23 M streamed features · dgm1 ~600 GB · las 12 TB and up.
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
while read -r FAM ST DS SIZE; do
  [[ -n "$FAM" ]] || continue
  i=$((i + 1))
  dest="$ROOT/$FAM/$ST-$DS"
  if [[ "$FAM" == "alkis" ]]; then
    script="download_alkis.sh"; set -- "$ST" "$DS"
  else
    script="$(lidar_script "$ST")"; set -- "$DS"
  fi

  echo
  echo "--- [$i/$N] $FAM $ST $DS  (~${SIZE//_/ })  -> $dest"
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
