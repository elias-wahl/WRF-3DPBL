#!/bin/bash
#SBATCH --job-name=x12_judge
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/exp/x12_judge/%x_%j.out
# Report-only judge for one X12 twin segment: --export=ALL,TAG=X12m|X12p,IDX=a..f, --dependency=afterok:<segment wrf job>.
# Writes exp/x12_judge/<TAG><IDX>.log (Kolsass wind/theta vs lidar+HATPRO, twin side by side). Cancels nothing.
set -u
DATA=/gpfs/data/fs72996/ewahl; mkdir -p $DATA/exp/x12_judge
source ~/miniconda3/etc/profile.d/conda.sh && conda activate proc
python $DATA/wrf3dpbl-diag/judge_x12.py "${TAG:?}" "${IDX:?}" > $DATA/exp/x12_judge/${TAG}${IDX}.log 2>&1
tail -3 $DATA/exp/x12_judge/${TAG}${IDX}.log
