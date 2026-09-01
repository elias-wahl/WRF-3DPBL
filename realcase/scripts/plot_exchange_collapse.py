#!/usr/bin/env python
"""Figure: the surface exchange-conductance collapse at Kolsass, evening 2025-07-17
(DECISIONS 2026-09-02 ~00:45). Two panels: (a) effective exchange conductance
|ChU| = |H| / (rho cp |dT_skin-air|) vs time; (b) the trajectory in (bulk Ri, |ChU|)
space -- the observed surface walks into the high-Ri collapsed branch while the model
stays pinned at low Ri, outside the region any stable-tail cutoff governs.
Data = the measured half-hour table (obs: EC flux, lw_out skin, tower air/wind;
model: EVE1 Kolsass cell, 5-min stream). Output: plot_output/diagnostics/.
"""
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OBS, MOD = "#2a78d6", "#eb6834"
INK, INK2, GRID = "#333333", "#666666", "#e6e6e6"

t = ["19:00", "19:30", "20:00", "20:30", "21:00", "21:30", "22:00"]
x = np.arange(len(t))
obs_chu = np.array([1.7, 7.6, 3.4, 0.8, 1.3, 2.9, 2.2])   # mm/s; 21:30 = upward flux
obs_ri = np.array([0.16, 0.14, 0.10, 0.57, 0.56, 0.52, 0.87])
mod_chu = np.array([8.9, 27.7, 30.9, 9.8, 10.3, 24.2, 10.9])
mod_ri = np.array([0.08, 0.03, 0.02, 0.07, 0.06, 0.03, 0.06])

fig, (ax, bx) = plt.subplots(1, 2, figsize=(10.5, 4.3), dpi=200)
fig.subplots_adjust(left=0.075, right=0.985, top=0.86, bottom=0.18, wspace=0.28)

for a in (ax, bx):
    a.set_facecolor("white")
    a.grid(True, color=GRID, linewidth=0.7, zorder=0)
    for s in a.spines.values():
        s.set_color(GRID)
    a.tick_params(colors=INK2, labelsize=9)

# ---- panel a: time series -------------------------------------------------
ax.axvspan(2.85, 3.15, color="#f0f0f0", zorder=0)
ax.plot(x, mod_chu, "-o", color=MOD, lw=2, ms=6, zorder=3)
ax.plot(x, obs_chu, "-o", color=OBS, lw=2, ms=6, zorder=3)
ax.plot(x[5], obs_chu[5], "o", mfc="white", mec=OBS, mew=1.6, ms=6, zorder=4)
ax.set_yscale("log")
ax.set_ylim(0.5, 50)
ax.set_xticks(x, t)
ax.set_ylabel("effective exchange conductance  |H| / ρc$_p$|ΔT|   (mm s$^{-1}$)", color=INK, fontsize=9)
ax.set_title("(a) the observed surface lets go — the model never does", color=INK, fontsize=10, loc="left")
ax.text(2.0, 33, "model (EVE1 cell)", color=MOD, fontsize=9, ha="center")
ax.text(1.35, 10.6, "observed\n(Kolsass tower)", color=OBS, fontsize=9, ha="center")
ax.annotate("lull → collapse", xy=(3, 0.85), xytext=(3.7, 0.62),
            color=INK2, fontsize=8.5, arrowprops=dict(arrowstyle="-", color=INK2, lw=0.8))
ax.annotate("the model's lull attempt:\nsame clock, bottoms 12× too high", xy=(3, 9.8), xytext=(3.55, 4.6),
            color=INK2, fontsize=8, arrowprops=dict(arrowstyle="-", color=INK2, lw=0.8))
ax.annotate("flux briefly upward", xy=(5, 2.9), xytext=(4.55, 1.15),
            color=INK2, fontsize=8, arrowprops=dict(arrowstyle="-", color=INK2, lw=0.8))
ax.set_xlabel("17 July 2025, UT", color=INK2, fontsize=9)

# ---- panel b: trajectory in (Ri, ChU) space --------------------------------
bx.axvspan(0.2, 2.0, color="#f0f0f0", zorder=0)
bx.text(0.62, 38, "region a stable-tail\ncutoff would govern", color=INK2, fontsize=8.5, ha="center")
bx.plot(mod_ri, mod_chu, "-o", color=MOD, lw=1.6, ms=6, zorder=3)
bx.plot(obs_ri, obs_chu, "-o", color=OBS, lw=1.6, ms=6, zorder=3)
bx.plot(obs_ri[5], obs_chu[5], "o", mfc="white", mec=OBS, mew=1.6, ms=6, zorder=4)
bx.set_xscale("log"); bx.set_yscale("log")
bx.set_xlim(0.015, 2.0); bx.set_ylim(0.5, 50)
bx.set_xlabel("bulk Richardson number", color=INK2, fontsize=9)
bx.set_title("(b) trajectory 19–22 UT: the model stays pinned at low Ri", color=INK, fontsize=10, loc="left")
bx.text(0.021, 6.5, "model", color=MOD, fontsize=9)
bx.text(0.30, 4.6, "observed", color=OBS, fontsize=9)
for ri, chu, lab, dx, dy in [(obs_ri[0], obs_chu[0], "19:00", 1.0, 0.70),
                             (obs_ri[3], obs_chu[3], "20:30", 0.98, 0.72),
                             (obs_ri[6], obs_chu[6], "22:00", 1.0, 1.35),
                             (mod_ri[2], mod_chu[2], "20:00", 1.0, 1.3)]:
    bx.text(ri * dx, chu * dy, lab, color=INK2, fontsize=7.5, ha="center")

fig.suptitle("Surface exchange collapse at Kolsass — evening transition, 17 July 2025",
             color=INK, fontsize=11, x=0.075, ha="left")
fig.text(0.075, 0.030,
         "observed: H = eddy covariance (i-Box vf0 sonic, 4 m, 30-min, QC-filtered) · skin T from CNR4 lw$_{out}$ (ε = 0.97) · "
         "air T 2 m (tower) · wind: 2-D sonic level 2.",
         color=INK2, fontsize=7.2, ha="left")
fig.text(0.075, 0.008,
         "model: 3D-closure evening run, 5-min surface stream (HFX, TSK, T2, 10-m wind) at the Kolsass cell.   "
         "the two curves share no inputs; r(log |ChU|) = 0.82 over the seven half-hours.",
         color=INK2, fontsize=7.2, ha="left")
import os
os.makedirs("/gpfs/data/fs72996/ewahl/plot_output/diagnostics", exist_ok=True)
for ext in ("png", "pdf"):
    fig.savefig(f"/gpfs/data/fs72996/ewahl/plot_output/diagnostics/exchange_collapse_20250717.{ext}")
print("written: plot_output/diagnostics/exchange_collapse_20250717.png/.pdf")
