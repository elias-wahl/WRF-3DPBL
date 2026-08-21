# Decisions log

Append-only, newest first. One entry per judgment call on this project's
science/config setup — not process fixes (those go in the assistant's
lessons file) and not things `branko/realcase/README.md`,
`CHANGES.md`, or `OPEN_ISSUES.md` already document in depth.

---

**2026-08-21 (VSC-5) — Six-run result: the bootstrap trap is real but not the lever — the deficit
is the closure's stable-regime equilibrium; a third of production is unpaid on slopes; the strain
cap is load-bearing; and every run blows up two hours after sunrise.**

`q_sq` = twice the turbulence kinetic energy, m^2 s^-2. `l` = master length scale, the size of the
energy-containing eddies, m. `l0` = the asymptotic scale the Blackadar blend relaxes to away from
the wall, m. `Ri` = gradient Richardson number, buoyant suppression over shear production. `N` =
buoyancy frequency, s^-1. `P/eps` = production over dissipation of `q_sq`. `Sk/eps` = strain rate
times eddy turnover time, what the strain cap bounds. `sf_alpha` = the slope taper, layers a
coordinate surface crosses per grid cell. Six 6 h runs, 2025-07-18 01:00 -> 07:00 UTC (sunrise
~03:40), `pbl3d_opt=2`, 2 nodes x 128 ranks, backfilled 2026-08-20 20:41; archives
`exp/X<n>/wrf_output/<jobid>/`. Measured unless marked inferred.

| run | job | init | `l0` floor | cap `Sk/eps` | reached | s/step |
|---|---|---|---|---|---|---|
| X0 (reference = previous code) | 8477283 | floor | 0 | 6 | 05:52 (CFL, `W` = -334 m/s in one column, then SIGSEGV) | 1.50 |
| X1 | 8477284 | equilibrium | 0 | 6 | 05:59 (SIGSEGV) | 1.47 |
| X2 (candidate) | 8477285 | equilibrium | 8 m | 6 | 06:02 (SIGSEGV) | 1.50 |
| X3 | 8477286 | equilibrium | 4 m | 6 | 06:14 (SIGSEGV) | 1.49 |
| X4 | 8477287 | equilibrium | 8 m | 12 | 01:47 (SIGSEGV) | 1.33 |
| X5 | 8477288 | equilibrium | 8 m | off (1000) | 01:43 (SIGSEGV) | 1.32 |

**Predicted vs measured.** Yesterday's entry predicted a laminar fixed point: with `q` at its floor
the asymptotic scale degenerates to 0.1 m at every level, the run cold-starts there, so starting at
equilibrium and flooring `l0` should lift `q_sq` toward the control. **It does not.** The reference
run, the equilibrium start and both floor values agree on the layer-mean ratio to within +-0.01 at
every output time — 2-4 %.

| ratio 3D / MYNN control (job 8320565), `q_sq` domain mean, lowest ~100 m | 02:00 | 03:00 | 04:00 | 05:00 | 05:30 |
|---|---|---|---|---|---|
| all four science runs, agreeing within +-0.01 | 0.27 | 0.34 | 0.33 | 0.32 | 0.51 |

Absolute: the closure plateaus at 0.11 m^2 s^-2 from 02:30 to 04:00 against the control's 0.31-0.32;
0.39 vs 0.72 at 05:30; the candidate run 0.74 vs 0.91 at 06:00 as the convective boundary layer takes
over. **Correction to yesterday's record: "still rising after an hour" was the tail of spin-up.** The
closure equilibrates by ~02:30 at one third of the control, so numbers taken at 02:00 measured
spin-up, not equilibrium.

**The trap was measured, and it is not rate-limiting.** At 03:00 the median `l0` is already 22.6 m in
the reference run (10th percentile 2.5 m, which the 8 m floor lifts), yet the median `l` in the
lowest five faces is 1.3 m without the floor, 1.4 m with it, against the control's 3.1 m: `l` is set
by the buoyancy and strain limits, not by `l0`. The 10 m wind bias against the control at 04:00 is
unchanged, -0.33 m s^-1 on 0-3 deg slopes and +0.60 on 22-40 deg.

**Where the deficit lives: stable stratification.** At 04:00, faces 17-140 m above ground, binned by
the 3D run's own local `Ri`:

| `Ri` | <0 | 0-0.1 | 0.1-0.2 | 0.2-0.3 | >0.3 (every bin to >5) |
|---|---|---|---|---|---|
| `q_sq` ratio 3D / MYNN | 0.96 | 0.54 | 0.34 | 0.27 | 0.22-0.23 (flat) |

The nocturnal valley air in the lowest 8 levels has median `Ri` 0.68; 69 % of cells exceed 0.25, 42 %
exceed 1 (`N` ~ 0.017 s^-1). Median `l` there, 3D vs control: 9.4 vs 8.5 m for `Ri` < 0, 1.0 vs 3.8 m
for `Ri` 1-2. Where the flow is neutral or unstable the two closures agree within 4 %. **The deficit
is the stable-regime equilibrium of Mellor-Yamada level 2.5 with the 1982 constants, which loses its
turbulence beyond `Ri` ~ 0.2, against MYNN, which holds `q_sq` at 0.15-0.3 there.** That is the
branch named in yesterday's falsification condition, and it is now the live one.

**Caveat, and the next decision turns on it: MYNN is the control, not the truth.** Whether 0.1 or
0.3 m^2 s^-2 is right for this valley at `Ri` ~ 1 is an observational question; the TEAMx
intensive-observation data under `$DATA/TEAMx_sEOP_IOP17` and `$DATA/TEAMx_sEOP_IOP18-20` are the
natural reference (pointer only, not analysed).

**A third of shear production is never paid for by the resolved flow (measured in-model).** The new
diagnostics `KE_LOSS_H` (resolved kinetic-energy tendency from horizontal turbulent momentum mixing,
m^2 s^-3) and `QSQ_SHEAR_H` (the six horizontal-pairing production terms of `q_sq`, m^2 s^-3) close
the check the offline reconstruction could not. Mass-weighted over the lowest ~100 m,
`KE_LOSS_H + QSQ_SHEAR_H/2` leaves a residual of **0.87-0.91 of |QSQ_SHEAR_H/2|** at every time from
02:00 to 05:30 in every run: ~90 % of horizontal-pairing production is created from nothing. At
04:00 that pairing is 36 % of total shear production in the lowest six mass levels, so ~33 % of
total production is spurious domain-wide; on 22-40 deg slopes it is ~120 % of the total with 92 %
unpaid, on 0-3 deg slopes ~0. Consistent (**inferred**) with the 1/`sf_alpha` taper applied to the
tendency but not to the stresses entering production, median `sf_alpha` 5.2. **Note the sign:** a
spurious *source* pushes `q_sq` up and the closure is still 3x low — a consistent closure is lower
still, and part of the 0.5 ratio on steep slopes is this source, not physics.

