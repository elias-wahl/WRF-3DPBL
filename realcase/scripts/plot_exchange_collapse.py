#!/usr/bin/env python
"""Figure: the evening-transition failure at Kolsass, 2025-07-17, 14-22 UT (DECISIONS
2026-09-02 ~01:30). Three panels, all computed from the source files:
(a) floor wind — the observed four-hour decay through the calm vs the model's regime
    handoff (weak up-valley -> early NNW crossflow at 17:30, never quiet);
(b) effective exchange conductance |ChU| = |H| / (rho cp |dT_skin-air|), log scale —
    the observed collapse vs the model bottoming out an order too high;
(c) the (bulk Ri, |ChU|) trajectory of the stable hours 19-22 UT — the observed surface
    walks into the high-Ri collapsed branch; the model stays pinned at low Ri.
obs: EC flux (i-Box vf0 sonic 4 m, 30-min, QC>-1), skin T from CNR4 lw_out (eps 0.97),
air T 2 m (tower), wind sonic level 4. model: X10a 30-min frames (14:00-18:30) +
the instrumented evening run's 5-min stream sampled half-hourly (19:00-22:00),
Kolsass cell (HFX, TSK, T2, U10/V10).
"""
import glob

import numpy as np
import pandas as pd
import netCDF4 as nc
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = "/gpfs/data/fs72996/ewahl"
OBS, MOD = "#2a78d6", "#eb6834"
INK, INK2, GRID = "#333333", "#666666", "#e6e6e6"
SIG, EPS, RHOCP, G = 5.670e-8, 0.97, 1100.0, 9.81
LAT, LON = 47.305341, 11.62219

times = pd.date_range("2025-07-17 14:00", "2025-07-17 22:00", freq="30min")

# ---------------- observations ----------------
ec = pd.read_csv(f"{D}/data/stations/ibox_ecpy/vf0_toc_ecpy_30min_2025.csv",
                 skiprows=[1], na_values=["NAN"])
ec["t"] = pd.to_datetime(ec["Date/Time"], format="%d/%m/%Y %H:%M:%S")
ec = ec.set_index("t"); ec = ec[ec.qcflag_wt1 > -1]
mr = pd.read_csv(f"{D}/data/stations/kol/202507-70322_met_rad.csv", sep=";", comment="#")
mr["t"] = pd.to_datetime(mr["rawdate"]); mr = mr.set_index("t")
sn = pd.read_csv(f"{D}/data/stations/kol/202507-70322_wind_prof.csv", sep=";", comment="#")
sn["t"] = pd.to_datetime(sn["rawdate"]); sn = sn.set_index("t")

obs = []
for t in times:
    e = ec[abs(ec.index - t) <= pd.Timedelta("15min")]
    r = mr[abs(mr.index - t) <= pd.Timedelta("5min")]
    s = sn[abs(sn.index - t) <= pd.Timedelta("10min")]
    H = e.wt1.mean() * RHOCP
    tskin = ((r.lw_out_avg - (1 - EPS) * r.lw_in_avg) / (EPS * SIG)).mean() ** 0.25 - 273.15
    dT = tskin - r.taact_avg.mean()
    U = s.wind_speed_4.mean()
    obs.append(dict(t=t, H=H, dT=dT, U=U,
                    chu=abs(H) / RHOCP / abs(dT) * 1000 if abs(dT) > 0.25 else np.nan,
                    ri=G / 288 * (-dT) * 4.0 / max(U, 0.2) ** 2))
obs = pd.DataFrame(obs).set_index("t")

# ---------------- model ----------------
def cell_fields(path):
    ds = nc.Dataset(path)
    xlat, xlon = np.asarray(ds["XLAT"][0]), np.asarray(ds["XLONG"][0])
    j, i = np.unravel_index(np.argmin((xlat - LAT) ** 2 + (xlon - LON) ** 2), xlat.shape)
    out = dict(H=float(ds["HFX"][0, j, i]),
               dT=float(ds["TSK"][0, j, i]) - float(ds["T2"][0, j, i]),
               U=float(np.hypot(ds["U10"][0, j, i], ds["V10"][0, j, i])))
    ds.close()
    return out

mod = []
for t in times:
    hh = t.strftime("%H:%M")
    f = glob.glob(f"{D}/exp/X10a/wrf_output/*/wrfout_d01_2025-07-17_{hh}:00.nc") \
      + glob.glob(f"{D}/exp/EVE1/temp/branko/qsqdiag_d01_2025-07-17_{hh}:00.nc")
    if not f:
        mod.append(dict(t=t, H=np.nan, dT=np.nan, U=np.nan, chu=np.nan, ri=np.nan)); continue
    c = cell_fields(f[0])
    mod.append(dict(t=t, **c,
                    chu=abs(c["H"]) / RHOCP / abs(c["dT"]) * 1000 if abs(c["dT"]) > 0.25 else np.nan,
                    ri=G / 288 * (-c["dT"]) * 8.0 / max(c["U"], 0.2) ** 2))
mod = pd.DataFrame(mod).set_index("t")

# ---------------- figure ----------------
fig, (wx, ax, bx) = plt.subplots(1, 3, figsize=(14.5, 4.4), dpi=200)
fig.subplots_adjust(left=0.055, right=0.99, top=0.84, bottom=0.19, wspace=0.26)
for a in (wx, ax, bx):
    a.set_facecolor("white")
    a.grid(True, color=GRID, linewidth=0.7, zorder=0)
    for s in a.spines.values():
        s.set_color(GRID)
    a.tick_params(colors=INK2, labelsize=8.5)

