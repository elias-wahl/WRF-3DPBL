#!/bin/bash
#SBATCH --job-name=eve_ping
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:02:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/.claude_wake/ping_%j.out
# Failure hook for the evening formation-budget pair (DECISIONS 2026-09-01 ~19:45).
# Submit with --dependency=afternotok:<job> and --export=ALL,FAILED_JOB=<id>,NAME=<EVE1|EVE1M>.
DATA=/gpfs/data/fs72996/ewahl
if [ -n "${FAILED_JOB:-}" ]; then
  st=$(sacct -j "$FAILED_JOB" -n -o State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in CANCELLED*) echo "job $FAILED_JOB was CANCELLED, not a failure -- no flag written"; exit 0 ;; esac
fi
cat > "$DATA/.claude_wake/eve_${NAME:-unknown}_$(date +%s).txt" <<MSG
EVENING FORMATION RUN FAILED: ${NAME:-unknown} (job ${FAILED_JOB:-unknown}, run dir branko_runs/innval_pbl3d_${NAME:-EVE1}).

FIRST summarise the context from the records into the handover (Elias 2026-09-01): read the handover top blocks and
DECISIONS 2026-09-01 ~19:45/~19:00. In one paragraph: these are twin 19->01 UT restart segments off the X10 lineage
hunting the pool-FORMATION deficit (the ~3 K Kolsass bias forms 19-21 UT; hypotheses C1 drainage-too-warm, C2 surface
reversal too slow, C3 residual-layer downmixing, C4 down-valley advection); EVE1 = 3D closure (pbl3d), EVE1M = MYNN twin
(bl_pbl_physics=5, diff_opt=2, QKE spins up from the restart's stale field -- first hour is spin-up). Full WRFlux theta
budget at 30-min means; 5-min surface stream (auxhist23) for the flux-reversal timing.

Diagnose: sacct -j ${FAILED_JOB:-}; read rsl.error.0000 in the run dir (grep -iE "FATAL|SIGSEGV|cfl|NaN").
If TIMEOUT: record it; do not resubmit from an auto-session. If a crash: locate sim time and place; note that a crash in
the MYNN twin's first ~hour may be the QKE cold-start -- record, do not retune. Partial archive lands in
exp/${NAME:-EVE1}/wrf_output/${FAILED_JOB:-}/ even on failure.
Record findings in HANDOVER_2026-08-20.md before ending; sync to branko/realcase/project/ and commit if git is permitted.
MSG
echo "flag written for ${NAME:-unknown} job ${FAILED_JOB:-unknown}"
