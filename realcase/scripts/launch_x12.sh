#!/bin/bash
# launch_x12.sh (2026-09-03): X12 = X10 physics, X10 window (17_13 -> 18_22), but forced by the NATIVE 65-level (default) or
# MODEL-LEVEL-derived ICON product (icon2wrf --ml-plevs, 36 pressure levels; WPS/metgrid_output_1712ml).
# Tests OPEN_ISSUES A21: the 11-level product handed WRF a 0.5-2.5 m/s ramp where the lidar had a
# 6 m/s valley jet at 100-300 m; the ML product carries the jet (3.8 m/s nose at 940-930 hPa at Kolsass).
# One real job (X12bdy, full window) feeds every segment; X12a links its wrfinput/wrfbdy.
#   X12bdy real (devel) -> wrfinput check (devel) -> X12a wrf (zen3_1024, 5:15) -> chain_x12 link b..f
# Submit scripts cd to SLURM_SUBMIT_DIR -> always sbatch from inside the rundir.
set -u -o pipefail
DATA=/gpfs/data/fs72996/ewahl
RC=$DATA/branko/realcase
# usage: launch_x12.sh m|p [--submit]   (Elias 2026-09-03: twin chains, m = native 65 ICON levels, p = 36-level ln-p ladder)
V=${1:?usage: launch_x12.sh m|p [--submit]}; shift
SMOKE=0
case $V in
  m)  MET=$DATA/WPS/metgrid_output_1712nat ;;                       # native 65 ICON levels, WRF (smoothed geogrid) terrain
  p)  MET=$DATA/WPS/metgrid_output_1712ml ;;                        # 36-level ln-p ladder, WRF terrain
  mt) MET=$DATA/WPS/metgrid_output_1712nat_icontopo; SMOKE=1 ;;     # native levels on ICON's own terrain (geogrid_icontopo); 1 h daytime smoke gates the chain
  *) echo "bad variant $V (m|p|mt)"; exit 1 ;;
esac
TAG=X12$V
n=$(ls $MET/met_em.d01.2025-07-1[78]_*.nc 2>/dev/null | wc -l)
[ "$n" -ge 35 ] || { echo "!!! only $n met_em files in $MET (need 35: 17_13 .. 18_23)"; exit 1; }
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
sets() { # the X10 physics/output settings (unchanged for X12 -- the forcing is the only difference)
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
for x in ${TAG}bdy ${TAG}a ${TAG}smoke; do
  [ -f "$RC/env/vsc5_$x.sh" ] || printf '#!/bin/bash\n# %s: X12 twin (m=native levels, p=36-level ladder) = X10 window/physics with model-level ICON forcing (A21), 2026-09-03\nsource "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"\nexport WRF_OUTPUT_ROOT=%s/exp/%s\n' "$x" "$DATA" "$x" > "$RC/env/vsc5_$x.sh"
done
BDY=$DATA/branko_runs/innval_pbl3d_${TAG}bdy; RUN=$DATA/branko_runs/innval_pbl3d_${TAG}a
echo "=== building ${TAG}bdy (full-window real, no --hours) from $MET"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}bdy.sh" "$BDY" pbl3d --met-dir "$MET" | tail -3
echo "=== building ${TAG}a (17_13 -> 19)"
"$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}a.sh" "$RUN" pbl3d --met-dir "$MET" --hours 6 | tail -3
for d in "$BDY" "$RUN"; do sets "$d/namelist.input"; ln -sfn "$RC/iofields_d1d2.txt" "$d/iofields_d1d2.txt"; done
ln -sfn "$BDY/wrfinput_d01" "$RUN/wrfinput_d01"; ln -sfn "$BDY/wrfbdy_d01" "$RUN/wrfbdy_d01"
if [ "$SMOKE" = 1 ]; then
  SMK=$DATA/branko_runs/innval_pbl3d_${TAG}smoke
  echo "=== building ${TAG}smoke (1 h from 13 UT, 10-min output; ICON terrain slopes up to 44.6 deg)"
  "$RC/scripts/setup_rundir.sh" "$RC/env/vsc5_${TAG}smoke.sh" "$SMK" pbl3d --met-dir "$MET" --smoke | tail -2
  sets "$SMK/namelist.input"; ln -sfn "$RC/iofields_d1d2.txt" "$SMK/iofields_d1d2.txt"
  ln -sfn "$BDY/wrfinput_d01" "$SMK/wrfinput_d01"; ln -sfn "$BDY/wrfbdy_d01" "$SMK/wrfbdy_d01"
  hdr "$SMK" wrf_${TAG}smoke zen3_1024 zen3_1024 2 01:15:00
fi
hdr "$BDY" real_${TAG}bdy zen3_0512 zen3_0512_devel 2 00:10:00
hdr "$RUN" wrf_${TAG}a    zen3_1024 zen3_1024       2 05:15:00
grep -E '^ (start_day|start_hour|end_day|end_hour|run_hours|pbl3d_t2_scalar|diff_6th_opt|iofields_filename)' "$RUN/namelist.input" | tr -s ' '
echo "=== namelist diff ${TAG}a vs X10a (expect only output paths and num_metgrid_levels)"
diff <(grep -vE 'outname|num_metgrid_levels' "$DATA/branko_runs/innval_pbl3d_X10a/namelist.input") <(grep -vE 'outname|num_metgrid_levels' "$RUN/namelist.input") && echo "identical apart from output paths / num_metgrid_levels"
[ "${1:-}" = "--submit" ] || { echo "(dry build; rerun with --submit)"; exit 0; }
echo "=== submitting"
br=$(cd "$BDY" && sbatch --parsable submit_real.slurm)
ck=$(sbatch --parsable --dependency=afterok:$br -A p72996 -p zen3_0512 -q zen3_0512_devel -N1 -t 00:05:00 -J ${TAG}_chk \
     -o "$BDY/check_wrfinput.%j.out" \
     --wrap="set +u; . $RC/env/vsc5.sh; set -u; python3 $RC/scripts/check_wrfinput.py $BDY/wrfinput_d01")
if [ "$SMOKE" = 1 ]; then
  sw=$(cd "$SMK" && sbatch --parsable --dependency=afterok:$ck submit_wrf.slurm)
  aw=$(cd "$RUN" && sbatch --parsable --dependency=afterok:$sw submit_wrf.slurm)
  sbatch --parsable --dependency=afternotok:$sw --export=ALL,STAGE=${TAG}smoke,FAILED_JOB=$sw "$RC/scripts/notify_x12.slurm" >/dev/null
  echo "smoke gate: wrf_${TAG}smoke=$sw (a-segment afterok)"
else
  aw=$(cd "$RUN" && sbatch --parsable --dependency=afterok:$ck submit_wrf.slurm)
fi
lb=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,IDX=b,TAG=$TAG --chdir="$RUN" "$RC/scripts/chain_x12.slurm")
jg=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,TAG=$TAG,IDX=a "$RC/scripts/judge_x12.slurm")
for j in "$br ${TAG}bdy-real" "$ck ${TAG}-check" "$aw ${TAG}a" "$lb ${TAG}-chain-b"; do set -- $j
  sbatch --parsable --dependency=afternotok:$1 --export=ALL,STAGE=$2,FAILED_JOB=$1 "$RC/scripts/notify_x12.slurm" >/dev/null
done
echo "${TAG}: bdy_real=$br check=$ck a=$aw link_b=$lb judge_a=$jg (pings armed)"
