#!/bin/bash
# X8 on MUSICA: the 23 h run, 2025-07-18 01:00 -> 2025-07-19 00:00, same namelist as
# VSC-5 X8 (pbl3d_sf_pair=1, surface-layer bounds, albedo guard 1fc2fa464). Queued on
# both machines 2026-08-22 because the VSC-5 queue estimate was three days; whichever
# starts first runs, the other is cancelled.
source "$(dirname "${BASH_SOURCE[0]}")/musica.sh"
export WRF_OUTPUT_ROOT=/data/fs201110/ew24501/exp/X8
