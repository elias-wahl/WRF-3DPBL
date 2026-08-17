#!/usr/bin/env python3
"""Sanity-check wrfinput_d01 before spending core-hours on wrf.exe.

    python3 check_wrfinput.py wrfinput_d01

real.exe finishing is not the same as real.exe being right. This looks at the
handful of fields that go wrong quietly with ICON forcing and CORINE land use,
where the model still runs but the answer is not physics.

The one to read first is SMOIS. ICON's W_SO is a soil water MASS, kg m-2 per
layer; WRF's SMOIS is a volumetric fraction, m3 m-3. Nothing between ungrib and
real.exe converts between them, so if the Vtable passed W_SO straight through
you get SMOIS of order 1-100 instead of 0.02-0.6. The run proceeds, the soil is
saturated everywhere, the Bowen ratio collapses, and the daytime heating that is
supposed to erode the cold pool never happens. Fix it upstream (divide by layer
thickness x 1000) rather than clipping it here.
"""

import sys

try:
    from netCDF4 import Dataset

    def open_ds(p):
        return Dataset(p)

    def var(ds, n):
        return ds.variables[n][:] if n in ds.variables else None

    def gattr(ds, n, d=None):
        return getattr(ds, n, d)
except ImportError:
    try:
        import xarray as xr

        def open_ds(p):
            return xr.open_dataset(p)

        def var(ds, n):
            return ds[n].values if n in ds else None

        def gattr(ds, n, d=None):
            return ds.attrs.get(n, d)
    except ImportError:
        sys.exit("need python netCDF4 or xarray -- `conda install netcdf4` or load a "
                 "module that provides it")

import numpy as np

findings = []


def check(name, ok, detail, hint=""):
    findings.append(("ok  " if ok else "FAIL", name, detail, "" if ok else hint))


def info(name, detail):
    findings.append(("    ", name, detail, ""))


def rng(a):
    a = np.asarray(a)
    a = a[np.isfinite(a)]
    return (float(a.min()), float(a.max()), float(a.mean())) if a.size else (np.nan,) * 3


