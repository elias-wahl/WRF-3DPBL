#!/bin/bash
# clone_twin_rundir.sh PARENT NAME --hours H --end-hour HH --wall HH:MM:SS [--set 'sed-expr' ...] [--own-table] [--desc "text"] [--submit]
# Builds branko_runs/innval_pbl3d_NAME as a twin of innval_pbl3d_PARENT (same wrfinput/wrfbdy, COPIED never linked), own output root exp/NAME,
# own env file realcase/env/vsc5_NAME.sh. --set takes sed expressions applied to namelist.input (e.g. 's/diff_6th_opt *= *2,/diff_6th_opt = 0,/').
# --own-table replaces the NoahmpTable.TBL SYMLINK by a real copy of branko/run's (E60: never edit through the link). Prints the namelist diff.
# Wall-time rule (E57, 5 x 128, full output): 2 h sim -> 1:00, 5 h -> 2:10, 8 h -> 3:15. Built 2026-09-18 after six hand-made twins in one day.
set -euo pipefail; D=/gpfs/data/fs72996/ewahl; PAR=$1; NAME=$2; shift 2; HOURS=; ENDH=; WALL=; SETS=(); OWN=0; DESC="twin of $PAR"; SUB=0
while [ $# -gt 0 ]; do case $1 in --hours) HOURS=$2; shift 2;; --end-hour) ENDH=$2; shift 2;; --wall) WALL=$2; shift 2;; --set) SETS+=("$2"); shift 2;; --own-table) OWN=1; shift;; --desc) DESC=$2; shift 2;; --submit) SUB=1; shift;; *) echo "unknown $1"; exit 2;; esac; done
P=$D/branko_runs/innval_pbl3d_$PAR; N=$D/branko_runs/innval_pbl3d_$NAME; [ -d "$P" ] || { echo "no parent $P"; exit 1; }; [ -e "$N" ] && { echo "$N exists"; exit 1; }
mkdir -p "$N" "$D/exp/$NAME/temp/branko"
for f in "$P"/*; do b=$(basename "$f"); case "$b" in wrfinput_d01|wrfbdy_d01) continue;; esac; [ -L "$f" ] && ln -s "$(readlink "$f")" "$N/$b"; done
for b in qr_acr_qg_V4.dat qr_acr_qsV2.dat; do [ -e "$N/$b" ] || ln -s "$(readlink -f "$P/$b")" "$N/$b"; done
if [ $OWN = 1 ]; then rm -f "$N/NoahmpTable.TBL"; cp "$D/branko/run/NoahmpTable.TBL" "$N/NoahmpTable.TBL"; fi
sed -e "s/$PAR/$NAME/g" "$P/env.sh" > "$N/env.sh"
EXPR=(-e "s#exp/$PAR#exp/$NAME#g"); [ -n "$HOURS" ] && EXPR+=(-e "s/^\( *run_hours *= *\)[0-9]*,/\1$HOURS,/"); [ -n "$ENDH" ] && EXPR+=(-e "s/^\( *end_hour *= *\)[0-9]*,/\1$ENDH,/"); for s in "${SETS[@]:-}"; do [ -n "$s" ] && EXPR+=(-e "$s"); done
sed "${EXPR[@]}" "$P/namelist.input" > "$N/namelist.input"
sed -e "s/--job-name=wrf_$PAR/--job-name=wrf_$NAME/" ${WALL:+-e "s/^#SBATCH --time=.*/#SBATCH --time=$WALL/"} "$P/submit_wrf.slurm" > "$N/submit_wrf.slurm"
grep -qF 'mkdir -p "${WRF_OUTPUT_ROOT:?}/temp/branko"' "$N/submit_wrf.slurm" || { echo "E49 mkdir guard missing in submit script"; exit 1; }
printf '#!/bin/bash\n# %s: %s\nsource "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"\nexport WRF_OUTPUT_ROOT=%s/exp/%s\n' "$NAME" "$DESC" "$D" "$NAME" > "$D/branko/realcase/env/vsc5_$NAME.sh"
cp "$P/wrfbdy_d01" "$N/"; cp "$P/wrfinput_d01" "$N/"
echo "=== namelist diff vs $PAR (output paths hidden):"; diff <(grep -v outname "$P/namelist.input") <(grep -v outname "$N/namelist.input") | grep '^[<>]' || true
(cd "$D/branko" && git diff --quiet run/NoahmpTable.TBL) && echo "default Noah-MP table clean" || { echo "DEFAULT TABLE MODIFIED (E60)"; exit 1; }
[ $SUB = 1 ] && (cd "$N" && sbatch --parsable submit_wrf.slurm) || echo "built $N (not submitted)"
