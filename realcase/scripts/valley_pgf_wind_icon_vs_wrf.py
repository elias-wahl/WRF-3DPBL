#!/usr/bin/env python
"""Along-valley pressure-gradient force and wind at Kolsass, ICON (met_em, native levels) vs WRF runs, hourly.
PGF at FIXED heights ASL from two floor boxes (<700 m, r<3 km) at Hall (47.283N 11.505E) and Schwaz-Buch (47.360N 11.720E), 18.4 km apart along the valley
(log-p interpolation of each column to z, box means; E59). u_s>0 = up-valley (from ~75 deg), Kolsass column mean over 3x3 cells.
Usage: python valley_pgf_wind_icon_vs_wrf.py RUN[=SEGS]... [HOURS=13,14,15,16,17]"""
import glob, sys, numpy as np, netCDF4 as nc, warnings; warnings.filterwarnings("ignore")
sys.path.insert(0, "/gpfs/data/fs72996/ewahl/wrf3dpbl-diag"); from evening18_check import lidar, vmean
D = "/gpfs/data/fs72996/ewahl"; LAT, LON = 47.30523, 11.62226; BRG = 75.0; ZF = np.array([700., 800., 900., 1100.]); RHO = 1.1; DS = 18.4e3   # Hall-Schwaz box centre separation [m]
args = [a for a in sys.argv[1:] if not a.startswith("HOURS=")]
HOURS = [int(x) for x in next((a[6:] for a in sys.argv[1:] if a.startswith("HOURS=")), "13,14,15,16,17").split(",")]
fr = lambda segs: {f.split("d01_")[1][:16]: f for s in segs for f in glob.glob(f"{D}/exp/{s}/wrf_output/*/wrfout_d01_*.nc")}
R = {}
for a in args or ["X17=X17a+X17b"]:
    lab, _, segs = a.partition("="); R[lab] = fr(segs.split("+") if segs else [lab])
def dest(lat, lon, brg, km):
    b = np.radians(brg); return lat + km / 111. * np.cos(b), lon + km / (111. * np.cos(np.radians(lat))) * np.sin(b)
def masks(la, lo, hg):
    out = []
    for y, x in ((47.283, 11.505), (47.360, 11.720)):     # up-valley box (Hall), down-valley box (Schwaz-Buch); the valley bends at Kolsass
        dd = np.hypot((la - y) * 111e3, (lo - x) * 111e3 * np.cos(np.radians(47.4)))
        out.append((dd < 3000) & (hg < 700))
    dk = np.hypot((la - LAT) * 111e3, (lo - LON) * 111e3 * np.cos(np.radians(47.4))); out.append(dk < 800)
    return out
def p_at_z(z3, p3, zf):     # z3,p3 (nz,ny,nx) increasing z; log-p interpolation per column at fixed z (NaN below ground)
    nz, ny, nx = z3.shape; out = np.full((len(zf), ny, nx), np.nan)
    for k, z in enumerate(zf):
        above = z3 >= z; kk = np.argmax(above, axis=0); ok = above.any(0) & (kk > 0)
        j, i = np.where(ok); k1 = kk[ok]; k0 = k1 - 1
        z0, z1, p0, p1 = z3[k0, j, i], z3[k1, j, i], p3[k0, j, i], p3[k1, j, i]
        out[k, j, i] = np.exp(np.log(p0) + (z - z0) / (z1 - z0) * (np.log(p1) - np.log(p0)))
    return out
def wrf_fields(f):
    d = nc.Dataset(f); la, lo, hg = np.asarray(d["XLAT"][0]), np.asarray(d["XLONG"][0]), np.asarray(d["HGT"][0])
    ph = (np.asarray(d["PH"][0]) + np.asarray(d["PHB"][0])) / 9.81; z = 0.5 * (ph[:-1] + ph[1:]); p = np.asarray(d["P"][0]) + np.asarray(d["PB"][0])
    U, V = np.asarray(d["U"][0]), np.asarray(d["V"][0]); u = 0.5 * (U[:, :, :-1] + U[:, :, 1:]); v = 0.5 * (V[:, :-1] + V[:, 1:])
    ca, sa = np.asarray(d["COSALPHA"][0]), np.asarray(d["SINALPHA"][0]); ue, ve = u * ca - v * sa, v * ca + u * sa; d.close()
    return la, lo, hg, z, p, ue, ve
