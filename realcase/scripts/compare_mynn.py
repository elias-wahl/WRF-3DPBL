#!/usr/bin/env python
"""compare_mynn.py -- 3D PBL closure (pbl3d_opt=2) vs the MYNN control run.

Merges five ad-hoc analysis scripts written while chasing OPEN_ISSUES A9/A10
(the q^2 runaway and the strain-limiter fix) into one tool with a subcommand
per question. All read already-archived wrfout / auxhist files; none of them
run or submit anything.

Units and staggering, read once:
  * q^2 (Q_SQ in the 3D run, QKE in MYNN) is TWICE the turbulence kinetic
    energy, m^2 s^-2 -- i.e. u'^2+v'^2+w'^2, not TKE itself.
  * Q_SQ is carried on WRF's vertical FACE (staggered, "w") levels -- one more
    level than the mass grid. It is averaged to mass levels with
    0.5*(q[:-1]+q[1:]) wherever it is compared level-for-level against a mass
    quantity.
  * MYNN's QKE and EL_PBL are already on mass levels -- no staggering fix
    needed on that side.
  * L_MASTER (3D closure) and EL_PBL (MYNN) are both mixing length scales in
    metres, carried on face levels.
  * The five Q_SQ_* budget terms (SHEAR, BUOYANCY, DISSIP, VDIFF, HDIFF) are
    m^2 s^-3, i.e. rate of change of q^2 -- production/loss terms in the q^2
    budget, also on face levels.

Subcommands:
  slope   -- slope-stratified domain q^2 and 10 m wind speed, 3D vs MYNN, at
             one instant. Answers: does the 3D closure diverge from MYNN more
             on steep terrain?
  spinup  -- layer-mean q^2 time series in both runs, three height bands.
             Answers: when/where does the 3D run's q^2 depart from MYNN's?
  lscale  -- median mixing length by face level, 3D L_MASTER vs MYNN EL_PBL,
             plus a floor-vs-above-floor split for the 3D run (q^2 pinned at
             its floor value vs not). Answers: is the 3D closure's length
             scale collapsing, or is q^2 itself hitting a floor?
  t1      -- PBL3D_T1_RATIO (the Tier-1 strain limiter's output ratio, 1 =
             not binding) vs Q_SQ, from the 1-minute qsq_subset diagnostic.
             Answers: where and how strongly does the limiter engage, and at
             what q^2 does it do so?
  cap     -- production/dissipation ratio (Q_SQ_SHEAR / Q_SQ_DISSIP) split
             into cells where the Tier-1 limiter is bound vs unbound.
             Answers: does the limiter actually suppress net production where
             it engages, or is it engaging too late/too weakly?

Reference numbers this script must reproduce (see DECISIONS.md 2026-08-20):
  slope : all-domain q^2 3D 0.0847 vs MYNN 0.3156 (ratio 0.27); wind bias
          -0.32 m/s (slope 0-3 deg), +0.56 m/s (slope 22-40 deg)
  spinup: 3D 02:00 lowest layer (k0-5) 0.0847, MYNN 0.3156
  lscale: 3D k5 at 02:00 median L_MASTER 0.42 m, MYNN median EL_PBL 6.70 m
  t1    : last frame, stag k=1..5, fraction with T1_RATIO<0.999 = 0.379
  cap   : bound cells (T1_RATIO<0.999) median P/eps 1.19; unbound median 0.81
"""
import argparse
import netCDF4 as nc
import numpy as np

DEFAULT_RUN_DIR = '/gpfs/data/fs72996/ewahl/wrf_output/8476273'
DEFAULT_MYNN_DIR = '/gpfs/data/fs72996/ewahl/wrf_output/8320565'


def wrfout(run_dir, time):
    return nc.Dataset(f'{run_dir}/wrfout_d01_2025-07-18_{time}:00.nc')


def face_to_mass(v):
    """Average a staggered (face/'w') level array down to mass levels."""
    return 0.5 * (v[:-1] + v[1:])


