#!/usr/bin/env python3
"""Sync and validate namelist.input against geo_em / met_em, for the ICON-forced
Inn Valley case with the 3D PBL scheme.

    prepare_namelist.py namelist.input --geo geo_em_d01.nc --met-dir /path/to/met_em
    prepare_namelist.py namelist.input --geo ... --met-dir ... --apply

Without --apply it only reports; with --apply it rewrites the namelist in place
(keeping comments and layout) and re-checks.

Why this exists
---------------
Six namelist values are not free parameters -- they are properties of the WPS
output, and getting one of them wrong gives either an immediate real.exe abort
or, worse, a run that starts and is silently wrong:

    e_we, e_sn, dx, dy            from geo_em_d01.nc
    num_land_cat                  from geo_em_d01.nc (CORINE is not 21)
    num_metgrid_levels            from met_em (number of ICON model levels)
    num_metgrid_soil_levels       from met_em (ICON/TERRA has 8, not 3 or 4)
    interval_seconds, start/end   from the met_em file list

On top of that it enforces the constraints the 3D PBL scheme carries, which
module_check_a_mundo.F will also catch but only after you have queued the job:
bl_pbl_physics=0, hybrid_opt=0, diff_opt=0.

Only needs ncdump on PATH -- no python netCDF bindings.
"""

import argparse
import glob
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta

FATAL, WARN, INFO, OK = "FATAL", "WARN", "INFO", "ok"
_findings = []


def note(level, msg):
    _findings.append((level, msg))


# --------------------------------------------------------------------------
# netCDF header reading (via ncdump -h, so no python bindings are needed)
# --------------------------------------------------------------------------

def ncheader(path):
    try:
        out = subprocess.run(["ncdump", "-h", path], check=True,
                             capture_output=True, text=True).stdout
    except FileNotFoundError:
        sys.exit("ncdump not found on PATH -- load your netCDF module first")
    except subprocess.CalledProcessError as e:
        sys.exit("ncdump failed on %s:\n%s" % (path, e.stderr.strip()))
    return out


def nc_global_attrs(header):
    """Global attributes as {NAME: value}, numbers converted, strings unquoted."""
    attrs = {}
    for m in re.finditer(r'^\s*:([A-Za-z0-9_\-]+)\s*=\s*(.+?)\s*;\s*$', header, re.M):
        name, raw = m.group(1), m.group(2).strip()
        if raw.startswith('"'):
            attrs[name] = raw.strip('"')
            continue
        raw = raw.split(",")[0].strip().rstrip("fdbsUL")
        try:
            attrs[name] = int(raw)
        except ValueError:
            try:
                attrs[name] = float(raw)
            except ValueError:
                attrs[name] = raw
    return attrs


def nc_dims(header):
    dims = {}
    body = header.split("dimensions:", 1)
    if len(body) < 2:
        return dims
    body = body[1].split("variables:", 1)[0]
    for m in re.finditer(r'^\s*([A-Za-z0-9_]+)\s*=\s*(\d+|UNLIMITED)', body, re.M):
        if m.group(2) != "UNLIMITED":
            dims[m.group(1)] = int(m.group(2))
    return dims


# --------------------------------------------------------------------------
# Fortran namelist read/edit that preserves comments and layout
# --------------------------------------------------------------------------

_KEY_RE = re.compile(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*=\s*)(.*)$')


def _strip_inline_comment(value):
    """Split 'a, b,  ! comment' into ('a, b,', '  ! comment')."""
    i = value.find("!")
    return (value, "") if i < 0 else (value[:i].rstrip(), value[i:])


