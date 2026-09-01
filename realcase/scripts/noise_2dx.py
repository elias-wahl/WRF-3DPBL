#!/usr/bin/env python
"""Grid-scale (2dx) noise comparison between two wrfout frames at the same valid time.

The 6th-order filter exists to damp the shortest resolvable wavelengths; this measures
them directly: for each field the small-scale residual r = f - s, where s is f smoothed
with a 1-2-1 kernel in x and y (kills 2dx exactly, halves 4dx). Reported is var(r) per
height band for run A and B and the ratio A/B -- shared physical small-scale structure
(gravity waves, terrain) cancels to first order when both runs share initial state and
window. Interior domain only (10-cell rim excluded), plus the Inn-valley subset.

Usage: noise_2dx.py --a <wrfout_A> --b <wrfout_B> [--kmax 40]
"""
import argparse
import sys

import numpy as np
import netCDF4 as nc

sys.path.insert(0, "/gpfs/data/fs72996/ewahl/proc")
from proc.turbulence import foreland_mountain_masks  # noqa: E402

RIM = 10


def smooth121(a):
    p = np.pad(a, ((0, 0), (1, 1), (1, 1)), mode="edge")
    s = 0.25 * (p[:, :-2, 1:-1] + 2 * a + p[:, 2:, 1:-1])
    p = np.pad(s, ((0, 0), (1, 1), (1, 1)), mode="edge")
    return 0.25 * (p[:, 1:-1, :-2] + 2 * s + p[:, 1:-1, 2:])


def residual_var(ds, name, kmax, sel2d=None):
    a = np.asarray(ds[name][0, :kmax], dtype=np.float64)
    r = a - smooth121(a)
    r = r[:, RIM:-RIM, RIM:-RIM]
    if sel2d is not None:
        r = np.where(sel2d[None, RIM:-RIM, RIM:-RIM], r, np.nan)
    return np.nanvar(r.reshape(r.shape[0], -1), axis=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", required=True, help="wrfout of the run under test")
    ap.add_argument("--b", required=True, help="wrfout of the reference run")
    ap.add_argument("--kmax", type=int, default=40)
    args = ap.parse_args()

    da, db = nc.Dataset(args.a), nc.Dataset(args.b)
    hgt = np.asarray(da["HGT"][0]); xlat = np.asarray(da["XLAT"][0]); xlon = np.asarray(da["XLONG"][0])
    inn = foreland_mountain_masks(hgt, xlat, xlon, dx=500.0)["C"]

    bands = [(0, 5), (5, 15), (15, 30), (30, args.kmax)]
    print(f"A = {args.a}\nB = {args.b}")
    for name in ("W", "T"):
        for label, sel in (("domain", None), ("inn", inn)):
            va = residual_var(da, name, args.kmax + 1 if name == "W" else args.kmax, sel)
            vb = residual_var(db, name, args.kmax + 1 if name == "W" else args.kmax, sel)
            row = "  ".join(
                f"k{a}-{b}: {np.nanmean(va[a:b]):.2e}/{np.nanmean(vb[a:b]):.2e} (x{np.nanmean(va[a:b]) / np.nanmean(vb[a:b]):.2f})"
                for a, b in bands)
            print(f"{name} 2dx var {label:6s}: {row}")


if __name__ == "__main__":
    main()