**The strain cap is load-bearing, and yesterday's analytic claim about it is wrong.** Loosening the
cap to 12, or removing it, brings the nocturnal runaway back within 45 min (crashes 01:47 and 01:43
at the known fragile column near j=54, i=37-38 in the 01:30 frame; max `q_sq` 30 and 20 m^2 s^-2 at
j=49, i=134; 348k / 359k cells with a length-scale back-off and 163k / 199k with `P/eps` > 3 at
01:30, against 36k with `P/eps` > 3 in the reference run at 05:30). **Correction:** the claim that
growth saturates harmlessly once `l` reaches its geometric bound holds in the algebra and fails in
practice — the run hits the CFL limit before the saturated state is reached. The cap stays at 6.

**A new failure, pre-existing: every run blows up 2-2.5 h after sunrise.** All four science runs die
between 05:52 and 06:14 UTC at ridge-top columns, the unchanged code included — not an artefact of
the new switches, and a 47 h run would have failed at ~06:00 regardless. Worst column, reference run
at 05:30: terrain 2513 m, 29 deg slope, sensible heat flux -179 W m^-2 (still downward), friction
velocity 0.51 m s^-1, `q_sq` 8.1 / 23.1 / 34.0 m^2 s^-2 at 17 / 33 / 50 m above ground, `l` 4-7 m,
vertical velocity -7.7 m s^-1 at 17 m, potential temperature 300.5-301.3 K through the lowest 14
levels (neutral). Cells with `q_sq` > 5 m^2 s^-2 go 3-6k through the night, 11k at 05:30, 47k at
06:00. **Inferred mechanism:** neutral, strongly sheared plunging flow over a ridge; the strain cap
binds, so `l ~ q` and `P/eps` stays above 1, and growth is exponential until `l` meets the geometric
bound, where the closure's own equilibrium `q_sq` = b1 l^2 S_m S^2 is O(100) m^2 s^-2 at a strain
rate of 0.5 s^-1. Opened as its own issue in `branko/OPEN_ISSUES.md`.

**The rebuild is bit-for-bit (measured), and reproducibility is fragile.** The reference run's 01:30
frame is identical to job 8476273's in `U`, `V`, `W`, `T`, `Q_SQ`, `L_MASTER`, `PBL3D_T1_RATIO` —
maximum difference exactly 0 — so every difference above is physics, not the build. It cost one
round: a first devel-queue smoke (5 nodes) differed by up to 0.6 m s^-1 in `U` after 10 min because
one factor of the strain-cap bound had been rewritten single -> double precision; reverted (commit
`16fa7407b`). Two 640-rank smokes with and without that change then differed from each other as much
as either differed from the 256-rank reference. **Consequence:** any last-bit change reaches the
whole domain within ten minutes and is amplified locally to O(0.1-1 m s^-1) — attributed
(**inferred**) to the closure's discrete backstops (length-scale halving on solver distress,
realizability projections, floors). Compare runs statistically, never cell by cell; bit reproduction
needs identical decomposition *and* identical arithmetic.

**Decisions.**

(a) **The decision rule is not met; neither fix becomes a default.** The candidate run was not finite
to 07:00, did not hold `q_sq` within 0.5-2x of the control in every slope bin, and did not shrink the
slope-wind bias. The floor on the asymptotic length scale (`pbl3d_l0_min`) and the equilibrium start
(`pbl3d_init_opt`) **stay default-off options** — harmless, they remove a real trap, worth +2-4 %,
and not to be called the fix. The balance limiter stays withdrawn; the cap stays at 6.

(b) **Priority, in this order.** (1) **Fix the slope-factor pairing** — now justified by measurement
rather than code reading: taper the stresses before the horizontal divergence is taken and reuse
those same stresses in production, as WRF core applies the factor to the diffusivity. It changes the
answer, so it must land before any tuning, or tuning rewards the compensating error. (2) **Diagnose
and contain the morning runaway** before any run goes past 05:30. (3) **Then the stable-regime
equilibrium**: first decide the reference (the control is not truth; the TEAMx observations are the
candidate), and only then the closure constants, the buoyancy-limit coefficient (`pbl3d_n_tau_max`,
0.53) or the stratification-aware strain cap (`pbl3d_limiter_opt=2`, built, never run) — one
sensitivity run each, namelist only.

(c) **All six archives are kept**, `exp/X<n>/wrf_output/<jobid>/`, ~280 GB total. Analysis:
`branko/realcase/scripts/compare_mynn.py`, subcommand `exp`.

---

**2026-08-20 (VSC-5) — The closure is turbulence-starved: the asymptotic length scale
collapses to a constant when q² sits at its floor, the run cold-starts at that floor, and the
strain limiter throttles ignition.**

`q_sq` = twice the turbulence kinetic energy, m^2 s^-2. `l` = the master length scale, the size
of the energy-containing eddies, m. `alpha` = the asymptotic-scale constant, 0.1 here. All rows
below are **measured** from job 8476273 (3D closure) against job 8320565 (MYNN-EDMF control) —
same grid, forcing, levels, timestep and surface-layer scheme, both from the state at 01:00.

| at 02:00 | 3D closure | MYNN control |
|---|---|---|
| `q_sq`, lowest ~100 m | 0.085, still rising linearly | 0.316, equilibrated by 01:30 |
| ratio 3D/MYNN, flat 0-3 deg / steep 22-40 deg | 0.14 / 0.36 | — |
| 10 m wind bias 3D - MYNN, flat / steep | -0.32 / +0.56 m s^-1 | — |
| median `l` at 85 m AGL | **0.42 m** | **6.7 m** |
| `l` where `q_sq` sits at its floor (1e-5) | **0.09-0.10 m** (= `alpha`) | n/a |
| cells at the floor, lowest 5 levels, 01:10 / 01:30 / 02:00 | 65% / 41% / 27% | — |
| strain limiter binding, lowest 5 levels, 01:38 | 38% (15% with `l` cut >2x) | no such limiter |

A 0.42 m eddy at 85 m above ground is not a boundary-layer eddy; it is what the formula returns
when it has no turbulence to integrate. **Inferred:** the three open items — "is the damping too
strong", the slope-factor pairing, the "unexplained" slope-dependent wind bias — are one problem,
far too little turbulence energy everywhere. The length-scale unification is not the cause: it
moved `q_sq` by 20-30%, and the deficit is 3.7x.

**Mechanism (code reading, `dyn_em/module_pbl3d_my.F`).** Every bound on `l` in the full-3D path
scales with `q = sqrt(q_sq)`: small `q` gives tiny `l`, hence tiny stresses (they go as `l q`),
hence tiny production, hence `q` stays small. A closed loop with a laminar fixed point.

