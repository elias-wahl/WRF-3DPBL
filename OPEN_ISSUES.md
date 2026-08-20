# Open issues / questions — 3D PBL rebase (WRF v4.4 -> v4.8.0)

## A9 — FIXED (2026-08-20, VSC-5 job 8476273)

`pbl3d_opt=2` now **completes**. Job 8476273: `COMPLETED 0:0`, 1800 steps,
`01:00` -> `02:00`, zero errors, 1.696 s/step. The baseline died at step 1141.
This is the first completed real-terrain run of the full 3D closure.

At `2025-07-18_01:38:00`, where every previous run died:

| | baseline 8472687 | rerun 8476273 |
|---|---|---|
| non-finite cells | 8.3e6 | **0** |
| max `Q_SQ` | 44.5 | 30.3 |
| max \|W\| | 26.5 m/s | 14.2 m/s |
| outcome | SIGSEGV in RRTMG | ran on to 02:00 |

Domain max `Q_SQ` over k=0..9, baseline -> rerun: 01:35 46.4 -> 15.2,
01:36 65.8 -> 14.9, 01:37 **150.5 -> 18.5**. The baseline more than doubles in
the last minute; the rerun is flat. The argmax also stops locking onto one cell
and wanders normally.

**The fix** (commit `db3b9176c`): write Tier 1's limited length scale back into
`l_master`, so the dissipation, the q^2 diffusion coefficients and the history
field see the same eddy size the stresses do. Ten lines, no new parameter, no
Registry change. See `DECISIONS.md` for the physical argument.

### Two predictions that did NOT verify, and why

