#!/bin/bash
# Smoke/regression run of the 2026-08-20 rebuild on the devel QOS (X0 configuration, 12 min).
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/smoke
