#!/bin/bash
# X17a: DAYTIME START 2025-07-17 13:00 UT (twin of X12ma: same physics, met_em, wrfbdy) with the production land state from the
# winter-start HRLDAS spin-up (RESTART.2025071713_DOMAIN1). First segment 13->19 UT; X17b (19->01) and X17c (01->05) follow by
# chain_segment.slurm. Tests whether the realistic surface heating yields the observed evening transition and pool onset
# (Elias 2026-09-17: the cold start at 21 UT may itself be part of the deficit). DECISIONS 2026-09-17.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X17a
