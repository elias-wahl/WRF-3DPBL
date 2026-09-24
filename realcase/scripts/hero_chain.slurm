#!/bin/bash
#SBATCH --job-name=hero_chain
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=hero_chain_%j.out
#
# SLURM-resident link for the hero pair's restart segments (2026-09-22). Segment table (restart_interval 180 from 01 UT):
#   6-h segments (2026-09-23, for backfill): a 17 Jul 01-07  b 07-13  c 13-19  d 19-01  e 18 Jul 01-07  f 07-13  g 13-19  h 19-00 (5 h)
# Submit with --export=ALL,RUN=HERO,IDX=b --dependency=afterok:<segment a wrf job>. Builds branko_runs/innval_pbl3d_<RUN><IDX>
# as a copy of the previous segment's dir (same namelist apart from times/restart/output root; tables, wrfinput/wrfbdy, urban
# tables, iofields carried over; restart file linked), submits wrf.exe, and queues the next link afterok.
set -u
D=/gpfs/data/fs72996/ewahl; RC=$D/branko/realcase
: "${RUN:?}" "${IDX:?}"
declare -A SDAY=([a]=17 [b]=17 [c]=17 [d]=17 [e]=18 [f]=18 [g]=18 [h]=18) SHR=([a]=01 [b]=07 [c]=13 [d]=19 [e]=01 [f]=07 [g]=13 [h]=19)
declare -A EDAY=([a]=17 [b]=17 [c]=17 [d]=18 [e]=18 [f]=18 [g]=18 [h]=19) EHR=([a]=07 [b]=13 [c]=19 [d]=01 [e]=07 [f]=13 [g]=19 [h]=00) HRS=([a]=6 [b]=6 [c]=6 [d]=6 [e]=6 [f]=6 [g]=6 [h]=5)
declare -A WT=([a]=05:15:00 [b]=05:15:00 [c]=05:15:00 [d]=05:15:00 [e]=05:15:00 [f]=05:15:00 [g]=05:15:00 [h]=04:30:00) NXT=([a]=b [b]=c [c]=d [d]=e [e]=f [f]=g [g]=h [h]=)
PREV_IDX=$(echo "$IDX" | tr 'b-h' 'a-g'); [ "$PREV_IDX" = a ] && PREV=$D/branko_runs/innval_pbl3d_$RUN || PREV=$D/branko_runs/innval_pbl3d_$RUN$PREV_IDX
NEW=$D/branko_runs/innval_pbl3d_$RUN$IDX; RST=$PREV/wrfrst_d01_2025-07-${SDAY[$IDX]}_${SHR[$IDX]}:00:00
[ -f "$RST" ] || { echo "!!! restart missing: $RST"; exit 1; }
rm -rf $NEW; mkdir -p $NEW $D/exp/$RUN$IDX/temp/branko
for f in $PREV/*; do b=$(basename $f); case $b in wrfrst_*|wrfout*|rsl.*|wrf.*.out|wrf.*.err|namelist.output|env.sh|namelist.input) ;; wrfinput_d01|wrfbdy_d01) ln $(readlink -f $f) $NEW/$b;; *) cp -a $f $NEW/;; esac; done
ln -s $RST $NEW/$(basename $RST)
PREVNAME=$(basename $PREV | sed 's/innval_pbl3d_//')
sed "s#exp/$PREVNAME/#exp/$RUN$IDX/#g; s/^ start_day *= *[0-9]*,/ start_day              = ${SDAY[$IDX]},/; s/^ start_hour *= *[0-9]*,/ start_hour             = ${SHR[$IDX]},/; s/^ end_day *= *[0-9]*,/ end_day                = ${EDAY[$IDX]},/; s/^ end_hour *= *[0-9]*,/ end_hour               = ${EHR[$IDX]},/; s/^ run_hours *= *[0-9]*,/ run_hours              = ${HRS[$IDX]},/; s/^ run_days *= *[0-9]*,/ run_days               = 0,/; s/^ restart *= *\.false\.,/ restart                = .true.,/" $PREV/namelist.input > $NEW/namelist.input
grep -q "override_restart_timers" $NEW/namelist.input || sed -i "s/^ restart                = .true.,/ restart                = .true.,\n override_restart_timers = .true.,/" $NEW/namelist.input
printf 'source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"\nexport WRF_OUTPUT_ROOT=%s/exp/%s\n' $D $RUN$IDX > $RC/env/vsc5_$RUN$IDX.sh
sed "s#vsc5_$PREVNAME.sh#vsc5_$RUN$IDX.sh#" $PREV/env.sh > $NEW/env.sh
sed -i "s/job-name=wrf_$PREVNAME/job-name=wrf_$RUN$IDX/; s/^#SBATCH --time=.*/#SBATCH --time=${WT[$IDX]}/" $NEW/submit_wrf.slurm
echo "--- $RUN$IDX namelist diff vs previous:"; diff $PREV/namelist.input $NEW/namelist.input | grep "^>" | grep -v outname | cut -c1-80
find $NEW -maxdepth 1 -xtype l && { echo "!!! dangling symlink"; exit 1; }
cd $NEW && jid=$(sbatch --parsable submit_wrf.slurm) && echo "hero chain: $RUN$IDX submitted as $jid"
if [ -n "${NXT[$IDX]}" ]; then nj=$(sbatch --parsable --dependency=afterok:$jid --export=ALL,RUN=$RUN,IDX=${NXT[$IDX]} --chdir=$NEW $RC/scripts/hero_chain.slurm); echo "hero chain: next link ${NXT[$IDX]} queued as $nj (afterok:$jid)"; fi
# report-only judge after the day-1 night (segment d, to 01 UT) and after the whole run (h); it waits for BOTH runs' segment via a
# marker: the HERO link submits it afterany its own segment and the judge itself waits for the HCTL segment's output to exist.
if [ "$RUN" = HERO ] && { [ "$IDX" = d ] || [ "$IDX" = h ]; }; then jj=$(sbatch --parsable --dependency=afterany:$jid --export=ALL,UPTO=$IDX $RC/scripts/hero_judge.slurm); echo "hero chain: judge (up to $IDX) queued as $jj (afterany:$jid)"; fi
