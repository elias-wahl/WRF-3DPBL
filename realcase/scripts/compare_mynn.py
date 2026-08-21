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
  exp     -- multi-run, multi-time report for the six 6-hour experiments
             (DECISIONS.md 2026-08-20 top entry): slope x height stratified
             q^2, 10 m wind bias, per-level length scales/floor fraction,
             strain-limiter footprint, and a q^2-shear vs KE-loss budget
             check, each run vs the MYNN control at matching times.
  fog     -- morning fog / cold-air-pool diagnostics (A12 follow-on): per
             terrain band x slope-aspect low-cloud fraction and cloud-top
             height, T2/Q2/RH2, surface fluxes, TSK-T(k=0), q^2; cold cells
             vs cloud co-location; the near-surface saturation path
             (T, QVAPOR, RH at k=0) and its 30-min tendency; and drainage-flow
             cells (>15 m/s at the lowest mass level) vs cold/cloudy
             neighbours. Runs and the MYNN control (as a run named "MYNN")
             are each reported independently, band x aspect x time.

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

# bins used by the `exp` subcommand
EXP_SLOPE_BINS_DEG = [(0, 3), (3, 8), (8, 15), (15, 22), (22, 40)]
EXP_HEIGHT_BINS_M = [(0, 50), (50, 100), (100, 200), (200, 400)]
EXP_NL_MASS = 25  # mass levels 0..24 -- covers ~0-800 m AGL, well past the 200-400 m bin


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


def slope_deg(hgt, dx=500.):
    """Terrain slope [deg] from centred differences of HGT, matching `slope`."""
    dhdx = np.gradient(hgt, dx, axis=1)
    dhdy = np.gradient(hgt, dx, axis=0)
    return np.degrees(np.arctan(np.hypot(dhdx, dhdy)))


