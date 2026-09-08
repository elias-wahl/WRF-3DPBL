#!/usr/bin/env python3
"""Splice the X13 refined near-surface level set into a namelist (in place).

X13 = X12m physics/forcing with 9 extra levels below ~600 m AGL (valley):
the first full layer is kept at 24 m (first mass level ~12 m, surface layer
untouched), layers 2..N are ~15 m up to ~145 m and ~16.5 m up to ~260 m,
then a smooth geometric rejoin to the unchanged X12 ladder at eta=0.9339
(~610 m valley AGL). e_vert 80 -> 89. Crest-cell minimum layer ~8.5 m
(vs 13.5 in X12) -- the 1 h daytime smoke gates the vertical CFL.
Usage: set_eta_x13.py <namelist.input>
"""
import re
import sys

# 1.0 .. 0.9339: refined (28 values); tail from 0.9275 on: X12's list unchanged.
REFINED = [
    1.0000, 0.9974,
    # ~15 m layers to ~145 m
    0.99576, 0.99413, 0.99249, 0.99085, 0.98921, 0.98758, 0.98594, 0.98430,
    # ~16.5 m layers to ~260 m
    0.98251, 0.98073, 0.97894, 0.97716, 0.97537, 0.97359, 0.97180,
    # geometric rejoin (~19 -> 48 m) to the old ladder
    0.96975, 0.96749, 0.96501, 0.96228, 0.95928, 0.95598, 0.95235,
    0.94835, 0.94395, 0.93911, 0.93390,
]
TAIL = [
    0.9275, 0.9206, 0.9132, 0.9053, 0.8969, 0.8880, 0.8786, 0.8685,
    0.8579, 0.8467, 0.8349, 0.8225, 0.8095, 0.7959, 0.7817, 0.7669,
    0.7515, 0.7355, 0.7189, 0.7018, 0.6841, 0.6658, 0.6471, 0.6279,
    0.6082, 0.5881, 0.5677, 0.5469, 0.5257, 0.5044, 0.4828, 0.4610,
    0.4392, 0.4173, 0.3954, 0.3735, 0.3518, 0.3302, 0.3089, 0.2879,
    0.2672, 0.2470, 0.2272, 0.2080, 0.1894, 0.1715, 0.1542, 0.1377,
    0.1220, 0.1071, 0.0931, 0.0799, 0.0677, 0.0563, 0.0459, 0.0363,
    0.0275, 0.0196, 0.0124, 0.0059, 0.0000,
]
LEVELS = REFINED + TAIL
assert len(LEVELS) == 89, len(LEVELS)
assert all(a > b for a, b in zip(LEVELS, LEVELS[1:])), "eta not monotonic"

path = sys.argv[1]
text = open(path).read()

text, n = re.subn(r"^( e_vert\s*=\s*)\d+,", r"\g<1>89,", text, flags=re.M)
assert n == 1, "e_vert not found"

rows = [", ".join(f"{v:.5f}" for v in LEVELS[i:i + 5]) + "," for i in range(0, 89, 5)]
block = " eta_levels             = " + ("\n" + " " * 26).join(rows)
# replace the whole existing multi-line eta_levels block (continuation lines
# are runs of numbers/commas/whitespace)
text, n = re.subn(r"^ eta_levels\s*=[^\n]*\n(?:[ \t]+[0-9., \t]+\n)*", block + "\n",
                  text, flags=re.M)
assert n == 1, "eta_levels block not found"

open(path, "w").write(text)
nl = text.count("eta_levels")
print(f"{path}: e_vert=89, {len(LEVELS)} eta levels spliced")
