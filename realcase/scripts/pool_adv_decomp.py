#!/usr/bin/env python
"""Explicit WRFlux theta-budget decomposition for the Inn-valley cold pool (DECISIONS 2026-09-01).

Replaces the residual estimate of the pool's warming term with the model's own resolved
advective tendency, computed exactly from the time-mean advective fluxes the advection
scheme accumulated (`FT{X,Y,Z}_ADV_MEAN`), in the native terrain-following (eta) frame
where the budget closes at the grid point:

    dT/dt = adv_X + adv_Y + adv_Z  +  SGS flux divergence  +  RADLW + RADSW + MP + CU + DAMP  +  eps

All terms in K/h. `T` is dry potential temperature minus 300 K (WRFlux runs with
output_dry_theta_fluxes). The advective tendencies mirror wrflux/tools.py `adv_tend`
(cartesian=False): the stored vertical flux is Cartesian, so the correction fluxes
(FTX_CORR + FTY_CORR + CORR_DTDT, density-weighted, on z-faces) are subtracted to
recover the eta-frame flux; horizontal divergences are mass (mu)-weighted with the
hybrid-coordinate column mass mu(k) = C1H*MUT + C2H and map factors. The advection of
the 300 K base state is restored through the continuity equation: the three mass terms
sum to (1/mu) dmu/dt (exact), with the vertical mass term as the continuity residual.

`eps` is the closure gap: everything the instrumentation does not capture. With this
configuration (diff_opt=0) that is, to leading order, the explicit 6th-order
hyperdiffusion (diff_6th_opt=2, factor 0.12, slope-tapered) plus time-integration
(RK3/acoustic) errors -- the *non-advective* numerics. The implicit upwind diffusion of
the 5th/3rd-order advection scheme is INSIDE adv_*; separating it needs the offline
stencil reconstruction (phase 2, pool_upwind_diffusion.py).

Usage:
  python pool_adv_decomp.py --archive exp/CPB1d/wrf_output/8552151 \
      --t0 2025-07-18_01:10:00 --t1 2025-07-18_01:20:00
Reads meanout_d01_<t1>.nc (means over [t0,t1]) and wrfout_d01_<t0/t1>.nc.
"""
import argparse
import sys

import numpy as np
import netCDF4 as nc

sys.path.insert(0, "/gpfs/data/fs72996/ewahl/proc")
from proc.turbulence import foreland_mountain_masks, terrain_classes  # noqa: E402

G = 9.81


def rd(ds, name, kmax=None):
    v = ds.variables[name]
    a = v[0] if v.dimensions[0] == "Time" else v[:]
    a = np.asarray(a, dtype=np.float64)
    if kmax is not None and a.ndim == 3:
        nfull = ds.dimensions["bottom_top"].size
        a = a[: kmax + 1] if a.shape[0] > nfull else a[:kmax]
    return a


def stag_x(a):  # mass -> x faces, edge-padded (interior exact, edges nearest)
    p = np.concatenate([a[..., :1], a, a[..., -1:]], axis=-1)
    return 0.5 * (p[..., :-1] + p[..., 1:])


def stag_y(a):
    p = np.concatenate([a[:, :1, :], a, a[:, -1:, :]], axis=1)
    return 0.5 * (p[:, :-1, :] + p[:, 1:, :])


