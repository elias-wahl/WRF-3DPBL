#!/bin/bash
# hero_build_pair.sh — from the base dir HERO0 (real.exe done: wrfinput_d01 + wrfbdy_d01 on the ICON terrain, 17 July 01 UT →
# 19 July 00 UT) build the hero pair (2026-09-22, DECISIONS 14:40):
#   HERO = spun-up hero land state, towns → class 1 under the single-layer urban canopy model, meadows 2 → 3 above 700 m,
#          hero Noah-MP table, diff_6th_slopeopt = 5 (stabthresh 10, hfxthresh 20)
#   HCTL = identical, production filter (diff_6th_slopeopt = 1)
# First segment 01 → 10 UT (9 h; restart_interval 180 → restarts at 04, 07, 10). Later segments: hero_chain.slurm.
#   usage: hero_build_pair.sh [RESTART_FILE]   (default: spinup_hero_july/LDASOUT/RESTART.2025071701_DOMAIN1)
set -eu
D=/gpfs/data/fs72996/ewahl; RC=$D/branko/realcase; B=$D/branko_runs/innval_pbl3d_HERO0
RST=${1:-$D/hrldas_runs/spinup_hero_july/LDASOUT/RESTART.2025071701_DOMAIN1}
source ~/miniconda3/etc/profile.d/conda.sh; conda activate proc
[ -f $B/wrfinput_d01 ] && [ -f $B/wrfbdy_d01 ] || { echo "HERO0 has no wrfinput/wrfbdy"; exit 1; }
[ -f "$RST" ] || { echo "no restart $RST"; exit 1; }
echo "=== land state -> wrfinput_hero_d01"
rm -f $B/wrfinput_hero_d01
python $RC/scripts/hrldas_tools/hrldas_to_wrfinput.py $B/wrfinput_d01 "$RST" $B/wrfinput_hero_d01
echo "=== land-use relabel (towns -> 1, meadows 2 -> 3 above 700 m) + attributes"
python - <<PY
import numpy as np, netCDF4 as nc
d=nc.Dataset("$B/wrfinput_hero_d01","r+"); g=lambda k: np.asarray(d[k][0])
lu,iv,hgt,lf=g("LU_INDEX"),g("IVGTYP"),g("HGT"),np.array(g("LANDUSEF"))
towns=np.isin(lu,(31,32,33)); meadow=(lu==2)&(hgt>700)
d["LU_INDEX"][0]=np.where(towns,1,np.where(meadow,3,lu)); d["IVGTYP"][0]=np.where(towns,1,np.where(meadow,3,iv))
lf[0]+=lf[30]+lf[31]+lf[32]; lf[30:33]=0.0; lf[2]+=np.where(meadow,lf[1],0.0); lf[1]=np.where(meadow,0.0,lf[1]); d["LANDUSEF"][0]=lf
d.setncattr("SF_URBAN_PHYSICS",1); d.setncattr("HERO_LU_EDIT","2026-09-22: 31/32/33 -> 1 (UCM, URBPARM type 2 = open low-rise); 2 -> 3 above 700 m (A30); land state from $RST")
d.close(); print("relabelled: towns",int(towns.sum()),"meadows",int(meadow.sum()))
PY
python $RC/scripts/check_wrfinput.py $B/wrfinput_hero_d01 | tail -2
for R in HERO HCTL; do
  T=$D/branko_runs/innval_pbl3d_$R; rm -rf $T; mkdir -p $T $D/exp/$R/temp/branko
  for f in $B/*; do b=$(basename $f); case $b in wrfinput_d01|wrfinput_hero_d01|wrfbdy_d01|rsl.*|real.*|met_em.*|NoahmpTable.TBL|URBPARM*.TBL|namelist.input|env.sh|submit_real.slurm) ;; *) cp -a $f $T/;; esac; done
  ln $B/wrfinput_hero_d01 $T/wrfinput_d01; ln $B/wrfbdy_d01 $T/wrfbdy_d01
  cp $D/hrldas_runs/spinup_hero/NoahmpTable.TBL $T/NoahmpTable.TBL          # own table (E60)
  cp $D/branko_runs/innval_pbl3d_SMOKEURB/URBPARM.TBL $T/; cp $D/branko/run/URBPARM_LCZ.TBL $D/branko/run/URBPARM_UZE.TBL $T/
  sed "s#exp/HERO0/#exp/$R/#g" $B/namelist.input > $T/namelist.input
  sed -i "s/^ sf_urban_physics *= *0,/ sf_urban_physics       = 1,           ! hero: single-layer UCM on the relabelled towns/" $T/namelist.input
  if [ $R = HERO ]; then sed -i "s/^ diff_6th_slopeopt *= *1,.*/ diff_6th_slopeopt      = 5,           ! hero: regime-gated, stratification-corrected along-eta filter\n diff_6th_stabthresh    = 10.0,\n diff_6th_hfxthresh     = 20.0,/" $T/namelist.input; fi
  sed -i "s/^ run_hours *= *[0-9]*,/ run_hours              = 9,/; s/^ end_day *= *[0-9]*,/ end_day                = 17,/; s/^ end_hour *= *[0-9]*,/ end_hour               = 10,/" $T/namelist.input
  grep -q "^ restart_interval *= *180" $T/namelist.input || sed -i "s/^ restart_interval *= *[0-9]*,/ restart_interval       = 180,/" $T/namelist.input
  sed "s#vsc5_HERO0.sh#vsc5_$R.sh#" $B/env.sh > $T/env.sh
  sed -i "s/job-name=wrf_[A-Za-z0-9]*/job-name=wrf_$R/" $T/submit_wrf.slurm
  echo "--- $R namelist diff vs HERO0:"; diff $B/namelist.input $T/namelist.input | grep "^>" | grep -vE "outname" | cut -c1-90
  [ -n "$(find $T -maxdepth 1 -xtype l)" ] && echo "!!! dangling symlink in $T" || echo "    no dangling symlinks"
done
echo "=== built HERO and HCTL (segment a: 01 -> 10 UT). Submit with: cd branko_runs/innval_pbl3d_HERO && sbatch submit_wrf.slurm"
