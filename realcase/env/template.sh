# Copy to env/<yourcluster>.sh and fill in.  Source it, do not execute it.
#
# Everything the build and run scripts need from the cluster is set here, so
# nothing cluster-specific is baked into the namelists or the SLURM scripts.
#
# Read env/levante.sh alongside this -- it is a filled-in, verified example.

# --- compiler + MPI + netCDF ------------------------------------------------
# Use a compiler consistent with the one netcdf-fortran was built with.
# The scheme is built and verified with gcc 11.2; gcc 12 has not been tested.
#
# module load ... > /dev/null 2>&1      <-- REDIRECT, never pipe (KNOWN_ISSUES E1)

module purge                          > /dev/null 2>&1
# module load <compiler>              > /dev/null 2>&1
# module load <mpi>                   > /dev/null 2>&1
# module load <netcdf-c>              > /dev/null 2>&1
# module load <netcdf-fortran>        > /dev/null 2>&1

export NETCDF=$(nf-config --prefix)      # must be the netcdf-FORTRAN prefix
export NETCDF_classic=1
export HDF5=$(nc-config --prefix)

# --- LAPACK/BLAS ------------------------------------------------------------
# REQUIRED.  The 3D PBL closure solves a 10x10 system with LAPACK dgesvx at
# every grid point, and a 4x4 for the moisture side.  WRF's own configure does
# not know about this: build_em_real.sh injects LAPACK_LIBS into configure.wrf
# as LIB_LOCAL.  Without it the link fails with undefined reference to dgesvx_.
#
# Any LAPACK works (netlib, OpenBLAS, MKL).  With MKL use e.g.
#   LAPACK_LIBS="-L${MKLROOT}/lib/intel64 -lmkl_gf_lp64 -lmkl_sequential -lmkl_core"
#
# Include -Wl,-rpath unless the library is on the runtime loader path anyway.
# Without it the link succeeds and wrf.exe dies at startup on the compute node
# with "error while loading shared libraries: liblapack.so.3" -- which is a
# miserable thing to discover from inside a queued job.  build_em_real.sh
# link-tests AND runs a small dgesvx program, so it catches this before the
# compile rather than after.
LAPACK_DIR=/path/to/lapack
export LAPACK_LIBS="-L${LAPACK_DIR}/lib -Wl,-rpath,${LAPACK_DIR}/lib -llapack -lblas"

# --- WPS only ---------------------------------------------------------------
export JASPERLIB=/usr/lib64
export JASPERINC=/usr/include
export WRF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# --- build options ----------------------------------------------------------
# Run ./configure once by hand to see the numbering for your machine; the
# gfortran dmpar entry moves between WRF releases.
export WRF_CONFIGURE_OPTION=34   # Linux x86_64, gfortran, dmpar
export WRF_NEST_OPTION=1

# --- runtime ----------------------------------------------------------------
export MPI_LAUNCHER="srun"       # or "mpirun -np $SLURM_NTASKS"
export SLURM_ACCOUNT_DEFAULT=
export SLURM_PARTITION_DEFAULT=
export CORES_PER_NODE=128
