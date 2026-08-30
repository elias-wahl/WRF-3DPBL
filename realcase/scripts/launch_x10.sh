#!/bin/bash
# One-shot launcher (submit scripts cd to SLURM_SUBMIT_DIR -> always sbatch from inside the rundir) for X10 (evening-start, ICON 17_12 forcing, A18 fix on).
# Builds X10a (17_13->19) + a 1 h smoke, submits with dependency gating:
#   smoke_real -> smoke_wrf ;  x10a_real -> wrfinput check ;  X10a wrf
#   afterok:(smoke_wrf, check) ; chain links b..f self-propagate afterok.
set -u -o pipefail
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
MET=$DATA/WPS/metgrid_output_1712
hdr() { # hdr <rundir> <jobname> <partition> <qos> <nodes> <time>
  local d=$1 f; for f in submit_real.slurm submit_wrf.slurm; do
    sed -i -E -e "s/^#SBATCH --account=.*/#SBATCH --account=p72996/" \
              -e "s/^#SBATCH --partition=.*/#SBATCH --partition=$3/" \
              -e "s/^#SBATCH --qos=.*/#SBATCH --qos=$4/" \
              -e "s/^#SBATCH --nodes=.*/#SBATCH --nodes=$5/" "$d/$f"
    grep -q -- '--hint=nomultithread' "$d/$f" || sed -i "/^#SBATCH --ntasks-per-node=/a #SBATCH --hint=nomultithread" "$d/$f"
  done
  sed -i -E "s/^#SBATCH --time=.*/#SBATCH --time=00:10:00/" "$d/submit_real.slurm"
  sed -i -E -e "s/^#SBATCH --time=.*/#SBATCH --time=$6/" -e "s/^#SBATCH --job-name=.*/#SBATCH --job-name=$2/" "$d/submit_wrf.slurm"
}
sets() { # apply the X10 physics/output settings to a namelist
  local NL=$1 kv
  for kv in pbl3d_t2_scalar=1 pbl3d_init_opt=0 pbl3d_l0_min=0.0 pbl3d_moist_cond_max=10000.0 \
            output_t_fluxes=0 output_q_fluxes=0 output_u_fluxes=0 output_v_fluxes=0 \
            output_w_fluxes=0 output_tke_moments=1 auxhist24_interval_m=30; do
    local k=${kv%%=*} v=${kv#*=}
    grep -qE "^ $k[[:space:]]*=" "$NL" || { echo "!!! key missing: $k"; exit 1; }
    sed -i -E "s/^( $k[[:space:]]*=[[:space:]]*)[^,!]*(,?)/\1$v\2/" "$NL"
  done
  sed -i -E "s/^( iofields_filename[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"iofields_d1d2.txt\"/" "$NL"
}
for n in X10a X10smoke; do
  [ -f "$RC/env/vsc5_$n.sh" ] || printf '#!/bin/bash\n# %s: X10 evening-start (ICON 17_12 forcing), 2026-08-31\nsource "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"\nexport WRF_OUTPUT_ROOT=%s/exp/%s\n' "$n" "$DATA" "$n" > "$RC/env/vsc5_$n.sh"
done
echo "=== building X10a"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_X10a.sh" "$DATA/branko_runs/innval_pbl3d_X10a" pbl3d --met-dir "$MET" --hours 6 | tail -4
echo "=== building X10smoke"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_X10smoke.sh" "$DATA/branko_runs/innval_pbl3d_X10smoke" pbl3d --met-dir "$MET" --smoke | tail -4
for d in X10a X10smoke; do
  RUN=$DATA/branko_runs/innval_pbl3d_$d
  sets "$RUN/namelist.input"
  ln -sfn "$RC/iofields_d1d2.txt" "$RUN/iofields_d1d2.txt"
done
hdr "$DATA/branko_runs/innval_pbl3d_X10smoke" wrf_X10smoke zen3_1024 zen3_1024 2 01:15:00
hdr "$DATA/branko_runs/innval_pbl3d_X10a"     wrf_X10a     zen3_1024 zen3_1024 2 05:15:00
# real jobs on devel
for d in X10a X10smoke; do
  sed -i -E -e "s/^#SBATCH --partition=.*/#SBATCH --partition=zen3_0512/" \
            -e "s/^#SBATCH --qos=.*/#SBATCH --qos=zen3_0512_devel/" \
    "$DATA/branko_runs/innval_pbl3d_$d/submit_real.slurm"
done
grep -E '^ (start_day|start_hour|end_day|end_hour|run_hours|pbl3d_t2_scalar|output_tke_moments|iofields_filename)' \
  "$DATA/branko_runs/innval_pbl3d_X10a/namelist.input" | tr -s ' '
echo "=== submitting"
sr=$(cd "$DATA/branko_runs/innval_pbl3d_X10smoke" && sbatch --parsable submit_real.slurm)
sw=$(cd "$DATA/branko_runs/innval_pbl3d_X10smoke" && sbatch --parsable --dependency=afterok:$sr submit_wrf.slurm)
ar=$(cd "$DATA/branko_runs/innval_pbl3d_X10a" && sbatch --parsable submit_real.slurm)
ck=$(sbatch --parsable --dependency=afterok:$ar -A p72996 -p zen3_0512 -q zen3_0512_devel -N1 -t 00:05:00 -J x10_chk \
     -o "$DATA/branko_runs/innval_pbl3d_X10a/check_wrfinput.%j.out" \
     --wrap="set +u; . $RC/env/vsc5.sh; set -u; python3 $RC/scripts/check_wrfinput.py $DATA/branko_runs/innval_pbl3d_X10a/wrfinput_d01")
aw=$(cd "$DATA/branko_runs/innval_pbl3d_X10a" && sbatch --parsable --dependency=afterok:$sw:$ck submit_wrf.slurm)
lb=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,IDX=b --chdir="$DATA/branko_runs/innval_pbl3d_X10a" "$RC/scripts/chain_x10.slurm")
echo "smoke_real=$sr smoke_wrf=$sw x10a_real=$ar check=$ck X10a=$aw link_b=$lb"
