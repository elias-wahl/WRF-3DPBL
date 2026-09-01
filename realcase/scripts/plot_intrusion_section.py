#!/usr/bin/env python
"""Figure: N-S vertical cross-section through Kolsass of the northerly intrusion
(DECISIONS 2026-09-02 ~02:15). Shading = meridional wind v (diverging, blue = from
the north / southward = the intrusion), contours = potential temperature, terrain
filled. Two times: 17:30 UT (X10a frame, intrusion arriving down the Karwendel wall)
and 20:30 UT (instrumented evening run, the observed-lull hour). Section: fixed
model column of Kolsass, 5 km south to 15 km north.
"""
import glob

import numpy as np
import netCDF4 as nc
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm

D = "/gpfs/data/fs72996/ewahl"
INK, INK2, GRID = "#333333", "#666666", "#e6e6e6"
CMAP = LinearSegmentedColormap.from_list("div", ["#2a78d6", "#f0efec", "#c0392b"])
LAT, LON = 47.305341, 11.62219
KMAX = 45


def section(path):
    ds = nc.Dataset(path)
    xlat, xlon = np.asarray(ds["XLAT"][0]), np.asarray(ds["XLONG"][0])
    j0, i0 = np.unravel_index(np.argmin((xlat - LAT) ** 2 + (xlon - LON) ** 2), xlat.shape)
    js = slice(j0 - 10, j0 + 31)
    v = 0.5 * (np.asarray(ds["V"][0, :KMAX, js, i0]) + np.asarray(ds["V"][0, :KMAX, j0 - 9:j0 + 32, i0]))
    th = np.asarray(ds["T"][0, :KMAX, js, i0]) + 300.0
    ph = (np.asarray(ds["PH"][0, :KMAX + 1, js, i0]) + np.asarray(ds["PHB"][0, :KMAX + 1, js, i0])) / 9.81
    z = 0.5 * (ph[:-1] + ph[1:])
    hgt = np.asarray(ds["HGT"][0, js, i0])
    ds.close()
    y = (np.arange(j0 - 10, j0 + 31) - j0) * 0.5
    return y, z, v, th, hgt


fig, axes = plt.subplots(1, 2, figsize=(12.5, 4.6), dpi=200, sharey=True)
fig.subplots_adjust(left=0.06, right=0.93, top=0.86, bottom=0.14, wspace=0.10)

files = [("17:30 UT — the intrusion attaches to the wall",
          glob.glob(f"{D}/exp/X10a/wrf_output/*/wrfout_d01_2025-07-17_17:30:00.nc")[0]),
         ("20:30 UT — the observed-lull hour: still running",
          glob.glob(f"{D}/exp/EVE1/wrf_output/*/wrfout_d01_2025-07-17_20:30:00.nc")[0])]
norm = TwoSlopeNorm(vmin=-8, vcenter=0, vmax=8)
for ax, (title, f) in zip(axes, files):
    y, z, v, th, hgt = section(f)
    yy = np.broadcast_to(y[None, :], z.shape)
    pm = ax.pcolormesh(yy, z, v, cmap=CMAP, norm=norm, shading="gouraud", rasterized=True)
    cs = ax.contour(yy, z, th, levels=np.arange(290, 330, 1), colors=INK2, linewidths=0.6)
    ax.clabel(cs, levels=np.arange(290, 330, 4), fontsize=7, colors=INK2, fmt="%d")
    ax.fill_between(y, 0, hgt, color="#4a4a48", zorder=5)
    ax.axvline(0, color=INK2, lw=0.8, ls=":", zorder=6)
    ax.text(0.2, 300, "Kolsass", color="white", fontsize=8, zorder=7)
    ax.set_ylim(400, 3200)
    ax.set_xlabel("distance from Kolsass (km, → north)", color=INK2, fontsize=9)
    ax.set_title(title, color=INK, fontsize=10, loc="left")
    ax.tick_params(colors=INK2, labelsize=8.5)
    for s in ax.spines.values():
        s.set_color(GRID)
axes[0].set_ylabel("height ASL (m)", color=INK, fontsize=9)
cb = fig.colorbar(pm, ax=axes, fraction=0.025, pad=0.015)
cb.set_label("meridional wind v (m s$^{-1}$)  —  blue: from the north (the intrusion)", color=INK, fontsize=8.5)
cb.ax.tick_params(colors=INK2, labelsize=8)
fig.suptitle("The Karwendel northerly reaching the valley floor — N–S section through Kolsass, 17 July 2025",
             color=INK, fontsize=11, x=0.06, ha="left")
fig.text(0.06, 0.015, "model: X10-lineage frames; θ contours every 1 K (labels every 4 K); terrain filled. "
         "Crest northerly verified at Arbeser (obs 4–7 m s$^{-1}$); the observed Stanser-Joch slope is sheltered (2 m s$^{-1}$) — the modeled wall attachment is the error.",
         color=INK2, fontsize=7.2, ha="left")
for ext in ("png", "pdf"):
    fig.savefig(f"{D}/plot_output/diagnostics/intrusion_section_20250717.{ext}")
print("written")
