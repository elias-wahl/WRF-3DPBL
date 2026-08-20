#!/usr/bin/env python3
"""Add the q^2 budget diagnostic stream (auxhist23) to a namelist.input.

Called by setup_rundir.sh --qsq-diag. Separate from prepare_namelist.py because
this is a diagnostic overlay for OPEN_ISSUES A9, not part of the case setup:
it should be easy to drop once A9 is closed.

Stream 23 matches the stream MUSICA job 88971 used, so frames are directly
comparable with the evidence written up in A9. The stream carries only what
iofields_qsq.txt assigns to it -- an auxhist stream is empty by default.
"""
import re
import sys

BLOCK = """ ! --- q^2 budget diagnostic, OPEN_ISSUES A9 (setup_rundir.sh --qsq-diag) -----
 ! Stream 23 carries ONLY what iofields_qsq.txt puts in it: the five q^2
 ! budget terms plus Q_SQ (the runaway quantity) and W (the symptom).
 ! 1-minute frames at ~675 MB each -- ~25 GB to reach the 01:38 blowup.
 auxhist23_outname      = "{root}/temp/branko/qsqdiag_d<domain>_<date>.nc"
 auxhist23_interval_m   = 1,
 auxhist23_interval_s   = 0,
 frames_per_auxhist23   = 1,
 io_form_auxhist23      = 2,
"""


def main():
    path = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else ""
    txt = open(path).read()

    # Point iofields_filename at the q^2 file. The default namelist ships
    # "NONE_SPECIFIED"; without this the stream is declared but stays empty.
    txt, n = re.subn(r'(\n\s*iofields_filename\s*=\s*)"[^"]*"',
                     r'\1"iofields_qsq.txt"', txt, count=1)
    if n:
        print("    iofields_filename <- iofields_qsq.txt")
    else:
        print("!!! no iofields_filename in the namelist -- stream 23 would be "
              "empty; add it by hand", file=sys.stderr)
        return 1

    if "auxhist23_outname" in txt:
        print("    auxhist23 already configured, left alone")
    else:
        m = re.search(r"&time_control\b", txt)
        if not m:
            print("!!! no &time_control group found", file=sys.stderr)
            return 1
        # The group terminator is a line whose only content is '/'.
        end = re.search(r"\n\s*/\s*(?:\n|$)", txt[m.end():])
        if not end:
            print("!!! &time_control has no terminating '/'", file=sys.stderr)
            return 1
        at = m.end() + end.start() + 1
        txt = txt[:at] + BLOCK.format(root=root or "@OUTPUT_ROOT@") + txt[at:]
        print("    auxhist23 block inserted into &time_control")

    open(path, "w").write(txt)

    # An unexpanded token here is fatal by the same convention
    # prepare_namelist.py enforces -- wrf.exe would write to a literal
    # '@OUTPUT_ROOT@' directory and die partway into the run.
    # Only the VALUE matters: the template mentions @OUTPUT_ROOT@ in trailing
    # comments to say where the path comes from, and those are not a problem.
    # Strip everything after '!' before testing, or this fires on every run.
    live = "\n".join(line.split("!", 1)[0] for line in txt.splitlines())
    if "@OUTPUT_ROOT@" in live:
        print("!!! namelist still contains @OUTPUT_ROOT@ -- WRF_OUTPUT_ROOT "
              "was not set in the env file", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