1. **The asymptotic scale collapses to a constant.** `l0 = alpha * int (q-q_min) z dz /
   int (q-q_min) dz` (`:410-422`) — `alpha` times the energy-weighted height centroid of the
   turbulent layer. With `q` at the floor both integrals degenerate to their 1e-5 seeds, the
   height weighting cancels, and `l0 = alpha = 0.1 m` exactly (**measured** 0.09-0.10). The
   Blackadar blend `l = l0 kz/(kz+l0)` (`:431`) then returns ~0.1 m at *every* level, surface to
   model top. MYNN bounds its equivalent to [8, 400] m (`phys/module_bl_mynnedmf.F:1791`).
2. **The run cold-starts exactly at that fixed point:** `q_sq = 1e-5` everywhere (`:4292`). The
   friction-velocity seed that would break it is dead code (`:4327-4341`) and inert anyway — the
   lowest level never enters the `l0` integral and the level-2 routine overwrites it.
3. The Deardorff stable limit `l <= 0.53 q/N` (`:441-445`; `N` = buoyancy frequency, s^-1) is
   correct physics, MYNN has the same one, and at the floor it gives 0.08 m — it adds nothing to
   the trap once (1) has fired. The strain cap (`:1603-1612`) is the third `l ~ q` bound; below.

**Spin-up is a first-order part of the deficit (measured).** MYNN initialises turbulence at local
equilibrium — five passes of `q_sq = (b1 l P)^(2/3)`, length scale recomputed each pass — and its
layer mean is flat by 01:30. The 3D closure starts at 1e-5 and is still rising *linearly* an hour
later. Every run so far has measured the approach to this closure's equilibrium, not equilibrium.

**The strain limiter throttles ignition; it does not laminarise equilibrium turbulence
(measured).** Fixed run, 01:38, lowest five levels, live cells: where the cap binds, production
over dissipation has median **1.19** (63% above 1) — those cells are *growing*; where it does not
bind, 0.81; without the cap they would sit at median **3.0**. So it slows ignition ~2.5x and holds
nothing down at equilibrium: under any `l ~ q` bound P/eps is independent of `q`, so growth is
exponential until `l` meets a geometric bound (`kz` or `l0`), and with the unified length scale it
saturates (the old blowup cell reaches `q_sq ~ 0.8`, not 44). Its equilibrium footprint duplicates
the Deardorff limit — both shut turbulence off above Ri ~ 0.13 for these constants. It is a
defensible shear length scale, the strain analogue of `q/N`.

**A correction before the fact: the production/dissipation balance limiter designed earlier today
is withdrawn, not deferred.** Its premise was that limited cells sit in decay and should be held
at balance. They sit at 1.19, above balance — the premise is false. A P/eps controller also
carries no physical content of its own and would discard the realizability pre-filter the strain
cap gives the algebraic solve.

**Two corrections to the record.** The strain limiter's footprint was reported as 4.1% of cells;
that was diluted over all 80 levels, most of them free atmosphere — in the lowest five, the
drainage layer where the physics is, it binds in **38%**. And the slope-dependent wind bias was
recorded as unexplained; it needs no slope-dependent cause (**inferred**): turbulence is the
*brake* on a locally forced drainage wind, so too little of it leaves the 3D run fast on slopes
(+0.56 m s^-1), and the *conveyor* feeding momentum down to a remotely forced valley-floor wind,
so too little of it leaves the run slow on flat ground (-0.32). One deficit, two signs.

**Decisions.**

(a) **Floor the asymptotic length scale** — new namelist `pbl3d_l0_min`, default 0.0 = current
behaviour. It removes the laminar fixed point without touching what should bind: `kz` and the
Deardorff limit still apply after the blend, so stable free air stays laminar and only sheared
layers ignite. The value is a judgement — 8 m is `alpha` x 80 m, asserting a turbulent layer with
its energy centroid 80 m up; 4 m is also run, because MYNN's 8 m sits at `alpha = 0.23` and so
corresponds to a ~35 m centroid, not 80.

(b) **Equilibrium initialisation** — `pbl3d_init_opt`, default 0 = current floor start. Option 1
runs the closure's own level-2 solution to equilibrium against the initial shear and
stratification: the same assumption the MYNN control already makes, self-consistent, and required
for the 47 h comparison to be fair. It does not cover re-ignition after turbulence dies mid-run —
the length-scale floor does.

(c) **New diagnostics** `PBL3D_P_EPS` (production over dissipation as built; free, it reuses the
accepted solve), `L0_ASYM` (so the collapse is visible in output), and `KE_LOSS_H` /
`QSQ_SHEAR_H` — the resolved kinetic energy horizontal turbulent mixing actually takes out of the
wind, m^2 s^-3, against the horizontal-pairing part of shear production. Those two are the
subgrid energy-closure check the slope-factor pairing needs. **Compare domain or column integrals,
never points:** pointwise the resolved-KE loss differs from production by a transport divergence,
which integrates away but is large locally.

(d) A **stratification-aware strain cap** (`pbl3d_limiter_opt = 2`, default 1 = present fixed cap)
is built in the same reconfigure but not run this round — it scales the cap by the closure's own
equilibrium `Sk/eps` at the local Richardson number, so "twice equilibrium" means the same thing
at every stratification. Built now only to avoid a second 30-60 min rebuild if the cap turns out
to matter.

(e) **Every new switch defaults to current behaviour**, so the rebuilt binary must reproduce job
8476273 — 1.70 s/step, `q_sq` 0.0847 at 02:00 in a smoke run. That check separates "the fix
changed the answer" from "the rebuild changed the answer".

(f) **One `WRF_OUTPUT_ROOT` per experiment**: `realcase/env/vsc5_X<n>.sh` sources `vsc5.sh` and
sets the root to `$DATA/exp/X<n>`. Concurrent runs otherwise write the same
`temp/branko/wrfout_d01_<date>.nc` and clobber each other *live*, mid-run. Hand-editing
`history_outname` is not the knob; this is.

(g) **Six 6 h runs, 01:00 -> 07:00 through sunrise**, against the MYNN control, every comparison
stratified by slope bin x height bin:

| run | init | strain cap `Sk/eps` | `l0` floor | answers |
|---|---|---|---|---|
| X0 | floor | 6 | 0 m | does the present code reach MYNN if given 6 h? |
| X1 | equilibrium | 6 | 0 m | how much of the deficit is spin-up alone |
| X2 | equilibrium | 6 | 8 m | **the candidate**: floor plus equilibrium start |
| X3 | equilibrium | 6 | 4 m | floor-value sensitivity |
| X4 | equilibrium | 12 | 8 m | does the ignition throttle still matter once `l0` is floored |
| X5 | equilibrium | off | 8 m | upper bound on the cap's role |

