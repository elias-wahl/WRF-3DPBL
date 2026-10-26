#!/usr/bin/env python
"""Four-panel site map, one shared elevation colour scale:
(a) WRF domain (model terrain, five largest cities, country borders),
(b) Lower Inn Valley (SRTM 1"), with the zoom boxes of (c) and (d) and the
    three observation sites as nested icons,
(c) Kolsass (DGM Tirol 10 m), (d) Radfeld supersite (DGM Tirol 10 m).

Every instrument position is read from the measurement metadata (source per
entry below); nothing is digitised from a map.  Co-located instruments are drawn
as nested icons (one per instrument type) centred on the site.
Positions are transformed to EPSG:31254 with pyproj (datum-correct MGI Helmert);
cartopy's EPSG:31254 drops the datum shift (~75 m) and is not used.

Run with the `proc` conda env:
    ~/miniconda3/envs/proc/bin/python scripts/make_site_map.py [--preview PNG]
"""
import argparse
import itertools
from pathlib import Path

import numpy as np
import netCDF4
import rasterio
from rasterio.windows import from_bounds
from pyproj import Transformer
from scipy.ndimage import map_coordinates
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LightSource, LinearSegmentedColormap, PowerNorm
from matplotlib.lines import Line2D
from matplotlib.markers import MarkerStyle
from matplotlib.path import Path as MplPath
from matplotlib.transforms import offset_copy
import cartopy.crs as ccrs
import cartopy.feature as cfeature

DATA = Path("/gpfs/data/fs72996/ewahl")
WRFINPUT = DATA / "branko_runs/innval_pbl3d_HSI2/wrfinput_d01"
DGM = DATA / "data/geo/DGM_Tirol_10m_epsg31254_2006_2020.tif"
SRTM = DATA / "WPS_GEOG/topo_SRTM"          # WPS geog tiles, the source of the model HGT
OUT = DATA / "concept/figures/site_map.pdf"

# ---------------------------------------------------------------- instruments
# kind -> (marker, colour, legend label).  Co-located kinds are drawn NESTED and FILLED
# (same centre), so colours that touch must separate.  Elias: no two blue-ish colours, no
# white HATPRO; no green (lost on the valley floor).  Searched over palette + off-palette
# hues + black: HATPRO light pink keeps every other colour; touching pairs OKLab dE >= 22
# (normal, red-pink) and >= 10.4 (protan/deutan/tritan, Machado 2009; pink-aqua, whose
# shapes also differ); legend pairs >= 17.7; HATPRO vs radiosonde 47.
KINDS = {
    "lidar": ("D", "#e34948", "Doppler wind lidar"),
    "sonde": ("*", "#1a1a19", "Radiosonde"),
    "mwr":   ("h", "#f2a7c3", "Microwave radiometer (HATPRO)"),
    "ec":    ("s", "#1baf7a", "Eddy-covariance tower (i-Box)"),
    "aws":   ("o", "#eda100", "Weather station (GeoSphere TAWES)"),
    "uas":   ("P", "#2a78d6", "UAS profile site"),
    "city":  ("o", "white", "City (panel a)"),
}
# default nesting order, outermost first (per-site override via site(nest=...))
NEST_ORDER = ["city", "aws", "lidar", "mwr", "ec", "uas", "sonde"]
SIZE = {"D": 0.82, "s": 0.9, "h": 1.0, "^": 1.0, "o": 1.0, "P": 1.0, "*": 1.3}   # equal visual size, single icons
GROW = {1: 1.0, 2: 1.45, 3: 1.8, 4: 2.2}    # outer icon of a nest of n, relative to a single icon

