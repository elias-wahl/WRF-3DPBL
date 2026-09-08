# DKRZ Levante Antrag — WRF-LES of the Inn Valley: the five core bullets

*Drafted 2026-09-08. Final agreed version: 50 000 node-hours. Numbers marked
"measured" come from the VSC-5 production runs (601×501×80 at Δx = 500 m,
1.5 s per 2-s step on 256 cores ≈ 190 core-h per simulated hour); the LES chain
is scaled from them by grid points and time step.*

**1 — Objective.** 20 m WRF-LES of the Radfeld transect (Inn Valley, TEAMx) to
derive correction functions for UAS-measured turbulence — the objective of the
DFG-funded partner project (virtual flights along the real ascent trajectories,
identical processing chain). Complementary objective of the FWF-funded
applicant: the same runs as turbulence reference for evaluating a 3D PBL
closure in the 500 m grey zone.

**2 — Funding context.** The UAS data, processing chain and joint analysis are
contributed by the DFG-funded group at Tübingen (Platis); the applicant's own
position is FWF-funded. Results feed the DFG project's work packages directly;
research stay in Tübingen spring 2027.

**3 — Feasibility.** Production only: a validated ICON-driven 500 m WRF setup
of the valley is in continuous research use with measured throughput; a 100 m
LES of the same valley exists in the group (Freddi 2026) and supplies the
intermediate nest; no methodological development on Levante.

**4 — Scope and request.** Six full diurnal cycles from the two TEAMx intensive
periods — nights included, because the valley cold pool and stable-layer
turbulence are where the model deficits concentrate and where 20 m resolution
is decisive; the 20 m nest covers the full cross-valley transect with
along-valley fetch (~130×10⁶ points, Δt ≈ 0.1 s, ≈ 160 node-h per simulated
hour, anchored in the measured 500 m throughput). With a three-member
sensitivity suite (subgrid closure, nesting ratio) and a 50 % restart/I-O
margin: **50 000 node-hours, ≈ 60 TB work / 15 TB archive**.

**5 — Data value.** One reference dataset serving three uses — UAS correction
functions (DFG partner project), grey-zone evaluation of a 3D PBL closure
(FWF-funded applicant project), and the first LES-resolved nocturnal cold-pool
budget of this valley — documented and shared with the TEAMx community.

---

## The arithmetic behind bullet 4 (for the resource section)

| component | assumption | cost |
|---|---|---|
| 500 m parent | 24×10⁶ pts, Δt 2 s — **measured** | ≈ 190 core-h / sim-h |
| 100 m nest | ~40×30 km, 12×10⁶ pts, Δt 0.6 s (Freddi-like; confirm extent + Δt against the thesis) | ≈ 320 core-h / sim-h |
| 20 m nest | full transect + fetch ≈ 25×15 km, 1250×750×140 ≈ 130×10⁶ pts, Δt 0.1 s | ≈ 20 000 core-h / sim-h |
| chain total | | ≈ 160 node-h / sim-h (128-core nodes) |
| production | 6 cases × 26 sim-h (24 h + spin-up) | ≈ 25 000 node-h |
| sensitivity | 3 members × 1 case | ≈ 12 000 node-h |
| margin | restarts, I/O, failed segments (×1.33) | → **≈ 50 000 node-h** |

Fallback if reviewers push: 2 sensitivity members → ≈ 42 000 node-h (honest
floor). The dropped extensions that scaled a 100 k variant: 10 cases instead of
6, and a 10 m stable-night pilot (~5 000 node-h) — reusable as a follow-up
request.

**To confirm before submission:** Freddi's 100 m domain extent and time step
(sharpens the intermediate-nest row); the 20 m nest extent (my 25×15 km
assumption moves the total linearly); whether one case needs the multi-layer
stratification rehearsal flagged as a risk in the PhD concept.

---

## DKRZ process constraints (from the allocation rules, added 2026-09-08)

- **Eligibility / who submits:** the PI should be affiliated with a German
  research institution; international groups need a significant German
  contribution. → The proposal should be **led by Tübingen (Platis)** as PI;
  Innsbruck joins as the international partner supplying the model system and
  running the simulations. This inverts the framing of bullets 1–2: it is the
  German DFG project's proposal, with us as contributor — not ours with them
  as anchor.
- **Submission windows:** Sep 1 – Oct 31 (start Jan 1) and Mar 1 – Apr 30
  (start Jul 1). Allocations run 12 months. **The current window is open
  (deadline 2026-10-31, start 2027-01-01).**
- **Compute expires quarterly:** granted node-hours must be consumed roughly
  evenly (unused compute expires after three months). With LES setup planned
  for H1 2027 and production H2 2027, a **Jan 1 start forces ~12.5 k node-h of
  consumption per quarter from January** — either front-load the sensitivity
  suite and the rehearsal case into Q1/Q2, or target the **Mar–Apr window
  (start Jul 1 2027)** whose period matches the production schedule. Decide
  before writing.
- **Pre-/post-processing needs its own compute** (everything runs through
  SLURM): add an explicit line item — virtual-flight sampling, spectra,
  statistics — ≈ 3 000 node-h on top of the 50 k, requested as such.
- **Document limits:** normal first proposal ≤ 8 pages, ≤ 4 000 characters
  per page; required structure = project overview, scientific scope,
  computational/numerical methods, suitability for HLRE-4, **scalability
  (performance vs. node count — our measured 500 m scaling curve 2/4/5 nodes
  covers this)**, resource derivation, added value. Renewals require a
  ≤ 2-page report.
- **No extra paperwork triggered:** the thresholds for a data-storage usage
  plan (≥ 1 000 000 node-h, ≥ 1 024 TiB disk or archive) are far above our
  53 k node-h / 60 TB / 15 TB.
- **Storage policy:** disk is per allocation period (re-request on renewal;
  default path is moving data to archive within the period); unused archive
  grants expire — request archive close to what will actually be written in
  the period.
- **GPU:** not requested — WRF runs CPU-only here; hardware-accelerated
  remote visualization would be the only reason to add it.
