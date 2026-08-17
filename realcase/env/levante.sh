# Build/run environment for DKRZ Levante (gcc 11.2 + OpenMPI 4.1.2).
# Known good: this is the toolchain the 3D PBL scheme was built and verified
# with (job 26586607).  Source it, do not execute it:  . env/levante.sh
#
# `module load` MUST be redirected, never piped.  Piping runs it in a subshell
# and silently discards it, after which mpif90 resolves to the mambaforge gcc 12
# and the link fails with EXIT=0 and no executables.  See KNOWN_ISSUES.md E1.

module purge                                                  > /dev/null 2>&1
module load gcc/11.2.0-gcc-11.2.0                             > /dev/null 2>&1
module load openmpi/4.1.2-gcc-11.2.0                          > /dev/null 2>&1
module load netcdf-c/4.8.1-openmpi-4.1.2-gcc-11.2.0           > /dev/null 2>&1
module load netcdf-fortran/4.5.3-openmpi-4.1.2-gcc-11.2.0     > /dev/null 2>&1

export NETCDF=$(nf-config --prefix)
export NETCDF_classic=1
export HDF5=$(nc-config --prefix)

# LAPACK/BLAS -- required, the 3D PBL closure calls dgesvx at every grid point.
# -Wl,-rpath is not optional: no module here puts liblapack.so.3 on the runtime
# loader path, so without it wrf.exe links fine and then dies at startup with
# "error while loading shared libraries: liblapack.so.3".
export LAPACK_DIR=/sw/spack-levante/netlib-lapack-3.9.1-y24c4j
export LAPACK_LIBS="-L${LAPACK_DIR}/lib64 -Wl,-rpath,${LAPACK_DIR}/lib64 -llapack -lblas"

# WPS only
export JASPERLIB=/usr/lib64
export JASPERINC=/usr/include
export WRF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# git is not on the default PATH here
export PATH=/sw/spack-levante/git-2.50.1-h5tkvy/bin:$PATH

export WRF_CONFIGURE_OPTION=34   # Linux x86_64, gfortran, dmpar
export WRF_NEST_OPTION=1         # basic nesting

# Runtime
export MPI_LAUNCHER="srun"
export SLURM_ACCOUNT_DEFAULT=bm1236
export SLURM_PARTITION_DEFAULT=compute
export CORES_PER_NODE=128
