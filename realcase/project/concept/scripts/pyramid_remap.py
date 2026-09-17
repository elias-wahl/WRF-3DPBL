#!/usr/bin/env python3
"""Shift the along-ground (x) coordinates of every block of a pyramid master: \\pb, \\pbf, \\hl, \\pbunion
(text anchor, pieces, outline). Usage:  pyramid_remap.py FILE "0.2:+0.15,2.0:+0.35,11.5:-0.05"
Each pair is threshold:shift; a coordinate takes the shift of the last threshold it reaches (x >= threshold),
coordinates below the first threshold stay. Afterwards set individual blocks by hand or script, then rerun
make_moons.py and make_pyramid_vertical.py on FILE. A block whose text overflows enlarges the picture and
adds a page: check the page count after every change."""
import re, sys, pathlib
P = pathlib.Path(sys.argv[1]); rules = sorted((float(a), float(b)) for a, b in (r.split(":") for r in sys.argv[2].split(",")))
fmt = lambda v: f"{v:.3f}".rstrip("0").rstrip(".")
def g(x):
    x = float(x); d = 0.0
    for t, sft in rules:
        if x >= t: d = sft
    return fmt(x + d)
def take_args(t, pos, n):
    out = []
    for _ in range(n):
        assert t[pos] == "{"
        d, j = 0, pos
        while True:
            if t[j] == "{": d += 1
            elif t[j] == "}":
                d -= 1
                if d == 0: break
            j += 1
        out.append(t[pos + 1:j]); pos = j + 1
    return out, pos
new = []
for ln in P.read_text().split("\n"):
    if re.match(r"\\(pb|pbf)\{", ln):
        ln = re.sub(r"^(\\pbf?)\{([\d.]+)\}\{([\d.]+)\}", lambda m: f"{m.group(1)}{{{g(m.group(2))}}}{{{g(m.group(3))}}}", ln)
    elif ln.startswith("\\hl{"):
        ln = re.sub(r"\\hl\{([\d.]+)\}\{([\d.]+)\}", lambda m: f"\\hl{{{g(m.group(1))}}}{{{g(m.group(2))}}}", ln)
    elif ln.startswith("\\pbunion{"):
        a, end = take_args(ln, len("\\pbunion"), 7)
        a[1] = g(a[1])
        a[5] = ",".join("/".join([g(q[0]), g(q[1]), q[2], q[3]]) for q in (p.split("/") for p in a[5].split(",")))
        a[6] = re.sub(r"\(([\d.]+),([\d.]+)\)", lambda m: f"({g(m.group(1))},{m.group(2)})", a[6])
        ln = "\\pbunion" + "".join("{" + x + "}" for x in a) + ln[end:]
    new.append(ln)
P.write_text("\n".join(new)); print("remapped", P, rules)
