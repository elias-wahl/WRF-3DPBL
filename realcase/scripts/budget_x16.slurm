#!/bin/bash
#SBATCH --job-name=budget_x16
#SBATCH --account=p72996
#SBATCH --partition=zen3_0512
#SBATCH --qos=zen3_0512_devel
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=/gpfs/data/fs72996/ewahl/exp/x16_judge/%x_%j.out
# SLURM-resident follow-up for a WRFlux-instrumented night run: --export=ALL,RUN=X16w --dependency=afterany:<wrf job>.
# Writes exp/x16_judge/<RUN>_budget.log (x16_theta_budget.py: theta budget per window/layer vs HATPRO). Cancels nothing.
set -u
DATA=/gpfs/data/fs72996/ewahl; RUN=${RUN:-X16w}
source ~/miniconda3/etc/profile.d/conda.sh && conda activate proc
{ echo "=== $(date) archive: $(ls -d $DATA/exp/$RUN/wrf_output/*/ 2>/dev/null | tail -1)"
  ls $DATA/exp/$RUN/wrf_output/*/ 2>/dev/null | grep -cE "meanout" | sed 's/^/meanout files: /'
  python $DATA/wrf3dpbl-diag/x16_theta_budget.py "$RUN" ${T0:-2025-07-17_21:30:00} ${T1:-2025-07-18_01:00:00}; } > $DATA/exp/x16_judge/${RUN}_budget.log 2>&1
tail -8 $DATA/exp/x16_judge/${RUN}_budget.log
