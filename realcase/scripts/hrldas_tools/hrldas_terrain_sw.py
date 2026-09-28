#!/usr/bin/env python
"""Terrain-corrected shortwave forcing for the HRLDAS spin-up (KNOWN_ISSUES E88: HRLDAS has no slope/shading code, ICON's SWDOWN is the
horizontal-plane flux without terrain shading — checked: cells WRF shades get the same or more ICON SW on clear days, DECISIONS 2026-09-28).
For every hourly LDASIN file (SWDOWN = mean over the hour ENDING at the time stamp) two corrected copies are written:
  SW' = SW [f_d + (1 - f_d) F],  F = hour-mean direct-beam terrain factor (weights sin(el) at 4 sub-times, t-52.5 ... t-7.5 min),
  f_d = diffuse fraction from the hourly clearness index k_t = SW / (S0 E0 <sin el>) (Erbs et al. 1982), diffuse left unchanged as in WRF's
  TOPO_RAD_ADJ; F capped at 4; F = 1 (SW unchanged) when <sin el> S0 < 20 W m-2.
  variant "sh500": WRF-like on the model terrain (= the setup file's HGT = HERO2's): F = sunlit x max(cos i, 0) / sin(el), cos i from the
      cell's centred-difference slope (earth-rotated with COSALPHA/SINALPHA), sunlit = el > horizon of the cell centre (march along the
      grid-relative sun azimuth over HGT, bilinear, 500 m steps to 25 km, 72 azimuth sectors) — as toposhad/TOPO_RAD_ADJ do in WRF;
  variant "sh10": real terrain: cell mean over its 50 m facets (10 m Tirol DEM block-averaged 5 x 5) of sunlit x max(cos i_facet, 0) /
      (cos(slope_facet) sin(el)) — the direct beam intercepted per unit horizontal area (energy-conserving: a rough, fully lit cell gets the
      flat value at high sun; per-surface averaging would lose 5-10 % on steep terrain); sh500 keeps WRF's own per-surface formula; facet horizons from
      the 50 m DEM, beyond the DEM (outside Tirol, 25 km margin) the model HGT; cells with < 85 of ~100 facets in the DEM use the sh500 factor.
Sun: true sun (NOAA equations incl. equation of time) per cell centre; facets take their cell's sun.
Usage: python hrldas_terrain_sw.py geometry            -> <WORK>/geometry.npz (horizons, facets)
       python hrldas_terrain_sw.py test  YYYYMMDDHH ...  -> diagnostics for those forcing hours (no files written)
       python hrldas_terrain_sw.py write [first last]    -> <WORK>/LDASIN_sh500/, <WORK>/LDASIN_sh10/ (all or a range of hours)
Run on a compute node (multiprocessing, 64 workers)."""
import sys, os, glob, shutil, numpy as np, netCDF4 as nc, rasterio, pandas as pd
from multiprocessing import Pool
from scipy.ndimage import map_coordinates
from pyproj import Transformer
D = "/gpfs/data/fs72996/ewahl"
SETUP = f"{D}/hrldas_runs/spinup_hero/HRLDAS_setup_2024121821_d1"
INDIR = f"{D}/hrldas_runs/spinup_winter/LDASIN"
WORK = f"{D}/hrldas_runs/terrain_sw"
DEMF = f"{D}/data/geo/DGM_Tirol_10m_epsg31254_2006_2020.tif"
NAZ = 72; AZ = np.arange(NAZ) * 2 * np.pi / NAZ
STEPS_F = np.r_[np.arange(50, 1000, 50), np.arange(1000, 5000, 200), np.arange(5000, 25001, 500)].astype(float)
STEPS_C = np.arange(500, 25001, 500).astype(float)
NW = int(os.environ.get("NWORK", "64"))

