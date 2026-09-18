#!/usr/bin/env python
"""Surface energy input to the Innsbruck-Jenbach reach by terrain class: ICON surface series vs WRF runs, hourly.
Box 47.27-47.50N 11.30-11.85E; classes on each model's own terrain: floor <700, slopes 700-1800, crests >1800 m.
Usage: python valley_heat_input_icon_vs_wrf.py RUN[=SEGS]... [HOURS=13,14,15,16,17]"""
import glob, sys, numpy as np, netCDF4 as nc, warnings; warnings.filterwarnings("ignore")
D = "/gpfs/data/fs72996/ewahl"
args = [a for a in sys.argv[1:] if not a.startswith("HOURS=")]
HOURS = [int(x) for x in next((a[6:] for a in sys.argv[1:] if a.startswith("HOURS=")), "13,14,15,16,17").split(",")]
fr = lambda segs: {f.split("d01_")[1][:16]: f for s in segs for f in glob.glob(f"{D}/exp/{s}/wrf_output/*/wrfout_d01_*.nc")}
R = {}
for a in args or ["X17=X17a+X17b"]:
    lab, _, segs = a.partition("="); R[lab] = fr(segs.split("+") if segs else [lab])
S = nc.Dataset(f"{D}/ICON/surface_series/icon_surface_2025040100_2025071800.nc"); sla, slo, shg = np.asarray(S["lat"]), np.asarray(S["lon"]), np.asarray(S["HSURF"]); st = np.asarray(S["time"])
box = lambda la, lo: (la > 47.27) & (la < 47.50) & (lo > 11.30) & (lo < 11.85)
CL = (("floor", 0, 700), ("slope", 700, 1800), ("crest", 1800, 9e9), ("all", 0, 9e9))
print("how compared: ICON = hourly surface series (SHFLX/LHFLX upward positive, SWDOWN, T2D, TG) on the series' own HSURF; WRF = instantaneous frames (HFX, LH, SWDOWN, T2, TSK) on WRF HGT; class means over the box; n = cells")
for h in HOURS:
    it = int(np.argmin(np.abs(st - (107 + h / 24.)))); print(f"\n=== {h:02d} UT (ICON series index {it}, t={st[it]*24:.1f} h)")
    print(f"{'class':6s} {'model':5s} {'n':>5s} {'SWdn':>6s} {'H':>6s} {'LE':>6s} {'H+LE':>6s} {'Bowen':>6s} {'T2':>6s} {'Tskin':>6s}")
    rows = {"ICON": dict(la=sla, lo=slo, hg=shg, sw=np.asarray(S["SWDOWN"][it]), H=np.asarray(S["SHFLX"][it]), LE=np.asarray(S["LHFLX"][it]), t2=np.asarray(S["T2D"][it]) - 273.15, ts=np.asarray(S["TG"][it]) - 273.15)}
    for k in R:
        f = R[k].get(f"2025-07-17_{h:02d}:00")
        if not f: continue
        d = nc.Dataset(f); rows[k] = dict(la=np.asarray(d["XLAT"][0]), lo=np.asarray(d["XLONG"][0]), hg=np.asarray(d["HGT"][0]), sw=np.asarray(d["SWDOWN"][0]), H=np.asarray(d["HFX"][0]), LE=np.asarray(d["LH"][0]), t2=np.asarray(d["T2"][0]) - 273.15, ts=np.asarray(d["TSK"][0]) - 273.15); d.close()
    for cn, a, b in CL:
        for name, r in rows.items():
            m = box(r["la"], r["lo"]) & (r["hg"] >= a) & (r["hg"] < b); g = lambda x: float(np.mean(x[m]))
            print(f"{cn:6s} {name:5s} {m.sum():5d} {g(r['sw']):6.0f} {g(r['H']):6.0f} {g(r['LE']):6.0f} {g(r['H'])+g(r['LE']):6.0f} {g(r['H'])/max(g(r['LE']),1):6.2f} {g(r['t2']):6.1f} {g(r['ts']):6.1f}")
