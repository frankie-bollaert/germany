#!/usr/bin/env bash
#
# download_samples.sh — fetch the 5x5 km sample square of every Bundesland.
#
# The squares live in sample_squares.tsv, one per state, aligned to the UTM kilometre grid
# in each state's own CRS. This drives the per-state LiDAR downloaders over them so a sample
# pack can be built with one command instead of sixteen, and so the two easy ways to get it
# wrong are handled once here rather than remembered every time:
#
#   · BBOX is an INCLUSIVE tile-corner range, not a coordinate extent. The TSV stores the
#     true 5 km extent (371..376), so passing it through verbatim selects six tiles per axis
#     -- 36 tiles, 6x6 km. Every maximum therefore gets 1 subtracted here.
#   · Not every downloader honours BBOX, and the ones that don't fail SILENTLY -- they accept
#     the square and plan the whole state. download_rlp_lidar.sh ignores it outright
#     (32.8 GB of dgm1, 5.18 TB of las), and two others ignore it for one dataset only:
#     by/dgm1 (216.9 GB) and be/las (232.3 GB). All are detected and refused, not skipped
#     quietly. be/las is the one that has a way out: Berlin's smallest published unit is a
#     city region, and the smallest region is sample-sized, so BE is cut by BE_LAS_REGIONS
#     instead of by the square. See the note above cuttable().
#   · A square can also land in a hole in a state's coverage. That plans zero tiles and
#     reports success, which is indistinguishable from a finished download until you look
#     in the directory. Every combination is checked and the empty ones are listed at the
#     end. bb/las does this at LAS_KM=3: Brandenburg's ALS is still partial, so the centred
#     core at Luebbenau is empty while the full 5 km square has 5 tiles.
#
# Point cloud is sampled smaller than terrain on purpose. A 5x5 km las square is ~2.4 GB per
# state and ~150 M points -- far past what a sample is for -- so las takes a centred core.
# Terrain stays at the full 5x5 km, where extent is what makes it useful.
#
# LAS_KM defaults to 3, not 1, because tile size is not uniform: bw, sn and be package in
# 2 km units. A 1 km core there can fall entirely between tile corners and come back with
# zero tiles and no error -- Sachsen does exactly that. 3 km finds data on both the 1 km and
# 2 km grids. Drop it to 1 for the 1 km states if the ~1.9 GB matters more than uniformity.
#
# A related wrinkle, unfixed: the -1 rule assumes 1 km tiles, so the footprint is a true
# 5x5 km only on 1 km grids (bb, nw -> 25 tiles). On 2 km grids the same square yields 4-9
# tiles covering a slightly different area. Comparable, not identical, between states.
#
# Coverage: 11 of 16 states have a LiDAR downloader, 10 of those accept BBOX (rp is the one
# that does not). Ten cover the whole state; st fetches two sample areas, so a square outside
# them plans zero tiles. The other five publish LiDAR openly but behind portals with no
# anonymous bulk endpoint -- see
# README.md. ALKIS is NOT wired in yet: download_alkis.sh has no BBOX support, so
# there is no way to ask it for a square. It is per-state or per-package until that lands.
#
# Usage : ./download_samples.sh [dgm1|las|both] [output_dir]
#   ./download_samples.sh                       # dgm1 for every state -> ./samples/<key>/dgm1
#   ./download_samples.sh both                  # terrain + centred point cloud core
#   ./download_samples.sh las /mnt/big          # -> /mnt/big/<key>/las
#   DRY_RUN=1 ./download_samples.sh both        # print every state's plan, download nothing
#   STATES="nw be sn" ./download_samples.sh dgm1
#
# The per-state output dir is laid out as <output_dir>/<key>/{dgm1,las}, which is exactly the
# input_base that convert_to_cloud_optimized.sh expects:
#   ./convert_to_cloud_optimized.sh dgm1 ./samples/nw ./cog
#
# Env vars (override defaults):
#   DRY_RUN=1        print each state's plan, transfer nothing (honoured by every downloader)
#   STATES="nw be"   restrict to these state keys (default: all in the TSV)
#   ALLOW_UNCUT=1    run the combinations that ignore BBOX anyway — this downloads whole
#                    states, hundreds of GB. Only meaningful with DRY_RUN=1 to see the size.
#   LAS_KM=3         width in km of the centred point-cloud core (default 3; see above)
#   BE_LAS_REGIONS   Berlin city regions to take for be/las (default Nordost, 0.9 GB).
#                    Empty refuses be/las again, as it was before regions were selectable.
#   SQUARES=path     square definitions (default ./sample_squares.tsv)
#   JOBS=8 CONN=4    passed through to the downloaders
#
set -uo pipefail

