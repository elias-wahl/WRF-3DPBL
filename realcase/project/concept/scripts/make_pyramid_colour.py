#!/usr/bin/env python3
"""Colour-coded twin of the vertical pyramid page (Elias, 2026-09-21): a NEW document, generated from the
GENERATED vertical file (default pbl_assumptions_pyramid_split_vertical.tex) -- run make_pyramid_vertical.py first.

  * every block gets its own fill: the hue runs through the rainbow from the top of the page to the bottom
    (block centre), the shade lightens from the premises (left) to the formalism (right) -- a colour names a place;
  * the scheme frames (Goger port red, 3D closure purple) are dropped;
  * a grey tab in every block's top-left corner carries its shortcut: P1.. premises, C1.. concepts, F1.. formal
    statements, numbered from the top of the page;
  * the recorded leans (\\lean{child}{parent}, the dependences the contact rule cannot draw; in the master ordered by
    importance within a child) become filled corner triangles in the CHILD block, in the PARENT's colour: at most
    three, the most important at the bottom left, then counter-clockwise (bottom right, top right); each carries the
    parent's shortcut.
Colours in OKLCH (perceptually even lightness steps), gamut-clipped by lowering the chroma.
Usage: python3 scripts/make_pyramid_colour.py [VERTICAL.tex]   -> VERTICAL_colour.tex ; then tectonic it.
"""
import re, sys, pathlib, math

SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("pbl_assumptions_pyramid_split_vertical.tex")
DST = SRC.with_name(SRC.stem + "_colour.tex")
LIGHT = {"ground": 0.70, "hyp": 0.82, "row": 0.93}   # OKLab L per column: dark left, light right (Elias 2026-09-21)
CHROMA = 0.11
HUE0, HUE1 = 25.0, 320.0                              # top of the page -> bottom (red -> violet)
LEG = 0.40                                            # triangle leg (cm); holds the parent's shortcut
TABW, TABH = 0.46, 0.25                               # shortcut tab (cm)
MAXTRI = 3
PREFIX = {"ground": "P", "hyp": "C", "row": "F"}
PX1, NEWPX1 = 2.5, 3.0     # the premise column is widened for the tabs (the page margins pay: 9 mm -> 6 mm)
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

# ---- widen the premise column: x <= PX1 scaled, everything right of it shifted; contacts are preserved ----
def rx(x):
    x = float(x); return x * NEWPX1 / PX1 if x <= PX1 + 1e-6 else x + (NEWPX1 - PX1)
fmt = lambda v: f"{v:.3f}"
in_pic = False
for k, ln in enumerate(lines):
    if ln.startswith("\\begin{tikzpicture}"): in_pic = True; continue
    if ln.startswith("\\end{tikzpicture}"): in_pic = False
    if not in_pic: continue
    if ln.startswith("\\pbv{") or ln.startswith("\\pbh{"):
        name = ln[:ln.index("{")]; a, end = take_args(ln, len(name), 4)
        a[0], a[1] = fmt(rx(a[0])), fmt(rx(a[1]))
        ln = name + "".join("{" + x + "}" for x in a) + ln[end:]
    elif ln.startswith("\\pbunion{"):
        a, end = take_args(ln, len("\\pbunion"), 7)
        a[1] = fmt(rx(a[1])); a[3] = f"{float(a[3]) * NEWPX1 / PX1:.2f}"
        a[5] = ",".join("/".join([fmt(rx(q[0])), fmt(rx(q[1])), q[2], q[3]]) for q in (pc.split("/") for pc in a[5].split(",")))
        a[6] = re.sub(r"\(([-\d.]+),([-\d.]+)\)", lambda m: f"({fmt(rx(m.group(1)))},{m.group(2)})", a[6])
        ln = "\\pbunion" + "".join("{" + x + "}" for x in a) + ln[end:]
    elif ln.startswith("\\node"):
        ln = re.sub(r" at \(([-\d.]+),([-\d.]+)\)", lambda m: f" at ({fmt(rx(m.group(1)))},{m.group(2)})", ln)
    lines[k] = ln
