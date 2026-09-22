#!/bin/bash
#SBATCH --job-name=hero_judge
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/exp/x16_judge/hero_judge_%j.log
# Report-only judge of the hero pair (2026-09-22). Submitted by hero_chain.slurm afterany the segment named in $UPTO
# (c = day-1 evening in, f = both days in). RUN specs use the segment lists so every script's RUN=SEG+SEG syntax works.
set -u
D=/gpfs/data/fs72996/ewahl; cd $D; source ~/miniconda3/etc/profile.d/conda.sh && conda activate proc
UPTO=${UPTO:-c}
segs() { local r=$1 out=$r; for x in b c d e f; do out="$out+$r$x"; [ $x = $UPTO ] && break; done; echo $out; }
H=$(segs HERO); C=$(segs HCTL)
LASTC=HCTL$UPTO; for i in $(seq 1 18); do ls $D/exp/$LASTC/wrf_output/*/wrfout_d01_* >/dev/null 2>&1 && break; sleep 30; done
ls $D/exp/$LASTC/wrf_output/*/wrfout_d01_* >/dev/null 2>&1 || echo "!!! $LASTC has no archive yet -- HCTL lags; judge runs on what exists"
echo "########## hero judge up to segment $UPTO: HERO=$H  HCTL=$C  $(date)"
echo "########## 1. onset bands at 1800 m (17 July) -- ICON 2-6dx 0.21, 6-12dx 0.19"
python wrf3dpbl-diag/gradient_scale_onset.py Z=1800 RUNS=HERO,HCTL TIMES=13:00,13:30,14:00,14:30,15:00,16:00,17:00 2>&1 | grep -E "^(HERO|HCTL|ICON) " 
echo; echo "########## 2. crest/floor break-in and Kolsass column, 17 July 14-18 UT -- ICON floor v -1.5 at 17 UT"
python wrf3dpbl-diag/breakin_check.py HERO=$H HCTL=$C HOURS=13,14,15,16,17,18,19 2>&1 | tail -22
echo; echo "########## 3. lee buoyancy barrier -- ICON +1.79 K at 17 UT; and the nocturnal slope theta (damage control)"
for R in HERO=$H HCTL=$C; do python wrf3dpbl-diag/lee_barrier_physical.py $R TIMES=13:00,14:00,15:00,16:00,17:00,18:00,20:00,22:00 2>&1 | tail -12; done
echo; echo "########## 4. evening arrival / 0-100 m bias vs HATPRO (17 July 19 UT -> 18 July 05 UT)"
python wrf3dpbl-diag/evening_arrival_check.py HERO=$H HCTL=$C 2>&1 | tail -30
if [ $UPTO = f ]; then
  echo; echo "########## 5. DAY 2 (18 July): break-in and bands"
  python wrf3dpbl-diag/breakin_check.py HERO=$H HCTL=$C HOURS=13,14,15,16,17,18 DAY=18 2>&1 | tail -20
  python wrf3dpbl-diag/onset_bands_multi.py "RUNS=HEROe:2025-07-18_13:00,2025-07-18_13:30,2025-07-18_14:00,2025-07-18_17:00;HCTLe:2025-07-18_13:00,2025-07-18_13:30,2025-07-18_14:00,2025-07-18_17:00" 2>&1 | grep -E "^(HERO|HCTL)" | grep -E "range      1800  v|foreland   1200  w"
fi
echo "########## hero judge done $(date)"