x = np.arange(len(times))
ticks = [i for i, t in enumerate(times) if t.minute == 0]
tlabs = [times[i].strftime("%H") for i in ticks]
sunset = list(times).index(pd.Timestamp("2025-07-17 18:30"))
lull = list(times).index(pd.Timestamp("2025-07-17 20:30"))

# (a) wind
wx.axvline(sunset + 0.1, color=GRID, lw=1.2, zorder=1)
wx.text(sunset + 0.25, 0.25, "sunset 18:33", color=INK2, fontsize=8, rotation=90, va="bottom")
wx.plot(x, mod.U, "-o", color=MOD, lw=2, ms=5, zorder=3)
wx.plot(x, obs.U, "-o", color=OBS, lw=2, ms=5, zorder=3)
wx.set_xticks(ticks, tlabs)
wx.set_ylim(0, 7)
wx.set_ylabel("floor wind speed  (m s$^{-1}$)", color=INK, fontsize=9)
wx.set_xlabel("17 July 2025, UT", color=INK2, fontsize=9)
wx.set_title("(a) the observed decay the model never has", color=INK, fontsize=10, loc="left")
wx.text(2.6, 5.4, "observed (sonic L4)", color=OBS, fontsize=9)
wx.text(4.0, 1.9, "model (10 m)", color=MOD, fontsize=9)
wx.annotate("17:30: model hands off to a\nNNW crossflow, never quiet", xy=(7, 4.0), xytext=(6.2, 6.1),
            color=INK2, fontsize=8, arrowprops=dict(arrowstyle="-", color=INK2, lw=0.8))
wx.annotate("calm", xy=(lull, 1.0), xytext=(lull + 0.8, 2.6),
            color=INK2, fontsize=8, arrowprops=dict(arrowstyle="-", color=INK2, lw=0.8))

# (b) conductance
ax.axvline(sunset + 0.1, color=GRID, lw=1.2, zorder=1)
ax.axvspan(lull - 0.15, lull + 0.15, color="#f0f0f0", zorder=0)
ax.plot(x, mod.chu, "-o", color=MOD, lw=2, ms=5, zorder=3)
ax.plot(x, obs.chu, "-o", color=OBS, lw=2, ms=5, zorder=3)
up = [i for i, t in enumerate(times) if t == pd.Timestamp("2025-07-17 21:30")]
ax.plot(up, obs.chu.iloc[up], "o", mfc="white", mec=OBS, mew=1.5, ms=5, zorder=4)
ax.set_yscale("log")
ax.set_ylim(0.5, 60)
ax.set_xticks(ticks, tlabs)
ax.set_ylabel("|H| / ρc$_p$|ΔT|   (mm s$^{-1}$)", color=INK, fontsize=9)
ax.set_xlabel("17 July 2025, UT", color=INK2, fontsize=9)
ax.set_title("(b) exchange conductance: collapse vs 12× floor", color=INK, fontsize=10, loc="left")
ax.text(2.3, 42, "model", color=MOD, fontsize=9)
ax.text(1.1, 4.3, "observed", color=OBS, fontsize=9)
ax.annotate("lull → collapse", xy=(lull, 0.85), xytext=(lull + 0.7, 0.62),
            color=INK2, fontsize=8, arrowprops=dict(arrowstyle="-", color=INK2, lw=0.8))

# (c) Ri trajectory, stable hours only
night = times >= pd.Timestamp("2025-07-17 19:00")
bx.axvspan(0.2, 2.0, color="#f0f0f0", zorder=0)
bx.text(0.6, 45, "region a stable-tail\ncutoff would govern", color=INK2, fontsize=8, ha="center")
bx.plot(mod.ri[night], mod.chu[night], "-o", color=MOD, lw=1.5, ms=5, zorder=3)
bx.plot(obs.ri[night], obs.chu[night], "-o", color=OBS, lw=1.5, ms=5, zorder=3)
bx.set_xscale("log"); bx.set_yscale("log")
bx.set_xlim(0.015, 2.0); bx.set_ylim(0.5, 80)
bx.set_xlabel("bulk Richardson number", color=INK2, fontsize=9)
bx.set_title("(c) trajectory 19–22 UT: pinned at low Ri", color=INK, fontsize=10, loc="left")
bx.text(0.021, 5.5, "model", color=MOD, fontsize=9)
bx.text(0.32, 5.0, "observed", color=OBS, fontsize=9)
o19 = obs[night].iloc[0]; o2030 = obs.loc["2025-07-17 20:30"]
bx.text(o19.ri, o19.chu * 0.68, "19:00", color=INK2, fontsize=7.5, ha="center")
bx.text(o2030.ri, o2030.chu * 0.68, "20:30", color=INK2, fontsize=7.5, ha="center")

fig.suptitle("The evening-transition failure at Kolsass — 17 July 2025, 14–22 UT",
             color=INK, fontsize=11, x=0.055, ha="left")
fig.text(0.055, 0.030,
         "observed: H = eddy covariance (i-Box vf0 sonic, 4 m, 30-min, QC-filtered) · skin T from CNR4 lw$_{out}$ (ε = 0.97) · air T 2 m · wind: sonic L4 "
         "(height differs from 10 m — the daytime wind gap is partly profile shape) · conductance masked where |ΔT| < 0.25 K.",
         color=INK2, fontsize=7.2, ha="left")
fig.text(0.055, 0.008,
         "model: X10-lineage Kolsass cell — 30-min frames 14:00–18:30, instrumented evening run 5-min stream from 19:00 "
         "(HFX, TSK, T2, 10-m wind).   the conductance curves share no inputs; r(log |ChU|, 19–22 UT) = 0.82.",
         color=INK2, fontsize=7.2, ha="left")
for ext in ("png", "pdf"):
    fig.savefig(f"{D}/plot_output/diagnostics/exchange_collapse_20250717.{ext}")
print("written")
