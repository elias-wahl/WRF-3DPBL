#!/bin/bash
# Build main/real.exe and main/wrf.exe for the ICON-forced Inn Valley case.
#
#   realcase/scripts/build_em_real.sh env/levante.sh [--reconfigure]
#
# What this does that a bare "./configure && ./compile em_real" does not:
#
#   1. Injects LAPACK/BLAS into configure.wrf as LIB_LOCAL.  WRF's configure
#      has no notion of LAPACK, but the 3D PBL closure calls dgesvx at every
#      grid point, so without this the link ends in "undefined reference to
#      dgesvx_" -- or, worse, in EXIT=0 with no executables.
#   2. Strips -DMTN from ARCHFLAGS.  That flag belongs to the em_les test
#      mountain; it is inert for em_real but leaving it in makes configure.wrf
#      diverge from a clean one for no reason.
#   3. Decides success on "Executables successfully built" plus an actual stat
#      of the two binaries, not on the exit status -- WRF's compile returns 0
#      even when the link produced nothing.
#   4. Checks the linked binaries for objects from a foreign toolchain, which
#      is how the gcc-12/mambaforge contamination in KNOWN_ISSUES E1 showed up.
set -u -o pipefail

usage() { sed -n '2,20p' "$0"; exit 1; }

ENVFILE=${1:-}
[ -n "$ENVFILE" ] || usage
shift
RECONFIGURE=0
for a in "$@"; do
  case "$a" in
    --reconfigure) RECONFIGURE=1 ;;
    -h|--help)     usage ;;
    *) echo "unknown argument: $a" >&2; usage ;;
  esac
done

HERE=$(cd "$(dirname "$0")" && pwd)
WRF=$(cd "$HERE/../.." && pwd)
[ -f "$ENVFILE" ] || ENVFILE="$WRF/realcase/$ENVFILE"
[ -f "$ENVFILE" ] || { echo "env file not found: $ENVFILE" >&2; exit 1; }

echo "=== environment: $ENVFILE"
# EESSI's own init chain (init/eessi_defaults) references unset variables
# like EESSI_VERSION_OVERRIDE with no default -- fine under a normal shell,
# fatal under our -u. Drop -u only for the sourcing, not for the rest of
# this script.
set +u
# shellcheck disable=SC1090
. "$ENVFILE"
set -u

: "${NETCDF:?NETCDF is not set -- check your env file}"
: "${LAPACK_LIBS:?LAPACK_LIBS is not set -- the 3D PBL closure needs LAPACK}"
: "${WRF_CONFIGURE_OPTION:?WRF_CONFIGURE_OPTION is not set}"
: "${WRF_NEST_OPTION:=1}"

echo "    NETCDF      = $NETCDF"
echo "    LAPACK_LIBS = $LAPACK_LIBS"
echo "    mpif90      = $(command -v mpif90 || echo MISSING)"
echo "    gfortran    = $(command -v gfortran || echo MISSING)"
command -v mpif90 >/dev/null || { echo "mpif90 not on PATH -- did module load get piped?" >&2; exit 1; }

cd "$WRF" || exit 1

# --- 1. link check for LAPACK before spending an hour on the build ----------
echo "=== checking that LAPACK links"
TMPD=$(mktemp -d)
cat > "$TMPD/t.f90" <<'EOF'
program t
  integer, parameter :: n = 2
  double precision :: a(n,n), af(n,n), b(n), x(n), r(n), c(n), work(4*n)
  double precision :: rcond, ferr(1), berr(1)
  integer :: ipiv(n), iwork(n), info
  character :: equed
  a = reshape([2.d0,0.d0,0.d0,2.d0],[n,n]); b = [2.d0,4.d0]
  call dgesvx('E','N',n,1,a,n,af,n,ipiv,equed,r,c,b,n,x,n,rcond,ferr,berr,work,iwork,info)
  if (info /= 0 .or. abs(x(1)-1.d0) > 1.d-10) stop 1
end program t
EOF
if ! gfortran -o "$TMPD/t" "$TMPD/t.f90" $LAPACK_LIBS > "$TMPD/log" 2>&1; then
  echo "!!! LAPACK link test FAILED -- fix LAPACK_LIBS in $ENVFILE before building" >&2
  cat "$TMPD/log" >&2
  rm -rf "$TMPD"; exit 1
