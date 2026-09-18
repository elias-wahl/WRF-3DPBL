#!/usr/bin/env python
"""Northerly break-in check: 10 m station winds (Innsbruck, Jenbach, Rinn, Kufstein) vs runs,
crest/floor meridional wind, Kolsass lidar bands, floor HFX/T2, hourly 14-18 UT (or HOURS=...).
Usage: python breakin_check.py RUN[=SEG1+SEG2] ...   e.g. X17=X17a+X17b X17m X19r   [HOURS=16,17,18]
Comparison method printed in the header (E59). conda env proc, env -u PYTHONPATH."""
import glob, sys, numpy as np, pandas as pd, netCDF4 as nc, warnings
warnings.filterwarnings("ignore"); sys.path.insert(0, "/gpfs/data/fs72996/ewahl/wrf3dpbl-diag")
from evening18_check import lidar, vmean, model_col
D = "/gpfs/data/fs72996/ewahl"
args = [a for a in sys.argv[1:] if not a.startswith("HOURS=")]
HOURS = [int(x) for x in next((a[6:] for a in sys.argv[1:] if a.startswith("HOURS=")), "14,15,16,17,18").split(",")]
def fr(segs): return {f.split("d01_")[1][:16]: f for s in segs for f in glob.glob(f"{D}/exp/{s}/wrf_output/*/wrfout_d01_*.nc") + glob.glob(f"{D}/exp/{s}/temp/branko/wrfout_d01_*.nc")}
R = {}
for a in args or ["X17=X17a+X17b"]:
    lab, _, segs = a.partition("="); R[lab] = fr(segs.split("+") if segs else [lab])
names = list(R)
g = nc.Dataset(next(iter(R[names[0]].values()))); la, lo, hg = np.asarray(g["XLAT"][0]), np.asarray(g["XLONG"][0]), np.asarray(g["HGT"][0]); g.close()
df = pd.read_csv(f"{D}/data/stations/tawes/klima_10min_20250716_20250719.csv"); df["t"] = pd.to_datetime(df["time"]).dt.tz_localize(None)
ST = {"Innsbruck": (11804, 47.260, 11.357, 578.), "Jenbach": (11901, 47.389, 11.758, 529.), "Rinn": (14822, 47.249, 11.504, 924.), "Kufstein": (9016, 47.575, 12.163, 490.)}
def cells(y, x, alt): dd = np.hypot((la - y) * 111e3, (lo - x) * 111e3 * np.cos(np.radians(47.4))); return np.where((dd < 1500) & (np.abs(hg - alt) < 40))
def w10(f, jj, ii):
    d = nc.Dataset(f); u, v = np.asarray(d["U10"][0]), np.asarray(d["V10"][0]); ca, sa = np.asarray(d["COSALPHA"][0]), np.asarray(d["SINALPHA"][0]); d.close()
    ue, ve = (u * ca - v * sa)[jj, ii].mean(), (v * ca + u * sa)[jj, ii].mean(); return np.hypot(ue, ve), np.degrees(np.arctan2(-ue, -ve)) % 360
W = 10 + 11 * len(names)
print("how compared: stations = hourly vector-mean 10 m wind (speed/dir from); models = 10 m diagnostic, vector mean over cells within 1.5 km and +-40 m of the station height, instantaneous frame; no exposure correction")
print(f"{'UT':5s} " + " ".join(f"{n + ': obs | ' + ' | '.join(names):^{W}s}" for n in ST))
for h in HOURS:
    ts = pd.Timestamp(f"2025-07-17 {h}:00"); row = f"{h}:00 "
    for n, (k, y, x, alt) in ST.items():
        w = df[(df.station == k) & (df.t > ts - pd.Timedelta("30min")) & (df.t <= ts + pd.Timedelta("30min"))]; r = np.radians(w["dd"].values)
        uo, vo = np.nanmean(-w["ff"].values * np.sin(r)), np.nanmean(-w["ff"].values * np.cos(r)); c = f"{np.hypot(uo, vo):4.1f}/{np.degrees(np.arctan2(-uo, -vo)) % 360:3.0f}"
        jj, ii = cells(y, x, alt)
        for rn in names:
            f = R[rn].get(f"{ts:%Y-%m-%d_%H:%M}"); c += (" | %4.1f/%3.0f" % w10(f, jj, ii)) if f else " |    --   "
        row += f"{c:^{W}s} "
    print(row)
b = (la > 47.27) & (la < 47.50) & (lo > 11.30) & (lo < 11.85); lh, Z, wl, dl = lidar("0717"); us = lambda s, dd: s * np.cos(np.radians(dd - 75.))
print("\ncrest 10 m meridional wind v [m/s] (terrain >1800 m, box 47.27-47.50N 11.30-11.85E; ICON -2.4..-2.7 at 14-17 UT) | floor (<700 m) | Kolsass up-valley wind 50-150 / 150-300 m AGL (lidar 15-min window) | floor-class HFX [W/m2], T2 [degC]")
for h in HOURS:
    ts = pd.Timestamp(f"2025-07-17 {h}:00"); row = f"{h}:00 "
    for rn in names:
        f = R[rn].get(f"{ts:%Y-%m-%d_%H:%M}")
        if not f: row += f" {rn}: --  |"; continue
        d = nc.Dataset(f); ca, sa = np.asarray(d["COSALPHA"][0]), np.asarray(d["SINALPHA"][0]); v = np.asarray(d["V10"][0]) * ca + np.asarray(d["U10"][0]) * sa; hfx = np.asarray(d["HFX"][0]); t2 = np.asarray(d["T2"][0]); d.close()
        z, s, dd = model_col(f); k = [us(*vmean(s[(z >= a) & (z < c)], dd[(z >= a) & (z < c)])) for a, c in ((50, 150), (150, 300))]
        row += f" {rn}: crest v {v[b & (hg > 1800)].mean():+5.1f}, floor v {v[b & (hg < 700)].mean():+5.1f}, Kols {k[0]:+4.1f}/{k[1]:+4.1f}, HFX crest {hfx[b & (hg > 1800)].mean():4.0f} floor {hfx[b & (hg < 700)].mean():4.0f}, T2 floor {t2[b & (hg < 700)].mean() - 273.15:4.1f} |"
    sel = np.abs(lh - h) <= 0.25; lk = [us(*vmean(wl[np.ix_(sel, (Z >= a) & (Z < c))], dl[np.ix_(sel, (Z >= a) & (Z < c))])) for a, c in ((50, 150), (150, 300))]
    print(row + f" lidar {lk[0]:+4.1f}/{lk[1]:+4.1f}")
