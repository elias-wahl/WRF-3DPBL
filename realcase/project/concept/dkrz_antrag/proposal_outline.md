# Request-document outline — ≤ 8 pages, ≤ 4 000 chars/page

DKRZ's required points, in their order, with our content mapped in and a
character budget that sums to ~30 k (≈ 7.5 pages). Science wording comes from
`antrag_bullets.md` bullets 1–3 and 5; every number in sections 5–7 is in the
arithmetic table there.

## 1. Project overview (~3 500 chars)
One paragraph each: the TEAMx Inn Valley campaign and the UAS turbulence gap
(the DFG project's objective); the 20 m LES as the reference that closes it
(virtual flights, correction functions); partners and funding (PI Tübingen/DFG,
Innsbruck/FWF supplies and runs the model system); deliverables and data
sharing with the TEAMx community.

## 2. Planned work, scientific view (~5 000 chars)
Six full diurnal cycles from the two intensive periods (nights included — the
stable valley boundary layer is where model deficits concentrate); virtual UAS
ascents along the real trajectories through the identical processing chain →
transfer functions vs Δx/z_i; secondary uses: grey-zone partition reference,
LES-resolved nocturnal cold-pool budget. Keep it to what the compute buys —
no closure-development story here.

## 3. Mathematical/computational aspects (~4 000 chars)
WRF (ARW) 4.8; two-stage online nesting 500 → 100 → 20 m; Deardorff 1.5-order
TKE closure in the LES domains; RK3 split-explicit dynamics, terrain-following
grid; ICON 500 m forecasts as forcing (native 65-level conversion, our
icon2wrf pipeline); output: 3-D snapshots + high-frequency column/trajectory
sampling for the virtual flights.

## 4. Numerical methods and solution procedures (~3 000 chars)
Time step ratios (2 s / 0.6 s / 0.1 s), nesting-ratio and damping choices with
the complex-terrain precedents (Wiersema/METEX21, Perdigão, Chow Riviera);
gravity-wave absorbing layer; spin-up strategy per diurnal cycle; the
sensitivity suite (subgrid closure, nesting ratio — 3 members).

## 5. Suitability for HLRE-4 / Levante (~2 500 chars)
Pure-MPI WRF scales on Levante's Milan nodes; the problem is
wall-clock-bound production, not development; group precedents: the running
500 m system (VSC-5) and the existing 100 m LES of the same valley
(Freddi 2026); I/O sized to Levante's Lustre (frame sizes, output cadence).

## 6. Scalability (~2 500 chars + 1 figure/table)
Measured on the 500 m domain (24×10⁶ points, 128-core AMD nodes): 1.5 s/step
on 2 nodes, ~0.8 on 4, 0.65 on 5 — near-linear to 5 nodes at ~190 core-h per
simulated hour. The 20 m nest (130×10⁶ points) has 5× the points per node at
the same decomposition depth → plan 10–20 nodes per LES segment; halo/compute
ratio stays below the 500 m case. State planned node counts per domain.

## 7. Computing time and storage derivation (~4 500 chars + the table)
The table from `antrag_bullets.md` verbatim: measured base → chain cost
(≈ 160 node-h per simulated hour) → 6 × 26 sim-h production (25 k) +
sensitivity (12 k) + ×1.33 margin = **50 k node-h**, + **3 k node-h
pre-/post-processing** (SLURM: virtual-flight sampling, spectra, statistics).
Storage: ≈ 8 GB (100 m) / ≈ 17 GB (20 m) per 3-D frame → 60 TB work over the
period, 15 TB to archive (documented case set + virtual-flight products).
Consumption profile per quarter (match to the chosen start date — see
README open decision 1).

## 8. Added value vs. other projects (~2 500 chars)
One reference dataset serving a DFG project's observational correction, a
closure-evaluation problem of general grey-zone interest, and the first
LES-resolved cold-pool budget of this heavily instrumented valley; reuse by
the TEAMx community; no comparable LES exists at the transect.

---
*Not in the document: the 3D-closure development narrative (scientific
backstory beyond what the compute buys) — DKRZ reviews the computational
case.*
