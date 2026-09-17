import sys, glob, numpy as np, netCDF4 as nc
files = sorted(f for f in glob.glob(sys.argv[1] + "/*.LDASIN_DOMAIN1") if not __import__("os").path.islink(f))
k, n = int(sys.argv[2]), int(sys.argv[3]); files = files[k::n]; bad = []
V = ["T2D", "Q2D", "U2D", "V2D", "PSFC", "RAINRATE", "SWDOWN", "LWDOWN"]
for f in files:
    try:
        d = nc.Dataset(f)
        for v in V:
            a = d[v][0]
            if a.shape != (500, 600) or np.isnan(np.asarray(a, dtype="f8")).any(): bad.append((f, v, "shape/NaN")); break
        if "valid_time" not in d.ncattrs(): bad.append((f, "-", "no valid_time attr"))
        d.close()
    except Exception as e: bad.append((f, "-", str(e)[:60]))
print(f"part {k}: {len(files)} files checked, {len(bad)} bad"); [print("  BAD", *b) for b in bad[:20]]