Recorded before the run: `P/eps` at `j=111, i=161` would go 1.146 -> ~0.46 at
01:36. **Measured 24.6.** That is not a miss in the fix, it is a miss in the
prediction: the cell never reached the runaway state (`Q_SQ` 0.43 against the
baseline's 18.1), so `P/eps` there is a ratio of two near-zero numbers, exactly
the ignition regime where the baseline itself showed 155, 3271, 57471. The
prediction was **linearised** -- it assumed the flow would arrive at the same
state and only the ratio would change. With the fix active from ~01:05 the
trajectories diverge for half an hour first. The counterfactual was an estimate
at fixed state, never a forecast, and should not have been written as one.

Also: an interim comparison table showed baseline and rerun identical at 01:38.
That was a stale file -- the rerun had not yet overwritten the baseline's
`qsqdiag_..._01:38:00.nc`. Filter by mtime when comparing against `temp/branko/`.

### What this does NOT settle

- Domain `Q_SQ` runs 20-30% below baseline through the window. Whether that is
  correct damping or over-damping is the unresolved 17-41% boundary-layer
  deficit question. Only the 47 h MYNN comparison answers it.
- The `sf_alpha` energy-pairing defect is **untouched**. The falsification
  condition was "if it still dies, sf_alpha becomes primary". It did not die,
  so that hypothesis is neither confirmed nor refuted.

## A9 — RESOLVED by measurement (2026-08-20, VSC-5 job 8472687)

Job 8472687 wrote all 39 one-minute `qsqdiag` frames through 01:38 before the
terminal RRTMG segfault. **Branch 1 confirmed, branch 2 dead.**

Blowup cell `j=111, i=161` (46.639 N, 10.806 E, terrain 1549 m, local slope
**33.6 deg**, `dz` 16.8 m), q2 peak at stag `k=1`, |W| peak at `k=0`. This is a
*different* cell from the 01:30 peak of 8464723 and from MUSICA's
`k=4, j=182, i=514` — the mechanism is not cell-specific.

`T1_RATIO` 0.18–0.40 throughout; `SK_EPS` 15–34 against a limit of 6.0;
`L_MASTER` 6.05 m (approx `kappa*z`, surface-layer limited). `P/eps` **as built**
1.09–1.23 for eight consecutive minutes; with a **consistent** length scale
0.43–0.60 in every frame. Exponential fit over 01:32–01:38: e-folding **105 s**,
doubling 73 s, net imbalance 9.5e-3 s^-1. Domain *means* of every budget term are
flat to 5% across the window — this is a point failure, not a domain imbalance.
`Q_SQ_BUOYANCY` never exceeds 0.19 anywhere and is a net sink in the mean.

The honest-limit caveat from 2026-08-19 is discharged: the correction needed
`SK_EPS > 12.6` co-located at 01:36; measured **15.07**.

**Correction 1 — Tiers 2 and 3 are NOT globally dead.** Earlier text in this
section says `T2_STEPS = T3_FLAGS = 0`. Domain-wide at 01:36 that is wrong:
`T2_STEPS` non-zero in **294,398** cells (max 5), `T3_FLAGS` in **60,156**
(max 240). What is true is narrower and worse — at the runaway column they are
silent: `T3_FLAGS = 0` at every level in every frame, `T2_STEPS` only
sporadically 1–2 at `k=3`. Tier 2 escalates on solver distress and
non-realizability, Tier 3 enforces PSD; a budget running 15% hot is neither.
**The ladder has no feedback path from "production is outrunning dissipation"
back onto `l`.** This changes the fix: it is not "the backstops never fire", it
is "the backstops cannot see this".

**Correction 2 — the Tier-1 footprint is 4.1%, not ~20%.** `T1_RATIO < 0.999`
in **977,518 / 24,000,000** cells at 01:36; `< 0.5` in 1.06%; `SK_EPS > 6` in
4.08%. The 899,613-cell figure was a different frame of a different job.

Full tables, vertical structure, grey-zone context and reproduction commands:
`FINDINGS_QSQ_RUNAWAY.md` (project root and `realcase/project/`).

The recommended fix — write Tier 1's `l_use` back so `l_dissip` sees it — is
**still not implemented**, for the reasons in `DECISIONS.md`.

## OPEN (A9): first real-terrain run blows up in nocturnal katabatic flow on the steepest slopes
(2026-08-19 — MUSICA jobs 88703 and 88971. Terminal symptom recorded as U2 in `KNOWN_ISSUES.md`.)

**Superseded framing:** this was first written up as "a NaN of unknown origin reaches
RRTMG". The 1-minute diagnostic rerun (job 88971, `auxhist23` stream, `iofields_nandiag.txt`)
settles it: the RRTMG segfault is only the *terminal* symptom. The actual failure is a
**vertical-velocity instability in nocturnal downslope flow**, and it is ours.

### The crash is bit-for-bit deterministic

Job 88971 reran job 88703 from byte-identical `wrfinput`/`wrfbdy`, namelist unchanged
except for adding the diagnostic stream. Identical outcome: same step (1141 / model
2025-07-18_01:38:00), **same 81 of 190 ranks**, same fault address `0x24fcd83`. So the
stochastic McICA cloud-overlap path is *not* implicated, and any fix can be regression-tested
directly.

### Confirmed cross-cluster: the same step on a completely different toolchain
(2026-08-19, VSC-5 job **8464723** — archived at `wrf_output/8464723/`, found on return.)

The blowup is not a MUSICA artifact. The *original* VSC-5 run, which predates the move,
died at the same place: `rsl.out.0000` ends at

```
Timing for main: time 2025-07-18_01:38:00
```

That is VSC-5 zen3 with **gcc 12.2 / OpenMPI 4.1 / netlib-lapack**, against MUSICA zen4
with **EESSI gcc 13.3 / OpenMPI 5.0.3 / FlexiBLAS**. Two unrelated compilers, MPI stacks
and LAPACK implementations, two CPU generations, different rank counts (2x128 vs 190) —
and the identical failure step. Any residual "miscompiled binary" or "bad BLAS" hypothesis
is excluded, which matters because E12 makes a subtly wrong binary a real possibility.

The archived frame at 01:30 also reproduces the numbers quantitatively: `max Q_SQ` = 29.11
and `max|W|` = 9.96, sitting exactly between this table's 01:29 and 01:31 entries. And
`max|W|` sits at **k=0, j=54, i=38** — the same hot column named further down. So the
VSC-5 and MUSICA runs are the same trajectory, not merely the same endpoint.

Two details for whoever reads the archived logs: `rsl.error.0000` shows no error, because
rank 0 was not among the 81 that faulted — absence there is not evidence of a different
failure. And `Q_SQ` is identically zero at `k=0` (surface boundary value); it peaks at
`k=3`, so a `k=0` slice of the *budget* terms shows nothing. `max|W|` is the one that
lives at `k=0`.

### What actually happens

All 27 diagnostic fields are **fully finite through 01:37:00**; at 01:38:00 roughly a
third of the domain (8.3e6 points) is non-finite at once. The seed is visible in the
preceding minutes as runaway `|W|` at the **lowest model level (k=0)**:

| model time | max abs W | #(abs W >10) | max Q_SQ | max COND_A | #(COND_A >1e5) |
|---|---|---|---|---|---|
| 01:29 | 9.65 | - | - | - | 1 |
| 01:31 | 10.31 | 1 | 29.6 | 5.6e4 | 0 |
| 01:33 | 11.29 | 2 | 29.2 | 1.1e5 | 1 |
| 01:35 | 14.98 | 6 | 43.0 | 7.9e4 | 0 |
| 01:36 | 17.48 | 15 | 81.7 | 2.1e5 | 2 |
| 01:37 | 22.44 | 20 | 247 | 5.6e4 | 0 |
| 01:38 | 26.63 | (blown up) | 44.5 | 3.4e38 | 10247 |

### The linear solve is NOT the cause — this is the key negative result

The obvious suspect, given the section below this one, is the `dgesvx` solve going
ill-conditioned. **It did not.** `COND_MAX` is 1.0E8; through 01:37 the number of points
exceeding even 1e5 is 0-2 out of 24.1e6. The closure was healthy the entire time. The
10247 exactly-singular solves at 01:38 (`mat_cond = Huge`, i.e. `rcond` returned 0) appear
*after* the state has already gone non-finite — they are a consequence, not a cause.

Note also that the safety net described in the section below **has since been implemented**
and that text is stale: `info` is checked, `mat_cond = 1/rcond` is live, and
`solve_ok = (info == 0) .and. (mat_cond <= COND_MAX)` zeroes all ten fluxes on failure
(`module_pbl3d_my.F:1953-1985`). Realizability enforcement is live too (`PBL3D_T3_FLAGS`
fires on ~60000 points/frame). Neither prevented this.

### The instability is katabatic, on the steepest terrain in the domain

Peak `|W|` sits at k=0 over slopes of **33.6 deg**, against a domain max of 34.2 deg and
only 208 points steeper than 30 deg. It is a *downslope* flow (w and v both negative) —
i.e. nocturnal drainage, the regime this run is the first ever to attempt.

At the surface in terrain-following coordinates `w = u.grad(h)` is legitimately nonzero,
so that had to be excluded. It does not explain it — the ratio of actual `W` to the
kinematic value grows monotonically while the downslope wind itself accelerates:

| model time | W(k=0) | v | u.grad(h) | W / u.grad(h) |
|---|---|---|---|---|
| 01:29 | -3.60 | -3.26 | -2.14 | 1.68 |
| 01:31 | -4.81 | -3.57 | -2.35 | 2.05 |
| 01:33 | -8.73 | -5.47 | -3.62 | 2.41 |
| 01:35 | -14.98 | -8.78 | -5.80 | 2.58 |
| 01:37 | -22.44 | -11.47 | -7.59 | **2.96** |

Pure terrain-following flow holds that ratio near 1. A monotonic climb to ~3, with `v`
accelerating 3.5x over the same window, is a positive feedback: the closure is not
supplying enough damping to the drainage flow, the slope wind accelerates, `w` grows
faster than kinematics allows, and it runs away. `w_damping = 1` is on and produced no
messages.

This matches the "extreme vertical-velocity blowup (`w-cfl` ~14, SIGSEGV) observed
empirically during Phase 1 regression testing" noted in the section below — described
there as longstanding and present pre-rebase. What is new here is that it is now
reproduced on real terrain, deterministically, with per-minute diagnostics.

### Why no idealized run caught this

Two independent reasons, both structural:

1. **Terrain.** Group J was a single smooth cosine bell. Real terrain has 208 points
   steeper than 30 deg and grid-scale roughness a cosine bell does not have.
2. **Regime.** This is the first nocturnal/cold-pool case, so it is the first time
   katabatic drainage flow has existed at all.
3. **The crash site was never even compiled in.** `test/em_les/namelist.input` runs
   `mp_physics = 0`, `ra_lw_physics = 0`, `ra_sw_physics = 0`, `sf_surface_physics = 0`.
   Not one line of RRTMG, Thompson or Noah-MP executed in any idealized run, which is why
   the blowup surfaced as a segfault in radiation rather than as a CFL error.

### The MYNN control already ran 47 h on this exact case — terrain and numerics are exonerated

(user-supplied 2026-08-19: `WRF/run/namelists/namelist.input_inn_inner_dom_ICON`, stock
current WRF, completed `run_hours = 47`.)

This removes the need for the control run recommended earlier, and it is a much stronger
result than that would have been: the control ran **twice as long**, through the same
night, and did not blow up. Everything below is **identical** between it and the crashing
`pbl3d` run:

`dx = dy = 500`, `e_we = 601`, `e_sn = 501`, `e_vert = 80`, the full 80-entry
`eta_levels` list, `p_top_requested = 20000`, `time_step = 2`, `num_metgrid_levels = 12`,
`num_metgrid_soil_levels = 8`, the same ICON hourly forcing and the same start time
(2025-07-18_01:00), `epssm = 0.9`, `smdiv = 0.15`, `emdiv = 0.03`, `w_damping = 1`,
`damp_opt = 3`, `zdamp = 5000`, `dampcoef = 0.02`, `non_hydrostatic`, `moist_adv_opt = 1`,
`scalar_adv_opt = 1`, `use_theta_m = 1`, `m_opt = 1`, `sfs_opt = 0`, `mix_isotropic = 0`,
`base_temp = 290`, **the entire `diff_6th_*` block including `diff_6th_slopeopt = 1` and
`diff_6th_thresh = 0.10`**, and every physics option that matters here
(`mp_physics = 8`, `ra_lw/sw_physics = 4`, `radt = 1`, `sf_sfclay_physics = 1`,
`sf_surface_physics = 4`, `isfflx = 1`, `icloud = 1`, `slope_rad = 1`, `topo_shading = 1`,
`num_land_cat = 33`, `cu_physics = 0`).

So the following are **ruled out**, not merely unlikely:

- dx = 500 m being too coarse for a 34-degree slope
- `time_step = 2` being too long
- `epssm = 0.9` / the divergence-damping settings
- the smoothed `geo_em` terrain
- the ICON forcing, the soil moisture, the vertical level distribution
- Thompson / RRTMG / Noah-MP themselves (all three ran 47 h here without incident)

**Only three differences remain, and every one of them is forced by `pbl3d`:**

| | MYNN control (ran 47 h) | `pbl3d` run (dies at 38 min) | forced by |
|---|---|---|---|
| closure | `bl_pbl_physics = 5` | `bl_pbl_physics = 0`, `pbl3d_opt = 2` | the scheme itself |
| SGS mixing | `diff_opt = 2`, `km_opt = 4` — Smagorinsky **active** | `diff_opt = 0` — `pbl3d` does *all* SGS mixing, no backstop | scheme design |
| vertical coordinate | `hybrid_opt = 2` (Klemp cubic — the WRF default, omitted from the namelist) | `hybrid_opt = 0` — original pure terrain-following sigma | **hard fatal check**, `share/module_check_a_mundo.F:390` |

(Also `zadvect_implicit = 1` in ours, absent in the control — minor, but untested here.)

The second and third rows deserve emphasis given the observed failure mode is *runaway
vertical velocity at the surface over the steepest slopes*:

- `diff_opt = 0` means that when the closure under-supplies damping there is **nothing
  else**. The control has Smagorinsky horizontal mixing underneath it the whole time.
- `hybrid_opt = 0` is the original coordinate; the hybrid coordinate exists specifically
  to reduce terrain-induced error over steep topography, and `pbl3d` cannot use it —
  `module_check_a_mundo.F` makes it a fatal error. So the one configuration that most
  needs terrain-error mitigation is the one forbidden from having it.

Neither is proof of cause on its own — but together they mean `pbl3d` is running this
terrain with *both* safety nets the control enjoys removed, by construction.

### RESOLVED BRANCH (2026-08-19, job 89167): `pbl3d_opt = 1` survives — the forced config is exonerated

The discriminator was run: `pbl3d_opt = 2 -> 1` (analytical `_pbl_approx`, HL88-realizable),
with **`hybrid_opt = 0` and `diff_opt = 0` deliberately unchanged**, same `wrfinput`/`wrfbdy`,
same 1-minute stream. It ran straight through the failure point with **0 non-finite values
in 41 frames**, at 0.78 s/step (vs 1.26 for the full solve).

| model time | opt=2 max abs W | opt=2 max Q_SQ | opt=1 max abs W | opt=1 max Q_SQ |
|---|---|---|---|---|
| 01:31 | 10.31 | 29.6 | 10.14 | 11.5 |
| 01:33 | 11.29 | 29.2 | 10.60 | 9.9 |
| 01:35 | 14.98 | 43.0 | 11.98 | 9.2 |
| 01:36 | 17.48 | 81.7 | 12.54 | 8.3 |
| 01:37 | 22.44 | **246.6** | 12.69 | 8.9 |
| 01:38 | **blowup** | - | 12.50 | 9.7 |
| 01:40 | (dead) | - | 12.24 | 10.7 |

The two runs are bit-comparable for the first ~20 minutes (W ratio 0.98-1.04), so this is
a clean single-lever comparison.

**Therefore ruled out**, on top of everything the MYNN control already excluded:

- `hybrid_opt = 0` (pure terrain-following sigma) — `pbl3d_opt=1` uses it too and is stable
- `diff_opt = 0` (no Smagorinsky backstop) — likewise
- the katabatic flow itself being unrepresentable: at the *other* hot column (j=54, i=38)
  `opt=1` sustains `W = -12.5 m/s` **flat** for ten minutes without trouble. Strong
  drainage flow is fine; it is the *runaway* that is not.

**The fault is inside the full 3D path (`Calc_fluxes`, `pbl3d_opt == 2`).**

### The mechanism is a q^2 runaway, not the `dgesvx` solve

The diagnostic that separates the two runs is not `W` — it is `Q_SQ`, and it separates
*earlier*. `opt=2`'s `Q_SQ` grows 30 -> 43 -> 82 -> **247** over six minutes while `opt=1`
holds flat at 9-11 the entire time. `W` follows with a lag, which is the expected causal
order: q^2 sets the eddy diffusivity and hence the SGS flux magnitudes, so a runaway q^2
inflates the SGS forcing on the resolved flow, which increases the strain, which feeds
back into shear production of q^2.

Note this is *not* the ill-conditioned-solve hypothesis from the section below, which the
earlier analysis already excluded on its own evidence (`COND_A` under 1e5 essentially
everywhere until after the state had gone non-finite).

At the 33.6-degree column the difference is qualitative, not quantitative — `opt=1` peaks
and **recovers**, `opt=2` never turns over:

| | 01:31 | 01:33 | 01:35 | 01:37 | 01:39 |
|---|---|---|---|---|---|
| opt=2 W(k=0) | -4.81 | -8.73 | -14.98 | -22.44 | dead |
| opt=1 W(k=0) | -3.62 | -4.98 | -5.03 | -3.32 | -2.84 |

### Prime suspects, now narrow

`opt=1` and `opt=2` differ in exactly three q^2-relevant places
(`dyn_em/module_pbl3d.F:5790-5810`, `module_pbl3d_my.F:200`):

1. **`Calc_q_sq_shear` vs `Calc_q_sq_shear_pbl_approx`** — full stress-tensor shear
   production (`turb_flux_u2/v2/w2/uv/uw/vw` against all nine velocity gradients) versus
   the 1D form using only `du_dz`, `dv_dz`, `turb_flux_uw`, `turb_flux_vw`. **Most likely
   culprit**: it is a *production* term, it is the one that scales with the full strain
   tensor, and strain is exactly what steep-slope drainage flow maximises.
2. **`Calc_q_sq_horizontal_diffusion`** — only called for `pbl3d_opt > 1`. Nominally a
   sink, but on 500 m grid over 34-degree slopes the horizontal-diffusion operator acts
   along sloping coordinate surfaces, which can be a spurious *source*.
3. The flux computation itself (10x10 solve vs analytical), which also feeds (1).

### ANSWERED (2026-08-19, job 89435): shear production runs away; it is not a dissipation failure

With the five budget terms promoted to history output, `pbl3d_opt=2` was rerun and
reproduced **exactly** (FAILED 139:0, 81 ranks, same address `0x24fcd83`, model
01:38:00 — identical even on the rebuilt binary, since the Registry change touches
only I/O metadata).

**The instability is highly localised.** The domain-mean `|SHEAR|/|DISSIP|` ratio is
flat at ~1.25 for the entire run and does not move at the blowup. Only the maxima
explode. So this is a few cells running away, not a domain-wide imbalance — which is
why it was invisible in every aggregate diagnostic before now.

Co-located budget at the cell where q^2 peaks (k=4, j=182, i=514), m2 s-3:

| model time | Q_SQ | SHEAR | BUOY | DISSIP | VDIFF | HDIFF | net |
|---|---|---|---|---|---|---|---|
| 01:33 | 2.26 | 0.011 | -0.003 | 0.034 | +0.057 | +0.007 | +0.037 |
| 01:34 | 5.87 | 0.098 | -0.004 | 0.150 | +0.012 | -0.003 | -0.047 |
| 01:35 | 17.11 | 0.727 | +0.002 | 0.698 | -0.360 | -0.056 | -0.385 |
| 01:36 | 57.68 | **9.032** | +0.002 | 4.284 | -3.802 | -0.052 | **+0.897** |
| 01:37 | 246.63 | **26.752** | -0.007 | 23.070 | -10.454 | -29.332 | -36.110 |

**`Q_SQ_SHEAR` is the driver.** It grows by a factor of ~2400 at that cell
(0.011 -> 26.75). The runaway moment is **01:36**, where production reaches
**2.1x dissipation** and the net budget turns positive; q^2 then goes 17 -> 58 -> 247
and the model dies two minutes later.

**Dissipation is not failing** — it grows an order of magnitude too (0.034 -> 23.07).
It simply cannot keep pace with a production term that is growing faster. The
distinction matters for the fix: the problem is an unbounded *source*, not a missing
*sink*.

### `Q_SQ_HDIFF` is exonerated — it is a sink here, not a spurious source

This was the second suspect, and the natural one, because
`Calc_q_sq_horizontal_diffusion` is the term `pbl3d_opt=1` does not have at all.
In domain maxima it looked damning: it grows **x183** over 01:26-01:37, far faster
than shear's x18.

That reading was wrong. At the blowup cell `Q_SQ_HDIFF` is **-29.33**, a large
*sink*, and `Q_SQ_VDIFF` is likewise negative. Both are exporting q^2 away from the
spike. The huge domain-max value sits in a *different* cell — the neighbour receiving
what the peak is shedding. The x183 growth is horizontal diffusion responding to the
enormous gradient the spike created, i.e. a consequence, and a mitigating one.

A domain maximum is not a budget. The co-located numbers are what settle this.

### Where the fix belongs — and one measurement still missing

**A cap on shear production would be the wrong instrument.** Tier 1 already *is* the
principled limiter: it bounds `l` so that `S k / eps <= pbl3d_sk_eps_max` (6.0),
derived from the weak-equilibrium assumption the algebraic system rests on. Adding a
second cap on production would be a parallel mechanism doing the same job worse, and
would tune away the symptom.

What the data supports at the blowup cell (k=4, j=182, i=514):

- `PBL3D_T2_STEPS = 0` and `PBL3D_T3_FLAGS = 0` for every frame through the blowup.
  **Tiers 2 and 3 never fired**, in the one column that destroyed the run.
- `PBL3D_SK_EPS` reaches **17.4** against a limit of 6.0. Note this diagnostic is
  computed from the **pre-limit** `l` (`dg_sk_eps = strain_mag * b_1 * l / (2 q)`,
  `module_pbl3d_my.F` ~1578), so it proves Tier 1 had work to do, **not** whether
  `l_use` was actually applied.
- `L_MASTER` holds ~16 m while q^2 grows x363, so there is no q-l runaway and the
  q^3 dissipation superlinearity is intact.
- Dissipation timescale `tau = b_1 l / 2q` falls 157 s -> 8 s, still well above
  `dt = 2 s`, so this is **not** stiff explicit integration either.

**The missing measurement is `PBL3D_T1_RATIO` at the blowup cell**, and it was not in
job 89435's diagnostic stream (`iofields_nandiag.txt` lists `PBL3D_T2_STEPS`,
`PBL3D_T3_FLAGS`, `PBL3D_SK_EPS`, `PBL3D_N_TAU` but omits it). It *is* carried in the
full `wrfout` and is demonstrably active there — at 01:30, 899,613 cells have
`T1_RATIO < 0.999`, reaching 0.00124 — but `wrfout` is only 10-minutely, so there is
no frame at 01:36-01:37 when it matters.

