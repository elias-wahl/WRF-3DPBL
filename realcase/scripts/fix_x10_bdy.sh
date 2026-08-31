#!/bin/bash
# fix_x10_bdy.sh (2026-08-31): rebuild the X10 boundary file over the FULL window
# and re-arm the chain from segment b. Root cause of job 8549830's FATAL
# ("Ran out of valid boundary conditions"): X10a's real.exe ran with --hours 6,
# so its wrfbdy_d01 ends at 17_19:00; every later segment linked it.
# Run from an interactive/approving session. Idempotent.
set -eu -o pipefail
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
# Guard (2026-08-31 22:15): if the chain already recovered (X10c archived), a second
# re-arm duplicates segments and re-runs real under the live chain's wrfbdy. Abort.
if ls $DATA/exp/X10c/wrf_output/* >/dev/null 2>&1; then
  echo "X10c already archived -- chain recovered; refusing to re-arm (check sacct/git log first)"; exit 1
fi
ENV=$RC/env/vsc5_X10bdy.sh
[ -f "$ENV" ] || printf '#!/bin/bash\n# X10bdy: full-window real for the X10 chain boundary file\nsource "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"\nexport WRF_OUTPUT_ROOT=%s/exp/X10bdy\n' "$DATA" > "$ENV"
RUN=$DATA/branko_runs/innval_pbl3d_X10bdy
# no --hours: prepare_namelist takes the full met_em coverage (17_13 -> 18_23)
"$RC/scripts/setup_rundir.sh" "$ENV" "$RUN" pbl3d --met-dir "$DATA/WPS/metgrid_output_1712" | tail -3
sed -i -E -e "s/^#SBATCH --account=.*/#SBATCH --account=p72996/" \
          -e "s/^#SBATCH --partition=.*/#SBATCH --partition=zen3_0512/" \
          -e "s/^#SBATCH --qos=.*/#SBATCH --qos=zen3_0512_devel/" \
          -e "s/^#SBATCH --nodes=.*/#SBATCH --nodes=2/" \
          -e "s/^#SBATCH --time=.*/#SBATCH --time=00:10:00/" "$RUN/submit_real.slurm"
jr=$(cd "$RUN" && sbatch --parsable submit_real.slurm)
echo "full-window real: job $jr"
lb=$(sbatch --parsable --dependency=afterok:$jr --export=ALL,IDX=b --chdir="$RUN" "$RC/scripts/chain_x10.slurm")
echo "chain re-armed from b: link $lb (afterok:$jr)"
for j in "$jr X10bdy-real" "$lb chain-b-rearm"; do set -- $j
  sbatch --parsable --dependency=afternotok:$1 --export=ALL,STAGE=$2,FAILED_JOB=$1 "$RC/scripts/notify_x10.slurm" >/dev/null
done
echo "pings armed"
