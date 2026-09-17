#!/usr/bin/env python
"""Compatibility of two icon2wrf surface series that are to be joined (A ends where B begins) and of the setup grid:
grid (lat/lon/HSURF), soil axes, variable set and units, time contiguity (no gap, no overlap), NaNs at the junction, and the
physical continuity at the junction (last hour of A vs first hour of B) at the i-Box sites and as domain statistics.
Usage: python check_series_join.py <seriesA.nc> <seriesB.nc> [<wrfinput or setup file>]"""
import sys, numpy as np, netCDF4 as nc   # WRF-env python: no pandas here (E56)
A, B = nc.Dataset(sys.argv[1]), nc.Dataset(sys.argv[2]); ok = True
def chk(cond, msg):
    global ok; ok &= bool(cond); print(("  [ok  ] " if cond else "  [FAIL] ") + msg)
def ndt(v):   # "days|hours|seconds since <iso>" -> numpy datetime64[s] (no cftime/pandas dependence)
    unit, _, base = v.units.partition(" since "); fac = {"days": 86400, "hours": 3600, "seconds": 1}[unit.strip()]
    return np.datetime64(base.strip().replace(" ", "T")) + (np.asarray(v[:], dtype="f8") * fac).round().astype("timedelta64[s]")
tA = ndt(A["time"]); tB = ndt(B["time"])
print(f"A: {sys.argv[1].split('/')[-1]}  {tA[0]} -> {tA[-1]}  ({len(tA)} h)\nB: {sys.argv[2].split('/')[-1]}  {tB[0]} -> {tB[-1]}  ({len(tB)} h)")
chk(np.array_equal(A["lat"][:], B["lat"][:]) and np.array_equal(A["lon"][:], B["lon"][:]), "identical lat/lon grids")
chk(np.array_equal(A["HSURF"][:], B["HSURF"][:]), "identical HSURF")
chk(np.array_equal(A["soil_depth"][:], B["soil_depth"][:]) and np.array_equal(A["soil_layer_bottom"][:], B["soil_layer_bottom"][:]), "identical soil axes")
core = ["T2D", "Q2D", "U2D", "V2D", "PSFC", "RAINRATE", "SWDOWN", "LWDOWN", "TG", "SNOWH", "SNOWC", "TSOIL", "WSOIL"]
chk(all(v in A.variables and v in B.variables for v in core), "all forcing/state variables present in both")
chk(all(getattr(A[v], "units", None) == getattr(B[v], "units", None) for v in core), "identical units: " + ", ".join(f"{v}={getattr(A[v],'units','?')}" for v in core[:8]))
dt_h = (tB[0] - tA[-1]) / np.timedelta64(1, "h")
chk(abs(dt_h - 1.0) < 1e-6, f"B starts exactly one hour after A ends (gap = {dt_h:.2f} h)")
dA = np.diff(tA) / np.timedelta64(1, "h"); dB = np.diff(tB) / np.timedelta64(1, "h")
chk(np.allclose(dA, 1) and np.allclose(dB, 1), "both series hourly without internal gaps")
extra = sorted(set(A.variables) - set(B.variables)); print(f"  variables only in A: {extra}")
init = [v for v in A.variables if v.endswith("_init")]
if init:
    t0 = str(tA[0])[:13]; note = getattr(A, "initial_state", "")
    chk(t0 in note, f"_init fields declared for the first hour ({t0}): '{note[:90]}'")
    for v in init: chk(not np.isnan(np.asarray(A[v][:], dtype="f8")).any(), f"{v} NaN-free")
    if "SNEQV_init" in A.variables and "RHOSNOW_init" in A.variables:
        sn, se, rh = np.asarray(A["SNOWH"][0]), np.asarray(A["SNEQV_init"][:]), np.asarray(A["RHOSNOW_init"][:]); m = sn > 0.01
        r = se[m] / (rh[m] * sn[m]); chk(np.nanmedian(np.abs(r - 1)) < 0.02, f"SNEQV_init = RHOSNOW_init * SNOWH(t0) (median ratio {np.nanmedian(r):.3f}, {m.sum()} snow cells, median density {np.nanmedian(rh[m]):.0f} kg m-3)")
# junction continuity
la, lo = np.asarray(A["lat"][:]), np.asarray(A["lon"][:]); cell = lambda y, x: np.unravel_index(np.argmin((la - y) ** 2 + (lo - x) ** 2), la.shape)
S = {"Kolsass": (47.305341, 11.62219), "Eggen": (47.3165, 11.6162), "StanserJoch": (47.39504, 11.68714), "Arbeser": (47.320654, 11.746592)}
print(f"\n--- junction: A last ({tA[-1]}) -> B first ({tB[0]}); provenance A: {A['data_flag'][-1] if 'data_flag' in A.variables else '?'} / lead {A['lead_hours'][-1] if 'lead_hours' in A.variables else '?'} h; B: {B['data_flag'][0] if 'data_flag' in B.variables else '?'} / lead {B['lead_hours'][0] if 'lead_hours' in B.variables else '?'} h")
print(f"{'site':12s} {'T2D':>12s} {'PSFC':>16s} {'TG':>12s} {'SNOWH':>12s} {'TSOIL18cm':>12s} {'WSOIL9-27':>12s} {'LWDOWN':>12s}")
for n, (y, x) in S.items():
    j, i = cell(y, x)
    row = []
    for v, k in (("T2D", None), ("PSFC", None), ("TG", None), ("SNOWH", None), ("TSOIL", 4), ("WSOIL", 3), ("LWDOWN", None)):
        a = float(A[v][-1, k, j, i]) if k is not None else float(A[v][-1, j, i]); b = float(B[v][0, k, j, i]) if k is not None else float(B[v][0, j, i])
        row.append(f"{a:.1f}/{b:.1f}" if v != "SNOWH" else f"{a:.3f}/{b:.3f}")
    print(f"{n:12s} " + " ".join(f"{r:>12s}" if k != 1 else f"{r:>16s}" for k, r in enumerate(row)))
print("--- domain: median and 90th percentile of |B(first) - A(last)| over land-ish cells (all cells), and the NaN count at the junction")
for v in ("T2D", "TG", "PSFC", "Q2D", "SNOWH", "LWDOWN"):
    a, b = np.asarray(A[v][-1], dtype="f8"), np.asarray(B[v][0], dtype="f8"); d = np.abs(b - a)
    print(f"  {v:7s} median {np.nanmedian(d):9.4f}  p90 {np.nanpercentile(d, 90):9.4f}  NaN A/B {np.isnan(a).sum()}/{np.isnan(b).sum()}")
for v, k in (("TSOIL", 4), ("TSOIL", 6), ("WSOIL", 3), ("WSOIL", 5)):
    a, b = np.asarray(A[v][-1, k], dtype="f8"), np.asarray(B[v][0, k], dtype="f8"); d = np.abs(b - a)
    print(f"  {v}[{k}] median {np.nanmedian(d):9.4f}  p90 {np.nanpercentile(d, 90):9.4f}")
if len(sys.argv) > 3:
    w = nc.Dataset(sys.argv[3]); chk(w["XLAT"].shape[1:] == la.shape and np.allclose(np.asarray(w["XLAT"][0]), la, atol=1e-4) and np.allclose(np.asarray(w["XLONG"][0]), lo, atol=1e-4), f"setup/wrfinput grid matches the series ({sys.argv[3].split('/')[-1]})")
print("\n=== JOIN OK" if ok else "\n=== JOIN HAS FAILURES")
sys.exit(0 if ok else 1)