def cmd_exp(args):
    """Multi-run report for the six 6-hour experiments vs the MYNN control.

    q^2 (Q_SQ / QKE) = twice the turbulence kinetic energy, m^2 s^-2. All
    face-level (staggered, "w" grid) fields are averaged to mass levels with
    face_to_mass() before being compared level-for-level to a mass quantity,
    same convention as `slope`/`spinup`. Height AGL is (PH+PHB)/9.81 minus
    the k=0 (surface) value of that same profile, at mass levels unless noted.

    For every run in --runs and every time in --times, against the MYNN file
    at the same time:

    [1] Table stratified by slope bin x height-AGL bin: mean q^2 of the run,
        mean MYNN QKE, their ratio (mean/mean, not mean-of-ratios), and cell
        count. This is the block written to --csv if given.
    [2] Per slope bin: 10 m wind-speed bias, run minus MYNN (U10/V10 hypot).
    [3] Per face level k=0..7: mean AGL, fraction of cells at/under the q^2
        floor (1.5e-5 m^2 s^-2), median L_MASTER (run) and median EL_PBL
        (MYNN) -- both mixing-length scales in metres, face levels. If the
        run file carries L0_ASYM (a 2-D, level-independent asymptotic-length
        field, m), its domain median is printed once, not per level.
    [4] Only if PBL3D_T1_RATIO and PBL3D_SK_EPS are in the run file: the
        fraction of "live" cells (Q_SQ > 2e-5 m^2 s^-2) in the lowest 5 face
        levels where the Tier-1 strain limiter binds (T1_RATIO < 0.999).
        Only if PBL3D_P_EPS is also present: median P/eps (production over
        dissipation) and the fraction < 1, split into limiter-bound vs
        unbound live cells -- same masking as `cap`. PBL3D_P_EPS is itself a
        face-level field with the same (Time, bottom_top_stag, ...) shape as
        Q_SQ, so unlike Q_SQ_SHEAR/Q_SQ_DISSIP in `cap` there is no k offset
        between it and PBL3D_T1_RATIO.
    [5] Only if KE_LOSS_H and QSQ_SHEAR_H are in the run file (mass-level 3-D
        fields, m^2 s^-3): mass-weighted domain sums over the lowest --top-m
        metres AGL of KE_LOSS_H (S_ke) and QSQ_SHEAR_H/2 (S_p, the /2
        converting q^2 production to a TKE-production rate comparable to
        KE_LOSS_H). The per-column layer weight is the dry-air column mass
        per unit area, weight = -(MU+MUB)*DNW[k]/9.81 (kg m^-2; DNW < 0 so
        the sign makes weight > 0). S_ke and S_p are pointwise different
        terms in the q^2/TKE budget that differ by a transport-divergence
        term cell by cell -- only their domain integrals are expected to
        cancel (residual = S_ke + S_p near 0) in a closed, consistent
        budget; the residual and residual/|S_p| are printed as the check.
    """
    runs = {}
    for kv in args.runs:
        name, sep, path = kv.partition('=')
        if not sep or not name or not path:
            raise SystemExit(f"--runs entries must be NAME=DIR, got {kv!r}")
        runs[name] = path

    times = args.times.split(',')
    csv_rows = []

    for t in times:
        mynn_path = f'{args.mynn_dir}/wrfout_d01_{args.date}_{t}:00.nc'
        try:
            b = nc.Dataset(mynn_path)
        except OSError:
            print(f'[{t}] MYNN file missing: {mynn_path} -- skipping this time')
            continue

        for name, run_dir in runs.items():
            run_path = f'{run_dir}/wrfout_d01_{args.date}_{t}:00.nc'
            try:
                a = nc.Dataset(run_path)
            except OSError:
                print(f'[{name} {t}] run file missing: {run_path} -- skipping')
                continue

            print(f'\n=== run={name}  time={t} ===')
            print('times', a['Times'][0].tobytes(), b['Times'][0].tobytes())

            hgt = a['HGT'][0]
            slope = slope_deg(hgt)

            NL = EXP_NL_MASS
            q3m = face_to_mass(a['Q_SQ'][0, 0:NL + 1])
            qm = b['QKE'][0, 0:NL]

            zf = (a['PH'][0, 0:NL + 1] + a['PHB'][0, 0:NL + 1]) / 9.81
            zf = zf - zf[0]
            zm = face_to_mass(zf)

            # --- [1] slope x height stratified q^2 table --------------------
            print(f"\n[1] q^2 (m^2 s^-2) by slope x height-AGL bin, {name} vs MYNN")
            print(f"{'slope deg':>10} {'height m':>10} {'n':>9} {'q2_run':>9} "
                  f"{'q2_MYNN':>9} {'ratio':>7}")
            for slo, shi in EXP_SLOPE_BINS_DEG:
                sm = (slope >= slo) & (slope < shi)
                for hlo, hhi in EXP_HEIGHT_BINS_M:
                    m = (zm >= hlo) & (zm < hhi) & sm[None, :, :]
                    n = int(m.sum())
                    if n == 0:
                        continue
                    qr = float(q3m[m].mean())
                    qk = float(qm[m].mean())
                    ratio = qr / qk if qk else float('nan')
                    print(f"{slo:>3}-{shi:<6} {hlo:>3}-{hhi:<6} {n:>9d} {qr:9.4f} "
                          f"{qk:9.4f} {ratio:7.2f}")
                    csv_rows.append(dict(run=name, time=t, slope_lo=slo, slope_hi=shi,
                                          height_lo=hlo, height_hi=hhi, n=n,
                                          q2_run=qr, q2_mynn=qk, ratio=ratio))
            h100 = zm < 100
            r100 = float(q3m[h100].mean()) / float(qm[h100].mean())
            print(f"  all-domain, lowest 100 m: q2_run {q3m[h100].mean():.4f}  "
                  f"q2_MYNN {qm[h100].mean():.4f}  ratio {r100:.2f}")

            # --- [2] 10 m wind bias by slope bin -----------------------------
            print(f"\n[2] 10 m wind bias (run - MYNN), m/s, by slope bin")
            w3 = np.hypot(a['U10'][0], a['V10'][0])
            wm = np.hypot(b['U10'][0], b['V10'][0])
            for slo, shi in EXP_SLOPE_BINS_DEG:
                sm = (slope >= slo) & (slope < shi)
                if sm.sum() == 0:
                    continue
                print(f"  {slo:>3}-{shi:<4} deg: n={int(sm.sum()):7d}  "
                      f"bias {(w3[sm] - wm[sm]).mean():+.2f}")

            # --- [3] per-level floor fraction and length scales --------------
            print(f"\n[3] per face level k=0..7: floor fraction, length scales (m)")
            print(f"{'k':>3} {'z_AGL':>8} {'frac<=floor':>12} {'med L_MASTER':>13} "
                  f"{'med EL_PBL':>11}")
            q_face = a['Q_SQ'][0, 0:8]
            L = a['L_MASTER'][0, 0:8]
            EL = b['EL_PBL'][0, 0:8]
            zface = (a['PH'][0, 0:8] + a['PHB'][0, 0:8]) / 9.81
            zface = zface - zface[0]
            floor = q_face <= 1.5e-5
            for k in range(8):
                print(f"{k:>3} {float(zface[k].mean()):8.1f} {float(floor[k].mean()):12.3f} "
                      f"{np.median(L[k]):13.3f} {np.median(EL[k]):11.3f}")
            if 'L0_ASYM' in a.variables:
                print(f"  L0_ASYM (2-D, domain median): {np.median(a['L0_ASYM'][0]):.3f} m")
            else:
                print("  L0_ASYM not in run file -- skipping")

            # --- [4] strain-limiter footprint / P-eps -------------------------
            print(f"\n[4] strain-limiter footprint (needs PBL3D_T1_RATIO, PBL3D_SK_EPS)")
            if 'PBL3D_T1_RATIO' in a.variables and 'PBL3D_SK_EPS' in a.variables:
                t1 = a['PBL3D_T1_RATIO'][0, 0:5]
                qlo = a['Q_SQ'][0, 0:5]
                live = qlo > 2e-5
                if live.any():
                    frac = float((t1[live] < 0.999).mean())
                    print(f"  live cells (Q_SQ>2e-5), lowest 5 face levels: "
                          f"fraction T1<0.999 = {frac:.3f}  (n_live={int(live.sum())})")
                else:
                    print("  no live cells (Q_SQ>2e-5) in lowest 5 face levels")

                if 'PBL3D_P_EPS' in a.variables:
                    # face-level, same shape as Q_SQ -- no k offset vs T1_RATIO
                    pe = a['PBL3D_P_EPS'][0, 0:5]
                    bound = live & (t1 < 0.999)
                    unbound = live & (t1 >= 0.999)
                    for label, mask in (('bound', bound), ('unbound', unbound)):
                        x = pe[mask]
                        x = x[np.isfinite(x)]
                        if x.size:
                            print(f"  {label:>7}: n={x.size:8d}  median P/eps "
                                  f"{np.median(x):5.2f}  frac<1 {np.mean(x < 1):.2f}")
                        else:
                            print(f"  {label:>7}: no cells")
                else:
                    print("  PBL3D_P_EPS not in run file -- skipping P/eps split")
            else:
                print("  PBL3D_T1_RATIO/PBL3D_SK_EPS not in run file -- skipping block 4")

            # --- [5] mass-weighted q^2-shear vs KE-loss budget check ----------
            print(f"\n[5] mass-weighted q^2-shear vs KE-loss budget, lowest "
                  f"{args.top_m:g} m AGL (needs KE_LOSS_H, QSQ_SHEAR_H)")
            if 'KE_LOSS_H' in a.variables and 'QSQ_SHEAR_H' in a.variables:
                dnw = a['DNW'][0]
                mu = a['MU'][0] + a['MUB'][0]
                zmass_mean = zm.mean(axis=(1, 2))
                kmax = max(int(np.searchsorted(zmass_mean, args.top_m)), 1)
                kmax = min(kmax, dnw.shape[0])
                weight = -mu[None, :, :] * dnw[:kmax, None, None] / 9.81  # kg m^-2
                ke = a['KE_LOSS_H'][0, 0:kmax]
                qs = a['QSQ_SHEAR_H'][0, 0:kmax]
                S_ke = float((weight * ke).sum())
                S_p = float((weight * qs / 2.).sum())
                resid = S_ke + S_p
                print(f"  levels used: k=0..{kmax - 1} (AGL up to ~{zmass_mean[kmax - 1]:.0f} m)")
                print(f"  S_ke={S_ke:.4e}  S_p={S_p:.4e}  residual={resid:.4e}  "
                      f"residual/|S_p|={(resid / abs(S_p)) if S_p else float('nan'):.3f}")
                print("  (pointwise S_ke and S_p differ by a transport-divergence term; only "
                      "the domain integrals should cancel in a consistent closure)")
            else:
                print("  KE_LOSS_H/QSQ_SHEAR_H not in run file -- skipping block 5")

    if args.csv:
        if csv_rows:
            import csv as csvmod
            with open(args.csv, 'w', newline='') as f:
                w = csvmod.DictWriter(f, fieldnames=list(csv_rows[0].keys()))
                w.writeheader()
                w.writerows(csv_rows)
            print(f"\nwrote {len(csv_rows)} rows (block [1]) to {args.csv}")
        else:
            print(f"\nno block [1] rows produced -- not writing {args.csv}")


