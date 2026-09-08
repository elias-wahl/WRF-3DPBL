#!/bin/bash
# launch_x13.sh (2026-09-08): X13 = X12m (native 65-level ICON forcing, WRF terrain, X10 physics)
# with a REFINED NEAR-SURFACE LEVEL SET (e_vert 80 -> 89; ~15 m layers to 145 m, ~16.5 m to 260 m,
# rejoined at ~610 m; first layer kept at 24 m so the surface layer is untouched; set_eta_x13.py).
# Tests the stratification/sheltering root of the cold-pool formation deficit (DECISIONS 2026-09-08):
# sharper floor inversion -> deeper 19-21 UT cooling and blocking of the Karwendel wall intrusion.
# X12m is the identical-but-levels twin. Refinement breaks restart compatibility -> fresh real,
# 13 UT start, full 6-segment chain (cut early via scancel of the pending link if b answers it).
# Gate: 1 h daytime smoke (crest-cell min layer ~8.5 m -> vertical-CFL risk peaks with convection).
#   X13bdy real (devel) -> wrfinput check (devel) -> X13smoke (1 h) -> X13a -> chain b..f
# Always sbatch from inside the rundir (SLURM_SUBMIT_DIR trap).
set -u -o pipefail
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
MET=$DATA/WPS/metgrid_output_1712nat
TAG=X13
LANE=zen3_0512      # E42: zen3_1024 is frozen by the owner's cap; 0512 is the only lane starting public work
NODES=5
EVERT=89
n=$(ls $MET/met_em.d01.2025-07-1[78]_*.nc 2>/dev/null | wc -l)
[ "$n" -ge 35 ] || { echo "!!! only $n met_em files in $MET (need 35)"; exit 1; }
hdr() { # hdr <rundir> <jobname> <nodes> <time>
  local d=$1 f; for f in submit_real.slurm submit_wrf.slurm; do
    sed -i -E -e "s/^#SBATCH --account=.*/#SBATCH --account=p72996/" \
              -e "s/^#SBATCH --partition=.*/#SBATCH --partition=$LANE/" \
              -e "s/^#SBATCH --qos=.*/#SBATCH --qos=$LANE/" \
              -e "s/^#SBATCH --nodes=.*/#SBATCH --nodes=$3/" "$d/$f"
    grep -q -- '--hint=nomultithread' "$d/$f" || sed -i "/^#SBATCH --ntasks-per-node=/a #SBATCH --hint=nomultithread" "$d/$f"
  done
  sed -i -E -e "s/^#SBATCH --partition=.*/#SBATCH --partition=zen3_0512/" -e "s/^#SBATCH --qos=.*/#SBATCH --qos=zen3_0512_devel/" \
            -e "s/^#SBATCH --nodes=.*/#SBATCH --nodes=2/" -e "s/^#SBATCH --time=.*/#SBATCH --time=00:10:00/" "$d/submit_real.slurm"
  sed -i -E -e "s/^#SBATCH --time=.*/#SBATCH --time=$4/" -e "s/^#SBATCH --job-name=.*/#SBATCH --job-name=$2/" "$d/submit_wrf.slurm"
}
sets() { # X10/X12 physics/output settings -- the level set is the only physics-relevant difference to X12m
  local NL=$1 kv
  for kv in pbl3d_t2_scalar=1 pbl3d_init_opt=0 pbl3d_l0_min=0.0 pbl3d_moist_cond_max=10000.0 \
            output_t_fluxes=0 output_q_fluxes=0 output_u_fluxes=0 output_v_fluxes=0 \
            output_w_fluxes=0 output_tke_moments=1 auxhist24_interval_m=30; do
    local k=${kv%%=*} v=${kv#*=}
    grep -qE "^ $k[[:space:]]*=" "$NL" || { echo "!!! key missing: $k"; exit 1; }
    sed -i -E "s/^( $k[[:space:]]*=[[:space:]]*)[^,!]*(,?)/\1$v\2/" "$NL"
  done
  sed -i -E "s/^( iofields_filename[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"iofields_d1d2.txt\"/" "$NL"
  python3 "$RC/scripts/set_eta_x13.py" "$NL" || exit 1
}
for x in ${TAG}bdy ${TAG}a ${TAG}smoke; do
  [ -f "$RC/env/vsc5_$x.sh" ] || printf '#!/bin/bash\n# %s: X13 = X12m with refined near-surface levels (e_vert 89), 2026-09-08\nsource "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"\nexport WRF_OUTPUT_ROOT=%s/exp/%s\n' "$x" "$DATA" "$x" > "$RC/env/vsc5_$x.sh"
done
BDY=$DATA/branko_runs/innval_pbl3d_${TAG}bdy; RUN=$DATA/branko_runs/innval_pbl3d_${TAG}a; SMK=$DATA/branko_runs/innval_pbl3d_${TAG}smoke
echo "=== building ${TAG}bdy (full-window real, no --hours) from $MET"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}bdy.sh" "$BDY" pbl3d --met-dir "$MET" | tail -3
echo "=== building ${TAG}a (17_13 -> 19)"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}a.sh" "$RUN" pbl3d --met-dir "$MET" --hours 6 | tail -3
echo "=== building ${TAG}smoke (1 h from 13 UT; vertical-CFL gate for the 8.5 m crest layers)"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}smoke.sh" "$SMK" pbl3d --met-dir "$MET" --smoke | tail -2
for d in "$BDY" "$RUN" "$SMK"; do sets "$d/namelist.input"; ln -sfn "$RC/iofields_d1d2.txt" "$d/iofields_d1d2.txt"; done
ln -sfn "$BDY/wrfinput_d01" "$RUN/wrfinput_d01"; ln -sfn "$BDY/wrfbdy_d01" "$RUN/wrfbdy_d01"
ln -sfn "$BDY/wrfinput_d01" "$SMK/wrfinput_d01"; ln -sfn "$BDY/wrfbdy_d01" "$SMK/wrfbdy_d01"
hdr "$BDY" real_${TAG}bdy 2 00:10:00
hdr "$SMK" wrf_${TAG}smoke $NODES 00:45:00
hdr "$RUN" wrf_${TAG}a     $NODES 02:45:00
grep -E '^ (e_vert|start_day|end_day|run_hours|pbl3d_t2_scalar|iofields_filename)' "$RUN/namelist.input" | tr -s ' '
echo "=== namelist diff ${TAG}a vs X12ma (expect only e_vert, eta_levels, output paths)"
diff <(grep -vE 'outname' "$DATA/branko_runs/innval_pbl3d_X12ma/namelist.input") <(grep -vE 'outname' "$RUN/namelist.input") | head -40
[ "${1:-}" = "--submit" ] || { echo "(dry build; rerun with --submit)"; exit 0; }
echo "=== submitting"
br=$(cd "$BDY" && sbatch --parsable submit_real.slurm)
ck=$(sbatch --parsable --dependency=afterok:$br -A p72996 -p zen3_0512 -q zen3_0512_devel -N1 -t 00:05:00 -J ${TAG}_chk \
     -o "$BDY/check_wrfinput.%j.out" \
     --wrap="set +u; . $RC/env/vsc5.sh; set -u; python3 $RC/scripts/check_wrfinput.py $BDY/wrfinput_d01")
sw=$(cd "$SMK" && sbatch --parsable --dependency=afterok:$ck submit_wrf.slurm)
aw=$(cd "$RUN" && sbatch --parsable --dependency=afterok:$sw submit_wrf.slurm)
lb=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,IDX=b,TAG=$TAG,LANE=$LANE,NODES=$NODES,EVERT=$EVERT --chdir="$RUN" "$RC/scripts/chain_x12.slurm")
jg=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,TAG=$TAG,IDX=a "$RC/scripts/judge_x12.slurm")
for j in "$br ${TAG}bdy-real" "$ck ${TAG}-check" "$sw ${TAG}smoke" "$aw ${TAG}a" "$lb ${TAG}-chain-b"; do set -- $j
  sbatch --parsable --dependency=afternotok:$1 --export=ALL,STAGE=$2,FAILED_JOB=$1 "$RC/scripts/notify_x12.slurm" >/dev/null
done
echo "${TAG}: bdy_real=$br check=$ck smoke=$sw a=$aw link_b=$lb judge_a=$jg (pings armed)"