def sun(doy, hr, lat, lon):
    """true sun (NOAA): elevation, azimuth from N clockwise [rad]; hr = UTC hour (float), lat/lon arrays [deg]"""
    g = 2 * np.pi / 365 * (doy - 1 + (hr - 12) / 24)
    eot = 229.18 * (0.000075 + 0.001868 * np.cos(g) - 0.032077 * np.sin(g) - 0.014615 * np.cos(2 * g) - 0.040849 * np.sin(2 * g))
    de = (0.006918 - 0.399912 * np.cos(g) + 0.070257 * np.sin(g) - 0.006758 * np.cos(2 * g) + 0.000907 * np.sin(2 * g)
          - 0.002697 * np.cos(3 * g) + 0.00148 * np.sin(3 * g))
    ha = np.radians((hr * 60 + eot + 4 * lon) / 4 - 180); ph = np.radians(lat)
    cz = np.sin(ph) * np.sin(de) + np.cos(ph) * np.cos(de) * np.cos(ha)
    az = np.arctan2(np.sin(ha), np.cos(ha) * np.sin(ph) - np.tan(de) * np.cos(ph)) + np.pi
    return np.arcsin(np.clip(cz, -1, 1)), np.mod(az, 2 * np.pi)

def grid():
    s = nc.Dataset(SETUP); g = {k: np.asarray(s[k][0]).astype(float) for k in ("XLAT", "XLONG", "HGT", "COSALPHA", "SINALPHA")}; s.close()
    return g

# ------------------------------------------------------------------ geometry
_G = {}
def _hor_cell(k):
    hg, rot = _G["hg"], _G["rot"]; ny, nx = hg.shape; jj, ii = np.mgrid[0:ny, 0:nx].astype(float); azg = AZ[k] + rot; h = np.full(hg.shape, -np.pi / 2)
    for s in STEPS_C:
        z = map_coordinates(hg, [jj + s * np.cos(azg) / 500., ii + s * np.sin(azg) / 500.], order=1, mode="nearest")
        h = np.maximum(h, np.arctan((z - hg) / s))
    return h.astype(np.float16)
def _hor_facet(k):
    zc, r0, c0, zf = _G["zc"], _G["fr"], _G["fc"], _G["fz"]; h = np.full(r0.shape, -np.pi / 2, np.float32)
    for s in STEPS_F:
        z = map_coordinates(zc, [r0 - s * np.cos(AZ[k]) / 50., c0 + s * np.sin(AZ[k]) / 50.], order=1, mode="nearest")
        h = np.maximum(h, np.arctan((z - zf) / s))
    return h.astype(np.float16)
def geometry():
    os.makedirs(WORK, exist_ok=True); G = grid(); hg = G["HGT"]; ny, nx = hg.shape
    rot = np.where(G["COSALPHA"] >= 0, np.arcsin(G["SINALPHA"]), np.pi - np.arcsin(G["SINALPHA"]))
    gy, gx = np.gradient(hg, 500.)                                   # grid-relative dz/dj (north-ish), dz/di (east-ish)
    ca, sa = G["COSALPHA"], G["SINALPHA"]; gxe, gye = gx * ca - gy * sa, gy * ca + gx * sa   # earth-relative gradient
    _G.update(hg=hg, rot=rot)
    with Pool(min(NW, NAZ)) as p: hc = np.stack(p.map(_hor_cell, range(NAZ)))
    print("cell horizons done", hc.shape, flush=True)
    # 50 m DEM + margin filled with model HGT
    dem = rasterio.open(DEMF); z10 = dem.read(1).astype(np.float32); z10[z10 < -100] = np.nan; b = dem.bounds
    n5r, n5c = z10.shape[0] // 5, z10.shape[1] // 5
    z50 = z10[:n5r * 5, :n5c * 5].reshape(n5r, 5, n5c, 5); valid = np.isfinite(z50).all(axis=(1, 3)); z50 = np.nanmean(z50, axis=(1, 3)); z50[~valid] = np.nan
    del z10
    M = 500                                                          # margin cells of 50 m = 25 km
    x0, y0 = b.left - M * 50, b.top + M * 50; nr, nc_ = n5r + 2 * M, n5c + 2 * M
    X = x0 + (np.arange(nc_) + 0.5) * 50.; Y = y0 - (np.arange(nr) + 0.5) * 50.
    tr = Transformer.from_crs("EPSG:31254", "EPSG:4326", always_xy=True)
    lcc = Transformer.from_crs("EPSG:4326", "+proj=lcc +lat_1=44 +lat_2=50 +lat_0=47.264633 +lon_0=11.5 +R=6370000 +units=m", always_xy=True)
    xl0, yl0 = lcc.transform(G["XLONG"][0, 0], G["XLAT"][0, 0]); xl1, yl1 = lcc.transform(G["XLONG"][ny - 1, nx - 1], G["XLAT"][ny - 1, nx - 1])
    print(f"LCC check: grid span {(xl1 - xl0) / 500:.2f} x {(yl1 - yl0) / 500:.2f} cells (expect {nx - 1} x {ny - 1})", flush=True)
    jmap = np.empty((nr, nc_), np.float32); imap = np.empty((nr, nc_), np.float32)
    for r in range(0, nr, 400):
        XX, YY = np.meshgrid(X, Y[r:r + 400]); lo, la = tr.transform(XX, YY); xl, yl = lcc.transform(lo, la)
        imap[r:r + 400] = (xl - xl0) / 500.; jmap[r:r + 400] = (yl - yl0) / 500.
    zm = map_coordinates(hg, [jmap, imap], order=1, mode="nearest").astype(np.float32)
    zc = zm.copy(); zc[M:M + n5r, M:M + n5c] = np.where(valid, z50, zm[M:M + n5r, M:M + n5c])
    fr, fc = np.nonzero(np.pad(valid, M)); ci, cj = np.rint(imap[fr, fc]).astype(int), np.rint(jmap[fr, fc]).astype(int)
    inside = (ci >= 0) & (ci < nx) & (cj >= 0) & (cj < ny); fr, fc, ci, cj = fr[inside], fc[inside], ci[inside], cj[inside]
    dzr, dzc = np.gradient(zc, 50.); gxe_f, gye_f = dzc[fr, fc], -dzr[fr, fc]    # row 0 = north: dz/dnorth = -dz/drow
    _G.update(zc=zc, fr=fr.astype(np.float32), fc=fc.astype(np.float32), fz=zc[fr, fc])
    with Pool(min(NW, NAZ)) as p: hf = np.stack(p.map(_hor_facet, range(NAZ)))
    cell = (cj * nx + ci).astype(np.int32); cnt = np.bincount(cell, minlength=ny * nx).reshape(ny, nx)
    print(f"facets {len(fr)}, cells with >= 85 facets {int((cnt >= 85).sum())}", flush=True)
    np.savez(f"{WORK}/geometry.npz", hc=hc, gxe=gxe.astype(np.float32), gye=gye.astype(np.float32), hf=hf, fcell=cell,
             fgx=gxe_f.astype(np.float32), fgy=gye_f.astype(np.float32), cnt=cnt, lat=G["XLAT"], lon=G["XLONG"])

