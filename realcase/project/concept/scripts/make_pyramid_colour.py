#!/usr/bin/env python3
"""Colour-coded twin of the vertical pyramid page (Elias, 2026-09-21): a NEW document, generated from the
GENERATED vertical file (default pbl_assumptions_pyramid_split_vertical.tex) -- run make_pyramid_vertical.py first.

  * every block gets its own fill: the hue runs through the rainbow from the top of the page to the bottom
    (block centre), the shade darkens from the premises (left) to the formalism (right) -- a colour names a place;
  * the scheme frames (Goger port red, 3D closure purple) are dropped;
  * every recorded lean (\\lean{child}{parent}, the dependences the contact rule cannot draw) becomes a filled
    corner triangle in the CHILD block, in the PARENT's colour: left corners point to the previous column, right
    corners to the same column; upper corners to a parent above, lower corners to one below; several in one corner
    stack along the edge.
Colours in OKLCH (perceptually even lightness steps), gamut-clipped by lowering the chroma.
Usage: python3 scripts/make_pyramid_colour.py [VERTICAL.tex]   -> VERTICAL_colour.tex ; then tectonic it.
"""
import re, sys, pathlib, math

SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("pbl_assumptions_pyramid_split_vertical.tex")
DST = SRC.with_name(SRC.stem + "_colour.tex")
LIGHT = {"ground": 0.93, "hyp": 0.82, "row": 0.70}   # OKLab L per column: light left, dark right
CHROMA = 0.11
HUE0, HUE1 = 25.0, 320.0                              # top of the page -> bottom (red -> violet)
LEG = 0.26                                            # triangle leg (cm)
GAP = 0.05                                            # between stacked triangles
TIER = {"ground": 0, "hyp": 1, "row": 2}

def take_args(s, i, n):
    args = []
    for _ in range(n):
        assert s[i] == "{", s[i:i + 20]
        d, j = 0, i
        while True:
            if s[j] == "{": d += 1
            elif s[j] == "}":
                d -= 1
                if d == 0: break
            j += 1
        args.append(s[i + 1:j]); i = j + 1
    return args, i

