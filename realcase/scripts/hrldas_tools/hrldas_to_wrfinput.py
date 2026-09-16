#!/usr/bin/env python
"""Write a spun-up HRLDAS land state into a copy of a WRF wrfinput (the WRF twin's initial file).
From RESTART.<YYYYMMDDHH>_DOMAIN1: SOIL_T -> TSLB, SMC -> SMOIS, SH2O -> SH2O, TG -> TSK, SNEQV -> SNOW [mm], SNOWH -> SNOWH [m],
CANLIQ+CANICE -> CANWAT, LAI -> LAI (land cells only; water cells untouched). Everything else stays as in the wrfinput.
Usage: python hrldas_to_wrfinput.py <wrfinput_d01> <RESTART file> <out_wrfinput>"""
import sys, shutil
import numpy as np, netCDF4 as nc
src, rst, out = sys.argv[1:4]
shutil.copyfile(src, out)
r = nc.Dataset(rst); d = nc.Dataset(out, "a")
land = np.asarray(d["XLAND"][0]) < 1.5
def put2(name, arr):
    cur = np.asarray(d[name][0]); cur[land] = arr[land]; d[name][0, :, :] = cur
for k in range(4):
    for wv, hv in (("TSLB", "SOIL_T"), ("SMOIS", "SMC"), ("SH2O", "SH2O")):
        cur = np.asarray(d[wv][0, k]); new = np.asarray(r[hv][0, :, k, :]); cur[land] = new[land]; d[wv][0, k, :, :] = cur
put2("TSK", np.asarray(r["TG"][0])); put2("SNOW", np.asarray(r["SNEQV"][0])); put2("SNOWH", np.asarray(r["SNOWH"][0]))
put2("SNOWC", (np.asarray(r["SNOWH"][0]) > 0.01).astype("f4")); put2("CANWAT", np.asarray(r["CANLIQ"][0]) + np.asarray(r["CANICE"][0]))
if "LAI" in d.variables: put2("LAI", np.asarray(r["LAI"][0]))
d.setncattr("LAND_STATE_FROM_HRLDAS", f"{rst.split('/')[-1]} (soil T/M, liquid water, TG->TSK, snow, canopy water, LAI); static fields from {src.split('/')[-1]}")
j, i = 259, 285
print(f"wrote {out}: Kolsass TSLB {np.round(np.asarray(d['TSLB'][0, :, j, i]) - 273.15, 2)} C, SMOIS {np.round(np.asarray(d['SMOIS'][0, :, j, i]), 3)}, TSK {float(d['TSK'][0, j, i]) - 273.15:.2f} C")
d.close(); r.close()
