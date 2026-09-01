#!/usr/bin/env python
"""The three obs-side discriminators for the pool-formation deficit (DECISIONS 2026-09-01
~19:45 C1/C2/C4), all from disk — evening of 2025-07-17, UT.

C2  Surface timing at Kolsass: observed net radiation (met_rad, 1-min, 4 components),
    skin temperature from lw_out (emissivity 1), air T (taact), eddy heat flux (vf0 ECpy
    wt1 at 4 m, 30-min, x rho*cp ~ 1100 W m-2 per K m s-1) vs model TSK/T2/HFX/GRDFLX —
    5-min stream (qsqdiag, 19:00->) plus X10a 30-min frames before 19:00.
C1  Slope drainage onset: i-Box slope stations mean_t1/mean_spd1/wdir1 (30-min) vs the
    model's T2/10-m wind at the mapped cells. Katabatic direction reference = aspect+180.
C4  Down-valley onset at Kolsass: SONIC2 4-level speed/direction (1-min) vs model 10-m
    wind. Down-valley flow at Kolsass comes FROM ~WSW (~247 deg).

Model = EVE1 (3D closure). Heights differ (obs sonics 4-17 m vs model 10 m/first level
~9 m) — compare onset TIMES and tendencies, not absolute speeds.
"""
import glob

import numpy as np
import pandas as pd
import netCDF4 as nc

D = "/gpfs/data/fs72996/ewahl"
SIGMA, RHOCP = 5.670e-8, 1100.0
STATIONS = {  # code: (lat, lon, aspect_deg)  from ibox stations.csv
    "vf0": (47.305341, 11.62219, 188), "sf8": (47.325538, 11.65247, 147),
    "nf10": (47.299754, 11.672969, 314), "nf27": (47.28755, 11.63122, 1),
}


def cells(path, codes):
    ds = nc.Dataset(path)
    xlat, xlon = np.asarray(ds["XLAT"][0]), np.asarray(ds["XLONG"][0])
    out = {}
    for c in codes:
        la, lo, _ = STATIONS[c]
        out[c] = np.unravel_index(np.argmin((xlat - la) ** 2 + (xlon - lo) ** 2), xlat.shape)
    ds.close()
    return out


def model_series(codes):
    """5-min qsqdiag (19->01) + 30-min X10a frames (17->19); returns DataFrame per code."""
    rows = {c: [] for c in codes}
    frames = sorted(glob.glob(f"{D}/exp/X10a/wrf_output/*/wrfout_d01_2025-07-17_1[789]*.nc")) \
        + sorted(glob.glob(f"{D}/exp/EVE1/temp/branko/qsqdiag_d01_*.nc"))
    ji = cells(frames[0], codes)
    for f in frames:
        ds = nc.Dataset(f)
        t = pd.Timestamp(f[-22:-3].replace("_", " "))
        for c in codes:
            j, i = ji[c]
            rows[c].append(dict(
                t=t, tsk=float(ds["TSK"][0, j, i]) - 273.15, t2=float(ds["T2"][0, j, i]) - 273.15,
                hfx=float(ds["HFX"][0, j, i]), grdflx=float(ds["GRDFLX"][0, j, i]),
                u10=float(ds["U10"][0, j, i]), v10=float(ds["V10"][0, j, i])))
        ds.close()
    out = {}
    for c in codes:
        df = pd.DataFrame(rows[c]).drop_duplicates("t").set_index("t").sort_index()
        df["spd"] = np.hypot(df.u10, df.v10)
        df["wdir"] = (np.degrees(np.arctan2(-df.u10, -df.v10))) % 360
        out[c] = df
    return out


def zero_cross(series, window=("2025-07-17 16:00", "2025-07-17 21:00")):
    s = series.loc[window[0]:window[1]]
    neg = s[s < 0]
    return neg.index[0] if len(neg) else None


