#!/bin/bash
#SBATCH --job-name=real_innval
#SBATCH --output=real.%j.out
#SBATCH --error=real.%j.err
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=128
#SBATCH --time=01:00:00
#---- EDIT THESE, they ship blank/placeholder on purpose ---------------------
#SBATCH --account=CHANGEME
#SBATCH --partition=CHANGEME
#SBATCH --qos=CHANGEME
#-----------------------------------------------------------------------------
# Levante:  --account=bm1236        --partition=compute        (128 cores/node)
# VSC-5:    --account=<projectid>   --partition=zen3_0512      (128 cores/node)
#           add  #SBATCH --qos=zen3_0512
# MUSICA:   --account=p201110       --partition=zen4_0768      (192 physical
#           cores/node; SLURM reports 384, ThreadsPerCore=2 -- also add
#           --hint=nomultithread and set --ntasks-per-node=190, NOT 192: a
#           "full cpu node" site policy silently reserves 2 cores/node for OS
#           overhead (sbatch prints "setting --ntasks-per-node=190" at
#           submission regardless of what is requested), and OpenMPI's
#           default CORE binding policy refuses to bind more processes than
#           the allocation actually grants -- requesting 192 fails at MPI
#           launch. See branko/KNOWN_ISSUES.md E10.)
#           --qos is REQUIRED here and not optional: zen4_0768's AllowQos list
#           does not include the default "normal" QOS, so a job submitted
#           without an explicit --qos is rejected outright, not defaulted.
#           There is no separate devel *partition* on MUSICA (dev_zen4_0768 as
#           a partition does not exist) -- devel is instead a QOS layered on
#           this same partition: --qos=dev_zen4_0768, capped at MaxWall=00:10:00
#           and 2 nodes. For a --smoke run whose per-step cost is not yet
#           known, prefer the plain --qos=zen4_0768 (3-day cap, no node cap)
#           with an explicit --time bound instead, so an expensive first
#           measurement is not truncated before wrf.exe reports throughput.
#           See branko/KNOWN_ISSUES.md E9.
#
# real.exe is I/O bound, not compute bound. Two nodes is plenty; more mainly
# buys a longer decomposition argument. On MUSICA a single node (192 cores)
# alone is already close to VSC-5's whole 200-task job -- one node is enough.

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
