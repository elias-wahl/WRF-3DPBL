#!/bin/bash
# Run one experiment window as two restart-chained halves (2026-08-29; generalises
# split_d_zen3_2048.sh). First half: built now from a restart file and submitted; second half:
# built and submitted by chain_segment.slurm afterok the first (SLURM-resident). Why halves:
# short jobs fit the backfill window and re-use the freed node at once; a restart continuation
# is bit-exact (DECISIONS 2026-08-28 14:00). Archives: exp/<NAME> (first half), exp/<NAME>b.
#
# Usage:
#   run_split_segment.sh <NAME> --start HH --end HH[:MM] --split HH:MM --partition P --nodes N
#        --wtime HH:MM:SS [--rst FILE] [--iofields FILE] [--sets "--set k=v --set k2=v2"] [--dry]
# Defaults: --rst X7's 07:00 restart; --iofields realcase/iofields_d1d2.txt; 30-min WRFlux means;
# always adds --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0 --set pbl3d_moist_cond_max=10000.0
# (A14 gate, E27) and the D stream settings (flux outputs off, output_tke_moments=1).
set -u -o pipefail
DATA=/gpfs/data/fs72996/ewahl; RC=$DATA/branko/realcase
NAME=$1; shift
RST=$DATA/branko_runs/innval_pbl3d_X7/wrfrst_d01_2025-07-18_07:00:00
IOF=$RC/iofields_d1d2.txt; SETS=""; DRY=0; START=""; END=""; SPLIT=""; PART=""; NODES=""; WTIME=""
while [ $# -gt 0 ]; do case $1 in
  --start) START=$2; shift 2;; --end) END=$2; shift 2;; --split) SPLIT=$2; shift 2;;
  --partition) PART=$2; shift 2;; --nodes) NODES=$2; shift 2;; --wtime) WTIME=$2; shift 2;;
  --rst) RST=$2; shift 2;; --iofields) IOF=$2; shift 2;; --sets) SETS=$2; shift 2;; --dry) DRY=1; shift;;
  *) echo "unknown arg $1" >&2; exit 1;; esac; done
for v in START END SPLIT PART NODES WTIME; do [ -n "${!v}" ] || { echo "--$(echo $v | tr A-Z a-z) required" >&2; exit 1; }; done
mins() { local h=${1%%:*}; local m=0; [[ "$1" == *:* ]] && m=${1##*:}; echo $((10#$h*60 + 10#$m)); }
S=$(mins $START); E=$(mins $END); P=$(mins $SPLIT)
[ $S -lt $P ] && [ $P -lt $E ] || { echo "need start < split < end" >&2; exit 1; }
H1=$(( (P-S)/60 )); M1=$(( (P-S)%60 )); H2=$(( (E-P)/60 )); M2=$(( (E-P)%60 ))
RSTMIN=$((P-S))   # restart_interval of the first half = its length -> one restart, at the split
RST_DATE=$(printf "2025-07-18_%02d:%02d:00" $((P/60)) $((P%60)))
START2=$(printf "%02d:%02d" $((P/60)) $((P%60)))
COMMON="--set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0 --set pbl3d_moist_cond_max=10000.0 --set output_t_fluxes=0 --set output_q_fluxes=0 --set output_u_fluxes=0 --set output_v_fluxes=0 --set output_w_fluxes=0 --set output_tke_moments=1"
echo "$NAME: half 1 $START -> $SPLIT (${H1}h${M1}m, restart at $SPLIT), half 2 $SPLIT -> $END (${H2}h${M2}m); $PART x $NODES nodes, $WTIME each"
echo "  sets: $SETS"
[ $DRY -eq 1 ] && { echo "  (dry run: nothing submitted)"; exit 0; }
out=$("$RC/scripts/setup_restart_run.sh" "$NAME" --rst "$RST" --start "$START" --hours $H1 --minutes $M1 --time "$WTIME" \
      --nodes "$NODES" --partition "$PART" --iofields "$IOF" --wrflux-min 30 --set restart_interval=$RSTMIN $COMMON $SETS --submit 2>&1)
echo "$out" | grep -E "FATAL|ERROR|Submitted"
j1=$(echo "$out" | grep -oE "Submitted batch job [0-9]+" | awk '{print $4}'); [ -n "$j1" ] || { echo "!!! first half not submitted"; echo "$out" | tail -20; exit 1; }
d=$DATA/branko_runs/innval_pbl3d_$NAME
EXP="ALL,SEG=${NAME}b,PREV_RUNDIR=$d,RST_DATE=$RST_DATE,START=$START2,HOURS=$H2,MINUTES=$M2,WTIME=$WTIME,WRFLUXMIN=30,NODES=$NODES,PARTITION=$PART,IOFIELDS=$IOF,EXTRA_SETS=--set pbl3d_moist_cond_max=10000.0 --set output_t_fluxes=0 --set output_q_fluxes=0 --set output_u_fluxes=0 --set output_v_fluxes=0 --set output_w_fluxes=0 --set output_tke_moments=1 $SETS,NEXT_SEG=,NEXT_RST_DATE=,NEXT_START=,NEXT_HOURS=,NEXT_WTIME="
j2=$(sbatch --parsable --dependency=afterok:$j1 --export="$EXP" --chdir=$d $RC/scripts/chain_segment.slurm)
echo "  half 1 job $j1 -> chain link $j2 builds ${NAME}b afterok"
