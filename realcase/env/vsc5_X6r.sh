#!/bin/bash
# X6r: continuation of X6 (pbl3d_sf_pair=1) from its 07:00 restart, 07:00 -> 10:00. Same output root as X6 (archive goes to a new jobid).
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X6
