#!/usr/bin/env python3
"""Generate pbl_assumptions_pyramid_vertical.tex from pbl_assumptions_pyramid.tex.

The horizontal pyramid (tiers stacked upward, ground at the bottom) is transposed:
old x (position along the ground, left->right) becomes the vertical position (top->bottom),
old y (tier) becomes the horizontal position (left->right). A block then touches at its
LEFT exactly the blocks it relies on. Text is set at 7 pt on 7.5 pt leading (blocks are wide and short).
Run:  python3 scripts/make_pyramid_vertical.py   (from concept/), then tectonic the output.
"""
import re, sys, pathlib
SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("pbl_assumptions_pyramid.tex"); DST = SRC.with_name(SRC.stem + "_vertical.tex")
S = 0.86   # old cm along the ground -> new cm downward (0.88 no longer left room for the legend on page 1)
WIDTHS = [2.5, 4.18, 5.3]   # column widths (cm) of premises, concepts, formalism; moons and the hectometre column follow
XMAX = 27.35  # old extent of the ground
H = XMAX * S

src = SRC.read_text()
src_nc = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("%"))  # no comment lines

def take_args(s, i, n):
    """return n brace-delimited args starting at s[i]=='{' and the index after them"""
    args = []
    for _ in range(n):
        assert s[i] == "{", s[i:i+20]
        depth = 0; j = i
        while True:
            c = s[j]
            if c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0: break
            j += 1
        args.append(s[i+1:j]); i = j + 1
    return args, i

tikz0 = src.index("\\begin{tikzpicture}"); tikz1 = src.index("\\end{tikzpicture}")
body = src[tikz0:tikz1]
# tier bounds in old y from the blocks, mapped piecewise-linearly onto the column widths
_by = {}
for m in re.finditer(r"\\(pbf|pb)\{", body):
    a = take_args(body, m.end() - 1, 6)[0]; _by.setdefault(a[4], []).append((float(a[2]), float(a[3])))
_bounds = [(min(v[0] for v in _by[st]), max(v[1] for v in _by[st])) for st in ("ground", "hyp", "row")]
_bounds[0] = (0.0, _bounds[0][1])  # the ground starts at 0 whatever a raised block does
TIERS = [(_bounds[i][0], _bounds[i][1], sum(WIDTHS[:i]), WIDTHS[i]) for i in range(len(WIDTHS))]
_ys = [TIERS[0][0], TIERS[-1][1]]
def X(y):
    for y0, y1, x0, w in TIERS:
        if y0 - 1e-6 <= y <= y1 + 1e-6: return x0 + (y - y0) / (y1 - y0) * w
    raise ValueError(y)
YTOP = _ys[-1]; XF = sum(WIDTHS)          # right edge of the formalism column
HX0, HX1 = XF + 0.25, XF + 0.25 + 5.3    # hectometre column right of the formalism (moons end at 19.1 cm)
MOONDX = 0.34; MX0 = HX1 + 0.25                 # the four scheme columns at the far right
out = []
for m in re.finditer(r"\\(pbunion|pbf|pb|hl)\{", body):
    kind = m.group(1); i = m.end() - 1
    if kind == "pbunion":
        (style, tx, ty, tw, text, pieces, outline), _ = take_args(body, i, 7)
        np_ = []
        for pc in pieces.split(","):
            x0, x1, y0, y1 = map(float, pc.split("/"))
            np_.append(f"{X(y0):.3f}/{X(y1):.3f}/{H - x1 * S:.3f}/{H - x0 * S:.3f}")
        pts = re.findall(r"\(([-\d.]+),([-\d.]+)\)", outline)
        no = " -- ".join(f"({X(float(y)):.3f},{H - float(x) * S:.3f})" for x, y in pts)
        x0, x1, y0, y1 = map(float, pieces.split(",")[0].split("/"))   # the body piece carries the text
        out.append(f"\\pbunion{{{style}}}{{{X((y0 + y1) / 2):.3f}}}{{{H - (x0 + x1) / 2 * S:.3f}}}{{{X(y1) - X(y0) - 0.30:.2f}}}{{{text}}}{{{','.join(np_)}}}{{{no}}}")
        continue
    if kind == "pb":
        (x0, x1, y0, y1, style, text), _ = take_args(body, i, 6); hpad = 0.30
    elif kind == "pbf":
        (x0, x1, y0, y1, style, text, red), _ = take_args(body, i, 7)
        hpad = 0.56 if float(red) > 0.4 else 0.40
    else:
        (x0, x1, y0, y1, col, ins), _ = take_args(body, i, 6)
    x0, x1, y0, y1 = map(float, (x0, x1, y0, y1))
    nx0, nx1 = X(y0), X(y1)
    ny0, ny1 = H - x1 * S, H - x0 * S
    if kind == "hl":
        out.append(f"\\hlv{{{nx0:.3f}}}{{{nx1:.3f}}}{{{ny0:.3f}}}{{{ny1:.3f}}}{{{col}}}{{{ins}}}")
    else:
        out.append(f"\\pbv{{{nx0:.3f}}}{{{nx1:.3f}}}{{{ny0:.3f}}}{{{ny1:.3f}}}{{{style}}}{{{text}}}{{{hpad:.2f}}}")