# --- constants for `fog` -----------------------------------------------------
# Terrain bands (m, HGT) and their labels -- rows of block [1]/[3] below.
FOG_TERRAIN_BANDS_M = [(0, 1000), (1000, 1500), (1500, 2000), (2000, 2500), (2500, 1.e9)]
FOG_BAND_LABELS = ['<1000', '1000-1500', '1500-2000', '2000-2500', '>2500']
# Slope-aspect labels: "N-facing"/"S-facing" only assigned above this slope
# [deg]; flatter terrain has no well-defined downslope direction.
FOG_ASPECT_LABELS = ['N-facing', 'S-facing', 'flat']
FOG_ASPECT_SLOPE_MIN_DEG = 3.0
FOG_CLOUD_THRESH = 1.e-5   # kg/kg, QCLOUD+QICE threshold marking a level "cloudy"
FOG_K_FOG = 12             # mass levels 0..11 ~ <200 m AGL -- ground fog layer
FOG_K_DECK = 25            # mass levels 0..24 ~ <700 m AGL -- low stratus deck
FOG_K_CLOUDTOP = 30        # search range (mass levels 0..29) for the cloud top
FOG_COLD_T2_K = 270.0      # 2 m temperature threshold marking a "cold" (pooled) cell
FOG_DRAIN_WIND_MS = 15.0   # lowest-mass-level wind speed threshold for drainage flow
FOG_NEIGHBOURHOOD_HALF = 5  # 11x11 cell (half-width 5) neighbourhood, dx=500 m -> 5.5 km


