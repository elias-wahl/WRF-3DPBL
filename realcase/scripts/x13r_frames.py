#!/usr/bin/env python3
"""X13r (job 8580933, 2026-09-09): the reproduction of the X13a crash died at the same step
(2025-07-17 16:49:54) in the same cell (i=165, j=73) with the same detector values.
Read the fifteen 1-minute stream-23 frames (16:35 ... 16:49) and answer OPEN_ISSUES A24:

  (a) vertical-advection blow-up  -> |W| and the vertical Courant number at k=1..3 climb over
                                     the last frames; PH/P at k=2 depart before anything else
  (b) closure spike               -> Q_SQ, PBL3D_COND_A, PBL3D_T3_FLAGS, PBL3D_SK_EPS spike in the
                                     cell before the dynamics move
  (c) surface layer itself        -> PSFC/QSFC/MOL/BR/REGIME go bad while k=1..3 stay finite

Frames live in exp/X13r/temp/branko/ (submit_wrf.slurm archives wrfout*/meanout* only) or in the
archive if they were moved there. PHB, PB, HGT are time-invariant and are taken from the 16:45
history frame in the archive.
Written by the 2026-09-09 ~23:00 auto-wake session (python was not available there) — unrun.
"""
import glob
import sys
import numpy as np
from netCDF4 import Dataset

I, J = 165, 73                 # WRF 1-based mass-grid indices from the FATAL message
i, j = I - 1, J - 1
DT = 2.0                       # s, time_step
G, RD, CP, P0 = 9.81, 287.04, 1004.6, 1.0e5
KAP = RD / CP

ROOT = '/gpfs/data/fs72996/ewahl/exp/X13r/'
ARCH = sorted(glob.glob(ROOT + 'wrf_output/*/'))[-1]
FRAMES = sorted(glob.glob(ROOT + 'temp/branko/qsqdiag_d01_*.nc')) or \
         sorted(glob.glob(ARCH + 'qsqdiag_d01_*.nc'))
if not FRAMES:
    sys.exit('no qsqdiag frames found under ' + ROOT)
print('frames:', len(FRAMES), FRAMES[0].split('/')[-1], '...', FRAMES[-1].split('/')[-1])

ref = Dataset(ARCH + 'wrfout_d01_2025-07-17_16:45:00.nc')
PHB = np.asarray(ref.variables['PHB'][0])
PB = np.asarray(ref.variables['PB'][0])
HGT = np.asarray(ref.variables['HGT'][0])
print('cell HGT %.1f m; HGT domain max %.1f m' % (HGT[j, i], HGT.max()))
ref.close()


def get(ds, name):
    if name not in ds.variables:
        return None
    return np.asarray(ds.variables[name][0])


def cell(ds, name, k=None):
    a = get(ds, name)
    if a is None:
        return float('nan')
    if a.ndim == 2:
        return float(a[j, i])
    return float(a[k, j, i])


def column(ds, name, n):
    a = get(ds, name)
    if a is None:
        return None
    return a[:n, j, i]


SFC = ['PSFC', 'TSK', 'QSFC', 'HFX', 'QFX', 'LH', 'UST', 'ZNT', 'MOL', 'RMOL', 'BR', 'ZOL',
       'REGIME', 'T2', 'Q2', 'U10', 'V10', 'SNOWC', 'SNOWH', 'MU']
D3 = ['W', 'T', 'P', 'PH', 'QVAPOR', 'U', 'V', 'Q_SQ', 'L_MASTER', 'PBL3D_T1_RATIO',
      'PBL3D_T2_STEPS', 'PBL3D_T3_FLAGS', 'PBL3D_COND_A', 'PBL3D_SK_EPS']

series = []            # one row per frame for the summary table
first_nan_reported = False

