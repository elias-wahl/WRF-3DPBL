#!/usr/bin/env python3
"""Quality gate between the verification run X7 and the 23 h run X8 (DECISIONS 2026-08-21 22:30).

Exit 0  -> X7 passed, the dependent job may start.
Exit 1  -> X7 failed the gate (or could not be checked): the caller cancels X8.

Checks (all on the X7 archive dir):
  (a) the 03:30 frame is bit-identical to X6's (U, T, Q_SQ, TSK): the night has no
      short-wave, so the albedo guard must change nothing;
  (b) 07:00 frame: T finite, no negative land albedo, 2 m temperature 1st percentile > 271 K,
      < 2000 cells with T2 < 270 K, < 200 cells with > 15 m/s at the lowest level;
  (c) the run reached its last expected frame (10:00) and it is finite.

usage: gate_x7_to_x8.py <x7_archive_dir> [<x6_archive_dir>]
"""
import sys, os, glob
import numpy as np
from netCDF4 import Dataset

x7 = sys.argv[1]
x6 = sys.argv[2] if len(sys.argv) > 2 else '/gpfs/data/fs72996/ewahl/exp/X6/wrf_output/8478327'
fails = []

def frame(d, t):
    p = os.path.join(d, f'wrfout_d01_2025-07-18_{t}:00.nc')
    return Dataset(p) if os.path.exists(p) else None

# (a) night bit-identical to X6
a7, a6 = frame(x7, '03:30'), frame(x6, '03:30')
if a7 is None or a6 is None:
    fails.append('03:30 frame missing in X7 or X6')
else:
    for v in ('U', 'T', 'Q_SQ', 'TSK'):
        if v in a7.variables and v in a6.variables:
            d = np.abs(a7[v][0].astype('f8') - a6[v][0].astype('f8')).max()
            print(f'(a) 03:30 {v}: max |X7-X6| = {d:g}')
            if d != 0.0:
                fails.append(f'03:30 {v} differs from X6 (max {d:g})')
        else:
            print(f'(a) {v} not in both files - skipped')

# (b) 07:00 morning
b = frame(x7, '07:00')
if b is None:
    fails.append('07:00 frame missing')
else:
    T = b['T'][0]
    if not np.isfinite(T).all():
        fails.append('07:00 T not finite')
    lm = b['LANDMASK'][0]
    alb = b['ALBEDO'][0]
    nneg = int(((alb < 0) & (lm > 0.5)).sum())
    t2 = b['T2'][0]
    p1 = float(np.percentile(t2, 1))
    ncold = int((t2 < 270).sum())
    u = b['U'][0, 0]; v = b['V'][0, 0]
    um = 0.5 * (u[:, :-1] + u[:, 1:]); vm = 0.5 * (v[:-1, :] + v[1:, :])
    spd = np.sqrt(um**2 + vm**2)
    nfast = int((spd > 15).sum())
    print(f'(b) 07:00: neg land albedo {nneg}, T2 p1 {p1:.1f} K, T2<270 {ncold}, >15 m/s lev1 {nfast}')
    if nneg > 0: fails.append(f'{nneg} land cells with negative albedo at 07:00')
    if p1 <= 271: fails.append(f'T2 1st percentile {p1:.1f} K <= 271')
    if ncold >= 2000: fails.append(f'{ncold} cells T2 < 270 K')
    if nfast >= 200: fails.append(f'{nfast} cells > 15 m/s at level 1')

# (c) end of run
c = frame(x7, '10:00')
if c is None:
    fails.append('10:00 frame missing - X7 did not finish')
elif not np.isfinite(c['T'][0]).all():
    fails.append('10:00 T not finite')
else:
    print('(c) 10:00 frame present and finite')

if fails:
    print('GATE FAILED:\n  ' + '\n  '.join(fails))
    sys.exit(1)
print('GATE PASSED')