def _fog_band_index(hgt):
    """Terrain-band index 0..4 into FOG_TERRAIN_BANDS_M/FOG_BAND_LABELS."""
    idx = np.zeros(hgt.shape, dtype=int)
    for i, (lo, hi) in enumerate(FOG_TERRAIN_BANDS_M):
        idx = np.where((hgt >= lo) & (hgt < hi), i, idx)
    return idx


def _fog_aspect_index(hgt):
    """Slope-aspect index 0=N-facing, 1=S-facing, 2=flat, from HGT (dx=500 m).

    facing = direction of -grad(h) (the downslope direction); N-facing when
    that direction has a northward (-dh/dy > 0) component. Only assigned
    where slope_deg(hgt) > FOG_ASPECT_SLOPE_MIN_DEG, else "flat".
    """
    slope = slope_deg(hgt)
    dhdy = np.gradient(hgt, 500., axis=0)
    north_facing = (-dhdy) > 0
    steep = slope > FOG_ASPECT_SLOPE_MIN_DEG
    idx = np.full(hgt.shape, 2, dtype=int)
    idx[steep & north_facing] = 0
    idx[steep & ~north_facing] = 1
    return idx, slope


def _box_sum(a, half):
    """Sum of `a` over a (2*half+1)x(2*half+1) cell window centred on each
    cell. Edge-padded (border value repeated) so every window is full size --
    a deliberate approximation, adequate for the neighbourhood checks here."""
    win = 2 * half + 1
    ap = np.pad(np.asarray(a, dtype=float), ((half, half), (half, half)), mode='edge')
    ii = np.zeros((ap.shape[0] + 1, ap.shape[1] + 1))
    ii[1:, 1:] = ap.cumsum(0).cumsum(1)
    ny, nx = a.shape
    return (ii[win:win + ny, win:win + nx] - ii[:ny, win:win + nx]
            - ii[win:win + ny, :nx] + ii[:ny, :nx])


def _box_mean(a, half):
    return _box_sum(a, half) / float((2 * half + 1) ** 2)


def _median_or_nan(x):
    x = np.asarray(x, dtype=float)
    x = x[np.isfinite(x)]
    return float(np.median(x)) if x.size else float('nan')


def _pctl_or_nan(x, p):
    x = np.asarray(x, dtype=float)
    x = x[np.isfinite(x)]
    return float(np.percentile(x, p)) if x.size else float('nan')


def _saturation_rh_pct(T, p, q):
    """RH [%] from temperature T [K], pressure p [Pa], mixing ratio q [kg/kg].

    es = 611.2*exp(17.67*(T-273.15)/(T-29.65)) [Pa] (saturation vapour
    pressure, Bolton-form); qs = 0.622*es/(p-es) [kg/kg] (saturation mixing
    ratio); RH = 100*q/qs.
    """
    es = 611.2 * np.exp(17.67 * (T - 273.15) / (T - 29.65))
    qs = 0.622 * es / np.maximum(p - es, 1.)
    return 100. * q / np.maximum(qs, 1.e-12)


def _time_to_minutes(t):
    hh, mm = t.split(':')
    return int(hh) * 60 + int(mm)


