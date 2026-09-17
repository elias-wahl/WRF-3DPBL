#!/bin/bash
# X19a: X17a twin (17 July 13->19 UT, standard terrain, production land state) with BOTH A29 roughness fixes in a run-local table copy:
# class 19 bare-ground roughness 0.05 m, and CORINE urban classes 31-33 flagged urban (URBTYPE_beg=30; z0 0.5 m, canopy 8 m). DECISIONS 2026-09-17.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/X19a