Decision rule: adopt the floor and the equilibrium start as defaults if the candidate run (i) is
finite to 07:00, (ii) holds `q_sq` in the lowest 100 m within ~0.5-2x MYNN at 04:00 and 06:00 in
**every** slope bin, and (iii) shrinks the slope-wind bias in both signs. The 4 m run picks the
floor value. If either cap run differs materially from the candidate, the cap is a lever after all
and the stratification-aware version earns its own run. Then the 47 h run; only after that the
slope-factor pairing fix.

**Build state:** `main/wrf.exe` and `main/real.exe` are **missing** — an incremental build was
interrupted at 18:03, objects recompiled and never linked; tracked source is clean at HEAD.
Nothing runs until the next build, and that build is the `--reconfigure` these Registry entries
require anyway.

---

**2026-08-20 (VSC-5) — The length-scale fix works: `pbl3d_opt=2` completed its first
real-terrain run. And the `sf_alpha` defect is now the bigger problem.**

Job 8476273: `COMPLETED 0:0`, 1800 steps, 01:00 -> 02:00, zero errors, 1.696 s/step. At
01:38:00, where every previous run died: 0 non-finite cells against 8.3e6, max `Q_SQ` 30.3
against 44.5, max `|W|` 14.2 against 26.5 m/s. Domain max `Q_SQ` at 01:37 went 150.5 -> 18.5,
and the argmax stopped locking onto one cell. The mechanism diagnosed in A9 was the cause, and
unifying the master length scale removed it. Ten lines, no new parameter.

**Two of my own predictions failed, and both are recorded in A9 rather than quietly dropped.**
The predicted `P/eps` of ~0.46 at the blowup cell measured 24.6 — because the cell never
reached the runaway state at all (`Q_SQ` 0.43 against 18.1), making it a ratio of two near-zero
numbers. The prediction was linearised: it assumed the flow would arrive at the same state and
only the ratio would change, when in fact the fix is active from 01:05 and the trajectories
diverge for half an hour first. A counterfactual at fixed state is not a forecast and should
not have been written as one. Separately, an interim comparison table showed baseline and rerun
identical at 01:38 because the rerun had not yet overwritten the baseline's file — filter by
mtime when comparing against `temp/branko/`.

**The `sf_alpha` footprint was badly underestimated, and this changes the priority order.**
A9 described it as affecting the 208 points steeper than 30 deg. Measured across all 300,000
columns: median `sf_alpha` is **5.2**, and it exceeds 2 over **67%** of the domain and 5 over
**51%**. The reason is the grid, not the terrain — `dx/dz ~ 30`, so a 2 deg slope already gives
1.05 and 10 deg gives 5.3. Horizontal turbulent mixing is suppressed five-fold or more over half
this domain, while the production computed from the same stresses is not. Opened as A10.

**An attempt to quantify the resulting energy error failed, and the number is retracted.**
Reconstructing `P_vert` offline from `TURB_FLUX_UW/VW/W2` plus gradients from U, V, W, and
taking the residual against `Q_SQ_SHEAR`, gave "59% of production is spurious". Its sanity check
then showed correlation 0.067 between the reconstructed `P_vert` and the model's own
`Q_SQ_SHEAR` — so the residual was reconstruction error, not physics. Reported here because a
plausible-looking number from a failed method is worse than no number.

**Revised priority: build the SGS energy-closure diagnostic BEFORE the 47 h control run.**
I previously argued it could be deferred, on the grounds that a surviving run would be indirect
evidence about `sf_alpha`. The run survived and told us nothing about it — exactly as the
falsification condition said it would. The stronger argument is now this: the A9 fix *damps*,
`sf_alpha` is a spurious *source*, and two large errors of opposite sign may be partially
cancelling. Tuning against MYNN in that state would reward the cancellation rather than expose
it. The diagnostic costs one Registry field and one reconfigure, and it measures the mismatch
inside the model where the offline reconstruction cannot reach.

**Still unsettled:** domain `Q_SQ` runs 20-30% below baseline through the window. Whether that
is correct damping or over-damping remains the open 17-41% boundary-layer question, and only the
47 h MYNN comparison answers it.

---

**2026-08-20 (VSC-5) — Implemented the unified master length scale. This reverses yesterday's
"deliberately not implemented".**

Yesterday's entry deferred this fix because it is a science change and the scope call was the
user's. That call has now been made, after a physical re-derivation that made three things
clearer than they were.

**Why it is a bug fix and not a tuning change.** In Mellor-Yamada the master length scale does
two jobs that come from the *same* picture — an eddy of size `l` moving at speed `q`. It is the
displacement that sets the flux (`P ~ q l`), and it is the lifetime `l/q` that sets the cascade
rate (`eps = q^3/(b_1 l)`). Those are one geometry read twice. So an eddy that transports like a
2.41 m eddy and dissipates like a 6.04 m one is not a defensible modelling choice; it is not a
physical object. Tier 1's finding is "the eddies are smaller than you assumed", and smaller
eddies both transport less *and* die sooner. The code implemented the first and dropped the
second, leaving turbulence that is simultaneously weakly-mixing and long-lived — which is the
opposite of what strong shear produces.

**The size of the error is the size of the failure.** At the blowup cell the turbulence is given
a lifetime of 11.8 s when its own asserted 2.41 m permits 4.7 s. At 01:25, where the instability
is seeded, 1.21 m eddies are given 395 s against a permitted 78 s — five times too long. The
runaway e-folds in 105 s. An error of two-to-five-fold in the lifetime of the energy-containing
eddies, in a process whose own timescale is the same order, is not a bookkeeping detail.

**Blast radius, measured rather than assumed.** Yesterday's entry worried this changes the
solution broadly. It does, but less than feared: at 01:36 Tier 1 is active in 4.1% of cells, and
among those the *median* `T1_RATIO` is 0.71 — a 40% increase in dissipation for the typical
affected cell, not the 5.6x seen at the blowup point. Only the worst 5% (`T1_RATIO ~ 0.10`) see a
tenfold correction, and that tail is exactly where the runaway lives. Tier 1 activity is 0% at
01:00 and grows monotonically to 4.1% by 01:36 as the drainage layer spins up.

**Implementation choice worth recording: `dg_t1_ratio`, not the final `l_use`.** `dg_t1_ratio` is
set at `module_pbl3d_my.F:1584`, before both Tier 2 loops, so it carries the Tier 1 result alone.
That is what we want. Tier 1 is a physical claim about eddy size; Tier 2 shortens `l` in response
to solver distress or non-realizability, and a failed linear solve is not evidence that the
eddies got smaller. Feeding numerical distress into the dissipation would be a different bug.
A happy consequence: `Diagnose_fluxes` needed no modification at all — the write is one line in
the caller, where the `pbl3d_*` diagnostics are already stored.

**A trap that would have failed quietly.** `Calc_l_master_algebra` copies `ktf` up to `kte`
*before* the point loop runs. Without redoing that copy afterwards, the model-top face keeps the
unlimited value while `ktf` holds the limited one — and `Fill_l_mass_with_l_face` and both
`xkxavg` blocks read index `kte`. It would not have crashed; it would have been subtly wrong at
one level. Edit B exists for that.

