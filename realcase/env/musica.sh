# Build/run environment for MUSICA Innsbruck (zen4_0768), EESSI 2025.06.
# Source it, do not execute it:  . env/musica.sh
#
# `module load` MUST be redirected, never piped (KNOWN_ISSUES E1).
#
# Every value below was probed on the machine on 2026-08-19, and the dgesvx
# link+run test at the bottom of this comment block was actually executed
# there, not assumed.

# EESSI is a CVMFS-mounted stack; its init sets MODULEPATH, so it has to come
# before any module command. Do NOT `module purge` after this -- that strips
# the EESSI paths back out and every load below then fails silently.
source /cvmfs/software.eessi.io/versions/2025.06/init/bash  > /dev/null 2>&1

# Toolchain: gompi-2024a = GCC 13.3.0 + OpenMPI 5.0.3.
#
# Deliberately NOT the newest. EESSI also offers gompi-2025a (GCC 14.2.0) and
# gompi-2025b (GCC 14.3.0), but:
#   - this scheme is verified with gcc 11.2 and was built on VSC-5 with 12.2,
#     so 13.3 is the smallest jump available here;
#   - gompi-2025b has no netCDF-Fortran at all, which WRF needs;
#   - GCC 14 tightens argument-mismatch diagnostics further, and WRF's own
#     configure only knows to pass -fallow-argument-mismatch for GCC >= 10.
# If 13.3.0 ever fails, 2025a is the next rung up, not 2025b.
module load netCDF-Fortran/4.6.1-gompi-2024a               > /dev/null 2>&1
module load FlexiBLAS/3.4.4-GCC-13.3.0                     > /dev/null 2>&1
module load JasPer/4.2.4-GCCcore-13.3.0                    > /dev/null 2>&1

export NETCDF=$(nf-config --prefix)      # netCDF-Fortran 4.6.1
export NETCDF_classic=1
export HDF5=$(nc-config --prefix)        # netCDF-C 4.9.2

# EESSI/Lmod modules do set LD_LIBRARY_PATH properly (unlike VSC-5's Spack
# modules, which needed LIBRARY_PATH copied across by hand). Kept as a
# defensive no-op: if a future EESSI release stops exporting it, wrf.exe would
# otherwise link fine and die on the compute node with
# "error while loading shared libraries: libnetcdff.so.7".
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}${LIBRARY_PATH:+:$LIBRARY_PATH}"

# Pin the compilers. WRF's vendored external/io_grib1 tools (MEL_grib1, WGRIB)
# hardcode CC="gcc" in their own Makefiles and resolve it via PATH at build
# time, bypassing configure.wrf entirely -- that is what produced the mixed
# GCC 8.5.0/12.2.0 build on VSC-5 that build_em_real.sh caught.
export CC=$(command -v gcc)
export CXX=$(command -v g++)
export FC=$(command -v gfortran)
export F77=$(command -v gfortran)
export F90=$(command -v gfortran)
export PATH="$(dirname "$CC"):$PATH"

# LAPACK/BLAS -- required, the 3D PBL closure calls dgesvx at every grid point.
# There is no standalone LAPACK module in EESSI; FlexiBLAS provides both the
# BLAS and LAPACK APIs in one library, so -lflexiblas replaces "-llapack -lblas".
#
# Verified on MUSICA, not assumed: dgesvx_ is present in libflexiblas.so, and a
# test program calling dgesvx('E','N',...) compiled, linked and ran, returning
# the correct solution. -Wl,-rpath is included for the same reason as
# everywhere else in this project.
export LAPACK_LIBS="-L${EBROOTFLEXIBLAS}/lib -Wl,-rpath,${EBROOTFLEXIBLAS}/lib -lflexiblas"

# WPS only
export JASPERLIB=${EBROOTJASPER}/lib
export JASPERINC=${EBROOTJASPER}/include
export WRF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# NOT verified from VSC-5 -- run ./configure by hand once on MUSICA and read the
# gfortran/dmpar entry number off the menu. 34 is the VSC-5 value and the
# numbering moves between WRF releases and platforms. This is the one setting
# in this file that still needs a human on the far side.
export WRF_CONFIGURE_OPTION=34   # <-- CONFIRM THIS BEFORE THE FIRST BUILD
export WRF_NEST_OPTION=1

# Output root. Everything below it is fixed by convention and identical on
# every cluster: temp/branko/ for the live run, wrf_output/<jobid>/ for the
# archive. See "Where the output goes" in realcase/README.md.
export WRF_OUTPUT_ROOT=/data/fs201110/ew24501

# Runtime.
# Single-quoted so $SLURM_NTASKS stays literal here; submit_real.slurm and
# submit_wrf.slurm use `eval` to resolve it at job-launch time.
export MPI_LAUNCHER='mpirun -np $SLURM_NTASKS'
export SLURM_ACCOUNT_DEFAULT=p201110
export SLURM_PARTITION_DEFAULT=zen4_0768

# 192 PHYSICAL cores per node (8 sockets x 24 cores); SLURM reports CPUTot=384
# because ThreadsPerCore=2. Use the physical count and --hint=nomultithread --
# WRF gains nothing from SMT and loses cache. Nodes have 770 GB, so memory is
# not the constraint it was on VSC-5.
#
# For scale: VSC-5 ran this case on 2 nodes x 100 tasks = 200. One MUSICA node
# is 192 cores, so the same job is roughly a single node here. Measure with
# --smoke before choosing; submit_wrf.slurm prints the mean s/step.
export CORES_PER_NODE=192

# Devel queue for smoke tests, the MUSICA equivalent of VSC-5's
# zen3_0512_devel: dev_zen4_0768. zen4_0768 itself has MaxTime=UNLIMITED and a
# 1-day default, so the production run does not need chaining the way it did on
# VSC-5 -- though restart_interval is still set, which does no harm.
export SLURM_PARTITION_DEVEL=dev_zen4_0768

# check_wrfinput.py needs the netCDF4 python bindings, which in EESSI only exist
# for the foss-2025a toolchain (netcdf4-python/1.7.2-foss-2025a) and would drag
# in GCC 14.2.0, conflicting with the build toolchain above. Do NOT load it
# here. It is a standalone diagnostic, so run it in a separate shell:
#
#   source /cvmfs/software.eessi.io/versions/2025.06/init/bash
#   module load netcdf4-python/1.7.2-foss-2025a
#   python3 realcase/scripts/check_wrfinput.py wrfinput_d01
#
# prepare_namelist.py is unaffected -- it only needs python3 >= 3.7 and ncdump,
# both of which the modules above already provide.