# ------------------------------------------------------------------ forcing hours
GEO = {}
def load():
    if not GEO: GEO.update({k: v for k, v in np.load(f"{WORK}/geometry.npz").items()})
    return GEO
def _gather(h, az):
    """horizon (NAZ, N) at azimuth az (N,) — linear between sectors"""
    x = az / (2 * np.pi) * NAZ; k0 = np.floor(x).astype(int) % NAZ; k1 = (k0 + 1) % NAZ; w = (x - np.floor(x)).astype(np.float32)
    n = np.arange(h.shape[1]); return h[k0, n].astype(np.float32) * (1 - w) + h[k1, n].astype(np.float32) * w
def cosi(gx, gy, el, az):
    n = 1 / np.sqrt(1 + gx ** 2 + gy ** 2); return n * (-gx * np.sin(az) * np.cos(el) - gy * np.cos(az) * np.cos(el) + np.sin(el))
def cosi_h(gx, gy, el, az):
    """cos(incidence) / cos(slope): direct beam intercepted per unit HORIZONTAL area (energy-conserving facet mean)"""
    return -gx * np.sin(az) * np.cos(el) - gy * np.cos(az) * np.cos(el) + np.sin(el)
def factors(t):
    """hour ending at t (Timestamp): F_sh500, F_sh10 (ny, nx), <sin el> (ny, nx)"""
    g = load(); lat, lon = g["lat"], g["lon"]; ny, nx = lat.shape; doy = t.dayofyear; N = ny * nx
    num_a = np.zeros(N); num_b = np.zeros(N); wsum = np.zeros(N)
    fcell = g["fcell"]; cnt = np.bincount(fcell, minlength=N).astype(float)
    for m in (52.5, 37.5, 22.5, 7.5):
        tt = t - pd.Timedelta(minutes=m); el, az = sun(tt.dayofyear, tt.hour + tt.minute / 60 + tt.second / 3600, lat.ravel(), lon.ravel())
        w = np.maximum(np.sin(el), 0); se = np.maximum(np.sin(el), 1e-2)
        lit = el > _gather(g["hc"].reshape(NAZ, N), az)
        Fa = np.where(w > 0.01, lit * np.maximum(cosi(g["gxe"].ravel(), g["gye"].ravel(), el, az), 0) / se, 1.0)
        elf, azf = el[fcell], az[fcell]; litf = elf > _gather(g["hf"], azf)
        ff = litf * np.maximum(cosi_h(g["fgx"], g["fgy"], elf, azf), 0) / np.maximum(np.sin(elf), 1e-2)
        Fb = np.bincount(fcell, weights=ff, minlength=N) / np.maximum(cnt, 1); Fb = np.where((cnt >= 85) & (w > 0.01), Fb, Fa)
        num_a += w * Fa; num_b += w * Fb; wsum += w
    Fa = np.where(wsum > 0, num_a / np.maximum(wsum, 1e-9), 1.0); Fb = np.where(wsum > 0, num_b / np.maximum(wsum, 1e-9), 1.0)
    return np.minimum(Fa, 4).reshape(ny, nx), np.minimum(Fb, 4).reshape(ny, nx), (wsum / 4).reshape(ny, nx)
