#!/usr/bin/env python
"""HRLDAS setup file = copy of a WRF wrfinput with the initial land state replaced by ICON's state at the
spin-up start hour, taken from the icon2wrf surface-forcing series (TSOIL 9 depths -> TSLB 4 layers by
depth interpolation at the layer centres; WSOIL 8 layers [kg m-2] -> SMOIS volumetric by thickness-weighted
overlap; TSK = TG; SNOWH from the forcing; SNOWC 0/1 from SNOWH; CANWAT 0). Everything static (land use, soil type,
VEGFRA, SHDMAX/MIN, LAI, TMN, terrain) stays as in the wrfinput.
Snow water equivalent: if the series carries the ICON initial state of its first hour (`SNEQV_init` [kg m-2], written by
icon2wrf --init-state; valid only when <YYYYMMDDHH> is that first hour) SNOW = SNEQV_init, i.e. ICON's own W_SNOW with its
per-cell density RHO_SNOW; otherwise SNOW = SNOWH * 350 kg m-3 (the pre-2026-09-17 assumption). Soil ice: with
`WSOIL_ICE_init` [kg m-2 per ICON layer] present, SH2O = SMOIS - ice (mapped like WSOIL, clipped to [0, SMOIS]); otherwise
SH2O = SMOIS (Noah-MP's frozen-soil option 1 re-derives the liquid fraction from TSLB anyway).
Usage: python make_setup.py <wrfinput_d01> <forcing.nc> <YYYYMMDDHH> <out_setup_file>"""
import sys, shutil
import numpy as np, xarray as xr, netCDF4 as nc

wrfinput, forcing, stamp, out = sys.argv[1:5]
t0 = np.datetime64(f"{stamp[:4]}-{stamp[4:6]}-{stamp[6:8]}T{stamp[8:10]}")
shutil.copyfile(wrfinput, out)
f = xr.open_dataset(forcing).sel(time=t0)
d = nc.Dataset(out, "a")
zs = np.asarray(d["ZS"][0]); dzs = np.asarray(d["DZS"][0])          # WRF layer centres 0.05 0.25 0.70 1.50, thickness
# --- soil temperature: interpolate ICON depths to the WRF layer centres
zi = f.soil_depth.values; ts = f.TSOIL.values                           # (9, y, x), zi[0] = 0 (skin-like level)
tslb = np.empty((4,) + ts.shape[1:], "f4")
for k, z in enumerate(zs):
    j = np.searchsorted(zi, z); j = min(max(j, 1), len(zi) - 1)
    w = (z - zi[j - 1]) / (zi[j] - zi[j - 1]); tslb[k] = (1 - w) * ts[j - 1] + w * ts[j]
# --- soil moisture: ICON layer water (kg m-2 = mm) over layers with bottoms zb (tops = previous bottom)
zb = f.soil_layer_bottom.values; zt = np.concatenate([[0.0], zb[:-1]]); ws = f.WSOIL.values  # (8, y, x)
smois = np.zeros((4,) + ws.shape[1:], "f4"); top = 0.0
for k, dz in enumerate(dzs):
    bot = top + dz; acc = np.zeros(ws.shape[1:], "f4")
    for l in range(len(zb)):
        ov = max(0.0, min(bot, zb[l]) - max(top, zt[l]))
        if ov > 0: acc += ws[l] * (ov / (zb[l] - zt[l]))
    smois[k] = acc / (dz * 1000.0); top = bot                              # mm of water / (m * 1000 mm/m) -> m3 m-3
land = np.asarray(d["XLAND"][0]) < 1.5
smois = np.clip(smois, 0.02, 0.6)
# --- soil ice from the series' initial state (same layer mapping as WSOIL), if present and valid for this hour
init_ok = "SNEQV_init" in f and str(np.datetime64(str(xr.open_dataset(forcing).time.values[0])[:13])) == str(t0)
sh2o = smois.copy()
if init_ok and "WSOIL_ICE_init" in f:
    wi = f.WSOIL_ICE_init.values; ice = np.zeros_like(smois); top = 0.0
    for k, dz in enumerate(dzs):
        bot = top + dz
        for l in range(len(zb)):
            ov = max(0.0, min(bot, zb[l]) - max(top, zt[l]))
            if ov > 0: ice[k] += wi[l] * (ov / (zb[l] - zt[l]))
        ice[k] /= dz * 1000.0; top = bot
    sh2o = np.clip(smois - np.nan_to_num(ice), 0.0, smois)
def put(name, new2d):            # full-slice write, land cells only (a masked assignment on a netCDF slice never reaches the file)
    cur = np.asarray(d[name][0]); cur[land] = new2d[land]; d[name][0, :, :] = cur
for k in range(4):
    cur = np.asarray(d["TSLB"][0, k]); cur[land] = tslb[k][land]; d["TSLB"][0, k, :, :] = cur
    cur = np.asarray(d["SMOIS"][0, k]); cur[land] = smois[k][land]; d["SMOIS"][0, k, :, :] = cur
    cur = np.asarray(d["SH2O"][0, k]); cur[land] = sh2o[k][land]; d["SH2O"][0, k, :, :] = cur
put("TSK", f.TG.values.astype("f4"))
snowh = np.maximum(f.SNOWH.values, 0.0).astype("f4"); put("SNOWH", snowh)
if init_ok:
    sneqv = np.maximum(np.nan_to_num(f.SNEQV_init.values), 0.0).astype("f4"); put("SNOW", sneqv); snow_note = "SNOW = SNEQV_init (ICON W_SNOW, per-cell density)"
else:
    sneqv = snowh * 350.0; put("SNOW", sneqv); snow_note = "SNOW = SNOWH * 350 kg m-3 (no valid SNEQV_init for this hour)"
put("SNOWC", (snowh > 0.01).astype("f4")); put("CANWAT", np.zeros_like(snowh))
d.setncattr("HRLDAS_SETUP_NOTE", f"land state from ICON forcing {forcing.split('/')[-1]} at {stamp}; {snow_note}; SH2O = SMOIS - WSOIL_ICE_init: {init_ok and 'WSOIL_ICE_init' in f}; static fields from {wrfinput.split('/')[-1]}")
d.close()
j, i = 259, 285
print(f"wrote {out}: {snow_note}; Kolsass TSLB {np.round(tslb[:, j, i] - 273.15, 1)} C, SMOIS {np.round(smois[:, j, i], 3)}, SH2O {np.round(sh2o[:, j, i], 3)}, TSK {f.TG.values[j, i] - 273.15:.1f} C, SNOWH {snowh[j, i]:.2f} m")
j, i = 278, 295
print(f"  StanserJoch TSLB {np.round(tslb[:, j, i] - 273.15, 1)} C, SMOIS {np.round(smois[:, j, i], 3)}, SH2O {np.round(sh2o[:, j, i], 3)}, SNOWH {snowh[j, i]:.3f} m, SNOW {sneqv[j, i]:.1f} kg m-2; domain SNOWH>1cm land cells: {(snowh > 0.01)[land].sum()}, SNOW land total {sneqv[land].sum() / 1e9:.3f} Gt-equivalent(kg m-2 * cells)")
