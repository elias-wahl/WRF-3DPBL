#!/bin/bash
# X16b: evening COLD START 2025-07-17 21:00 UT from the native ICON analysis (calm Kolsass, flat along-valley structure), 8 h to 05 UT, X12m physics.
# Tests whether WRF re-creates the up-valley wind / warm wide reach from a calm state (evening physics) or holds the calm (daytime heating is the origin). DECISIONS 2026-09-10 ~15:00
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X16b