def main():
    mod = model_series(list(STATIONS))

    # ---------------- C2: Kolsass surface timing ----------------
    mr = pd.read_csv(f"{D}/data/stations/kol/202507-70322_met_rad.csv", sep=";", comment="#")
    mr["t"] = pd.to_datetime(mr["rawdate"])
    mr = mr.set_index("t").loc["2025-07-17 15:00":"2025-07-17 23:00"]
    mr["rnet"] = mr.sw_in_avg - mr.sw_out_avg + mr.lw_in_avg - mr.lw_out_avg
    mr["tskin"] = (mr.lw_out_avg / SIGMA) ** 0.25 - 273.15
    ec = pd.read_csv(f"{D}/data/stations/ibox_ecpy/vf0_toc_ecpy_30min_2025.csv",
                     skiprows=[1], na_values=["NAN"])
    ec["t"] = pd.to_datetime(ec["Date/Time"], format="%d/%m/%Y %H:%M:%S")
    ec = ec.set_index("t").loc["2025-07-17 15:00":"2025-07-17 23:00"]
    ec = ec[ec.qcflag_wt1 > -1]

    print("=== C2: Kolsass surface timing (17 Jul, UT) ===")
    print(f"obs sunset (sw_in < 5 W/m2):        {mr[mr.sw_in_avg < 5].index[0]:%H:%M}")
    print(f"obs R_net crosses 0:                {mr[mr.rnet < 0].index[0]:%H:%M}")
    print(f"obs skin-air dT crosses 0:          {mr[(mr.tskin - mr.taact_avg) < 0].index[0]:%H:%M}")
    wtW = ec.wt1 * RHOCP
    neg = wtW[wtW < -5]
    print(f"obs eddy heat flux < -5 W/m2 (4 m): {neg.index[0]:%H:%M}" if len(neg) else "obs flux never < -5")
    m = mod["vf0"]
    mneg = m.hfx[m.hfx < -5]
    print(f"model HFX < -5 W/m2:                {mneg.index[0]:%H:%M}" if len(mneg) else "model HFX never < -5 W/m2")
    print("\n  UT     obs: wt*rcp  Tskin-Tair | model: HFX  GRDFLX  TSK-T2")
    for hh in ["17:00", "18:00", "18:30", "19:00", "19:30", "20:00", "20:30", "21:00", "22:00"]:
        t = pd.Timestamp(f"2025-07-17 {hh}")
        o = ec[abs(ec.index - t) <= pd.Timedelta("15min")]
        r = mr[abs(mr.index - t) <= pd.Timedelta("3min")]
        mm = m[abs(m.index - t) <= pd.Timedelta("3min")]
        ow = o.wt1.mean() * RHOCP if len(o) else np.nan
        od = (r.tskin - r.taact_avg).mean() if len(r) else np.nan
        print(f"  {hh}  {ow:+9.1f}  {od:+9.2f}   | {mm.hfx.mean():+7.1f} {mm.grdflx.mean():+7.1f} {(mm.tsk - mm.t2).mean():+7.2f}")

    # ---------------- C1: slope drainage onset ----------------
    print("\n=== C1: slope stations, 30-min (obs level 1 ~4-7 m vs model 10 m) ===")
    for c in ("sf8", "nf10", "nf27"):
        f = glob.glob(f"{D}/data/stations/ibox_ecpy/{c}_*.csv")[0]
        o = pd.read_csv(f, skiprows=[1], na_values=["NAN"])
        o["t"] = pd.to_datetime(o["Date/Time"], format="%d/%m/%Y %H:%M:%S")
        o = o.set_index("t").loc["2025-07-17 16:00":"2025-07-17 23:00"]
        kat = (STATIONS[c][2] + 180) % 360
        m = mod[c]
        print(f"\n  {c} (katabatic wdir ref ~{kat:.0f}):  UT  obs T1/spd1/wdir1 | model T2/spd10/wdir10")
        for hh in ["17:00", "18:00", "19:00", "20:00", "21:00", "22:00"]:
            t = pd.Timestamp(f"2025-07-17 {hh}")
            oo = o[abs(o.index - t) <= pd.Timedelta("15min")]
            mm = m[abs(m.index - t) <= pd.Timedelta("3min")]
            print(f"    {hh}  {oo.mean_t1.mean():5.1f}C {oo.mean_spd1.mean():4.1f} {oo.wdir1.mean():5.0f} | "
                  f"{mm.t2.mean():5.1f}C {mm.spd.mean():4.1f} {mm.wdir.mean():5.0f}")

    # ---------------- C4: down-valley onset at Kolsass ----------------
    sn = pd.read_csv(f"{D}/data/stations/kol/202507-70322_wind_prof.csv", sep=";", comment="#")
    sn["t"] = pd.to_datetime(sn["rawdate"])
    sn = sn.set_index("t").loc["2025-07-17 16:00":"2025-07-17 23:00"]
    print("\n=== C4: Kolsass down-valley onset (down-valley wdir ~247; obs sonic L4 vs model 10 m) ===")
    m = mod["vf0"]
    for hh in ["17:00", "18:00", "19:00", "19:30", "20:00", "20:30", "21:00", "22:00"]:
        t = pd.Timestamp(f"2025-07-17 {hh}")
        oo = sn[abs(sn.index - t) <= pd.Timedelta("10min")]
        mm = m[abs(m.index - t) <= pd.Timedelta("3min")]
        print(f"  {hh}  obs {oo.wind_speed_4.mean():4.1f} m/s from {oo.avg_wdir4.mean():5.0f} | "
              f"model {mm.spd.mean():4.1f} m/s from {mm.wdir.mean():5.0f}")


if __name__ == "__main__":
    main()
