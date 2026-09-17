#!/bin/bash
# X17m: X17a twin 17 July 13->18 UT (standard terrain, production land state, same forcing/binary) with the standard MYNN boundary layer instead of the 3D closure:
# bl_pbl_physics=5, pbl3d_opt=0, diff_opt=2 (km_opt=4) as in the MYNN control. Discriminates "3D closure" from "WRF dynamics/configuration" as the cause of the lee-slope northerly break-in. DECISIONS 2026-09-18.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X17m