for n, path in enumerate(FRAMES):
    ds = Dataset(path)
    tstr = path.split('_')[-1][:-3]
    if n == 0:
        print('\nvariables in stream 23:',
              ' '.join(f'{v}{ds.variables[v].shape[1:]}' for v in ds.variables
                       if ds.variables[v].ndim >= 3))
    print(f'\n===== {tstr}')
    # --- surface scalars at the cell
    print('  ' + ' '.join(f'{nm}={cell(ds, nm):.4g}' for nm in SFC if nm in ds.variables))
    # --- lowest layers at the cell
    z = (column(ds, 'PH', 6) + PHB[:6, j, i]) / G
    dz = np.diff(z)
    p = column(ds, 'P', 5) + PB[:5, j, i]
    th = column(ds, 'T', 5) + 300.
    w = column(ds, 'W', 6)
    qv = column(ds, 'QVAPOR', 5)
    cour = np.abs(w[1:5]) * DT / np.minimum(dz[:4], dz[1:5])
    print('  z_w(k=1..5) AGL m', np.round(z[1:6] - HGT[j, i], 1), '| dz', np.round(dz[:5], 2))
    print('  W(k=1..5)   m/s  ', np.round(w[:6], 3), '| vert. Courant k=2..5', np.round(cour, 3))
    print('  p(k=1..5)   hPa  ', np.round(p / 100., 2), '| p_sfc %.2f' % (cell(ds, 'PSFC') / 100.))
    print('  theta(k=1..5) K  ', np.round(th, 2), '| theta_g(Tsk,psfc) %.2f' %
          (cell(ds, 'TSK') * (P0 / cell(ds, 'PSFC')) ** KAP))
    print('  qv(k=1..5)  g/kg ', np.round(1e3 * qv, 3))
    u = column(ds, 'U', 4)
    v = column(ds, 'V', 4)
    print('  U(k=1..4) at i    ', np.round(u, 2), '| V at j', np.round(v, 2))
    for nm in ['Q_SQ', 'L_MASTER', 'PBL3D_COND_A', 'PBL3D_T2_STEPS', 'PBL3D_T3_FLAGS',
               'PBL3D_SK_EPS', 'PBL3D_T1_RATIO']:
        c = column(ds, nm, 8)
        if c is not None:
            print(f'  {nm:15s} k=1..8', np.round(c, 4))
    # --- 3x3 stencil of the quantities that carry a NaN first
    for nm, kk in [('W', 1), ('W', 2), ('PH', 2), ('P', 1), ('T', 1), ('Q_SQ', 1)]:
        a = get(ds, nm)
        if a is not None:
            print(f'  {nm}(k={kk}) 3x3:', np.round(a[kk, j - 1:j + 2, i - 1:i + 2], 3).tolist())
    for nm in ['PSFC', 'HFX', 'BR', 'MOL', 'UST']:
        a = get(ds, nm)
        if a is not None:
            print(f'  {nm} 3x3:', np.round(a[j - 1:j + 2, i - 1:i + 2], 4).tolist())
    # --- domain-wide: NaN counts, extremes, Courant hot spot
    nan_total = 0
    for nm in D3 + ['PSFC', 'HFX', 'QFX', 'UST', 'BR', 'MOL', 'TSK', 'QSFC']:
        a = get(ds, nm)
        if a is None:
            continue
        nn = int(np.isnan(a).sum())
        nan_total += nn
        if nn and not first_nan_reported:
            idx = np.argwhere(np.isnan(a))[:10]
            print(f'  FIRST NaN: {nm} count {nn}; first (k,j,i)/(j,i) 0-based:', idx.tolist())
    if nan_total and not first_nan_reported:
        first_nan_reported = True
    W = get(ds, 'W')
    PHf = (get(ds, 'PH') + PHB) / G
    dzf = np.diff(PHf, axis=0)
    cfl = np.abs(W[1:-1]) * DT / np.minimum(dzf[:-1], dzf[1:])
    km = np.unravel_index(np.nanargmax(cfl), cfl.shape)
    Q = get(ds, 'Q_SQ')
    CA = get(ds, 'PBL3D_COND_A')
    T3 = get(ds, 'PBL3D_T3_FLAGS')
    wmax = np.unravel_index(np.nanargmax(np.abs(W)), W.shape)
    print(f'  DOMAIN: NaN total {nan_total} | |W| max {float(np.abs(W[wmax])):.2f} at (k,j,i)1 '
          f'{(wmax[0] + 1, wmax[1] + 1, wmax[2] + 1)} | Courant max {float(cfl[km]):.3f} at '
          f'{(km[0] + 1, km[1] + 1, km[2] + 1)} | cell column Courant max {float(cfl[:, j, i].max()):.3f}'
          f' | min dz {float(dzf.min()):.2f} m')
    if Q is not None:
        qm = np.unravel_index(np.nanargmax(Q), Q.shape)
        print(f'  DOMAIN: Q_SQ max {float(Q[qm]):.3f} at (k,j,i)1 {(qm[0] + 1, qm[1] + 1, qm[2] + 1)}'
              f' | cell column max {float(np.nanmax(Q[:, j, i])):.4f}')
    if CA is not None:
        cm = np.unravel_index(np.nanargmax(CA), CA.shape)
        print(f'  DOMAIN: COND_A max {float(CA[cm]):.3g} at (k,j,i)1 {(cm[0] + 1, cm[1] + 1, cm[2] + 1)}'
              f' | cell column max {float(np.nanmax(CA[:, j, i])):.3g}')
    if T3 is not None:
        print(f'  DOMAIN: T3_FLAGS>0 cells {int((T3 > 0).sum())} | in cell column {int((T3[:, j, i] > 0).sum())}')
    series.append(dict(t=tstr, psfc=cell(ds, 'PSFC') / 100., tsk=cell(ds, 'TSK'), hfx=cell(ds, 'HFX'),
                       ust=cell(ds, 'UST'), br=cell(ds, 'BR'), zol=cell(ds, 'ZOL'), mol=cell(ds, 'MOL'),
                       reg=cell(ds, 'REGIME'), w1=float(w[1]), w2=float(w[2]), cmax=float(cour.max()),
                       th1=float(th[0]), p1=float(p[0] / 100.), dz1=float(dz[0]),
                       q1=float(column(ds, 'Q_SQ', 2)[1]) if 'Q_SQ' in ds.variables else float('nan'),
                       ca1=float(column(ds, 'PBL3D_COND_A', 2)[1]) if 'PBL3D_COND_A' in ds.variables else float('nan'),
                       t3=int((T3[:, j, i] > 0).sum()) if T3 is not None else -1))
    ds.close()

print('\n===== cell time series (k=1 is the first mass level, k=2 the first refined layer)')
hdr = ['t', 'psfc', 'tsk', 'hfx', 'ust', 'br', 'zol', 'mol', 'reg', 'w1', 'w2', 'cmax', 'th1', 'p1', 'dz1', 'q1', 'ca1', 't3']
print(' '.join(f'{h:>9s}' for h in hdr))
for r in series:
    print(' '.join(f'{r[h]:>9}' if isinstance(r[h], (str, int)) else f'{r[h]:9.4g}' for h in hdr))
print('\nRead: Courant (cmax) or |w| at k=1..2 rising monotonically into the last frame -> (a);'
      ' q1/ca1/t3 jumping first -> (b); psfc/br/mol/reg going bad with dynamics steady -> (c).')
