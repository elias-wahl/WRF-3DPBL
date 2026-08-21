#!/bin/bash
# A13: 12-min restart of X6 from 07:00 with the 1-min budget stream, to diagnose the 07:10 crash of job 8481238.
source "$(dirname "${BASH_SOURCE[0]}")/vsc5.sh"
export WRF_OUTPUT_ROOT=/gpfs/data/fs72996/ewahl/exp/A13
