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
# If the gate fails, this job exits non-zero and SLURM never starts X8
# (it stays pending with DependencyNeverSatisfied); we scancel it explicitly too.
set -u
X7_JOB=${X7_JOB:-8483386}
X8_JOB=${X8_JOB:-8483404}
DATA=/gpfs/data/fs72996/ewahl
source $DATA/branko/realcase/env/vsc5.sh >/dev/null 2>&1
ARCH=$DATA/exp/X7/wrf_output/$X7_JOB
echo "gate on $ARCH at $(date)"
python3 $DATA/branko/realcase/scripts/gate_x7_to_x8.py "$ARCH" $DATA/exp/X6/wrf_output/8478327
rc=$?
if [ $rc -ne 0 ]; then
  echo "GATE FAILED (rc=$rc) -> cancelling X8 $X8_JOB"
  scancel $X8_JOB
  exit 1
fi
echo "GATE PASSED -> X8 $X8_JOB may start"
exit 0