DATASET="${1:-dgm1}"
OUTROOT="${2:-./samples}"
SQUARES="${SQUARES:-./sample_squares.tsv}"
LAS_KM="${LAS_KM:-3}"
STATES="${STATES:-}"
DRY_RUN="${DRY_RUN:-0}"

case "$DATASET" in
  dgm1|las|both) : ;;
  *) echo "ERROR: dataset must be dgm1, las or both (got '$DATASET')" >&2; exit 2 ;;
esac
[[ -f "$SQUARES" ]] || { echo "ERROR: no square definitions at $SQUARES" >&2; exit 1; }

# The downloader filenames do not all match the state key used everywhere else.
script_for() {
  case "$1" in
    nw) echo "download_nrw_lidar.sh" ;;
    rp) echo "download_rlp_lidar.sh" ;;
    *)  echo "download_$1_lidar.sh" ;;
  esac
}

# bw and ni publish no point cloud, so their downloaders only offer dgm1. Read that off the
# usage line rather than hard-coding a list that would drift as states start publishing.
offers() { grep -qE "^# Usage.*\[.*\b$2\b.*\]" "$1"; }

# A script mentioning BBOX does not mean it honours BBOX for every dataset it offers, and the
# failure is silent: the square is accepted and the whole state is planned anyway. Verified
# by dry run 2026-07-28, these are the combinations where that happens:
#
#   by/dgm1  BBOX is wired only into the las polygon sweep; dgm1 comes from a statewide
#            Metalink and ignores it -> 71,979 tiles, 216.9 GB
#   be/las   the point cloud ships as whole city regions rather than tiles; the script says
#            "BBOX ignored" and hands back all 9 region packages, 232.3 GB
#
# Refused by default because the whole point of this driver is that a sample stays a sample.
#
# be/las has a second knob, though. A region is the smallest unit Berlin publishes, and one of
# the nine is small enough to be a sample on its own: Nordost, 0.9 GB against 232.3 GB for the
# city. So BE takes a region instead of a square, and lands within a factor of two of what the
# square-cut states produce. Set BE_LAS_REGIONS="" to go back to refusing it outright.
# Unset means Nordost; explicitly empty means refuse. Hence ${x-y}, not ${x:-y} — the
# latter would collapse the two and make BE_LAS_REGIONS="" silently mean "Nordost".
BE_LAS_REGIONS="${BE_LAS_REGIONS-Nordost}"

cuttable() {
  case "$1/$2" in
    be/las)  [[ -n "$BE_LAS_REGIONS" ]] ;;   # cut by region, not by square
    by/dgm1) return 1 ;;
    *)       return 0 ;;
  esac
}