It decides between two very different fixes:

1. **`T1_RATIO < 1` at that cell** — Tier 1 binds and q^2 still explodes. Then the
   bound is the wrong bound for this regime: a strain-limited `l` still admits runaway
   production at `strain_mag ~ 0.1 s-1`, and the fix belongs either in how `l_use`
   feeds the stress solve or in Tier 2's escalation criteria, which demonstrably never
   triggered here.
2. **`T1_RATIO ~ 1` at that cell** — Tier 1 is blind to the strain that is driving
   this. The suspect is `strain_mag`, built from raw `du_dx ... dw_dz`
   (`module_pbl3d_my.F` ~1571): on a 34-degree terrain-following coordinate surface
   those are not the physical strain components, so the limiter could be reading a
   much smaller strain than the flow actually has.

**Cost to settle: one line and one rerun, no rebuild.** `pbl3d_t1_ratio` is already an
`rh` Registry field; add it to the `+:h:23:` line and repeat the ~33 min run.

### ANSWERED by identity (2026-08-19, VSC-5): `T1_RATIO` is a function of `SK_EPS`, and the answer is branch 1

**`PBL3D_T1_RATIO` carries no information beyond `PBL3D_SK_EPS`.** Reading the Tier 1
block in `dyn_em/module_pbl3d_my.F` (~1571-1585), the two diagnostics are computed from
the same `strain_mag`, `l` and `q` in the same pass:

```fortran
l_use       = Min ( l, (2*SK_EPS_MAX/b_1) * q / Max (strain_mag, STRAIN_MIN) )
dg_sk_eps   = strain_mag * b_1 * l / (2 q)      ! pre-limit l
dg_t1_ratio = l_use / l
```

Substituting one into the other, for `strain_mag > STRAIN_MIN` (= 1e-10, never binding
here — the blowup cell has `strain_mag ~ 0.1 s-1`):

**`T1_RATIO = min (1, SK_EPS_MAX / SK_EPS)`**

Verified against the archived `wrfout` of job 8464723 at 01:30, over all **4,328,912**
cells with finite, positive values: **maximum absolute deviation 9.5e-08, and not one
cell deviates by more than 1e-6.** Spot checks agree at both ends — `T1_RATIO` = 1
where `SK_EPS` = 4.611, and `T1_RATIO` = 0.001216 where `SK_EPS` = 4935.9
(6/4935.9 = 0.0012156).

So the measurement A9 called missing was already implied by job 89435's own data:

| at the blowup cell (k=4, j=182, i=514) | value |
|---|---|
| `SK_EPS` (measured, job 89435) | **17.4** |
| `T1_RATIO` = min(1, 6.0/17.4) | **0.345** |

**This is branch 1, and branch 2 is excluded.** Tier 1 is *not* blind to the strain: it
sees `S k / eps` at nearly three times its limit and responds by cutting `l` to **34.5%**
of its unlimited value — and q^2 still goes 17 -> 58 -> 247 and kills the model two
minutes later. `strain_mag` is therefore **not** the suspect; whatever the terrain-following
coordinate does to the raw gradients, the strain it computes is large enough to trigger
the limiter hard.

That relocates the fix, and sharpens what the gap is. At the blowup cell:

- Tier 1 binds hard (`T1_RATIO` 0.345) and is insufficient.
- Tier 2 and Tier 3 never fire (`T2_STEPS` = `T3_FLAGS` = 0 for every frame).
- Tier 2 escalates on solver degeneracy or a non-realizable stress state; neither occurs
  (`COND_A` < 1e5 against a 1e8 threshold, `T3_FLAGS` = 0).

So **no tier responds to the actual failure mode**. The escalation ladder is triggered by
*solver* distress and *realizability*, and a runaway q^2 budget is neither: every solve at
that cell is well conditioned and returns a physically admissible stress state, right up
until the state goes non-finite. The closure has no feedback path from "production is
outrunning dissipation" back onto `l`. That is the gap, and it is a design gap rather than
a bug — which is consistent with `pbl3d_opt=1`, whose 1D shear production simply never
reaches this magnitude, surviving unchanged.

Note this does **not** license a cap on production, for the reason already stated: Tier 1
is the principled limiter and a second cap would duplicate it. The open question is
whether `SK_EPS_MAX = 6.0` is the right bound in this regime, or whether Tier 2's
escalation criteria should include a budget-based test alongside the solver and
realizability ones.

*Status:* derived from the source and confirmed against 4.3e6 archived cells; job 8472687
(VSC-5, 1-minute stream now carrying `PBL3D_T1_RATIO`, `PBL3D_SK_EPS`, `PBL3D_T2_STEPS`,
`PBL3D_T3_FLAGS`, `L_MASTER`) will confirm it directly at 01:36-01:37, the window no
`wrfout` frame covers.

### MECHANISM (2026-08-19, VSC-5): production and dissipation use *different* length scales

Tracing where Tier 1's limited scale actually goes settles why a limiter that binds hard
still fails.

- **Production.** `l_use` is a **local scalar** in the per-point solver
  (`module_pbl3d_my.F:1531`). It sizes the stress system — the matrix diagonal is
  `a(1,1) = q/(2*a_1*l) + 2*u_x`, so the relaxation time is `tau ~ l/q` and the stresses,
  hence `Q_SQ_SHEAR`, scale with `l_use`. It is never written back.
- **Dissipation.** `Fill_dissip_length_scale` sets `l_dissip = l_master` for
  `pbl3d_l_opt = 1` (`module_pbl3d.F:6327`), i.e. the scale **before** Tier 1 touched it,
  and `Calc_q_sq_dissip` uses `eps = 2 q^3 / (b_1 * l_dissip)`.

Since `eps ~ 1/l`, every time Tier 1 binds it reduces production **and leaves dissipation
under-estimated by exactly the same factor**. The unlimited branch is the dissipative one,
so Tier 1 firing *widens* the imbalance it exists to close. At the blowup cell the closure
transports momentum as if the eddies were 5.5 m and dissipates them as if they were 16 m.

In Mellor-Yamada the master length scale is singular by construction: the same `l` sets the
stress closure and `eps = q^3/(B_1 l)`. This is **not** the k-epsilon situation, where
Durbin's bound is a constitutive device and leaving the prognostic `eps` equation alone is
correct — here `eps` is *diagnosed* from `l`, so the length scale **is** the dissipation.

**Effect of making it consistent** (`eps -> eps / T1_RATIO`, with `T1_RATIO = 0.345`):

| model time | P | eps as built | P/eps as built | P/eps consistent |
|---|---|---|---|---|
| 01:35 | 0.727 | 0.698 | 1.04 | 0.36 |
| 01:36 | 9.032 | 4.284 | **2.11** | **0.73** |
| 01:37 | 26.752 | 23.070 | 1.16 | 0.40 |

`P/eps` never reaches 1 on the consistent scale, so q^2 decays instead of exploding — with
no new parameter, no cap on production, and Tier 1's bound untouched.

**Condition, stated exactly:** the correction suffices at 01:36 iff `T1_RATIO < eps/P =
0.474`, i.e. `SK_EPS > 12.6` co-located at that frame. A9 reports a *peak* of 17.4, which
clears it, but a peak is not a co-located value — job 8472687 carries both at 1-minute
resolution and settles it.

**Caveat, and it is not small.** Tier 1 was active in 899,613 cells at 01:30, ~20% of the
domain. This changes the solution broadly, not just at the blowup, and must be validated
against the 47 h MYNN control and the idealized regressions before being called a fix. The
deterministic crash is the clean first test.

### Grey-zone findings for this case, measured rather than assumed

- **The scale-aware tapering is inert.** `pbl3d_scale_aware = 1`, but at dx = 500 m with a
  nocturnal PBL depth ~100 m, `dxdh ~ 12.5` gives `Psig_bl = 1.0009`, clipped to **1.0**.
  Correct behaviour — a shallow stable layer under a 500 m grid is fully parameterized —
  but nothing in this configuration tapers anything, and Honnert's partition is derived for
  *convective* PBLs. There is no validated grey-zone partition for katabatic layers.
