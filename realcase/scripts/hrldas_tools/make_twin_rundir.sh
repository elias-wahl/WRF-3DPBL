#!/bin/bash
# Build a WRF twin run directory that differs from its parent ONLY in the land state (from an HRLDAS restart) and the output root.
#
#   hrldas/tools/make_twin_rundir.sh <PARENT_NAME> <NEW_NAME> <HRLDAS RESTART file>
#   e.g.  make_twin_rundir.sh X16b X16s $DATA/hrldas_runs/spinup_winter_july/LDASOUT/RESTART.2025071721_DOMAIN1
#   PRODUCTION LAND STATE (Elias 2026-09-17, DECISIONS 14:55): the winter-start spin-up restarts in hrldas_runs/spinup_winter_july/LDASOUT
#   (hourly 15 Jul 21 UT -> 18 Jul 00 UT; daily 21 UT restarts in spinup_winter/LDASOUT). Every future WRF run starts from one of these.
#
# Parent = branko_runs/innval_pbl3d_<PARENT_NAME>; new dir = branko_runs/innval_pbl3d_<NEW_NAME>; env file
# branko/realcase/env/vsc5_<NEW_NAME>.sh must exist (WRF_OUTPUT_ROOT=exp/<NEW_NAME>). Every symlink of the parent is recreated,
# wrfbdy_d01 copied, namelist.input copied with exp/<PARENT> -> exp/<NEW> (and the standing rule: iofields_full.txt,
# output_t_fluxes = 1), the SLURM scripts copied with the job name changed, wrfinput_d01 = parent's wrfinput with the HRLDAS state
# (hrldas_to_wrfinput.py). The restart's time must equal the namelist start. Ends with the namelist diff, check_wrfinput.py and a
# dangling-symlink check (KNOWN_ISSUES E11). Nothing is submitted: cd into the dir and  sbatch submit_wrf.slurm  after the gate.
set -u -o pipefail
D=/gpfs/data/fs72996/ewahl; HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 3 ] || { sed -n '2,15p' "$0"; exit 1; }
P="$D/branko_runs/innval_pbl3d_$1"; N="$D/branko_runs/innval_pbl3d_$2"; RST=$3; ENV="$D/branko/realcase/env/vsc5_$2.sh"
[ -d "$P" ] || { echo "no parent $P" >&2; exit 1; }; [ -f "$RST" ] || { echo "no restart $RST" >&2; exit 1; }
[ -f "$ENV" ] || { echo "env file $ENV missing (WRF_OUTPUT_ROOT=$D/exp/$2)" >&2; exit 1; }
[ -e "$N" ] && { echo "$N exists -- refusing to overwrite" >&2; exit 1; }
source "$D/branko/realcase/env/vsc5.sh" >/dev/null 2>&1
# restart time vs namelist start
rt=$(basename "$RST" | sed -E 's/RESTART\.([0-9]{10})_DOMAIN1/\1/'); ns=$(grep -E "^\s*start_(year|month|day|hour)" "$P/namelist.input" | sed -E 's/.*=\s*([0-9]+).*/\1/' | tr -d '\n')
[ "$rt" = "$ns" ] || { echo "restart time $rt != namelist start $ns" >&2; exit 1; }
mkdir -p "$N" "$D/exp/$2"
n=0; for f in "$P"/*; do [ -L "$f" ] && { ln -s "$(readlink "$f")" "$N/$(basename "$f")"; n=$((n+1)); }; done; echo "=== $n symlinks recreated"
[ -e "$N/iofields_full.txt" ] || ln -s "$D/branko/realcase/iofields_full.txt" "$N/iofields_full.txt"
sed -e "s#$D/exp/$1/#$D/exp/$2/#g" -e 's/^\(\s*iofields_filename\s*=\s*\)"[^"]*"/\1"iofields_full.txt"/' -e 's/^\(\s*output_t_fluxes\s*=\s*\)[0-9]*/\11/' "$P/namelist.input" > "$N/namelist.input"
for s in submit_wrf.slurm submit_real.slurm; do sed "s/_$1\b/_$2/g" "$P/$s" > "$N/$s"; done
# E49 guard: a parent run dir built before 2026-09-12 carries a submit_wrf.slurm without the output-dir mkdir -- WRF then runs to
# the end writing nothing (X16s job 8637042, 2.5 h of 5 nodes lost). Insert the line if missing, and create the dir here as well.
grep -q 'mkdir -p "${WRF_OUTPUT_ROOT:?}/temp/branko"' "$N/submit_wrf.slurm" || sed -i '/^\[ -f wrfinput_d01 \]/i mkdir -p "${WRF_OUTPUT_ROOT:?}/temp/branko" || exit 1   # E49: without it WRF still reports SUCCESS while every write fails (-1021)' "$N/submit_wrf.slurm"
grep -q 'mkdir -p "${WRF_OUTPUT_ROOT:?}/temp/branko"' "$N/submit_wrf.slurm" || { echo "!!! could not insert the E49 mkdir into $N/submit_wrf.slurm -- add it by hand" >&2; exit 1; }
mkdir -p "$D/exp/$2/temp/branko"
sed "s#vsc5_$1.sh#vsc5_$2.sh#" "$P/env.sh" > "$N/env.sh"
echo "=== copying wrfbdy_d01"; cp "$P/wrfbdy_d01" "$N/wrfbdy_d01"
echo "=== wrfinput_d01 <- $RST"; python3 "$HERE/hrldas_to_wrfinput.py" "$P/wrfinput_d01" "$RST" "$N/wrfinput_d01" || exit 1
echo "=== namelist diff parent -> twin"; diff "$P/namelist.input" "$N/namelist.input"
echo "=== check_wrfinput.py"; python3 "$D/branko/realcase/scripts/check_wrfinput.py" "$N/wrfinput_d01" || echo "!!! check_wrfinput failed"
echo "=== dangling symlinks (must be empty)"; find "$N" -maxdepth 1 -xtype l
echo "=== SLURM: $(grep -E 'SBATCH --(nodes|time)' "$N/submit_wrf.slurm" | tr '\n' ' ')  -> cd $N && sbatch submit_wrf.slurm  (after the HRLDAS gate)"