# (name, kind, lat, lon, source)
INSTR = [
    # Innsbruck
    ("Innsbruck Flughafen", "aws", 47.25999, 11.35667, "tawes/metadata_klima_10min.json id 11804"),
    ("Innsbruck Universität", "aws", 47.25986, 11.38425, "tawes/metadata_klima_10min.json id 11803"),
    ("Innsbruck radiosonde", "sonde", 47.26000, 11.35500, "proc/config/config.yaml poi.ibk (11120)"),
    ("Oberschleißheim radiosonde", "sonde", 48.245, 11.553, "config.yaml poi.obs (10868)"),
    ("Altenstadt radiosonde", "sonde", 47.8340, 10.8671, "data/plane soundings/als/*-10954.csv launch; config.yaml poi.als"),
    # Kolsass valley site
    ("Kolsass", "ec", 47.305341, 11.62219, "stations/ibox_ecpy/stations.csv vf0"),
    ("Kolsass lidar", "lidar", 47.30523, 11.62226, "dlid86 L2 netCDF global attrs"),
    ("Kolsass radiosonde", "sonde", 47.30414, 11.62304, "proc/config/config.yaml poi.kol_sound (11121)"),
    # HATPRO UIBK: during the campaign next to the i-Box tower at the Kolsass main station
    # (Elias 2026-09-25) -> pinned at the tower (vf0).  The ACINN portal gives only its
    # permanent site (Innsbruck university roof, 47.2643 N 11.3853 E).
    ("Kolsass HATPRO", "mwr", 47.305341, 11.62219, "next to the i-Box tower (Elias 2026-09-25)"),
    # i-Box slope / crest stations
    ("Eggen", "ec", 47.3165, 11.6162, "stations.csv sf1"),
    ("Terfens", "ec", 47.325538, 11.65247, "stations.csv sf8"),
    ("Weerberg", "ec", 47.299754, 11.672969, "stations.csv nf10"),
    ("Hochhäuser", "ec", 47.28755, 11.63122, "stations.csv nf27"),
    ("Stanser Joch", "ec", 47.39504, 11.68714, "stations.csv sf23"),
    ("Arbeser", "ec", 47.320654, 11.746592, "stations.csv mt21"),
    ("Jenbach", "aws", 47.38878, 11.75814, "tawes/metadata_klima_10min.json id 11901"),
    # Radfeld supersite
    ("Radfeld", "aws", 47.456408, 11.931428, "stations/rad/*.dat header (TAWES 89120)"),
    ("Klärwerk", "lidar", 47.458998, 11.932217, "WLS100S101 VAD netCDF attrs"),
    # MeteoSwiss HATPRO-G5, 12 Jun - 8 Sep 2025 (a second radiometer; the UIBK one was at Kolsass)
    ("Radfeld HATPRO", "mwr", 47.458999, 11.932239, "Zenodo 10.5281/zenodo.21918290 metadata"),
    ("Museum", "lidar", 47.465144, 11.92255, "SLXR98 VAD netCDF attrs"),
    ("Oberberg", "lidar", 47.47494, 11.920056, "WLS100S34 VAD netCDF attrs"),
    ("Manny", "uas", 47.477256, 11.912614, "config.yaml poi.mny"),
    ("Molt", "uas", 47.473397, 11.916786, "config.yaml poi.mlt"),
    ("Hopper", "uas", 47.465881, 11.922881, "config.yaml poi.hop"),
    ("Thumper", "uas", 47.461408, 11.929067, "config.yaml poi.tmp"),
]
BY_NAME = {n: (k, la, lo) for n, k, la, lo, _ in INSTR}

# Five largest Natural Earth populated places inside the domain (POP_MAX).
CITIES = {"Munich": (48.131888, 11.573048), "Augsburg": (48.350006, 10.899996),
          "Salzburg": (47.810478, 13.04002), "Innsbruck": (47.280407, 11.409991),
          "Bolzano": (46.500429, 11.36002)}


