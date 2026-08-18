# Build/run environment for VSC-5 (zen3_0512), gcc 12.2 + OpenMPI 4.1.6.
# Source it, do not execute it:  . env/vsc5.sh
#
# `module load` MUST be redirected, never piped (KNOWN_ISSUES E1).

module purge                                                  > /dev/null 2>&1
module load gcc/12.2.0-gcc-9.5.0-ohbahza                      > /dev/null 2>&1
module load openmpi/4.1.6-gcc-12.2.0-exh7lqk                  > /dev/null 2>&1
module load netcdf-c/4.9.0-gcc-12.2.0-pdqbhir                 > /dev/null 2>&1
module load netcdf-fortran/4.6.0-gcc-12.2.0-t2mf7lo            > /dev/null 2>&1
module load zlib/1.2.13-gcc-12.2.0-gf7pqwu                    > /dev/null 2>&1
module load netlib-lapack/3.10.1-gcc-12.2.0-4qrxbdw            > /dev/null 2>&1
# prepare_namelist.py needs Python >= 3.7 (subprocess capture_output=); the
# system default python3 here is 3.6. check_wrfinput.py needs netCDF4/xarray.
module load python/3.9.15-gcc-12.2.0-3sr5utz                  > /dev/null 2>&1
module load py-netcdf4/1.5.8-gcc-12.2.0-qm2nhum                > /dev/null 2>&1

export NETCDF=$(nf-config --prefix)
export NETCDF_classic=1
export HDF5=$(nc-config --prefix)

# Spack modules on VSC-5 do NOT export LD_LIBRARY_PATH (they assume RPATH,
# which WRF's own build does not add for NetCDF/HDF5/zlib -- only
# LIB_LOCAL/LAPACK below gets an explicit -Wl,-rpath). Without this,
# wrf.exe/real.exe link fine and then die on the compute node with
# "error while loading shared libraries: libnetcdff.so.7". Spack DOES set
# LIBRARY_PATH (build-time linker search path) for every loaded module, so
# reuse it wholesale for LD_LIBRARY_PATH rather than hand-picking paths --
# this automatically covers HDF5/zlib/gcc runtime libs too. Same class of
# fix already used in run_files/RUN_WRF.sh (there, just for netcdf-c).
export LD_LIBRARY_PATH="${LIBRARY_PATH}:${LD_LIBRARY_PATH:-}"

# Some of WRF's vendored external/io_grib1 C tools (MEL_grib1, WGRIB) hardcode
# CC="gcc" in their own Makefiles, bypassing configure.wrf's chosen compiler
# entirely and resolving "gcc" via PATH at build time instead. Pin CC/FC to
# the exact Spack toolchain and hard-prepend its bin dir so nothing later in
# an hour-long build can shadow it -- this is what caused the mixed
# GCC 8.5.0 / 12.2.0 toolchain build_em_real.sh's verification step caught.
export CC=$(command -v gcc)
export CXX=$(command -v g++)
export FC=$(command -v gfortran)
export F77=$(command -v gfortran)
export F90=$(command -v gfortran)
export PATH="$(dirname "$CC"):$PATH"

# LAPACK/BLAS -- required, the 3D PBL closure calls dgesvx at every grid point.
# netlib-lapack on VSC-5 ships both liblapack.so and libblas.so in the same
# lib64 dir. -Wl,-rpath is not optional: without it wrf.exe links fine and
# dies at startup on the compute node with "error while loading shared
# libraries: liblapack.so.3".
LAPACK_DIR=/gpfs/opt/sw/zen/spack-0.19.0/opt/spack/linux-almalinux8-zen3/gcc-12.2.0/netlib-lapack-3.10.1-4qrxbdwldfgikj6faaab3obvgzqhwqxi
export LAPACK_LIBS="-L${LAPACK_DIR}/lib64 -Wl,-rpath,${LAPACK_DIR}/lib64 -llapack -lblas"

# WPS only
export JASPERLIB=/gpfs/data/fs72996/ewahl/LIBS/jasper/lib
export JASPERINC=/gpfs/data/fs72996/ewahl/LIBS/jasper/include
export WRF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

export WRF_CONFIGURE_OPTION=34   # Linux x86_64, gfortran, dmpar -- verified by hand for this branch
export WRF_NEST_OPTION=1         # basic nesting

# Runtime
# Single-quoted so $SLURM_NTASKS stays literal here; submit_real.slurm /
# submit_wrf.slurm now use `eval` to resolve it at job-launch time. Matches
# the "mpirun -np $SLURM_NTASKS" pattern already proven in run_files/RUN_WRF.sh.
export MPI_LAUNCHER='mpirun -np $SLURM_NTASKS'
export SLURM_ACCOUNT_DEFAULT=
export SLURM_PARTITION_DEFAULT=zen3_0512
export CORES_PER_NODE=100        # matches --ntasks-per-node used elsewhere in run_files (hint=nomultithread)