fi
if ! "$TMPD/t" > "$TMPD/runlog" 2>&1; then
  RC=$?
  cat "$TMPD/runlog" >&2
  if grep -q 'error while loading shared libraries' "$TMPD/runlog"; then
    echo "!!! LAPACK links but does not LOAD. Add -Wl,-rpath,<lapack lib dir> to" >&2
    echo "    LAPACK_LIBS in $ENVFILE. Without it wrf.exe builds fine and then dies" >&2
    echo "    at startup inside the queued job." >&2
  else
    echo "!!! the dgesvx test program failed (rc=$RC) -- LAPACK is present but wrong" >&2
  fi
  rm -rf "$TMPD"; exit 1
fi
rm -rf "$TMPD"
echo "    dgesvx links, loads and gives the right answer"

# --- 2. configure ----------------------------------------------------------
if [ ! -f configure.wrf ] || [ "$RECONFIGURE" = 1 ]; then
  echo "=== ./clean -a  (full clean, configure.wrf will be regenerated)"
  ./clean -a > /dev/null 2>&1
  echo "=== ./configure  (option $WRF_CONFIGURE_OPTION, nesting $WRF_NEST_OPTION)"
  printf '%s\n%s\n' "$WRF_CONFIGURE_OPTION" "$WRF_NEST_OPTION" | ./configure
  [ -f configure.wrf ] || { echo "!!! configure produced no configure.wrf" >&2; exit 1; }
else
  echo "=== ./clean  (configure.wrf kept; pass --reconfigure to regenerate it)"
  ./clean > /dev/null 2>&1
fi

# --- 3. patch configure.wrf ------------------------------------------------
echo "=== patching configure.wrf"
python3 - "$WRF/configure.wrf" "$LAPACK_LIBS" <<'PYEOF'
import sys
path, lapack = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()

# LIB_LOCAL: LAPACK/BLAS for the 3D PBL closure (dgesvx).  Done line by line
# rather than with a multiline regex -- python's \s matches newlines, so
# ^LIB_LOCAL\s*=\s*(.*)$ silently runs past the end of a blank LIB_LOCAL and
# appends the libraries to whatever line comes next.
done = False
for i, line in enumerate(lines):
    if not line.startswith('LIB_LOCAL'):
        continue
    key, _, cur = line.partition('=')
    # Test for the exact string we are about to add, not for library *names*.
    # The name sniff missed FlexiBLAS -- 'flexiblas' contains none of 'lapack',
    # 'mkl' or 'openblas' -- so every rebuild appended another copy and
    # LIB_LOCAL grew without bound (three copies by 2026-08-19). See
    # KNOWN_ISSUES E13. Keep the name sniff as a fallback for the case where
    # configure.wrf already carries a *different* LAPACK than ours.
    if lapack.strip() and lapack.strip() in cur:
        print('    LIB_LOCAL   already has exactly these libs, left alone')
    elif 'lapack' in cur or 'mkl' in cur or 'openblas' in cur or 'flexiblas' in cur:
        print('    LIB_LOCAL   already has a LAPACK, left alone:%s' % cur.rstrip())
    else:
        lines[i] = '%s= %s' % (key, (cur.strip() + ' ' + lapack).strip())
        print('    LIB_LOCAL   <- %s' % lines[i].partition('=')[2].strip())
    done = True
    break
if not done:
    lines.append('LIB_LOCAL       = %s' % lapack)
    print('    LIB_LOCAL   <- %s   (appended, configure.wrf had no LIB_LOCAL)' % lapack)

# ARCHFLAGS: -DMTN is the em_les test mountain, not wanted for em_real.
if any('-DMTN' in l for l in lines):
    lines = [l.replace(' -DMTN', '') for l in lines]
    print('    ARCHFLAGS   <- removed -DMTN')

open(path, 'w').write('\n'.join(lines) + '\n')
PYEOF
grep -m1 '^LIB_LOCAL' configure.wrf