def main(path):
    ds = open_ds(path)

    # ---- soil ------------------------------------------------------------
    sm = var(ds, "SMOIS")
    if sm is not None:
        lo, hi, mean = rng(sm)
        check("SMOIS  [m3 m-3]", 0.0 <= lo and hi <= 1.0,
              "min %.3f  max %.3f  mean %.3f" % (lo, hi, mean),
              "values above 1 mean ICON's W_SO (kg m-2) reached SMOIS unconverted; "
              "divide by layer thickness x 1000 in the ungrib step")
        if 0.0 <= lo and hi <= 1.0 and hi < 0.05:
            check("SMOIS  spread", False, "max is only %.3f -- soil is bone dry" % hi,
                  "check that SOILM* actually made it through metgrid")

    st = var(ds, "TSLB")
    if st is not None:
        lo, hi, mean = rng(st)
        check("TSLB   [K]", 200.0 < lo and hi < 350.0,
              "min %.1f  max %.1f  mean %.1f" % (lo, hi, mean),
              "soil temperature outside 200-350 K -- SOILT* levels were probably "
              "mismatched between the Vtable and num_metgrid_soil_levels")

    for name, lim in (("TSK", (200.0, 350.0)), ("TMN", (200.0, 350.0))):
        v = var(ds, name)
        if v is not None:
            lo, hi, mean = rng(v)
            check("%-6s [K]" % name, lim[0] < lo and hi < lim[1],
                  "min %.1f  max %.1f  mean %.1f" % (lo, hi, mean))

    # ---- terrain ---------------------------------------------------------
    hgt = var(ds, "HGT")
    dx = float(gattr(ds, "DX", 0) or 0)
    if hgt is not None:
        h = np.asarray(hgt)[0] if np.asarray(hgt).ndim == 3 else np.asarray(hgt)
        lo, hi, mean = rng(h)
        info("HGT    [m]", "min %.0f  max %.0f  mean %.0f" % (lo, hi, mean))
        if dx > 0:
            dzdy, dzdx = np.gradient(h, dx, dx)
            slope = np.degrees(np.arctan(np.hypot(dzdx, dzdy)))
            info("terrain slope [deg]",
                 "max %.1f   99th pct %.1f   mean %.1f"
                 % (slope.max(), np.percentile(slope, 99), slope.mean()))
            check("terrain slope < 45 deg", slope.max() < 45.0,
                  "max %.1f deg" % slope.max(),
                  "beyond ~45 deg the terrain-following coordinate metric terms get "
                  "large enough that diff_6th_slopeopt tapering may not be enough")

    # ---- land use --------------------------------------------------------
    lu = var(ds, "LU_INDEX")
    if lu is not None:
        cats = np.unique(np.asarray(lu).astype(int))
        nlc = gattr(ds, "NUM_LAND_CAT")
        info("LU_INDEX", "%d distinct categories, %d..%d (NUM_LAND_CAT=%s, MMINLU=%s)"
             % (cats.size, cats.min(), cats.max(), nlc, gattr(ds, "MMINLU")))
        if nlc:
            check("LU_INDEX within NUM_LAND_CAT", int(cats.max()) <= int(nlc),
                  "max index %d vs NUM_LAND_CAT %s" % (cats.max(), nlc),
                  "num_land_cat in namelist.input must match the geogrid land-use "
                  "dataset, or the LSM will read the wrong table rows")

    # ---- vertical grid ---------------------------------------------------
    ph, phb = var(ds, "PH"), var(ds, "PHB")
    if ph is not None and phb is not None and hgt is not None:
        z = (np.asarray(ph)[0] + np.asarray(phb)[0]) / 9.81
        h = np.asarray(hgt)[0] if np.asarray(hgt).ndim == 3 else np.asarray(hgt)
        agl = z - h[None, :, :]
        zc = 0.5 * (agl[:-1] + agl[1:])
        info("first mass level AGL [m]",
             "min %.1f  max %.1f  mean %.1f" % rng(zc[0]))
        below1km = int((zc[:, zc.shape[1] // 2, zc.shape[2] // 2] < 1000).sum())
        info("levels below 1 km AGL", "%d (at the domain centre)" % below1km)
        check("model top above terrain", float(np.nanmin(agl[-1])) > 5000.0,
              "lowest model-top AGL height %.0f m" % float(np.nanmin(agl[-1])),
              "with damp_opt=3 and zdamp=8000 the damping layer must sit entirely "
              "above the highest terrain")

    # ---- atmosphere ------------------------------------------------------
    qv = var(ds, "QVAPOR")
    if qv is not None:
        lo, hi, mean = rng(qv)
        check("QVAPOR [kg kg-1]", lo >= -1e-9 and hi < 0.05,
              "min %.2e  max %.2e" % (lo, hi))
    for name in ("U", "V"):
        v = var(ds, name)
        if v is not None:
            lo, hi, _ = rng(v)
            check("%-6s [m s-1]" % name, max(abs(lo), abs(hi)) < 120.0,
                  "min %.1f  max %.1f" % (lo, hi))
    t = var(ds, "T")
    if t is not None:
        lo, hi, _ = rng(t)
        info("T (theta-300) [K]", "min %.1f  max %.1f" % (lo, hi))

    for name in ("SMOIS", "TSLB", "TSK", "U", "V", "T", "QVAPOR", "PH"):
        v = var(ds, name)
        if v is not None and not np.all(np.isfinite(np.asarray(v))):
            check("%s finite" % name, False, "contains NaN or Inf",
                  "real.exe wrote non-finite values -- do not run wrf.exe on this")

    # ---- report ----------------------------------------------------------
    width = max(len(f[1]) for f in findings)
    print("=== %s" % path)
    for status, name, detail, hint in findings:
        print("  [%s] %-*s  %s" % (status, width, name, detail))
        if hint:
            for line in ("         -> " + hint).split("\n"):
                print("  " + line)
    nfail = sum(1 for f in findings if f[0].strip() == "FAIL")
    print("\n=== %s" % ("%d check(s) FAILED" % nfail if nfail else "all checks passed"))
    return 1 if nfail else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