# ---- moons: the scheme quicklook, four columns beside the formalism blocks -------------------------------
moons = {}
for m in re.finditer(r"\\moon\{", src_nc):
    (title, vals), _ = take_args(src_nc, m.end() - 1, 2); moons[title] = vals.split()
MOONCOL = ["cMYNN", "cGXIX", "cAPPROX", "cFULL"]; GLYPH = {"K": "\\gK", "P": "\\gP", "D": "\\gD"}
nm = 0
for m in re.finditer(r"\\(pbf|pb)\{", body):
    kind = m.group(1); args, _ = take_args(body, m.end() - 1, 7 if kind == "pbf" else 6)
    x0, x1, y0, y1, style, text = args[:6]
    if style != "row": continue
    title = re.match(r"\\textbf\{(.*?)\}\\\\", text + "\\\\").group(1)
    if title not in moons: print("WARN no moons for", title, file=sys.stderr); continue
    yc = H - (float(x0) + float(x1)) / 2 * S
    for k, (col, v) in enumerate(zip(MOONCOL, moons[title])):
        out.append(f"\\node[inner sep=0pt] at ({MX0 + MOONDX * (k + 0.5):.3f},{yc:.3f}) {{\\color{{{col}}}{GLYPH[v]}}};"); nm += 1
print("moons:", nm)
# ---- hectometre column: one dashed box per formal statement, aligned with its rows -----------------
hect = {}
for m in re.finditer(r"\\hecto\{", src_nc):
    (title, text), _ = take_args(src_nc, m.end() - 1, 2)
    hect[title] = text
nh = 0
for m in re.finditer(r"\\(pbf|pb)\{", body):
    kind = m.group(1); i = m.end() - 1
    args, _ = take_args(body, i, 7 if kind == "pbf" else 6)
    x0, x1, y0, y1, style, text = args[:6]
    if style != "row": continue
    title = re.match(r"\\textbf\{(.*?)\}", text).group(1)
    if title not in hect: print("WARN no hecto text for", title, file=sys.stderr); continue
    x0, x1 = float(x0), float(x1)
    ny0, ny1 = H - x1 * S + 0.03, H - x0 * S - 0.03
    out.append(f"\\pbh{{{HX0:.3f}}}{{{HX1:.3f}}}{{{ny0:.3f}}}{{{ny1:.3f}}}{{{hect[title]}}}"); nh += 1
print("hectometre boxes:", nh)

# paragraphs of the horizontal page, adapted to the transposed geometry
intro = re.search(r"\{\\footnotesize Every block is an assumption.*?\\par\}", src, re.S).group(0)
rest = src[src.index("\\end{center}") + len("\\end{center}"): src.index("\\end{document}")]
rep = [
 ("A block touches at its\nbottom exactly the blocks it relies on, and blocks on one level do not touch each other. Three tiers.",
  "A block touches at its\nleft exactly the blocks it relies on, and blocks in one column do not touch each other. Three columns."),
 ("Dark grey, the ground: ", "Dark grey, the ground (left column): "),
 ("Light grey, the\nconcepts:", "Light grey, the\nconcepts (middle column):"),
 ("White, the formalism:", "White, the formalism (right column):"),
 ("The middle tier is where", "The middle column is where"),
 ("The top\ntier is the closure as written", "The right\ncolumn is the closure as written"),
 ("Terrain breaks the ground on the left\nand in the middle", "Terrain breaks the ground at the top\nand in the middle"),
 ("and the grey zone breaks it\non the far left; the right third,", "and the grey zone breaks it\nat the very top; the lower third,"),
]
for a, b in rep:
    n = (intro + rest).count(a)
    if n != 1: print("WARN anchor", n, repr(a[:50]), file=sys.stderr)
    intro = intro.replace(a, b); rest = rest.replace(a, b)

pre_end = src.index("\\begin{document}")
pre = src[:pre_end]
pre = pre.replace("\\usepackage[a4paper,landscape,margin=10mm,top=7mm,bottom=7mm]{geometry}",
                  "\\usepackage[a4paper,margin=9mm,top=9mm,bottom=9mm]{geometry}")
