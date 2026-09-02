#!/usr/bin/env python
"""Figures: the 17-July spin-up and night entry at Kolsass with the new dlid86 VAD
(DECISIONS 2026-09-02 ~15:30 and the IC finding).

Fig 1 (kolsass17_timeheight): (a) lidar wind speed time-height 12-24 UT, 0-800 m
(CNR > -27, 30-min bins); (b) model same axes (ICON IC at 13:00, X10a 13:30-19:00,
instrumented evening run 19:30-00:00); (c) the 50-150 m band curves — the story:
the IC carries ~40 % of the observed circulation (the 584-1522 m pressure-level gap
wipes the valley-wind jet, A19's momentum twin), WRF spins one up all afternoon,
peaks late at 17 UT, dies early, and is re-stirred through the observed calm.

Fig 2 (kolsass17_profiles): profiles at 13 UT (IC vs obs), 17 UT (model peak), 21 UT
(observed calm vs re-stirred model).
"""
import glob

import numpy as np
import pandas as pd
import netCDF4 as nc
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = "/gpfs/data/fs72996/ewahl"
NEW = f"{D}/data/lidar/new"
OBS, MOD, INK, INK2, GRID = "#2a78d6", "#eb6834", "#333333", "#666666", "#e6e6e6"
ZG = np.arange(20, 801, 20.0)
HRS = np.arange(12.25, 24.0, 0.5)          # bin midpoints for the lidar; model on the half hours

# ---------------- lidar ----------------
ds = nc.Dataset(f"{NEW}/dlid86/teamx_dlr_dlid86_l2_00_20250717000000.nc")
lt = pd.to_datetime(np.asarray(ds["time"][:]), unit="s")
lZ = np.asarray(ds["Z"][:])
lw = np.ma.filled(ds["WSPD"][:], np.nan)
ld = np.ma.filled(ds["WDIR"][:], np.nan)
cnr = np.ma.filled(ds["CNR"][:], np.nan)
lw[~(cnr > -27)] = np.nan
ds.close()
lh = np.array([(x - pd.Timestamp("2025-07-17")).total_seconds() / 3600 for x in lt])
zm = lZ <= 820
OBS_TH2D = np.full((len(HRS), zm.sum()), np.nan)
for k, h in enumerate(HRS):
    sel = np.abs(lh - h) <= 0.25
    if sel.sum():
        OBS_TH2D[k] = np.nanmean(lw[np.ix_(sel, zm)], axis=0)
obs_band = np.array([np.nanmean(OBS_TH2D[k][(lZ[zm] >= 50) & (lZ[zm] < 150)]) for k in range(len(HRS))])

# ---------------- model ----------------
def col(path):
    d_ = nc.Dataset(path)
    xlat, xlon = np.asarray(d_["XLAT"][0]), np.asarray(d_["XLONG"][0])
    j, i = np.unravel_index(np.argmin((xlat - 47.30523) ** 2 + (xlon - 11.62226) ** 2), xlat.shape)
    u = 0.5 * (np.asarray(d_["U"][0, :24, j, i]) + np.asarray(d_["U"][0, :24, j, i + 1]))
    v = 0.5 * (np.asarray(d_["V"][0, :24, j, i]) + np.asarray(d_["V"][0, :24, j + 1, i]))
    ph = (np.asarray(d_["PH"][0, :25, j, i]) + np.asarray(d_["PHB"][0, :25, j, i])) / 9.81
    z = 0.5 * (ph[:-1] + ph[1:]) - float(d_["HGT"][0, j, i])
    d_.close()
    return z, np.hypot(u, v)

mh, MOD_TH2D = [], []
ic_z, ic_s = col(f"{D}/branko_runs/innval_pbl3d_X10bdy/wrfinput_d01")
for h in np.arange(13.0, 24.01, 0.5):
    hh = f"{int(h):02d}:{'30' if h % 1 else '00'}"
    day = "17" if h < 24 else "18"
    if h == 13.0:
        z, s = ic_z, ic_s
    else:
        f = glob.glob(f"{D}/exp/X10a/wrf_output/*/wrfout_d01_2025-07-17_{hh}:00.nc") \
          + glob.glob(f"{D}/exp/EVE1/wrf_output/*/wrfout_d01_2025-07-17_{hh}:00.nc")
        if not f:
            continue
        z, s = col(f[0])
    mh.append(h)
    MOD_TH2D.append(np.interp(ZG, z, s))
mh = np.array(mh)
MOD_TH2D = np.array(MOD_TH2D)
mod_band = np.array([MOD_TH2D[k][(ZG >= 50) & (ZG < 150)].mean() for k in range(len(mh))])

# ---------------- figure 1 ----------------
fig = plt.figure(figsize=(13.6, 4.6), dpi=200)
gs = fig.add_gridspec(1, 3, left=0.05, right=0.965, top=0.855, bottom=0.15, wspace=0.24,
                      width_ratios=[1, 1, 1.15])
axA, axB, axC = [fig.add_subplot(gs[0, k]) for k in range(3)]
vmax = 9.0
pm = axA.pcolormesh(HRS, lZ[zm], OBS_TH2D.T, cmap="Blues", vmin=0, vmax=vmax, shading="nearest")
axA.set_title("(a) observed — dlid86 VAD", color=INK, fontsize=10, loc="left")
axB.pcolormesh(mh, ZG, MOD_TH2D.T, cmap="Blues", vmin=0, vmax=vmax, shading="nearest")
axB.set_title("(b) model — from the 13:00 ICON start", color=INK, fontsize=10, loc="left")
for ax in (axA, axB):
    ax.set_xlim(12, 24)
    ax.set_ylim(0, 800)
    ax.axvline(18.55, color="#888", lw=1, ls=":")
    ax.set_xticks([12, 15, 18, 21, 24])
    ax.set_xlabel("17 July 2025, UT", color=INK2, fontsize=9)
    ax.tick_params(colors=INK2, labelsize=8.5)