- **Ri collapses as the jet accelerates.** At the blowup cell, 75 m AGL:
  `dthetav/dz = +0.0086 K/m`, `N = 0.0168 s-1`. Strain grows far faster than stratification,
  so `Ri = N^2/S^2` falls ~0.39 -> ~0.03. `Q_SQ_BUOYANCY` never exceeds +/-0.007 — the sink
  that should oppose shear production is absent. The collapse is real physics; amplifying
  without bound in response to it is not.
- **Terrain-following cancellation is present but secondary.** Measured at the blowup cell
  at 01:30, `du_dx`: along-sigma term -0.00042 s-1, metric term -0.00111, physical residual
  +0.00069 — error amplification ~2.2x. Real, an order too small to be the driver, and it
  does not reach the blowup window. Do not act on it before the primary fix.
- **The grid is ~60:1 anisotropic** (dz ~ 8 m, dx = 500 m) with a single ~16 m master length
  scale serving both directions.

### Implication for the fix (superseded by the section above — read that first)

The scheme already contains the right idea in the right form, applied to the wrong
quantity. **Tier 1 (`pbl3d_sk_eps_max`, Durbin 1996) limits `Sk/eps` — precisely a
production-to-dissipation ratio — but it bounds the *length scale*, and nothing
bounds shear production in the q^2 budget itself.** At the blowup cell that ratio
reaches 2.1 with no limiter in the path.

Suggested first attempt, in increasing order of intrusiveness:

1. **Limit shear production against dissipation in the q^2 budget**, mirroring the
   existing Tier 1 construction — cap `Q_SQ_SHEAR` at some multiple of
   `Q_SQ_DISSIP`. The domain mean ratio sits at ~1.25 all run, and healthy cells stay
   near there, so a cap of order 2-3 would never bind in normal conditions and would
   have bound at 01:36 here. Make the multiple a namelist parameter alongside
   `pbl3d_sk_eps_max` rather than hardcoding it.
2. Investigate *why* the full stress-tensor form produces such extreme local values
   where the 1D form does not. `Calc_q_sq_shear` contracts the full
   `turb_flux_u2/v2/w2/uv/uw/vw` against all nine velocity gradients; on a 34-degree
   slope the cross terms are large and, unlike the 1D form, nothing about the
   construction bounds their sum.
3. Only then consider realizability constraints on the stress tensor feeding it.

**Still do not** apply U2's index guard as the fix — it hides this, silently.

### Next steps

- **Do not** "fix" this by applying U2's index guard alone — that converts a loud crash
  into a silently NaN radiative tendency while the blowup continues.
- **Separate the q^2 budget.** *(Promotion DONE, commit `b7b2c76ae`.)* All five terms
  exist as Registry state variables — `q_sq_shear`, `q_sq_buoyancy`, `q_sq_dissip`,
  `q_sq_vdiff`, `q_sq_hdiff` (now `Registry/Registry.EM_COMMON:1169-1173`) — and were
  flagged **`r` (restart only)**, so none reached `wrfout`. This is the same blind spot `CHANGES.md` describes for
  `turb_flux_*`, which had to be promoted `r` -> `rh`. Promote these five the same way and
  rerun `pbl3d_opt=2` with 1-minute output: whichever term runs away identifies the
  culprit directly, and the run only needs to reach 01:38 (~30 min).
- **Tooling for this now exists and is committed** (2026-08-19, VSC-5):
  `realcase/iofields_qsq.txt` puts the five terms plus `Q_SQ` and `W` on stream
  `auxhist23`; `setup_rundir.sh --qsq-diag` wires up the 1-minute stream; and
  `realcase/scripts/qsq_budget.py` tabulates max/min/mean per frame with the peak
  `(k,j,i)` and the `P/eps` ratio. The chain was verified statically before burning a
  queue slot — Registry `rh`, the `Calc_*` routines filling the arrays as `intent(out)`,
  and `module_first_rk_step_part2.F:1264-1265` binding them to `grid%q_sq_*`. **A build
  older than `b7b2c76ae` writes an empty stream and only warns**, so check
  `rsl.error.0000` for `W A R N I N G` on the first run.
- If it is `Calc_q_sq_shear`: the natural first fix is a production/dissipation limiter on
  the shear term, consistent with how Tier 1 (`pbl3d_sk_eps_max`, Durbin) already limits
  `Sk/eps` — i.e. the machinery exists, it is just not applied to the q^2 budget.
- **Do not** conclude `pbl3d_opt=1` is the answer for production. It is the diagnostic, not
  the science target; the whole point of this configuration is the full 3D closure.
- Instrument the slope columns rather than the whole domain: `PBL3D_T3_FLAGS` fires on
  ~60000 points/frame globally, which is too coarse to see what happens in the ~208
  points steeper than 30 deg. A tslist at the blowup columns (`j=111,i=161` and
  `j=54,i=38`) would give per-timestep behaviour there for negligible cost.
- The `hybrid_opt = 0` requirement deserves its own investigation. If `pbl3d` is intended
  for real steep terrain it will keep meeting this, and the constraint is currently a
  hard fatal error with no documented justification in this file.

---

## FIX IMPLEMENTED (A1): buoyancy limit on `l` for `pbl3d_l_opt = 1` (`pbl3d_n_tau_max`)
(2026-07-31 — full record in `CHANGES.md`, Group G)

**A1 was closed as unnecessary on 2026-07-30 and that was wrong.** The evidence used to
close it was an offline regime table in which `l` and `q` were taken from the *same*
regime and were therefore consistent with each other. `N·tau` peaked at ~1.0 in that
table, so a limit looked redundant. The table could not represent the failure mode,
because the failure mode is precisely `l` and `q` becoming inconsistent.

`run_u20_l0fix` shows it. `q_sq` is a local production/dissipation balance and correctly
collapses to `Q_SQ_MIN` above the boundary layer. `l = l0 kappa z / (kappa z + l0)` is
geometric — it knows the distance to the ground and the depth of the turbulent layer,
never whether there is turbulence at *this* level — and asymptotes to `l0` (~30 m here)
all the way to the model lid. Above 1 km that gives `tau = l/q ~ 8000 s` against a
buoyancy period of ~500 s, so `N·tau ~ 100`.

Run-wide medians make the same point:

| | all `q_sq > Q_SQ_MIN` | genuinely turbulent, `q_sq > 0.1` |
|---|---|---|
| n | 874,181 | 255,975 |
| Tier 1 binds | 72.29% | 12.24% |
| Tier 2 escalates | 23.90% | 0.49% |
| median `Sk/eps` | 38.24 | 3.49 |
| median `N·tau` | 76.60 | 0.05 |

The right-hand column is healthy (`Sk/eps = 3.49` against the theoretical equilibrium
3.3). The left-hand column is laminar free air being pushed through a 10x10 solve at
`N·tau ~ 100`.

**The limit was missing only from the default option.** `pbl3d_l_opt = 2` (MYNN) has
`l_f = alpha_2 q/N`; `pbl3d_l_opt = 3` (Messinger) has `l_d = c_r q/N`;
`pbl3d_l_opt = 1` (MY74, the default and the one in use) had none, despite two comments
in the file asserting that it did.

Fix: `l <= pbl3d_n_tau_max * q / N` in stable layers, default `0.53` = Deardorff (1980)
`l = 0.76 sqrt(e)/N` with `e = q^2/2`. **This also closes A2** (which constant to use).
In level-2 equilibrium it only binds above `Ri ~ O(1)`, far past the `Ri = 0.195` cutoff,
so it is inert wherever the closure is already healthy and acts only where `l` and `q`
have decoupled.

**Still to verify by running:** `pbl3d_n_tau_max` at its default vs. a large value
(disabled), otherwise identical, the same way `pbl3d_l0_opt` isolated A0.

---

## FIX IMPLEMENTED (A0): `l0` was set by the model top, not by the turbulence
(found 2026-07-30 while evaluating whether to add a buoyancy limit on `l`;
fixed the same day as `pbl3d_l0_opt = 1` — see `CHANGES.md`, Group E. The text below
is the original diagnosis, kept as the record of why.)

`Calc_l_master_algebra` evaluates MY74 Eq. 72,
`l0 = alpha * integral(q z dz) / integral(q dz)`, over the **whole column**
(`do k = kts + 1, ktf`), weighting by `q = Sqrt(q_sq)`. But `q_sq` is floored at
`Q_SQ_MIN = 1e-5`, so every non turbulent level in the free atmosphere
contributes `q_min = 3.16e-3` rather than zero. The numerator then grows like
`H^2` while the denominator grows like `H`, so

    l0  ->  alpha * H / 2

Verified numerically to the digit: for a column carrying nothing but the floor,
`l0` = 250 / 500 / 1000 / 1500 m for model tops of 5 / 10 / 20 / 30 km, against
`alpha H / 2` = 250 / 500 / 1000 / 1500 m. **The boundary layer master length
scale is set by where the model lid is put.** MY74's integral converges because
`q -> 0` above the turbulence; the numerical floor destroys that convergence.
Lowering `Q_SQ_MIN` does not fix it (`1e-7` still gives `l0 = 287 m`).

Magnitude, 20 km top, `alpha = 0.1` (MY82 default), stretched 60 level column:

| regime | `l0` now | `l0` from genuine turbulence | `l` at probe | `N*tau` now | `N*tau` fixed |
|---|---|---|---|---|---|
| nocturnal SBL (h=100 m) | 802 m | 3.5 m | 19.5 m | 3.95 | 0.60 |
| valley cold pool (h=50 m) | 962 m | 1.7 m | 9.9 m | 6.33 | 0.94 |
| shallow stable (h=30 m) | 987 m | 1.0 m | 6.0 m | 6.82 | 1.00 |
| residual layer (h=600 m) | 378 m | 20.7 m | 91.1 m | 4.25 | 0.83 |
| CBL + capping inversion | 122 m | 34.6 m | 92.4 m | 1.83 | 0.63 |

Why it matters for the closure: median `cond(A)` grows roughly as `(N*tau)^3`
and crosses `COND_MAX = 1e8` near `N*tau = 5` (4000 random 3D strain tensors).
So in cold pools and shallow stable layers the solve fails `solve_ok`, exhausts
all six Tier 2 escalations, and lands in the isotropic fallback
`u'2 = v'2 = w'2 = q^2/3` with every covariance zero. **The expected symptom is
SGS fluxes collapsing to isotropic with no transport inside cold pools.**

Proposed fix: weight the Eq. 72 integral by `Max(q - q_min, 0)` instead of `q`.
This restores the intended meaning (the integral is over the turbulence; the
floor is a numerical device to avoid division by zero and should not be fed into
an integral as though it were a physical value). Tested against a hard
`q > q_min` mask, the excess weighting is smoother: as a level crosses the floor
the largest step in `l0` is 0.027 m versus 0.049 m for the mask and 1.0 m for the
present code.

