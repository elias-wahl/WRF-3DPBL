#!/bin/bash
# Stitch each D segment's two halves (exp/<run>/wrf_output/<j1>: 07:30-10:00, exp/<run>b/wrf_output/<j2>:
# 10:30-13:00) into a pseudo-job $DATA/wrf_output/<FAKE>/ so proc treats it like one archive
# (pattern: synthesize_day.sh). Symlinks only. Colour/legend key = second-to-last component of the
# "WRF run path:" line in job_info.txt (proc/util/wrf.py) -> the run's name; add matching entries
# under colors: in proc/config/config.yaml and the FAKE ids under paths.job_ids to include them.
#   stitch_d.sh [Dctl Dsq06bc1 ...]     (default: all five)   -- idempotent, re-run after new archives
set -u
DATA=/gpfs/data/fs72996/ewahl
declare -A FAKE=([Dctl]=9999101 [Dsq06bc1]=9999102 [Dsq06]=9999103 [Dbc1]=9999104 [Dsq10]=9999105)
for r in ${@:-Dctl Dsq06bc1 Dsq06 Dbc1 Dsq10}; do
  DST=$DATA/wrf_output/${FAKE[$r]}; mkdir -p $DST
  find $DST -maxdepth 1 -xtype l -delete
  # newest archive per segment only: exp/Dctl/wrf_output also holds the crashed 8531824 (gate off, 2 x 128)
  SRCS=(); for seg in $r ${r}b; do d=$(ls -d $DATA/exp/$seg/wrf_output/*/ 2>/dev/null | sort | tail -1); [ -n "$d" ] && [ "$(ls $d | grep -c wrfout)" -gt 0 ] && SRCS+=("${d%/}"); done
  n=0; for src in ${SRCS[@]+"${SRCS[@]}"}; do for f in $src/wrfout_d01_* $src/meanout_d01_*; do [ -e "$f" ] || continue; b=$(basename $f); [ -e $DST/$b ] || { ln -s $f $DST/$b; n=$((n+1)); }; done; done
  { echo "Job ID: ${FAKE[$r]} (pseudo-job -- stitched halves of $r, not a real SLURM job)"; echo "Start time: $(date)"
    echo "WRF run path: $DATA/$r/run"; echo "Namelist used: see sources"; echo "Sources (07->10 then 10->13), 1 x 128, pbl3d_moist_cond_max=1e4, WRFlux flux outputs off (E26):"
    for s in ${SRCS[@]+"${SRCS[@]}"}; do echo "  $s"; done; } > $DST/job_info.txt
  miss=""; for t in 07:30 08:00 08:30 09:00 09:30 10:00 10:30 11:00 11:30 12:00 12:30 13:00; do [ -e $DST/wrfout_d01_2025-07-18_$t:00.nc ] || miss="$miss $t"; done
  echo "$r -> ${FAKE[$r]}: sources ${#SRCS[@]}, $n new links, $(ls $DST | grep -c wrfout) wrfout; missing:${miss:- none}"
done