**Deliberately still out of scope.** Three other changes were designed and are not in this
commit: the SGS energy-closure diagnostic (needs a Registry field, hence a full reconfigure), a
budget-based `P/eps` limiter threshold (insurance for near-neutral regimes; it would not fire at
this blowup cell once the length scale is unified), and pairing the `sf_alpha` slope taper with
its production terms (larger, and it depends on the diagnostic to justify). A fourth — using
perpendicular rather than vertical wall distance in `kappa*z` — was dropped: the geometry is
right, but it is ~17% at the steepest points, it is inconsistent with WRF's vertical-height
surface layer, and it would have muddied attribution of the first test.

**No namelist switch, on purpose.** A new namelist variable is a Registry change and would have
forced a 30-60 min reconfigure for a ten-line source edit. The old behaviour is reproducible by
reverting the commit, and the baseline output is preserved
(`wrf_output/8472687/baseline_qsq_subset_k0-9_0125-0138.nc`, 1.1 GB, lowest 10 levels,
01:25-01:38) because the rerun overwrites `temp/branko/`.

**Falsifiable predictions, recorded before the result.** At `j=111, i=161`, stag `k=1`, 01:36:
`P/eps` 1.146 -> ~0.46; cascade timescale 11.8 s -> ~4.7 s; `L_MASTER` 6.04 -> ~2.41 m; and the
run clears `2025-07-18_01:38:00`. If it still dies there, the split length scale is not
sufficient and the `sf_alpha` energy-pairing hypothesis becomes primary. If it clears but a
different cell runs away, the budget limiter is needed. If it clears but boundary-layer q^2 falls
further below the MYNN control, this over-damps and the budget limiter should replace the fixed
`SK_EPS_MAX` so limited cells sit at balance rather than decay. Job 8476273.

---

**2026-08-20 (VSC-5) — A9 closed by measurement; two earlier statements corrected; still not implementing the fix.**

Job 8472687 ran ahead of its estimated start and completed all 39 one-minute `qsqdiag`
frames through 01:38 before the terminal RRTMG segfault. The measurement A9 was waiting
for exists, and it lands on **branch 1**: at the blowup cell (`j=111, i=161`, 46.639 N
10.806 E, 33.6 deg slope) `T1_RATIO` runs 0.18-0.40 for the entire event and `SK_EPS`
15-34 against a limit of 6.0. Tier 1 is not blind to the strain; it binds hard and the
binding is what fails. `P/eps` as built sits at 1.09-1.23 for eight consecutive minutes
(e-folding 105 s, doubling 73 s); with a consistent length scale it is 0.43-0.60 in every
frame. Snapshot written to `FINDINGS_QSQ_RUNAWAY.md` (root + `realcase/project/`).

**Correction 1 — Tier 2 and Tier 3 are not globally dead.** A9 and the 2026-08-19 entry
say `T2_STEPS = T3_FLAGS = 0`. Domain-wide at 01:36 that is wrong: T2 fires in 294,398
cells (max 5), T3 in 60,156 (max 240). The true statement is narrower and worse - they
are silent *at the runaway column* (T3 zero at every level, every frame; T2 only
sporadically 1-2 at k=3). Tier 2 escalates on solver distress and non-realizability;
Tier 3 enforces PSD. A budget running 15% hot is neither, so nothing in the ladder can
see this. Recorded because "the backstops never fire" and "the backstops cannot see this
failure" lead to different fixes, and only the second is true.

**Correction 2 — the Tier-1 footprint is 4.1%, not ~20%.** `T1_RATIO < 0.999` in 977,518
of 24,000,000 cells at 01:36; `< 0.5` in 1.06%. The ~20% / 899,613 figure was a different
frame of a different job. It does not change the recommendation - Group F still has Tier 1
binding at 100% in nocturnal SBL, slope drainage and residual-LLJ - but the number in the
previous entry was five times too large and would have overstated the blast radius.

**Resolved:** that entry's honest-limit caveat asked for `SK_EPS > 12.6` co-located at
01:36. Measured 15.07. The conclusion no longer rests on the `T1_RATIO = min(1,
SK_EPS_MAX/SK_EPS)` identity alone.

**Why a snapshot file rather than the fix.** The ask was to save findings so work can
resume later, and the fix remains what the 2026-08-19 entry said it was: a science change
touching every cell where Tier 1 fires, needing revalidation against the 47 h MYNN control
and the idealized regressions. Writing it down with its falsification condition keeps the
scope decision with the user and on evidence. Committed locally, not pushed, at the user's
instruction.

**Also corrected, on a separate point:** an exploration pass flagged that
`realcase/namelist.input.mynn` and `namelist.input.pbl3d` are not matched (24 h vs 47 h,
`time_step` 3 vs 2, `epssm` 0.7 vs 0.9, `sf_sfclay_physics` 5 vs 1) and inferred the MYNN
control was therefore not a controlled comparison. It was. The 47 h control is job 8320565
run from `WRF/run/namelists/namelist.input_inn_inner_dom_ICON`, which uses `time_step=2`,
`epssm=0.9`, 47 h and `sf_sfclay_physics=1` - the same surface layer as pbl3d. The tracked
`namelist.input.mynn` is a template that was never the control. Left alone; the confound
noted in its header does not apply to the run the exclusions rest on.

---

**2026-08-19 (VSC-5) — Diagnosed the blowup as a split master length scale, and did NOT
implement the fix.**

The deep dive landed on a structural inconsistency rather than a missing limiter:
`Q_SQ_SHEAR` scales with Tier 1's limited `l_use` (a local scalar in the solver, never
written back), while `Calc_q_sq_dissip` uses `l_dissip = l_master`, the unlimited scale.
Because `eps ~ 1/l`, Tier 1 firing reduces production and simultaneously leaves dissipation
under-estimated by the same factor — it widens the imbalance it exists to close. Making the
scales consistent takes `P/eps` at the blowup cell from 2.11 to 0.73, below unity, with no
new parameter. Full reasoning and the grey-zone measurements are in `OPEN_ISSUES.md` A9.

**Why this and not a production cap:** in Mellor-Yamada the master length scale is singular
by construction — the same `l` sets the stress closure and `eps = q^3/(B_1 l)`. The k-epsilon
analogy that would justify leaving dissipation alone does not transfer, because there `eps`
is prognostic and here it is *diagnosed from `l`*. So this is removing an inconsistency, not
adding a mechanism, which is what makes it different in kind from the shear-production cap
A9 rules out.

**Deliberately not implemented.** Tier 1 was active in ~20% of the domain at 01:30, so this
changes the solution broadly and is a science change, not a bug fix. Implementing it
unasked would have put an unvalidated physics modification into a tree whose whole purpose
is diagnosing a numerical instability — and it needs checking against the 47 h MYNN control
and the idealized regressions, which is the user's call on scope and priority. Written up
with the falsification conditions instead, so the decision is theirs on evidence.

