#!/bin/bash
# 2026-08-28 (Elias): the five D segments (07->13) as two 3-h halves each on zen3_2048, 1 x 128,
# 5:00 h per half. Why: the backfill scan is global and ~1750 jobs deep; at priority ~1.09e5 our
# jobs are never examined on zen3_0512/zen3_1024, while on zen3_2048 every pending job is below
# us, so the main scheduler takes us as soon as a node frees (19:57, 06:27, 10:22 x4). Halves
# keep each job at 5 h and let the freed node be re-used at once. The first half is the existing
# run dir cut at 10:00 with a restart written; the second half is built and submitted by
# chain_segment.slurm (afterok) -- SLURM-resident, no session needed. Restart continuation is
# bit-exact (BBA vs BBA2, DECISIONS 2026-08-28 14:00); the second half's namelist reproduces the
# parent's except start/length/paths (checked by a test build of Dctlb before this script ran).
set -u
DATA=/gpfs/data/fs72996/ewahl; RC=$DATA/branko/realcase
OLD="8539492 8539493 8539494 8539495 8539496"
scancel $OLD && echo "cancelled: $OLD"; sleep 3
COMMON_SETS="--set pbl3d_moist_cond_max=10000.0 --set output_t_fluxes=0 --set output_q_fluxes=0 --set output_u_fluxes=0 --set output_v_fluxes=0 --set output_w_fluxes=0 --set output_tke_moments=1"
for spec in Dctl:0.2:0 Dsq06bc1:0.6:1 Dsq06:0.6:0 Dbc1:0.2:1 Dsq10:1.0:0; do
  IFS=: read r sq bc <<<"$spec"; d=$DATA/branko_runs/innval_pbl3d_$r; NL=$d/namelist.input; S=$d/submit_wrf.slurm
  # sanity: the run dir's own switches must match the table
  grep -qE "^ pbl3d_sq\s*=\s*$sq," $NL && grep -qE "^ pbl3d_sfc_qsq_bc\s*=\s*$bc," $NL || { echo "$r: switch mismatch (expected sq=$sq bc=$bc)" >&2; continue; }
  grep -q 'pbl3d_moist_cond_max *= *10000' $NL || { echo "$r: A14 gate not set" >&2; continue; }
  # first half: 07->10, write the 10:00 restart
  sed -i -E 's/^( run_hours[[:space:]]*=[[:space:]]*)[^,!]*/\13/; s/^( end_hour[[:space:]]*=[[:space:]]*)[^,!]*/\110/; s/^( restart_interval[[:space:]]*=[[:space:]]*)[^,!]*/\1180/' $NL
  sed -i -E 's/^#SBATCH --nodes=.*/#SBATCH --nodes=1/; s/^#SBATCH --time=.*/#SBATCH --time=05:00:00/; s/^#SBATCH --partition=.*/#SBATCH --partition=zen3_2048/; s/^#SBATCH --qos=.*/#SBATCH --qos=zen3_2048/' $S
  [ $(find $d -maxdepth 1 -xtype l | wc -l) -eq 0 ] || { echo "$r: dangling symlinks" >&2; continue; }
  j1=$(cd $d && sbatch --parsable submit_wrf.slurm) || { echo "$r: sbatch failed" >&2; continue; }
  # second half: chain link builds ${r}b from the 10:00 restart and submits it afterok
  EXP="ALL,SEG=${r}b,PREV_RUNDIR=$d,RST_DATE=2025-07-18_10:00:00,START=10,HOURS=3,WTIME=05:00:00,WRFLUXMIN=30,NODES=1,PARTITION=zen3_2048,IOFIELDS=$RC/iofields_d1d2.txt,EXTRA_SETS=$COMMON_SETS --set pbl3d_sq=$sq --set pbl3d_sfc_qsq_bc=$bc,NEXT_SEG=,NEXT_RST_DATE=,NEXT_START=,NEXT_HOURS=,NEXT_WTIME="
  j2=$(sbatch --parsable --dependency=afterok:$j1 --export="$EXP" --chdir=$d $RC/scripts/chain_segment.slurm)
  echo "$r: half 1 (07->10) job $j1  [$(grep -E '^#SBATCH --(nodes|time|partition)' $S | sed 's/#SBATCH --//' | tr '\n' ' ')]  -> chain link $j2 builds ${r}b (10->13) afterok"
done
squeue -u $USER -o "%.9i %.13j %.2t %.10l %.5D %.7Q %.10P %R"