def cmd_slope(args):
    times = args.times.split(',')
    t = times[0]
    a = wrfout(args.run_dir, t)   # 3D closure
    b = wrfout(args.mynn_dir, t)  # MYNN control
    print('times', a['Times'][0].tobytes(), b['Times'][0].tobytes())
    hgt = a['HGT'][0]
    dx = 500.
    dhdx = np.gradient(hgt, dx, axis=1)
    dhdy = np.gradient(hgt, dx, axis=0)
    slope = np.degrees(np.arctan(np.hypot(dhdx, dhdy)))
    NL = args.levels
    q3 = a['Q_SQ'][0, 0:NL + 1]
    q3m = face_to_mass(q3)                # face -> mass
    qm = b['QKE'][0, 0:NL]                # MYNN QKE = q^2 = 2 TKE
    print('3D QKE max (should be 0 if unfilled):', float(a['QKE'][0, 0:NL].max()),
          ' 3D TKE_PBL max:', float(a['TKE_PBL'][0, 0:NL + 1].max()))
    print('MYNN TKE_PBL max (k<=6):', float(b['TKE_PBL'][0, 0:NL + 1].max()),
          ' QKE max:', float(qm.max()))
    q3l = q3m.mean(axis=0)
    qml = qm.mean(axis=0)                 # layer mean over lowest ~100 m
    w3 = np.hypot(a['U10'][0], a['V10'][0])
    wm = np.hypot(b['U10'][0], b['V10'][0])
    bins = [0, 3, 8, 15, 22, 40, 90]
    print(f"{'slope':>8} {'n':>7} {'wind3D':>7} {'windMY':>7} {'dwind':>7} "
          f"{'q2_3D':>8} {'q2_MYNN':>8} {'dq2':>8} {'ratio':>6} {'medratio':>8}")
    for lo, hi in zip(bins[:-1], bins[1:]):
        m = (slope >= lo) & (slope < hi)
        if m.sum() == 0:
            continue
        r = q3l[m] / np.maximum(qml[m], 1e-6)
        print(f"{lo:>3}-{hi:<4} {m.sum():>7d} {w3[m].mean():7.2f} {wm[m].mean():7.2f} "
              f"{(w3[m]-wm[m]).mean():+7.2f} {q3l[m].mean():8.4f} {qml[m].mean():8.4f} "
              f"{(q3l[m]-qml[m]).mean():+8.4f} {q3l[m].mean()/qml[m].mean():6.2f} "
              f"{np.median(r):8.2f}")
    m = slope >= 0
    print(f"{'all':>8} {m.sum():>7d} {w3[m].mean():7.2f} {wm[m].mean():7.2f} "
          f"{(w3[m]-wm[m]).mean():+7.2f} {q3l[m].mean():8.4f} {qml[m].mean():8.4f} "
          f"{(q3l[m]-qml[m]).mean():+8.4f} {q3l[m].mean()/qml[m].mean():6.2f}")
    # level-by-level, lowest NL mass levels, flat vs steep
    print('\nper level q2 ratio 3D/MYNN  (flat 0-3 deg | steep 22-40 deg)')
    mf = (slope < 3)
    ms = (slope >= 22) & (slope < 40)
    for k in range(NL):
        print(f"k={k}  flat {q3m[k][mf].mean()/qm[k][mf].mean():5.2f}   "
              f"steep {q3m[k][ms].mean()/qm[k][ms].mean():5.2f}   "
              f"3D: {q3m[k][mf].mean():.4f}/{q3m[k][ms].mean():.4f}  "
              f"MY: {qm[k][mf].mean():.4f}/{qm[k][ms].mean():.4f}")


def cmd_spinup(args):
    times = args.times.split(',')
    NL = args.levels

    def lay(path, var, k0, k1, stag):
        d = nc.Dataset(path)
        v = d[var][0, k0:k1 + 1 + stag]
        if stag:
            v = face_to_mass(v)
        return v

    print('domain-mean q2, layer means: 0-100 m (k0-5), 100-350 m (k6-20), 350-700 m (k21-40)')
    for t in times:
        f3 = f'{args.run_dir}/wrfout_d01_2025-07-18_{t}:00.nc'
        q = nc.Dataset(f3)['Q_SQ'][0, 0:42]
        qm = face_to_mass(q)
        s3 = f"3D  {t}  {qm[0:NL].mean():.4f}  {qm[6:21].mean():.4f}  {qm[21:41].mean():.4f}"
        fm = f'{args.mynn_dir}/wrfout_d01_2025-07-18_{t}:00.nc'
        try:
            qk = nc.Dataset(fm)['QKE'][0, 0:41]
            s3 += f"   | MYNN {qk[0:NL].mean():.4f}  {qk[6:21].mean():.4f}  {qk[21:41].mean():.4f}"
        except OSError:
            pass
        print(s3)
    # heights of those levels, roughly, at the last requested time (3D file)
    d = nc.Dataset(f'{args.run_dir}/wrfout_d01_2025-07-18_{times[-1]}:00.nc')
    z = (d['PH'][0, 0:42] + d['PHB'][0, 0:42]) / 9.81
    z = z - z[0]
    zm = face_to_mass(z).mean(axis=(1, 2))
    print('mean AGL of mass levels k=0,5,6,20,21,40:', [round(float(zm[k]), 0) for k in (0, 5, 6, 20, 21, 40)])


