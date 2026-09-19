#!/bin/bash
# X25: X17a twin 13->18 UT with the operational-MYNN-like master length (pbl3d_l_opt=5), the diffusion-number cap (pbl3d_dn_max=0.4) and crest roughness Z0MVT(19)=0.30 m: does deeper daytime mixing plus ICON-level crest drag remove the shallow crest northerly? DECISIONS 2026-09-19.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X25
