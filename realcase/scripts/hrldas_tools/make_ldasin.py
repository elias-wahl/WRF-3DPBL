#!/usr/bin/env python
"""Split the icon2wrf surface-forcing series (one NetCDF, hourly, WRF mass grid) into HRLDAS LDASIN files:
<OUTDIR>/<YYYYMMDDHH>.LDASIN_DOMAIN1 with T2D Q2D U2D V2D PSFC RAINRATE SWDOWN LWDOWN (Time, south_north, west_east),
global attributes TITLE (with a vYYYYMMDD tag, which HRLDAS parses) and MMINLU.
Usage: python make_ldasin.py <forcing.nc> <outdir> [start YYYYMMDDHH] [end YYYYMMDDHH]"""
import sys, os
from pathlib import Path
import numpy as np, xarray as xr, netCDF4 as nc

src, outdir = sys.argv[1], Path(sys.argv[2]); outdir.mkdir(parents=True, exist_ok=True)
t0 = np.datetime64(f"{sys.argv[3][:4]}-{sys.argv[3][4:6]}-{sys.argv[3][6:8]}T{sys.argv[3][8:10]}") if len(sys.argv) > 3 else None
t1 = np.datetime64(f"{sys.argv[4][:4]}-{sys.argv[4][4:6]}-{sys.argv[4][6:8]}T{sys.argv[4][8:10]}") if len(sys.argv) > 4 else None
VARS = [("T2D", "K"), ("Q2D", "kg kg-1"), ("U2D", "m s-1"), ("V2D", "m s-1"), ("PSFC", "Pa"), ("RAINRATE", "mm s-1"), ("SWDOWN", "W m-2"), ("LWDOWN", "W m-2")]
ds = xr.open_dataset(src)
times = (ds.time.values + np.timedelta64(30, "m")).astype("datetime64[h]")   # round to the hour: a 'days since' axis decodes with us-level jitter (23:00:00.000013 / 22:59:59.99999) that would mislabel a file
sel = np.ones(len(times), bool)
if t0 is not None: sel &= times >= t0
if t1 is not None: sel &= times <= t1
n = 0
for it in np.where(sel)[0]:
    t = times[it]; stamp = str(t)[:13].replace("-", "").replace("T", "")   # times are datetime64[h] -> 'YYYY-MM-DDTHH'
    fn = outdir / f"{stamp}.LDASIN_DOMAIN1"
    if fn.exists(): continue
    with nc.Dataset(fn, "w", format="NETCDF4") as o:
        ny, nx = ds.T2D.shape[1:]
        o.createDimension("Time", 1); o.createDimension("south_north", ny); o.createDimension("west_east", nx)
        for v, u in VARS:
            a = ds[v].isel(time=it).values.astype("f4")
            if v == "RAINRATE": a = np.maximum(a, 0.0)
            var = o.createVariable(v, "f4", ("Time", "south_north", "west_east"), zlib=True, complevel=2)
            var[0] = a; var.units = u; var.description = str(ds[v].attrs.get("long_name", v))
        o.TITLE = "v20260916 ICON 500 m (TEAMx sEOP) surface forcing on the WRF mass grid, HRLDAS LDASIN"
        o.MMINLU = "USGS"; o.source_file = os.path.basename(src); o.valid_time = str(t)[:16]
    n += 1
print(f"wrote {n} LDASIN files to {outdir} ({int(sel.sum())} hours selected)")
