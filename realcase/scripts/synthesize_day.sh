#!/bin/bash
# Stitch the segmented 23 h day (2025-07-18 01:00 -> 07-19 00:00) into one
# pseudo-run directory under $DATA/wrf_output/<FAKE_JOBID>/ so post-processing
# (compare_mynn.py etc.) can treat it exactly like a single job's archive,
# sitting next to the real archives (e.g. the MYNN control 8320565).
#
#   realcase/scripts/synthesize_day.sh [FAKE_JOBID]     (default 9999999)
#
# Frames are symlinked, not copied (no disk cost); the constituent archives
# stay untouched. Idempotent: re-run it after a new segment archives and the
# new frames are picked up. At a segment seam the EARLIER segment wins (the
# parent wrote the frame the child restarted from). Provenance goes to
# job_info.txt in the target; a coverage report of the 30-min ladder prints
# at the end -- missing frames are listed, not fatal.
#
# NOTE for interpretation: the composite is NOT one continuous integration of
# one binary. 01->10 is X7 (pre-A14 binary; the fix is inert wherever
# cond_moist < 1e4, but X7 could not reject what the fixed binary rejects);
# 10->24 is the fixed binary with pbl3d_moist_cond_max=1e4 (X9a/X9b/X9c).
# Segment boundaries are bit-transparent restarts on the same 2x128 layout.
set -u -o pipefail

DATA=/gpfs/data/fs72996/ewahl
FAKE=${1:-9999999}
DST=$DATA/wrf_output/$FAKE

# Chronological order = priority order (first listed wins a name clash).
SOURCES=(
  "$DATA/exp/X7/wrf_output/8483386"
  "$DATA/exp/X9a/wrf_output/8489332"
)
# X9b/X9c archive under a job id we don't hard-code; glob whatever exists.
for seg in X9b X9c; do
  for d in "$DATA/exp/$seg"/wrf_output/*/; do
    [ -e "${d}namelist.input" ] && SOURCES+=("${d%/}")
  done
done

mkdir -p "$DST"
linked=0; kept=0
for src in "${SOURCES[@]}"; do
  [ -d "$src" ] || { echo "!!! missing source: $src"; continue; }
  for f in "$src"/wrfout_d01_* "$src"/meanout_d01_*; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    if [ -e "$DST/$b" ]; then kept=$((kept+1)); else ln -s "$f" "$DST/$b"; linked=$((linked+1)); fi
  done
done

{
  echo "Pseudo-job $FAKE -- segmented 23 h day 2025-07-18 01:00 -> 07-19 00:00, stitched $(date)"
  echo "Not a real SLURM job. Sources, in priority order:"
  for src in "${SOURCES[@]}"; do echo "  $src"; done
  echo "See DECISIONS 2026-08-24 and the note in synthesize_day.sh: 01->10 is the"
  echo "pre-A14 binary (X7), 10->24 the fixed binary with pbl3d_moist_cond_max=1e4."
} > "$DST/job_info.txt"

echo "=== $DST: $linked new links, $kept already present"
echo "=== coverage of the 30-min wrfout ladder (missing frames listed):"
missing=0
for m in $(seq 60 30 1440); do
  if [ "$m" -lt 1440 ]; then d=18; hh=$((m/60)); mm=$((m%60));
  else d=19; hh=0; mm=0; fi
  t=$(printf '2025-07-%02d_%02d:%02d:00' "$d" "$hh" "$mm")
  [ -e "$DST/wrfout_d01_$t.nc" ] || { echo "    missing wrfout_d01_$t.nc"; missing=$((missing+1)); }
done
echo "=== $missing of 47 half-hour frames missing; meanout frames linked: $(ls "$DST" | grep -c '^meanout')"
