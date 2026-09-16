# Mirror of $DATA/hrldas/tools (the working copies live there, next to the NCAR HRLDAS v5.1.1 clone, which is not our repo).
# make_ldasin.py: ICON surface series -> hourly LDASIN files; make_setup.py: wrfinput + ICON land state at t0 -> HRLDAS setup file;
# hrldas_to_wrfinput.py: HRLDAS RESTART -> land state in a copy of wrfinput_d01; make_twin_rundir.sh: parent run dir -> twin with that wrfinput.
# Edit in $DATA/hrldas/tools, cp -p here, commit. DECISIONS 2026-09-16.
