#!/bin/bash
# Tune the four pending 1-node D-segment jobs (2026-08-28, Elias):
#   - TimeLimit 10:30 -> 9:30  (measured 1.34 s/step on 256 ranks => ~2.7-2.9 s/step
#     on 128 ranks => 8.1-8.7 h + ~15 min restart read; 9:30 keeps ~45 min margin)
#   - Nice -> 0 (drop the priority handicap; submission order still breaks ties)
# Only touches PENDING jobs; a job that already started keeps its limit.
set -u
JOBS="8533211 8533212 8533213 8533214"
for j in $JOBS; do
  st=$(squeue -h -j "$j" -o %t 2>/dev/null)
  if [ "$st" != "PD" ]; then
    echo "$j: state '${st:-gone}', skipped"
    continue
  fi
  scontrol update JobId="$j" TimeLimit=9:30:00 Nice=0 \
    && echo "$j: TimeLimit=9:30:00 Nice=0"
done
squeue -u "$USER" -o "%.9i %.13j %.2t %.10M %.10l %.5D %.7Q %.20S %R"
