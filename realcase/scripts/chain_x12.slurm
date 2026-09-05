#!/bin/bash
#SBATCH --job-name=chain_x12
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=chain_x12_%j.out
#
# Self-propagating chain link for X12 (2026-09-03) = X10 chain with MODEL-LEVEL ICON forcing (A21); X12bdy = full-window real on metgrid_output_1712ml.
# Submit with --export=ALL,IDX=b and --dependency=afterok:<X12a wrf job>.
# Each link: builds segment X12<IDX> from the previous segment's restart via
# setup_restart_run.sh (NO --submit), then (a) relinks wrfinput/wrfbdy to
# X12a's (the tool hardcodes the 18th's window, whose wrfbdy does not cover
# the 17th evening), (b) fixes start_day/end_day (the tool takes start_day
# from the template, which the old met dir syncs to 18), (c) submits, and
# (d) queues the next link afterok. On any failure the chain halts
# (DependencyNeverSatisfied) -- the session-side watchdog polls sacct.
set -u
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
IDX=${IDX:?}; TAG=${TAG:?X12m|X12p}
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
# lane/size overrides handed down the chain (2026-09-04): NODES=4 halves the wall (measured 1.5 s/step on 2 nodes, ~0.8 on 4)
NODES=${NODES:-2}
if   [ "$NODES" -ge 5 ]; then WTIME=$( [ "$HOURS" -ge 6 ] && echo 02:15:00 || echo 01:10:00 )   # 0.65 s/step measured on 5 nodes
elif [ "$NODES" -ge 4 ]; then WTIME=$( [ "$HOURS" -ge 6 ] && echo 03:00:00 || echo 01:35:00 ); fi
RST=$DATA/branko_runs/innval_pbl3d_$TAG$PREV/wrfrst_d01_$RSTD
[ -f "$RST" ] || { echo "!!! restart missing: $RST"; exit 1; }
"$RC/scripts/setup_restart_run.sh" $TAG$IDX --rst "$RST" --start "$START" --hours "$HOURS" \
  --time "$WTIME" --nodes "$NODES" --partition "${LANE:-zen3_1024}" --iofields "$RC/iofields_d1d2.txt" --wrflux-min 30 \
  --set restart_interval=180 --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0 \
  --set pbl3d_moist_cond_max=10000.0 --set pbl3d_t2_scalar=1 \
  --set output_t_fluxes=0 --set output_q_fluxes=0 --set output_u_fluxes=0 \
  --set output_v_fluxes=0 --set output_w_fluxes=0 --set output_tke_moments=1 \
  --set start_day="$SDAY" --set end_day="$EDAY" || { echo "!!! build failed"; exit 1; }
RUNDIR=$DATA/branko_runs/innval_pbl3d_$TAG$IDX
ln -sfn $DATA/branko_runs/innval_pbl3d_${TAG}bdy/wrfinput_d01 $RUNDIR/wrfinput_d01   # X12bdy = full-window real (13->23); X12a's wrfbdy ends 19:00 (its real ran --hours 6) and starved X12b (job 8549830)
ln -sfn $DATA/branko_runs/innval_pbl3d_${TAG}bdy/wrfbdy_d01   $RUNDIR/wrfbdy_d01
grep -E '^ (start_day|end_day|start_hour|run_hours|pbl3d_t2_scalar)' $RUNDIR/namelist.input | tr -s ' '
jid=$(cd "$RUNDIR" && sbatch --parsable submit_wrf.slurm) || { echo "!!! sbatch failed"; exit 1; }   # MUST sbatch from the rundir: the submit scripts cd to SLURM_SUBMIT_DIR, which --chdir does not set
echo "$TAG$IDX submitted as $jid"
sbatch --parsable --dependency=afterok:$jid --export=ALL,TAG=$TAG,IDX=$IDX "$RC/scripts/judge_x12.slurm" >/dev/null && echo "judge armed afterok:$jid"
sbatch --parsable --dependency=afternotok:$jid --export=ALL,STAGE=$TAG$IDX,FAILED_JOB=$jid "$RC/scripts/notify_x12.slurm" >/dev/null && echo "ping armed afternotok:$jid"
if [ -n "$NEXT" ]; then
  nj=$(sbatch --parsable --dependency=afterok:$jid --export=ALL,IDX=$NEXT,TAG=$TAG,LANE=${LANE:-zen3_1024},NODES=$NODES --chdir="$RUNDIR" "$RC/scripts/chain_x12.slurm")
  echo "next link ($NEXT) queued as $nj afterok:$jid"
fi