**Honest limit of the result:** `T1_RATIO = 0.345` derives from A9's `SK_EPS = 17.4`, which
is quoted as a *peak*, not co-located at 01:36. The correction suffices at that frame iff
`SK_EPS > 12.6` there. Job 8472687 carries both at 1-minute resolution; its estimated start
slipped to 2026-08-20T21:30, so the conclusion is on the identity and the source reading
until then, both of which are checkable without it.

**2026-08-19 (VSC-5) — Read the limiter's source before waiting 33 minutes for its
output, and the run became a confirmation rather than the measurement.**

A9 framed `PBL3D_T1_RATIO` as a missing measurement costing one rerun. Reading the Tier 1
block first showed it is not independent data at all: `l_use`, `dg_sk_eps` and
`dg_t1_ratio` are computed from the same `strain_mag`, `l` and `q` in one pass, which
forces `T1_RATIO = min(1, SK_EPS_MAX/SK_EPS)` algebraically. Confirmed on archived
`wrfout` across 4.3e6 cells at 9.5e-08 maximum deviation, so it is an identity in
practice and not just on paper. `SK_EPS = 17.4` at the blowup cell was already measured
in job 89435, so `T1_RATIO = 0.345` there and the branch was already decided.

**Judgment: report it now rather than wait for the queue.** The derivation is checkable
in ten lines of source and was verified against millions of cells; holding it back until
job 8472687 lands would delay a result that redirects the next piece of work, and the run
still serves as independent confirmation at 01:36-01:37 where no `wrfout` frame exists.
The run was left queued rather than cancelled for exactly that reason — a derived result
and a measured one disagreeing would itself be important.

**Consequence for the fix, recorded because it narrows the search:** branch 2 is dead.
`strain_mag` is not misreading the terrain-following gradients — it reports `S k/eps`
at ~3x the limit and Tier 1 cuts `l` to 34.5%, and q^2 explodes anyway. Meanwhile Tier 2
and Tier 3 never fire, because they escalate on solver degeneracy and stress
realizability, and at that cell the solve stays well conditioned and admissible
throughout. So no tier is triggered by the thing that actually goes wrong. That is a
design gap in the escalation ladder rather than a coding bug, which also explains why
`pbl3d_opt=1` survives untouched: its 1D shear production never gets large enough to
need a tier that does not exist.

**Not done, deliberately:** no fix attempted. The next question — whether
`SK_EPS_MAX = 6.0` is simply the wrong bound in strong katabatic strain, or whether Tier
2 needs a budget-based escalation test beside its solver/realizability ones — is a
science decision for the user, and the crash is a clean deterministic regression test for
whichever is chosen.

**2026-08-19 (VSC-5, job 8472687) — Added four fields alongside `PBL3D_T1_RATIO`, and
did not rebuild.**

*No rebuild.* A9 asks for one iofields line and no code change, and that is right, but it
was worth confirming rather than assuming: `pbl3d_t1_ratio` is registered for history in
the **built** binary (`streams(1) = 1` in `inc/allocs_*.f90`), the pull touched only two
`.md` files, and no source is newer than `main/wrf.exe`. So the VSC-5 build from earlier
today stands. (Minor correction to A9's wording: `pbl3d_t1_ratio` is flagged `h`, not
`rh` — history without restart. Irrelevant to this measurement, which only needs history.)

*Carried four extra fields.* `PBL3D_SK_EPS`, `PBL3D_T2_STEPS`, `PBL3D_T3_FLAGS` and
`L_MASTER` were added to stream 23 next to `PBL3D_T1_RATIO`, at ~96 MB/field/frame
(~44 GB total instead of ~25 GB). Reason: A9 itself notes `SK_EPS` is computed from the
**pre-limit** `l`, so it shows Tier 1 had work to do but **not** whether `l_use` was
applied — only `T1_RATIO` and `SK_EPS` *together* separate "the limiter bound and failed"
from "the limiter never bound". Reading them from different frames, or inferring `SK_EPS`
from 10-minutely `wrfout` while `T1_RATIO` comes at 1 minute, would reintroduce exactly
the non-co-located comparison that made `Q_SQ_HDIFF` look like a source. `T2_STEPS` and
`T3_FLAGS` confirm at 1-minute resolution what `wrfout` could only show at 10, and
`L_MASTER` shows whether `l` moved at all. The marginal cost is one run's disk, against
the risk of needing a second 33-minute run to answer a follow-up.

*Already true from a free reading of archived `wrfout` (job 8464723, 01:30):* at A9's
blowup cell (4,182,514) `T1_RATIO = 1`, `SK_EPS = 4.611`, `T2_STEPS = T3_FLAGS = 0`,
`L_MASTER = 15.95`. `SK_EPS` is **below** the 6.0 limit there, so `T1_RATIO = 1` is Tier 1
correctly doing nothing rather than failing to act — which pins down that `T1_RATIO = 1`
is the "did not bind" value, and confirms the cell is still quiet eight minutes out. It
also confirms A9's claim that no `wrfout` frame covers 01:36-01:37: the last one before
death is 01:30.

*Analysis tooling gained a `--cell K,J,I` mode* that reports every term co-located at one
cell and sums them to a net, because "a domain maximum is not a budget" is the lesson A9
paid for once already and the tool should make the right comparison the easy one.

**2026-08-19 (VSC-5) — Staged the q^2 diagnostic run: reused `real.exe` output, and let
the validator overrule a sizing "optimisation".**

*Skipped `real.exe`.* Linked the existing `wrfinput_d01`/`wrfbdy_d01` from
`branko_runs/innval_pbl3d_18th` rather than regenerating them, which saves a whole queue
cycle. `CLAUDE.md` calls re-running `real.exe` after a rebuild the safer default, and that
is right in general — but here the only change is `r -> rh`, which is an **output** stream
mask. Verified rather than assumed: in `inc/allocs_4.f90` the promoted `Q_SQ_SHEAR` now has
`streams(1) = 1`, identical to `TURB_FLUX_UW` (already proven to reach `wrfout`), while
still-`r` `Q_SQ_TMP` has `streams(1) = 0`. Input membership is untouched, so `wrfinput`
cannot have changed. `check_wrfinput.py` passes on the linked files (SMOIS mean 0.284,
slope max 34.2 deg). These are also the exact files job 8464723 crashed from, which makes
the rerun a direct comparison rather than a fresh trajectory.

*This also explains a scare:* all four rebuilt binaries have byte-identical sizes to the
Aug 18 ones. That is not a stale build — WRF's field registry is a runtime data table, so
promoting a variable to history flips a bitmask constant without changing code volume.

