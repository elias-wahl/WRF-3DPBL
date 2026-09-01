#!/usr/bin/env python
"""HATPRO retrieval vs the co-located Kolsass radiosondes (launched < 100 m away, Elias).

For every launch with HATPRO coverage (2025-07-18: 05, 08, 11, 14, 17, 20, 23 UT), the
sonde theta (air_potential_temperature, referenced 1000 hPa, 1-s ascent) is averaged into
height bands (m AGL, station 545 m ASL) and compared with the HATPRO profile nearest the
launch time + 3 min (the lowest 2 km take the sonde ~7 min). Same theta convention on
both sides. The 20 and 23 UT launches test HATPRO in exactly the post-sunset phase in
which it is the only profile source for the IOP formation night (17 Jul 19-21 UT).
"""
import glob

import numpy as np
import pandas as pd

D = "/gpfs/data/fs72996/ewahl"
ELEV = 545.0
Z39 = np.array([0, 10, 30, 50, 75, 100, 125, 150, 200, 250, 325, 400, 475, 550,
                625, 700, 800, 900, 1000, 1150, 1300, 1450, 1600, 1800, 2000,
                2200, 2500, 2800, 3100, 3500, 3900, 4400, 5000, 5600, 6200,
                7000, 8000, 9000, 10000], dtype=float)
KAPPA, P0, H = 0.2854, 950.0, 8000.0
BANDS = [(0, 100), (100, 300), (300, 600), (600, 1000), (1000, 2000)]


def load_hatpro():
    f = glob.glob(f"{D}/data/stations/kol/kolsass_claude/acinn_data_HATPRO UIBK Temperature_RAW_*/data.csv")[0]
    df = pd.read_csv(f, sep=";", comment="#")
    t = pd.to_datetime(df["rawdate"])
    T = df[[c for c in df.columns if c.startswith("v")]].to_numpy(float)
    p = P0 * np.exp(-Z39 / H)
    return t, T * (1000.0 / p[None, :]) ** KAPPA


def load_sonde(path):
    df = pd.read_csv(path, skiprows=8, header=None, usecols=[3, 11],
                     names=["z_asl", "theta"])
    with open(path) as fh:
        for line in fh:
            if "ascent start time" in line:
                t0 = pd.Timestamp(line.split(": ", 1)[1].replace(" UTC", "").strip())
                break
    return t0, df


def main():
    th, theta_h = load_hatpro()
    rows = []
    for f in sorted(glob.glob(f"{D}/data/soundings/kol/2025071[89]*-11121.csv")):
        t0, s = load_sonde(f)
        if t0 > th.iloc[-1]:
            continue
        i = np.argmin(np.abs(th - (t0 + pd.Timedelta("3min"))))
        prof = theta_h[i]
        z_agl = s["z_asl"] - ELEV
        row = {"launch": f"{t0:%d %H:%M}"}
        for a, b in BANDS:
            ms = (z_agl >= a) & (z_agl < b)
            mh = (Z39 >= a) & (Z39 < b)
            row[f"{a}-{b}m"] = prof[mh].mean() - s.loc[ms, "theta"].mean() if ms.sum() else np.nan
        rows.append(row)
    out = pd.DataFrame(rows)
    pd.set_option("display.width", 160)
    print("HATPRO minus sonde, layer-mean theta bias (K), heights AGL:")
    print(out.to_string(index=False, float_format=lambda x: f"{x:+7.2f}"))
    print("\nmean |bias| per band:",
          "  ".join(f"{c}: {out[c].abs().mean():.2f}" for c in out.columns[1:]))


if __name__ == "__main__":
    main()
