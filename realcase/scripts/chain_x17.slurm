#!/bin/bash
#SBATCH --job-name=chain_x17
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/branko_runs/innval_pbl3d_X17a/chain_x17_%j.out
# SLURM-resident link for the X17 chain (17 July 13 UT start, production land state; DECISIONS 2026-09-17). Same recipe as
# chain_x12.slurm: setup_restart_run.sh builds from the template for the 18th, so the X12 physics sets, start/end day and the
# 17 July boundary files (X17a's wrfbdy covers 17_13 -> 18_22) must be put back; ABSOLUTE iofields path (a relative one is
# resolved from the job's cwd and fails -- link 8640529). WRFlux switches as X17a/X16s (t on; q,u,v,w off; tke moments on).
# Variables: SEG PREV RSTD START HOURS SDAY EDAY WTIME  (e.g. SEG=X17c PREV=X17b RSTD=2025-07-18_01:00:00 START=01 HOURS=4 SDAY=18 EDAY=18 WTIME=02:00:00)
set -u
DATA=/gpfs/data/fs72996/ewahl; RC=$DATA/branko/realcase
: "${SEG:?}" "${PREV:?}" "${RSTD:?}" "${START:?}" "${HOURS:?}" "${SDAY:?}" "${EDAY:?}" "${WTIME:?}"
RST=$DATA/branko_runs/innval_pbl3d_$PREV/wrfrst_d01_$RSTD; [ -f "$RST" ] || { echo "!!! restart missing: $RST"; exit 1; }
source $RC/env/vsc5.sh >/dev/null 2>&1
"$RC/scripts/setup_restart_run.sh" $SEG --rst "$RST" --start "$START" --hours "$HOURS" --time "$WTIME" --nodes 5 --partition zen3_0512 \
  --iofields "$RC/iofields_full.txt" --wrflux-min 30 --set restart_interval=180 --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0 \
  --set pbl3d_moist_cond_max=10000.0 --set pbl3d_t2_scalar=1 --set output_t_fluxes=1 --set output_q_fluxes=0 --set output_u_fluxes=0 \
  --set output_v_fluxes=0 --set output_w_fluxes=0 --set output_tke_moments=1 --set start_day="$SDAY" --set end_day="$EDAY" || { echo "!!! build failed"; exit 1; }
RUNDIR=$DATA/branko_runs/innval_pbl3d_$SEG
ln -sfn $DATA/branko_runs/innval_pbl3d_X17a/wrfinput_d01 $RUNDIR/wrfinput_d01; ln -sfn $DATA/branko_runs/innval_pbl3d_X17a/wrfbdy_d01 $RUNDIR/wrfbdy_d01
grep -q 'temp/branko' $RUNDIR/submit_wrf.slurm || { echo "!!! E49 mkdir missing in $RUNDIR/submit_wrf.slurm"; exit 1; }
jid=$(cd "$RUNDIR" && sbatch --parsable submit_wrf.slurm) || { echo "!!! sbatch failed"; exit 1; }
echo "$SEG submitted: $jid"; echo "$SEG $jid (chain_x17 $SLURM_JOB_ID)" >> $DATA/branko_runs/innval_pbl3d_X17a/CHAIN_JOBIDS.txt
