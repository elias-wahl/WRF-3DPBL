#!/bin/bash
# launch_x14.sh (2026-09-09): X14 = X12m (native 65-level forcing, X10 physics, 80 levels)
# with pbl3d_l_opt=2 -- the MYNN harmonic-blend master length scale (surface, asymptotic and
# buoyancy scales blended; own buoyancy limit l_f = alpha_2 q/N). Tests the subgrid
# carrying-capacity deficit of the convective boundary layer (DECISIONS 2026-09-09 ~18:15:
# resolved share is grid-set at 6-8 dx because the Blackadar-l subgrid flux cannot carry the
# heating). Gates PRE-REGISTERED (DECISIONS ~19:00): morning profiles 08-11 UT less stratified,
# 11 UT mixed-layer depth toward 900 m, morning theta dipole shrinking, noon w-spectrum sub-8dx
# variance fraction down from 0.34-0.38; GUARD: the 18th wind + theta scorecard must not
# degrade toward MYNN. X12m is the identical-but-length-scale twin.
# real.exe output is independent of pbl3d_* options -> X14bdy just links X12mbdy's files;
# a 1 h daytime smoke still gates the chain (first-ever run of l_opt=2).
#   X14smoke (1 h from 13 UT) -> X14a -> chain b..f (XSETS hands pbl3d_l_opt=2 down)
set -u -o pipefail
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
MET=$DATA/WPS/metgrid_output_1712nat
TAG=X14
LANE=zen3_0512
NODES=5
XSETS="pbl3d_l_opt=2"
n=$(ls $MET/met_em.d01.2025-07-1[78]_*.nc 2>/dev/null | wc -l)
[ "$n" -ge 35 ] || { echo "!!! only $n met_em files in $MET"; exit 1; }
hdr() { # hdr <rundir> <jobname> <nodes> <time>  (wrf only; no real jobs in this chain)
  local d=$1
  sed -i -E -e "s/^#SBATCH --account=.*/#SBATCH --account=p72996/" \
            -e "s/^#SBATCH --partition=.*/#SBATCH --partition=$LANE/" \
            -e "s/^#SBATCH --qos=.*/#SBATCH --qos=$LANE/" \
            -e "s/^#SBATCH --nodes=.*/#SBATCH --nodes=$3/" \
            -e "s/^#SBATCH --time=.*/#SBATCH --time=$4/" \
            -e "s/^#SBATCH --job-name=.*/#SBATCH --job-name=$2/" "$d/submit_wrf.slurm"
  grep -q -- '--hint=nomultithread' "$d/submit_wrf.slurm" || sed -i "/^#SBATCH --ntasks-per-node=/a #SBATCH --hint=nomultithread" "$d/submit_wrf.slurm"
}
sets() { # X12 physics/output settings + the one lever
  local NL=$1 kv
  for kv in pbl3d_l_opt=2 pbl3d_t2_scalar=1 pbl3d_init_opt=0 pbl3d_l0_min=0.0 pbl3d_moist_cond_max=10000.0 \
            output_t_fluxes=0 output_q_fluxes=0 output_u_fluxes=0 output_v_fluxes=0 \
            output_w_fluxes=0 output_tke_moments=1 auxhist24_interval_m=30; do
    local k=${kv%%=*} v=${kv#*=}
    grep -qE "^ $k[[:space:]]*=" "$NL" || { echo "!!! key missing: $k"; exit 1; }
    sed -i -E "s/^( $k[[:space:]]*=[[:space:]]*)[^,!]*(,?)/\1$v\2/" "$NL"
  done
  sed -i -E "s/^( iofields_filename[[:space:]]*=[[:space:]]*)\"[^\"]*\"/\1\"iofields_d1d2.txt\"/" "$NL"
}
for x in ${TAG}a ${TAG}smoke; do
  [ -f "$RC/env/vsc5_$x.sh" ] || printf '#!/bin/bash\n# %s: X14 = X12m with pbl3d_l_opt=2 (MYNN-blend length scale), 2026-09-09\nsource "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"\nexport WRF_OUTPUT_ROOT=%s/exp/%s\n' "$x" "$DATA" "$x" > "$RC/env/vsc5_$x.sh"
done
# bdy: real output is pbl3d-independent -> reuse X12mbdy via a link directory the chain expects
BDY=$DATA/branko_runs/innval_pbl3d_${TAG}bdy
mkdir -p "$BDY"
ln -sfn $DATA/branko_runs/innval_pbl3d_X12mbdy/wrfinput_d01 "$BDY/wrfinput_d01"
ln -sfn $DATA/branko_runs/innval_pbl3d_X12mbdy/wrfbdy_d01   "$BDY/wrfbdy_d01"
RUN=$DATA/branko_runs/innval_pbl3d_${TAG}a; SMK=$DATA/branko_runs/innval_pbl3d_${TAG}smoke
echo "=== building ${TAG}a (17_13 -> 19)"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}a.sh" "$RUN" pbl3d --met-dir "$MET" --hours 6 | tail -3
echo "=== building ${TAG}smoke (1 h from 13 UT; first run of l_opt=2)"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}smoke.sh" "$SMK" pbl3d --met-dir "$MET" --smoke | tail -2
for d in "$RUN" "$SMK"; do
  sets "$d/namelist.input"; ln -sfn "$RC/iofields_d1d2.txt" "$d/iofields_d1d2.txt"
  ln -sfn "$BDY/wrfinput_d01" "$d/wrfinput_d01"; ln -sfn "$BDY/wrfbdy_d01" "$d/wrfbdy_d01"
done
hdr "$SMK" wrf_${TAG}smoke $NODES 00:45:00
hdr "$RUN" wrf_${TAG}a     $NODES 02:30:00
grep -E '^ (pbl3d_l_opt|pbl3d_t2_scalar|e_vert|start_day|end_day)' "$RUN/namelist.input" | tr -s ' '
echo "=== namelist diff ${TAG}a vs X12ma (expect only pbl3d_l_opt and output paths)"
diff <(grep -vE 'outname' "$DATA/branko_runs/innval_pbl3d_X12ma/namelist.input") <(grep -vE 'outname' "$RUN/namelist.input")
[ "${1:-}" = "--submit" ] || { echo "(dry build; rerun with --submit)"; exit 0; }
echo "=== submitting"
sw=$(cd "$SMK" && sbatch --parsable submit_wrf.slurm)
aw=$(cd "$RUN" && sbatch --parsable --dependency=afterok:$sw submit_wrf.slurm)
lb=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,IDX=b,TAG=$TAG,LANE=$LANE,NODES=$NODES,XSETS=$XSETS --chdir="$RUN" "$RC/scripts/chain_x12.slurm")
jg=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,TAG=$TAG,IDX=a "$RC/scripts/judge_x12.slurm")
for j in "$sw ${TAG}smoke" "$aw ${TAG}a" "$lb ${TAG}-chain-b"; do set -- $j
  sbatch --parsable --dependency=afternotok:$1 --export=ALL,STAGE=$2,FAILED_JOB=$1 "$RC/scripts/notify_x12.slurm" >/dev/null
done
echo "${TAG}: smoke=$sw a=$aw link_b=$lb judge_a=$jg (pings armed)"