blocks = []          # dict(title, tier, rect=(x0,x1,y0,y1) of the body, line index)
for k, ln in enumerate(lines):
    if ln.startswith("\\pbv{"):
        a, _ = take_args(ln, len("\\pbv"), 7)
        x0, x1, y0, y1 = map(float, a[:4]); style, text = a[4], a[5]
        blocks.append(dict(title=re.match(r"\\textbf\{(.*?)\}", text).group(1), tier=TIER[style], rect=(x0, x1, y0, y1), k=k, kind="pbv",
                           tab=(x0, y1), top=y1))
    elif ln.startswith("\\pbunion{"):
        a, _ = take_args(ln, len("\\pbunion"), 7)
        style, text = a[0], a[4]
        pcs = [tuple(map(float, pc.split("/"))) for pc in a[5].split(",")]
        x0, x1, y0, y1 = pcs[0]
        top = max(pcs, key=lambda q: q[3])                       # the topmost piece carries the tab
        blocks.append(dict(title=re.match(r"\\textbf\{(.*?)\}", text).group(1), tier=TIER[style], rect=(x0, x1, y0, y1), k=k, kind="pbunion",
                           tab=(top[0], top[3]), top=top[3]))
ytop = max(b["rect"][3] for b in blocks); ybot = min(b["rect"][2] for b in blocks)
by_title = {b["title"]: b for b in blocks}
# shortcuts: P/C/F + rank from the top of the page within the column
for st, pre in PREFIX.items():
    col = sorted((b for b in blocks if b["tier"] == TIER[st]), key=lambda b: -b["top"])
    for n, b in enumerate(col, 1): b["code"] = f"{pre}{n}"
tabs = []
for b in blocks:
    tx, ty = b["tab"]
    tabs.append(f"\\fill[black!16] ({tx:.3f},{ty - TABH:.3f}) rectangle ({tx + TABW:.3f},{ty:.3f}); \\draw[black!60, line width=0.25pt] ({tx:.3f},{ty - TABH:.3f}) rectangle ({tx + TABW:.3f},{ty:.3f});"
                f" \\node[inner sep=0pt, font=\\fontsize{{5.5}}{{6}}\\selectfont\\bfseries] at ({tx + TABW / 2:.3f},{ty - TABH / 2:.3f}) {{{b['code']}}}; % {b['title']}")
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
tri = []; per_child = {}; dropped = []
for c, p in leans: per_child.setdefault(c, []).append(p)
CORNER = [("BL", lambda r: (r[0], r[2], LEG, LEG)), ("BR", lambda r: (r[1], r[2], -LEG, LEG)), ("TR", lambda r: (r[1], r[3], -LEG, -LEG))]
for c, ps in per_child.items():
    cb = by_title[c]
    for n, p in enumerate(ps):
        if n >= MAXTRI: dropped.append((c, p)); continue
        cx, cy, dx, dy = CORNER[n][1](cb["rect"]); pb = by_title[p]
        tri.append(f"\\filldraw[fill={pb['col']}, draw=black, line width=0.3pt] ({cx:.3f},{cy:.3f}) -- ({cx + dx:.3f},{cy:.3f}) -- ({cx:.3f},{cy + dy:.3f}) -- cycle;"
                   f" \\node[inner sep=0pt, font=\\fontsize{{4}}{{4.5}}\\selectfont\\bfseries] at ({cx + 0.30 * dx:.3f},{cy + 0.30 * dy:.3f}) {{{pb["code"]}}}; % {c} <- {p} ({CORNER[n][0]})")
