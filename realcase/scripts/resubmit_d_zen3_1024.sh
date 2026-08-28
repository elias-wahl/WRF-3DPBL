#!/bin/bash
# 2026-08-28 (Elias): move the five D segments to the empty lane — partition/QOS zen3_1024
# (27 idle nodes, 224 jobs ahead vs 2249 on zen3_0512), back on 2 nodes x 128 (5:00 h:
# 1.34-1.5 s/step measured -> 4.0-4.5 h + restart read). Node count cannot be changed on a
# pending job without breaking the task layout, so: cancel, edit headers, resubmit.
# Order of submission = tie-break order at equal priority: control first.
set -u
DATA=/gpfs/data/fs72996/ewahl
OLD="8539159 8533211 8533212 8533213 8533214"
scancel $OLD && echo "cancelled: $OLD"
sleep 3
for r in Dctl Dsq06bc1 Dsq06 Dbc1 Dsq10; do
  d=$DATA/branko_runs/innval_pbl3d_$r; S=$d/submit_wrf.slurm
  sed -i -E 's/^#SBATCH --nodes=[0-9]+/#SBATCH --nodes=2/; s/^#SBATCH --time=.*/#SBATCH --time=05:00:00/; s/^#SBATCH --partition=.*/#SBATCH --partition=zen3_1024/; s/^#SBATCH --qos=.*/#SBATCH --qos=zen3_1024/' $S
  grep -q -E '^#SBATCH --hint=nomultithread' $S || sed -i '/^#SBATCH --ntasks-per-node=128/a #SBATCH --hint=nomultithread' $S
  hdr=$(grep -E '^#SBATCH --(nodes|time|partition|qos)' $S | tr '\n' ' ')
  dl=$(find $d -maxdepth 1 -xtype l | wc -l); [ "$dl" -eq 0 ] || { echo "$r: $dl dangling symlinks, skipped" >&2; continue; }
  grep -q 'pbl3d_moist_cond_max *= *10000' $d/namelist.input || { echo "$r: A14 gate not set, skipped" >&2; continue; }
  (cd $d && sbatch submit_wrf.slurm | sed "s/^/$r: /; s/$/  [$hdr]/")
done
squeue -u $USER -o "%.9i %.13j %.2t %.10l %.5D %.7Q %.10P %.20S %R"
