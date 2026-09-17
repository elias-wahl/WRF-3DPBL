#!/usr/bin/env python3
"""Generate pbl_assumptions_pyramid_radial.tex: the pyramid's blocks as a radial map. Premises on the inner
ring, concepts on the middle ring, formal statements on the outer ring; straight lines for every dependency
(contacts from the block geometry, thick; leans from the \lean entries, thin arrows). Each block sits at the
mean angle of its parents, so related blocks cluster. Run from concept/ after editing the horizontal source."""
import re, math, pathlib, sys
SRC = pathlib.Path("pbl_assumptions_pyramid.tex"); DST = pathlib.Path("pbl_assumptions_pyramid_radial.tex")
s = SRC.read_text(); nc = "\n".join(l for l in s.splitlines() if not l.lstrip().startswith("%"))
def take_args(t, i, n):
    args = []
    for _ in range(n):
        assert t[i] == "{"; d = 0; j = i
        while True:
            if t[j] == "{": d += 1
            elif t[j] == "}":
                d -= 1
                if d == 0: break
            j += 1
        args.append(t[i+1:j]); i = j + 1
    return args, i
t0 = s.index("\\begin{tikzpicture}"); t1 = s.index("\\end{tikzpicture}"); body = s[t0:t1]
blocks = []   # dict(title, style, rects=[(x0,x1,y0,y1)], key=(x0,x1,y0) of the main rect)
for m in re.finditer(r"\\(pbunion|pbf|pb)\{", body):
    kind = m.group(1)
    if kind == "pbunion":
        (style, tx, ty, tw, text, pieces, outline), _ = take_args(body, m.end() - 1, 7)
        rects = [tuple(map(float, pc.split("/"))) for pc in pieces.split(",")]
    else:
        args, _ = take_args(body, m.end() - 1, 7 if kind == "pbf" else 6)
        style, text = args[4], args[5]; rects = [tuple(map(float, args[:4]))]
    title = re.match(r"\\textbf\{(.*?)\}\\\\", text + "\\\\").group(1)
    blocks.append(dict(title=title, style=style, rects=rects, x=min(r[0] for r in rects)))
tier = {"ground": 0, "hyp": 1, "row": 2}
byt = {b["title"]: b for b in blocks}; ids = {b["title"]: f"n{i}" for i, b in enumerate(blocks)}
def touches(c, p):
    for (cx0, cx1, cy0, cy1) in c["rects"]:
        for (px0, px1, py0, py1) in p["rects"]:
            if abs(cy0 - py1) < 1e-6 and min(cx1, px1) - max(cx0, px0) > 0.02: return True
    return False
contacts = [(c["title"], p["title"]) for c in blocks for p in blocks
            if tier[c["style"]] == tier[p["style"]] + 1 and touches(c, p)]
leans = []
for m in re.finditer(r"\\lean\{", nc):
    (a, b), _ = take_args(nc, m.end() - 1, 2)
    for t in (a, b):
        if t not in byt: sys.exit(f"unknown block in \\lean: {t!r}")
    leans.append((a, b))
frames = {}
for m in re.finditer(r"\\hl\{", body):
    (x0, x1, y0, y1, col, ins), _ = take_args(body, m.end() - 1, 6)
    for b in blocks:
        r = b["rects"][0]
        if abs(r[0] - float(x0)) < 1e-6 and abs(r[1] - float(x1)) < 1e-6 and abs(r[2] - float(y0)) < 1e-6:
            frames.setdefault(b["title"], set()).add(col)
# ---- angles: premises evenly, clockwise from the top in ground order; children at the mean angle of parents
R = {0: 4.4, 1: 8.5, 2: 12.0}; W = {0: 2.4, 1: 2.0, 2: 2.0}
ang = {}
ground = sorted((b for b in blocks if b["style"] == "ground"), key=lambda b: b["x"])
for i, b in enumerate(ground): ang[b["title"]] = 90.0 - 360.0 * i / len(ground)
def cmean(pairs):
    sx = sum(w * math.cos(math.radians(a)) for a, w in pairs); sy = sum(w * math.sin(math.radians(a)) for a, w in pairs)
    return math.degrees(math.atan2(sy, sx))
def spread(names, r, w):
    """enforce a minimum angular separation on a ring, keeping the circular order"""
    dmin = math.degrees((w + 0.35) / r)
    a = sorted(((ang[n] % 360.0), n) for n in names)
    # start after the largest gap so the wrap-around gap absorbs the spreading
    gaps = [((a[(i+1) % len(a)][0] - a[i][0]) % 360.0, i) for i in range(len(a))]
    start = (max(gaps)[1] + 1) % len(a); a = a[start:] + a[:start]
    base = a[0][0]; pos = [((x - base) % 360.0) for x, _ in a]
    for _ in range(4):
        for i in range(1, len(pos)):
            if pos[i] - pos[i-1] < dmin: pos[i] = pos[i-1] + dmin
        if pos[-1] > 360.0 - dmin: pos = [p * (360.0 - dmin) / pos[-1] for p in pos]
    for (x, n), p in zip(a, pos): ang[n] = (base + p) % 360.0
