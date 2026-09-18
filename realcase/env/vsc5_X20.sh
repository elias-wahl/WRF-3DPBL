#!/bin/bash
# X20: X17a twin (17 July 13->21 UT, standard terrain, production winter-spun-up land state, same forcing/binary, 3D closure) with the
# A30 land-cover set in a run-local NoahmpTable.TBL + wrfinput LU_INDEX relabel: (1) class 14 MP 6->9, VCMX25 50->60; (2) class-2 cells
# above 700 m relabelled to class 3 = 'mountain meadow' (LAI Jun-Aug 4.5, HVT 0.5, Z0MVT 0.06); (3) class 11 VCMX25 60->80, class 15 55->65;
# (4) class 19 sparse alpine vegetation (grassland optics/physiology, LAI 0.5, HVT 0.3, Z0MVT 0.05). Towns (31-33) unchanged. DECISIONS 2026-09-18.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X20