**Scope and cost.** `l0` feeds `pbl3d_l_opt = 1` *and* `2` (both the harmonic
blend and `q_c`), and `Calc_l_master_algebra` serves **both** the approximate and
the full 3D paths. Fixing it therefore changes the validated `pbl3d_opt = +-1`
baseline, by a factor 3-7 in `l` in stable conditions and about 3 in the CBL
(92 m -> 32 m at the capping inversion). That is a large change to a working
configuration, and it is unavoidable: `l0` proportional to the model top cannot
be defended.

**This supersedes item A1 below.** After the fix `N*tau` peaks at about 1.0
across all five regimes, i.e. right at the limit a buoyancy constraint with
`alpha_2 = 1.0` would impose, so the limiter would barely bind. The large
`N*tau` values that motivated A1 are a symptom of this bug, not evidence of a
missing limiter. Adding a compensating limiter on top of the unfixed integral
would mask it.


## FIX IMPLEMENTED: self-consistent q^2 for pbl3d_opt=2 (`pbl3d_qsq_opt`)
(implemented 2026-07-30)

### Why the closure was not self-consistent

`Calc_fluxes` builds and solves the 10x10 algebraic system at every grid point,
but it does not compute `q` itself. Every diagonal entry of `A` is one of
`q/(2 a_1 l)`, `q/(3 a_1 l)`, `q/(3 a_2 l)`, `q/(b_2 l)`, and `b(1:3)` carry
`q^3/(6 a_1 l)`. In the structural decomposition `A = (1/tau) D + S` with
`tau = l/q`, the velocity scale `q` therefore sets the relaxation time that
decides whether the system is diagonally dominant or degenerate.

Until now that `q` came from `Prep_for_fluxes_l2_pbl_approx`, i.e. from

    q^2 = b_1 l^2 (du/dz^2 + dv/dz^2) (1 - Rif) Sm

which is a **1D** closure: it sees only `du/dz`, `dv/dz`, `dthetav_dz`, and `Sm`
is the 1D Mellor-Yamada stability function of those same three gradients. It
knows nothing about horizontal gradients, about `dw/dx_i`, or about the
anisotropy the 10x10 system exists to represent. So the matrix diagonal was
being set by a model that cannot see the physics the matrix describes. Over
complex terrain, where `du/dz` and `dv/dz` are a poor proxy for the total
strain, this is exactly where it would be wrong.

The author's self-consistent alternative, `Prep_for_fluxes_l2` ->
`Calc_q_sq_l2`, closes the same level 2 balance on the **full 3D** production

    q^3 / (b_1 l) = - <u_i' u_j'> dU_i/dx_j + (g/T_ref) <w' thetav'>

evaluated with the stress tensor the 10x10 system itself returned. That closes
the loop: the velocity scale is derived from the same turbulence it goes on to
produce. It was commented out with the note "Full 3D level 2 model is unstable
right now".

### Why it was unstable

Two defects in the dead code, both fixed:

1. **`Calc_q_sq_l2` never took the cube root.** The line read

       q = q ** 1./3.

   Fortran binds `**` tighter than `/`, so this parses as `(q**1.0)/3.0` — a
   division by three, not a cube root. The variable holds `b_1 * l * production`,
   which is dimensionally `q^3`, so `q_sq = q*q` evaluated to `q_true^6 / 9`.
   Feeding a sixth power of `q` into the matrix diagonal blows up unconditionally.
   Every other cube root in the file is correctly parenthesised as
   `** (1.0 / 3.0)` (lines 363, 2603-2616), so this was a typo, not intent.
   Now computed as `q_sq = max(q_cubed, 0)**(2.0/3.0)` in one step.

2. **The 3D production can be negative, and a negative base with a real
   exponent is a NaN.** The only guard is `if (rif < rif_c)`, and `rif` is the
   *1D* flux Richardson number — it cannot know the sign of a nine-term 3D
   production plus buoyancy. Fixing (1) without a floor would therefore have
   traded a blow-up for a NaN. Hence the `max(q_cubed, 0)`.

