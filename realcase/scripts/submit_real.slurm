#!/bin/bash
#SBATCH --job-name=real_innval
#SBATCH --output=real.%j.out
#SBATCH --error=real.%j.err
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=128
#SBATCH --time=01:00:00
#---- EDIT THESE TWO, they ship blank on purpose -----------------------------
#SBATCH --account=CHANGEME
#SBATCH --partition=CHANGEME
#-----------------------------------------------------------------------------
# Levante:  --account=bm1236        --partition=compute      (128 cores/node)
# VSC-5:    --account=<projectid>   --partition=zen3_0512    (128 cores/node)
#           add  #SBATCH --qos=zen3_0512
#
# real.exe is I/O bound, not compute bound. Two nodes is plenty; more mainly
# buys a longer decomposition argument.

set -u
cd "$SLURM_SUBMIT_DIR" || exit 1
. ./env.sh

ulimit -s unlimited
export OMP_NUM_THREADS=1

echo "=== real.exe on $SLURM_NTASKS ranks, $(date)"
rm -f rsl.out.* rsl.error.*
# eval, not a bare expansion: MPI_LAUNCHER may embed $SLURM_NTASKS (e.g.
# "mpirun -np $SLURM_NTASKS"), which needs a second expansion pass to resolve.
eval "${MPI_LAUNCHER:-srun} ./real.exe"
RC=$?

echo "=== real.exe returned $RC"
if grep -q 'SUCCESS COMPLETE REAL_EM INIT' rsl.out.0000 2>/dev/null; then
  echo "=== SUCCESS COMPLETE REAL_EM INIT"
  ls -l wrfinput_d01 wrfbdy_d01
  echo
  echo "Now run the sanity check before queueing wrf.exe:"
  echo "    python3 <wrf>/realcase/scripts/check_wrfinput.py wrfinput_d01"
else
  echo "!!! real.exe did not finish. First errors:"
  grep -iE 'error|fatal|abort' rsl.error.0000 2>/dev/null | head -20
  exit 1
fi