def site(names, label, side="right", bold=False, nest=None):
    """A drawn site: the kinds of the instruments `names`, nested at their mean position.
    `names` may include cities (panel a).  `nest`: nesting order, outermost first."""
    pts = [(BY_NAME[n][0], BY_NAME[n][1], BY_NAME[n][2]) if n in BY_NAME
           else ("city", *CITIES[n]) for n in names]
    kinds = sorted({p[0] for p in pts}, key=(nest or NEST_ORDER).index)
    inst = [p for p in pts if p[0] != "city"] or pts          # anchor on the instruments
    return dict(kinds=kinds, lat=np.mean([p[1] for p in inst]), lon=np.mean([p[2] for p in inst]),
                label=label, side=side, bold=bold)


IBK = ["Innsbruck Flughafen", "Innsbruck Universität", "Innsbruck radiosonde"]
KOL = ["Kolsass", "Kolsass lidar", "Kolsass radiosonde", "Kolsass HATPRO"]
RAD = ["Radfeld", "Klärwerk", "Radfeld HATPRO", "Museum", "Oberberg", "Manny", "Molt", "Hopper", "Thumper"]

SITES_A = [
    site(["Munich"], "Munich"), site(["Augsburg"], "Augsburg"),
    site(["Salzburg"], "Salzburg"), site(["Bolzano"], "Bolzano"),
    site(["Innsbruck radiosonde", "Innsbruck"], "Innsbruck", side="left"),
    site(["Kolsass radiosonde"], "Kolsass"),
    site(["Oberschleißheim radiosonde"], "Oberschleißheim", side="left"),
    site(["Altenstadt radiosonde"], "Altenstadt"),
]
SITES_B = [
    site(IBK, "Innsbruck", bold=True),
    site(KOL, "Kolsass", side="left", bold=True),
    site(RAD, "Radfeld", side="left", bold=True),
]
SITES_C = [
    site(KOL, "Kolsass", side="left", bold=True),
    site(["Eggen"], "Eggen"), site(["Terfens"], "Terfens"),
    site(["Weerberg"], "Weerberg"), site(["Hochhäuser"], "Hochhäuser"),
    site(["Stanser Joch"], "Stanser Joch"), site(["Arbeser"], "Arbeser"),
    site(["Jenbach"], "Jenbach"),
]
# UAS sites: "UAS <multicopter name> (<site>)", parallel to "Lidar <site>"; the caption says that the sites
# carry the names of the multicopters (review c60, 2026-10-26: keep the nicknames).  Not exclusive: hopper
# flew from the valley-centre site from 18 Jul 19:22 to 19 Jul 07:20 UT (launch GPS of the profile files).
SITES_D = [
    site(["Manny"], "UAS Manny (crest)"),
    site(["Molt"], "UAS Molt (slope)", side="left"),
    site(["Oberberg"], "Lidar Oberberg"),
    # Hopper and the Museum lidar are 86 m apart -- resolvable at this scale, so drawn separately
    # (a nest at their mean position put Hopper 129 m off the UAS transect instead of its true 95 m)
    site(["Hopper"], "UAS Hopper (foot of sidewall)", side="left"),
    site(["Museum"], "Lidar Museum"),
    site(["Thumper"], "UAS Thumper (valley centre)"),
    site(["Klärwerk", "Radfeld HATPRO"], "Lidar + HATPRO Klärwerk", side="left", bold=True),
    site(["Radfeld"], "Radfeld TAWES"),
]

# ---------------------------------------------------------------- geometry
ASPECT = 1.2                       # width / height of every map = the WRF domain's 300 x 250 km
# zoom panels: centre (lon, lat) and width in m, in EPSG:31254; height = width / ASPECT
EXT_B = ((11.655, 47.370), 56_000)
EXT_C = ((11.683, 47.341), 18_000)
EXT_D = ((11.9224, 47.4668), 4_200)

TO_GK = Transformer.from_crs(4326, 31254, always_xy=True)
TO_LL = Transformer.from_crs(31254, 4326, always_xy=True)


def gk_bounds(ext):
    (lon, lat), w = ext
    x, y = TO_GK.transform(lon, lat)
    h = w / ASPECT
    return x - w / 2, y - h / 2, x + w / 2, y + h / 2