3. **Cold-start dead-lock (new finding, not in the original code's comment).**
   `Set_init_turb_state_my` sets every `turb_flux_*` to `TURB_FLUX_MIN` and
   `q_sq` to `Q_SQ_MIN`. The self-consistent `q^2` is diagnosed *from* the
   fluxes and the fluxes are diagnosed *from* `q^2`, with no independent source
   anywhere in the cycle: production ~ 1e-12 x gradients gives
   `q^2 < Q_SQ_MIN`, which trips the `if_no_turb` branch in `Calc_fluxes`,
   which writes the fluxes straight back to their floor. Level 2 could never
   spin up. Fixed by falling back on the 1D local-equilibrium value wherever
   the 3D estimate does not clear `Q_SQ_MIN` — the same balance evaluated with
   the only gradients available before a tensor exists. Written to agree bit for
   bit with `Calc_q_sq_l2_pbl_approx` so the fallback and `pbl3d_qsq_opt = 0`
   cannot disagree. In a spun-up boundary layer the fallback never fires.

Also fixed here: `Calc_q_sq_l2` now uses `l_dissip` (not `l_master`) for the
dissipation length scale, which is what `Fill_dissip_length_scale` computes it
for. See finding 3 in the audit section below — the approximate routine still
has this wrong and was deliberately left alone.

### The switch

New namelist option, `Registry.EM_COMMON` + `run/README.namelist` +
validation in `share/module_check_a_mundo.F`:

| `pbl3d_qsq_opt` | behaviour |
|---|---|
| `1` (**default**) | self-consistent full-3D production, `Prep_for_fluxes_l2` / `_l2p5` |
| `0` | legacy 1D surrogate, `Prep_for_fluxes_l2_pbl_approx` / `_l2p5_pbl_approx` |

Only read on the `pbl3d_opt = 2` path. **It is only consequential for
`pbl3d_prog = 0`**: for `pbl3d_prog > 0` the two branches differ only in
`q_sq_hl88`, which feeds the HL88 limiter on `sm`/`sh`, and `sm`/`sh` are never
read anywhere on the full-3D path (audit finding 2). `q_sq` itself comes from
the prognostic TKE equation there, whose full-3D shear production
(`Calc_q_sq_shear` in `module_pbl3d.F`) was already correct and already wired to
`pbl3d_opt >= 2`.

### Consistency audit of the full-3D path (2026-07-30)

Verified correct, no change needed:

- `Fill_in_a_matrix` / `Fill_in_b_vector` — trace identity holds to 7e-14
  (checked numerically); rows 1-3 cancel on columns 4-10 and sum to
  `q/(2 a_1 l)` on columns 1-3.
- `Calc_q_sq_l2` production term — expands exactly to
  `-<u_i'u_j'> dU_i/dx_j` with the symmetric pairs grouped, plus
  `(g/T) <w'thetav'>`. Sign convention correct.
- `Fill_in_a_matrix_moist` / `Fill_in_b_vector_moist` — structurally identical
  to rows 7-10 of the 10x10 with `thetav -> qv`. The `2 q/(b_2 l)` in `a(4,4)`
  versus `q/(b_2 l)` in `a(10,10)` is correct: the variance has two identical
  production terms so the 2 cancels, the covariance has two distinct ones so it
  survives.
- `Calc_heat_flux` — YM75 A13 back-transformation
  `<u'theta'> = (<u'thetav'> - 0.608 theta <u'qv'>) / (1 + 0.608 qv)` is the
  correct inversion of `thetav' = theta'(1+0.608 qv) + 0.608 theta qv'`, and
  `th_wall` correctly adds `T0` to the perturbation potential temperature.
- `dgesvx` workspace — `work(4N)`, `iwork(N)`, `rsf`/`csf(N)` all correctly
  sized; `A` and `B` being overwritten by `FACT='E'` is harmless since both are
  local.

Fixed in this pass:

1. **`l_boulac` read uninitialized in the default configuration.**
   `Calc_l_master_algebra` declares it `intent(out)` but only assigned it in the
   `pbl3d_l_opt == 2` branch, then read it unconditionally at
   `l_boulac(i, kte, j) = l_boulac(i, ktf, j)`. `pbl3d_l_opt = 1` is the
   Registry default, so this read uninitialized memory on every default run,
   and `Make_scale_aware` then multiplied it into a state array that gets
   written to output. Now set to `l_master` on that branch — MY74 makes no
   distinction between the mixing and the dissipation length scale.
2. **Per-gridpoint heap allocation.** `Solve_turb_system` and
   `Solve_turb_system_moist` did `allocate`/`deallocate` of `a`, `af`, `b`, `x`
   on every grid point every timestep — 4 mallocs and 4 frees per point.
   `N_VARS` is a `parameter`, so these are now fixed-size locals.
   Behaviour-identical.
3. Removed unused `iter` in `Calc_fluxes` and the uninitialized `ri` read in
   `Calc_q_sq_l2`'s debug block.

**Found and NOT fixed — these need a decision, see the numbered list at the end
of this section.**

1. `Calc_q_sq_l2_pbl_approx` has the same `l_dissip` bug: the argument is
   passed in, `Fill_dissip_length_scale` computes it, and the routine then uses
   `l_master` anyway and references `l_dissip` only inside a disabled debug
   print. Identical for `pbl3d_l_opt < 3` (where `l_dissip == l_master`), wrong
   for `pbl3d_l_opt >= 3` (BouLac). **Not touched because this is the live,
   validated approximate path** and fixing it changes results there. One-line
   fix when wanted.
2. In `Calc_fluxes`, `sm`, `sh`, `sm_l2`, `sh_l2`, `rif`, `q_sq_hl88` and
   `q_ratio` are computed and never read. For `pbl3d_prog > 0` the entire
   `Prep_for_fluxes_l2p5*` call therefore reduces to
   `Fill_q_sq_with_q_sq_prog`; the rest is wasted work, including the whole
   HL88 limiter. Either wire `sm`/`sh` into the full-3D path or stop computing
   them.
3. `Calc_q_sq_rhs` in `module_pbl3d.F` declares `turb_flux_u2 ... wtheta_v`
   `intent(out)` but only ever *reads* them (passing them to
   `Calc_q_sq_shear`, where they are `intent(in)`). It works today because the
   actual arguments are contiguous full arrays so gfortran passes by reference,
   but the standard leaves the dummies undefined on entry. Should be
   `intent(in)`.
4. **No buoyancy limit on `l` for `pbl3d_l_opt = 1`, the default.** Option 2
   applies `l <= alpha_2 q/N` (with `alpha_2 = 1.0`, about 1.9x looser than
   Deardorff's `0.53 q/N`). Option 1 is purely geometric,
   `l = l0 kappa z/(kappa z + l0)`, with no `N` dependence at all. Combined
   with the earlier result that Tier 1's strain limit can never fire for
   `Ri >~ 0.54`, that means strongly stratified regions — nocturnal
   complex-terrain flow, exactly the hard case — run with an unbounded `l` and
   no limiter of any kind. Applying the standard stability limit on all
   `l_opt` values is defensible and cheap, but it changes the approximate path
   too, so it is left as a decision.
5. `q_sq` and `l_master` are updated in sequence, not iterated: `q_sq` is
   computed with the previous step's `l_master`, then `l_master` is recomputed
   from the new `q_sq`, and the solve then uses the new `l_master` with a
   `q_sq` that does not satisfy the level 2 balance together with it. The
   author's commented-out init code had `do init_iter = 1, 2`, suggesting they
   were aware. A two-pass fixed point inside `Prep_for_fluxes_l2` would be
   cheap and would make the pair genuinely consistent.
6. Moisture fluxes still have no `qv'^2`, so no Cauchy-Schwarz bound and no
   realizability constraint of any kind can be applied to them; the moist Tier 2
   loop can only escalate on `solve_ok`. A 5x5 moist block would close this.

**Not validated by any model run.** Everything above is code-level reasoning
and offline numerics.

## FIX IMPLEMENTED: solvability + realizability safeguards for pbl3d_opt=2
(implemented 2026-07-28; diagnosis of the underlying problem is the section below)

All changes are inside `Diagnose_fluxes` / `Solve_turb_system` /
`Solve_turb_system_moist` in `dyn_em/module_pbl3d_my.F`, which are reached
**only** from `Calc_fluxes`, i.e. only when `pbl3d_opt == 2`. The approximate
(`pbl3d_opt = -1, 1`) branch is bit-for-bit unchanged.

**Guiding idea.** The A matrix has the structure `A = (1/tau) I + S`, where
`tau = l/q` is the turbulence relaxation time scale and `S` carries the mean
gradient terms. It degenerates when `|S| tau ~ 1` — which is exactly the point
where the weak-equilibrium (algebraic) assumption underpinning the whole
closure stops being valid. Ill-conditioning here is not a separate numerical
problem; it is the closure signalling that it is outside its own regime. The
safeguards therefore act on the single physical knob `l`, never on the matrix
entries directly (no diagonal boosting, no ad-hoc regularisation).

**Tier 0 — numerical, zero physics change.**
- `dgesvx` FACT changed `'N'` -> `'E'`, enabling row/column equilibration.
  The columns of A carry mixed units (m2 s-2, K m s-1, K2), so the raw system
  is badly scaled *by construction* and `rcond` was previously dominated by
  units rather than physics. With FACT='N' dgesvx does no equilibration at all.
- `iwork` was declared `real` but LAPACK writes `integer` into it — fixed.
- `info` and `rcond` are now actually used. Note `info` in `[1,N]` means X was
  **not computed**, i.e. the old code was reading uninitialised memory into the
  turbulent fluxes in exactly the failure case that matters most.
- `mat_cond_heat` / `mat_cond_moist` are now filled (previously dead `-9999.`).

**Tier 1 — strain-limited length scale (always on).**
`l_eff = min(l, (2*SK_EPS_MAX/b_1) * q / |S|)`, with `|S| = sqrt(2 S_ij S_ij)`
and `SK_EPS_MAX = 6`. This is Durbin's (1996, *Int. J. Heat Fluid Flow* **17**,
89-90) realizability time-scale bound, written in length-scale form using
`k = q^2/2`, `eps = q^3/(b_1 l)`. With `b_1 = 16.6` the coefficient is ~0.72,
i.e. it is the *shear analogue* of the stability limit `l <= 0.53 q/N` that
`Calc_l_master_algebra` already applies — same structure, same spirit.
`SK_EPS_MAX = 6` is about twice the homogeneous-shear equilibrium value
`Sk/eps ~ 3.3`, so the limiter is inactive in ordinary shear layers and only
engages in the strong-strain regime.
`l_eff` is applied to **both** A and b, which leaves the strain-free limit
exactly untouched: `u'2 = v'2 = w'2 = q^2/3` independently of `l`.

**Tier 2 — local escalation.**
`l_eff` is halved and the solve retried, up to 6 times, while the solve reports
`info /= 0` or `1/rcond > 1e8`, **or its solution is not a physically possible
turbulence state** (new `pure logical function Is_realizable`, full Sylvester
positive semi-definiteness of the stress tensor, not just non-negative
variances). Shortening `l` shortens the return-to-isotropy time scale,
strengthening the diagonal *physically*. The escalation has a well defined
endpoint: as `l -> 0` the matrix becomes exactly diagonal and its solution is
isotropic turbulence carrying the correct TKE — so the sequence always
terminates in an admissible state, never in a numerical artefact. That terminal
state is also written out explicitly as a hard fallback.

Escalating on unrealizability rather than only on solver distress is the single
most consequential choice here. Monte-Carlo over synthetic gradient tensors: an
outright singular `A` occurs in ~0.005% of states, whereas a well-conditioned
solve returning an impossible stress state occurs in 6-40% of states in strong
strain — and 1-9% even at equilibrium `Sk/eps ~ 3.3`, where Tier 1 is inactive
by design and cannot help. Escalation costs ~0.4 extra solves per point on
average and leaves 0.00% residual unrealizability, versus 6-9% left for Tier 3
to project away if the trigger is solver distress only. It is also the less
distorting option, because each escalation step returns an *exact solution of
the closure at a shorter length scale*, whereas the Tier 3 projection returns a
state that solves no equation at all.

`l_eff` is only shortened when another attempt actually follows, so on
exhaustion it still describes the state returned — Tier 3 and the moisture
system both consume it.

**Tier 3 — realizability enforcement (always on, no-op when already satisfied).**
New `pure subroutine Enforce_realizability`. Nothing in it is a free parameter:
1. Variances floored at zero (definitional).
2. **Trace restored exactly.** Rows 1-3 of A cancel exactly on columns 4-10
   (including the buoyancy column 9) and sum to `q/(2 a_1 l)` on columns 1-3,
   while `b1+b2+b3 = q^3/(2 a_1 l) + 3 c_1 q^2 div(U)`. Hence
   `u'2 + v'2 + w'2 = q^2 (1 + 6 a_1 c_1 l div(U) / q)` is an **exact identity of
   this very system** (verified numerically to a relative error of 7e-14),
   reducing to `= q^2` for non-divergent flow. Any departure is numerical error,
   so rescaling to it restores a property only round-off can break. (The
   divergence correction stays bounded in [0.61, 1.39] once Tier 1 is active,
   since `|div U| <= sqrt(3/2)|S|`.)
3. Cauchy-Schwarz on all covariances and buoyancy fluxes,
   e.g. `(u'w')^2 <= u'2 w'2`, `(w'tv')^2 <= w'2 tv'2`. These are the 2x2
   principal minors of the stress tensor.
4. **Positive semi-definiteness of the stress tensor as a whole.** Steps 1 and 3
   supply the non-negative diagonal and the three 2x2 principal minors, so by
   Sylvester's criterion the only condition still missing is `det >= 0`. Pairwise
   Cauchy-Schwarz is *not* sufficient: measured over synthetic states, 6-9% of
   points passing steps 1-3 still had a negative eigenvalue, i.e. a negative
   variance along some rotated axis, and ~1-4% even at equilibrium. Restored by
   shrinking all three covariances with one common factor `gamma`, found by
   bisection on the cubic `det(gamma) = det_0 - det_2 gamma^2 + det_3 gamma^3`
   (non-negative at `gamma = 0` because step 1 floored the variances, so
   bisection maintaining `det(gam_lo) >= 0` always returns an admissible factor).
   This preserves the trace — hence the TKE — exactly, and the sign and relative
   magnitude of every flux. Measured cost: touches ~2-10% of points with mean
   `gamma ~ 0.93-0.99`, changing mean `|u'w'|` by under 1%.
This is the full-3D counterpart of the HL88 criterion the approximate branch
already applies — same principle, existing precedent in the same file.

Moisture fluxes get Tiers 0-2 but no Cauchy-Schwarz bound: the 4x4 moist system
solves for `tv'q'` as its fourth unknown, not `q'2`, so no variance is available
to bound them against. Noted rather than approximated.

**Diagnostics.** `Calc_fluxes` counts points where escalation fired and reports
via `wrf_debug(100, ...)`. A healthy run should show this rarely or never; a
run that reports it constantly is a signal that the flow is chronically outside
the closure's validity range at that resolution/terrain.

**Cost.** One `sqrt` + one `min` per point for Tier 1; Tier 2 retries only at
points that actually failed (~0.4 extra solves per point in strong strain, 0.01
at equilibrium); Tier 3 is a handful of flops plus, at the few percent of points
that need it, a 20-step bisection on a cubic. Equilibration in `dgesvx` is
O(N^2) against an O(N^3) factorisation. Net overhead should be well under the
noise of the existing solve.

**Measured effect on the modelled eddies** (synthetic gradient tensors, Lumley
barycentric decomposition of the stress tensor; orderings are robust, absolute
percentages are not predictions for a real run):
- At equilibrium (`Sk/eps = 3.3`, where the neutral surface layer actually
  sits — `u* = 0.3 m/s`, `z = 100 m` gives `Sk/eps = 3.2`) the safeguards are
  invisible: Tier 1 is an exact no-op, and `w'2/q^2`, `|u'w'|` and all three
  barycentric coordinates are unchanged to three decimals.
- Beyond it, the *unguarded* solution is not physics to be preserved: at
  `Sk/eps = 6` the unguarded mean eddy viscosity is ~6x larger and the mean
  anisotropy tensor is far outside the realizable triangle (`C_3c = -4.4`).
- Where they engage, the safeguards shorten the eddy lifetime and drive the SGS
  stress toward isotropy. Tier 1 changes the *form* of the eddy viscosity in the
  limited regime from `K ~ q l` to `K ~ 0.72 q^2/|S| ∝ k/S`, i.e. the standard
  realizable-`k-eps` bound.
- Tier 1 combined with the existing stability limit `l <= 0.53 q/N` implies
  `Sk/eps <= 4.40/sqrt(Ri)`, so **Tier 1 can never activate for `Ri >~ 0.54`** —
  it is a near-neutral / unstable, strongly-sheared limiter (terrain distortion,
  lee slopes, gap flows, entrainment zone), not a stable-BL one.
- **Tier 1 alone is not a safeguard and can make the solution worse** (3D strain,
  `Sk/eps = 20`: mean `|u'w'|` goes 0.63 unguarded -> 1.31 with Tier 1 only). It
  improves conditioning, not realizability, and is only sound paired with
  Tiers 2-3.
- Relying on the Tier 3 projection instead of Tier 2 escalation biases the SGS
  eddies toward one-component, vertically flattened structure (`C_1c` 0.59 ->
  0.70, `w'2/q^2` 0.21 -> 0.17 at `Sk/eps = 6`), drives `w'2` to *exactly* zero
  at ~16% of affected points (which via Cauchy-Schwarz zeroes `u'w'`, `v'w'` and
  `w'tv'` there, patchily in space), and in stable layers preserves heat mixing
  while cutting momentum mixing — an artificially low turbulent Prandtl number
  exactly where `Pr_t` should be rising with `Ri`. This is the concrete reason
  the Tier 2 trigger includes unrealizability.

**Still open after this fix:** recommendation #3 below (re-deriving the disabled
self-consistent full-3D TKE prep, `Prep_for_fluxes_l2`/`_l2p5`) is untouched —
the full path still takes its TKE and length scale from the approximate closure.
These safeguards make the solve robust; they do not make the closure
self-consistent.

