#!/bin/bash
# X9n: the X7 configuration bit for bit, plus pbl3d_moist_cond_max=1e4 (A14 fix armed),
# 01:00 -> 10:00, 2026-08-24 -- does the nocturnal stable-regime statistics shift under
# the moist-solve acceptance? Compare against exp/X7 statistically (E14).
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X9n
