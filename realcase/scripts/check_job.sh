#!/bin/bash
# Report on a real.exe/wrf.exe SLURM job: state via sacct, and if it ran,
# whether the RSL logs show a clean finish or a failure.
#
#   realcase/scripts/check_job.sh <jobid> [rundir]
#
# rundir defaults to the current directory. Exit status: 0 = SUCCESS COMPLETE
# (real.exe or wrf.exe), 1 = ran but did not finish cleanly, 2 = not finished
# yet (PENDING/RUNNING), 3 = usage error.
set -u

JOBID=${1:-}
[ -n "$JOBID" ] || { echo "usage: check_job.sh <jobid> [rundir]" >&2; exit 3; }
RUNDIR=${2:-.}

STATE=$(sacct -j "$JOBID" --format=State --noheader 2>/dev/null | head -1 | tr -d ' ')
echo "=== job $JOBID: ${STATE:-UNKNOWN}"

case "$STATE" in
  PENDING|""|RUNNING)
    sacct -j "$JOBID" --format=JobID,JobName,State,ExitCode,Elapsed
    echo "=== not finished yet"
    exit 2
    ;;
esac

sacct -j "$JOBID" --format=JobID,JobName,State,ExitCode,Elapsed

ERR="$RUNDIR/rsl.error.0000"
OUT="$RUNDIR/rsl.out.0000"
RC=1
for tag in "SUCCESS COMPLETE WRF" "SUCCESS COMPLETE REAL_EM"; do
  if [ -f "$OUT" ] && grep -q "$tag" "$OUT"; then
    echo "=== $tag"
    RC=0
  fi
done

if [ "$RC" != 0 ]; then
  echo "!!! no SUCCESS COMPLETE marker found. State was $STATE."
  if [ "$STATE" = TIMEOUT ]; then
    echo "    (TIMEOUT means it hit the wall-time cap, not a crash -- check"
    echo "    whether it was still stepping cleanly right before the cutoff.)"
  fi
  if [ -f "$ERR" ]; then
    echo "--- last errors in $ERR:"
    grep -iE 'error|fatal|cfl|abort|stop' "$ERR" | tail -20
  fi
fi

if [ -f "$OUT" ]; then
  echo "--- last timing line(s):"
  grep 'Timing for main' "$OUT" | tail -3
fi

exit "$RC"