def _fog_fields(d, is_mynn):
    """Per-cell/column fields `cmd_fog` needs from one wrfout Dataset `d`.

    Units, once: T2/TSK/Tk0 in K; Q2/QVk0 in kg/kg (converted to g/kg at the
    print/CSV site, not here); RH in %; SWDOWN/GLW/HFX/LH in W/m^2; UST in
    m/s; wind0 (lowest mass level horizontal wind speed) in m/s; q2 (Q_SQ or
    QKE, twice the turbulence kinetic energy) in m^2/s^2; cloud_top_z in m
    AGL; hgt (surface elevation) in m.
    """
    hgt = d['HGT'][0]
    xland = d['XLAND'][0]
    aspect_idx, slope = _fog_aspect_index(hgt)

    qcloud = d['QCLOUD'][0]
    qice = d['QICE'][0] if 'QICE' in d.variables else np.zeros_like(qcloud)
    qc_qi = qcloud + qice

    nk = FOG_K_CLOUDTOP
    cld = qc_qi[0:nk] > FOG_CLOUD_THRESH                     # (nk, ny, nx) bool
    fog_mask = cld[0:FOG_K_FOG].any(axis=0)                  # fog, ~<200 m AGL
    deck_mask = cld[0:FOG_K_DECK].any(axis=0)                 # deck, ~<700 m AGL
    has_cloud = cld.any(axis=0)
    k_idx = np.arange(nk)[:, None, None]
    topk = np.where(cld, k_idx, -1).max(axis=0)               # highest cloudy k, -1 if none
    zf = (d['PH'][0, 0:nk + 1] + d['PHB'][0, 0:nk + 1]) / 9.81  # face height AGL, m
    zf = zf - zf[0]
    cloud_top_z = np.take_along_axis(zf, np.clip(topk, 0, None)[None, :, :], axis=0)[0]
    cloud_top_z = np.where(has_cloud, cloud_top_z, np.nan)

    T2 = d['T2'][0]
    Q2 = d['Q2'][0]
    PSFC = d['PSFC'][0]
    RH2 = _saturation_rh_pct(T2, PSFC, Q2)

    T = d['T'][0]
    P = d['P'][0]
    PB = d['PB'][0]
    Tk0 = (T[0] + 300.) * ((P[0] + PB[0]) / 1.e5) ** 0.2857   # actual temperature, k=0, K
    QVk0 = d['QVAPOR'][0, 0]
    RHk0 = _saturation_rh_pct(Tk0, P[0] + PB[0], QVk0)

    TSK = d['TSK'][0]

    U = d['U'][0, 0]
    V = d['V'][0, 0]
    u0 = 0.5 * (U[:, :-1] + U[:, 1:])          # unstaggered lowest-mass-level wind, m/s
    v0 = 0.5 * (V[:-1, :] + V[1:, :])
    wind0 = np.hypot(u0, v0)

    if is_mynn:
        q2 = d['QKE'][0, 0:6].mean(axis=0)                    # already on mass levels
    else:
        q2 = face_to_mass(d['Q_SQ'][0, 0:7])[0:6].mean(axis=0)  # face -> mass, lowest 6

    return dict(hgt=hgt, land=(xland < 1.5), slope=slope, aspect_idx=aspect_idx,
                fog_mask=fog_mask, deck_mask=deck_mask, cloud_top_z=cloud_top_z,
                T2=T2, Q2=Q2, RH2=RH2, Tk0=Tk0, QVk0=QVk0, RHk0=RHk0,
                SWDOWN=d['SWDOWN'][0], GLW=d['GLW'][0], HFX=d['HFX'][0], LH=d['LH'][0],
                TSK_minus_T0=TSK - Tk0, UST=d['UST'][0], wind0=wind0, q2=q2)