def gk_xy(lon, lat):
    return TO_GK.transform(lon, lat)


# ---------------------------------------------------------------- colour
# One elevation scale for all panels.  Square-root stretch so that the 500-1100 m
# of Radfeld and the 3700 m of the Hohe Tauern both keep colour contrast.
VMIN, VMAX = 100.0, 3700.0
NORM = PowerNorm(gamma=0.5, vmin=VMIN, vmax=VMAX)
_stops = [(100, "#4f7f44"), (500, "#7fa860"), (800, "#c3cf8a"), (1200, "#e6dcb0"),
          (1800, "#c8a57a"), (2400, "#9c7b62"), (3000, "#cfc8c2"), (3700, "#ffffff")]
TERRAIN = LinearSegmentedColormap.from_list(
    "alpine", [(float(NORM(v)), c) for v, c in _stops])
PC = ccrs.PlateCarree()
MS = 9          # legend glyph size, points
EDGE = "#1a1a19"
HALO = "#c9c9c4"        # ring behind every icon
LABEL_BG = "#e4e4e0"    # label background
FS_TITLE = 10


def shaded(z, dx, ve=1.0):
    ls = LightSource(azdeg=315, altdeg=40)
    zf = np.where(np.isfinite(z), z, np.nanmin(z))
    return ls.shade(zf, cmap=TERRAIN, norm=NORM, blend_mode="soft",
                    vert_exag=ve, dx=dx, dy=dx)


# ---------------------------------------------------------------- terrain readers
def read_dgm(bounds):
    with rasterio.open(DGM) as r:
        win = from_bounds(*bounds, transform=r.transform).round_offsets().round_lengths()
        z = r.read(1, window=win, masked=True).astype(float).filled(np.nan)
        wb = r.window_bounds(win)
    return z, (wb[0], wb[2], wb[1], wb[3])


def _srtm_index():
    meta = {}
    for line in (SRTM / "index").read_text().splitlines():
        if "=" in line:
            k, v = (s.strip() for s in line.split("=", 1))
            meta[k] = v
    return meta


