#!/bin/bash
# 2026-08-27 evening (Elias): the four non-gate D segments go on ONE node (10:30 h wall,
# ~3.1 s/step) so backfill finds them sooner; Dctl (8531824) stays on 2 x 128 because the
# bit-for-bit comparison with X7 needs X7's decomposition (KNOWN_ISSUES E14). Priority
# order via --nice (users may only lower priority): the candidate configuration first.
# Run once, from the login node:   bash realcase/scripts/resubmit_d_1node.sh
set -u
DATA=/gpfs/data/fs72996/ewahl
OLD="8531825 8531826 8531827 8531828"          # the 2-node Dsq06 Dbc1 Dsq10 Dsq06bc1
scancel $OLD && echo "cancelled: $OLD"
sleep 3
for spec in Dsq06bc1:0 Dsq06:500 Dbc1:1000 Dsq10:1500; do
  r=${spec%%:*}; nice=${spec##*:}
  d=$DATA/branko_runs/innval_pbl3d_$r
  grep -q -E '^#SBATCH --nodes=1$' $d/submit_wrf.slurm || { echo "$r: not a 1-node script, skipped" >&2; continue; }
  (cd $d && sbatch --nice=$nice submit_wrf.slurm | sed "s/^/$r (nice $nice): /")
done
squeue -u $USER -o "%.9i %.13j %.2t %.10l %.5D %.7Q %R"
