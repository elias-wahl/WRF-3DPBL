#!/bin/bash
# Build a ready-to-submit WRF run directory for the ICON-forced Inn Valley case.
#
#   realcase/scripts/setup_rundir.sh <envfile> <rundir> <pbl3d|mynn> \
#        --geo /path/to/geo_em_d01.nc --met-dir /path/to/met_em [--hours N] [--smoke]
#
# It links the run/ tables and the executables, links the met_em files, drops in
# the right namelist, syncs the WPS-derived values into it with
# prepare_namelist.py, and copies the SLURM scripts.  Nothing is copied that
# would go stale: tables and executables are symlinks back into the source tree,
# so a rebuild is picked up without redoing the run directory.
#
#   --hours N   run length in hours (default: whatever the met_em files cover)
#   --smoke     1 h run, output every 10 min -- use this first to measure
#               throughput and confirm stability before queueing the full day
#   --qsq-diag  add the 1-minute q^2 budget stream (auxhist23) for OPEN_ISSUES
#               A9. Needs a build newer than the r -> rh Registry promotion.
set -u -o pipefail

usage() { sed -n '2,18p' "$0"; exit 1; }
[ $# -ge 3 ] || usage

ENVFILE=$1; RUNDIR=$2; CONFIG=$3; shift 3
GEO=""; METDIR=""; HOURS=""; SMOKE=0; QSQDIAG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --geo)     GEO=$2; shift 2 ;;
    --met-dir) METDIR=$2; shift 2 ;;
    --hours)   HOURS=$2; shift 2 ;;
    --smoke)   SMOKE=1; shift ;;
    --qsq-diag) QSQDIAG=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

case "$CONFIG" in pbl3d|mynn) ;; *) echo "config must be pbl3d or mynn" >&2; exit 1 ;; esac

HERE=$(cd "$(dirname "$0")" && pwd)
RC=$(cd "$HERE/.." && pwd)
WRF=$(cd "$RC/.." && pwd)
[ -f "$ENVFILE" ] || ENVFILE="$RC/$ENVFILE"
[ -f "$ENVFILE" ] || { echo "env file not found: $ENVFILE" >&2; exit 1; }
# Resolve to an absolute path -- env.sh below embeds this string verbatim,
# and it gets sourced from inside $RUNDIR (a different cwd), so a relative
# path here would silently fail to source at job-launch time.
ENVFILE=$(cd "$(dirname "$ENVFILE")" && pwd)/$(basename "$ENVFILE")
# EESSI's init chain references unset variables (e.g. EESSI_VERSION_OVERRIDE
# in init/eessi_defaults) with no default -- fatal under our -u. Drop -u only
# for the sourcing.
set +u
# shellcheck disable=SC1090
. "$ENVFILE"
set -u

for exe in real.exe wrf.exe; do
  [ -x "$WRF/main/$exe" ] || { echo "$WRF/main/$exe is missing -- run build_em_real.sh first" >&2; exit 1; }
done

mkdir -p "$RUNDIR" || exit 1
RUNDIR=$(cd "$RUNDIR" && pwd)
echo "=== run directory: $RUNDIR"

