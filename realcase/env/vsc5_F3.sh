#!/bin/bash
# F3: fog/cold-air feedback diagnosis (DECISIONS 2026-08-21): restart of X6 from 04:00 -> 07:30, 5-min stream + 30-min WRFlux budgets.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/F3