def cmd_lscale(args):
    times = args.times.split(',')
    lev = [1, 2, 3, 5, 8, 12, 20]
    print("median eddy size l [m] on face levels; 3D L_MASTER vs MYNN EL_PBL; "
          "also 3D L where q2 at floor vs above floor")
    for t in times:
        d = nc.Dataset(f'{args.run_dir}/wrfout_d01_2025-07-18_{t}:00.nc')
        L = d['L_MASTER'][0, 0:22]
        q = d['Q_SQ'][0, 0:22]
        row = f"3D   {t} " + " ".join(f"k{k}:{np.median(L[k]):6.2f}" for k in lev)
        fl = (q <= 1.5e-5)
        row += (f"  | floor-frac k1..5 {fl[1:6].mean():.2f}, "
                f"med L at floor {np.median(L[1:6][fl[1:6]]):.2f}, "
                f"above floor {np.median(L[1:6][~fl[1:6]]):.2f}")
        print(row)
        try:
            m = nc.Dataset(f'{args.mynn_dir}/wrfout_d01_2025-07-18_{t}:00.nc')
            E = m['EL_PBL'][0, 0:22]
            print(f"MYNN {t} " + " ".join(f"k{k}:{np.median(E[k]):6.2f}" for k in lev))
        except OSError:
            pass
    d = nc.Dataset(f'{args.run_dir}/wrfout_d01_2025-07-18_{times[-1]}:00.nc')
    z = (d['PH'][0, 0:22] + d['PHB'][0, 0:22]) / 9.81
    z = z - z[0]
    print('mean face AGL:', " ".join(f"k{k}:{float(z[k].mean()):.0f}m" for k in lev))


def cmd_t1(args):
    d = nc.Dataset(args.subset)
    print(list(d.variables)[:30])
    nt = d['PBL3D_T1_RATIO'].shape[0]
    print('frames', nt, d['PBL3D_T1_RATIO'].shape)
    it = nt - 1
    t1 = d['PBL3D_T1_RATIO'][it, 1:6]
    q = d['Q_SQ'][it, 1:6]
    sk = d['PBL3D_SK_EPS'][it, 1:6]
    print('fixed run, last frame, stag k=1..5: T1<0.999 fraction %.3f, <0.5 %.3f'
          % ((t1 < 0.999).mean(), (t1 < 0.5).mean()))
    edges = [0, 1e-4, 1e-3, 1e-2, 1e-1, 1, 100]
    print(f"{'q2 bin':>14} {'n':>9} {'frac T1<0.999':>14} {'median T1 (bound)':>18} "
          f"{'median SkEps (bound)':>20}")
    for lo, hi in zip(edges[:-1], edges[1:]):
        m = (q >= lo) & (q < hi)
        if m.sum() == 0:
            continue
        b = t1[m] < 0.999
        print(f"{lo:>6g}-{hi:<6g} {m.sum():>9d} {b.mean():>14.3f} "
              f"{np.median(t1[m][b]) if b.any() else float('nan'):>18.3f} "
              f"{np.median(sk[m][b]) if b.any() else float('nan'):>20.1f}")
    print('footprint vs time (k=1..5):')
    for it in range(0, nt, 3):
        t1 = d['PBL3D_T1_RATIO'][it, 1:6]
        print(' frame', it, 'T1<0.999 %.3f  <0.5 %.3f  domain-mean Q_SQ %.4f'
              % ((t1 < 0.999).mean(), (t1 < 0.5).mean(), d['Q_SQ'][it, 1:6].mean()))