def erbs(kt):
    kt = np.clip(kt, 0, 1.2)
    return np.clip(np.where(kt <= 0.22, 1 - 0.09 * kt, np.where(kt <= 0.8, 0.9511 - 0.1604 * kt + 4.388 * kt ** 2 - 16.638 * kt ** 3 + 12.336 * kt ** 4, 0.165)), 0.165, 1.0)
def corrected(f):
    t = pd.Timestamp(f"{os.path.basename(f)[:10]}"[:8] + " " + os.path.basename(f)[8:10] + ":00")
    sw = np.asarray(nc.Dataset(f)["SWDOWN"][0]).astype(float); Fa, Fb, mse = factors(t)
    e0 = 1 + 0.033 * np.cos(2 * np.pi * t.dayofyear / 365); g0 = 1361. * e0 * mse
    fd = np.where(g0 > 20, erbs(sw / np.maximum(g0, 1)), 1.0); Fa = np.where(g0 > 20, Fa, 1.0); Fb = np.where(g0 > 20, Fb, 1.0)
    return t, sw, sw * (fd + (1 - fd) * Fa), sw * (fd + (1 - fd) * Fb), fd, Fa, Fb
def _write(f):
    t, sw, sa, sb, fd, Fa, Fb = corrected(f); out = []
    for name, arr in (("sh500", sa), ("sh10", sb)):
        o = f"{WORK}/LDASIN_{name}/{os.path.basename(f)}"; shutil.copyfile(f, o)
        d = nc.Dataset(o, "r+"); d["SWDOWN"][0] = arr.astype(np.float32)
        d.setncattr("terrain_sw", f"{name}: SW x [f_d + (1 - f_d) F], hrldas_terrain_sw.py (DECISIONS 2026-09-28)"); d.close()
        out.append(float(np.nansum(arr)) / max(float(np.nansum(sw)), 1.))
    return t, float(np.nansum(sw)), out[0], out[1]