pre = re.sub(r"% =+\n%  The assumptions.*?% =+\n", "", pre, count=1, flags=re.S)
header = f"""% =============================================================================
%  The assumptions of a one-dimensional PBL closure, as a pyramid -- VERTICAL version
%  GENERATED by scripts/make_pyramid_vertical.py from pbl_assumptions_pyramid.tex; edit the
%  horizontal file and regenerate. Tiers are columns (physics | concepts | formalism); a block
%  touches at its left exactly what it relies on. Scale: {S} cm per old cm along the ground,
%  column widths {WIDTHS} cm for premises, concepts, formalism. Build: tectonic pbl_assumptions_pyramid_vertical.tex
% =============================================================================
"""
macros = r"""
% vertical block: rectangle + centred text, text width = block width - hpad
\newcommand{\pbv}[7]{\pgfmathsetmacro{\pbw}{#2-#1-#7}%
  \draw[#5] (#1,#3) rectangle (#2,#4);
  \node[align=center, font=\fontsize{7}{7.5}\selectfont, inner sep=0pt, text width=\pbw cm] at ({(#1+#2)/2},{(#3+#4)/2}) {#6};}
\newcommand{\hlv}[6]{\draw[#5, line width=1.1pt] (#1+#6,#3+#6) rectangle (#2-#6,#4-#6);}
% compound blocks in the page's text size
\renewcommand{\pbunion}[7]{\foreach \ux/\uX/\uy/\uY in {#6} {\fill[black!22] (\ux,\uy) rectangle (\uX,\uY);}
  \draw[#1, fill=none] #7 -- cycle;
  \node[align=center, font=\fontsize{7}{7.5}\selectfont, inner sep=0pt, text width=#4 cm] at (#2,#3) {#5};}
% hectometre box: dashed, left-aligned commentary beside a concept (not a block of the chain)
\newcommand{\pbh}[5]{\pgfmathsetmacro{\pbw}{#2-#1-0.30}%
  \draw[hecto] (#1,#3) rectangle (#2,#4);
  \node[align=left, font=\fontsize{6.5}{7.6}\selectfont, inner sep=0pt, text width=\pbw cm] at ({(#1+#2)/2},{(#3+#4)/2}) {#5};}
"""
labels = "\n".join(
    f"\\node[font=\\scriptsize\\bfseries, text=black!60] at ({(X(a)+X(b))/2:.3f},{H+0.35:.3f}) {{{name}}};"
    for (a, b, name) in [(t[0], t[1], n) for t, n in zip(TIERS, ["premises", "concepts", "formalism"])])
labels += f"\n\\node[font=\\scriptsize\\bfseries, text=black!60] at ({MX0 + 2 * MOONDX:.3f},{H+0.35:.3f}) {{schemes}};"
labels += f"\n\\node[font=\\scriptsize\\bfseries, text=black!60, align=center] at ({(HX0+HX1)/2:.3f},{H+0.5:.3f}) {{hectometre-scale simulations\\\\ in complex terrain}};"

doc = header + pre + macros + r"""
\begin{document}
{\large\bfseries The assumptions of a one-dimensional PBL closure, as a pyramid: what rests on what}\\[0.2ex]
{\small Vertical version of the companion page to the assumptions note. 2026-09-16.}

\vspace{0.3ex}
{\footnotesize Left, dark grey: the premises, hypotheses about the fluid and the flow. Middle, light grey: the concepts of
turbulence theory that follow. White: the formal statements of the level-2.5 closure. A block touches at its left
exactly the blocks it relies on; blocks in one column do not touch. Frames: \textcolor{cGXIX}{\textbf{red}} the Goger 2019
port, \textcolor{cFULL}{\textbf{purple}} the Kosovi\'c--Juliano three-dimensional closure, nested both. Right of the
formalism, dashed: what becomes of each formal statement in hectometre-scale simulations over complex terrain, here
$\Delta = 500$~m in the Inn Valley.
Far right, the four schemes of the concept's first research question, left to right \textcolor{cMYNN}{\textbf{MYNN as
run}}, \textcolor{cGXIX}{\textbf{G19 port}}, \textcolor{cAPPROX}{\textbf{3D-APPROX}}, \textcolor{cFULL}{\textbf{3D-FULL}}:
\gK{} the scheme as run implements the statement, \gP{} partly, \gD{} drops it (a block takes the status of its rows in the
note's Table~I.0). Rules, reading and the correspondence to the note's rows are on the next page.\par}

\vspace{0.4ex}
\begin{center}
\begin{tikzpicture}[x=1cm, y=1cm,
  ground/.style={draw, line width=0.4pt, fill=black!22},
  hyp/.style={draw, line width=0.4pt, fill=black!9},
  row/.style={draw, line width=0.4pt, fill=white},
  hecto/.style={draw=black!55, dashed, line width=0.4pt, fill=white}]
""" + labels + "\n" + "\n".join(out) + r"""
\end{tikzpicture}
\end{center}

\newpage
""" + intro + "\n" + rest + r"""
\end{document}
"""
DST.write_text(doc)
print("wrote", DST, "blocks:", sum(1 for o in out if o.startswith("\\pbv")), "frames:", sum(1 for o in out if o.startswith("\\hlv")))
