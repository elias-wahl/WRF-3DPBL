#!/usr/bin/env python3
"""Tabulate the q^2 budget terms from the auxhist23 diagnostic stream.

    qsq_budget.py <dir-or-files> [--from 01:25] [--to 01:38] [--level 0]

Answers the question OPEN_ISSUES A9 poses: as pbl3d_opt=2 runs away, is
PRODUCTION rising or is DISSIPATION failing?

The five terms (m2 s-3) sum to the q^2 tendency:

    Q_SQ_SHEAR      shear production      (source, >0)   <- prime suspect
    Q_SQ_BUOYANCY   buoyancy production   (sink at night, <0 in stable air)
    Q_SQ_DISSIP     dissipation           (sink, <0)
    Q_SQ_VDIFF      vertical diffusion    (redistribution)
    Q_SQ_HDIFF      horizontal diffusion  (redistribution; pbl3d_opt>1 only)

Reported per frame, so a term that turns over is visible as a turnover rather
than only as an endpoint:

  * max / min / mean over the whole 3D field, with the (k,j,i) where the max
    sits -- so it is visible whether the action stays put or migrates
  * the same restricted to one model level (default k=3, where Q_SQ peaks;
    NOTE k=0 is identically zero for Q_SQ, it is the surface boundary value,
    whereas max |W| does sit at k=0)
  * |shear| / |dissip|, the production-to-dissipation ratio. A closure that is
    damping properly holds this near or below 1; a monotonic climb is the
    signature of production outrunning dissipation.

Domain means include every point, so they are dominated by the ~24e6 quiet
points and move far less than the maxima -- that contrast is itself
informative, and is why both are printed.

STAGGERING -- do not compare Q_SQ and the budget terms level by level. Q_SQ is
declared with a Z stagger (face levels, 80 of them, and k=0 is identically zero
because it is the surface boundary value). The five tendencies are declared
unstaggered and are filled over k = kts..ktf (mass levels, 79) -- which matches
how they are computed, as the divergence of a face-level flux. So a given k is
a slightly different height in the two, and the arrays are different lengths.
This is consistent, not a bug. It does not affect the question being asked:
whether a term grows over time is independent of the level convention.
"""
import argparse
import glob
import os
import re
import sys

import numpy as np

try:
    from netCDF4 import Dataset
except ImportError:
    sys.exit("netCDF4 not importable -- source realcase/env/vsc5.sh first")

TERMS = ["Q_SQ_SHEAR", "Q_SQ_BUOYANCY", "Q_SQ_DISSIP", "Q_SQ_VDIFF", "Q_SQ_HDIFF"]
CONTEXT = ["Q_SQ", "W"]
# Tier diagnostics, carried when the stream has them (see iofields_qsq.txt).
TIERS = ["PBL3D_T1_RATIO", "PBL3D_SK_EPS", "PBL3D_T2_STEPS", "PBL3D_T3_FLAGS", "L_MASTER"]
TIME_RE = re.compile(r"(\d{4}-\d{2}-\d{2})_(\d{2}:\d{2}:\d{2})")


def frame_time(path):
    m = TIME_RE.search(os.path.basename(path))
    return m.group(2) if m else ""


def collect(paths, lo, hi):
    out = []
    for p in sorted(paths):
        t = frame_time(p)
        if not t:
            continue
        if lo and t[:5] < lo:
            continue
        if hi and t[:5] > hi:
            continue
        out.append((t, p))
    return out


def stats(a):
    """Finite-only stats, plus how many points are not finite."""
    a = np.asarray(a, dtype=np.float64)
    bad = int((~np.isfinite(a)).sum())
    f = a[np.isfinite(a)]
    if f.size == 0:
        return None, None, None, bad
    return float(f.max()), float(f.min()), float(f.mean()), bad


def peak_loc(a):
    """(k,j,i) of the largest |value|, ignoring non-finite points."""
    a = np.asarray(a, dtype=np.float64)
    m = np.where(np.isfinite(a), np.abs(a), -np.inf)
    return np.unravel_index(int(np.argmax(m)), a.shape)