for tr in (1, 2):
    names = [b["title"] for b in blocks if tier[b["style"]] == tr]
    for n in names:
        pairs = [(ang[p], 1.0) for c, p in contacts if c == n and p in ang] + [(ang[p], 0.35) for c, p in leans if c == n and p in ang]
        ang[n] = cmean(pairs) if pairs else 0.0
    spread(names, R[tr], W[tr])
# ---- emit
nodes, fr, edges = [], [], []
fill = {"ground": "black!22", "hyp": "black!9", "row": "white"}
for b in blocks:
    tr = tier[b["style"]]
    nodes.append(f"\\node[nd, fill={fill[b['style']]}, text width={W[tr]-0.25:.2f}cm] ({ids[b['title']]}) at ({ang[b['title']]:.2f}:{R[tr]}) {{\\textbf{{{b['title']}}}}};")
for title, cols in frames.items():
    n = ids[title]
    if "cFULL" in cols: fr.append(f"\\draw[cFULL, line width=1.1pt] ($({n}.south west)+(-0.07,-0.07)$) rectangle ($({n}.north east)+(0.07,0.07)$);")
    if "cGXIX" in cols: fr.append(f"\\draw[cGXIX, line width=1.1pt] ($({n}.south west)+(-0.16,-0.16)$) rectangle ($({n}.north east)+(0.16,0.16)$);")
for c, p in contacts: edges.append(f"\\draw[contact] ({ids[c]}) -- ({ids[p]});")
for c, p in leans:
    sty = "leansame" if tier[byt[c]["style"]] == tier[byt[p]["style"]] else "lean"
    edges.append(f"\\draw[{sty}] ({ids[c]}) -- ({ids[p]});")
pre = s[:s.index("\\begin{document}")]
pre = re.sub(r"% =+\n%  The assumptions.*?% =+\n", "", pre, count=1, flags=re.S)
pre = pre.replace("\\usepackage[a4paper,landscape,margin=10mm,top=7mm,bottom=7mm]{geometry}", "\\usepackage[paperwidth=42cm,paperheight=29.7cm,margin=8mm]{geometry}")
pre = pre.replace("\\usepackage{tikz}", "\\usepackage{tikz}\n\\usetikzlibrary{arrows.meta,calc,backgrounds}")
doc = """% =============================================================================
%  The assumptions of a one-dimensional PBL closure -- RADIAL map (A3 landscape)
%  GENERATED by scripts/make_pyramid_radial.py from pbl_assumptions_pyramid.tex. Premises inside, concepts
%  in the middle, formal statements outside; every block at the mean angle of its parents; straight lines:
%  thick = the pyramid's contacts (from the block geometry), thin blue arrows = the \\lean entries.
% =============================================================================
""" + pre + r"""
\definecolor{cLean}{HTML}{1F5FA8}
\tikzset{nd/.style={draw, line width=0.4pt, align=center, font=\scriptsize, inner sep=3pt, minimum height=0.9cm},
  contact/.style={black!45, line width=1.1pt},
  lean/.style={cLean, line width=0.5pt, -{Stealth[length=4pt, width=3pt]}},
  leansame/.style={cLean, line width=0.5pt, dashed, -{Stealth[length=4pt, width=3pt]}},
  ring/.style={black!18, line width=0.3pt, densely dotted},
  tier/.style={font=\small\bfseries, text=black!50}}
\begin{document}
{\Large\bfseries The assumptions of a one-dimensional PBL closure as a radial map}\\[0.3ex]
{\small Premises inside, the concepts that follow around them, the formal statements outside; each block at the mean
angle of what it rests on, so related blocks sit together. 2026-09-17.}

\vspace{0.3ex}
{\footnotesize Thick grey lines are the pyramid's contacts, the primary parents; thin blue arrows the further
dependencies of the audit, dashed within a ring. Frames: \textcolor{cGXIX}{\textbf{red}} the Goger 2019 port,
\textcolor{cFULL}{\textbf{purple}} the Kosovi\'c--Juliano three-dimensional closure. Statements, scheme quicklook and
the hectometre column are on the pyramid pages.\par}
\begin{center}
\begin{tikzpicture}[x=1cm, y=1cm]
""" + "\n".join(f"\\draw[ring] (0,0) circle ({R[t]});" for t in (0, 1, 2)) + "\n" + \
"\n".join(f"\\node[tier] at (90:{R[t] + 0.75}) {{{n}}};" for t, n in ((0, ""), (1, ""), (2, ""))) + "\n" + \
"\n".join(nodes) + "\n\\begin{scope}[on background layer]\n" + "\n".join(edges) + "\n\\end{scope}\n" + "\n".join(fr) + r"""
\node[tier, anchor=west] at (-19.0, 12.6) {outer ring: formalism};
\node[tier, anchor=west] at (-19.0, 12.0) {middle ring: concepts};
\node[tier, anchor=west] at (-19.0, 11.4) {inner ring: premises};
\end{tikzpicture}
\end{center}
\end{document}
"""
DST.write_text(doc)
print("radial: nodes", len(nodes), "contacts", len(contacts), "leans", len(leans), "frames", len(frames))
for b in blocks: print(f"  {ang[b['title']]:7.1f}  {b['style']:6s} {b['title']}")
