#!/bin/bash
# Create (and optionally submit) the six 6-hour sensitivity runs of 2026-08-20
# (DECISIONS.md, "The closure is turbulence-starved"): 2025-07-18 01:00 -> 07:00,
# pbl3d_opt=2, compared against the MYNN control (job 8320565) stratified by slope.
#
#   realcase/scripts/setup_experiments_20260820.sh [--submit] [--only X2,X3]
#
#   run  pbl3d_init_opt  pbl3d_l0_min  pbl3d_sk_eps_max   answers
#   X0        0              0             6          current code to 6 h (reproduces 8476273 to 02:00)
#   X1        1              0             6          how much of the deficit is spin-up
#   X2        1              8             6          the candidate fix (l0 floor + equilibrium start)
#   X3        1              4             6          floor-value sensitivity
#   X4        1              8            12          does the ignition throttle still matter once l0 is floored
#   X5        1              8          1000          upper bound on the cap's role (Tier 2 only)
#   X6        0              0             6          X0 + pbl3d_sf_pair=1: the slope-factor energy pairing (A10), 2026-08-21
#
# Each run has its own env file realcase/env/vsc5_X<n>.sh, which overrides
# WRF_OUTPUT_ROOT to $DATA/exp/X<n> so concurrent runs cannot clobber each other
# in temp/branko/ (CLAUDE.md). wrfinput_d01/wrfbdy_d01 are the ones every 3D run
# has used (branko_runs/innval_pbl3d_18th, 23 h of boundary data from 01:00).
set -u -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
RC=$(cd "$HERE/.." && pwd)
DATA=/gpfs/data/fs72996/ewahl
METDIR=$DATA/WPS/metgrid_output
SRC=$DATA/branko_runs/innval_pbl3d_qsq        # where wrfinput/wrfbdy symlinks point
HOURS=6
NODES=2

SUBMIT=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --submit) SUBMIT=1; shift ;;
    --only)   ONLY=$2; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 1 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

declare -A INIT L0MIN CAP WALL PAIR
INIT[X0]=0; L0MIN[X0]=0.0; CAP[X0]=6.0;    WALL[X0]=07:00:00
INIT[X1]=1; L0MIN[X1]=0.0; CAP[X1]=6.0;    WALL[X1]=07:00:00
INIT[X2]=1; L0MIN[X2]=8.0; CAP[X2]=6.0;    WALL[X2]=07:00:00
INIT[X3]=1; L0MIN[X3]=4.0; CAP[X3]=6.0;    WALL[X3]=07:00:00
INIT[X4]=1; L0MIN[X4]=8.0; CAP[X4]=12.0;   WALL[X4]=07:00:00
INIT[X5]=1; L0MIN[X5]=8.0; CAP[X5]=1000.0; WALL[X5]=08:00:00
INIT[X6]=0; L0MIN[X6]=0.0; CAP[X6]=6.0;    WALL[X6]=07:00:00
PAIR[X0]=0; PAIR[X1]=0; PAIR[X2]=0; PAIR[X3]=0; PAIR[X4]=0; PAIR[X5]=0; PAIR[X6]=1

RUNS="X0 X1 X2 X3 X4 X5 X6"
[ -n "$ONLY" ] && RUNS=$(echo "$ONLY" | tr ',' ' ')

WRFIN=$(readlink -f "$SRC/wrfinput_d01"); WRFBDY=$(readlink -f "$SRC/wrfbdy_d01")
for f in "$WRFIN" "$WRFBDY"; do [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }; done

