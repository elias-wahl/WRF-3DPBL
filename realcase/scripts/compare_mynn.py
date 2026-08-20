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

    args = p.parse_args()
    if getattr(args, 'subset', None) is None and args.cmd in ('t1', 'cap'):
        args.subset = f'{args.run_dir}/qsq_subset_k0-9_0125-0138.nc'
    args.func(args)


if __name__ == '__main__':
    main()
