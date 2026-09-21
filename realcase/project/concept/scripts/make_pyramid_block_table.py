#!/usr/bin/env python3
"""Block-by-block review table of the split pyramid (2026-09-18, for the reMarkable; 2026-09-21 after Elias's tablet notes).

Reads the block texts VERBATIM from pbl_assumptions_pyramid_split.tex (the source of the vertical working
document), derives the drawn contacts from the block geometry and prints them for checking, and writes
pbl_assumptions_pyramid_split_blocktable.tex: one row per block with
  1 exact block text | 2 what it means | 3 existing connections | 4 missing connections (severity 1-10) | 5 notes.
Columns 2-4 are hand-written below (ROWS), keyed by the block's position along the ground within its tier.

Usage: python3 scripts/make_pyramid_block_table.py [SOURCE.tex]
Build: source ~/miniconda3/bin/activate tex && tectonic pbl_assumptions_pyramid_split_blocktable.tex
"""
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "pbl_assumptions_pyramid_split.tex"
OUT = SRC.replace(".tex", "_blocktable.tex")


def args_of(s, i, n):
    """n brace-delimited arguments starting at s[i] == '{'."""
    out = []
    for _ in range(n):
        while s[i] != "{":
            i += 1
        depth, j = 0, i
        while True:
            if s[j] == "{":
                depth += 1
            elif s[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out.append(s[i + 1:j])
        i = j + 1
    return out


src = "\n".join(l for l in open(SRC).read().split("\n") if not l.lstrip().startswith("%"))
body = src[src.index(r"\begin{tikzpicture}"):]
blocks = []  # dict(title, text, style, tops=[(x0,x1)], bottoms=[(x0,x1)], x0)
for m in re.finditer(r"\\(pbunion|pbf|pb)\{", body):
    kind = m.group(1)
    i = m.end() - 1
    if kind == "pbunion":
        style, tx, ty, tw, text, pieces, outline = args_of(body, i, 7)
        pcs = [tuple(float(v) for v in p.split("/")) for p in pieces.split(",")]
        y0 = min(p[2] for p in pcs)
        y1 = max(p[3] for p in pcs)
        tops = [(p[0], p[1]) for p in pcs if abs(p[3] - y1) < 1e-6]
        bots = [(p[0], p[1]) for p in pcs if abs(p[2] - y0) < 1e-6]
        x0 = min(p[0] for p in pcs)
    else:
        a = args_of(body, i, 7 if kind == "pbf" else 6)
        x0, x1, y0, y1 = (float(v) for v in a[:4])
        style, text = a[4], a[5]
        tops = bots = [(x0, x1)]
    title = re.match(r"\\textbf\{(.*?)\}", text).group(1)
    blocks.append(dict(title=title, text=text, style=style, tops=tops, bots=bots, x0=x0, y0=y0, y1=y1))

TIER = {"ground": 0, "hyp": 1, "row": 2}
blocks.sort(key=lambda b: (TIER[b["style"]], b["x0"]))

# (until 2026-09-21 homogeneity's channel band was cut out of similarity's top edge here; the channel is gone)


def overlap(a, b):
    return max(0.0, min(a[1], b[1]) - max(a[0], b[0]))


print("drawn contacts (child <- parents, overlap in source cm):")
for c in blocks:
    ps = []
    for p in blocks:
        if TIER[p["style"]] != TIER[c["style"]] - 1:
            continue
        w = sum(overlap(cb, pt) for cb in c["bots"] for pt in p["tops"])
        if w > 0.05:
            ps.append(f"{p['title']} ({w:.2f})")
    if ps:
        print(f"  {c['title']:45s} <- " + "; ".join(ps))

# ------------------------------------------------------------------------------------------------------------
# hand-written columns: (title prefix for the safety check, detail, existing, [(missing, severity), ...])
S = r"\textbf{Stands on}"
C = r"\textbf{Carries}"
L = r"\textbf{Leans on}"
B = r"\textbf{Leaned on by}"
F = r"\textbf{Frames}"
ROWS = [
    # ------------------------------------------------------------------ premises
    ("Spectral gap",
     r"The energy spectrum has a minimum between the turbulent eddies (seconds to minutes, sizes up to the boundary-layer depth $z_i$) and the mean flow (hours, tens of km). Only then does a window exist that is long against every eddy and short against every change of the mean, so that ``mean'' and ``fluctuation'' are defined at all. First of the two conditions into which scale separation is split; names no grid quantity. Over a valley the gap is filled by day (thermals, slope-wind cells of the valley's width) and by night (waves, meanders, drainage pulses).",
     S + r": nothing (ground). " + C + r" (contact): Reynolds decomposition --- its two rules hold for a window only if the mean is constant across it. " + B + r" (text): Vertical divergence only, ``numerics at its own scale'': the horizontal mixing is left to a process assumed to live at a separate scale.",
     [(r"Local equilibrium $\leftarrow$ gap in \emph{time}: ``faster than the flow changes'' is the temporal form of the gap; the page gives that role to stationarity alone.", 3),
      (r"Master length scale $\leftarrow$ gap: $z_i$ as ``the largest eddy'' is defined only if the eddies end below the mean flow.", 3),
      (r"Spectral gap $\leftrightarrow$ Gradient scale: two halves of one hypothesis at opposite ends of the ground; only a caption sentence says they belong together.", 2)]),
    ("Mixing",
     r"Velocity correlations decay: beyond a finite integral length (in space) and integral time (along a particle path) an eddy has forgotten its origin. This makes a sum over many eddies converge, and it turns eddy transport into diffusion (Taylor's 1921 limit). Waves have scale separation \emph{without} mixing: in the stable night motions stay correlated over long distances and carry no scalar --- then this is the premise that fails.",
     C + r" (contact): Ergodicity in space, left part --- independent samples need decorrelation. " + B + r" (text): Locality (``after decorrelation''), Mixing length (``one integral scale''), Energy cascade (``integral-scale eddies''; in the source list only until 2026-09-21, made text at Elias's note).",
     [(r"Local equilibrium $\leftarrow$ Mixing: relaxation within $l/q$ presumes a finite Lagrangian memory; in wavy stable air the memory is long and the algebraic moments lag.", 4),
      (r"Eddy viscosity $\leftarrow$ Mixing: gradient transport \emph{is} the diffusive limit; reachable only in two steps through Locality.", 3)]),
    ("Horizontal homogeneity",
     r"Every statistic --- each mean and each moment --- is invariant under horizontal translation, so every horizontal derivative of a statistic vanishes. Taken strictly it also forces a horizontal, uniform surface. The premise that terrain breaks first: slope, valley axis and land-use mosaic give horizontal gradients of the order of the vertical ones. Until 2026-09-21 drawn with a channel under stationarity that reached Monin--Obukhov similarity and the mixing length; the channel is gone (Elias), both name homogeneity in their text and carry its mark on the colour page.",
     C + r" (contact): Ergodicity in space (statistics alike across the cell); Column approximation (its direct application); Constant-flux layer (no horizontal flux divergence). " + B + r" (text): Monin--Obukhov similarity (``homogeneous, hence horizontal, surface''; first of its leans), Mixing length (``set by the column alone''; first), Local equilibrium (advection of second moments neglected), Return to isotropy (``as in homogeneous turbulence away from walls'').",
     [(r"Buoyancy production $\leftarrow$ Homogeneity: ``no horizontal heat flux'' holds only over a horizontal surface; on a slope the surface-normal heat flux has a horizontal component. The block stands on Axisymmetric mixing + Boussinesq and never names homogeneity.", 6),
      (r"Universal constants / Constant set $\leftarrow$ Homogeneity: ``simple flows'', ``flat terrain'' \emph{are} homogeneous flows; present only as those words.", 4),
      (r"Surface fluxes and first level: one roughness length per cell is a homogeneity claim \emph{inside} the cell; reached only via Monin--Obukhov.", 3)]),
    ("Stationarity",
     r"Statistics invariant under time translation --- required only over the eddy relaxation time $l/q$ ($l$ mixing length, m; $q$ square root of twice the turbulence kinetic energy, m\,s$^{-1}$): a weak, local form. $l/q$ is short by day and long at night, when $q$ is small. Fails in transitions: sunrise, sunset, onset of the valley wind, drainage pulses.",
     C + r" (contact): Constant-flux layer (no storage below $z$); Local equilibrium (tendency neglected); Monin--Obukhov similarity (profiles adjusted to the present surface fluxes). " + B + r" (text): Energy cascade (``in equilibrium'').",
     [(r"Cutoff $\leftarrow$ Stationarity: the critical flux Richardson number is the limit of a \emph{steady} balance; decaying or intermittent turbulence lives beyond it. See row 33.", 5),
      (r"Master length scale $\leftarrow$ Stationarity: $z_i$ and the $q$-weighted length are diagnosed from the instantaneous profile as if it were adjusted.", 3),
      (r"Universal constants $\leftarrow$ Stationarity: the constants were measured in stationary flows.", 2)]),
    ("Similarity",
     r"Scaled by the right few parameters, a relation is the same universal function in every flow; the parameter list is complete. It is the licence to carry a number from a wind tunnel or a flat field site to the Inn Valley. Fails when an extra length or time enters: valley width, slope angle, inversion height, distance to the ridge.",
     C + r" (contact): Monin--Obukhov similarity (list $u_*$, $\theta_*$, $z$, buoyancy parameter); Mixing length ($l/z$ universal); Universal constants (scaled rates are pure numbers).",
     [(r"Energy cascade and Return to isotropy $\leftarrow$ Similarity: $\varepsilon \sim q^3/l$ and the return rate $q/l$ are dimensional arguments with $q$, $l$ as the complete list; reached only through Universal constants, a sibling.", 4),
      (r"Stability functions $\leftarrow$ Similarity: $S_M$, $S_H$ are universal functions of two scaled gradients and nothing else.", 4),
      (r"K-form's ``one $K_H$ for all scalars'': scalar similarity (all scalars mix alike) is a hypothesis of its own; no premise states it.", 4)]),
    ("Small-scale isotropy",
     r"At high Reynolds number the eddies much smaller than the energy-containing ones have lost the memory of the orientation of shear and gravity (Kolmogorov's local isotropy). It makes the dissipation a scalar, $\varepsilon_{ij} = \tfrac{2}{3}\delta_{ij}\varepsilon$ ($\varepsilon$ dissipation rate, m$^2$\,s$^{-3}$), and gives the pressure scrambling an isotropic target. In strongly stable air the largest overturning scale (Ozmidov) sinks toward the dissipative scales and the premise itself weakens.",
     C + r" (contact): Universal constants (right part: small-scale processes are flow-independent); Energy cascade; Return to isotropy (left part: the isotropic target, the scalar $\varepsilon$). High Reynolds number, a premise without a block, is named here. Since 2026-09-18 the statement about the \emph{large} eddies is its own premise, row 6b.",
     [(r"One size of the large eddies in every direction is in neither isotropy premise; it lives in the Mixing length (row 16). Mellor and Yamada state it as a bare closure assumption (``perhaps their greatest weakness''), not as a consequence of similarity. (Scored 7 as a missing premise on 2026-09-18; retracted the same day.)", 3),
      (r"The right third of the ground carries six concepts and five formal blocks but ``no scheme in the comparison touches it'': nothing on the page says whether it holds at night.", 3)]),
    ("Weak anisotropy",
     r"The stress tensor of the energy-containing eddies departs only weakly from the isotropic one: in $\langle u_i u_j\rangle = (\delta_{ij}/3 + a_{ij})\,q^2$ the anisotropy $a_{ij}$ is small. It is the expansion parameter of the Mellor--Yamada hierarchy: terms of order $a^2$ are eliminated, and the authors add that $a_{ij}^2 \approx 0.15$ ``is not overly small'' (1982, p.~854). Large eddies cannot be isotropic --- no flux would remain --- only nearly so. Fails in shear-dominated and stable air: two-component (pancake) and one-component states, the anisotropy classes of Stiperski. New 2026-09-18, split off Small-scale isotropy.",
     C + r" (contact): Return to isotropy (right part: ``linear in it, because it is small''). " + B + r" (text): Level-2.5 truncation (``to leading order in the anisotropy''). All four schemes keep it, the full 3D closure included.",
     [(r"When it fails the realizability clipping catches the algebra; realizability is excluded from the page by rule, so the failure has no visible consequence.", 4),
      (r"Universal constants / Constant set $\leftarrow$ Weak anisotropy: the constants are fitted to near-isotropic turbulence; a pancake's rates differ.", 4),
      (r"Pressure terms: the isotropisation-of-production term is exact in the isotropic limit only; inherited through Return to isotropy, not named.", 3)]),
    ("Gradient scale",
     r"The eddy is small against the distance over which the mean gradient changes (Corrsin's condition), so the expansion of the mean field across an eddy stops at the first term: flux $\propto$ local gradient. Fails in the convective layer ($l \sim z_i \sim$ gradient scale: heat flux against the gradient) and at a jet maximum (the gradient changes sign within one eddy).",
     C + r" (contact): Locality; Eddy viscosity (left part: gradient transport).",
     [(r"Mixing length / Master length $\leftrightarrow$ Gradient scale --- a \emph{tension}: by day the closure's own length is of the order of $z_i$, i.e.\ of the gradient scale, so the length the top tier builds violates the premise its K-form stands on. Nowhere shown.", 5),
      (r"Pressure terms' down-gradient TKE transport and the truncation reach this premise only through Locality; acceptable chain.", 2)]),
    ("Axisymmetric mixing",
     r"The mixing has one distinguished axis, gravity, and is invariant under rotation about it and under reflection: one $K$ (eddy diffusivity, m$^2$\,s$^{-1}$) along and across the shear, no handedness. It keeps only what homogeneity does not already give. Fails where slope wind turns into valley wind (the wind veers with height) and wherever the surface normal is not gravity (two axes).",
     C + r" (contact): Eddy viscosity (right part: ``alike along and across the shear''); Buoyancy production (left part: ``gravity acts along one axis'').",
     [(r"Master length, stability functions and shear production all treat the two horizontal directions alike (one $l$, one $S_M$, $U_z^2 + V_z^2$) without touching or naming this premise.", 4),
      (r"``Gravity the one axis'' is kept here although the geometric half (surface normal = gravity) was assigned to homogeneity: the slope case is split over two premises, neither names the other.", 4)]),
    ("Boussinesq",
     r"Density variations matter in the buoyancy force only; the flow is incompressible ($\nabla\cdot\mathbf{u} = 0$); the air is unsaturated, so buoyancy follows the virtual potential temperature linearly. Safe for a 2 km deep valley; the unsaturated clause fails on fog nights.",
     C + r" (contact): Buoyancy production (right part). " + B + r" (text): Column approximation (``$W = 0$ by continuity''). Unsaturated air, a premise without a block, is named here.",
     [(r"Unsaturated air $\leftrightarrow$ Grid means: in a partly saturated cell the buoyancy flux depends on the subgrid cloud fraction --- a link between the averaging and the buoyancy that only the control's condensation scheme carries.", 4),
      (r"Monin--Obukhov similarity $\leftarrow$ Boussinesq: the Obukhov length contains the buoyancy parameter and the buoyancy flux.", 2),
      (r"Reynolds decomposition $\leftarrow$ Boussinesq: plain, not density-weighted, averaging.", 1)]),
    # ------------------------------------------------------------------ concepts
    ("Reynolds decomposition",
     r"Every field is mean plus fluctuation, with $\langle a'\rangle = 0$ and $\langle\langle a\rangle b'\rangle = 0$. Exact for an ensemble mean; for a window or cell mean they hold only if the mean is constant across the window, otherwise cross terms survive. Every second-moment equation of the closure is derived with these two rules.",
     S + r": Spectral gap. " + C + r": Grid means are ensemble means (left part). " + B + r" (source list only): Universal constants (ensemble constants).",
     [(r"Root of the whole middle tier: every concept that speaks of a second moment (cascade, return to isotropy, local equilibrium, eddy viscosity, buoyancy production) presupposes it; the page shows it as the parent of one formal block at the far left.", 3),
      (r"Commutation of the average with derivatives on a stretched, terrain-following grid belongs between this block and Grid means; nowhere on the page.", 3),
      (r"Universal constants $\leftarrow$ Reynolds is recorded but invisible in the text.", 2)]),
    ("Ergodicity in space",
     r"The average over the cell equals the ensemble average. Three premises: statistics alike across the cell (invariance), correlations decaying within $l$ (mixing), many independent eddies per cell, $\Delta \gg l$ ($\Delta$ horizontal grid spacing, m) (window). By day $l \sim z_i \ge \Delta$: a handful of eddies or fewer; at night $l \ll \Delta$ but the cell straddles slope layer and valley core, so invariance fails instead.",
     S + r": Mixing (decorrelation) and Horizontal homogeneity (invariance across the cell). " + C + r": Grid means are ensemble means (right part).",
     [(r"Surface fluxes and first level $\leftarrow$ Ergodicity: the bulk formula is an ensemble relation applied to one cell mean over a heterogeneous cell.", 5),
      (r"$\Delta \gg l$ names a grid quantity inside a concept, against the page's own rule that nothing below the top tier names a model. A placement flaw rather than a missing link.", 3),
      (r"Ergodicity in \emph{time} carries the calibration data of the Constant set; not drawn by rule.", 2)]),
    ("Boundary-layer (column)",
     r"Every statistic varies with $z$ only. The three-dimensional budgets collapse: two of nine shear-production terms, vertical flux divergence only, mean vertical velocity $W = 0$ from continuity. It is homogeneity applied column by column ``as if'', even where neighbouring columns differ.",
     S + r": Horizontal homogeneity. " + L + r" (text): Boussinesq (``$W = 0$ by continuity''). " + C + r": Vertical shear only; Vertical divergence only. " + B + r": Stability functions (``vertical Ri alone''). " + F + r": both --- the Goger port breaks it for production alone, the 3D closure entirely.",
     [(r"Master length scale $\leftarrow$ Column: ``one $z_i$ per column'', ``blind to terrain'' \emph{is} this approximation; in the text, not in the lean list, no contact.", 5),
      (r"K-form fluxes $\leftarrow$ Column: written for $\langle uw\rangle$, $\langle w\theta\rangle$ and $z$-gradients only --- exactly what the Goger port keeps.", 5),
      (r"Buoyancy production / Buoyancy term $\leftarrow$ Column: ``no horizontal heat flux''. Same defect as row 3.", 5),
      (r"Level-2.5 truncation $\leftarrow$ Column: the algebraic system actually solved is the boundary-layer form; recorded for the stability functions only.", 3)]),
    ("Constant-flux layer",
     r"In the lowest tenth of the boundary layer the fluxes differ from their surface values by less than about 10\,\%: the stationary, homogeneous budget integrated over a thin layer. So the surface friction velocity $u_*$ (m\,s$^{-1}$) and temperature scale $\theta_*$ (K) characterise the whole layer. With a katabatic jet at 5--20 m the momentum flux changes sign inside the layer.",
     S + r": Horizontal homogeneity and Stationarity. " + C + r": Wall value of $q^2$ (left part). " + B + r" (text): Monin--Obukhov similarity.",
     [(r"Constant set $\leftarrow$ Constant-flux layer: several constants are fixed from neutral surface-layer ratios ($B_1$ from $q^2/u_*^2$).", 4),
      (r"Surface fluxes and first level $\leftarrow$ Constant-flux layer: $z_1$ must lie inside it; the block touches Monin--Obukhov only (chain through its lean).", 3)]),
    ("Local equilibrium",
     r"The eddies adjust within $l/q$, faster than their surroundings change along their path, so the second moments are set by the current local gradients: production + redistribution = dissipation, with tendency, advection and transport dropped. Level 2.5 applies it to every moment but $q^2$ (twice the turbulence kinetic energy, m$^2$\,s$^{-2}$). Fails when $l/q$ is long (night) or the flow changes fast (transitions; advection across one 500 m cell takes about 100 s at 5 m\,s$^{-1}$).",
     S + r": Stationarity. " + L + r" (text): Locality (``current local gradients''); Horizontal homogeneity (advection neglected). " + C + r": Wall value of $q^2$ (right part); Level-2.5 truncation. " + B + r": Stability functions (the balance $P_s + P_b = \varepsilon$).",
     [(r"$\leftarrow$ Return to isotropy: the relaxation \emph{is} the pressure scrambling at the rate $q/l$; the block uses the rate without its parent.", 4),
      (r"$\leftarrow$ Mixing: finite Lagrangian memory (row 2).", 4),
      (r"One length for $K$ and $\varepsilon$ $\leftarrow$ Local equilibrium: no $\varepsilon$ equation, $\varepsilon$ follows $q$ and $l$ instantly.", 4)]),
    ("Monin--Obukhov",
     r"In the constant-flux layer over a homogeneous, horizontal surface the only parameters are $u_*$, $\theta_*$, $z$ and the buoyancy parameter, so the scaled gradients are universal functions of $z/L_{\mathrm{MO}}$ (Obukhov length, m: the height where buoyancy production equals shear production). On a slope gravity is not along the surface normal and further parameters enter (slope angle, jet height).",
     S + r": Stationarity and Similarity. " + L + r" (text): Horizontal homogeneity (first: the homogeneous surface), Constant-flux layer. " + C + r": Surface fluxes and first level; Master length scale (left part: the wall branch $\kappa z$ with its stability correction).",
     [(r"Constant set / Stability functions $\leftarrow$ Monin--Obukhov: the closure is calibrated to reproduce the surface-layer functions. This calibration contact was drawn once and vanished when the truncation moved onto Local equilibrium alone.", 5),
      (r"Wall value of $q^2$ $\leftarrow$ Monin--Obukhov through $u_*$ (row 26).", 3),
      (r"$\leftarrow$ Buoyancy production / Boussinesq: $L_{\mathrm{MO}}$ is built from the vertical buoyancy flux.", 3)]),
    ("Mixing length",
     r"One length $l$ per height characterises the energy-containing eddies, a universal function of the column's own properties (height above ground, boundary-layer depth, stratification). ``One'': a scalar, the same for every direction and every moment. ``Column alone'': it knows nothing of valley width, distance to the slope, or the grid.",
     S + r": Similarity. " + L + r" (text): Horizontal homogeneity (first: ``set by the column alone''), Mixing (``integral scale''). " + C + r": Master length scale (middle part). " + B + r": Eddy viscosity ($K \sim lq$).",
     [(r"``One'' length for every direction and every moment, up to fixed constants, is Similarity's complete parameter list applied to the eddy size; it fails when a second length enters (valley width). The text says ``one'', not ``in every direction'': a missing clause, not a missing premise (retracted from 7).", 4),
      (r"Energy cascade and Return to isotropy use the \emph{same} $l$ ($\varepsilon \sim q^3/l$, rate $q/l$) and touch nothing of this block; only the formal block ``One length'' says so.", 4),
      (r"$\leftarrow$ Column approximation: in the text only.", 2)]),
    ("Universal constants",
     r"Scaled with $q$ and $l$, the rates of return to isotropy and of dissipation are pure numbers ($A_1$, $B_1$, \dots), the same in every flow, so they can be measured once in simple --- homogeneous, stationary, neutral --- flows. Combines Similarity (complete parameter list) with Small-scale isotropy (the processes are small-scale, hence flow-independent).",
     S + r": Similarity and Small-scale isotropy. " + C + r": Master length scale (a 0.3 cm sliver: its coefficients); Constant set; One length for $K$ and $\varepsilon$ (left part). " + B + r" (by symbol): Wall value ($B_1$), Pressure terms ($A_1$, $C_1$); (source only) Stability functions. " + L + r" (source only): Reynolds decomposition.",
     [(r"The contact with the Master length is nearly invisible, and wrong in kind: the coefficients of the three lengths are tuning constants from large-eddy simulations, not universal numbers.", 4),
      (r"$\leftarrow$ Homogeneity, Stationarity: the ``simple flows''.", 3),
      (r"Stability functions $\leftarrow$ Universal constants: recorded, not visible in the text.", 2)]),
    ("Energy cascade",
     r"Energy enters at the scale $l$, is handed down the inertial subrange without loss and is dissipated isotropically at the small end. In equilibrium the dissipation equals the supply by the large eddies, $\varepsilon \sim q^3/l$: the dissipation known from large-eddy quantities. Needs high Reynolds number and a stationary spectrum. In stable air part of the energy goes to potential energy and waves.",
     S + r": Small-scale isotropy. " + L + r" (text): Stationarity (``in equilibrium''), Mixing (``integral-scale eddies'', text since 2026-09-21; the block was widened by 0.3 units for the line). " + C + r": One length for $K$ and $\varepsilon$ (right part).",
     [(r"Grid means $\leftrightarrow$ Cascade: when $\Delta$ falls inside the energy-containing range the subgrid $q$ no longer scales $\varepsilon$ ($\varepsilon$ is filter-independent, $q^3$ is not). Only the hectometre text says it.", 4),
      (r"$\leftarrow$ Similarity (dimensional argument) and $\leftarrow$ Mixing length (the same $l$): rows 5, 16.", 4)]),
    ("Return to isotropy",
     r"Pressure fluctuations redistribute energy among the components without changing its sum; Rotta: the anisotropy decays toward zero at the one rate $q/l$, linearly. ``Computed locally'': pressure obeys a Poisson equation and is non-local; the model keeps the local term and omits the reflection at the ground (wall echo). Pressure transport of energy is lumped into a diffusive transport.",
     S + r": Small-scale isotropy (the isotropic target) and Weak anisotropy (the linear form). " + L + r" (text): Horizontal homogeneity. " + C + r": Pressure terms; Stability functions and cutoff. " + B + r" (text): Buoyancy production (the sharing of buoyancy's $\langle w^2\rangle$ among the components).",
     [(r"The \emph{buoyancy part} of the pressure terms (constants $C_2$, $C_3$ in the control; ``higher-order terms'' left out by Mellor and Yamada 1982, p.~853) is still in neither this text nor Pressure terms; the slow return of buoyancy-made anisotropy is now named from the Buoyancy production side.", 5),
      (r"Level-2.5 truncation $\leftarrow$ Return to isotropy: the algebraic system is solvable because Rotta's form is linear; the truncation now stands on Local equilibrium alone.", 3),
      (r"$\leftarrow$ Universal constants / Similarity: ``the one rate''.", 3)]),
    ("Locality",
     r"The flux at a point depends on the mean gradient at that point only: the eddy is small against the gradient scale and has decorrelated. Excludes transport by coherent plumes (non-local, against the gradient) and by waves.",
     S + r": Gradient scale. " + L + r" (text): Mixing (``after decorrelation''). " + C + r": K-form fluxes (left part). " + B + r": Local equilibrium, Eddy viscosity, Pressure terms.",
     [(r"Tension with the Master length scale: $z_i$ and the $q$-weighted length are integrals over the column --- a non-local length inside a local flux law. No mark on the page.", 3)]),
    ("Eddy viscosity",
     r"Flux $= -K\,\times$ gradient with one positive scalar $K \sim lq$; the same $K$ along and across the shear, so the stress axes are aligned with the strain axes. Positive $K$: energy flows from the mean flow to the turbulence only.",
     S + r": Gradient scale (gradient transport) and Axisymmetric mixing (one $K$). " + L + r" (text): Locality (``local''), Mixing length ($K \sim lq$). " + C + r": K-form fluxes (right part). " + F + r": 3D closure only --- it replaces $K$ by the solved stress tensor.",
     [(r"$\leftarrow$ Return to isotropy + Local equilibrium: in this closure family the eddy-viscosity form is not assumed but \emph{derived} --- it is what the algebraic stress equations give under the column approximation. The page shows it as an independent concept.", 6),
      (r"$\leftarrow$ the prognostic $q$: no block says that $q^2$ has a budget of its own; the nearest is the truncation's ``all but $q^2$''.", 4),
      (r"Positivity $\leftrightarrow$ realizability: excluded by rule.", 1)]),
    ("Buoyancy production",
     r"$P_b = \beta g \langle w\theta_v\rangle$ ($\beta$ thermal expansion coefficient, K$^{-1}$; $g$ gravity): buoyancy exchanges kinetic and potential energy through the vertical heat flux alone --- a sink in stable air. The place where stratification enters the pyramid.",
     S + r": Axisymmetric mixing (one axis) and Boussinesq. " + L + r" (text): Return to isotropy (``its sharing among the components''). " + C + r": Buoyancy term. " + B + r": Stability functions ($P_b$ in the balance).",
     [(r"Corrected 2026-09-18 (was 7): the clause ``no redistribution among the stress components'' is replaced by ``all of it in $\langle w^2\rangle$; its sharing \dots left to the return to isotropy''. Left over: the note's row for this block still says ``neither redistributes energy among the stress components''.", 3),
      (r"$\leftarrow$ Horizontal homogeneity / Column approximation: ``no horizontal heat flux'' (rows 3, 12).", 6),
      (r"Monin--Obukhov similarity $\leftarrow$ Buoyancy production ($L_{\mathrm{MO}}$).", 3)]),
    # ------------------------------------------------------------------ formalism
    ("Grid means are ensemble means",
     r"The model's variables, cell means, are treated as ensemble means: all turbulence is subgrid ($\Delta \gg l, z_i$), the resolved flow is laminar so that its shear is mean shear and feeds production, and the vertical grid is fine enough for the gradient it differentiates ($\Delta z \ll$ shear-layer depth). The grid spacing appears nowhere in the closure. Schemes: control partly, Goger port kept, both 3D variants partly.",
     S + r": Reynolds decomposition and Ergodicity in space.",
     [(r"It is the root of the formal tier, drawn as a leaf: every other formal block is evaluated on these grid means. Strongest: K-form $\leftarrow$ Grid means (the ``resolved gradient'' was merged into this block); Vertical shear only $\leftarrow$ Grid means (resolved shear counted as mean shear: double counting in the grey zone); Surface fluxes $\leftarrow$ Grid means.", 5),
      (r"$\Delta z \ll$ shear-layer depth rests on nothing below: a resolution premise without a parent.", 3)]),
    ("Vertical shear only",
     r"Shear production $P_s = -\langle uw\rangle U_z - \langle vw\rangle V_z$: two of the nine terms of $-\langle u_i u_j\rangle\,\partial U_i/\partial x_j$; no horizontal shear, no gradient of $W$. Schemes: control kept, Goger port partly (adds a horizontal source), 3D-approximate kept, 3D-full dropped.",
     S + r": Column approximation. " + F + r": both.",
     [(r"$\leftarrow$ K-form fluxes: the stresses in $P_s$ come from the K-form ($P_s = K_M S^2$). The same dependence is recorded for the Buoyancy term, not for this block.", 5),
      (r"$\leftarrow$ Grid means (row 23).", 5),
      (r"Stability functions $\leftarrow$ this block: their shear argument is the same vertical shear; recorded against the Column approximation instead.", 2)]),
    ("Vertical divergence only",
     r"Tendencies of the means and of the energy come from $\partial/\partial z$ of vertical fluxes only; the energy is not advected; horizontal mixing is handed to the dynamical core's diffusion, and the kinetic energy that removes is not credited to $q^2$; terrain-following surfaces count as horizontal. Schemes: control kept, Goger port partly, 3D-approximate partly, 3D-full dropped.",
     S + r": Column approximation. " + L + r" (text): Spectral gap. " + F + r": both.",
     [(r"``TKE not advected'' is local equilibrium applied to the one moment the truncation leaves prognostic: $\leftarrow$ Local equilibrium / sibling of the truncation.", 3),
      (r"``Its energy lost'' is a second sink beside $\varepsilon$: a link to One length for $K$ and $\varepsilon$; numerical dissipation is excluded by rule, but the clause sits inside the block.", 3),
      (r"$\leftarrow$ Pressure terms: what is diverged for $q^2$ is the down-gradient transport $S_q$.", 2)]),
    ("Wall value",
     r"Lower boundary condition of the energy equation: $q^2 = B_1^{2/3} u_*^2$, from production = dissipation in a neutral constant-flux layer (level 2); applied in every stability. $B_1$: dissipation constant, dimensionless. Schemes: control and Goger port kept, both 3D variants dropped.",
     S + r": Constant-flux layer and Local equilibrium. " + L + r" (by symbol): Universal constants ($B_1$).",
     [(r"$\leftarrow$ Surface fluxes and first level: $u_*$ is the output of the bulk transfer. Formal to formal, not recorded.", 5),
      (r"``Neutral'': the wall balance ignores $P_b$ --- a deliberate \emph{non}-link to the Buoyancy term that the text could name.", 3),
      (r"$\leftarrow$ One length for $K$ and $\varepsilon$: the $\varepsilon$ of the balance is $q^3/(B_1 L)$.", 3)]),
    ("Level-2.5 truncation",
     r"Of all second moments only $q^2$ keeps a prognostic equation; stresses, heat fluxes and the temperature variance are algebraic, their tendencies, advection and transport neglected. (Level 3 keeps the temperature variance prognostic and with it a heat flux against the gradient.) All four schemes keep it.",
     S + r": Local equilibrium. " + L + r" (text): Weak anisotropy (``to leading order in the anisotropy''). " + B + r": Stability functions and cutoff.",
     [(r"K-form fluxes $\leftarrow$ Truncation: the down-gradient heat flux is a consequence of making $\langle\theta^2\rangle$ algebraic; the chain runs through the stability functions only.", 4),
      (r"$\leftarrow$ Return to isotropy (row 19) and $\leftarrow$ Column approximation (row 12).", 3)]),
    ("Surface fluxes and first level",
     r"Fluxes between the ground and the first level $z_1$ from the integrated Monin--Obukhov profiles (bulk transfer coefficients). Needs $z_0 \ll z_1 \ll z_i$ ($z_0$ roughness length): above the roughness sublayer, inside the constant-flux layer. All four schemes keep it --- it is the surface-layer scheme they share.",
     S + r": Monin--Obukhov similarity.",
     [(r"$\leftarrow$ Ergodicity in space / Grid means: an ensemble relation applied to one heterogeneous cell mean (rows 11, 23).", 5),
      (r"Wall value of $q^2$ $\leftarrow$ this block ($u_*$).", 5),
      (r"K-form fluxes $\leftarrow$ this block: the surface flux is the lower boundary condition of the flux divergence.", 4),
      (r"Master length scale $\leftarrow$ this block: the stability parameter of the wall branch comes from the surface scheme. Also $\leftarrow$ Constant-flux layer.", 3)]),
    ("Master length scale",
     r"Harmonic sum of a wall length $L_S$ ($\kappa z$ with a stability correction in $\zeta = z/L_{\mathrm{MO}}$), a turbulent length $L_T$ ($\propto$ the $q$-weighted mean height, of the order of $z_i$) and a buoyancy length $L_B = q/N$ ($N$ buoyancy frequency, s$^{-1}$). One scalar for all directions and all moments; blind to terrain and grid. Schemes: control kept, Goger port partly (own horizontal length for its source), both 3D variants kept.",
     S + r": Monin--Obukhov similarity (wall branch), Mixing length (shape), Universal constants (sliver). " + L + r" (text): Buoyancy term ($q/N$). " + B + r": One length for $K$ and $\varepsilon$; K-form fluxes. " + F + r": both; ``the frontier''.",
     [(r"One scalar length for the whole stress tensor: carried by Similarity through the Mixing length (row 16), so no premise is missing; but the one block the 3D closure keeps says nowhere that its claim is directional (retracted from 7).", 4),
      (r"$\leftarrow$ Column approximation (row 12).", 5),
      (r"Loop $l \leftrightarrow q$: $L_T$ and $L_B$ depend on $q$, $q$ on $l$ through production and dissipation. The page has no block for the $q^2$ budget and a contact rule cannot show a loop; the nocturnal runaway lived in this loop.", 5),
      (r"$\leftarrow$ Spectral gap, Stationarity (rows 1, 4).", 3)]),
    ("Constant set",
     r"One fixed set ($A_1$, $A_2$, $B_1$, $B_2$, $C_1$, \dots) from neutral surface-layer data and large-eddy simulations of neutral and convective boundary layers over flat terrain; used unchanged in stable air over slopes. All four schemes keep it.",
     S + r": Universal constants.",
     [(r"$\leftarrow$ Constant-flux layer + Monin--Obukhov similarity: neutral surface-layer ratios fix several constants (rows 13, 15).", 5),
      (r"$\leftarrow$ Homogeneity, Stationarity: the calibration flows (row 3).", 4),
      (r"Wall value, Stability functions, Pressure terms and One length lean on the \emph{concept} Universal constants, not on this block: concept and formal twin are hard to tell apart.", 3)]),
    ("One length",
     r"$\varepsilon = q^3/(B_1 L)$ with the same $L$ that enters $K = LqS$; $\varepsilon$ isotropic, one rate. No separate dissipation length, no $\varepsilon$ equation. All four schemes keep it.",
     S + r": Universal constants ($B_1$) and Energy cascade (the form). " + L + r" (text): Master length scale.",
     [(r"$\leftarrow$ Local equilibrium: an algebraic $\varepsilon$ follows $q$ and $l$ instantly (row 14).", 4),
      (r"Wall value and Stability functions $\leftarrow$ this block: the $\varepsilon$ of both balances.", 3),
      (r"Any bound put on $l$ (buoyancy limit, strain cap) acts on $K$ and $\varepsilon$ at once with opposite effect on $q^2$; the block's consequence, unnamed.", 3)]),
    ("Pressure terms",
     r"Pressure--strain = Rotta's return (constant $A_1$) + isotropisation of production ($C_1$); the pressure transport of energy is absorbed into a down-gradient energy transport (coefficient $S_q$). All four schemes keep it.",
     S + r": Return to isotropy. " + L + r": Locality (down-gradient transport; text), Universal constants (by symbol).",
     [(r"$\leftarrow$ Buoyancy production: the control also carries the buoyancy parts of the pressure covariances ($C_2 = 0.729$, $C_3 = 0.340$ in \texttt{module\_bl\_mynnedmf\_common.F}); the block lists $A_1$, $C_1$, $S_q$ only.", 6),
      (r"Stability functions $\leftarrow$ Pressure terms: $S_M$, $S_H$ are the solution of the algebraic system these terms define; the two blocks sit side by side on the same parent, unrelated.", 4),
      (r"$S_q$ is tied to $S_M$ in the control ($K_q = 3K_M$): $\leftarrow$ Stability functions / K-form.", 3)]),
    ("Stability functions",
     r"$S_M$, $S_H$ (dimensionless) multiply $lq$ to give $K_M$, $K_H$; they solve the algebraic second-moment equations (Rotta + the level-2 balance of shear production $P_s$, buoyancy production $P_b$ and $\varepsilon$) and depend on the vertical gradients alone. Cutoff: no turbulence beyond the critical flux Richardson number $R_{fc}$. Schemes: control dropped (no cutoff), Goger port partly, 3D-approximate kept, 3D-full partly.",
     S + r": Return to isotropy. " + L + r": Level-2.5 truncation, Universal constants, Column approximation (``vertical Ri alone''), Buoyancy production ($P_b$), Local equilibrium (the balance). " + B + r": K-form fluxes. " + F + r": both.",
     [(r"One contact, five leans: the position shows a sixth of what the block relies on. Candidate cure: split into the \emph{functions} (algebra) and the \emph{cutoff} (a regime claim).", 6),
      (r"Cutoff $\leftarrow$ Stationarity: $R_{fc}$ is the limit of a steady balance (row 4). Most nocturnal valley cells lie beyond it.", 5),
      (r"$\leftarrow$ Pressure terms (row 32); $\leftarrow$ Similarity (row 5).", 4),
      (r"$\leftarrow$ Monin--Obukhov calibration (row 15).", 3)]),
    ("K-form fluxes",
     r"Every flux is local and down its own mean gradient with one scalar $K$ per kind (momentum $K_M$, heat and all scalars $K_H$), aligned with the gradient. How $K$ is built, $K = lqS$, is this closure's construction and not part of the K-form. Schemes: control, Goger port, 3D-approximate partly; 3D-full dropped.",
     S + r": Locality (left) and Eddy viscosity (right). " + L + r" (text): Master length scale ($l$), Stability functions ($S$). " + B + r": Buoyancy term. " + F + r": 3D closure only.",
     [(r"$\leftarrow$ Grid means (the gradient is the resolved one; row 23) and $\leftarrow$ Column approximation (vertical components only; row 12).", 5),
      (r"Vertical shear only $\leftarrow$ K-form (row 24).", 5),
      (r"$\leftarrow$ Level-2.5 truncation (row 27); $\leftarrow$ Surface fluxes as lower boundary (row 28); scalar similarity for ``one $K_H$'' (row 5).", 4),
      (r"Eddy viscosity and K-form say nearly the same sentence twice (``one scalar $K$ \dots'').", 3)]),
    ("Buoyancy term",
     r"$P_b = \beta g \langle w\theta_v\rangle$ for unsaturated air with the constant $\beta = 1/300$ K$^{-1}$; no horizontal heat flux; the flux itself from the K-form. All four schemes partly.",
     S + r": Buoyancy production. " + L + r" (text): K-form fluxes. " + B + r": Master length scale ($q/N$).",
     [(r"$\leftarrow$ Horizontal homogeneity / Column approximation: ``no horizontal heat flux'' (rows 3, 12, 22).", 6),
      (r"$\leftarrow$ Grid means through saturation: partly cloudy cells (row 9).", 4),
      (r"Stability functions $\leftarrow$ this term rather than the concept; Wall value deliberately \emph{not} (neutral).", 2)]),
]
assert len(ROWS) == len(blocks), (len(ROWS), len(blocks))
for r, b in zip(ROWS, blocks):
    plain = b["title"].replace("--", "--")
    assert plain.startswith(r[0]), (r[0], b["title"])

TIERNAME = {0: "Premises (dark grey; left column of the vertical page)",
            1: "Concepts (light grey; middle column)",
            2: "Formalism (white; right column, with moons and the hectometre column)"}

out = []
w = out.append
w(r"""% GENERATED by scripts/make_pyramid_block_table.py from @SRC@ -- do not edit by hand.
\documentclass[10pt]{article}
\usepackage{fontspec}
\setmainfont{lmroman10-regular.otf}[BoldFont=lmroman10-bold.otf,
  ItalicFont=lmroman10-italic.otf, BoldItalicFont=lmroman10-bolditalic.otf]
\usepackage[british]{babel}
\usepackage[paperwidth=240mm,paperheight=180mm,margin=5mm,top=5mm,bottom=8mm,footskip=4mm]{geometry}
\usepackage{amsmath,amssymb}
\usepackage[table]{xcolor}
\usepackage{longtable,array}
\usepackage{microtype}
\setlength{\parindent}{0pt}
\newcommand{\avg}[1]{\langle #1 \rangle}
\newcommand{\pd}[2]{\partial #1/\partial #2}
\newcommand{\qsq}{q^{2}}
\newcommand{\Rfc}{R_{fc}}
\newcommand{\sev}[1]{{\setlength{\fboxsep}{1.2pt}\fcolorbox{black}{black!12}{\bfseries #1}}}
\newcommand{\mi}[2]{\sev{#2}\ \,#1\par\vspace{0.5ex}}
\newcolumntype{P}[1]{>{\raggedright\arraybackslash}p{#1}}
\setlength{\tabcolsep}{2.2pt}
\renewcommand{\arraystretch}{1.12}
\setlength{\LTpre}{0pt}\setlength{\LTpost}{0pt}
\begin{document}
\fontsize{7.6}{9.1}\selectfont
{\large\bfseries The split vertical pyramid, block by block: text, meaning, connections, gaps}\hfill 2026-09-21\par
\vspace{0.6ex}
Source: \texttt{pbl\_assumptions\_pyramid\_split.tex} (texts copied by script, verbatim). Rows run as on the vertical page: top to bottom within a column, premises, then concepts, then formalism. Row numbers are for dictating notes (``row 22, second gap'').\par
\vspace{0.4ex}
\textbf{Column 3} names what the page shows: \textbf{Stands on}/\textbf{Carries} = a drawn contact (derived from the block coordinates); \textbf{Leans on}/\textbf{Leaned on by} = a dependence the contact rule cannot draw, recorded in the source (30 entries since 2026-09-21, each weighted 3 load-bearing / 2 real / 1 bookkeeping; the colour page draws weights 2 and 3); ``text'' = the child's wording names it, ``by symbol'' = only a symbol does, ``source only'' = recorded but invisible on the page. \textbf{Column 4} names what is neither drawn nor recorded, or is recorded but invisible, with a severity in the box: 1--2 bookkeeping; 3--4 a reader misses a real dependence of secondary weight; 5--6 the dependence decides how the block behaves over terrain or in stable air and the page hides it; 7+ the page says or implies something false. A gap that concerns two blocks is scored at both and cross-referenced.\par
\vspace{0.4ex}
\textbf{Symbols:} $l$ mixing length (m); $q$ square root of twice the turbulence kinetic energy (m\,s$^{-1}$), $q^2$ (m$^2$\,s$^{-2}$); $\varepsilon$ dissipation rate (m$^2$\,s$^{-3}$); $K$, $K_M$, $K_H$ eddy diffusivity, for momentum, for heat (m$^2$\,s$^{-1}$); $S_M$, $S_H$ stability functions (dimensionless); $P_s$, $P_b$ shear and buoyancy production (m$^2$\,s$^{-3}$); Ri gradient Richardson number, $R_{fc}$ critical flux Richardson number; $u_*$ friction velocity; $L_{\mathrm{MO}}$ Obukhov length; $z_i$ boundary-layer depth; $\Delta$, $\Delta z$ horizontal and vertical grid spacing; $N$ buoyancy frequency; $A_1 \dots C_3$ closure constants.\par
\vspace{0.6ex}
\textbf{The gaps that matter most} (details in the rows):
\textbf{7} --- none left: the redistribution clause of Buoyancy production was corrected on 2026-09-18 (row 22).
\textbf{6} --- ``no horizontal heat flux'' never touches or names homogeneity (rows 3, 22, 35); the eddy viscosity is derived in this family, not assumed (row 21); the buoyancy part of the pressure terms is absent (rows 19, 32; 5 in row 19 since the slow part is named); the stability functions show one of six parents (row 33).
\textbf{5} --- Grid means is the root of the formal tier but drawn as a leaf (23); shear production takes its stress from the K-form (24); the wall value takes $u_*$ from the surface scheme (26, 28); the column approximation reaches the master length and the K-form unseen (12); the constants are calibrated on Monin--Obukhov (15, 30); the loop $l \leftrightarrow q$ cannot be drawn (29); the cutoff is a steady-state claim (4, 33); the closure's daytime length violates the gradient-scale premise (7). \emph{Added 2026-09-18:} the premise Weak anisotropy, row 6b, split off Small-scale isotropy (Mellor and Yamada 1982, p.~854). \emph{Retracted 2026-09-18:} ``one scalar length has no premise'' (was 7) --- Similarity carries it; now a missing clause, 4 (rows 6, 16, 29). \emph{Applied 2026-09-21} from the tablet notes on the first issue: the cascade names the integral scale in its block (rows 2, 17), the layout clause is struck from Horizontal homogeneity (row 3). \emph{Evening:} the homogeneity channel removed (rows 3, 6, 16: Monin--Obukhov similarity and the mixing length now lean on it, first of their leans), leans weighted.\par
\vspace{0.8ex}
""".replace("@SRC@", SRC))

w(r"\begin{longtable}{|P{5mm}|P{34mm}|P{46mm}|P{43mm}|P{51mm}|P{40mm}|}")
w(r"\hline\rowcolor{black!12}\textbf{\#} & \textbf{1\quad Exact text in the block} & \textbf{2\quad What it says, in detail} & \textbf{3\quad Existing connections} & \textbf{4\quad Missing connections \hfill severity} & \textbf{5\quad Notes (Elias)} \\ \hline\endhead")
tier = -1
n = 0
for r, b in zip(ROWS, blocks):
    # rows keep the numbers of the first issue (2026-09-18 morning); blocks added later get a letter
    new = b["title"] == "Weak anisotropy"
    n += 0 if new else 1
    lab = "6b" if new else str(n)
    t = TIER[b["style"]]
    if t != tier:
        tier = t
        w(r"\multicolumn{6}{|l|}{\cellcolor{black!%d}\textbf{%s}} \\ \hline" % ((30, 14, 5)[t], TIERNAME[t]))
    text = b["text"].replace(r"\\", r"\newline ")
    missing = "".join(r"\mi{%s}{%d}" % (m, s) for m, s in r[3])
    w(r"\textbf{%s} & %s & %s & %s & %s & \rule[-26mm]{0pt}{1mm} \\ \hline" % (lab, text, r[1], r[2], missing))
w(r"\end{longtable}")
w(r"\end{document}")
open(OUT, "w").write("\n".join(out) + "\n")
print("wrote", OUT, "with", len(blocks), "rows")