def per_cell(frames, cell):
    """Co-located budget at one cell -- the table A9 uses.

    Every term is read at the SAME (k,j,i), so the columns actually sum to the
    net tendency. This is what distinguishes a runaway source from a failing
    sink; domain maxima cannot, because the maximum of each term generally
    sits in a different cell (that is exactly how Q_SQ_HDIFF was misread as a
    spurious source when at the blowup cell it is a large sink).
    """
    k, j, i = cell
    cols = TERMS + CONTEXT + TIERS
    print("co-located at (k,j,i) = (%d,%d,%d), 0-based\n" % (k, j, i))
    hdr = "%-9s" % "time"
    for c in cols:
        hdr += " %11s" % c.replace("Q_SQ_", "").replace("PBL3D_", "")[:11]
    print(hdr + " %11s" % "net")
    for t, p in frames:
        with Dataset(p) as d:
            row = "%-9s" % t[:8]
            net = 0.0
            for c in cols:
                if c not in d.variables:
                    row += " %11s" % "-"
                    continue
                a = d.variables[c][0]
                try:
                    v = float(a[k, j, i]) if a.ndim == 3 else float(a[j, i])
                except IndexError:
                    row += " %11s" % "oob"
                    continue
                if c in TERMS and np.isfinite(v):
                    net += v
                row += " %11.4g" % v
            print(row + " %11.4g" % net)
    print("\nnet = sum of the five budget terms at this cell. The runaway moment is")
    print("where net turns positive while SHEAR exceeds DISSIP.")
    print("T1_RATIO < 1 => Tier 1 bound l here (and failed anyway);")
    print("T1_RATIO ~ 1 => Tier 1 never bound, i.e. it is blind to this strain.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", nargs="+", help="qsqdiag_*.nc files, or a directory")
    ap.add_argument("--from", dest="lo", default="", help="HH:MM, inclusive")
    ap.add_argument("--to", dest="hi", default="", help="HH:MM, inclusive")
    ap.add_argument("--level", type=int, default=3, help="model level for the k-slice (default 3, where Q_SQ peaks)")
    ap.add_argument("--cell", default="", metavar="K,J,I",
                    help="report CO-LOCATED values at one cell, 0-based numpy "
                         "indexing (A9's blowup cell is 4,182,514). A domain "
                         "maximum is not a budget -- this is the mode that "
                         "answers A9.")
    args = ap.parse_args()

    paths = []
    for t in args.target:
        paths.extend(sorted(glob.glob(os.path.join(t, "qsqdiag_*.nc"))) if os.path.isdir(t) else [t])
    frames = collect(paths, args.lo, args.hi)
    if not frames:
        sys.exit("no frames matched -- check the path and the --from/--to window")

    k = args.level
    cell = None
    if args.cell:
        try:
            cell = tuple(int(x) for x in args.cell.replace(" ", "").split(","))
            if len(cell) != 3:
                raise ValueError
        except ValueError:
            sys.exit("--cell wants K,J,I (0-based), e.g. --cell 4,182,514")
    print("q^2 budget, %d frames, %s -> %s   (level slice: k=%d)"
          % (len(frames), frames[0][0], frames[-1][0], k))

    if cell is not None:
        return per_cell(frames, cell)

    missing = None
    for t, p in frames:
        with Dataset(p) as d:
            if missing is None:
                missing = [v for v in TERMS + CONTEXT if v not in d.variables]
                if missing:
                    print("\n!!! NOT IN THE FILE: %s" % ", ".join(missing))
                    print("!!! The r -> rh Registry promotion did not reach this binary,")
                    print("!!! or iofields_qsq.txt was not picked up. Check rsl.error.0000")
                    print("!!! for 'W A R N I N G'. Nothing below can answer A9.")
                    if all(v in missing for v in TERMS):
                        return 1
            print("\n=== %s   %s" % (t, os.path.basename(p)))
            print("    %-14s %12s %12s %12s | %12s %12s  %s" %
                  ("term", "max", "min", "mean", "max(k=%d)" % k,
                   "mean(k=%d)" % k, "peak|.| at (k,j,i)"))
            vals = {}
            for v in TERMS + CONTEXT:
                if v not in d.variables:
                    continue
                a = d.variables[v][0]           # (bottom_top, sn, we), single frame
                mx, mn, me, bad = stats(a)
                sl = a[k] if a.ndim == 3 else a
                kmx, _, kme, kbad = stats(sl)
                vals[v] = mx
                flag = "   <- %d NON-FINITE" % bad if bad else ""
                if mx is None:
                    print("    %-14s %12s %12s %12s | %12s %12s   ALL NON-FINITE"
                          % (v, "-", "-", "-", "-", "-"))
                    continue
                loc = peak_loc(a) if a.ndim == 3 else ()
                print("    %-14s %12.4g %12.4g %12.4g | %12.4g %12.4g  %-16s%s"
                      % (v, mx, mn, me, kmx, kme, str(tuple(int(x) for x in loc)), flag))
            # The discriminator A9 asks for.
            sh, di = vals.get("Q_SQ_SHEAR"), vals.get("Q_SQ_DISSIP")
            if sh is not None and di not in (None, 0):
                print("    %-14s %12.4g      (max|shear| / max|dissip|)"
                      % ("P/eps", abs(sh) / abs(di)))
    print("\nReading it: production outrunning dissipation shows as Q_SQ_SHEAR max")
    print("climbing while |Q_SQ_DISSIP| lags, i.e. P/eps rising monotonically.")
    print("Dissipation failing shows as |Q_SQ_DISSIP| flat or falling while Q_SQ")
    print("itself grows. If Q_SQ_HDIFF is positive and growing it is acting as a")
    print("spurious SOURCE on the sloping coordinate surfaces, which is the other")
    print("suspect A9 names.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