# --- 4. compile ------------------------------------------------------------
LOG="$WRF/compile_em_real.log"
# Compile SERIALLY by default. This is not conservatism for its own sake:
# -j 16 was tried on MUSICA 2026-08-19 (job 89218) and FAILED in 4.5 min with
# "Cannot open module file 'ccpp_kind_types.mod' / 'bl_shinhong.mod' /
# 'module_pbl_driver.mod'" -- the classic Fortran parallel-build race, where a
# file is compiled before the module it USEs has been written. The modules that
# raced are all stock WRF phys/ ones, i.e. it is WRF's own Makefile dependency
# graph that is incomplete and relies on serial ordering, not anything this
# fork added. See KNOWN_ISSUES E12.
#
# Do not "just lower -j" without reading E12 first: a race does not always fail
# loudly. It can also compile a file against a half-written .mod and produce a
# subtly wrong object, which is far worse here than a slow build -- this tree
# is used to diagnose a numerical instability, and a miscompiled binary would
# poison exactly that.
JOBS="${WRF_BUILD_JOBS:-1}"
if [ "$JOBS" = 1 ]; then
  echo "=== ./compile em_real   (serial, ~30-60 min; log: $LOG)"
else
  echo "=== ./compile -j $JOBS em_real   (log: $LOG) -- SEE KNOWN_ISSUES E12"
fi
echo "    do not poll with pgrep -f 'compile em_real',"
echo "    the pattern matches the poller itself (KNOWN_ISSUES E2)"
./compile -j "$JOBS" em_real > "$LOG" 2>&1
COMPILE_RC=$?

# --- 5. verify -------------------------------------------------------------
echo "=== verifying"
OK=1
if grep -q 'Executables successfully built' "$LOG"; then
  echo "    log says: Executables successfully built"
else
  echo "!!! 'Executables successfully built' not in the log (compile rc=$COMPILE_RC)"
  OK=0
fi
for exe in main/real.exe main/wrf.exe main/ndown.exe; do
  if [ -x "$exe" ]; then
    printf '    %-16s %s\n' "$(basename "$exe")" "$(stat -c '%y  %s bytes' "$exe")"
  else
    echo "!!! missing: $exe"
    [ "$exe" = main/ndown.exe ] || OK=0
  fi
done

if [ -x main/wrf.exe ]; then
  echo "=== toolchain check on our own compiled objects"
  # Scan the .o files WE compiled, not the linked exe -- on EESSI (and most
  # Linux systems generally) the final binary statically pulls in crt
  # startup objects from the base/compat-layer glibc, which legitimately
  # carries a different GCC signature (on MUSICA: "GCC: (Gentoo ...)" from
  # EESSI's compat layer) than the GCCcore module used to build WRF itself.
  # That is expected and does not indicate mixed-toolchain contamination;
  # see KNOWN_ISSUES E1 (the real VSC-5 mambaforge case, caught this way)
  # vs the EESSI false positive this replaced.
  if command -v strings > /dev/null; then
    FOREIGN=$(find . -name '*.o' -newer configure.wrf 2>/dev/null | xargs -r strings 2>/dev/null | grep -oE 'GCC: \(.*\) [0-9]+\.[0-9]+\.[0-9]+' | sort -u)
    if [ -n "$FOREIGN" ]; then
      echo "$FOREIGN" | sed 's/^/    /'
      if [ "$(echo "$FOREIGN" | wc -l)" -gt 1 ]; then
        echo "!!! more than one GCC version among our own compiled objects -- mixed toolchain, see KNOWN_ISSUES E1"
        OK=0
      fi
    else
      echo "    (no GCC version strings found -- skipped)"
    fi
  fi
  if command -v ldd > /dev/null && ldd main/wrf.exe | grep -qiE 'conda|mambaforge|miniforge'; then
    echo "!!! wrf.exe links against a conda/mambaforge library:"
    ldd main/wrf.exe | grep -iE 'conda|mambaforge|miniforge' | sed 's/^/    /'
    OK=0
  fi
fi

if [ "$OK" = 1 ]; then
  echo "=== BUILD OK"
  echo "    next: realcase/scripts/setup_rundir.sh $ENVFILE <rundir> pbl3d"
else
  echo "=== BUILD FAILED -- first errors from $LOG:"
  grep -iE 'error:|catastrophic|undefined reference|fatal error|cannot find -l' "$LOG" | head -20
  exit 1
fi
