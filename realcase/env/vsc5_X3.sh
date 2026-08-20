#!/bin/bash
# Experiment X3: same environment as vsc5.sh, separate output root so concurrent runs
# do not collide in temp/branko/ (see DECISIONS.md 2026-08-20).
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X3
