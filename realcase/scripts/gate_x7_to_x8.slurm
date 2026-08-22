#!/bin/bash
#SBATCH --job-name=gate_X7
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=gate_X7_%j.out
#
# Runs after X7 (job 8483386) exits successfully (submitted with
# --dependency=afterok:8483386); X8 (8483404) depends afterok on THIS job, so
# the quality gate lives inside SLURM and survives a Claude session restart.
# 2026-08-22 17:40: X8 was released from the dependency (Elias: queue it now, the
# wait is long anyway) and the gate is REPORT-ONLY. Export X8_JOB=<id> to re-arm
# the cancel-on-failure.
set -u
X7_JOB=${X7_JOB:-8483386}
X8_JOB=${X8_JOB:-}   # empty = report only
DATA=/gpfs/data/fs72996/ewahl
source $DATA/branko/realcase/env/vsc5.sh >/dev/null 2>&1
ARCH=$DATA/exp/X7/wrf_output/$X7_JOB
echo "gate on $ARCH at $(date)"
python3 $DATA/branko/realcase/scripts/gate_x7_to_x8.py "$ARCH" $DATA/exp/X6/wrf_output/8478327
rc=$?
if [ $rc -ne 0 ]; then
  if [ -n "$X8_JOB" ]; then
    echo "GATE FAILED (rc=$rc) -> cancelling X8 $X8_JOB"
    scancel $X8_JOB
  else
    echo "GATE FAILED (rc=$rc); report only, nothing cancelled"
  fi
  exit 1
fi
echo "GATE PASSED"
exit 0
