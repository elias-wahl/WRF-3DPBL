#!/usr/bin/env python3
"""X13a crash diagnosis (2026-09-09): job 8579083 died at 2025-07-17 16:49:54 with
SFCLAYREV NaN (hfx) at WRF cell i=165, j=73 (1-based). Print the cell's terrain,
land use, surface state and the lowest-layer geometry from the last two history
frames (16:00, 16:30), plus a domain-wide NaN / vertical-Courant scan.
Optionally the same cell in the twin (X12m segment a) for the same frames.
"""
import sys, glob
import numpy as np
from netCDF4 import Dataset

I, J = 165, 73            # WRF 1-based mass-grid indices from the FATAL message
i, j = I - 1, J - 1
DT = 2.0
ROOT = '/gpfs/data/fs72996/ewahl/exp/X13a/wrf_output/8579083/'
TWIN = sorted(glob.glob('/gpfs/data/fs72996/ewahl/exp/X12ma/wrf_output/*/'))
FRAMES = ['16:00:00', '16:30:00']


def cell2d(ds, name):
    return float(ds.variables[name][0][j, i])


def scan(path, label):
    ds = Dataset(path)
    print(f'\n===== {label}: {path.split("/")[-1]}')
    for nm in ['HGT', 'LU_INDEX', 'XLAT', 'XLONG', 'XLAND', 'ZNT', 'TSK', 'T2', 'Q2',
               'U10', 'V10', 'HFX', 'LH', 'UST', 'PSFC', 'SNOWH', 'SNOWC', 'PBLH',
               'ALBEDO', 'EMISS', 'SWDOWN', 'GLW', 'GRDFLX', 'SMOIS']:
        if nm in ds.variables:
            v = ds.variables[nm][0]
            val = float(v[j, i]) if v.ndim == 2 else float(v[0, j, i])
            print(f'{nm:10s} {val:14.4f}')
    ph = ds.variables['PH'][0][:, j, i] + ds.variables['PHB'][0][:, j, i]
    z = ph / 9.81
    dz = np.diff(z)
    print('z_sfc (m)', round(float(z[0]), 1), '| first 12 layer thicknesses (m):', np.round(dz[:12], 2))
    w = ds.variables['W'][0]
    print('W column at cell, levels 0..14 (m/s):', np.round(w[:15, j, i], 3))
    th = ds.variables['T'][0] + 300.
    print('theta first 12 (K):', np.round(th[:12, j, i], 2))
    u = ds.variables['U'][0]
    v = ds.variables['V'][0]
    print('U first 8 at (i) and (i+1):', np.round(u[:8, j, i], 2), np.round(u[:8, j, i + 1], 2))
    print('V first 8 at (j) and (j+1):', np.round(v[:8, j, i], 2), np.round(v[:8, j + 1, i], 2))
    qv = ds.variables['QVAPOR'][0]
    print('QVAPOR first 6 (g/kg):', np.round(1e3 * qv[:6, j, i], 3))
    for nm in ['QSQ', 'PBL3D_COND_A', 'PBL3D_T2_STEPS', 'PBL3D_T3_FLAGS', 'PBL3D_T1_RATIO',
               'PBL3D_L', 'PBL3D_L0', 'PBL3D_QSQ_FLOOR', 'PBL3D_SK_EPS']:
        if nm in ds.variables:
            a = ds.variables[nm][0]
            print(f'{nm}: cell first 10', np.round(a[:10, j, i], 3),
                  '| domain max', float(np.nanmax(a)), '| NaN count', int(np.isnan(a).sum()))
    # domain-wide sanity
    for nm in ['T', 'W', 'U', 'V', 'QVAPOR', 'P', 'MU', 'TSK', 'HFX', 'UST']:
        a = np.asarray(ds.variables[nm][0])
        print(f'{nm:7s} NaN {int(np.isnan(a).sum()):6d}  min {float(np.nanmin(a)):12.4f}  max {float(np.nanmax(a)):12.4f}')
    # vertical Courant number |W| dt / dz on full levels (dz of the layer below the level)
    phf = (ds.variables['PH'][0] + ds.variables['PHB'][0]) / 9.81
    dzf = np.diff(phf, axis=0)                     # layer thicknesses (nz-1, ny, nx)
    cfl = np.abs(w[1:-1]) * DT / np.minimum(dzf[:-1], dzf[1:])
    kmax = np.unravel_index(np.nanargmax(cfl), cfl.shape)
    print('vertical Courant max', round(float(cfl[kmax]), 3), 'at (k,j,i)=', (kmax[0] + 1, kmax[1] + 1, kmax[2] + 1),
          '| at crash cell (max over column):', round(float(cfl[:, j, i].max()), 3))
    print('min layer thickness in domain (m):', round(float(dzf.min()), 2), 'at', np.unravel_index(dzf.argmin(), dzf.shape))
    hgt = ds.variables['HGT'][0]
    print('HGT 5x5 around cell (rows j-2..j+2, cols i-2..i+2):\n', np.round(hgt[j - 2:j + 3, i - 2:i + 3]).astype(int))
    lu = ds.variables['LU_INDEX'][0]
    print('LU_INDEX 5x5:\n', lu[j - 2:j + 3, i - 2:i + 3].astype(int))
    tsk = ds.variables['TSK'][0]
    print('TSK 5x5:\n', np.round(tsk[j - 2:j + 3, i - 2:i + 3], 1))
    hfx = ds.variables['HFX'][0]
    print('HFX 5x5:\n', np.round(hfx[j - 2:j + 3, i - 2:i + 3], 0))
    ust = ds.variables['UST'][0]
    print('UST 5x5:\n', np.round(ust[j - 2:j + 3, i - 2:i + 3], 2))
    if 'ZNT' in ds.variables:
        znt = ds.variables['ZNT'][0]
        print('ZNT 5x5:\n', np.round(znt[j - 2:j + 3, i - 2:i + 3], 4))
    wk1 = w[1]
    print('W(k=1) 5x5:\n', np.round(wk1[j - 2:j + 3, i - 2:i + 3], 2))
    ds.close()


for f in FRAMES:
    scan(ROOT + f'wrfout_d01_2025-07-17_{f}.nc', 'X13a')
if TWIN:
    for f in FRAMES:
        p = TWIN[-1] + f'wrfout_d01_2025-07-17_{f}.nc'
        try:
            scan(p, 'X12ma twin')
        except OSError as e:
            print('twin frame missing:', p, e)
else:
    print('no X12ma archive found')
