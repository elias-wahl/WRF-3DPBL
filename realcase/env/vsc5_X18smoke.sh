#!/bin/bash
# X18smoke: 1 h smoke (17 July 13->14 UT) of the ICON-TERRAIN lineage (parent X12mta: geogrid_icontopo, native ICON levels) with the production
# land state (winter-start HRLDAS restart 13 UT) and production closure settings. Gate for the X18 chain. DECISIONS 2026-09-17 evening.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X18smoke