def oklch_to_srgb(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    gam = lambda c: 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return tuple(gam(c) for c in (r, g, bb))

def colour(L, h):
    C = CHROMA
    while C > 0:
        rgb = oklch_to_srgb(L, C, h)
        if all(-1e-6 <= c <= 1 + 1e-6 for c in rgb): return tuple(min(1, max(0, c)) for c in rgb)
        C -= 0.005
    return oklch_to_srgb(L, 0, h)

src = SRC.read_text()
lines = src.split("\n")
blocks = []          # dict(title, tier, rect=(x0,x1,y0,y1) of the body, line index)
for k, ln in enumerate(lines):
    if ln.startswith("\\pbv{"):
        a, _ = take_args(ln, len("\\pbv"), 7)
        x0, x1, y0, y1 = map(float, a[:4]); style, text = a[4], a[5]
        blocks.append(dict(title=re.match(r"\\textbf\{(.*?)\}", text).group(1), tier=TIER[style], rect=(x0, x1, y0, y1), k=k, kind="pbv"))
    elif ln.startswith("\\pbunion{"):
        a, _ = take_args(ln, len("\\pbunion"), 7)
        style, text = a[0], a[4]
        x0, x1, y0, y1 = map(float, a[5].split(",")[0].split("/"))
        blocks.append(dict(title=re.match(r"\\textbf\{(.*?)\}", text).group(1), tier=TIER[style], rect=(x0, x1, y0, y1), k=k, kind="pbunion"))
ytop = max(b["rect"][3] for b in blocks); ybot = min(b["rect"][2] for b in blocks)
by_title = {b["title"]: b for b in blocks}
# colours
defs = []
for i, b in enumerate(blocks):
    yc = (b["rect"][2] + b["rect"][3]) / 2
    t = (ytop - yc) / (ytop - ybot)                 # 0 at the top of the page, 1 at the bottom
    L = list(LIGHT.values())[b["tier"]]
    r, g, bl = colour(L, HUE0 + (HUE1 - HUE0) * t)
    b["col"] = f"blk{i}"
    defs.append(f"\\definecolor{{blk{i}}}{{rgb}}{{{r:.4f},{g:.4f},{bl:.4f}}} % {b['title']}")
# leans -> triangles
leans = []
for ln in lines:
    if ln.startswith("\\lean{"):
        (c, p), _ = take_args(ln, len("\\lean"), 2); leans.append((c, p))
missing = [n for c, p in leans for n in (c, p) if n not in by_title]
assert not missing, missing
tri = []; used = {}     # (block, corner) -> count
per_child = {}
for c, p in leans:
    cb, pb = by_title[c], by_title[p]
    x0, x1, y0, y1 = cb["rect"]
    ycc, ycp = (y0 + y1) / 2, (pb["rect"][2] + pb["rect"][3]) / 2
    side = "L" if pb["tier"] < cb["tier"] else "R"
    vert = "T" if ycp > ycc else "B"
    n = used.get((c, side + vert), 0); used[(c, side + vert)] = n + 1
    off = n * (LEG + GAP)
    cx = (x0 + off) if side == "L" else (x1 - off)
    cy = y1 if vert == "T" else y0
    dx = LEG if side == "L" else -LEG
    dy = -LEG if vert == "T" else LEG
    tri.append(f"\\filldraw[fill={pb['col']}, draw=black, line width=0.3pt] ({cx:.3f},{cy:.3f}) -- ({cx + dx:.3f},{cy:.3f}) -- ({cx:.3f},{cy + dy:.3f}) -- cycle; % {c} <- {p}")
    per_child.setdefault(c, []).append(p)
assert cb  # noqa
for (c, corner), n in used.items():
    if n > 1: print(f"  stacked {n} in corner {corner} of {c}")
# rewrite the lines
out = []
for k, ln in enumerate(lines):
    if ln.startswith("\\hlv{"): continue
    if ln.startswith("\\pbv{"):
        b = next(b for b in blocks if b["k"] == k); a, _ = take_args(ln, len("\\pbv"), 7)
        a[4] = f"bk, fill={b['col']}"
        ln = "\\pbv" + "".join("{" + x + "}" for x in a)
    elif ln.startswith("\\pbunion{"):
        b = next(b for b in blocks if b["k"] == k); a, _ = take_args(ln, len("\\pbunion"), 7)
        a[0] = b["col"]
        ln = "\\pbunion" + "".join("{" + x + "}" for x in a)
    out.append(ln)
doc = "\n".join(out)
# macros: union pieces filled with the block's colour; a plain border style; triangles after the blocks
doc = doc.replace(r"\renewcommand{\pbunion}[7]{\foreach \ux/\uX/\uy/\uY in {#6} {\fill[black!22] (\ux,\uy) rectangle (\uX,\uY);}"
                  "\n  \\draw[#1, fill=none] #7 -- cycle;",
                  r"\renewcommand{\pbunion}[7]{\foreach \ux/\uX/\uy/\uY in {#6} {\fill[#1] (\ux,\uy) rectangle (\uX,\uY);}"
                  "\n  \\draw[bk] #7 -- cycle;")
assert doc.count("\\fill[#1]") == 1
doc = doc.replace("  hecto/.style={draw=black!55, dashed, line width=0.4pt, fill=white}]",
                  "  bk/.style={draw, line width=0.4pt},\n  hecto/.style={draw=black!55, dashed, line width=0.4pt, fill=white}]")
doc = doc.replace("\\end{tikzpicture}", "% ---- corner triangles: the recorded leans, child block, parent colour ----\n" + "\n".join(tri) + "\n\\end{tikzpicture}", 1)
doc = doc.replace("\\begin{document}", "% ---- block colours (OKLCH: hue by vertical position, lightness by column) ----\n" + "\n".join(defs) + "\n\\begin{document}", 1)
# page-1 legend
old = re.search(r"\{\\footnotesize Left, dark grey: the premises.*?Rules and reading on the next page\.\\par\}", doc, re.S).group(0)
new = (r"{\footnotesize Left the premises, middle the concepts of turbulence theory, right the formal statements of the level-2.5 closure; "
       r"a block touches at its left exactly the blocks it relies on. \textbf{Colour names a place}: the hue by height on the page, red at the top "
       r"to violet at the bottom, the shade darkening from left to right. \textbf{A corner triangle} marks a dependence no contact can show, in "
       r"the colour of the block depended on: left corners point to the previous column, right corners to the same column, upper to a block above, "
       r"lower to one below. Dashed: each formal statement at $\Delta = 500$~m over the Inn Valley; far right the schemes "
       r"\textcolor{cMYNN}{\textbf{MYNN as run}}, \textcolor{cGXIX}{\textbf{G19 port}}, \textcolor{cAPPROX}{\textbf{3D-APPROX}}, "
       r"\textcolor{cFULL}{\textbf{3D-FULL}}, \gK{} implements, \gP{} partly, \gD{} drops. Rules, reading and the list of triangles overleaf.\par}")
doc = doc.replace(old, new)
doc = doc.replace("Dark grey, the ground (left column): ", "The ground (left column, lightest shade): ")
doc = doc.replace("Light grey, the\nconcepts (middle column):", "The\nconcepts (middle column, middle shade):")
doc = doc.replace("White, the formalism (right column):", "The formalism (right column, darkest shade):")
# the Frames paragraph -> the list of triangles
fr = re.search(r"\\vspace\{0\.2ex\}\n\{\\footnotesize\\textbf\{Frames\.\}.*?\\par\}", doc, re.S)
assert fr
order = sorted(per_child, key=lambda c: (-by_title[c]["tier"], -(by_title[c]["rect"][2] + by_title[c]["rect"][3])))
items = "; ".join(f"\\textbf{{{c}}}: {', '.join(per_child[c])}" for c in order)
trip = (r"\vspace{0.2ex}" "\n" r"{\footnotesize\textbf{Triangles.} The dependences recorded in the source that no contact can show, by the block that "
        r"carries the triangle (formalism first, top of the page first; the block leaned on in the triangle's colour on the page): " + items + r". "
        r"The scheme frames of the other pages are left off this one.\par}")
doc = doc[:fr.start()] + trip + doc[fr.end():]
doc = doc.replace("VERTICAL version\n%  GENERATED by scripts/make_pyramid_vertical.py from",
                  f"VERTICAL, COLOUR-CODED version\n%  GENERATED by scripts/make_pyramid_colour.py from {SRC.name} (itself generated by make_pyramid_vertical.py from")
doc = re.sub(r"\{\\small Vertical page of the split variant: (.*?)\}", r"{\\small Colour-coded page of the split variant, 2026-09-21: \1}", doc, count=1)
DST.write_text(doc)
print("wrote", DST, "blocks:", len(blocks), "triangles:", len(tri))