wanted() {
  [[ -z "$STATES" ]] && return 0
  local s
  for s in $STATES; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

run_one() {
  local key="$1" place="$2" ds="$3" bbox="$4" script="$5"
  # Berlin's point cloud is selected by region rather than by square; every other
  # state/dataset pair leaves REGIONS empty and is cut by BBOX alone.
  local regions=""
  [[ "$key/$ds" == "be/las" ]] && regions="$BE_LAS_REGIONS"
  echo
  echo "==> $key  $ds  ($place)  ${bbox:+BBOX=$bbox}${regions:+REGIONS=$regions}"
  mkdir -p "$OUTROOT/$key"
  local log="$OUTROOT/$key/.$ds.plan"
  if ! DRY_RUN="$DRY_RUN" BBOX="$bbox" REGIONS="$regions" ./"$script" "$ds" "$OUTROOT/$key" 2>&1 | tee "$log"; then
    echo "    FAILED: $script $ds" >&2
    rm -f "$log"
    return 1
  fi
  # A square that lands in a coverage hole plans zero tiles and still reports success. That
  # is the failure mode this script exists to prevent, so name it instead of letting an
  # empty directory look like a finished download. Not hypothetical: bb/las at Luebbenau
  # yields nothing at LAS_KM=3, and 5 tiles across the full 5 km square.
  if grep -qE '(tiles|files|packages): 0( |$)' "$log"; then
    ZERO+=("$key  $ds — planned 0 tiles: this square sits in a gap in the state's coverage")
  fi
  rm -f "$log"
}

ok=0; failed=0; no_script=0; no_bbox=0; no_product=0
declare -a NOTES=()
declare -a ZERO=()

while IFS=$'\t' read -r key epsg bbox place why; do
  [[ "$key" == \#* || -z "${key// }" ]] && continue
  wanted "$key" || continue

  script="$(script_for "$key")"
  if [[ ! -f "$script" ]]; then
    NOTES+=("$key  $place — no LiDAR downloader in this repo")
    no_script=$((no_script + 1)); continue
  fi
  if ! grep -q "BBOX" "$script"; then
    NOTES+=("$key  $place — $script ignores BBOX; refusing (it would fetch the whole state)")
    no_bbox=$((no_bbox + 1)); continue
  fi

  IFS=, read -r mine minn maxe maxn <<<"$bbox"

  for ds in dgm1 las; do
    [[ "$DATASET" == "both" || "$DATASET" == "$ds" ]] || continue
    if ! offers "$script" "$ds"; then
      NOTES+=("$key  $place — no $ds published")
      no_product=$((no_product + 1)); continue
    fi
    if ! cuttable "$key" "$ds" && [[ "${ALLOW_UNCUT:-0}" != "1" ]]; then
      NOTES+=("$key  $place — $script ignores BBOX for $ds; refusing (whole state). ALLOW_UNCUT=1 to force")
      no_bbox=$((no_bbox + 1)); continue
    fi
    if [[ "$ds" == "las" ]]; then
      # centred core: inset by half the leftover, then take LAS_KM tiles inclusively
      off=$(( (5 - LAS_KM) / 2 ))
      tb="$((mine + off)),$((minn + off)),$((mine + off + LAS_KM - 1)),$((minn + off + LAS_KM - 1))"
    else
      # inclusive tile range -> a true 5x5 km
      tb="$mine,$minn,$((maxe - 1)),$((maxn - 1))"
    fi
    # Berlin's las takes a region instead. Passing the square as well would only make the
    # downloader print a note saying it ignored it.
    [[ "$key/$ds" == "be/las" ]] && tb=""
    if run_one "$key" "$place" "$ds" "$tb" "$script"; then
      ok=$((ok + 1))
    else
      failed=$((failed + 1))
    fi
  done
done < "$SQUARES"

echo
echo "──────────────────────────────────────────────────────────────"
echo "downloads ok: $ok   failed: $failed"
echo "skipped: $no_script no downloader · $no_bbox no BBOX · $no_product product not published"
if [[ ${#NOTES[@]} -gt 0 ]]; then
  echo
  printf '  %s\n' "${NOTES[@]}"
fi
if [[ ${#ZERO[@]} -gt 0 ]]; then
  echo
  echo "empty squares — planned successfully, but there is nothing there to fetch:"
  printf '  %s\n' "${ZERO[@]}"
fi
[[ "$DRY_RUN" == "1" ]] && echo && echo "DRY_RUN=1 — nothing was transferred."
echo
echo "Each state's data carries its own licence and attribution — the downloaders print it."
exit $(( failed > 0 ? 1 : 0 ))