*Rank count 256, not 200.* Running 2 nodes x 128 = 256 ranks per the VSC-5 convention,
where job 8464723 used 200 (2 x 100). The decomposition therefore differs, so **the exact
crash step may shift by a step or two — that is decomposition sensitivity, not a failure of
the determinism A9 documents.** Accepted because the question ("which q^2 term runs away")
is about a feedback developing over eight minutes and is not sensitive to a step, and
because a fresh throughput number at the full node was explicitly wanted. Baseline to beat,
measured here rather than imported from MUSICA: **1.405 s/step on 200 ranks**, 1140 steps
to the blowup, ~27 min.

*Reverted an "optimisation" the validator caught.* Set `auxhist24_interval_m = 0` to skip
~75 GiB of WRFlux means that have nothing to do with A9 — and `prepare_namelist.py`
correctly refused it: `flux output is on but no auxhist24 interval is set`. Restored to 10.
The saving was never real (the run dies at 01:38, so only ~4 frames are written) and the
alternative — also disabling WRFlux flux output — would have changed the model
configuration relative to every reference run to save under a minute of I/O. Logged because
the instinct to trim a diagnostic run's output is a good one that was wrong here, and
because it is a clean case of the namelist validator earning its place.

**2026-08-19 (VSC-5, back from MUSICA) — Rebuilt with `--reconfigure`, not a plain
`./clean`, and recorded that the blowup is cross-cluster.** Two calls worth keeping.

*Why the full clean.* The rebuild here exists to get the five `q_sq_*` budget terms into
`wrfout` via the `r -> rh` promotion. This checkout's generated `Registry/Registry` and
`inc/*.inc` were dated Aug 17-18, i.e. **stale against the Aug 19 Registry commit**, and
reading `clean` shows only the `-a` branch removes them. A plain `./clean` would very
plausibly have produced a binary that builds, runs, costs a 30-minute queue slot and
writes an `auxhist23` stream with five silently missing fields — the failure mode this
project keeps meeting (`SMOIS`, E13, U2) where the wrong answer is quiet. The extra few
minutes of `./configure` is not a tradeoff worth thinking about. Verified afterwards that
`q_sq_shear` appears in exactly the same generated files as `turb_flux_uw`, a variable
already proven to reach `wrfout`.

*The crash is not MUSICA's.* Checked the archived VSC-5 job **8464723** (2026-08-19 16:06,
`pbl3d_opt=2`, this cluster, gcc 12.2 / OpenMPI 4.1 / zen3): its `rsl.out.0000` stops at
`Timing for main: time 2025-07-18_01:38:00` — the **same step** as MUSICA jobs 88703 and
88971 under an entirely different toolchain (EESSI gcc 13.3 / OpenMPI 5.0.3 / zen4). This
was free — the evidence was already on disk — and it retires the residual "MUSICA
compiler artifact" hypothesis that would otherwise have shadowed every result from the
rerun. A9 is updated. Note `rsl.error.0000` is clean because rank 0 was not among the 81
that faulted, which is consistent with A9 and not evidence of a different failure.

*Deliberately not touched:* the env loads **both** `openmpi/4.1.6` (explicit) and
`openmpi/4.1.4` (pulled in as a dependency by a later module), and 4.1.4 wins on `PATH`,
so `mpif90` is 4.1.4. Left alone: 4.1.x is ABI-stable, this is the exact env that produced
the working Aug 18 binaries, and re-picking modules mid-campaign would invalidate the one
build configuration known to work here while changing nothing about the physics question.
Recorded rather than fixed, so it is not rediscovered as a surprise.

*Config, reverted from MUSICA:* account `p72996`, partition/QOS `zen3_0512`
(devel `zen3_0512_devel`, MaxWall 10 min), **128 physical cores/node** (8 sockets x 16,
`ThreadsPerCore=2`, so SLURM reports `CPUTot=256`) — all read off `sacct`/`scontrol`, not
assumed. `CORES_PER_NODE` went 100 -> 128; earlier VSC-5 jobs here used 100 ranks/node
(job 8464711), so **throughput is not comparable with those without scaling**, any more
than it is with MUSICA's 1.26 s/step on 190 ranks. Also made `SLURM_ACCOUNT_DEFAULT` /
`_PARTITION_` / `_QOS_` actually do something: they were dead variables, and
`setup_rundir.sh` now substitutes them into the `CHANGEME` slots, so the values live in
the env file instead of being retyped into every run dir. `CHANGEME` survives when the env
file is silent, so the guard against submitting to the wrong project is intact.

**2026-08-19 (later) — Resolved: the crash IS in the scheme's domain, and the earlier
entry below is half wrong.** The 1-minute diagnostic rerun (job 88971) settles what the
entry below deliberately left open. Radiation is only where the corpse fell: the model
blows up over eight minutes beforehand as runaway near-surface `|W|` in nocturnal
katabatic drainage on 33.6-degree slopes, and `W / u.grad(h)` climbs 1.68 -> 2.96 while
the downslope wind accelerates 3.5x, so it is a genuine feedback and not terrain-following
kinematics. Recording this rather than quietly editing the entry below: the instinct to
resist blaming our own scheme was right as a *method* (it stopped a guess becoming a
conclusion) but wrong as a *prediction*, and the log is more useful if it shows that.

What the entry below still got right: refusing to set `ra_lw_physics = 0`. Had we done
that, the run would have proceeded past 01:38 with the drainage-flow instability intact
and no segfault to announce it — the silently-wrong outcome, on the first nocturnal case
this project has ever run.

Deliberately **not** applying the U2 index guard yet, for the same reason. It would
convert a loud, perfectly deterministic crash (same step, same 81 ranks, same address
across two runs) into a NaN quietly propagating through the radiative tendency. The guard
is correct and should land eventually — but after the blowup is understood, not before,
and never as the thing that "fixes" this.

Next discriminator chosen: **run the MYNN control on identical terrain** before touching
any `pbl3d` code. It is cheap, it is already a supported configuration, and it separates
"this closure under-damps slope flow" from "dx=500 m cannot resolve a 34-degree slope at
all" — a distinction that decides whether the fix is in the scheme or in the terrain
treatment. Guessing between those two would be expensive in both directions.

**2026-08-19 — Not treating the first real-terrain crash as a `pbl3d` regression, and
not disabling radiation to get the run through.** The smoke run (MUSICA job 88703)
segfaulted at 01:38 inside RRTMG-LW. It would have been quick to blame the 3D PBL
scheme, since this is its first real-terrain and first nocturnal case; and quicker still
to set `ra_lw_physics = 0` and "make it run". Both rejected. Disassembly puts the fault
on an upstream one-sided bounds guard (`KNOWN_ISSUES.md` U2), and the physics question —
which component emits the NaN that guard turns into a wild pointer — is logged as A9 in
`OPEN_ISSUES.md` rather than assumed. Turning radiation off would not be a workaround
but a different experiment: this is a cold-pool case, and longwave cooling is part of
the mechanism under study. Rationale for the ordering: U2's own guard converts the crash
into a *silent* NaN in the radiative tendency, so applying it before knowing the NaN
source would trade a loud failure for a quiet wrong answer — the exact failure mode the
`SMOIS` check in `realcase/README.md` exists to prevent.

