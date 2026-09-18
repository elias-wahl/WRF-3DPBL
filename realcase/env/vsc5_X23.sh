#!/bin/bash
# X23: X17a twin 13->18 UT with the barren/sparse class (19) roughness set to ICON median over the crests, Z0MVT(19)=0.30 m (target: ICON crest Cd10 16e-3; X19r with 0.20 m gave 13e-3) (A29 opt-in bare-ground path), nothing else: clean test of the crest surface-drag deficit (WRF Cd10 4.9e-3 vs ICON 16e-3). DECISIONS 2026-09-18.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X23