FAIL=0
for X in $RUNS; do
  ENV=$RC/env/vsc5_$X.sh
  RUNDIR=$DATA/branko_runs/innval_pbl3d_$X
  echo; echo "################ $X -> $RUNDIR"
  [ -f "$ENV" ] || { echo "no env file $ENV" >&2; FAIL=1; continue; }

  "$RC/scripts/setup_rundir.sh" "$ENV" "$RUNDIR" pbl3d --met-dir "$METDIR" --hours "$HOURS" || { FAIL=1; continue; }

  ln -sfn "$WRFIN"  "$RUNDIR/wrfinput_d01"
  ln -sfn "$WRFBDY" "$RUNDIR/wrfbdy_d01"
  ln -sfn "$RC/iofields_lscale.txt" "$RUNDIR/iofields_lscale.txt"

  NL=$RUNDIR/namelist.input
  sed -i -E "s/^( pbl3d_init_opt[[:space:]]*=[[:space:]]*)[-0-9.]+,/\1${INIT[$X]},/"       "$NL"
  sed -i -E "s/^( pbl3d_l0_min[[:space:]]*=[[:space:]]*)[-0-9.]+,/\1${L0MIN[$X]},/"        "$NL"
  sed -i -E "s/^( pbl3d_sk_eps_max[[:space:]]*=[[:space:]]*)[-0-9.]+,/\1${CAP[$X]},/"      "$NL"
  sed -i -E "s/^( pbl3d_sf_pair[[:space:]]*=[[:space:]]*)[-0-9.]+,/\1${PAIR[$X]},/"        "$NL"
  sed -i -E "s/^( auxhist24_interval_m[[:space:]]*=[[:space:]]*)[0-9]+,/\1360,/"            "$NL"   # WRFlux stream: one frame per 6 h (KNOWN_ISSUES E15)
  sed -i -E "s/^( iofields_filename[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"iofields_lscale.txt\"/" "$NL"
  for key in pbl3d_init_opt pbl3d_l0_min pbl3d_sk_eps_max pbl3d_sf_pair auxhist24_interval_m iofields_filename history_interval run_hours; do
    grep -E "^ $key[[:space:]]*=" "$NL" | head -1
  done
    # the namelist keys must actually be there (a silent no-op sed would leave the template value)
  grep -qE "^ pbl3d_init_opt[[:space:]]*=[[:space:]]*${INIT[$X]}," "$NL" || { echo "!!! pbl3d_init_opt not set in $NL" >&2; FAIL=1; }
  grep -qE "^ pbl3d_l0_min[[:space:]]*=[[:space:]]*${L0MIN[$X]}," "$NL"  || { echo "!!! pbl3d_l0_min not set in $NL" >&2; FAIL=1; }

  SB=$RUNDIR/submit_wrf.slurm
  sed -i -E "s/^#SBATCH --job-name=.*/#SBATCH --job-name=wrf_$X/"   "$SB"
  sed -i -E "s/^#SBATCH --nodes=.*/#SBATCH --nodes=$NODES/"         "$SB"
  sed -i -E "s/^#SBATCH --time=.*/#SBATCH --time=${WALL[$X]}/"     "$SB"
  grep -q -- '--hint=nomultithread' "$SB" || sed -i "/^#SBATCH --ntasks-per-node=/a #SBATCH --hint=nomultithread" "$SB"
  grep -E "^#SBATCH --(job-name|nodes|ntasks|hint|time)" "$SB"

    # re-validate after the edits (report only)
  python3 "$RC/scripts/prepare_namelist.py" "$NL" --output-root "$(bash -c "source $ENV >/dev/null 2>&1; echo \$WRF_OUTPUT_ROOT")" 2>&1 | grep -E "FATAL|WARN" | head -10

  D=$(find "$RUNDIR" -maxdepth 1 -xtype l 2>/dev/null)
  if [ -n "$D" ]; then echo "!!! dangling symlinks in $RUNDIR:"; echo "$D"; FAIL=1; fi
done

echo
if [ "$FAIL" != 0 ]; then echo "!!! at least one run dir is not clean -- not submitting"; exit 1; fi
for X in $RUNS; do
  RUNDIR=$DATA/branko_runs/innval_pbl3d_$X
  if [ "$SUBMIT" = 1 ]; then
    (cd "$RUNDIR" && sbatch submit_wrf.slurm)
  else
    echo "cd $RUNDIR && sbatch submit_wrf.slurm"
  fi
done
