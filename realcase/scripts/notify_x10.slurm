#!/bin/bash
#SBATCH --job-name=x10_ping
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:02:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/.claude_wake/ping_%j.out
# Failure hook for the X10 chain: submit with --dependency=afternotok:<job> and
# --export=ALL,STAGE=<name>,FAILED_JOB=<jobid>. Writes a status flag file that
# the monitoring layer (claude_watch.sh crontab / session watchdog) picks up.
DATA=/gpfs/data/fs72996/ewahl
cat > $DATA/.claude_wake/x10_${STAGE:-unknown}_$(date +%s).txt <<MSG
X10 chain failure: stage ${STAGE:-unknown} (job ${FAILED_JOB:-unknown}) did not complete cleanly.
Diagnose: sacct -j ${FAILED_JOB:-}; read rsl.error.0000 in branko_runs/innval_pbl3d_${STAGE:-X10a} (grep FATAL/SIGSEGV/cfl).
If TIMEOUT: rebuild the segment with a longer wall (realcase/scripts/setup_restart_run.sh) and re-arm the rest of the chain per realcase/scripts/chain_x10.slurm. If a physics crash: do not retune; record in OPEN_ISSUES and the handover, hold the chain, flag it for Elias.
Context: X10 = evening-start run, ICON 17_12 forcing, pbl3d_t2_scalar=1; segments a 17_13-19, b 19-01, c 01-07, d 07-13, e 13-19, f 19-22; records DECISIONS.md 2026-08-31 ~00:45.
Before ending this auto-session (Elias 2026-08-31): record what happened and what you found/did in HANDOVER_2026-08-20.md (and DECISIONS.md if a verdict or decision was made), sync both to branko/realcase/project/, commit and push.
MSG
echo "flag written for ${STAGE:-unknown}"
