#!/usr/bin/env python
"""Offline reconstruction of the 6th-order filter's theta tendency from an instantaneous
wrfout frame — exact port of `sixth_order_diffusion` ('m' branch, module_big_step_
utilities_em.F): 5th-difference pair fluxes with the monotonic (diff_6th_opt=2) zeroing,
the per-pair slope taper on base-state geopotential (thresh*g*dx), pair-mean hybrid
mu weighting, decoupled by mu as the model stores T_TEND_DAMP (K/s; here K/h).

Purpose: measure the filter term in the pool-FORMATION phase (X10b evening frames,
19:30-22:00 UT), where no meanout instrumentation exists. Field = THM (prognostic moist
theta - 300, what the routine actually diffuses; use_theta_m=1). Validated against the
measured T_TEND_DAMP_MEAN of the two probes (snapshot vs 10-min mean: the monotonic
limiter flickers, so expect agreement in the pool mean, not per cell).

Usage: filter_tend_offline.py <wrfout> [<wrfout> ...]   (prints Inn/slope layer means)
"""
import sys

import numpy as np
import netCDF4 as nc

sys.path.insert(0, "/gpfs/data/fs72996/ewahl/proc")
from proc.turbulence import foreland_mountain_masks, terrain_classes  # noqa: E402

KMAX = 30
FACTOR, THRESH, DT, G = 0.12, 0.10, 2.0, 9.81
COEF = FACTOR * 0.015625 / (2.0 * DT)
LAT, LON = 47.305341, 11.62219  # Kolsass


def pair_terms(f, phb, mu, dzthresh):
    """S*mu*D on interior pair-faces along the last axis. f,phb,mu: (k,y,x)."""
    nx = f.shape[-1]
    out = np.zeros_like(f)                      # face i between cells i-1, i
    i = np.arange(3, nx - 2)
    d = (10.0 * (f[..., i] - f[..., i - 1]) - 5.0 * (f[..., i + 1] - f[..., i - 2])
         + (f[..., i + 2] - f[..., i - 3]))
    d = np.where(d * (f[..., i] - f[..., i - 1]) <= 0.0, 0.0, d)   # monotonic option
    slope = np.maximum(1.0 - np.abs(phb[..., i] - phb[..., i - 1]) / dzthresh, 0.0)
    out[..., i] = slope * 0.5 * (mu[..., i - 1] + mu[..., i]) * d
    return out


def filter_tend(path):
    ds = nc.Dataset(path)
    thm = np.asarray(ds["THM"][0, :KMAX], dtype=np.float64)
    phb = np.asarray(ds["PHB"][0, :KMAX], dtype=np.float64) / G * G  # face k for level k (geopot.)
    mut = np.asarray(ds["MU"][0], dtype=np.float64) + np.asarray(ds["MUB"][0], dtype=np.float64)
    c1h = np.asarray(ds["C1H"][0][:KMAX], dtype=np.float64)
    c2h = np.asarray(ds["C2H"][0][:KMAX], dtype=np.float64)
    mfx = np.asarray(ds["MAPFAC_MX"][0], dtype=np.float64)
    mfy = np.asarray(ds["MAPFAC_MY"][0], dtype=np.float64)
    dx = 1.0 / float(ds["RDX"][0])
    mu3 = c1h[:, None, None] * mut[None] + c2h[:, None, None]
    dzthresh = THRESH * G * dx

    tx = pair_terms(thm, phb, mu3, dzthresh)
    tend_x = COEF * mfx[None] * (np.roll(tx, -1, axis=-1) - tx)
    tend_x[..., -1] = 0.0
    thm_t = np.swapaxes(thm, 1, 2)
    ty = pair_terms(thm_t, np.swapaxes(phb, 1, 2), np.swapaxes(mu3, 1, 2), dzthresh)
    ty = np.swapaxes(ty, 1, 2)                  # face j between cells j-1, j
    tend_y = COEF * mfy[None] * (np.roll(ty, -1, axis=1) - ty)
    tend_y[:, -1, :] = 0.0

    damp = (tend_x + tend_y) / mu3 * 3600.0     # K/h, decoupled
    ph = (np.asarray(ds["PH"][0, : KMAX + 1]) + np.asarray(ds["PHB"][0, : KMAX + 1])) / G
    hgt = np.asarray(ds["HGT"][0], dtype=np.float64)
    z_agl = 0.5 * (ph[:-1] + ph[1:]) - hgt[None]
    xlat, xlon = np.asarray(ds["XLAT"][0]), np.asarray(ds["XLONG"][0])
    ds.close()
    return damp, z_agl, hgt, xlat, xlon


def main():
    first = True
    for path in sys.argv[1:]:
        damp, z_agl, hgt, xlat, xlon = filter_tend(path)
        if first:
            global inn, slope, jk
            inn = foreland_mountain_masks(hgt, xlat, xlon, dx=500.0)["C"]
            slope = terrain_classes(hgt, 500.0) == 1
            jk = np.unravel_index(np.argmin((xlat - LAT) ** 2 + (xlon - LON) ** 2), xlat.shape)
            first = False
        row = f"{path[-22:-3]}  "
        for m, tag in ((inn, "inn"), (slope, "slp")):
            m3 = np.broadcast_to(m[None], damp.shape)
            for a, b in ((0, 50), (0, 300)):
                sel = m3 & (z_agl >= a) & (z_agl < b)
                row += f"{tag}[{a}-{b}] {damp[sel].mean():+7.3f}  "
        j, i = jk
        box = damp[:, j - 2:j + 3, i - 2:i + 3]
        zb = z_agl[:, j - 2:j + 3, i - 2:i + 3]
        row += f"kol5x5[0-300] {box[(zb >= 0) & (zb < 300)].mean():+7.3f}"
        print(row)


if __name__ == "__main__":
    main()