for c, p in dropped: print(f"  not drawn (fourth or later lean): {c} <- {p}")
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
doc = doc.replace("\\end{tikzpicture}", "% ---- shortcut tabs ----\n" + "\n".join(tabs) + "\n% ---- corner triangles: the recorded leans, child block, parent colour ----\n" + "\n".join(tri) + "\n\\end{tikzpicture}", 1)
doc = doc.replace("\\begin{document}", "% ---- block colours (OKLCH: hue by vertical position, lightness by column) ----\n" + "\n".join(defs) + "\n\\begin{document}", 1)
# page-1 legend
old = re.search(r"\{\\footnotesize Left, dark grey: the premises.*?Rules and reading on the next page\.\\par\}", doc, re.S).group(0)
new = (r"{\footnotesize Left the premises, middle the concepts, right the formal statements of the level-2.5 closure; a block touches at its "
       r"left exactly the blocks it relies on. \textbf{Colour names a place}: hue by height on the page, red at the top to violet at the bottom, "
       r"the shade lightening from left to right; the grey tab is the block's shortcut (P, C, F from the top). \textbf{A corner triangle} marks a "
       r"dependence no contact can show, in the colour and with the shortcut of the block depended on: the most important at the bottom left, then "
       r"counter-clockwise, three at most. Dashed: the formal statements at $\Delta = 500$~m in the Inn Valley; far right the schemes \textcolor{cMYNN}{\textbf{MYNN as run}}, "
       r"\textcolor{cGXIX}{\textbf{G19 port}}, \textcolor{cAPPROX}{\textbf{3D-APPROX}}, \textcolor{cFULL}{\textbf{3D-FULL}}: \gK{} implements, "
       r"\gP{} partly, \gD{} drops. Rules, reading, triangles overleaf.\par}")
doc = doc.replace(old, new)
doc = doc.replace("\\usepackage[a4paper,margin=9mm,top=9mm,bottom=9mm]{geometry}", "\\usepackage[a4paper,margin=6mm,top=9mm,bottom=9mm]{geometry}")
assert "margin=6mm" in doc
doc = doc.replace("Dark grey, the ground (left column): ", "The ground (left column, darkest shade): ")
doc = doc.replace("Light grey, the\nconcepts (middle column):", "The\nconcepts (middle column, middle shade):")
doc = doc.replace("White, the formalism (right column):", "The formalism (right column, lightest shade):")
# the Frames paragraph -> the list of triangles
fr = re.search(r"\\vspace\{0\.2ex\}\n\{\\footnotesize\\textbf\{Frames\.\}.*?\\par\}", doc, re.S)
assert fr
order = sorted(per_child, key=lambda c: (-by_title[c]["tier"], -(by_title[c]["rect"][2] + by_title[c]["rect"][3])))
code = lambda t: f"{by_title[t]['code']} {t}"
items = "; ".join(f"\\textbf{{{code(c)}}}: " + ", ".join(code(p) + (" (not drawn)" if (c, p) in dropped else "") for p in per_child[c]) for c in order)
trip = (r"\vspace{0.2ex}" "\n" r"{\footnotesize\textbf{Triangles.} The dependences recorded in the source that no contact can show, by the block that "
        r"carries the triangle (formalism first, top of the page first), in the order of importance, bottom left first, then counter-clockwise; "
        r"the block leaned on gives the triangle its colour; a fourth or fifth lean is listed but not drawn: " + items + r". "
        r"The scheme frames of the other pages are left off this one.\par}")
doc = doc[:fr.start()] + trip + doc[fr.end():]
doc = doc.replace("VERTICAL version\n%  GENERATED by scripts/make_pyramid_vertical.py from",
                  f"VERTICAL, COLOUR-CODED version\n%  GENERATED by scripts/make_pyramid_colour.py from {SRC.name} (itself generated by make_pyramid_vertical.py from")
doc = re.sub(r"\{\\small Vertical page of the split variant: (.*?)\}", r"{\\small Colour-coded page of the split variant, 2026-09-21: \1}", doc, count=1)
DST.write_text(doc)
print("wrote", DST, "blocks:", len(blocks), "triangles:", len(tri))