**Not yet validated by a model run** — compiles clean; needs a `pbl3d_opt=2`
regression over both flat and complex terrain to confirm it actually holds
together.

---

## MAIN PROBLEM: full-3D (pbl3d_opt=2) closure has no realizability safeguard
(investigated 2026-07-28; fixed by the section above)

**Which implementation is which:** confirmed directly in code
(`dyn_em/module_pbl3d_my.F:141`, inside `Calc_turb_fluxes_my`):
```fortran
if (config_flags%pbl3d_opt < 2) then  ! PBL approx analytical solution only
  call Calc_fluxes_pbl_approx (...)
else if (config_flags%pbl3d_opt == 2) then  ! Full 3D numerical solution
  call Calc_fluxes (...)
```
So `pbl3d_opt=-1` or `1` -> the homogeneity-approximation ("approx 3D") path,
analytically solvable, no matrix inversion. `pbl3d_opt=2` -> the "full 3D"
path: builds the complete anisotropic second-moment system (9-component
deformation tensor + 3D buoyancy gradient) and solves it numerically via
LAPACK (`dgesvx`) in `Solve_turb_system` (10x10, momentum+heat) and
`Solve_turb_system_moist` (4x4, moisture), called from `Diagnose_fluxes`.
This matches the two Kosović-Juliano formulations from the user's
description exactly.

**Root cause of the instability, found:**

1. **The full closure's own TKE-prep path is disabled by its original
   author**, with an explicit comment admitting why
   (`module_pbl3d_my.F:940`, inside `Calc_fluxes`):
   ```fortran
   ! Full 3D level 2 model is unstable right now
   !      if ( config_flags%pbl3d_prog .eq. 0 ) then   ! level 2 model
   !        call Prep_for_fluxes_l2 (...)
   !      else if ( config_flags%pbl3d_prog .gt. 0 ) then   ! level 2.5 model
   !        call Prep_for_fluxes_l2p5 (...)
   !      end if
   ! Calling level 2 model PBL approx for now
   if ( config_flags%pbl3d_prog .eq. 0 ) then
     call Prep_for_fluxes_l2_pbl_approx (...)
   else if ( config_flags%pbl3d_prog .gt. 0 ) then
     call Prep_for_fluxes_l2p5_pbl_approx (...)
   end if
   ```
   So even in "full 3D" mode, the TKE (`q_sq`) and master length scale
   (`l_master`) that feed the full anisotropic solve are computed by the
   simpler, homogeneous-approximation closure instead of a self-consistent
   full-3D TKE budget — an internal inconsistency the original author was
   already aware of and worked around rather than fixed.

2. **No realizability/condition check on the linear solve's output.**
   `Solve_turb_system`/`Solve_turb_system_moist` (both in
   `module_pbl3d_my.F`) call `dgesvx`, which returns both an error/status
   code (`info`) and a reciprocal condition number estimate (`rcond`) —
   exactly the diagnostics needed to detect an ill-conditioned or failed
   solve. Neither is used:
   ```fortran
   call dgesvx ('N', 'N', N_VARS, 1, a, N_VARS, af, N_VARS, ipiv, equed, &
       rsf, csf, b, N_VARS, x, N_VARS, rcond, ferr, berr, work, iwork, info)
   !      mat_cond = 1. / rcond          <-- commented out, in BOTH subroutines
   ```
   `info` is declared but never read after the call, in either subroutine.
   `mat_cond_heat`/`mat_cond_moist` (the caller's diagnostic arrays) are
   initialized to a `-9999.` sentinel in `Calc_fluxes` and never touched
   again — confirmed by grep, this diagnostic is 100% dead code.

3. **No realizability clipping on the solved fluxes.** After the solve,
   `Diagnose_fluxes` copies `tf_u2`/`tf_v2`/`tf_w2`/etc. straight into
   `turb_flux_u2`/`turb_flux_v2`/`turb_flux_w2`/etc. with zero floor/bound
   check — no non-negativity floor on the variances (which are physically
   required to be >=0), no Cauchy-Schwarz-type bound on the correlations
   (e.g. `tf_uw^2 <= tf_u2*tf_w2`). By contrast, the **approx** path
   explicitly implements the Helfand & Labraga (1988, JAS) realizability
   criterion for exactly this purpose — see the comment "so that we can
   apply HL88 realizability criterion" in
   `Prep_for_fluxes_l2p5_pbl_approx`, and the `q_sq_hl88`/`use_hl88`
   machinery that backs it. This is very likely *why* the approx path is
   comparatively stable and the full path is not: one has an enforced
   realizability guarantee, the other has none at all.

4. **Plausible destabilization mechanism, matching the user's own
   description** (unstable especially over complex terrain, not fully
   stable even over flat terrain): the diagonal of the 10x10 matrix
   combines a stabilizing "return-to-isotropy" relaxation term
   (`q/(2*a_1*l)`, always positive) with the local mean-flow strain rate
   added directly on top (e.g. `a(1,1) = q/(2*a_1*l) + 2*u_x` for the u2
   equation, `Fill_in_a_matrix`, `module_pbl3d_my.F:1529`). Sufficiently
   strong local convergence/divergence or shear (more likely, and more
   extreme, over complex terrain, but also possible in vigorous convective
   updrafts/downdrafts over flat terrain) can degrade or destroy the
   matrix's diagonal dominance, pushing the solve toward ill-conditioning
   or outright unphysical (e.g. negative-variance) output — with nothing
   in the code to detect or catch it before that output is used directly
   as SGS forcing on the resolved flow, which can then further amplify the
   local strain on the next timestep. This is consistent with the extreme
   vertical-velocity blowup (`w-cfl` ~14, SIGSEGV) observed empirically
   during Phase 1 regression testing under a strong prescribed surface
   flux, on both the pre- and post-rebase code (i.e. a longstanding bug,
   not something introduced by the v4.8.0 rebase).

**Recommended fix, in order of effort/risk:**

1. *Immediate, low-risk safety net:* re-enable `mat_cond = 1./rcond` and add
   an explicit `info` check after both `dgesvx` calls. Whenever
   `info /= 0` or `rcond` falls below a safe threshold (a common rule of
   thumb is `~1e-6`; LAPACK's own docs discuss the precision loss implied
   by small `rcond`), fall back to the already-implemented, analytically
   realizable `_pbl_approx` solution for that column/level instead of
   trusting the raw linear-solve output.
2. *Realizability clipping:* independent of #1, floor `tf_u2`/`tf_v2`/
   `tf_w2` at a small positive value (matching the existing `Q_SQ_MIN`
   floor already used elsewhere for `q_sq`), and check/clip the
   off-diagonal correlations against a Cauchy-Schwarz-consistent bound.
   Catches cases where the matrix was well-conditioned but the solution
   itself still isn't physical.
3. *Root-cause / longer-term fix:* investigate and properly re-derive the
   disabled `Prep_for_fluxes_l2`/`Prep_for_fluxes_l2p5` (the fully
   self-consistent full-3D TKE prep), rather than continuing to feed the
   full anisotropic solve a TKE/length-scale computed by the simpler
   homogeneous closure. Bigger, more open-ended effort — needs
   understanding why the original author found *that* code unstable
   (plausibly the same missing-realizability issue, one level up in the
   TKE equation itself).

Not yet implemented — this is a diagnosis, pending a decision on which fix
to pursue first.


## Status update (2026-07-28): WRFlux integration, phase 2

Branch `3dpbl_wrflux_v4.8.0` (built on top of `3dpbl_on_v4.8.0`) merges
matzegoebel/WRFlux's full patch (squashed from its v4.6.0 fork point,
437 commits, 47 files, +16k/-236 lines) on top of the rebased pbl3d code.
The merge itself needed only 6 real conflicts despite the scale (see commit
`5cd6bf989`), plus one real bug the merge exposed at compile time (a
`doing_q_sq` argument silently dropped from one of two sibling
`advect_scalar` calls, fixed in `8c3195c98`).

**Vertical SGS flux integration (done, empirically validated):** WRFlux's
two generic mechanisms for populating `ftz_sgs`/`fqz_sgs`/`fuz_sgs`/`fvz_sgs`
(`fluxes_from_bl_tend` for standard PBL schemes, `vertical_diffusion_implicit`
for km_opt=5) are both gated off whenever `pbl3d_opt>0`. Added
`Populate_wrflux_sgs_from_pbl3d` in `module_pbl3d.F` (commits `f51607318`,
`5462557ea`) which populates those arrays plus `fwz_sgs` directly from
pbl3d's own native kinematic flux diagnostics (`turb_flux_wtheta[_v]`,
`turb_flux_wqv`, `turb_flux_uw`, `turb_flux_vw`, `turb_flux_w2`), converted
to WRFlux's density-weighted convention and correctly staggered (rho
interpolated mass-point -> w-level via fnm/fnp, momentum terms staggered
onto u/v points via two-point averaging) — mirroring the exact conventions
`module_diffusion_em.F`/`vertical_diffusion_implicit` use elsewhere in this
codebase. Validated with a controlled test (fixed hfx=50 W/m^2 injected at
the pbl3d call site, mesoscale dx=4000m case): `FTZ_SGS_MEAN` max (0.0449)
matches the hand-derived theoretical surface value (hfx/(rho*cp)*rho ≈
0.050) closely, with the domain+height-averaged mean correctly much
smaller as the flux decays toward the PBL top. Momentum/moisture/w-variance
terms all show sensible non-zero magnitudes and physically expected signs.

**Horizontal SGS flux integration (done, 2026-07-28):** `ftx_sgs`, `fty_sgs`,
`fqx_sgs`, `fqy_sgs`, `fux_sgs`, `fvx_sgs`, `fvy_sgs`, `fwx_sgs`, `fwy_sgs` are
now all populated too (commit `cd1cb48e2`), extending
`Populate_wrflux_sgs_from_pbl3d`. As found: pbl3d's Registry-declared
`turb_flux_u2_mass`/`v2_mass`/`uv_mass`/`uw_mass`/`vw_mass`/`wtheta_v_mass`
mass-point variants are dead entries (never assigned anywhere in
`module_pbl3d.F`/`module_pbl3d_my.F`), so vertical de-staggering
(w-level -> mass-level, two-point average) was done manually from the raw
Z-staggered diagnostics instead. `fwx_sgs`/`fwy_sgs` reuse `fuz_sgs`/`fvz_sgs`
directly rather than recomputing, since they're the same physical stress
component (u'w'/v'w') viewed from the w-momentum equation's horizontal-flux
side instead of the u/v-momentum equation's vertical side. Validated:
`FWX_SGS_MEAN`/`FWY_SGS_MEAN` came out bit-identical to `FUZ_SGS_MEAN`/
`FVZ_SGS_MEAN` as designed, and the horizontal heat/moisture flux means came
out near-zero as expected for the horizontally homogeneous periodic test
case, with sensible non-zero variability.

