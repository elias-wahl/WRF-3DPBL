#!/usr/bin/env python
"""Kolsass HATPRO nocturnal cooling trajectory + soil-side SEB check (data of 2026-09-01).

Part 1 — the observed target curve for the 6th-order-filter experiment (A20): layer-mean
potential temperature above Kolsass from the HATPRO microwave radiometer (39 retrieval
levels, 10-min), 2025-07-17 12 UT -> 07-18 08 UT, with hourly cooling rates and the
01-05 UT mean rate (the experiment window), against the filter-ON model (X10c) column.

Level heights are a HYPOTHESIS: the standard RPG 39-level zenith grid (m AGL). It is
validated in-script against the recorded 05:02 sonde layer means (theta 290.81 K over
600-900 m ASL, 293.21 over 600-1500; DECISIONS 2026-08-31 22:25) before anything else
is trusted. theta from T via p(z) = p0 exp(-z/H), p0 = 950 hPa at station (545 m),
H = 8000 m — errors ~0.2 K absolute, ~0 for rates.

Part 2 — BODEN/BODEN2: nocturnal soil heat flux and soil temperatures vs the model's
GRDFLX/TSK/T2/HFX at the Kolsass cell (CPB probe wrfout, 01:20 and 04:20 UT).
Timestamps assumed UTC — checked by the hour of the daytime soil-heat-flux maximum.
"""
import glob

import numpy as np
import pandas as pd
import netCDF4 as nc

D = "/gpfs/data/fs72996/ewahl"
KOL = f"{D}/data/stations/kol/kolsass_claude"
LAT, LON, ELEV = 47.305341, 11.62219, 545.0

Z39 = np.array([0, 10, 30, 50, 75, 100, 125, 150, 200, 250, 325, 400, 475, 550,
                625, 700, 800, 900, 1000, 1150, 1300, 1450, 1600, 1800, 2000,
                2200, 2500, 2800, 3100, 3500, 3900, 4400, 5000, 5600, 6200,
                7000, 8000, 9000, 10000], dtype=float)  # m AGL, RPG standard (hypothesis)

KAPPA, P0, H = 0.2854, 950.0, 8000.0


def load_hatpro():
    f = glob.glob(f"{KOL}/acinn_data_HATPRO UIBK Temperature_RAW_*/data.csv")[0]
    df = pd.read_csv(f, sep=";", comment="#")
    t = pd.to_datetime(df["rawdate"])
    T = df[[c for c in df.columns if c.startswith("v")]].to_numpy(float)  # K
    p = P0 * np.exp(-Z39 / H)
    theta = T * (1000.0 / p[None, :]) ** KAPPA
    return t, theta


def layer_mean(theta, z, a, b):
    m = (z >= a) & (z < b)
    return theta[:, m].mean(axis=1)


def model_column_theta(path, lat, lon):
    ds = nc.Dataset(path)
    xlat, xlon = np.asarray(ds["XLAT"][0]), np.asarray(ds["XLONG"][0])
    j, i = np.unravel_index(np.argmin((xlat - lat) ** 2 + (xlon - lon) ** 2), xlat.shape)
    th = np.asarray(ds["T"][0, :, j, i]) + 300.0
    ph = (np.asarray(ds["PH"][0, :, j, i]) + np.asarray(ds["PHB"][0, :, j, i])) / 9.81
    z_agl = 0.5 * (ph[:-1] + ph[1:]) - float(ds["HGT"][0, j, i])
    hgt = float(ds["HGT"][0, j, i])
    return th, z_agl, hgt, (j, i), ds


