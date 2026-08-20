#!/bin/bash
#SBATCH --job-name=wrf_build
#SBATCH --output=build.%j.out
#SBATCH --error=build.%j.err
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=128
#SBATCH --hint=nomultithread
#SBATCH --time=02:00:00
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512
# ---------------------------------------------------------------------------
# Build WRF on a compute node instead of the login node.
#
# Why a batch job rather than tmux on the login node (which is what
# realcase/README.md describes): a parallel compile is exactly the kind of
# thing login nodes throttle or kill, and the node here is exclusive, so -j
# does not contend with other users. It also survives losing the session
# without needing tmux at all.
#
# Header is VSC-5 (zen3_0512): 128 PHYSICAL cores/node -- the node is 8
# sockets x 16 cores with ThreadsPerCore=2, so SLURM reports CPUTot=256 and
# --hint=nomultithread keeps one task per physical core. --qos is explicit
# because zen3_0512's devel counterpart (zen3_0512_devel, MaxWall 00:10:00,
# 5 nodes) would truncate an hour-long build.
#
# Reverted from MUSICA's zen4_0768 / p201110 / --ntasks-per-node=190 on
# 2026-08-19 when the campaign moved back here. Do NOT reinstate the 190: it
# encoded MUSICA's "full cpu node" policy (KNOWN_ISSUES E10), which does not
# exist on VSC-5.
#
# The task count is cosmetic for the build itself -- only one process is
# launched (no srun/mpirun) and the build is serial by default anyway
# (WRF_BUILD_JOBS=1, KNOWN_ISSUES E12).
#
# Usage:  sbatch realcase/scripts/build_em_real.slurm realcase/env/vsc5.sh
# ---------------------------------------------------------------------------
set -u
cd "$SLURM_SUBMIT_DIR" || exit 1

ENVFILE="${1:-realcase/env/vsc5.sh}"

export WRF_BUILD_JOBS="${WRF_BUILD_JOBS:-1}"

echo "=== build starting $(date)"
echo "    node       : $SLURMD_NODENAME"
echo "    cores      : $(nproc) (node is exclusive)"
echo "    -j level   : $WRF_BUILD_JOBS"
echo "    env file   : $ENVFILE"
echo

realcase/scripts/build_em_real.sh "$ENVFILE"
RC=$?

echo
echo "=== build finished $(date), rc=$RC"
exit "$RC"