def cmd_fog(args):
    """Morning fog / cold-air-pool diagnostics, each run (and the MYNN control,
    added as a run named "MYNN") reported independently -- not a run-vs-MYNN
    ratio like `slope`/`exp`, since the question here is where and how each
    closure's near-surface state saturates, not how far apart they are.

    Variables, defined once (units in parentheses):
      q^2 (Q_SQ in the 3D run, QKE in MYNN) -- twice the turbulence kinetic
        energy (m^2 s^-2), mean over the lowest 6 mass levels (Q_SQ is
        face-averaged to mass first, as in `slope`/`exp`).
      "fog" -- max over mass levels k<12 (~<200 m AGL) of QCLOUD+QICE
        exceeding 1e-5 kg/kg, i.e. a shallow ground-fog layer.
      "deck" -- same test over k<25 (~<700 m AGL), a low stratus deck.
      cloud top -- for columns with any QCLOUD+QICE>1e-5 kg/kg in k<30, the
        AGL height (m) of the highest such level, from (PH+PHB)/9.81 minus
        the surface value of that same face-height profile.
      T2, TSK (K) -- 2 m and skin temperature; T(k=0) -- actual (not
        potential) temperature at the lowest mass level, K, from
        (T+300)*((P+PB)/1e5)^0.2857; TSK-T(k=0) is the surface-minus-air
        temperature difference (K) that flags a strong nocturnal inversion.
      Q2 (g/kg), QVAPOR(k=0) (g/kg) -- water-vapour mixing ratio.
      RH2, RH(k=0) (%) -- relative humidity from the Bolton saturation-vapour-
        pressure formula (see _saturation_rh_pct docstring).
      SWDOWN, GLW (W/m^2) -- downward shortwave / longwave radiation at the
        surface; HFX, LH (W/m^2) -- surface sensible / latent heat flux;
        UST (m/s) -- friction velocity.
      wind speed, lowest mass level (m/s) -- hypot of U,V unstaggered to mass
        points at k=0; used to flag drainage-flow cells (>15 m/s).
      terrain band -- HGT (m) bin: <1000, 1000-1500, 1500-2000, 2000-2500,
        >2500. slope aspect -- N-facing/S-facing (only where slope_deg(HGT)
        > 3 deg) else "flat"; see _fog_aspect_index.

    Per run x time (land cells, XLAND<1.5, unless noted):

    A header line gives the ALL-CELL (land+water) fog/deck fraction and the
    ALL-CELL count of T2<270 K cells, as a check against reference numbers.

    [1] Per terrain band x aspect: n; fog/deck cloud fraction; median cloud-
        top height (cloudy columns only); T2 1st/10th/50th percentile; Q2,
        RH2, SWDOWN, GLW, HFX, LH, TSK-T(k=0), UST medians; mean q^2.
    [2] Cold cells (T2<270 K): count, fraction with deck cloud, median
        SWDOWN, median TSK-T(k=0), median terrain band. Per band: median T2
        of deck-cloud cells vs cloud-free cells, and their difference.
    [3] Saturation path per band: median T(k=0), QVAPOR(k=0), RH(k=0); and,
        when the previous requested time for the same run is exactly 30 min
        earlier, the 30-min change in median T(k=0) and QVAPOR(k=0).
    [4] Drainage cells (land, wind speed at k=0 > 15 m/s): n; median T(k=0)
        anomaly vs the 11x11-cell (5.5 km) neighbourhood mean; median HGT;
        fraction lying within that same neighbourhood of a cold (T2<270 K)
        or deck-cloudy land cell.

    All values are also written to --csv in long format: run,time,band,
    aspect,metric,value (band/aspect are "ALL" where a metric is not
    stratified that way).
    """
    runs = {}
    for kv in args.runs:
        name, sep, path = kv.partition('=')
        if not sep or not name or not path:
            raise SystemExit(f"--runs entries must be NAME=DIR, got {kv!r}")
        runs[name] = path
    runs.setdefault('MYNN', args.mynn_dir)

    times = args.times.split(',')
    csv_rows = []
    prev_state = {}  # (run, band_label) -> (time_minutes, median_Tk0, median_QVk0_gkg)

    def emit(run, time, band, aspect, metric, value):
        csv_rows.append(dict(run=run, time=time, band=band, aspect=aspect,
                              metric=metric, value=value))

    for t in times:
        for name, run_dir in runs.items():
            path = f'{run_dir}/wrfout_d01_{args.date}_{t}:00.nc'
            try:
                d = nc.Dataset(path)
            except OSError:
                print(f'[{name} {t}] file missing: {path} -- skipping')
                continue

            f = _fog_fields(d, is_mynn=(name == 'MYNN'))
            land = f['land']
            band_idx = _fog_band_index(f['hgt'])
            aspect_idx = f['aspect_idx']

            fog_all = float(f['fog_mask'].mean())
            deck_all = float(f['deck_mask'].mean())
            ncold_all = int((f['T2'] < FOG_COLD_T2_K).sum())
            print(f"\n=== run={name}  time={t} ===  "
                  f"[ALL-CELL CHECK] fog(k<{FOG_K_FOG})={fog_all*100:.1f}%  "
                  f"deck(k<{FOG_K_DECK})={deck_all*100:.1f}%  n(T2<{FOG_COLD_T2_K:.0f}K)={ncold_all}")

            # --- [1] band x aspect table ---------------------------------
            print(f"\n[1] land cells by terrain band x slope aspect")
            print(f"{'band':>11} {'aspect':>9} {'n':>7} {'fog%':>6} {'deck%':>6} "
                  f"{'ctop_m':>7} {'T2p1':>7} {'T2p10':>7} {'T2p50':>7} {'Q2gkg':>6} "
                  f"{'RH2%':>6} {'SW':>6} {'GLW':>6} {'HFX':>6} {'LH':>6} {'TSKmT':>6} "
                  f"{'UST':>5} {'q2':>8}")
            for bi, band_label in enumerate(FOG_BAND_LABELS):
                bmask = land & (band_idx == bi)
                for ai, aspect_label in enumerate(FOG_ASPECT_LABELS):
                    m = bmask & (aspect_idx == ai)
                    n = int(m.sum())
                    if n == 0:
                        continue
                    fog_pct = float(f['fog_mask'][m].mean()) * 100.
                    deck_pct = float(f['deck_mask'][m].mean()) * 100.
                    ctop = _median_or_nan(f['cloud_top_z'][m])
                    t2p1 = _pctl_or_nan(f['T2'][m], 1)
                    t2p10 = _pctl_or_nan(f['T2'][m], 10)
                    t2p50 = _pctl_or_nan(f['T2'][m], 50)
                    q2gkg = _median_or_nan(f['Q2'][m]) * 1000.
                    rh2 = _median_or_nan(f['RH2'][m])
                    sw = _median_or_nan(f['SWDOWN'][m])
                    glw = _median_or_nan(f['GLW'][m])
                    hfx = _median_or_nan(f['HFX'][m])
                    lh = _median_or_nan(f['LH'][m])
                    tskmt = _median_or_nan(f['TSK_minus_T0'][m])
                    ust = _median_or_nan(f['UST'][m])
                    q2mean = float(f['q2'][m].mean())
                    print(f"{band_label:>11} {aspect_label:>9} {n:>7d} {fog_pct:6.1f} "
                          f"{deck_pct:6.1f} {ctop:7.1f} {t2p1:7.2f} {t2p10:7.2f} "
                          f"{t2p50:7.2f} {q2gkg:6.2f} {rh2:6.1f} {sw:6.1f} {glw:6.1f} "
                          f"{hfx:6.1f} {lh:6.1f} {tskmt:6.2f} {ust:5.2f} {q2mean:8.4f}")
                    for metric, value in (
                        ('n', n), ('fog_frac_pct', fog_pct), ('deck_frac_pct', deck_pct),
                        ('cloud_top_median_m', ctop), ('T2_p1_K', t2p1),
                        ('T2_p10_K', t2p10), ('T2_p50_K', t2p50), ('Q2_median_gkg', q2gkg),
                        ('RH2_median_pct', rh2), ('SWDOWN_median_Wm2', sw),
                        ('GLW_median_Wm2', glw), ('HFX_median_Wm2', hfx),
                        ('LH_median_Wm2', lh), ('TSKminusT0_median_K', tskmt),
                        ('UST_median_ms', ust), ('q2_mean_lowest6_m2s2', q2mean),
                    ):
                        emit(name, t, band_label, aspect_label, metric, value)

            # --- [2] cold cells vs cloud ----------------------------------
            print(f"\n[2] cold cells vs cloud (land, T2<{FOG_COLD_T2_K:.0f} K)")
            cold = land & (f['T2'] < FOG_COLD_T2_K)
            n_cold = int(cold.sum())
            if n_cold:
                frac_lc = float(f['deck_mask'][cold].mean())
                sw_cold = _median_or_nan(f['SWDOWN'][cold])
                tskmt_cold = _median_or_nan(f['TSK_minus_T0'][cold])
                med_band_i = int(round(float(np.median(band_idx[cold]))))
                med_band_i = min(max(med_band_i, 0), len(FOG_BAND_LABELS) - 1)
                med_band_lbl = FOG_BAND_LABELS[med_band_i]
            else:
                frac_lc = sw_cold = tskmt_cold = float('nan')
                med_band_lbl = 'n/a'
            print(f"  n_cold={n_cold}  frac_deck_cloud={frac_lc:.3f}  "
                  f"median_SWDOWN={sw_cold:.1f}  median_TSKminusT0={tskmt_cold:.2f}  "
                  f"median_band={med_band_lbl}")
            emit(name, t, 'ALL', 'ALL', 'coldcells_n', n_cold)
            emit(name, t, 'ALL', 'ALL', 'coldcells_frac_deck_cloud', frac_lc)
            emit(name, t, 'ALL', 'ALL', 'coldcells_SWDOWN_median_Wm2', sw_cold)
            emit(name, t, 'ALL', 'ALL', 'coldcells_TSKminusT0_median_K', tskmt_cold)

            print(f"  per band: median T2 of deck-cloud cells vs cloud-free cells")
            for bi, band_label in enumerate(FOG_BAND_LABELS):
                bmask = land & (band_idx == bi)
                lc = bmask & f['deck_mask']
                clr = bmask & ~f['deck_mask']
                t2_lc = _median_or_nan(f['T2'][lc])
                t2_clr = _median_or_nan(f['T2'][clr])
                diff = t2_lc - t2_clr if np.isfinite(t2_lc) and np.isfinite(t2_clr) else float('nan')
                print(f"    {band_label:>11}: n_deckcloud={int(lc.sum()):6d} "
                      f"n_clear={int(clr.sum()):6d}  T2_deckcloud={t2_lc:7.2f}  "
                      f"T2_clear={t2_clr:7.2f}  diff={diff:+7.2f}")
                emit(name, t, band_label, 'ALL', 'lowcloud_T2_median_K', t2_lc)
                emit(name, t, band_label, 'ALL', 'clear_T2_median_K', t2_clr)
                emit(name, t, band_label, 'ALL', 'lowcloud_minus_clear_T2_K', diff)

            # --- [3] saturation path per band ------------------------------
            print(f"\n[3] saturation path per band: median T(k=0), QVAPOR(k=0), RH(k=0), "
                  f"and 30-min change vs the previous requested time (same run)")
            tmin = _time_to_minutes(t)
            for bi, band_label in enumerate(FOG_BAND_LABELS):
                bmask = land & (band_idx == bi)
                if bmask.sum() == 0:
                    continue
                medT0 = _median_or_nan(f['Tk0'][bmask])
                medQ0 = _median_or_nan(f['QVk0'][bmask]) * 1000.
                medRH0 = _median_or_nan(f['RHk0'][bmask])
                key = (name, band_label)
                prev = prev_state.get(key)
                dtxt = 'no prior frame'
                if prev is not None:
                    prev_t, prev_tmin, prev_medT0, prev_medQ0 = prev
                    if abs((tmin - prev_tmin) - 30.) < 1.e-6:
                        dT = medT0 - prev_medT0
                        dQ = medQ0 - prev_medQ0
                        dtxt = f"dT30={dT:+.3f} K  dQ30={dQ:+.4f} g/kg"
                        emit(name, t, band_label, 'ALL', 'Tk0_change_30min_K', dT)
                        emit(name, t, band_label, 'ALL', 'QVk0_change_30min_gkg', dQ)
                    else:
                        dtxt = f"n/a (prev frame {prev_t!r} is {tmin-prev_tmin:+.0f} min away)"
                prev_state[key] = (t, tmin, medT0, medQ0)
                print(f"    {band_label:>11}: T(k0)={medT0:7.2f} K  QVAPOR(k0)={medQ0:6.3f} g/kg  "
                      f"RH(k0)={medRH0:5.1f}%   {dtxt}")
                emit(name, t, band_label, 'ALL', 'Tk0_median_K', medT0)
                emit(name, t, band_label, 'ALL', 'QVk0_median_gkg', medQ0)
                emit(name, t, band_label, 'ALL', 'RHk0_median_pct', medRH0)

            # --- [4] drainage flow ------------------------------------------
            print(f"\n[4] drainage cells (land, wind speed at k=0 > {FOG_DRAIN_WIND_MS:.0f} m/s)")
            drain = land & (f['wind0'] > FOG_DRAIN_WIND_MS)
            n_drain = int(drain.sum())
            if n_drain:
                anom = f['Tk0'] - _box_mean(f['Tk0'], FOG_NEIGHBOURHOOD_HALF)
                med_anom = _median_or_nan(anom[drain])
                med_hgt = _median_or_nan(f['hgt'][drain])
                near = land & ((f['T2'] < FOG_COLD_T2_K) | f['deck_mask'])
                near_count = _box_sum(near, FOG_NEIGHBOURHOOD_HALF)
                frac_near = float((near_count[drain] > 0.5).mean())
            else:
                med_anom = med_hgt = frac_near = float('nan')
            print(f"  n_drain={n_drain}  median_Tk0_anomaly_vs_11x11={med_anom:.3f} K  "
                  f"median_HGT={med_hgt:.0f} m  frac_near_cold_or_cloud={frac_near:.3f}")
            emit(name, t, 'ALL', 'ALL', 'drainage_n', n_drain)
            emit(name, t, 'ALL', 'ALL', 'drainage_Tk0_anomaly_median_K', med_anom)
            emit(name, t, 'ALL', 'ALL', 'drainage_HGT_median_m', med_hgt)
            emit(name, t, 'ALL', 'ALL', 'drainage_frac_near_cold_or_cloud', frac_near)

    if args.csv:
        if csv_rows:
            import csv as csvmod
            with open(args.csv, 'w', newline='') as fh:
                w = csvmod.DictWriter(fh, fieldnames=list(csv_rows[0].keys()))
                w.writeheader()
                w.writerows(csv_rows)
            print(f"\nwrote {len(csv_rows)} rows to {args.csv}")
        else:
            print(f"\nno rows produced -- not writing {args.csv}")


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

    sp = sub.add_parser('exp', help='six 6-hour experiments: slope x height q^2, wind bias, '
                         'length scales, strain limiter, budget check, each vs MYNN')
    sp.add_argument('--runs', nargs='+', required=True, metavar='NAME=DIR',
                     help='one or more NAME=DIR run archive dirs to compare against MYNN')
    sp.add_argument('--times', required=True,
                     help='comma-separated model times HH:MM, e.g. 02:00,04:00,06:00,07:00')
    sp.add_argument('--date', default='2025-07-18', help='model date (default: %(default)s)')
    sp.add_argument('--top-m', dest='top_m', type=float, default=100.,
                     help='depth in metres AGL for the block-5 budget sums (default: %(default)s)')
    sp.add_argument('--csv', default=None,
                     help='optional path to write the block-1 slope x height table as CSV')
    sp.set_defaults(func=cmd_exp)

    sp = sub.add_parser('fog', help='morning fog / cold-air-pool diagnostics per terrain '
                         'band x slope aspect, each run (and MYNN) reported independently')
    sp.add_argument('--runs', nargs='+', required=True, metavar='NAME=DIR',
                     help='one or more NAME=DIR run archive dirs; MYNN (--mynn-dir) is '
                          'added automatically as an extra run named "MYNN"')
    sp.add_argument('--times', required=True,
                     help='comma-separated model times HH:MM, e.g. 01:30,02:00,...,07:00')
    sp.add_argument('--date', default='2025-07-18', help='model date (default: %(default)s)')
    sp.add_argument('--csv', default=None,
                     help='optional path to write the long-format '
                          'run,time,band,aspect,metric,value table as CSV')
    sp.set_defaults(func=cmd_fog)

    args = p.parse_args()
    if getattr(args, 'subset', None) is None and args.cmd in ('t1', 'cap'):
        args.subset = f'{args.run_dir}/qsq_subset_k0-9_0125-0138.nc'
    args.func(args)


if __name__ == '__main__':
    main()
