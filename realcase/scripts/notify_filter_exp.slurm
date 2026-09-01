#!/bin/bash
#SBATCH --job-name=f6exp_ping
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:02:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/.claude_wake/ping_%j.out
# Failure hook for the 6th-order-filter experiment (A20). Submit with
# --dependency=afternotok:<job> and --export=ALL,FAILED_JOB=<jobid>,RUNDIR=<name>.
# Writes the wake flag the l56 crontab watcher (claude_watch.sh) consumes.
DATA=/gpfs/data/fs72996/ewahl
# Deliberate cancellations are not failures (KNOWN_ISSUES E34).
if [ -n "${FAILED_JOB:-}" ]; then
  st=$(sacct -j "$FAILED_JOB" -n -o State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in CANCELLED*) echo "job $FAILED_JOB was CANCELLED, not a failure -- no flag written"; exit 0 ;; esac
fi
cat > "$DATA/.claude_wake/f6exp_$(date +%s).txt" <<MSG
FILTER EXPERIMENT FAILED: job ${FAILED_JOB:-unknown} (run dir branko_runs/${RUNDIR:-innval_pbl3d_CPB1x}) did not complete cleanly.

FIRST, before any action, summarise the context in your own words from the records (Elias 2026-09-01):
read the top block of HANDOVER_2026-08-20.md and DECISIONS.md entries 2026-09-01 ~16:30/~17:00/~17:45, then state in one paragraph:
what this run is (01-05 UT restart segment with diff_6th_opt=0, the controlled experiment for OPEN_ISSUES A20 -- the 6th-order
filter warming the Inn-valley cold pool), what it was predicted to show (pool cooling roughly doubling; resolved advection
compensating an unknown share), and what a failure here may mean (candidate: 2dx noise/instability without the filter --
the 20-min devel probe exp/CPB2d0 showed bounded, decelerating noise, so a crash LATER in the night is itself a finding).
Write that summary into the handover before diagnosing.

Diagnose: sacct -j ${FAILED_JOB:-}; read rsl.error.0000 in the run dir (grep -iE "FATAL|SIGSEGV|cfl|NaN").
If TIMEOUT: the run needs a longer wall on resubmission -- record it, do not resubmit from an auto-session.
If a crash: identify when (sim time) and where (grep the last frames; cfl prints give i,j,k); check whether grid-scale noise
grew (compare the last archived wrfout against exp/CPB2d/wrf_output/8552763 with wrf3dpbl-diag/noise_2dx.py -- python may be
denied in auto-mode; then record the frame names for the next interactive session instead). Do not retune anything.
The archive (even partial) is under exp/CPB1x/wrf_output/${FAILED_JOB:-}/ -- submit_wrf.slurm archives even on failure.

Before ending this auto-session (Elias 2026-08-31): record what happened and what you found in HANDOVER_2026-08-20.md
(and DECISIONS.md if a verdict was reached), sync to branko/realcase/project/, commit and push if git is permitted;
otherwise state in the handover that the commit is pending.
MSG
echo "flag written for filter experiment job ${FAILED_JOB:-unknown}"