def read_srtm_on_gk(bounds, res):
    """Sample the WPS SRTM 1" tiles bilinearly onto a regular EPSG:31254 grid."""
    m = _srtm_index()
    dx = float(m["dx"])
    lon0, lat0 = float(m["known_lon"]), float(m["known_lat"])
    tx, ty = int(m["tile_x"]), int(m["tile_y"])
    miss = int(m["missing_value"])
    x = np.arange(bounds[0] + res / 2, bounds[2], res)
    y = np.arange(bounds[3] - res / 2, bounds[1], -res)       # north -> south rows
    X, Y = np.meshgrid(x, y)
    lon, lat = TO_LL.transform(X, Y)
    fi = (lon - lon0) / dx                                   # 0-based global column
    fj = (lat - lat0) / dx                                   # 0-based global row, northward
    i0, i1 = int(np.floor(fi.min())) - 1, int(np.ceil(fi.max())) + 2
    j0, j1 = int(np.floor(fj.min())) - 1, int(np.ceil(fj.max())) + 2
    assert 0 <= j0 and j1 <= ty, "extent leaves the SRTM tile band"
    mosaic = np.empty((j1 - j0, i1 - i0), dtype=float)
    for t0 in range((i0 // tx) * tx, i1, tx):
        f = SRTM / f"{t0 + 1:05d}-{t0 + tx:05d}.{1:05d}-{ty:05d}"
        tile = np.memmap(f, dtype="<i2", mode="r", shape=(ty, tx))   # row 0 = north
        a, b = max(i0, t0), min(i1, t0 + tx)
        rows = tile[ty - j1: ty - j0, a - t0: b - t0][::-1].astype(float)  # -> northward
        mosaic[:, a - i0: b - i0] = rows
    mosaic[mosaic == miss] = np.nan
    mosaic[mosaic == -32768] = np.nan
    z = map_coordinates(mosaic, [fj - j0, fi - i0], order=1, mode="nearest")
    return z, (bounds[0], bounds[2], bounds[1], bounds[3])


# ---------------------------------------------------------------- decorations
_OUTLINE = {}


def _outline(m, n=400):
    """Unit outline of a matplotlib marker (as drawn at ms = 1), densely resampled."""
    if m not in _OUTLINE:
        st = MarkerStyle(m)
        poly = max(st.get_path().transformed(st.get_transform()).to_polygons(), key=len)
        poly = np.vstack([poly, poly[:1]])
        L = np.r_[0, np.cumsum(np.hypot(*np.diff(poly, axis=0).T))]
        t = np.linspace(0, L[-1], n, endpoint=False)
        _OUTLINE[m] = (np.c_[np.interp(t, L, poly[:, 0]), np.interp(t, L, poly[:, 1])], poly)
    return _OUTLINE[m]


_FIT = {}


def fit_scale(inner, outer):
    """Largest s such that marker `inner` at s * ms lies inside marker `outer` at ms, with
    the inner icon free to shift vertically by dy * ms: its outline then touches the outer
    one at as many points as the shapes allow.  Needed for matplotlib's '^', which is
    centred on its bounding box, not its circumcentre (in a circle: 0.709 unshifted, 0.795
    shifted up by 0.10, touching at all three vertices).  Ties -> smallest |dy|.
    Returns (s, dy)."""
    if (inner, outer) not in _FIT:
        pts, _ = _outline(inner)
        P = MplPath(_outline(outer)[1])
        best = (0.0, 0.0)
        for dy in np.arange(-0.25, 0.2501, 0.0025):
            lo, hi = 0.0, 3.0
            for _ in range(30):
                mid = 0.5 * (lo + hi)
                q = pts * mid
                q[:, 1] += dy
                lo, hi = (mid, hi) if P.contains_points(q, radius=1e-9).all() else (lo, mid)
            if lo > best[0] + 1e-4 or (abs(lo - best[0]) <= 1e-4 and abs(dy) < abs(best[1])):
                best = (lo, dy)
        _FIT[(inner, outer)] = best
    return _FIT[(inner, outer)]


def _area_perim(m):
    p = _outline(m)[1]
    x, y = p[:, 0], p[:, 1]
    return 0.5 * abs(np.dot(x[:-1], y[1:]) - np.dot(x[1:], y[:-1])), np.hypot(*np.diff(p, axis=0).T).sum()


def nest_chain(kinds):
    """Sizes (outer = 1) and vertical offsets (in outer sizes) of a filled nest: every icon
    the largest that fits inside the one beneath (fit_scale)."""
    out, s, y = [(1.0, 0.0)], 1.0, 0.0
    for a, b in zip(kinds[:-1], kinds[1:]):
        sc, dy = fit_scale(KINDS[b][0], KINDS[a][0])
        y += dy * s
        s *= sc
        out.append((s, y))
    return out


def nest_quality(kinds):
    """Thinnest visible band of a filled nest: visible area / own perimeter (outer size = 1)."""
    ch = nest_chain(kinds)
    ar = [_area_perim(KINDS[k][0])[0] * sz ** 2 for k, (sz, _) in zip(kinds, ch)]
    return min((ar[i] - (ar[i + 1] if i + 1 < len(ar) else 0.0)) / (_area_perim(KINDS[k][0])[1] * ch[i][0])
               for i, k in enumerate(kinds))


def draw_site(ax, s, to_xy, ms):
    """One site.  A single instrument: its filled icon (ms * SIZE).  Co-located instruments:
    NESTED and filled on the site's centre -- each icon the largest that fits inside the one
    beneath, so its outline touches that one's; the order is the one with the thickest
    thinnest band (every touching colour pair passes the contrast checks)."""
    xy = to_xy(s["lon"], s["lat"])
    kinds = s["kinds"]
    if len(kinds) > 1:
        kinds = list(max(itertools.permutations(kinds), key=nest_quality))
    m0 = KINDS[kinds[0]][0]
    S = ms * SIZE[m0] * GROW[len(kinds)]
    ax.plot(*xy, m0, ms=S + 2.8, mfc=HALO, mec=HALO, mew=0, zorder=6)   # halo
    for i, (k, (sz, dy)) in enumerate(zip(kinds, nest_chain(kinds))):
        m, c, _ = KINDS[k]
        tr = offset_copy(ax.transData, fig=ax.figure, x=0, y=dy * S, units="points")
        ax.plot(*xy, m, ms=sz * S, mfc=c, mec=EDGE, mew=0.8, zorder=7 + i, transform=tr)
    right = s["side"] == "right"
    half = S * np.abs(_outline(m0)[1][:, 0]).max()
    ax.annotate(s["label"], xy, xycoords="data",
                xytext=((half + 4) * (1 if right else -1), 0),
                textcoords="offset points", ha="left" if right else "right", va="center",
                fontsize=8.5 if s["bold"] else 8, fontweight="bold" if s["bold"] else "normal",
                zorder=30, bbox=dict(boxstyle="round,pad=0.15", fc=LABEL_BG, ec="none", alpha=0.85))


def scalebar(ax, length_m, label):
    """Scale bar in projected metres, lower left (all panels are in m)."""
    x0, x1 = ax.get_xlim()
    y0, y1 = ax.get_ylim()
    xs, ys = x0 + 0.05 * (x1 - x0), y0 + 0.05 * (y1 - y0)
    ax.plot([xs, xs + length_m], [ys, ys], color="k", lw=3, solid_capstyle="butt", zorder=8)
    ax.text(xs + length_m / 2, ys + 0.015 * (y1 - y0), label, ha="center", va="bottom",
            fontsize=7.5, zorder=8,
            bbox=dict(boxstyle="round,pad=0.12", fc=LABEL_BG, ec="none", alpha=0.85))


def gk_box(ax, ext, label, to_xy_from_gk):
    """Outline of a zoom panel (a rectangle in EPSG:31254) in another panel's coordinates."""
    x0, y0, x1, y1 = gk_bounds(ext)
    n = 25
    xs = np.r_[np.linspace(x0, x1, n), np.full(n, x1), np.linspace(x1, x0, n), np.full(n, x0)]
    ys = np.r_[np.full(n, y0), np.linspace(y0, y1, n), np.full(n, y1), np.linspace(y1, y0, n)]
    px, py = to_xy_from_gk(xs, ys)
    ax.plot(px, py, color="black", lw=1.7, zorder=5)
    ax.annotate(label, (px[n], py[n]), xytext=(3, -2), textcoords="offset points",
                ha="left", va="top", fontsize=9, fontweight="bold", zorder=5,
                bbox=dict(boxstyle="round,pad=0.1", fc=LABEL_BG, ec="none", alpha=0.85))


def graticule(ax, dlon, dlat, fmt):
    """Lat/lon graticule on an EPSG:31254 axes; ticks where the lines cross the frame."""
    x0, x1 = ax.get_xlim()
    y0, y1 = ax.get_ylim()
    corners = TO_LL.transform([x0, x1, x0, x1], [y0, y0, y1, y1])
    lons = np.arange(np.floor(min(corners[0]) / dlon) * dlon, max(corners[0]) + dlon, dlon)
    lats = np.arange(np.floor(min(corners[1]) / dlat) * dlat, max(corners[1]) + dlat, dlat)
    tb = np.linspace(min(corners[1]) - dlat, max(corners[1]) + dlat, 200)
    tl = np.linspace(min(corners[0]) - dlon, max(corners[0]) + dlon, 200)
    xt, xl, yt, yl = [], [], [], []
    for lo in lons:
        x, y = TO_GK.transform(np.full_like(tb, lo), tb)
        ax.plot(x, y, color="k", lw=0.4, ls=":", alpha=0.45, zorder=2)
        xb = np.interp(y0, y, x)
        if x0 < xb < x1:
            xt.append(xb); xl.append(fmt(lo) + "°E")
    for la in lats:
        x, y = TO_GK.transform(tl, np.full_like(tl, la))
        ax.plot(x, y, color="k", lw=0.4, ls=":", alpha=0.45, zorder=2)
        yb = np.interp(x0, x, y)
        if y0 < yb < y1:
            yt.append(yb); yl.append(fmt(la) + "°N")
    ax.set_xticks(xt, xl, fontsize=7)
    ax.set_yticks(yt, yl, fontsize=7)
    ax.tick_params(length=2)
    ax.set_xlim(x0, x1)
    ax.set_ylim(y0, y1)


def gk_panel(ax, ext, z, extent, dx):
    ax.imshow(shaded(z, dx), extent=extent, origin="upper", interpolation="bilinear", zorder=1)
    b = gk_bounds(ext)
    ax.set_xlim(b[0], b[2])
    ax.set_ylim(b[1], b[3])
    ax.set_aspect("equal")


# ---------------------------------------------------------------- figure
def main(preview=None):
    with netCDF4.Dataset(WRFINPUT) as d:
        hgt = d["HGT"][0].astype(float)
        lat = d["XLAT"][0]
        lon = d["XLONG"][0]
        lcc = ccrs.LambertConformal(central_longitude=d.STAND_LON,
                                    central_latitude=d.MOAD_CEN_LAT,
                                    standard_parallels=(d.TRUELAT1, d.TRUELAT2),
                                    globe=ccrs.Globe(ellipse=None, semimajor_axis=6370000,
                                                     semiminor_axis=6370000))
        dxm = d.DX

    # identical axes boxes, laid out in inches
    W = 5.45; H = W / ASPECT
    L, GAPX, R = 0.62, 0.78, 0.15
    T, GAPY, B = 0.32, 0.62, 1.42
    FW, FH = L + 2 * W + GAPX + R, T + 2 * H + GAPY + B
    fig = plt.figure(figsize=(FW, FH))

    def box(col, row):
        x = L + col * (W + GAPX)
        y = B + (1 - row) * (H + GAPY)
        return [x / FW, y / FH, W / FW, H / FH]

    # (a) domain --------------------------------------------------------------
    ax = fig.add_axes(box(0, 0), projection=lcc)
    xy = lcc.transform_points(PC, lon, lat)
    ext_a = (xy[0, 0, 0] - dxm / 2, xy[0, -1, 0] + dxm / 2, xy[0, 0, 1] - dxm / 2, xy[-1, 0, 1] + dxm / 2)
    ax.imshow(shaded(hgt, dxm), extent=ext_a, origin="lower", transform=lcc,
              interpolation="nearest", zorder=1)
    ax.set_extent(ext_a, crs=lcc)
    ax.add_feature(cfeature.BORDERS.with_scale("10m"), lw=0.7, edgecolor="k", alpha=0.35, zorder=3)
    gl = ax.gridlines(draw_labels=True, lw=0.4, color="k", alpha=0.35, ls=":",
                      x_inline=False, y_inline=False)
    gl.top_labels = gl.right_labels = False
    gl.xlocator = matplotlib.ticker.MultipleLocator(1.0)
    gl.ylocator = matplotlib.ticker.MultipleLocator(0.5)
    gl.xlabel_style = gl.ylabel_style = dict(size=7)
    gl.rotate_labels = False
    to_lcc = lambda lo, la: lcc.transform_point(lo, la, PC)
    for st in SITES_A:
        draw_site(ax, st, to_lcc, 7.5)

    def gk2lcc(x, y):
        lo, la = TO_LL.transform(x, y)
        p = lcc.transform_points(PC, np.asarray(lo), np.asarray(la))
        return p[:, 0], p[:, 1]

    gk_box(ax, EXT_B, "b", gk2lcc)
    scalebar(ax, 50_000, "50 km")
    # the note "only the radiosonde sites used here are shown" moved to the caption (review c60, 2026-10-26);
    # all four drawn sites lie inside the domain, while Hohenpeissenberg, Sterzing and Bolzano are not drawn
    ax.set_title("(a) WRF domain — model terrain, 600 × 500 cells, Δx = 500 m",
                 fontsize=FS_TITLE, loc="left")

    # (b) Lower Inn Valley ----------------------------------------------------
    ax = fig.add_axes(box(1, 0))
    z, e = read_srtm_on_gk(gk_bounds(EXT_B), 50.0)
    gk_panel(ax, EXT_B, z, e, 50.0)
    graticule(ax, 0.1, 0.1, lambda v: f"{v:.1f}")
    ident = lambda x, y: (x, y)
    gk_box(ax, EXT_C, "c", ident)
    gk_box(ax, EXT_D, "d", ident)
    for st in SITES_B:
        draw_site(ax, st, gk_xy, 7.5)
    scalebar(ax, 10_000, "10 km")
    ax.set_title("(b) Lower Inn Valley — SRTM 1″ (30 m)", fontsize=FS_TITLE, loc="left")

    # (c) Kolsass -------------------------------------------------------------
    ax = fig.add_axes(box(0, 1))
    z, e = read_dgm(gk_bounds(EXT_C))
    gk_panel(ax, EXT_C, z[::2, ::2], e, 20.0)
    graticule(ax, 0.05, 0.05, lambda v: f"{v:.2f}")
    for st in SITES_C:
        draw_site(ax, st, gk_xy, 9)
    scalebar(ax, 2000, "2 km")
    ax.set_title("(c) Kolsass (i-Box) — DGM Tirol 10 m", fontsize=FS_TITLE, loc="left")

    # (d) Radfeld -------------------------------------------------------------
    ax = fig.add_axes(box(1, 1))
    z, e = read_dgm(gk_bounds(EXT_D))
    gk_panel(ax, EXT_D, z, e, 10.0)
    graticule(ax, 0.01, 0.01, lambda v: f"{v:.2f}")
    for st in SITES_D:
        draw_site(ax, st, gk_xy, 9)
    scalebar(ax, 500, "500 m")
    ax.set_title("(d) Radfeld supersite — DGM Tirol 10 m", fontsize=FS_TITLE, loc="left")

    # shared colour bar (under the left column) and legend (under the right) -----
    cax = fig.add_axes([L / FW, 0.70 / FH, W / FW, 0.13 / FH])
    sm = plt.cm.ScalarMappable(cmap=TERRAIN, norm=NORM)
    cb = fig.colorbar(sm, cax=cax, orientation="horizontal",
                      ticks=[200, 500, 1000, 1500, 2000, 2500, 3000, 3500])
    cb.set_label("Elevation (m MSL), all panels", fontsize=8.5)
    cb.ax.tick_params(labelsize=7.5)

    handles = [Line2D([], [], marker=m, ms=MS * SIZE[m], mfc=c, mec=EDGE, mew=0.9, ls="none", label=l)
               for m, c, l in KINDS.values()]
    fig.legend(handles=handles, loc="upper center", ncol=2, fontsize=8, frameon=False,
               bbox_to_anchor=((L + 1.5 * W + GAPX) / FW, 1.24 / FH),
               handletextpad=0.4, columnspacing=1.2, labelspacing=0.45)
    fig.text(0.5, 0.06 / FH,
             "Nested icons = co-located instruments, all centred on the site.",
             ha="center", va="bottom", fontsize=7.5, color="#444441")

    fig.savefig(OUT)
    print(f"wrote {OUT}")
    if preview:
        fig.savefig(preview, dpi=150)
        print(f"preview {preview}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="also write a PNG preview here (not into figures/)")
    main(ap.parse_args().preview)
