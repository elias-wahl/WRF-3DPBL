#!/usr/bin/env python
"""First look at the new 17-July Doppler-lidar VADs against the evening findings
(DECISIONS 2026-09-02 ~01:30/~02:15/~02:45).

Sites (from the files' own metadata — the dlid86 title says Munich but its coordinates
are Kolsass): dlid86 = Kolsass floor (Wildmann, 75 deg VAD, CNR-filtered here at > -27 dB);
WLS100S34 = Kramsach Oberberg, 755 m, a NORTH-SIDEWALL site (Bergen, 70 deg VAD, 10-min).

Questions: (1) does the observed Kolsass wind profile decay through the evening where the
model keeps a 5-6 m/s up-valley jet at 100-160 m until late? (2) is there any observed NNW
layer near the floor 17:30-22 UT (the model's intrusion skin)? (3) down-valley onset time,
height-resolved. (4) is the sidewall site sheltered (like Stanser Joch) or swept?
"""
import glob

import numpy as np
import netCDF4 as nc
import pandas as pd

D = "/gpfs/data/fs72996/ewahl"
NEW = f"{D}/data/lidar/new"


def load_dlid86(day="20250717"):
    ds = nc.Dataset(f"{NEW}/dlid86/teamx_dlr_dlid86_l2_00_{day}000000.nc")
    t = pd.to_datetime(np.asarray(ds["time"][:]), unit="s")
    Z = np.asarray(ds["Z"][:])
    w = np.ma.filled(ds["WSPD"][:], np.nan)
    d = np.ma.filled(ds["WDIR"][:], np.nan)
    cnr = np.ma.filled(ds["CNR"][:], np.nan)
    bad = ~(cnr > -27.0)
    w[bad] = np.nan
    d[bad] = np.nan
    ds.close()
    return t, Z, w, d


def load_acinn(path):
    ds = nc.Dataset(path)
    t = pd.to_datetime(np.asarray(ds["time"][:]), unit="s",
                       origin=pd.Timestamp(ds["time"].units.split("since")[1].strip().split(".")[0])) \
        if "since" in ds["time"].units else None
    # CF seconds since epoch handled generically:
    import cftime
    tt = nc.num2date(ds["time"][:], ds["time"].units)
    t = pd.to_datetime([pd.Timestamp(str(x)) for x in tt])
    z = np.asarray(ds["height"][:])
    w = np.ma.filled(ds["wspd"][:], np.nan)
    d = np.ma.filled(ds["wdir"][:], np.nan)
    r2 = np.ma.filled(ds["R2"][:], np.nan)
    bad = ~(r2 > 0.9)
    w[bad] = np.nan
    d[bad] = np.nan
    ds.close()
    return t, z, w, d


def band_mean(t, Z, w, d, hh, z0, z1):
    ti = pd.Timestamp(f"2025-07-17 {hh}")
    sel = np.abs((t - ti).total_seconds()) <= 900 if hasattr(t - ti, "total_seconds") else None
    sel = np.array([abs((x - ti).total_seconds()) <= 900 for x in t])
    zm = (Z >= z0) & (Z < z1)
    ws = w[np.ix_(sel, zm)]
    u = -np.nanmean(ws * np.sin(np.radians(d[np.ix_(sel, zm)])))
    v = -np.nanmean(ws * np.cos(np.radians(d[np.ix_(sel, zm)])))
    spd = np.nanmean(ws)
    wd = (np.degrees(np.arctan2(-u, -v))) % 360
    n = np.isfinite(ws).sum()
    return spd, wd, n


def main():
    t, Z, w, d = load_dlid86()
    print("=== dlid86 VAD, KOLSASS floor, 17 July (CNR > -27 dB) ===")
    print("  UT     |  50-150 m       | 150-300 m       | 300-600 m")
    for hh in ["14:00", "15:00", "16:00", "17:00", "17:30", "18:00", "18:30", "19:00",
               "19:30", "20:00", "20:30", "21:00", "21:30", "22:00"]:
        row = f"  {hh}  |"
        for z0, z1 in [(50, 150), (150, 300), (300, 600)]:
            s, wd, n = band_mean(t, Z, w, d, hh, z0, z1)
            row += f"  {s:4.1f} m/s {wd:4.0f}° |" if n > 3 else "     ---       |"
        print(row)

    print("\n=== WLS100S34, KRAMSACH OBERBERG 755 m (north sidewall), R2 > 0.9 ===")
    t2, z2, w2, d2 = load_acinn(f"{NEW}/lidar_data_elias/WLS100S34_20250717_VAD.nc")
    print("  UT     |  50-150 m AGL   | 150-300 m AGL")
    for hh in ["16:00", "17:00", "17:30", "18:00", "19:00", "20:00", "21:00"]:
        row = f"  {hh}  |"
        for z0, z1 in [(50, 150), (150, 300)]:
            s, wd, n = band_mean(t2, z2, w2, d2, hh, z0, z1)
            row += f"  {s:4.1f} m/s {wd:4.0f}° |" if n > 3 else "     ---       |"
        print(row)

    print("\nmodel reference (Kolsass column, measured earlier): 17:30 — 4.4-6.2 m/s from 32-71°")
    print("at 27-160 m (up-valley jet persisting) with a 3.9 m/s NNW skin at 9 m; 21:00 — 2.4-2.6 m/s")
    print("slab through 9-140 m; no down-valley onset by 22 UT.")


if __name__ == "__main__":
    main()