**2026-08-19 — Migrating the operation to MUSICA (Innsbruck); VSC-5 job 8464723
never ran (`ReqNodeNotAvail`, whole `zen3_0512` partition down).** Moving
everything (~100 GB) rather than a minimal working set, so MUSICA is a
self-contained replica and nothing has to be re-fetched later. `branko/` and
`icon2wrf/` go over git (a fresh clone also guarantees no stale VSC-5 `.o` files
survive into the mandatory rebuild); bulk data goes by rsync over SSH.

**2026-08-19 — MUSICA builds against EESSI `gompi-2024a` (GCC 13.3.0), not the
newest toolchain available.** EESSI 2025.06 also offers `gompi-2025a` (GCC
14.2.0) and `gompi-2025b` (GCC 14.3.0). Chose the oldest because the scheme is
verified with gcc 11.2 and was built on VSC-5 with 12.2, so 13.3 is the smallest
step available; `gompi-2025b` ships no netCDF-Fortran at all; and GCC 14 tightens
argument-mismatch diagnostics further while WRF's configure only knows to pass
`-fallow-argument-mismatch` for GCC ≥ 10. Escalate to `2025a`, not `2025b`, if
13.3.0 fails.

**2026-08-19 — LAPACK on MUSICA is FlexiBLAS (`-lflexiblas`), replacing
`-llapack -lblas`.** EESSI ships no standalone LAPACK; FlexiBLAS provides both
APIs in one library. Verified rather than assumed: `dgesvx_` is in
`libflexiblas.so`, and a test program calling `dgesvx('E','N',...)` compiled,
linked and ran on MUSICA returning the correct solution — the check that matters,
since the closure calls it at every grid point on every timestep.

**2026-08-19 — MUSICA transfer used SSH connection multiplexing, not a `step`
certificate.** MUSICA is certificate-only for external logins (`authorized_keys`
is refused — verified with a byte-perfect key), and `step ssh login`/`step ssh
certificate` both fail at Authentik with "failed to resolve application" despite
the OIDC discovery document resolving and the device endpoint returning HTTP 200.
Rather than block on ASC support, one interactive device-auth login establishes a
`ControlMaster` socket that every subsequent rsync reuses. Constraint: the socket
is node-local, so the master and the transfers must run on the same VSC-5 login
node (l55 here).

**2026-08-19 — Output root parameterized as `WRF_OUTPUT_ROOT` instead of
hand-editing namelists per cluster.** `history_outname`/`auxhist24_outname` and
`submit_wrf.slurm`'s archive destination all carried absolute VSC-5 paths, which
contradicted `realcase/env/template.sh`'s own rule that nothing cluster-specific
belongs in namelists or SLURM scripts. The templates now carry an
`@OUTPUT_ROOT@` token expanded by `prepare_namelist.py --output-root`; the layout
below the root (`temp/branko/`, `wrf_output/<jobid>/`, `frames_per_outfile=1`)
is unchanged and deliberately identical on every cluster, so `proc/` keeps
finding this fork's output the same way. Expanding with the VSC-5 root reproduces
the previous paths byte for byte. An unexpanded token is FATAL, matching the
existing `num_metgrid_levels = 0` convention: fail at setup, not mid-run.

**2026-08-19 — `namelist.input.mynn`'s relative `auxhist24_outname` left as-is,
not brought into the shared output tree.** It writes into its own run directory
while `pbl3d` writes to `temp/branko/`, so the two configs are not actually
"identical outside the turbulence configuration" as `realcase/README.md` claims.
Rejected fixing it: relocating output could strand post-processing that already
expects it there, and it is not what this migration is about.
`prepare_namelist.py` now warns instead, so the inconsistency is visible rather
than silent.

**2026-08-19 — `phys/noahmp` and `phys/physics_mmm` pushed to personal forks
rather than carried as bundles or rsync'd `.git` dirs.** Both had exactly one
local commit (the 33-category CORINE table; the `sfclayrev` lower-bound guard)
on submodules whose remote is NCAR upstream, so those SHAs existed only on the
VSC-5 disk and `git clone --recursive` would abort anywhere else. Forking makes
the tree reproducibly cloneable on any future cluster; the bundle and
rsync-the-`.git` alternatives both work once and leave the same trap set for
next time. Gitlink SHAs are unchanged — forking copies commits byte for byte, so
only `.gitmodules` moved.

**2026-08-18 — Land-use categories 28/31-33 (CORINE-as-USGS) get copied
parameter rows, not distinct values or new physics.** Category 28 (lake)
copies row 16 (Water Bodies); 29-30 (unused in this domain) copy row 19
(Barren) as inert placeholders; 31-33 (urban) copy row 1 (Urban and
Built-Up). Rejected: building true CORINE-specific values (no CORINE
VEGPARM table exists anywhere in the project) and enabling urban/lake
physics (`sf_urban_physics`/lake scheme are off everywhere in this
project; out of scope for a grey-zone PBL run, not what's being studied).

**2026-08-18 — `MVT=27→33` bumped only in `phys/noahmp/drivers/wrf/`, not
`hrldas`/`lis`/`erf`.** Only the WRF driver is exercised by this build;
touching the others would be an unrequested, unverified change.

**2026-08-18 — Namelist merge is a union of ICON's namelist and the stock
`pbl3d` template; ICON's value wins on overlap.** Exceptions: the pbl3d
hard constraints (`bl_pbl_physics`/`hybrid_opt`/`diff_opt`/`tke_budget`,
enforced by `module_check_a_mundo.F`) stay at their required values, and
the WPS-synced placeholders (`e_we`/`e_sn`/`dx`/`dy`/`num_metgrid_*`/
`num_land_cat`) are left unmanaged for `prepare_namelist.py` to fill in.

**2026-08-18 — SMOIS unit fix (kg m⁻² → m³ m⁻³) went into `icon2wrf`
itself, not just a one-off patch of already-generated GRIB2/met_em.**
So future runs are correct from the start rather than needing the fix
reapplied. Pushed as an isolated commit on `icon2amundsen`, deliberately
not bundled with unrelated in-progress work already in that tree.

**2026-08-18 — Did not regenerate the shared `wrfinput_d01`/`wrfbdy_d01`
under `/home/fs72996/ewahl/data/WRF/run/`** after branko's first
`real.exe` run accidentally overwrote them (stale symlinks in
`branko/run/`, since removed). Per explicit instruction to focus on
branko only for now — **open item**, may still need restoring if another
fork's run depends on the original files.