class Namelist:
    def __init__(self, path):
        self.path = path
        with open(path) as f:
            self.lines = f.read().splitlines()
        self.index = {}          # key -> (line number, group)
        group = None
        for n, line in enumerate(self.lines):
            s = line.strip()
            if s.startswith("!"):
                continue
            if s.startswith("&"):
                group = s[1:].split()[0].lower()
                continue
            if s in ("/", "&end"):
                group = None
                continue
            if group is None:
                continue
            m = _KEY_RE.match(line)
            if m:
                self.index[m.group(2).lower()] = (n, group)

    def raw(self, key):
        hit = self.index.get(key.lower())
        if hit is None:
            return None
        m = _KEY_RE.match(self.lines[hit[0]])
        return _strip_inline_comment(m.group(4))[0].strip().rstrip(",").strip()

    def get(self, key, cast=None, default=None):
        v = self.raw(key)
        if v is None:
            return default
        v = v.split(",")[0].strip()          # first domain only; max_dom is 1 here
        if cast is None:
            return v
        if cast is bool:
            return v.strip(". ").lower() in ("t", "true")
        try:
            return cast(v)
        except ValueError:
            return default

    def has(self, key):
        return key.lower() in self.index

    def group_of(self, key):
        hit = self.index.get(key.lower())
        return hit[1] if hit else None

    def set(self, key, value):
        """Replace the value of an existing key, keeping any trailing comment in
        the column it was already in. Returns (old, new) or None."""
        hit = self.index.get(key.lower())
        if hit is None:
            return None
        n = hit[0]
        m = _KEY_RE.match(self.lines[n])
        val_field = m.group(4)
        bang = val_field.find("!")
        old_val = val_field if bang < 0 else val_field[:bang]
        comment = "" if bang < 0 else val_field[bang:]
        old = old_val.strip().rstrip(",").strip()
        new = str(value)
        if old == new:
            return None
        prefix = m.group(1) + m.group(2) + m.group(3)
        text = new + ("," if old_val.rstrip().endswith(",") else "")
        if comment:
            pad = max(1, len(prefix) + bang - len(prefix) - len(text))
            self.lines[n] = prefix + text + " " * pad + comment
        else:
            self.lines[n] = prefix + text
        return (old, new)

    def write(self):
        with open(self.path, "w") as f:
            f.write("\n".join(self.lines) + "\n")


# --------------------------------------------------------------------------
# met_em discovery
# --------------------------------------------------------------------------

MET_RE = re.compile(r'met_em\.d(\d\d)\.(\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2})\.nc$')

# The namelist templates ship with this token instead of an absolute path;
# --output-root replaces it.  An unexpanded token is FATAL (see check()) rather
# than something WRF discovers by writing to a literal "@OUTPUT_ROOT@" directory.
OUTPUT_ROOT_TOKEN = "@OUTPUT_ROOT@"
OUTPUT_KEYS = ("history_outname", "auxhist24_outname")