def main():
    t, theta = load_hatpro()

    # ---- grid validation vs the recorded sonde layer means (05:02 UT) ----
    i05 = np.argmin(np.abs(t - pd.Timestamp("2025-07-18 05:00:00")))
    z_asl = Z39 + ELEV
    m1 = (z_asl >= 600) & (z_asl < 900)
    m2 = (z_asl >= 600) & (z_asl < 1500)
    print("grid validation at 05:00 UT (sonde 05:02 recorded: 290.81 / 293.21 K):")
    print(f"  HATPRO theta(600-900 m ASL)  = {theta[i05, m1].mean():7.2f} K")
    print(f"  HATPRO theta(600-1500 m ASL) = {theta[i05, m2].mean():7.2f} K")

    # ---- observed trajectory and cooling rates ----
    bands = [(0, 100), (0, 300), (300, 600)]
    print("\nhourly layer-mean theta above station (K) and rate (K/h):")
    hours = pd.date_range("2025-07-17 15:00", "2025-07-18 08:00", freq="1h")
    prev = {}
    for hh in hours:
        i = np.argmin(np.abs(t - hh))
        if abs((t[i] - hh).total_seconds()) > 600:
            continue
        row = f"  {hh:%d %H UT}"
        for a, b in bands:
            v = layer_mean(theta, Z39, a, b)[i]
            r = f" ({v - prev[(a, b)]:+5.2f})" if (a, b) in prev else "        "
            row += f"   {a}-{b}m {v:7.2f}{r}"
            prev[(a, b)] = v
        print(row)
    v = layer_mean(theta, Z39, 0, 300)
    i1 = np.argmin(np.abs(t - pd.Timestamp("2025-07-18 01:00:00")))
    i5 = np.argmin(np.abs(t - pd.Timestamp("2025-07-18 05:00:00")))
    print(f"\nOBSERVED mean cooling rate 0-300 m, 01-05 UT: {(v[i5] - v[i1]) / 4:+.3f} K/h")

    # ---- filter-ON model at the same column (01:00 lives in the previous segment) ----
    print("\nmodel (filter ON, X10b/X10c) Kolsass column, theta 0-300 m AGL:")
    arch = sorted(glob.glob(f"{D}/exp/X10b/wrf_output/*/wrfout_d01_2025-07-18_01:00:00.nc")
                  + glob.glob(f"{D}/exp/X10c/wrf_output/*/wrfout_d01_2025-07-18_0[2-5]:00:00.nc"))
    vals = []
    for p in arch:
        th, z, hgt, ji, ds = model_column_theta(p, LAT, LON)
        m = (z >= 0) & (z < 300)
        vals.append(th[m].mean())
        print(f"  {p[-22:-3]}  {vals[-1]:7.2f} K   (cell HGT {hgt:.0f} m)")
        ds.close()
    if len(vals) >= 2:
        print(f"MODEL (filter ON) mean cooling rate 0-300 m, 01-05 UT: {(vals[-1] - vals[0]) / (len(vals) - 1):+.3f} K/h")

    # ---- soil / SEB side ----
    print("\n--- soil (BODEN, 1-min) ---")
    fb = glob.glob(f"{KOL}/acinn_data_i-Box Kolsass_BODEN_fb*/data.csv")[0]
    b = pd.read_csv(fb, sep=";", comment="#")
    b["t"] = pd.to_datetime(b["rawdate"])
    peak = b.loc[b["hfso_avg"].idxmax(), "t"]
    print(f"UTC check: daytime soil-heat-flux max at {peak} (expect ~11-12 UT local solar noon)")
    night = b[(b["t"] >= "2025-07-17 18:00") & (b["t"] <= "2025-07-18 07:00")]
    print(f"night 18-07 UT: hfso {night['hfso_avg'].mean():+.1f} W/m2 "
          f"(range {night['hfso_avg'].min():+.1f}..{night['hfso_avg'].max():+.1f}), "
          f"tso {night['tso_avg'].mean():.1f} C, mso {night['mso_avg'].mean():.1f} %")
    f2 = glob.glob(f"{KOL}/acinn_data_i-Box Kolsass_BODEN2_9*/data.csv")[0]
    b2 = pd.read_csv(f2, sep=";", comment="#")
    b2["t"] = pd.to_datetime(b2["rawdate"])
    n2 = b2[(b2["t"] >= "2025-07-17 18:00") & (b2["t"] <= "2025-07-18 07:00")]
    print(f"BODEN2 hfso_2 night mean {n2['hfso_2'].mean():+.1f} W/m2 "
          f"(range {n2['hfso_2'].min():+.1f}..{n2['hfso_2'].max():+.1f}) -- check plausibility")
    cols = [c for c in b2.columns if c.startswith("t_soil")]
    print("soil T night mean (t_soil_1..8, C):", " ".join(f"{n2[c].mean():.2f}" for c in cols))

    print("\nmodel surface at the Kolsass cell (CPB probes):")
    for tag, path, tt in [("01:20", f"{D}/exp/CPB1d/wrf_output/8552151/wrfout_d01_2025-07-18_01:20:00.nc", "2025-07-18 01:20"),
                          ("04:20", f"{D}/exp/CPB2d/wrf_output/8552763/wrfout_d01_2025-07-18_04:20:00.nc", "2025-07-18 04:20")]:
        ds = nc.Dataset(path)
        xlat, xlon = np.asarray(ds["XLAT"][0]), np.asarray(ds["XLONG"][0])
        j, i = np.unravel_index(np.argmin((xlat - LAT) ** 2 + (xlon - LON) ** 2), xlat.shape)
        ob = b[np.abs(b["t"] - pd.Timestamp(tt)) <= pd.Timedelta("5min")]
        print(f"  {tag} UT: GRDFLX {float(ds['GRDFLX'][0, j, i]):+7.1f}  HFX {float(ds['HFX'][0, j, i]):+7.1f}  "
              f"TSK {float(ds['TSK'][0, j, i]) - 273.15:6.2f} C  T2 {float(ds['T2'][0, j, i]) - 273.15:6.2f} C  "
              f"| obs hfso {ob['hfso_avg'].mean():+6.1f} W/m2, tso {ob['tso_avg'].mean():5.2f} C")
        ds.close()


if __name__ == "__main__":
    main()
