#!/bin/bash
# move_x12_lane.sh <TAG> <partition> (2026-09-04): move the pending first jobs of an X12 chain to another lane.
# VSC-5 cannot re-partition a queued job (KNOWN_ISSUES E31), so: cancel wrf_<TAG>a (and the smoke for mt), their
# dependents (chain link b, judge a, pings), resubmit into <partition> (QOS = partition), re-arm everything, and hand
# LANE on to the chain links so later segments follow. Only touches jobs that are still PENDING.
set -u -o pipefail
TAG=${1:?X12m|X12p|X12mt}; LANE=${2:?zen3_0512|zen3_1024|zen3_2048}; NODES=${3:-2}; WALL=${4:-05:15:00}; SWALL=${5:-01:15:00}   # a-segment wall / smoke wall
DATA=/gpfs/data/fs72996/ewahl; RC=$DATA/branko/realcase
A=$DATA/branko_runs/innval_pbl3d_${TAG}a; SMK=$DATA/branko_runs/innval_pbl3d_${TAG}smoke
pend() { squeue -u $USER -h -t PD -n "$1" -o "%i" | head -1; }
aj=$(pend wrf_${TAG}a); [ -n "$aj" ] || { echo "wrf_${TAG}a not pending -- nothing to move"; exit 1; }
sj=$(pend wrf_${TAG}smoke)
# dependents of the a-job (chain link, judge, pings) -- identified through their dependency strings
deps=$(squeue -u $USER -h -t PD -o "%i %E" | awk -v a="$aj" -v s="${sj:-none}" '$2 ~ a || $2 ~ s {print $1}' | tr '\n' ' ')
echo "cancelling: a=$aj smoke=${sj:-none} dependents=[$deps]"
scancel $aj ${sj:-} $deps
for d in "$A" ${sj:+"$SMK"}; do
  sed -i -E -e "s/^#SBATCH --partition=.*/#SBATCH --partition=$LANE/" -e "s/^#SBATCH --qos=.*/#SBATCH --qos=$LANE/" \
            -e "s/^#SBATCH --nodes=.*/#SBATCH --nodes=$NODES/" "$d/submit_wrf.slurm"
done
sed -i -E "s/^#SBATCH --time=.*/#SBATCH --time=$WALL/" "$A/submit_wrf.slurm"
[ -n "$sj" ] && sed -i -E "s/^#SBATCH --time=.*/#SBATCH --time=$SWALL/" "$SMK/submit_wrf.slurm"
if [ -n "$sj" ]; then
  sw=$(cd "$SMK" && sbatch --parsable submit_wrf.slurm)
  aw=$(cd "$A" && sbatch --parsable --dependency=afterok:$sw submit_wrf.slurm)
  sbatch --parsable --dependency=afternotok:$sw --export=ALL,STAGE=${TAG}smoke,FAILED_JOB=$sw "$RC/scripts/notify_x12.slurm" >/dev/null
  echo "smoke=$sw"
else
  aw=$(cd "$A" && sbatch --parsable submit_wrf.slurm)
fi
lb=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,IDX=b,TAG=$TAG,LANE=$LANE,NODES=$NODES --chdir="$A" "$RC/scripts/chain_x12.slurm")
jg=$(sbatch --parsable --dependency=afterok:$aw --export=ALL,TAG=$TAG,IDX=a "$RC/scripts/judge_x12.slurm")
for j in "$aw ${TAG}a" "$lb ${TAG}-chain-b"; do set -- $j
  sbatch --parsable --dependency=afternotok:$1 --export=ALL,STAGE=$2,FAILED_JOB=$1 "$RC/scripts/notify_x12.slurm" >/dev/null
done
echo "$TAG moved to $LANE ($NODES nodes, $WALL): a=$aw link_b=$lb judge_a=$jg (pings armed)"
