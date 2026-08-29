#!/bin/bash
#SBATCH --job-name=fb_t2s
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1 --ntasks=1 --time=00:10:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/branko_runs/fallback_%x_%j.out
# Runs only if the first half it depends on did NOT finish (afternotok):
# re-runs the whole pair as 4:30 halves under a new name.
set -u
NAME=${NAME:?}; SETS=${SETS:?}
cd /gpfs/data/fs72996/ewahl
branko/realcase/scripts/run_split_segment.sh ${NAME}r --start 07 --end 12 --split 09:30 \
  --partition zen3_2048 --nodes 1 --wtime 04:30:00 --sets "$SETS"
