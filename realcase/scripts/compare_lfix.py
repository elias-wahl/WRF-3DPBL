#!/usr/bin/env python3
"""Compare a unified-length-scale run against the job 8472687 baseline.

Baseline lives in wrf_output/8472687/baseline_qsq_subset_k0-9_0125-0138.nc
(lowest 10 levels, 01:25-01:38). New run is read live from temp/branko/.

Reports the blowup-cell time series and the domain budget, in the same layout
as FINDINGS_QSQ_RUNAWAY.md so the two can be diffed by eye.
"""
import netCDF4 as nc, numpy as np, glob, os, sys, warnings
warnings.filterwarnings('ignore')

ROOT = '/gpfs/data/fs72996/ewahl'
BASE = f'{ROOT}/wrf_output/8472687/baseline_qsq_subset_k0-9_0125-0138.nc'
J, I = 111, 161          # baseline blowup cell
B1 = 16.6                # pbl3d_constants = 'MY82'


def cell_series(get, times):
    print(f"{'time':>6} {'Q_SQ':>9} {'W':>8} {'T1R':>7} {'SKEPS':>8} {'LMAST':>8}"
          f" {'SHEAR':>10} {'DISSIP':>10} {'P/eps':>8} {'tau_s':>7}")
    for n, t in enumerate(times):
        qsq = get(n, 'Q_SQ', 1); w = get(n, 'W', 0)
        t1 = get(n, 'PBL3D_T1_RATIO', 1); sk = get(n, 'PBL3D_SK_EPS', 1)
        lm = get(n, 'L_MASTER', 1)
        sh = get(n, 'Q_SQ_SHEAR', 0); ds = get(n, 'Q_SQ_DISSIP', 0)
        pe = sh / ds if ds not in (0.0,) else float('nan')
        q = np.sqrt(max(qsq, 0.0))
        tau = B1 * lm / (2 * q) if q > 0 else float('nan')
        print(f"{t:>6} {qsq:9.4g} {w:8.3f} {t1:7.4f} {sk:8.4g} {lm:8.4g}"
              f" {sh:10.4g} {ds:10.4g} {pe:8.3f} {tau:7.2f}")


def from_baseline():
    d = nc.Dataset(BASE)
    times = [b''.join(r).decode().strip()[11:16] for r in d['Times'][:]]
    def get(n, v, k): return float(d[v][n, k, J, I])
    print("=== BASELINE  job 8472687  (l_master unlimited in eps) ===")
    cell_series(get, times)
    d.close()


def from_live():
    files = sorted(f for f in glob.glob(f'{ROOT}/temp/branko/qsqdiag_d01_*.nc')
                   if f[-11:-6] >= '01:25')
    if not files:
        print("no live qsqdiag frames >= 01:25 yet"); return
    times = [os.path.basename(f)[-11:-6] for f in files]
    ds = [nc.Dataset(f) for f in files]
    def get(n, v, k): return float(ds[n][v][0, k, J, I])
    print(f"\n=== RERUN  ({len(files)} frames, last {times[-1]}) "
          f"(l_master limited by Tier 1) ===")
    cell_series(get, times)
    for d in ds: d.close()


if __name__ == '__main__':
    from_baseline()
    from_live()
