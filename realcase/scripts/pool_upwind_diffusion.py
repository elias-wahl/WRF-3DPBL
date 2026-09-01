#!/usr/bin/env python
"""Phase 2 of the pool-budget decomposition: the implicit upwind diffusion hidden in
the resolved advective tendency (companion to pool_adv_decomp.py).

WRF's 5th-order horizontal / 3rd-order vertical scalar advection is an even-order
centered flux plus an upwind term proportional to |v| (module_advect_em.F):

    flux5 = flux6 - sign(v)/60 * [ (q_{i+2}-q_{i-3}) - 5(q_{i+1}-q_{i-2}) + 10(q_i-q_{i-1}) ]
    flux3 = flux4 - sign(v)/12 * [ (q_{k+1}-q_{k-2}) - 3(q_k-q_{k-1}) ]

The upwind part is the scheme's implicit numerical diffusion (acting along eta
surfaces). Here it is reconstructed from the 10-min mean fields (T_MEAN, U_MEAN,
V_MEAN; vertical velocity as the mu-coupled eta-dot WW_MEAN), so the |v|' covariance
within the window is neglected -- acceptable in the quasi-steady nocturnal pool, and
checked by the validation row: the full flux5/flux3 mean-field reconstruction of the
advective tendency against the exact stored-flux divergence of pool_adv_decomp.py
(both without the 300 K base state, which cancels in the diffusive part -- any
consistent reconstruction is exact for a constant).

Tendencies in K/h over the same masks/layers as phase 1.
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
    a = np.asarray(v[0] if v.dimensions[0] == "Time" else v[:], dtype=np.float64)
    if kmax is not None and a.ndim == 3:
        nfull = ds.dimensions["bottom_top"].size
        a = a[: kmax + 1] if a.shape[0] > nfull else a[:kmax]
    return a


def stag_x(a):
    p = np.concatenate([a[..., :1], a, a[..., -1:]], axis=-1)
    return 0.5 * (p[..., :-1] + p[..., 1:])


def stag_y(a):
    p = np.concatenate([a[:, :1, :], a, a[:, -1:, :]], axis=1)
    return 0.5 * (p[:, :-1, :] + p[:, 1:, :])


def flux56_x(q, u_face):
    """Centered 6th-order and diffusive 5th-order kinematic flux on interior x-faces.

    q: (k, y, x) mass points; u_face: (k, y, x+1). Returns (f6, fdiff) on faces,
    zero within 3 cells of the domain edge (those faces use lower order in WRF;
    irrelevant for the interior pool).
    """
    nx = q.shape[-1]
    f6 = np.zeros_like(u_face)
    fd = np.zeros_like(u_face)
    # face i (between mass i-1 and i), stencil mass i-3 .. i+2  -> valid i in [3, nx-3]
    i = np.arange(3, nx - 2)
    qm3, qm2, qm1 = q[..., i - 3], q[..., i - 2], q[..., i - 1]
    q0, qp1, qp2 = q[..., i], q[..., i + 1], q[..., i + 2]
    f6[..., i] = u_face[..., i] * (37 * (q0 + qm1) - 8 * (qp1 + qm2) + (qp2 + qm3)) / 60.0
    fd[..., i] = -np.abs(u_face[..., i]) * ((qp2 - qm3) - 5 * (qp1 - qm2) + 10 * (q0 - qm1)) / 60.0
    return f6, fd


def flux56_y(q, v_face):
    qt = np.swapaxes(q, 1, 2)
    vt = np.swapaxes(v_face, 1, 2)
    f6, fd = flux56_x(qt, vt)
    return np.swapaxes(f6, 1, 2), np.swapaxes(fd, 1, 2)


def flux34_z(q, om_face):
    """Centered 4th-order and diffusive 3rd-order mu-coupled flux on interior z-faces.

    q: (k, y, x); om_face: (k+1, y, x) = WW (mu eta-dot). Face k between k-1, k,
    stencil k-2 .. k+1 -> valid k in [2, nk-2]. Faces 0,1 and top: zero here (WRF
    uses 2nd order there = no upwind part at these faces except order reduction).
    """
    f4 = np.zeros_like(om_face)
    fd = np.zeros_like(om_face)
    nk = q.shape[0]
    k = np.arange(2, nk - 1)
    qm2, qm1, q0, qp1 = q[k - 2], q[k - 1], q[k], q[k + 1]
    f4[k] = om_face[k] * (7 * (q0 + qm1) - (qp1 + qm2)) / 12.0
    fd[k] = -np.abs(om_face[k]) * ((qp1 - qm2) - 3 * (q0 - qm1)) / 12.0
    return f4, fd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--archive", required=True)
    ap.add_argument("--t1", required=True)
    ap.add_argument("--kmax", type=int, default=40)
    args = ap.parse_args()
    kmax = args.kmax

    mn = nc.Dataset(f"{args.archive}/meanout_d01_{args.t1}.nc")
    w1 = nc.Dataset(f"{args.archive}/wrfout_d01_{args.t1}.nc")

    c1h, c2h = rd(w1, "C1H")[:kmax], rd(w1, "C2H")[:kmax]
    dnw = rd(w1, "DNW")[:kmax]
    dx, dy = 1.0 / float(w1["RDX"][0]), 1.0 / float(w1["RDY"][0])
    mfx, mfy = rd(w1, "MAPFAC_MX"), rd(w1, "MAPFAC_MY")
    mf_uy, mf_vx = rd(w1, "MAPFAC_UY"), rd(w1, "MAPFAC_VX")
    hgt, xlat, xlon = rd(w1, "HGT"), rd(w1, "XLAT"), rd(w1, "XLONG")

    mut = rd(mn, "MUT_MEAN")
    mu3 = c1h[:, None, None] * mut[None] + c2h[:, None, None]
    mu8x, mu8y = stag_x(mu3), stag_y(mu3)

    tm = rd(mn, "T_MEAN", kmax)[:kmax]
    um = rd(mn, "U_MEAN", kmax)[:kmax]
    vm = rd(mn, "V_MEAN", kmax)[:kmax]
    ww = rd(mn, "WW_MEAN", kmax)                    # mu-coupled eta-dot, z-faces

    def div_x(flux_x):
        term = flux_x * mu8x / mf_uy[None]
        return -(term[:, :, 1:] - term[:, :, :-1]) * mfx[None] * mfy[None] / dx / mu3

    def div_y(flux_y):
        term = flux_y * mu8y / mf_vx[None]
        return -(term[:, 1:, :] - term[:, :-1, :]) * mfx[None] * mfy[None] / dy / mu3

    def div_z_coupled(f):                           # mu-coupled flux on z-faces
        return -(f[1:] - f[:-1]) / dnw[:, None, None] / mu3

    f6x, fdx = flux56_x(tm, um)
    f6y, fdy = flux56_y(tm, vm)
    f4z, fdz = flux34_z(tm, ww)

    diff_h = div_x(fdx) + div_y(fdy)
    diff_z = div_z_coupled(fdz)
    full_recon = div_x(f6x + fdx) + div_y(f6y + fdy) + div_z_coupled(f4z + fdz)

    zf = rd(mn, "Z_MEAN", kmax)
    z_agl = 0.5 * (zf[:-1] + zf[1:]) - hgt[None]
    inn = foreland_mountain_masks(hgt, xlat, xlon, dx=dx)["C"]
    slope = terrain_classes(hgt, dx) == 1

    rows = [("upwind diff horiz (5th)", diff_h), ("upwind diff vert (3rd)", diff_z),
            ("upwind diff total", diff_h + diff_z),
            ("full mean-field recon (valid.)", full_recon)]
    layers = [(0, 50), (50, 300), (0, 300)]
    hdr = "".join(f"{m}[{a}-{b}m]".rjust(18) for m in ("inn", "slp") for a, b in layers)
    print(f"{args.t1}\n{'term (K/h)':32s}{hdr}")
    for label, f in rows:
        row = ""
        for m in (inn, slope):
            m3 = np.broadcast_to(m[None], f.shape)
            for a, b in layers:
                sel = m3 & (z_agl >= a) & (z_agl < b)
                row += f"{f[sel].mean() * 3600:18.3f}"
        print(f"{label:32s}{row}")


if __name__ == "__main__":
    main()
