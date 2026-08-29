#!/bin/bash
# The D1/D2 restart segments of 2026-08-27 (DECISIONS 2026-08-27 14:00 / 14:30 / 15:20):
# six-hour daytime runs 07:00 -> 13:00 UTC from X7's 07:00 restart, on the reference
# layout (2 nodes x 128), one per switch setting.
#
#   Dctl       pbl3d_sq=0.2  pbl3d_sfc_qsq_bc=0   control (new binary, switches off);
#                                                 its 07:30-10:00 frames must equal X7's
#                                                 bit for bit (bitcompare.py) before any
#                                                 other run is trusted
#   Dsq06      pbl3d_sq=0.6                       D1: q^2 diffusivity x3
#   Dsq10      pbl3d_sq=1.0                       D1: x5
#   Dbc1       pbl3d_sfc_qsq_bc=1                 D2: lowest level q^2 >= B1^(2/3) u*^2
#   Dsq06bc1   both
#
# Every run: history every 30 min thinned by iofields_d1d2.txt (~3.6 GB/frame), WRFlux
# stream every 30 min with output_*_fluxes=0 and output_tke_moments=1 (subgrid time
# means only, <1 GB/frame), no restart files, pbl3d_init_opt=0 / pbl3d_l0_min=0.0 as
# in X7 (KNOWN_ISSUES E19). The namelist is diffed against X7's at the end: only the
# keys listed under "expected" may differ.
#
# Usage:
#   setup_d1d2_segments.sh smoke [--submit]   12-min devel-QOS run, every switch ON
#   setup_d1d2_segments.sh wave1 [--submit]   Dctl Dsq06 Dbc1        (~170 GB)
#   setup_d1d2_segments.sh wave2 [--submit]   Dsq10 Dsq06bc1         (~115 GB)
#   setup_d1d2_segments.sh one NAME key=val ... [--submit]
#   setup_d1d2_segments.sh check NAME ...       namelist diff vs X7 only
# Two waves because the filesystem had 345 GB free at 97 % on 2026-08-27.
# 2026-08-27 evening: the four switch runs were re-queued on ONE node (10:30 h) by
# resubmit_d_1node.sh; only Dctl keeps the 2 x 128 layout (bit-for-bit vs X7, E14).
set -u -o pipefail
DATA=/gpfs/data/fs72996/ewahl
HERE=$(cd "$(dirname "$0")" && pwd)
RC=$(cd "$HERE/.." && pwd)
RST=$DATA/branko_runs/innval_pbl3d_X7/wrfrst_d01_2025-07-18_07:00:00
PARENT_NL=$DATA/branko_runs/innval_pbl3d_X7/namelist.input
[ -f "$RST" ] || { echo "restart file missing: $RST" >&2; exit 1; }

MODE=${1:-}; shift || true
SUBMIT=""
COMMON=(--rst "$RST" --start 07 --iofields "$RC/iofields_d1d2.txt"
        --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0
        --set output_t_fluxes=0 --set output_q_fluxes=0 --set output_u_fluxes=0
        --set output_v_fluxes=0 --set output_w_fluxes=0 --set output_tke_moments=1
        --set pbl3d_moist_cond_max=10000.0)
EXPECTED='restart|start_hour|run_days|run_hours|run_minutes|end_day|end_hour|end_minute|restart_interval|override_restart_timers|iofields_filename|history_interval|auxhist24_interval_m|auxhist24_outname|history_outname|avg_interval|output_._fluxes|output_tke_moments|pbl3d_sq|pbl3d_sfc_qsq_bc|pbl3d_sfc_qsq_zmax|pbl3d_sq_implicit|pbl3d_t2_scalar|pbl3d_moist_cond_max'
# pbl3d_moist_cond_max = 10000.0: the A14 gate (DECISIONS 2026-08-24). The segments run 07->13 THROUGH the
# A14 window; with the gate off Dctl (8531824) blew up at 11:04 like X8a at 10:18 (2026-08-28). The
# Whether the gate fires before 10:00 is NOT measured (X9a started at 10:00), so a segment with the gate on is
# not a bit-for-bit reference against X7; that check is done by 6-min devel runs from the same restart (BB* runs).

nl_diff() {   # differences against the parent run's namelist, key by key
  local nl=$1
  echo "=== namelist keys differing from X7 (KNOWN_ISSUES E19); expected: time/output keys + the switch under test"
  diff <(grep -E '^ [a-z0-9_]+ *=' "$PARENT_NL" | sed -E 's/!.*//; s/ +/ /g; s/ *$//' | sort) \
       <(grep -E '^ [a-z0-9_]+ *=' "$nl"        | sed -E 's/!.*//; s/ +/ /g; s/ *$//' | sort) \
    | grep '^[<>]' | grep -v -E "^[<>] +($EXPECTED) " > "$nl.diff_vs_X7" || true   # (pipefail: diff exits 1 on any difference)
  if [ -s "$nl.diff_vs_X7" ]; then
    cat "$nl.diff_vs_X7"; echo "!!! UNEXPECTED differences above"
  else
    echo "    only expected keys differ"
  fi
}

one() {
  local name=$1; shift
  local -a extra=()
  for kv in "$@"; do extra+=(--set "$kv"); done
  echo; echo "################ $name ${*:-}"
  "$HERE/setup_restart_run.sh" "$name" "${COMMON[@]}" --hours 6 --history-min 30 --wrflux-min 30 \
      --nodes 2 --time 05:30:00 "${extra[@]}" $SUBMIT || return 1
  nl_diff "$DATA/branko_runs/innval_pbl3d_$name/namelist.input"
}

case "$MODE" in
  smoke)
    [ "${1:-}" = "--submit" ] && SUBMIT=--submit
    "$HERE/setup_restart_run.sh" Dsmoke "${COMMON[@]}" --hours 0 --minutes 12 \
        --history-min 6 --wrflux-min 6 --set avg_interval=360 \
        --set pbl3d_sq=0.6 --set pbl3d_sfc_qsq_bc=2 --qos devel --nodes 5 $SUBMIT || exit 1
    nl_diff "$DATA/branko_runs/innval_pbl3d_Dsmoke/namelist.input"
    ;;
  wave1)
    [ "${1:-}" = "--submit" ] && SUBMIT=--submit
    one Dctl && one Dsq06 pbl3d_sq=0.6 && one Dbc1 pbl3d_sfc_qsq_bc=1
    ;;
  wave2)
    [ "${1:-}" = "--submit" ] && SUBMIT=--submit
    one Dsq10 pbl3d_sq=1.0 && one Dsq06bc1 pbl3d_sq=0.6 pbl3d_sfc_qsq_bc=1
    ;;
  check)   # namelist diff only, for existing run dirs
    for n in "$@"; do echo "################ $n"; nl_diff "$DATA/branko_runs/innval_pbl3d_$n/namelist.input"; done
    ;;
  one)
    NAME=$1; shift
    ARGS=(); for a in "$@"; do [ "$a" = "--submit" ] && SUBMIT=--submit || ARGS+=("$a"); done
    one "$NAME" "${ARGS[@]}"
    ;;
  *) sed -n '2,28p' "$0"; exit 1 ;;
esac