def instant(t):
    """instantaneous direct-beam factors and sunlit masks at time t (for validation against WRF's own SWNORM/SWDOWN)"""
    g = load(); lat, lon = g["lat"], g["lon"]; ny, nx = lat.shape; N = ny * nx; fcell = g["fcell"]; cnt = np.bincount(fcell, minlength=N).astype(float)
    el, az = sun(t.dayofyear, t.hour + t.minute / 60, lat.ravel(), lon.ravel()); se = np.maximum(np.sin(el), 1e-2)
    lit = el > _gather(g["hc"].reshape(NAZ, N), az); ca = cosi(g["gxe"].ravel(), g["gye"].ravel(), el, az)
    Fa = lit * np.maximum(ca, 0) / se
    elf, azf = el[fcell], az[fcell]; litf = elf > _gather(g["hf"], azf); cf = cosi_h(g["fgx"], g["fgy"], elf, azf)
    Fb = np.bincount(fcell, weights=litf * np.maximum(cf, 0) / np.maximum(np.sin(elf), 1e-2), minlength=N) / np.maximum(cnt, 1)
    sunlit_b = np.bincount(fcell, weights=(litf & (cf > 0)).astype(float), minlength=N) / np.maximum(cnt, 1)
    return Fa.reshape(ny, nx), Fb.reshape(ny, nx), (lit & (ca > 0)).reshape(ny, nx), sunlit_b.reshape(ny, nx), cnt.reshape(ny, nx)

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "validate":
        t = pd.Timestamp("2025-07-18 17:00"); Fa, Fb, la_, lb, cnt = instant(t)
        w = nc.Dataset(f"{D}/exp/HERO2/wrf_output/8670451/wrfout_d01_2025-07-18_17:00:00.nc"); r = np.asarray(w["SWNORM"][0]) / np.maximum(np.asarray(w["SWDOWN"][0]), 1)
        la, lo = np.asarray(w["XLAT"][0]), np.asarray(w["XLONG"][0]); w.close()
        box = (la > 46.95) & (la < 47.40) & (lo > 11.1) & (lo < 11.95); m = box & (cnt >= 85)
        wrf_sh = r < 0.35; my_sh = Fa < 0.05
        print(f"18 Jul 17:00 UT, box 46.95-47.40 N 11.1-11.95 E ({int(box.sum())} cells): WRF shaded (SWNORM/SWDOWN < 0.35) {wrf_sh[box].mean():.3f}, "
              f"sh500 F = 0 {my_sh[box].mean():.3f}, agreement {np.mean(wrf_sh[box] == my_sh[box]):.3f}; corr(F_sh500, WRF ratio) {np.corrcoef(Fa[box], r[box])[0, 1]:.2f}")
        print(f"  sh10 cells in the box {int(m.sum())}: sunlit fraction sh500 {la_[m].mean():.2f} vs sh10 (facet share) {lb[m].mean():.2f}; "
              f"mean F sh500 {Fa[m].mean():.2f} vs sh10 {Fb[m].mean():.2f}")
        for h in (14, 16, 17, 18):
            Fa, Fb, la_, lb, cnt = instant(pd.Timestamp(f"2025-07-18 {h}:00"))
            print(f"  {h} UT: sunlit fraction sh500 {la_[m].mean():.2f} / sh10 {lb[m].mean():.2f}; mean F {Fa[m].mean():.2f} / {Fb[m].mean():.2f}")
    elif mode == "geometry": geometry()
    elif mode == "test":
        g = load(); cnt = g["cnt"]; print(f"geometry: cells {cnt.size}, sh10 cells {int((cnt >= 85).sum())}")
        for s in sys.argv[2:]:
            f = f"{INDIR}/{s}.LDASIN_DOMAIN1"; t, sw, sa, sb, fd, Fa, Fb = corrected(f); land = np.isfinite(sw)
            m10 = cnt >= 85
            print(f"{t}: SW mean {sw[m10].mean():6.1f} | sh500 {sa[m10].mean():6.1f} | sh10 {sb[m10].mean():6.1f} W m-2 over the sh10 cells; "
                  f"f_d median {np.median(fd[m10]):.2f}; F=0 share sh500 {np.mean(Fa[m10] < 0.05):.2f}, sh10 {np.mean(Fb[m10] < 0.05):.2f}; "
                  f"F median {np.median(Fa[m10]):.2f} / {np.median(Fb[m10]):.2f}")
            np.savez(f"{WORK}/test_{s}.npz", sw=sw, sa=sa, sb=sb, fd=fd, Fa=Fa, Fb=Fb)
    elif mode == "write":
        for v in ("sh500", "sh10"): os.makedirs(f"{WORK}/LDASIN_{v}", exist_ok=True)
        files = sorted(glob.glob(f"{INDIR}/*.LDASIN_DOMAIN1"))
        if len(sys.argv) == 4: files = [f for f in files if sys.argv[2] <= os.path.basename(f)[:10] <= sys.argv[3]]
        load()
        with Pool(NW) as p: res = p.map(_write, files, chunksize=8)
        R = pd.DataFrame(res, columns=["t", "sw", "r500", "r10"]).set_index("t")
        R["month"] = R.index.month
        print("domain-sum SW ratio corrected/original by month (daylight-weighted):")
        for mo, q in R.groupby("month"):
            print(f"  {mo:2d}: sh500 {np.sum(q.sw * q.r500) / q.sw.sum():.3f}  sh10 {np.sum(q.sw * q.r10) / q.sw.sum():.3f}  ({len(q)} files)")
        print(f"wrote {len(files)} files x 2 variants")