def stag_z(a, fnm, fnp, cf, cfn):  # half levels (k) -> faces (k+1); WRF vertical staggering
    kk = a.shape[0]
    out = np.empty((kk + 1,) + a.shape[1:])
    out[1:kk] = fnm[1:kk, None, None] * a[1:kk] + fnp[1:kk, None, None] * a[: kk - 1]
    out[0] = cf[0] * a[0] + cf[1] * a[1] + cf[2] * a[2]
    out[kk] = cfn[0] * a[kk - 1] + cfn[1] * a[kk - 2]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--archive", required=True)
    ap.add_argument("--t0", required=True)
    ap.add_argument("--t1", required=True)
    ap.add_argument("--kmax", type=int, default=40)
    args = ap.parse_args()
    kmax = args.kmax

    mn = nc.Dataset(f"{args.archive}/meanout_d01_{args.t1}.nc")
    w0 = nc.Dataset(f"{args.archive}/wrfout_d01_{args.t0}.nc")
    w1 = nc.Dataset(f"{args.archive}/wrfout_d01_{args.t1}.nc")
    dt = (nc.num2date(w1["XTIME"][0], w1["XTIME"].units)
          - nc.num2date(w0["XTIME"][0], w0["XTIME"].units)).total_seconds()
    print(f"window {args.t0} -> {args.t1}  dt={dt:.0f} s")

    # ---- grid ----------------------------------------------------------------
    c1h, c2h = rd(w1, "C1H")[:kmax], rd(w1, "C2H")[:kmax]
    fnm, fnp = rd(w1, "FNM")[: kmax + 1], rd(w1, "FNP")[: kmax + 1]
    cf = [float(w1[f"CF{i}"][0]) for i in (1, 2, 3)]
    cfn = [float(w1["CFN"][0]), float(w1["CFN1"][0])]
    dnw = rd(w1, "DNW")[:kmax]
    dx = 1.0 / float(w1["RDX"][0])
    dy = 1.0 / float(w1["RDY"][0])
    mfx, mfy = rd(w1, "MAPFAC_MX"), rd(w1, "MAPFAC_MY")
    mf_uy, mf_vx = rd(w1, "MAPFAC_UY"), rd(w1, "MAPFAC_VX")
    hgt, xlat, xlon = rd(w1, "HGT"), rd(w1, "XLAT"), rd(w1, "XLONG")

    mut = rd(mn, "MUT_MEAN")                      # Pa, 2D
    mu3 = c1h[:, None, None] * mut[None] + c2h[:, None, None]      # half levels
    mu8x, mu8y = stag_x(mu3), stag_y(mu3)
    rhod = rd(mn, "RHOD_MEAN", kmax)
    rho8z = stag_z(rhod, fnm, fnp, cf, cfn)

    def div_x(flux_x):   # kinematic flux on x-faces, half levels -> tendency (K/s or 1/s)
        term = flux_x * mu8x / mf_uy[None]
        return -(term[:, :, 1:] - term[:, :, :-1]) * mfx[None] * mfy[None] / dx / mu3

    def div_y(flux_y):
        term = flux_y * mu8y / mf_vx[None]
        return -(term[:, 1:, :] - term[:, :-1, :]) * mfx[None] * mfy[None] / dy / mu3

    def div_z(fz_rho):   # density-weighted flux on z-faces -> tendency
        return (fz_rho[1:] - fz_rho[:-1]) / dnw[:, None, None] * G / mu3

    # ---- resolved advection (exact, eta frame) --------------------------------
    ftx = rd(mn, "FTX_ADV_MEAN", kmax)[:kmax]
    fty = rd(mn, "FTY_ADV_MEAN", kmax)[:kmax]
    ftz = rd(mn, "FTZ_ADV_MEAN", kmax)            # z-faces, kmax+1
    corr = (rd(mn, "FTX_CORR", kmax) + rd(mn, "FTY_CORR", kmax)
            + rd(mn, "CORR_DTDT", kmax))          # density-weighted, z-faces
    fz_eta = ftz * rho8z - corr                   # eta-frame vertical flux, rho-weighted

    adv_x, adv_y, adv_z = div_x(ftx), div_y(fty), div_z(fz_eta)

    # base state: mass advection, vertical as continuity residual
    dmu = rd(w1, "MU") - rd(w0, "MU")
    rho_tend = c1h[:, None, None] * dmu[None] / dt / mu3
    um = rd(mn, "U_MEAN", kmax)[:kmax]
    vm = rd(mn, "V_MEAN", kmax)[:kmax]
    mass_x, mass_y = div_x(um), div_y(vm)
    mass_z = rho_tend - mass_x - mass_y
    adv_x, adv_y, adv_z = (adv_x + 300 * mass_x, adv_y + 300 * mass_y,
                           adv_z + 300 * mass_z)
    adv_tot = adv_x + adv_y + adv_z

    # ---- SGS flux divergence ---------------------------------------------------
    sgs = div_z(rd(mn, "FTZ_SGS_MEAN", kmax) * rho8z)
    sgs_h = np.zeros_like(sgs)
    for name, dv in (("FTX_SGS_MEAN", div_x), ("FTY_SGS_MEAN", div_y)):
        if name in mn.variables:
            f = rd(mn, name, kmax)[:kmax]
            if np.abs(f).max() > 0:
                sgs_h += dv(f)
    sgs += sgs_h

    # ---- physics tendencies ------------------------------------------------------
    phys = {}
    for key, name in (("radlw", "T_TEND_RADLW_MEAN"), ("radsw", "T_TEND_RADSW_MEAN"),
                      ("mp", "T_TEND_MP_MEAN"), ("cu", "T_TEND_CU_MEAN"),
                      ("damp", "T_TEND_DAMP_MEAN")):
        phys[key] = rd(mn, name, kmax)[:kmax] if name in mn.variables else 0.0

    # ---- total tendency and closure gap ----------------------------------------
    tend = (rd(w1, "T", kmax)[:kmax] - rd(w0, "T", kmax)[:kmax]) / dt
    known = adv_tot + sgs + sum(v for v in phys.values() if isinstance(v, np.ndarray))
    eps = tend - known
    legacy_resid = tend - sgs - sum(v for v in phys.values() if isinstance(v, np.ndarray))

    # ---- masks and layers ---------------------------------------------------------
    zh = rd(mn, "Z_MEAN", kmax)
    z_agl = 0.5 * (zh[:-1] + zh[1:]) - hgt[None]
    masks = foreland_mountain_masks(hgt, xlat, xlon, dx=dx)
    inn = masks["C"]
    slope = terrain_classes(hgt, dx) == 1
    print(f"Inn-valley cells: {inn.sum()}, slope cells: {slope.sum()}")

    terms = [("total dT/dt", tend), ("adv total", adv_tot), ("  adv X (eta)", adv_x),
             ("  adv Y (eta)", adv_y), ("  adv Z (cross-eta)", adv_z), ("SGS", sgs),
             ("  SGS horiz", sgs_h), ("LW", phys["radlw"]), ("SW", phys["radsw"]),
             ("MP", phys["mp"]), ("CU", phys["cu"]), ("DAMP", phys["damp"]),
             ("eps (6th-ord filt + time-int)", eps),
             ("legacy residual (adv+eps)", legacy_resid)]
    layers = [(0, 50), (50, 300), (0, 300)]
    hdr = "".join(f"{m}[{a}-{b}m]".rjust(18) for m in ("inn", "slp") for a, b in layers)
    print(f"\n{'term (K/h)':32s}{hdr}")
    for label, f in terms:
        if not isinstance(f, np.ndarray):
            continue
        row = ""
        for m in (inn, slope):
            m3 = np.broadcast_to(m[None], f.shape)
            for a, b in layers:
                sel = m3 & (z_agl >= a) & (z_agl < b)
                row += f"{f[sel].mean() * 3600:18.3f}"
        print(f"{label:32s}{row}")


if __name__ == "__main__":
    main()
