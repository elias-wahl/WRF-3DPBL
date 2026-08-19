#!/bin/bash
#SBATCH --job-name=wrf_innval
#SBATCH --output=wrf.%j.out
#SBATCH --error=wrf.%j.err
#SBATCH --nodes=8
#SBATCH --ntasks-per-node=128
#SBATCH --time=12:00:00
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
START_TIME=$(date)
# eval, not a bare expansion: MPI_LAUNCHER may embed $SLURM_NTASKS (e.g.
# "mpirun -np $SLURM_NTASKS"), which needs a second expansion pass to resolve.
eval "${MPI_LAUNCHER:-srun} ./wrf.exe"
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

# --- archive output, matching run_files/RUN_WRF.sh's convention so branko's
# output lands next to the other forks' and post-processing in proc/ finds it
# the same way: $WRF_OUTPUT_ROOT/wrf_output/<jobid>/, with a
# job_info.txt and a copy of the namelist. history_outname/auxhist24_outname
# both point at the same temp scratch dir, so this reads that dir out of the
# namelist rather than hardcoding it. Always archives, even on failure, so a
# partial/crashed run's output isn't lost.
echo
echo "=== archiving output"
OUTDIR="${WRF_OUTPUT_ROOT:?WRF_OUTPUT_ROOT is not set -- add it to your env file}/wrf_output/$SLURM_JOB_ID"
mkdir -p "$OUTDIR"
{
  echo "Job ID: $SLURM_JOB_ID"
  echo "Start time: $START_TIME"
  echo "WRF run path: $SLURM_SUBMIT_DIR"
  echo "Namelist used: $SLURM_SUBMIT_DIR/namelist.input"
} > "$OUTDIR/job_info.txt"
cp namelist.input "$OUTDIR/"
TEMP_OUT_DIR=$(grep -m1 'history_outname' namelist.input | sed -E "s/^[^=]*=\s*['\"]([^'\"]*)['\"].*/\1/" | xargs dirname)
if [ -n "$TEMP_OUT_DIR" ] && [ -d "$TEMP_OUT_DIR" ]; then
  mv "$TEMP_OUT_DIR"/wrfout* "$OUTDIR/" 2>/dev/null
  mv "$TEMP_OUT_DIR"/meanout* "$OUTDIR/" 2>/dev/null
fi
echo "    archived to $OUTDIR"

[ "$RC" = 0 ] || exit "$RC"