axA.set_ylabel("height AGL (m)", color=INK, fontsize=9)
axA.text(18.7, 740, "sunset", color="#666", fontsize=7.5)
cb = fig.colorbar(pm, ax=axB, fraction=0.05, pad=0.02)
cb.set_label("wind speed (m s$^{-1}$)", color=INK, fontsize=8.5)
cb.ax.tick_params(colors=INK2, labelsize=8)

axC.set_facecolor("white")
axC.grid(True, color=GRID, lw=0.7)
for sp in axC.spines.values():
    sp.set_color(GRID)
axC.plot(HRS, obs_band, "-o", color=OBS, lw=2, ms=4)
axC.plot(mh, mod_band, "-o", color=MOD, lw=2, ms=4)
axC.plot([13.0], [ic_s[(ic_z >= 50) & (ic_z < 150)].mean()], "D", color=INK, ms=7, zorder=5)
axC.set_xlim(12, 24)
axC.set_ylim(0, 9.5)
axC.set_xticks([12, 15, 18, 21, 24])
axC.axvline(18.55, color="#888", lw=1, ls=":")
axC.set_xlabel("17 July 2025, UT", color=INK2, fontsize=9)
axC.set_ylabel("wind speed 50–150 m  (m s$^{-1}$)", color=INK, fontsize=9)
axC.set_title("(c) the story in one band", color=INK, fontsize=10, loc="left")
axC.tick_params(colors=INK2, labelsize=8.5)
axC.text(13.15, 1.5, "ICON IC:\n40 % of obs", color=INK, fontsize=8)
axC.annotate("spin-up", xy=(15.2, 3.9), color=MOD, fontsize=8.5)
axC.annotate("late peak", xy=(16.6, 6.6), color=MOD, fontsize=8.5)
axC.annotate("dies early", xy=(18.55, 0.85), xytext=(17.15, 1.55), color=MOD, fontsize=8.5,
             arrowprops=dict(arrowstyle="-", color=MOD, lw=0.7))
axC.annotate("re-stirred", xy=(20.6, 2.7), color=MOD, fontsize=8.5)
axC.annotate("observed calm", xy=(21.5, 0.2), xytext=(21.6, 3.1), color=OBS, fontsize=8.5,
             arrowprops=dict(arrowstyle="-", color=OBS, lw=0.7))
axC.text(12.2, 8.9, "observed", color=OBS, fontsize=9)
axC.text(14.6, 5.3, "model", color=MOD, fontsize=9)
fig.suptitle("Kolsass, 17 July 2025 — the valley wind the forcing never delivered",
             color=INK, fontsize=11.5, x=0.05, ha="left")
fig.text(0.05, 0.015, "lidar: DLR dlid86 75° VAD at Kolsass (metadata coordinates; CNR > −27 dB), 30-min bins · model: X10 lineage "
         "column, ICON wrfinput at 13:00 (◆) then 30-min frames · the 584–1522 m ASL pressure-level gap of the forcing sits across the valley-jet layer.",
         color=INK2, fontsize=7.2, ha="left")
for ext in ("png", "pdf"):
    fig.savefig(f"{D}/plot_output/diagnostics/kolsass17_timeheight.{ext}")

# ---------------- figure 2: profiles ----------------
fig2, axs = plt.subplots(1, 3, figsize=(10.5, 4.2), dpi=200, sharey=True)
fig2.subplots_adjust(left=0.07, right=0.985, top=0.84, bottom=0.15, wspace=0.12)
times = [("13:00 — the handover state", 13.0), ("17:00 — model peak, obs declining", 17.0),
         ("21:00 — the collapse hour", 21.0)]
for ax, (title, h) in zip(axs, times):
    ax.set_facecolor("white")
    ax.grid(True, color=GRID, lw=0.7)
    for sp in ax.spines.values():
        sp.set_color(GRID)
    k = np.argmin(np.abs(HRS - h))
    ax.plot(OBS_TH2D[k], lZ[zm], "-o", color=OBS, lw=2, ms=3.5)
    km = np.argmin(np.abs(mh - h))
    ax.plot(MOD_TH2D[km], ZG, "-", color=MOD, lw=2)
    if h == 13.0:
        ax.plot(np.interp(ZG, ic_z, ic_s), ZG, "--", color=INK, lw=1.6)
        ax.text(2.6, 640, "ICON IC\n(= model 13:00)", color=INK, fontsize=8)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 800)
    ax.set_title(title, color=INK, fontsize=9.5, loc="left")
    ax.set_xlabel("wind speed (m s$^{-1}$)", color=INK2, fontsize=9)
    ax.tick_params(colors=INK2, labelsize=8.5)
axs[0].set_ylabel("height AGL (m)", color=INK, fontsize=9)
axs[1].text(6.6, 240, "model", color=MOD, fontsize=9)
axs[1].text(7.4, 520, "observed", color=OBS, fontsize=9)
fig2.suptitle("Kolsass wind profiles — initial deficit, late catch-up, destroyed calm",
              color=INK, fontsize=11, x=0.07, ha="left")
for ext in ("png", "pdf"):
    fig2.savefig(f"{D}/plot_output/diagnostics/kolsass17_profiles.{ext}")
print("written: kolsass17_timeheight + kolsass17_profiles")