def cmd_cap(args):
    d = nc.Dataset(args.subset)
    it = d['Q_SQ'].shape[0] - 1
    # mass-level k pairs with stag faces k and k+1; use face k+1 (the one the
    # production at mass k mostly sees near the wall)
    P = d['Q_SQ_SHEAR'][it, 1:6]
    E = d['Q_SQ_DISSIP'][it, 1:6]
    t1 = d['PBL3D_T1_RATIO'][it, 2:7]
    q = d['Q_SQ'][it, 2:7]
    ok = (E > 1e-9) & (q > 2e-5)               # live turbulence only
    r = np.where(ok, P / np.maximum(E, 1e-30), np.nan)
    b = (t1 < 0.999) & ok
    u = (t1 >= 0.999) & ok

    def stats(m, name):
        x = r[m]
        x = x[np.isfinite(x)]
        print(f"{name:>28}: n={x.size:8d}  P/eps median {np.median(x):5.2f}  "
              f"frac<1 {np.mean(x<1):.2f}  frac<0.5 {np.mean(x<0.5):.2f}  "
              f"frac>1.5 {np.mean(x>1.5):.2f}")

    stats(u, 'cap not binding')
    stats(b, 'cap binding (as built)')
    # what the ratio would be without the cap, if P ~ l and eps ~ 1/l  (upper
    # bound on the need for the cap)
    ru = np.where(b, r / np.maximum(t1, 1e-3) ** 2, np.nan)
    x = ru[b]
    x = x[np.isfinite(x)]
    print(f"{'bound cells, cap removed':>28}: n={x.size:8d}  P/eps median {np.median(x):5.2f}  "
          f"frac<1 {np.mean(x<1):.2f}  frac>1.5 {np.mean(x>1.5):.2f}  frac>3 {np.mean(x>3):.2f}")
    # stratify bound cells by stability proxy: use SK_EPS vs N tau? only N_TAU
    # not in subset; use q2 magnitude bins instead
    sk = d['PBL3D_SK_EPS'][it, 2:7]
    for lo, hi in [(6, 8), (8, 12), (12, 20), (20, 1e9)]:
        m = b & (sk >= lo) & (sk < hi)
        x = r[m]
        x = x[np.isfinite(x)]
        if x.size:
            print(f"   bound, Sk/eps in [{lo},{hi}): n={x.size:7d} "
                  f"P/eps median {np.median(x):5.2f} frac<1 {np.mean(x<1):.2f}")


def main():
    p = argparse.ArgumentParser(
        description='Compare the 3D PBL closure (pbl3d_opt=2) run against the MYNN control.')
    p.add_argument('--run-dir', default=DEFAULT_RUN_DIR,
                    help='3D closure run archive dir (default: %(default)s)')
    p.add_argument('--mynn-dir', default=DEFAULT_MYNN_DIR,
                    help='MYNN control run archive dir (default: %(default)s)')
    p.add_argument('--levels', type=int, default=6,
                    help='number of lowest levels for layer means (default: %(default)s)')
    sub = p.add_subparsers(dest='cmd', required=True)

    sp = sub.add_parser('slope', help='slope-stratified q^2 and 10 m wind vs MYNN')
    sp.add_argument('--times', default='02:00',
                     help='comma-separated model times HH:MM (default: %(default)s)')
    sp.set_defaults(func=cmd_slope)

    sp = sub.add_parser('spinup', help='layer-mean q^2 time series, both runs')
    sp.add_argument('--times', default='01:00,01:10,01:20,01:30,01:40,01:50,02:00',
                     help='comma-separated model times HH:MM (default: %(default)s)')
    sp.set_defaults(func=cmd_spinup)

    sp = sub.add_parser('lscale', help='median L_MASTER vs MYNN EL_PBL by level')
    sp.add_argument('--times', default='01:10,01:30,02:00',
                     help='comma-separated model times HH:MM (default: %(default)s)')
    sp.set_defaults(func=cmd_lscale)

    sp = sub.add_parser('t1', help='strain-limiter (PBL3D_T1_RATIO) footprint vs q^2')
    sp.add_argument('--subset', default=None,
                     help='qsq_subset NetCDF file (default: <run-dir>/qsq_subset_k0-9_0125-0138.nc)')
    sp.set_defaults(func=cmd_t1)

    sp = sub.add_parser('cap', help='production/dissipation ratio, cap-bound vs unbound cells')
    sp.add_argument('--subset', default=None,
                     help='qsq_subset NetCDF file (default: <run-dir>/qsq_subset_k0-9_0125-0138.nc)')
    sp.set_defaults(func=cmd_cap)

    args = p.parse_args()
    if getattr(args, 'subset', None) is None and args.cmd in ('t1', 'cap'):
        args.subset = f'{args.run_dir}/qsq_subset_k0-9_0125-0138.nc'
    args.func(args)


if __name__ == '__main__':
    main()
