#!/bin/bash
#SBATCH --job-name=wrf_build
#SBATCH --output=build.%j.out
#SBATCH --error=build.%j.err
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=190
#SBATCH --hint=nomultithread
#SBATCH --time=02:00:00
#SBATCH --account=p201110
#SBATCH --partition=zen4_0768
#SBATCH --qos=zen4_0768
# ---------------------------------------------------------------------------
# Build WRF on a compute node instead of the login node.
#
# Why a batch job rather than tmux on the login node (which is what
# realcase/README.md describes): a parallel compile is exactly the kind of
# thing login nodes throttle or kill, and the node here is exclusive, so -j
# does not contend with other users. It also survives losing the session
# without needing tmux at all.
#
# The #SBATCH header must request --ntasks-per-node=190 even though the build
# is a single serial process: MUSICA's "full cpu node" policy rewrites
# --ntasks-per-node and --cpus-per-task on any exclusive allocation and
# REJECTS the job outright ("Requested node configuration is not available")
# if you ask for something else, e.g. --cpus-per-task=32. Same policy as
# KNOWN_ISSUES E10. It costs nothing here: the node is exclusive, only one
# process is actually launched (no srun/mpirun), and make -j forks freely
# across all cores regardless of the task count SLURM was told about.
#
# Usage:  sbatch realcase/scripts/build_em_real.slurm realcase/env/musica.sh
# ---------------------------------------------------------------------------
set -u
cd "$SLURM_SUBMIT_DIR" || exit 1

ENVFILE="${1:-realcase/env/musica.sh}"

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
