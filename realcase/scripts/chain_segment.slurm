#!/bin/bash
#SBATCH --job-name=chain_seg
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=chain_%j.out
#
# SLURM-resident link of a restart-segmented long run (DECISIONS 2026-08-22 22:40).
# Runs after the previous segment finished successfully (submit it with
# --dependency=afterok:<prev segment job>), builds the next segment's run dir from
# the restart file the previous segment wrote, submits it, and -- if a further
# segment is described -- queues another copy of itself behind that one. Nothing
# here depends on a live session (KNOWN_ISSUES: monitors die with the session).
#
# Why segments: 2-node jobs of <= 5:30 h start within minutes on zen3_0512, an 18 h
# job waits days. Segment boundaries MUST sit on the WRFlux 6-h averaging boundaries
# (07, 13, 19, 01 UTC): the mean fields are history-only (h{24}), not restart-carried.
#
# Variables (pass with --export=ALL,SEG=...,...):
#   SEG          name of the segment to build now, e.g. X8b
#   PREV_RUNDIR  run dir of the previous segment (its wrfrst_d01_<date> is read)
#   RST_DATE     date-time of the restart file, e.g. 2025-07-18_13:00:00
#   START        start hour HH of this segment (e.g. 13)
#   HOURS        run length in hours
#   WTIME        SLURM time limit, e.g. 05:30:00
#   WRFLUXMIN    WRFlux averaging interval in minutes (default 360; Elias 2026-08-22: 30
#                for everything from here on -- 6 h means are too coarse, and with 30-min
#                means the segment boundaries no longer need to sit on 6-h boundaries)
#   NEXT_SEG, NEXT_RST_DATE, NEXT_START, NEXT_HOURS, NEXT_WTIME  (optional) the
#                segment after this one; a chain job for it is queued afterok SEG.
#   NEXT2_SEG, NEXT2_RST_DATE, NEXT2_START, NEXT2_HOURS, NEXT2_WTIME  (optional) the
#                one after that; handed to the next link as its NEXT_*.
#
# The three --set overrides below are REQUIRED for a continuation of the X-run
# configuration: setup_restart_run.sh builds from namelist.input.pbl3d, whose
# template values are pbl3d_init_opt=1 / pbl3d_l0_min=8.0 (the X runs use 0 / 0.0,
# set by setup_experiments_20260820.sh) and whose restart_interval the tool resets
# to 0 (diagnosis-run default). See KNOWN_ISSUES E19.
set -u
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
: "${SEG:?}" "${PREV_RUNDIR:?}" "${RST_DATE:?}" "${START:?}" "${HOURS:?}" "${WTIME:?}"
RST=$PREV_RUNDIR/wrfrst_d01_$RST_DATE
echo "chain: building $SEG from $RST at $(date)"
[ -f "$RST" ] || { echo "!!! restart file missing: $RST"; exit 1; }
WRFLUXMIN=${WRFLUXMIN:-360}
out=$("$RC/scripts/setup_restart_run.sh" "$SEG" --rst "$RST" --start "$START" --hours "$HOURS" \
        --time "$WTIME" --nodes 2 --wrflux-min "$WRFLUXMIN" \
        --set restart_interval=180 --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0 --submit 2>&1)
rc=$?
echo "$out" | tail -40
[ $rc -eq 0 ] || { echo "!!! setup_restart_run.sh failed (rc=$rc)"; exit 1; }
jid=$(echo "$out" | grep -oE "Submitted batch job [0-9]+" | awk '{print $4}')
[ -n "$jid" ] || { echo "!!! no job id parsed"; exit 1; }
echo "chain: $SEG submitted as job $jid"
if [ -n "${NEXT_SEG:-}" ]; then
  EXP="ALL,SEG=$NEXT_SEG,PREV_RUNDIR=$DATA/branko_runs/innval_pbl3d_$SEG,RST_DATE=$NEXT_RST_DATE,START=$NEXT_START,HOURS=$NEXT_HOURS,WTIME=$NEXT_WTIME,WRFLUXMIN=$WRFLUXMIN"
  if [ -n "${NEXT2_SEG:-}" ]; then
    EXP="$EXP,NEXT_SEG=$NEXT2_SEG,NEXT_RST_DATE=$NEXT2_RST_DATE,NEXT_START=$NEXT2_START,NEXT_HOURS=$NEXT2_HOURS,NEXT_WTIME=$NEXT2_WTIME,NEXT2_SEG=,NEXT2_RST_DATE=,NEXT2_START=,NEXT2_HOURS=,NEXT2_WTIME="
  else
    EXP="$EXP,NEXT_SEG=,NEXT_RST_DATE=,NEXT_START=,NEXT_HOURS=,NEXT_WTIME="
  fi
  nj=$(sbatch --parsable --dependency=afterok:$jid --export="$EXP" \
        --chdir=$DATA/branko_runs/innval_pbl3d_$SEG "$RC/scripts/chain_segment.slurm")
  echo "chain: next link for $NEXT_SEG queued as job $nj (afterok:$jid)"
fi
exit 0