def icon_fields(f):
    d = nc.Dataset(f); la, lo, hg = np.asarray(d["XLAT_M"][0]), np.asarray(d["XLONG_M"][0]), np.asarray(d["HGT_M"][0])
    z, p = np.asarray(d["GHT"][0]), np.asarray(d["PRES"][0]); U, V = np.asarray(d["UU"][0]), np.asarray(d["VV"][0]); u = 0.5 * (U[:, :, :-1] + U[:, :, 1:]); v = 0.5 * (V[:, :-1] + V[:, 1:])
    if "COSALPHA" in d.variables: ca, sa = np.asarray(d["COSALPHA"][0]), np.asarray(d["SINALPHA"][0]); ue, ve = u * ca - v * sa, v * ca + u * sa
    else: ue, ve = u, v
    d.close(); o = np.argsort(z[:, 0, 0]); z, p, ue, ve = z[o], p[o], ue[o], ve[o]
    return la, lo, hg, z[1:], p[1:], ue[1:], ve[1:]     # drop the surface pseudo-level
def us_col(z, ue, ve, hg, mk, bands):
    j, i = np.where(mk); out = []
    for a, b in bands:
        vals = []
        for jj, ii in zip(j, i):
            agl = z[:, jj, ii] - hg[jj, ii]; m = (agl >= a) & (agl < b)
            if m.any(): vals.append((ue[m, jj, ii].mean(), ve[m, jj, ii].mean()))
        u, v = np.mean(vals, 0); out.append(-(u * np.sin(np.radians(BRG)) + v * np.cos(np.radians(BRG))))   # >0 = from 75 deg (up-valley)
    return out
lh, Z, wl, dl = lidar("0717"); us = lambda s, dd: s * np.cos(np.radians(dd - BRG))
print("PGF = -(1/rho) dp/ds, rho=1.1, from box-mean pressure at fixed heights ASL, down-valley box (Schwaz-Buch) minus up-valley box (Hall), 18.4 km: >0 pushes up-valley. Units 1e-4 m/s2 (1e-4 m/s2 over 1 h = +0.36 m/s). Kolsass floor ~545 m.")
print("u_s = along-valley wind at Kolsass (>0 up-valley), bands 50-150 / 150-300 m AGL; lidar 15-min window.")
hdr = "UT  model | PGF @ " + " ".join(f"{int(z)}m" for z in ZF) + " | dp(hPa)@800m | u_s 50-150  150-300 | lidar"
print(hdr)
for h in HOURS:
    sel = np.abs(lh - h) <= 0.25; lk = [us(*vmean(wl[np.ix_(sel, (Z >= a) & (Z < c))], dl[np.ix_(sel, (Z >= a) & (Z < c))])) for a, c in ((50, 150), (150, 300))]
    items = [("ICON", icon_fields(f"{D}/WPS/metgrid_output_1712nat/met_em.d01.2025-07-17_{h:02d}:00:00.nc"))]
    for k in R:
        f = R[k].get(f"2025-07-17_{h:02d}:00")
        if f: items.append((k, wrf_fields(f)))
    for name, (la, lo, hg, z, p, ue, ve) in items:
        mu, md, mk = masks(la, lo, hg); pz = p_at_z(z, p, ZF)
        dp = np.array([np.nanmean(pz[k][md]) - np.nanmean(pz[k][mu]) for k in range(len(ZF))]); pgf = dp / (DS * RHO)
        u1, u2 = us_col(z, ue, ve, hg, mk, ((50, 150), (150, 300)))
        print(f"{h:02d}  {name:5s} | " + " ".join(f"{x*1e4:+5.2f}" for x in pgf) + f" | {dp[1]/100:+5.2f} | {u1:+5.1f}  {u2:+5.1f} | {lk[0]:+4.1f} / {lk[1]:+4.1f}" + (f"   (boxes: up {mu.sum()} down {md.sum()} cells, floor hg up {hg[mu].mean():.0f} down {hg[md].mean():.0f} m)" if name == "ICON" and h == HOURS[0] else ""))
