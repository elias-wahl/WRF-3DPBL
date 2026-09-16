#!/bin/bash
# X16s: twin of X16b (evening cold start 2025-07-17 21:00 UT, 8 h to 05 UT, same physics, met_em, wrfbdy) with the LAND STATE
# replaced by the HRLDAS spin-up (A28): TSLB/SMOIS/SH2O/TSK/SNOW/SNOWH/SNOWC/CANWAT/LAI from RESTART.2025071721_DOMAIN1
# (hrldas_runs/spinup2025_july). Gates: slope HFX -> -13..-15 W m-2, GRDFLX -> -41..-47, LW-up at Weerberg/Hochhaeuser, drainage at
# Eggen/StanserJoch, HATPRO 21->01 cooling (-3.4/-3.1 K). DECISIONS 2026-09-16.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X16s