# --- static tables and executables -----------------------------------------
echo "=== linking tables from $WRF/run"
n=0
for f in "$WRF"/run/*; do
  b=$(basename "$f")
  case "$b" in
    *.exe|namelist.*|README*) continue ;;
  esac
  ln -sfn "$f" "$RUNDIR/$b" && n=$((n + 1))
done
echo "    $n files"
for exe in real.exe wrf.exe ndown.exe tc.exe; do
  [ -e "$WRF/main/$exe" ] && ln -sfn "$WRF/main/$exe" "$RUNDIR/$exe"
done
ln -sfn "$RC/iofields.txt" "$RUNDIR/iofields.txt"
ln -sfn "$RC/iofields_qsq.txt" "$RUNDIR/iofields_qsq.txt"

# --- met_em ----------------------------------------------------------------
if [ -n "$METDIR" ]; then
  echo "=== linking met_em from $METDIR"
  m=0
  for f in "$METDIR"/met_em.d01.*.nc; do
    [ -e "$f" ] || continue
    ln -sfn "$f" "$RUNDIR/$(basename "$f")" && m=$((m + 1))
  done
  [ "$m" -gt 0 ] || { echo "!!! no met_em.d01.*.nc in $METDIR" >&2; exit 1; }
  echo "    $m files"
else
  echo "=== no --met-dir given; link met_em.d01.*.nc into $RUNDIR yourself"
fi

# --- namelist --------------------------------------------------------------
echo "=== namelist: realcase/namelist.input.$CONFIG"
cp "$RC/namelist.input.$CONFIG" "$RUNDIR/namelist.input"

SYNC=("$RC/scripts/prepare_namelist.py" "$RUNDIR/namelist.input" --apply)
[ -n "$GEO" ]    && SYNC+=(--geo "$GEO")
[ -n "$METDIR" ] && SYNC+=(--met-dir "$METDIR")
[ -n "$HOURS" ]  && SYNC+=(--hours "$HOURS")
# The env file owns the output root; the layout under it is fixed by convention.
# wrf.exe does not create the output directory and dies partway into the run if
# it is missing, so make it here rather than discovering that from a queued job.
if [ -n "${WRF_OUTPUT_ROOT:-}" ]; then
  SYNC+=(--output-root "$WRF_OUTPUT_ROOT")
  mkdir -p "$WRF_OUTPUT_ROOT/temp/branko" || exit 1
  echo "=== output root: $WRF_OUTPUT_ROOT (live: temp/branko, archive: wrf_output/<jobid>)"
else
  echo "!!! WRF_OUTPUT_ROOT is not set in $ENVFILE -- prepare_namelist.py will" >&2
  echo "!!! report the unexpanded @OUTPUT_ROOT@ as FATAL below" >&2
fi
if [ "$SMOKE" = 1 ]; then
  echo "=== smoke mode: 1 h, output every 10 min"
  SYNC+=(--smoke)
fi
echo "=== syncing the namelist to geo_em/met_em"
python3 "${SYNC[@]}"
SYNC_RC=$?

# --- q^2 budget diagnostic (OPEN_ISSUES A9) --------------------------------
# Adds stream 23 at 1-minute frames, carrying only what iofields_qsq.txt puts
# in it. Kept behind a flag because it is ~675 MB per frame.
if [ "$QSQDIAG" = 1 ]; then
  echo "=== q^2 budget diagnostic: auxhist23, 1-minute frames"
  python3 "$RC/scripts/add_qsq_diag.py" "$RUNDIR/namelist.input" "${WRF_OUTPUT_ROOT:-}" || SYNC_RC=1
fi

# --- SLURM -----------------------------------------------------------------
cp "$RC/scripts/submit_real.slurm" "$RC/scripts/submit_wrf.slurm" "$RUNDIR/"

# The submit scripts ship with CHANGEME in --account/--partition/--qos so that
# a run dir can never be submitted to the wrong project by accident. Fill them
# from the env file when it declares them, so the values live in exactly one
# place (the env file) instead of being re-typed into every run dir -- that
# hand-edit is what the E9/E10 class of mistakes came from. Anything the env
# file does not declare stays CHANGEME and is reported below.
for f in submit_real.slurm submit_wrf.slurm; do
  [ -n "${SLURM_ACCOUNT_DEFAULT:-}" ]   && sed -i "s|^#SBATCH --account=CHANGEME|#SBATCH --account=$SLURM_ACCOUNT_DEFAULT|"     "$RUNDIR/$f"
  [ -n "${SLURM_PARTITION_DEFAULT:-}" ] && sed -i "s|^#SBATCH --partition=CHANGEME|#SBATCH --partition=$SLURM_PARTITION_DEFAULT|" "$RUNDIR/$f"
  [ -n "${SLURM_QOS_DEFAULT:-}" ]       && sed -i "s|^#SBATCH --qos=CHANGEME|#SBATCH --qos=$SLURM_QOS_DEFAULT|"                 "$RUNDIR/$f"
done
if grep -lq CHANGEME "$RUNDIR"/submit_*.slurm 2>/dev/null; then
  echo "=== SLURM headers still carry CHANGEME -- edit by hand before sbatch:"
  grep -Hn 'CHANGEME' "$RUNDIR"/submit_*.slurm | sed 's/^/    /'
else
  echo "=== SLURM headers filled from $ENVFILE:"
  echo "    account=${SLURM_ACCOUNT_DEFAULT:-} partition=${SLURM_PARTITION_DEFAULT:-} qos=${SLURM_QOS_DEFAULT:-}"
fi
printf '%s\n' "$ENVFILE" > "$RUNDIR/.wrfenv"
cat > "$RUNDIR/env.sh" <<EOF
# generated by setup_rundir.sh -- sourced by the SLURM scripts
# EESSI's init chain references unset variables with no default -- fatal
# under the submit scripts' -u. Drop -u only for the sourcing.
set +u
. "$ENVFILE"
set -u
export WRF_SRC="$WRF"
EOF

# --- E11: dangling symlinks ------------------------------------------------
# A run dir reused from an earlier cluster/checkout can carry symlinks that
# this script's own loop does not manage, so they survive every rerun. They
# are invisible to real.exe and only fail deep inside wrf.exe -- freezeH2O.dat
# cost a run that way (KNOWN_ISSUES E11). Check every time; it is free.
DANGLING=$(find "$RUNDIR" -maxdepth 1 -xtype l 2>/dev/null)
if [ -n "$DANGLING" ]; then
  echo
  echo "!!! DANGLING SYMLINKS in $RUNDIR (KNOWN_ISSUES E11) -- these will not"
  echo "!!! fail until wrf.exe is deep into the run. Remove them before sbatch:"
  printf '%s\n' "$DANGLING" | sed 's/^/    /'
  printf '%s\n' "$DANGLING" | sed 's|^|    rm |'
fi

echo
echo "=== $RUNDIR is set up ($CONFIG)"
if [ "$SYNC_RC" != 0 ]; then
  echo "!!! prepare_namelist.py reported FATAL findings above -- fix them first"
  exit 1
fi
cat <<EOF

Next, in $RUNDIR:
    1. check the #SBATCH header of submit_real.slurm / submit_wrf.slurm
       (account/partition/qos come from the env file; set --nodes/--time
       yourself -- sizing is not something the env file can know)
    2. sbatch submit_real.slurm
    3. python3 $RC/scripts/check_wrfinput.py wrfinput_d01
       -- do read this one, especially the SMOIS range
    4. sbatch submit_wrf.slurm
EOF
