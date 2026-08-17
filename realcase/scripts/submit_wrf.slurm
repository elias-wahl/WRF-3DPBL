#!/bin/bash
#SBATCH --job-name=wrf_innval
#SBATCH --output=wrf.%j.out
#SBATCH --error=wrf.%j.err
#SBATCH --nodes=8
#SBATCH --ntasks-per-node=128
#SBATCH --time=12:00:00
#---- EDIT THESE TWO, they ship blank on purpose -----------------------------
#SBATCH --account=CHANGEME
#SBATCH --partition=CHANGEME
#-----------------------------------------------------------------------------
# Levante:  --account=bm1236        --partition=compute      (128 cores/node)
# VSC-5:    --account=<projectid>   --partition=zen3_0512    (128 cores/node)
#           add  #SBATCH --qos=zen3_0512
#
# Sizing, for the 601 x 501 x 81 domain at dx=500 m and dt=3 s:
#
#   1024 ranks (8 nodes) gives roughly 19 x 16 points per patch. Do not go much
#   finer: the 3D PBL exchanges wider halos than the Smagorinsky path does
#   (HALO_EM_PBL3D_5), and once a patch is comparable to the halo the run is all
#   communication.
#
#   pbl3d_opt=2 solves a 10x10 and a 4x4 linear system at every grid point on
#   every timestep. Expect it to be a good deal slower per step than the MYNN
#   control -- measure it with a --smoke run before committing to 24 h rather
#   than guessing. 24 h at dt=3 s is 28800 steps.
#
#   restart_interval=180 (3 h) in the namelist exists so this can be chained
#   across the queue limit. To continue: set restart=.true. in namelist.input,
#   set the start time to the restart file's time, and resubmit.

set -u
cd "$SLURM_SUBMIT_DIR" || exit 1
. ./env.sh

ulimit -s unlimited
export OMP_NUM_THREADS=1

# The MY closure calls LAPACK dgesvx per grid point and inspects INFO itself
# (Tier 2 backs the length scale off on a degenerate system). Do not enable
# FPE trapping here -- intermediate NaNs in the back-off path are expected and
# handled.

[ -f wrfinput_d01 ] || { echo "no wrfinput_d01 -- run submit_real.slurm first" >&2; exit 1; }
[ -f wrfbdy_d01 ]   || { echo "no wrfbdy_d01 -- run submit_real.slurm first" >&2; exit 1; }

echo "=== wrf.exe on $SLURM_NTASKS ranks, $(date)"
rm -f rsl.out.* rsl.error.*
${MPI_LAUNCHER:-srun} ./wrf.exe
RC=$?

echo "=== wrf.exe returned $RC, $(date)"
if grep -q 'SUCCESS COMPLETE WRF' rsl.out.0000 2>/dev/null; then
  echo "=== SUCCESS COMPLETE WRF"
else
  echo "!!! wrf.exe did not finish. First errors:"
  grep -iE 'error|fatal|cfl|abort' rsl.error.0000 2>/dev/null | head -30
fi

echo
echo "=== throughput"
grep 'Timing for main' rsl.out.0000 2>/dev/null | tail -5
awk '/Timing for main/ {s += $9; n++} END {if (n) printf "    mean %.3f s/step over %d steps\n", s/n, n}' \
    rsl.out.0000 2>/dev/null

echo
echo "=== 3D PBL solver health (per-gridpoint diagnostics are in wrfout)"
echo "    PBL3D_T1_RATIO  < 1 where the Durbin strain limit bound the length scale"
echo "    PBL3D_T2_STEPS  > 0 where the 10x10 system needed a length-scale back-off"
echo "    PBL3D_T3_FLAGS  > 0 where realizability had to be enforced"
echo "    PBL3D_COND_A        condition number of the 10x10 system"
echo "    A healthy run has COND_A of order 10-500. Order 1e5+ means the closure"
echo "    is being solved far outside its validity range."
[ "$RC" = 0 ] || exit "$RC"