One caught-but-not-yet-fixed bug during implementation: an early version
computed the vertically de-staggered mass-level fields (e.g. `utheta_mass`)
as tile-local intermediate arrays, then read a `j-1`/`i-1` neighbor from
them for `fty_sgs`/`fqy_sgs`/`fvx_sgs` — but under OMP tiling, a neighboring
tile's portion of that same tile-local array was never computed in the
current call, so this would have read uninitialized memory. Fixed by
inlining those specific computations directly from the grid-level
(halo-safe) `turb_flux_*` arrays instead of via the tile-local intermediate.
`u2_mass`/`v2_mass` were kept as tile-local arrays since `fux_sgs`/`fvy_sgs`
only read them at the same `(i,j)`, with no neighbor offset — safe.

Known remaining narrow gap: `turb_flux_utheta_v`/`turb_flux_vtheta_v` (the
virtual-theta variants, used only when `output_dry_theta_fluxes=.false.`,
a non-default WRFlux setting) are read with an `i-1`/`j-1` neighbor offset
for `ftx_sgs`/`fty_sgs` but were never halo-exchanged anywhere in pbl3d's
own code (only ever used at the same point elsewhere), unlike the plain
`turb_flux_utheta`/`turb_flux_vtheta` (which the existing
`HALO_EM_PHYS_DIFFUSION_PBL3D` halo macro does cover). The default case
(`output_dry_theta_fluxes=.true.`, dry theta, what this session's testing
used) is unaffected and halo-safe. If the non-default virtual-theta output
is ever needed, either add a halo exchange for those two fields or add a
new Registry halo macro entry.

**Not yet done: rigorous WRFlux-native budget closure.** The validation
above is a physical-magnitude sanity check, not WRFlux's own bit-for-bit
closure test (which needs their Python toolkit under `wrflux/wrflux/`,
comparing resolved+SGS+tendency terms to near machine precision). Worth
running once the horizontal terms are in, if a rigorous closure number is
needed (e.g. before publishing results based on this integration).

## 1. sfclay HFX discrepancy between v4.4 and v4.8.0 (unresolved)

**Symptom:** In an idealized mesoscale test case (dx=4000m, `pbl3d_opt=2`,
`bl_pbl_physics=0`, `isfflx=2`, `sf_sfclay_physics=1`, static `TSK`),
`grid%HFX` (surface sensible heat flux, as computed by the stock
surface-layer driver) stayed exactly 0.0 for the entire 2-hour run on the
v4.8.0 branch, while the identical namelist on the v4.4 branch produced
growing HFX (68 -> 172 W/m^2 over 2 hours). This caused turbulence
intensity (U/V/W std, PBLH variability, turb_flux_* fields) in the v4.8.0
run to be ~20x weaker than in the v4.4 run.

**What's been ruled out:**
- `pbl3d_opt` was correctly parsed as 2 in both runs (confirmed via
  `namelist.output`).
- `isfflx=2` was correctly parsed as 2 in both runs.
- `tke_heat_flux` (the namelist var meant to force surface flux at
  `diff_opt=2`/`km_opt=2`) is irrelevant here regardless of version: it's
  only read inside `dyn_em/module_diffusion_em.F`, which isn't invoked when
  `diff_opt=0` (required for `pbl3d_opt>0`). Identical in both branches.
- The 3D PBL scheme itself (`dyn_em/module_pbl3d.F`) consumes `grid%hfx` /
  `grid%qfx` directly as plain input arguments — it does not read
  `tke_heat_flux` at all. So this is not a pbl3d-code issue; the zero is
  coming from upstream of pbl3d, in the stock surface-layer chain
  (`phys/module_sf_sfclay.F` / `phys/module_surface_driver.F`), neither of
  which the fork modifies.

**Not yet determined:** why the *stock* surface-layer scheme's `isfflx=2`
handling produces different HFX between WRF v4.4 and v4.8.0 given identical
namelist/TSK. Two live hypotheses:
  (a) a genuine upstream behavior change in `module_sf_sfclay.F` /
      `module_surface_driver.F` over the ~4 years of drift (plausible —
      sfclay gets frequent revisions), unrelated to the 3D PBL fork; or
  (b) `isfflx=2` was never a reliable way to force this scheme in the first
      place (it may have been effectively dead/inert outside the
      `diff_opt=2` context in both versions, and the "growth" seen in v4.4
      is coincidental/from a different source than a genuine flux).

**Status:** deferred. Not blocking the rebase regression test, since we're
bypassing sfclay's HFX entirely by injecting a fixed HFX/QFX directly at the
pbl3d call site for the controlled comparison (see below). Worth revisiting
if/when real-data or production runs with pbl3d + isfflx are planned, since
production use would rely on sfclay's real HFX, not an injected constant.

**Controlled-comparison result (2026-07-28):** with a fixed `grid%hfx=50.0`
/ `grid%qfx=0.00005` injected identically into both branches immediately
before the pbl3d sub-stepping loop in `module_first_rk_step_part2.F`
(bypassing sfclay's HFX entirely), a 2-hour dx=4000m `pbl3d_opt=2` run on
both v4.4 and v4.8.0 produced statistically consistent results:
  - Domain-mean `T`, `QVAPOR`, `TURB_FLUX_WTHETA` matched to 3-5 significant
    figures between the two branches.
  - `PBLH` mean/range matched closely (375 vs 378 m mean; similar spread).
  - `U`/`V`/`W` std and other `turb_flux_*` fields differed by ~15-20%
    (old running slightly more turbulent than new), consistent with the
    normal chaotic sensitivity of convective turbulence to any tiny
    perturbation (compiler differences, random-seed handling in
    `module_initialize_ideal.F`, etc.) rather than a functional regression
    in the ported pbl3d code — an exact bit-match after 2h of chaotic
    evolution would itself be the surprising result.
  - Conclusion: no evidence the rebase changed the 3D PBL scheme's behavior.
    The original sfclay HFX=0-vs-nonzero discrepancy remains unexplained
    but is now confirmed to be a stock-WRF surface-layer question, separate
    from and not a blocker for the pbl3d rebase itself.

**Patch used for this test** (uncommitted, local-only, must be reverted
before any real use of these branches):
```fortran
! TEMPORARY: fixed HFX/QFX override for old-vs-new regression test (see OPEN_ISSUES.md #1)
grid%hfx = 50.0
grid%qfx = 0.00005
```
inserted at the top of the "Sub-stepping for 3DPBL" block in
`dyn_em/module_first_rk_step_part2.F`, identically in both the
`3dpbl_on_v4.8.0` working tree and the `wrf-v4.4-old` worktree.

## 2. LES-scale testing is not representative of pbl3d's intended use case

Already discussed with user — LES-resolution (dx~100m) tests exercise the
scheme's "scale-aware tapering" edge case, not its primary mesoscale PBL
parameterization role. Mesoscale-resolution (dx~4000m) idealized testing is
the more appropriate regression check; this is what's now in progress.

## 3. WRFlux compatibility (deferred from original scope)

The 3D PBL scheme bypasses the standard `module_pbl_driver.F` tendency path
entirely (early return when `pbl3d_opt>0`), computing/injecting tendencies
via its own sub-stepping loop in `module_first_rk_step_part2.F`. WRFlux
assumes conventional PBL schemes report through `RUBLTEN`-style arrays via
`module_pbl_driver.F` and reconstructs vertical flux by integrating those
top-down — this won't see pbl3d's mixing at all. The scheme already
computes native `turb_flux_*` diagnostics, which is the right data source
for a WRFlux integration, but this hasn't been implemented. See prior
conversation for full detail. Not started.

---

## OPEN (A10): the `sf_alpha` slope taper breaks the SGS energy pairing

Raised 2026-08-20 from code reading, after A9 was fixed. **Not measured in-model
yet** — the offline attempt failed its own sanity check (below).

`Calc_slope_factor` (`dyn_em/module_pbl3d.F:3077-3081`) builds

```
sf_alpha ~ |grad h| * dx/dz  =  max( sqrt(tmpzx^2 + tmpzy^2), 1 )
```

and `Calc_htend_du/dv/dw/ds` **divide** the horizontal turbulent tendency by it
(`:4031-4044`, `:4299`). `Vertical_turb_mix` carries no such factor, and
`Calc_q_sq_shear` (`:6238`) contracts the **untapered** stresses against the full
nine-component strain.

`P` is not a free-standing quantity — it is by definition the rate the resolved
flow loses kinetic energy to those same stresses. Tapering one end and not the
other means SGS energy appears having been removed from nothing.

**The footprint is domain-wide, not a steep-slope corner case.** `dx/dz ~ 30`
here, so a 2 deg slope already gives 1.05, 10 deg gives 5.3, 20 deg gives 10.9.
Measured over all 300,000 columns at the lowest model level:

| | |
|---|---|
| median `sf_alpha` | **5.2** |
| 90th percentile | 11.3 |
| max | 21.2 |
| fraction of domain > 2x | **67%** |
| fraction > 5x | **51%** |
| fraction > 10x | 18% |

So horizontal turbulent mixing of momentum, heat and moisture is suppressed
five-fold or more over half this domain. (Earlier text in A9 described this as
affecting the 208 points steeper than 30 deg. That was wrong by three orders of
magnitude in footprint.)

**Why it also explains the opt=1 / opt=2 split.** Of the nine production terms,
three pair with the untapered vertical mixing (`uw*du_dz`, `vw*dv_dz`,
`w2*dw_dz`) and six with the tapered horizontal mixing. The three untapered ones
are almost exactly `Calc_q_sq_shear_pbl_approx`. So `opt=1` is energetically
self-consistent by accident, and the defect switches on only at `opt=2`.

**Magnitude: NOT established.** An offline decomposition was attempted at 01:30
using `TURB_FLUX_UW/VW/W2` from wrfout plus gradients reconstructed from U, V, W,
taking `P_horiz` as the residual against `Q_SQ_SHEAR`. **It failed**: correlation
between the reconstructed `P_vert` and the model's `Q_SQ_SHEAR` was 0.067, so the
residual is dominated by reconstruction error, not by horizontal production. A
figure of "59% of production is spurious" was produced this way and is
**retracted**. Probable cause: the mass->face interpolation smooths away the sharp
near-surface shear that `Calc_du_dz_at_mass` resolves with `fnm`/`fnp` weights.

Crude bound only: if the horizontal terms carry 10-75% of shear production, the
spurious input is 8-60% of it over half the domain.

**Why this now matters more, not less, after A9 was fixed.** The A9 fix *damps*;
`sf_alpha` is a spurious *source*. Two large errors of opposite sign may now be
partially cancelling — a worse position than one error, because tuning against
the MYNN control would reward the cancellation instead of exposing it.

**Next step: the SGS energy-closure diagnostic.** One Registry field comparing
the resolved-KE loss implied by the applied turbulent tendencies against
`Q_SQ_SHEAR/2`. In a consistent closure they are equal by construction. This
measures the mismatch *inside* the model, where the offline reconstruction cannot
reach. Costs one `--reconfigure`. **Do this before the 47 h control run**, not
after, for the compensating-errors reason above.

The fix itself, once the diagnostic confirms it: taper the six horizontal-pairing
terms of `Calc_q_sq_shear` by the same `sf_alpha`, leaving the momentum tendency
untouched. That restores the pairing without changing the dynamics or
reintroducing whatever numerical fragility `sf_alpha` was added to suppress.
