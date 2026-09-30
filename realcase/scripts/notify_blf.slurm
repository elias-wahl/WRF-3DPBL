#!/bin/bash
#SBATCH --job-name=blf_ping
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:02:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/.claude_wake/ping_%j.out
# Failure hook for the BLF chain (A43/A44): submit with --dependency=afternotok:<job> and --export=ALL,STAGE=<name>,FAILED_JOB=<jobid>.
# Writes a flag that claude_watch.sh (crontab, every 15 min) turns into a RESUMED session 6d8256a7-... (Elias 2026-09-30).
DATA=/gpfs/data/fs72996/ewahl
if [ -n "${FAILED_JOB:-}" ]; then
  st=$(sacct -j "$FAILED_JOB" -n -o State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in CANCELLED*) echo "job $FAILED_JOB was CANCELLED, not a failure -- no flag written"; exit 0 ;; esac
fi
cat > $DATA/.claude_wake/blf_${STAGE:-unknown}_$(date +%s).txt <<MSG
RESUME_SESSION=6d8256a7-e5e0-49eb-ab02-e03c915b1b10
BLF chain failure: stage ${STAGE:-unknown} (job ${FAILED_JOB:-unknown}, state ${st:-?}) did not complete cleanly.
Diagnose: sacct -j ${FAILED_JOB:-}; rsl.error.0000 in branko_runs/innval_pbl3d_${STAGE:-BLFa} (grep FATAL/SIGSEGV/cfl); for the gate: exp/x16_judge/gate_hbg.*.log.
If TIMEOUT: resume that segment from its newest 3-hourly wrfrst (restart_interval 180) with a longer wall and re-arm the rest of the chain (afterok). If the gate failed: find the differing variables, do not start BLF. If a physics crash: locate onset (history + closure fields, as for BL47R), record in OPEN_ISSUES A43/A44, DECISIONS and the passover; do not retune; tell Elias.
MSG
echo "flag written for ${STAGE:-unknown}"
