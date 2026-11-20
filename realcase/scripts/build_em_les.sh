#!/bin/bash
# Serial em_les build (ideal.exe + wrf.exe) with the same configure option and configure.wrf patches
# as realcase/scripts/build_em_real.sh: LAPACK into LIB_LOCAL (for NCAR's dgesvx), -DMTN removed.
#   build_em_les.sh <wrf tree> <env file>
set -u -o pipefail
WRF=$1; ENVFILE=$2
set +u; . "$ENVFILE"; set -u
cd "$WRF" || exit 1
echo "=== $(date) host $(hostname) tree $WRF"
./clean -a > /dev/null 2>&1
printf '%s\n%s\n' "$WRF_CONFIGURE_OPTION" "$WRF_NEST_OPTION" | ./configure > configure_em_les.log 2>&1
[ -f configure.wrf ] || { echo "no configure.wrf"; exit 1; }
python3 - "$WRF/configure.wrf" "$LAPACK_LIBS" <<'PYEOF'
import sys
path, lapack = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
for i, line in enumerate(lines):
    if line.startswith('LIB_LOCAL'):
        key, _, cur = line.partition('=')
        if lapack.strip() not in cur:
            lines[i] = '%s= %s' % (key, (cur.strip() + ' ' + lapack).strip())
        print('LIB_LOCAL <-', lines[i].partition('=')[2].strip()); break
else:
    lines.append('LIB_LOCAL       = %s' % lapack)
if any('-DMTN' in l for l in lines):
    lines = [l.replace(' -DMTN', '') for l in lines]; print('removed -DMTN')
open(path, 'w').write('\n'.join(lines) + '\n')
PYEOF
grep -m1 '^LIB_LOCAL' configure.wrf
echo "=== $(date) ./compile -j 1 em_les"
./compile -j 1 em_les > compile_em_les.log 2>&1
echo "=== $(date) compile rc=$?"
grep -q 'Executables successfully built' compile_em_les.log && echo "log: Executables successfully built" || echo "!!! no success line"
ls -l main/ideal.exe main/wrf.exe
grep -iE 'error:|undefined reference|fatal error' compile_em_les.log | head -20
echo "=== done $(date)"