def scan_met(met_dir, dom=1):
    files = []
    for p in sorted(glob.glob(os.path.join(met_dir, "met_em.d%02d.*.nc" % dom))):
        m = MET_RE.search(os.path.basename(p))
        if m:
            files.append((datetime.strptime(m.group(2), "%Y-%m-%d_%H:%M:%S"), p))
    files.sort()
    return files


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("namelist")
    ap.add_argument("--geo", help="geo_em_d01.nc")
    ap.add_argument("--met-dir", help="directory holding met_em.d01.*.nc")
    ap.add_argument("--met", help="a single met_em file (instead of --met-dir)")
    ap.add_argument("--apply", action="store_true",
                    help="write the synced values into the namelist")
    ap.add_argument("--output-root",
                    help="expand @OUTPUT_ROOT@ in history_outname/auxhist24_outname; "
                         "normally passed by setup_rundir.sh from $WRF_OUTPUT_ROOT")
    ap.add_argument("--hours", type=float,
                    help="override the run length; default is the met_em coverage")
    ap.add_argument("--smoke", action="store_true",
                    help="1 h run with 10 min output -- measure throughput and confirm "
                         "stability before committing to the full day")
    args = ap.parse_args()

    nl = Namelist(args.namelist)
    changes = []

    def sync(key, value, source):
        r = nl.set(key, value)
        if r:
            changes.append((key, r[0], r[1], source))

    if args.smoke:
        for k, v in (("history_interval", 10), ("auxhist24_interval_m", 10),
                     ("avg_interval", 600), ("restart_interval", 60)):
            sync(k, v, "smoke")
        args.hours = args.hours or 1.0

    # ---- output root ------------------------------------------------------
    # The two outname paths are the only absolute paths in the namelist, and the
    # only thing about them that is cluster-specific is the root.  Keeping the
    # rest of the path (temp/branko/, the <domain>/<date> patterns) in the
    # template means the output layout is identical on every cluster -- see
    # OUTPUT_KEYS below and the convention table in realcase/README.md.
    if args.output_root:
        root = args.output_root.rstrip("/")
        for key in OUTPUT_KEYS:
            cur = nl.raw(key)
            if cur and OUTPUT_ROOT_TOKEN in cur:
                sync(key, cur.replace(OUTPUT_ROOT_TOKEN, root), "output root")

    # ---- geo_em -----------------------------------------------------------
    if args.geo:
        if not os.path.exists(args.geo):
            sys.exit("no such file: %s" % args.geo)
        g = nc_global_attrs(ncheader(args.geo))
        sync("e_we", g["WEST-EAST_GRID_DIMENSION"], "geo_em")
        sync("e_sn", g["SOUTH-NORTH_GRID_DIMENSION"], "geo_em")
        sync("dx", "%g" % g["DX"], "geo_em")
        sync("dy", "%g" % g["DY"], "geo_em")
        if "NUM_LAND_CAT" in g:
            sync("num_land_cat", g["NUM_LAND_CAT"], "geo_em")
        mminlu = g.get("MMINLU", "?")
        note(INFO, "geo_em: %dx%d at %g m, land use '%s' with %s categories"
             % (g["WEST-EAST_GRID_DIMENSION"], g["SOUTH-NORTH_GRID_DIMENSION"],
                g["DX"], mminlu, g.get("NUM_LAND_CAT", "?")))
        if isinstance(mminlu, str) and "corine" not in mminlu.lower() \
                and g.get("NUM_LAND_CAT") in (21, 24):
            note(WARN, "geo_em land use is '%s' with %s categories -- that looks like "
                       "stock MODIS/USGS, not CORINE. Re-check geog_data_res in "
                       "namelist.wps if CORINE was the intent."
                 % (mminlu, g.get("NUM_LAND_CAT")))
    else:
        note(WARN, "no --geo given: e_we/e_sn/dx/dy/num_land_cat were not checked")

    # ---- met_em -----------------------------------------------------------
    met_files = []
    if args.met_dir:
        met_files = scan_met(args.met_dir)
        if not met_files:
            sys.exit("no met_em.d01.*.nc found in %s" % args.met_dir)
    elif args.met:
        m = MET_RE.search(os.path.basename(args.met))
        if not m:
            sys.exit("cannot parse a date out of %s" % args.met)
        met_files = [(datetime.strptime(m.group(2), "%Y-%m-%d_%H:%M:%S"), args.met)]

    if met_files:
        hdr = ncheader(met_files[0][1])
        dims, attrs = nc_dims(hdr), nc_global_attrs(hdr)

        nlev = dims.get("num_metgrid_levels")
        if nlev is None:
            note(FATAL, "met_em has no num_metgrid_levels dimension")
        else:
            sync("num_metgrid_levels", nlev, "met_em")

        nsoil = attrs.get("NUM_METGRID_SOIL_LEVELS") or dims.get("num_st_layers")
        if nsoil:
            sync("num_metgrid_soil_levels", nsoil, "met_em")
            if nsoil != 8:
                note(WARN, "met_em reports %d soil levels; ICON/TERRA normally has 8. "
                           "Check that ungrib picked up all SOILT*/SOILM* entries." % nsoil)

        if attrs.get("FLAG_SOIL_LAYERS", 0) != 1 and attrs.get("FLAG_SOIL_LEVELS", 0) != 1:
            note(FATAL, "met_em sets neither FLAG_SOIL_LAYERS nor FLAG_SOIL_LEVELS -- "
                        "real.exe will fall back to the legacy ST000010 path and find "
                        "nothing. The ICON Vtable was probably not used.")

        times = [t for t, _ in met_files]
        note(INFO, "met_em: %d files, %s .. %s, %d vertical levels"
             % (len(times), times[0].strftime("%Y-%m-%d_%H:%M"),
                times[-1].strftime("%Y-%m-%d_%H:%M"), nlev or -1))

        if len(times) > 1:
            deltas = {int((b - a).total_seconds()) for a, b in zip(times, times[1:])}
            if len(deltas) > 1:
                note(FATAL, "met_em files are not evenly spaced: intervals %s s. "
                            "WRF needs one constant interval_seconds." % sorted(deltas))
            else:
                sync("interval_seconds", deltas.pop(), "met_em spacing")

        start = times[0]
        end = start + timedelta(hours=args.hours) if args.hours else times[-1]
        if end > times[-1]:
            note(FATAL, "--hours %g runs to %s but the last met_em is %s"
                 % (args.hours, end, times[-1]))
            end = times[-1]
        span = end - start
        for k, v in (("start_year", start.year), ("start_month", "%02d" % start.month),
                     ("start_day", "%02d" % start.day), ("start_hour", "%02d" % start.hour),
                     ("start_minute", "%02d" % start.minute), ("start_second", "%02d" % start.second),
                     ("end_year", end.year), ("end_month", "%02d" % end.month),
                     ("end_day", "%02d" % end.day), ("end_hour", "%02d" % end.hour),
                     ("end_minute", "%02d" % end.minute), ("end_second", "%02d" % end.second),
                     ("run_days", span.days),
                     ("run_hours", span.seconds // 3600),
                     ("run_minutes", (span.seconds % 3600) // 60),
                     ("run_seconds", span.seconds % 60)):
            sync(k, v, "met_em window")
    else:
        note(WARN, "no --met-dir/--met given: num_metgrid_levels, soil levels and the "
                   "time window were not checked")
        if args.smoke:
            for k, v in (("run_days", 0), ("run_hours", 1),
                         ("run_minutes", 0), ("run_seconds", 0)):
                sync(k, v, "smoke")

    # ---- apply ------------------------------------------------------------
    if changes:
        print("=== namelist values %s" % ("WRITTEN" if args.apply else "that WOULD change (use --apply)"))
        for k, old, new, src in changes:
            print("    %-26s %-12s -> %-12s   [%s]" % (k, old, new, src))
        if args.apply:
            nl.write()
            nl = Namelist(args.namelist)          # re-read so the checks see the new values
    else:
        print("=== namelist already consistent with geo_em/met_em")

    # ---- checks -----------------------------------------------------------
    check(nl)

    print("\n=== checks")
    worst = OK
    for level, msg in _findings:
        print("    [%-5s] %s" % (level, msg))
        if level == FATAL:
            worst = FATAL
        elif level == WARN and worst != FATAL:
            worst = WARN
    if not _findings:
        print("    all clear")
    print("\n=== %s" % {FATAL: "FATAL problems -- do not submit",
                        WARN: "warnings only -- read them, then you may submit",
                        OK: "clean"}[worst])
    return 1 if worst == FATAL else 0


def check(nl):
    g = nl.get

    # -- values that must have been synced ---------------------------------
    if not g("num_metgrid_levels", int, 0):
        note(FATAL, "num_metgrid_levels is 0 -- run this script with --met-dir")

    for key in OUTPUT_KEYS:
        v = nl.raw(key)
        if v is None:
            continue
        if OUTPUT_ROOT_TOKEN in v:
            note(FATAL, "%s still contains %s -- pass --output-root, or set "
                        "WRF_OUTPUT_ROOT in your env file and let setup_rundir.sh "
                        "pass it. WRF would otherwise write to a literal '%s' "
                        "directory." % (key, OUTPUT_ROOT_TOKEN, OUTPUT_ROOT_TOKEN))
        elif not v.strip("'\"").startswith("/"):
            note(WARN, "%s is a relative path (%s); output would land in the run "
                       "directory rather than the shared output tree" % (key, v))

    # -- 3D PBL hard requirements (module_check_a_mundo.F) -----------------
    p3 = g("pbl3d_opt", int, 0)
    if p3 != 0:
        if g("bl_pbl_physics", int, 0) != 0:
            note(FATAL, "pbl3d_opt=%d needs bl_pbl_physics=0 (got %s)"
                 % (p3, g("bl_pbl_physics", int)))
        if g("hybrid_opt", int, 2) != 0:
            note(FATAL, "pbl3d_opt=%d needs hybrid_opt=0; the default is 2, so it must "
                        "be set explicitly in &dynamics (got %s)"
                 % (p3, g("hybrid_opt", int, 2)))
        diff = g("diff_opt", int, 0)
        if p3 in (1, 2) and diff != 0:
            note(FATAL, "pbl3d_opt=%d does all the SGS mixing itself and needs "
                        "diff_opt=0 (got %d)" % (p3, diff))
        if p3 == -1:
            if diff not in (1, 2):
                note(FATAL, "pbl3d_opt=-1 needs diff_opt=1 or 2 (got %d)" % diff)
            if g("km_opt", int, -1) != 4:
                note(FATAL, "pbl3d_opt=-1 needs km_opt=4 (got %s)" % g("km_opt", int))
        if g("pbl3d_sk_eps_max", float, 6.0) <= 0:
            note(FATAL, "pbl3d_sk_eps_max must be > 0")
        ntau = g("pbl3d_n_tau_max", float, 0.53)
        if ntau <= 0:
            note(FATAL, "pbl3d_n_tau_max must be > 0")
        elif ntau > 5.0:
            note(WARN, "pbl3d_n_tau_max=%g effectively disables the buoyancy limit on "
                       "the master length scale" % ntau)
        if g("pbl3d_l0_opt", int, 1) not in (0, 1):
            note(FATAL, "pbl3d_l0_opt must be 0 or 1")
        elif g("pbl3d_l0_opt", int, 1) == 0:
            note(WARN, "pbl3d_l0_opt=0 makes l0 depend on the model lid height; use it "
                       "only to reproduce pre-group-E runs")
        if g("pbl3d_qsq_opt", int, 1) == 0 and p3 == 2:
            note(WARN, "pbl3d_qsq_opt=0 closes q^2 on vertical gradients only, which is "
                       "not self-consistent with the full 3D system")
        if g("tke_budget", int, 0) != 0:
            note(WARN, "tke_budget is a MYNN-only diagnostic and does nothing with "
                       "bl_pbl_physics=0; set it to 0")
        if g("pbl3d_l_opt", int, 1) == 3:
            note(WARN, "pbl3d_l_opt=3 (Messinger) has never been run since the group F "
                       "l_dissip fix and the group G NaN guard touched that path")
        if g("sf_sfclay_physics", int, 0) not in (1, 91):
            note(WARN, "pbl3d expects sf_sfclay_physics=1 (sfclayrev); got %s. Other "
                       "surface layers are not wrong, but they are untested here."
                 % g("sf_sfclay_physics", int))
    else:
        if g("bl_pbl_physics", int, 0) == 0:
            note(WARN, "both pbl3d_opt and bl_pbl_physics are 0 -- this run has no "
                       "boundary-layer turbulence closure at all")

    # -- WRFlux ------------------------------------------------------------
    flux_on = any(g("output_%s_fluxes" % v, int, 0) for v in "tquvw")
    if flux_on:
        avg = g("avg_interval", float, -1)
        out = (g("auxhist24_interval", float, 0) * 60
               + g("auxhist24_interval_d", float, 0) * 86400
               + g("auxhist24_interval_h", float, 0) * 3600
               + g("auxhist24_interval_m", float, 0) * 60
               + g("auxhist24_interval_s", float, 0))
        if out == 0:
            note(FATAL, "flux output is on but no auxhist24 interval is set")
        elif avg > out:
            note(FATAL, "avg_interval=%g s exceeds the auxhist24 interval of %g s; "
                        "check_a_mundo makes this fatal" % (avg, out))
        if g("use_adaptive_time_step", bool, False):
            note(FATAL, "WRFlux does not support adaptive timestepping")
        if g("do_avgflx_em", int, 0) != 1:
            note(WARN, "do_avgflx_em=0: the time-averaged mass-coupled winds WRFlux "
                       "builds its budget on will not be written")
        if not g("output_dry_theta_fluxes", bool, True) and g("use_theta_m", int, 1) == 1:
            note(INFO, "fluxes will be for moist theta, matching the model's own variable")

    # -- domain / dynamics -------------------------------------------------
    dx = g("dx", float, 0)
    dt = g("time_step", float, 0)
    if dx and dt > 6 * dx / 1000.0:
        note(WARN, "time_step=%g s is above the 6*dx rule of thumb (%g s) for dx=%g m; "
                   "over 35 deg slopes that is asking for a CFL failure"
             % (dt, 6 * dx / 1000.0, dx))
    sbw, sz, rz = (g("spec_bdy_width", int, 5), g("spec_zone", int, 1), g("relax_zone", int, 4))
    if sbw != sz + rz:
        note(FATAL, "spec_bdy_width (%d) must equal spec_zone + relax_zone (%d + %d)"
             % (sbw, sz, rz))
    if not g("specified", bool, False):
        note(FATAL, "specified=.false. in &bdy_control -- a real case driven by lateral "
                    "boundary conditions needs .true.")
    if g("slope_rad", int, 0) != 1 or g("topo_shading", int, 0) != 1:
        note(WARN, "slope_rad/topo_shading are not both 1; in a deep valley the surface "
                   "energy budget that drives cold-pool erosion depends on them")

    # -- output volume -----------------------------------------------------
    ew, sn, ev = g("e_we", int, 0), g("e_sn", int, 0), g("e_vert", int, 0)
    if ew and sn and ev and flux_on:
        pts = ew * sn * ev
        n_flux = sum(1 for v in "tquvw" if g("output_%s_fluxes" % v, int, 0))
        gib_per_frame = pts * 4 * (25 * n_flux + 15) / 2**30
        run_s = (g("run_days", float, 0) * 86400 + g("run_hours", float, 0) * 3600
                 + g("run_minutes", float, 0) * 60)
        out_s = (g("auxhist24_interval_m", float, 0) * 60
                 + g("auxhist24_interval_h", float, 0) * 3600
                 + g("auxhist24_interval_s", float, 0)) or 1e9
        note(INFO, "rough auxhist24 volume: ~%.1f GiB/frame x %d frames = ~%.0f GiB. "
                   "If that is too much, point iofields_filename at realcase/iofields.txt "
                   "or drop the flux components you do not need."
             % (gib_per_frame, int(run_s / out_s), gib_per_frame * int(run_s / out_s)))


if __name__ == "__main__":
    sys.exit(main())
