#!/bin/bash
#SBATCH --job-name=chain_x10
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=chain_x10_%j.out
#
# Self-propagating chain link for the X10 evening-start run (2026-08-31).
# Submit with --export=ALL,IDX=b and --dependency=afterok:<X10a wrf job>.
# Each link: builds segment X10<IDX> from the previous segment's restart via
# setup_restart_run.sh (NO --submit), then (a) relinks wrfinput/wrfbdy to
# X10a's (the tool hardcodes the 18th's window, whose wrfbdy does not cover
# the 17th evening), (b) fixes start_day/end_day (the tool takes start_day
# from the template, which the old met dir syncs to 18), (c) submits, and
# (d) queues the next link afterok. On any failure the chain halts
# (DependencyNeverSatisfied) -- the session-side watchdog polls sacct.
set -u
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
IDX=${IDX:?}
# seg table:      PREV RST_DATE                 START SDAY EDAY HOURS WTIME
case $IDX in
  b) T=(a "2025-07-17_19:00:00" 19 17 18 6 "05:15:00"); NEXT=c ;;
  c) T=(b "2025-07-18_01:00:00" 01 18 18 6 "05:15:00"); NEXT=d ;;
  d) T=(c "2025-07-18_07:00:00" 07 18 18 6 "05:15:00"); NEXT=e ;;
  e) T=(d "2025-07-18_13:00:00" 13 18 18 6 "05:15:00"); NEXT=f ;;
  f) T=(e "2025-07-18_19:00:00" 19 18 18 3 "02:45:00"); NEXT="" ;;
  *) echo "bad IDX $IDX"; exit 1 ;;
esac
PREV=${T[0]}; RSTD=${T[1]}; START=${T[2]}; SDAY=${T[3]}; EDAY=${T[4]}; HOURS=${T[5]}; WTIME=${T[6]}
RST=$DATA/branko_runs/innval_pbl3d_X10$PREV/wrfrst_d01_$RSTD
[ -f "$RST" ] || { echo "!!! restart missing: $RST"; exit 1; }
"$RC/scripts/setup_restart_run.sh" X10$IDX --rst "$RST" --start "$START" --hours "$HOURS" \
  --time "$WTIME" --nodes 2 --partition zen3_1024 --iofields "$RC/iofields_d1d2.txt" --wrflux-min 30 \
  --set restart_interval=180 --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0 \
  --set pbl3d_moist_cond_max=10000.0 --set pbl3d_t2_scalar=1 \
  --set output_t_fluxes=0 --set output_q_fluxes=0 --set output_u_fluxes=0 \
  --set output_v_fluxes=0 --set output_w_fluxes=0 --set output_tke_moments=1 \
  --set start_day="$SDAY" --set end_day="$EDAY" || { echo "!!! build failed"; exit 1; }
RUNDIR=$DATA/branko_runs/innval_pbl3d_X10$IDX
ln -sfn $DATA/branko_runs/innval_pbl3d_X10a/wrfinput_d01 $RUNDIR/wrfinput_d01
ln -sfn $DATA/branko_runs/innval_pbl3d_X10a/wrfbdy_d01   $RUNDIR/wrfbdy_d01
grep -E '^ (start_day|end_day|start_hour|run_hours|pbl3d_t2_scalar)' $RUNDIR/namelist.input | tr -s ' '
jid=$(sbatch --parsable --chdir="$RUNDIR" "$RUNDIR/submit_wrf.slurm") || { echo "!!! sbatch failed"; exit 1; }
echo "X10$IDX submitted as $jid"
if [ -n "$NEXT" ]; then
  nj=$(sbatch --parsable --dependency=afterok:$jid --export=ALL,IDX=$NEXT --chdir="$RUNDIR" "$RC/scripts/chain_x10.slurm")
  echo "next link ($NEXT) queued as $nj afterok:$jid"
fi
