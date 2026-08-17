# Change log — `3dpbl_wrflux_v4.8.0`

Working notes on the 3D PBL fixes carried by this branch, grouped by change set.
Newest group first.

**Related files:** `OPEN_ISSUES.md` (open defects in the scheme), `KNOWN_ISSUES.md`
(upstream WRF bugs and environment traps).

**Base:** `da0c5ef88` *Document horizontal SGS flux completion and diagnose the
full-3D instability*

Group letters are **labels, not chronology** — J and I were added after H. Sections
run newest first.

---

# How this was committed

## The four commits

Committed 2026-07-31 on `3dpbl_wrflux_v4.8.0`, on top of `da0c5ef88`. Each leaves
the tree compiling — 1 and 2 are independent of the scheme, 3 is the smallest set
that builds (the Registry fields, the `Init_pbl3d` argument chain and
`module_pbl3d_my.F` must move together), and 4 is documentation. **Established by
dependency, not by building each state.**

| # | commit | subject | paths |
|---|---|---|---|
| 1 | `4479a638f` | Centre the em_les test mountain and fix its width in metres | `dyn_em/module_initialize_ideal.F` |
| 2 | `a961effc8` | Carry the sf_sfclayrev table lower-bound fix as a submodule patch | `patches/physics_mmm-sf_sfclayrev-table-lower-bound.patch` |
| 3 | `6aa59ea69` | Make the full-3D closure (pbl3d_opt=2) solvable and realizable | `dyn_em/module_pbl3d_my.F` `dyn_em/module_pbl3d.F` `dyn_em/start_em.F` `Registry/Registry.EM_COMMON` `run/README.namelist` `share/module_check_a_mundo.F` |
| 4 | *(this file)* | Document the 3D PBL fixes, open issues and environment traps | `CHANGES.md` `OPEN_ISSUES.md` `KNOWN_ISSUES.md` |

Commit 3 carries groups A–I. Its message body is the group list from this file — the
granularity that cannot be preserved in the history is preserved there.

**Not pushed.** There is no remote this branch can be pushed to yet; see the rebase
plan for the fork-of-record step.

## Why groups A–I are not one commit each

They are interleaved inside `dyn_em/module_pbl3d_my.F` at the routine level, and
in places at the block level:

| routine | groups sharing it |
|---|---|
| `Calc_l_master_algebra` | E (`l0` weighting), G (buoyancy limit) |
| `Calc_fluxes` | B, C, D, I |
| `Diagnose_fluxes` | A (tiers 0–3), G (`l` limit reaches the solver), H (moist tier 3), I (diagnostics) |
| `Solve_turb_system_moist` | A, H |

Several groups also *edit lines an earlier group introduced* — H extends A's Tier 3
bit histogram from 5 bins to 8, and I reads the `l_use` that A's Tier 2 produces.
A per-group split is therefore not a hunk partition; it would need hand-written
intermediate states, none of which has ever been compiled or run.

The one split that does correspond to a state that existed is **A–F | G–H**: the
2026-07-30 10:57 build was A–F, the 2026-07-31 build is A–I. Verifying it would cost
a `./clean` + full rebuild in this tree, which destroys the `em_les` executable the
verification runs used, and cannot be done concurrently (KNOWN_ISSUES G6). Not
recommended.

## ⚠ Do not `git add -A`

Still true for any future commit on this branch. The build leaves ~40 untracked
generated files. List as of `git status` 2026-07-31:

```
Registry/Registry                       Registry/io_boilerplate_temporary.inc
frame/module_dm.F  frame/md_calls.inc   frame/module_state_description.F
inc/dm_comm_cpp_flags  inc/wrf_io_flags.h  inc/wrf_status_codes.h
external/RSL_LITE/*.f90                 external/io_grib1/io_grib1.f90
external/io_grib_share/io_grib_share.f90
external/io_int/diffwrf   external/io_int/test_io_idx   external/io_netcdf/diffwrf
phys/module_bl_mynnedmf*.F  phys/module_sf_mynnsfc_*.F  phys/module_cu_gfl_*.F
phys/module_mp_tempo_*.F90              (symlinks into the phys/* submodules)
run/namelist.input  run/input_sounding  run/NoahmpTable.TBL
test/em_les/README.namelist  test/em_real/README.namelist
test/em_real/BROADBAND_CLOUD_GODDARD.bin
run_baseline_test/  run_pbl3d_test/     (run directories, not source)
```

## ⚠ `phys/physics_mmm` is a submodule and cannot carry the fix

The `sf_sfclayrev` fix (issue U1, described under group G) lives in
`phys/physics_mmm`, a submodule of `https://github.com/NCAR/MMM-physics.git`
pinned at `550b5b4`. Two consequences:

- **`git status` shows `phys/physics_mmm` as modified, but the gitlink SHA is
  unchanged** (`550b5b4` → `550b5b4-dirty`). Committing it in the parent repo
  records nothing and preserves nothing. The fix would be lost on a fresh clone.
- Committing *inside* the submodule and bumping the gitlink would pin this fork to
  a SHA that exists only on this filesystem — unclonable for anyone else.

So it is carried as `patches/physics_mmm-sf_sfclayrev-table-lower-bound.patch`
(commit 2), reapplied with:

```bash
cd phys/physics_mmm && git apply ../../patches/physics_mmm-sf_sfclayrev-table-lower-bound.patch
```

Leave `phys/physics_mmm` and `phys/noahmp` out of every `git add`. This is a
stopgap: the real fix is to report U1 upstream.

---

## Group J — Centred, fixed-width test mountain for `em_les`
*(2026-07-31; `dyn_em/module_initialize_ideal.F`)*

Suggested message: **`Centre the em_les test mountain and fix its width in metres`**

Test-harness only — inside `#ifdef MTN`, which is set by `-DMTN` in `configure.wrf`
and is off in any stock build. Two changes to the `em_les` cosine-bell mountain,
both needed to make it a complex-terrain test rather than a token bump:

1. **It is centred on the domain.** The original block set `xs = ids - 3`, putting
   the mountain on the western boundary, where the periodic BCs `em_les` normally
   runs with split it in half.
2. **Its width is fixed in metres** (7000 m, `mtn_wid = max(4, nint(7000./dx))`)
   rather than at 6 grid cells, so refining `dx` resolves the same mountain instead
   of shrinking it.

The ridge-line profile `h = hm/2 (1 - cos 2*pi*s)` has steepest slope `hm*pi/7000`,
so `hm` (namelist `&domains`) sets the maximum terrain angle directly:
`theta_max = atan(hm*pi/7000)`. `hm = 1000` → 24.2°, `hm = 1560` → **35.0°**,
`hm = 2000` → 41.9°. 35° is the Inn Valley target.

Separable from everything else and committed first because nothing depends on it.

---

## Group I — Per-gridpoint solver diagnostics in `wrfout`
*(2026-07-31; `dyn_em/module_pbl3d_my.F`, `dyn_em/module_pbl3d.F`, `Registry/Registry.EM_COMMON`, `run/README.namelist`)*

Commit 3 body bullet: **`Write the Tier 1/2/3 solver state to history as per-gridpoint fields`**

Groups A–H are all *conditional* — a tier that fires at 0.3% of points and a tier
that fires at 24% of them look identical in the output fields. Without these, none
of the verification results quoted below could have been measured at all.

Six new `h` (history-only) state fields, filled once per grid point in `Calc_fluxes`
from values returned by `Diagnose_fluxes`:

| field | meaning |
|---|---|
| `pbl3d_sk_eps` | `S k / eps` **before** Tier 1 limiting — the raw strain the point would have run at |
| `pbl3d_t1_ratio` | `l_use / l_master` after Tier 1; `1.0` = the strain limit did not bind |
| `pbl3d_t2_steps` | Tier 2 length-scale back-off steps taken |
| `pbl3d_t3_flags` | Tier 3 bitmask, 8 bits: 1 var floor, 2 trace, 4 Cauchy-Schwarz, 8 determinant, 16 heat, 32 `qv2` floor, 64 `qv` CS, 128 `qv-thetav` CS |
| `pbl3d_n_tau` | **signed** `N*tau`; negative means unstable stratification, which is where the buoyancy coupling degenerates the matrix rather than stiffening it |
| `pbl3d_cond_a` | condition number of the 10x10 momentum-heat matrix |

The sign convention on `pbl3d_n_tau` is the one that matters: the two failure modes
(`|N*tau|` large and stable, `|N*tau| -> 0.21` and unstable, group F) are opposite in
sign and would be indistinguishable in a magnitude.

Also aggregated per timestep into the existing `wrf_debug(100, ...)` summary:
Tier 1 bind rate, Tier 2 escalation rate, the 8-bin Tier 3 histogram, and
`max(Sk/eps)` / `min,max(N*tau)`.

**Also corrected here:** `run/README.namelist` documented `pbl3d_prog` with default
`0`. The Registry default is and always was `1`. The prose was rewritten at the same
time to say *why* the two levels differ in practice — level 2 forces `q^2` to
`Q_SQ_MIN` above `rif_c` (gradient `Ri = 0.195`), level 2.5 does not gate on it at
all — which is the property that decides whether a nocturnal or cold-pool column has
any turbulence.

---

## Group H — A4: moisture variance and moisture-side realizability
*(2026-07-31; `dyn_em/module_pbl3d_my.F`, `dyn_em/module_pbl3d.F`, `Registry/Registry.EM_COMMON`)*

Commit 3 body bullet: **`Diagnose <qv'2> and apply realizability to the moisture fluxes`**

### The gap

The moist system solves a 4x4 for `(u'qv', v'qv', w'qv', qv'thetav')`. It carries **no
`<qv'^2>`**, so the moisture fluxes were the only moments in the scheme under no
realizability constraint of any kind — there was nothing to bound them against, and the
implied correlation `<w'qv'>/sqrt(<w'^2><qv'^2>)` could exceed one with nothing in the
code noticing. Meanwhile `x(4) = <qv' thetav'>` was solved for and then **discarded**.

### `<qv'^2>` does not need a 5x5 system

The steady `<qv'^2>` budget is the exact analogue of the `<thetav'^2>` equation already
carried as row 10 of `Fill_in_a_matrix`:

```
<u_j' qv'> dQv/dx_j  +  q <qv'^2> / (b_2 l)  =  0
```

As a fifth row it would read `(dQv/dx, dQv/dy, dQv/dz, 0, q/(b_2 l))` with a zero right
hand side — and **no other row has an entry in the `<qv'^2>` column**, because the
buoyancy term in the `<w'qv'>` equation goes through `<qv' thetav'>`, which is already
column 4. The 5x5 is block triangular and its first four unknowns are identical to the
4x4 solution. `Calc_qv_variance` therefore solves it in closed form:

```fortran
tf_qv2 = - (b_2 * l / q) * (dqv_dx*tf_uqv + dqv_dy*tf_vqv + dqv_dz*tf_wqv)
```

This is algebraically exact, costs nothing, and — unlike enlarging the matrix — cannot
perturb the existing fluxes through `dgesvx`'s equilibration (`FACT = 'E'` rescales rows
and columns, so an extra row would move the computed `x(1:4)` at round-off level for no
benefit).

**Cross-check against the code, not just the derivation:** in the 1D limit
`<w'qv'> = -l q Sh dQv/dz` this reduces to `<qv'^2> = b_2 l^2 Sh (dQv/dz)^2`, which is
exactly the form `diag_th2v_pbl_approx` (line ~2979) already uses for `<thetav'^2>`. The
full-3D and approximate branches therefore agree by construction.

### `Enforce_realizability_moist`

The three constraints the heat side already obeys, applied to the moisture side:

```
1. <qv'^2> >= 0                                       -> Tier 3 bit 32
2. <u_i' qv'>^2 <= <u_i'^2> <qv'^2>   (i = u, v, w)   -> Tier 3 bit 64
3. <qv' thetav'>^2 <= <qv'^2> <thetav'^2>             -> Tier 3 bit 128
```

Constraint 3 is why `tf_qvtv` is now returned from `Solve_turb_system_moist`.

- **Inert in 1D**, like every other Tier 3 step: substituting the gradient-diffusion
  forms turns constraint 2 into a condition on the closure constants alone, which they
  satisfy. It engages where the moisture flux vector and the moisture gradient are
  *misaligned*, i.e. where transport is set by the 3D stress tensor rather than by the
  local gradient. A valley moisture gradient combined with a slope flow is exactly that.
- **One pass, not iterated**, matching step 5 of `Enforce_realizability`, which has the
  same structure for `<thetav'^2>`. `<qv'^2>` is diagnosed *from* the fluxes, so clipping
  one makes it stale — but clipping only ever reduces `|flux|`, so the pass is a
  contraction and cannot introduce a new violation of the bound it just enforced.
- `n_t3_flags` is now `intent(inout)` across the two enforcers and `dg_t3_flags` is set
  once, after both have run. The `wrf_debug` Tier 3 summary reports 8 bins.

### Debugging output

`turb_flux_*` were `r` (restart only), so the SGS fluxes could not be inspected in
`wrfout` at all — this blocked part of the review of `run_u20_l0fix`. Promoted to `rh`:
`turb_flux_w2`, `_uw`, `_vw`, `_wtheta_v`, `_wqv`. `turb_flux_theta2_v` was `-` (written
nowhere) and is now `h`. New history field `pbl3d_qv2`.

The set is chosen so the Cauchy-Schwarz bounds can be checked **directly in the output**:
`(w'qv')^2 <= w'^2 qv'^2` from `TURB_FLUX_WQV`, `TURB_FLUX_W2`, `PBL3D_QV2`.

`turb_flux_utheta_v`, `_vtheta_v`, `_theta2_v` were also added to the `any_pbl3d_used`
package, so they are allocated on the same condition as their siblings rather than
unconditionally. Verified safe: both call sites (`module_first_rk_step_part2.F`,
`start_em.F`) are guarded by `ABS(config_flags%pbl3d_opt) > 0`, which is what already
protects the packaged `turb_flux_*` passed alongside them.

### Verification design

Three runs in `/work/bm1236/b301097/pbl3d_test/`, checked by `check_a4.py`:

| run | sounding | `pbl3d_n_tau_max` | tests |
|---|---|---|---|
| `run_dry` | `qv` identically 0 | 0.53 | **A4 null test** |
| `run_moist` | 8 g/kg surface | 0.53 | A4 active, A1 on |
| `run_a1off` | 8 g/kg surface | 1e6 | A1 off |

The dry sounding is not simply the moist one with `qv` deleted: its `theta` is set to the
moist run's `theta_v`, so **both runs have identical virtual potential temperature
profiles** (matched to 5e-5 K). With `mp_physics = 0` and no radiation `qv` is otherwise a
passive tracer, so the momentum/heat side sees the same problem and any difference is
attributable to moisture alone. Generated by the script embedded in `check_a4.py`'s
header comment; sounding files `input_sounding_dry` / `input_sounding_u20`.

`run_dry` is a hard pass/fail: `PBL3D_QV2`, `TURB_FLUX_WQV` and Tier 3 bits 32/64/128
must all be **exactly** zero.

### Verification result (job 26586607, all three runs `SUCCESS COMPLETE WRF`)

**Null test: PASS.** In `run_dry`, `max|PBL3D_QV2|`, `max|TURB_FLUX_WQV|` and Tier 3 bits
32/64/128 are all **exactly** zero, over every timestep and every rank - while the heat
bit fires 11,749 times through the same diagnostic machinery. The zeros are a physical
null, not a plumbing failure that would report zero regardless.

**Moist: correct magnitude and correlation.**

| | |
|---|---|
| `PBL3D_QV2` median / max | 5.81e-10 / 6.87e-08 kg2 kg-2 (RMS 0.024 / 0.26 g/kg) |
| negative `qv2` in output | 0 |
| `(w'qv')^2 > w'^2 qv'^2` | **0 points** of 920,465 |
| `r = w'qv'/sqrt(w'^2 qv'^2)` | median **+0.455**, range -0.50 .. +0.64 |

The correlation coefficient is the discriminating test. A wrong `b_2 l / q` prefactor
fails visibly in one of two directions: too small a variance pins `r` at exactly +-1 with
the clip doing all the work, too large collapses `r` toward 0. Observed is the 0.3-0.5
band that observations give for boundary-layer moisture flux, with a natural spread and
`|r|` never above 0.64. Predicted from the 1D estimate beforehand: ~0.4.

**The constraint is terrain-selective, exactly as designed.** Activations per grid point
over the 12 post-init frames:

| terrain slope | points | bit 32 | bit 64 | bit 64 rate |
|---|---|---|---|---|
| flat < 1 deg | 10,886,460 | 4 | 12 | 1.1e-6 |
| 1-10 deg | 46,800 | 0 | 1 | 2.1e-5 |
| 10-25 deg | 49,920 | 0 | 10 | 2.0e-4 |
| **steep > 25 deg** | 62,400 | 2 | **19** | **3.0e-4** |

A **270x** higher activation rate on steep terrain than on flat. This is the predicted
behaviour: the bound engages where the moisture flux vector and the moisture gradient go
out of alignment, which is over slopes. In absolute terms it stays rare - a safety net,
not a routine modifier of the fluxes.

---

## Group G — A1: buoyancy limit on the master length scale (`pbl3d_n_tau_max`)
*(2026-07-31; `dyn_em/module_pbl3d_my.F`, `dyn_em/module_pbl3d.F`, `dyn_em/start_em.F`, `Registry/Registry.EM_COMMON`, `run/README.namelist`, `share/module_check_a_mundo.F`)*
*(plus `phys/physics_mmm/sf_sfclayrev.F90` — **submodule, goes in commit 2 as a patch file**, see above)*

Commit 3 body bullet: **`Apply the Deardorff buoyancy limit to l for pbl3d_l_opt=1 (pbl3d_n_tau_max)`**

### Why A1 was reopened

Group F closed A1 as "likely unnecessary" on the strength of an offline regime table
that showed `N·tau` peaking at ~1.0 after the `l0` fix. **That table was built from
consistent `(l, q)` pairs and therefore could not see the failure mode.** The mesoscale
run `run_u20_l0fix` shows it directly: `q` and `l` are computed by independent routes
and nothing couples them.

Domain medians per level, `run_u20_l0fix` at t = 2 h:

| k | z AGL | `l_master` | `q_sq` | `q` | `tau = l/q` | `N·tau` |
|---|---|---|---|---|---|---|
| 4 | 104 m | 16.3 m | 1.9e+00 | 1.37 m/s | 12 s | ~0.1 |
| 12 | 407 m | 25.3 m | 8.6e-01 | 0.93 | 27 s | ~0.3 |
| 16 | 644 m | 27.0 m | 2.5e-03 | 0.050 | 540 s | ~6 |
| 24 | 1405 m | 28.8 m | 1.4e-05 | 0.0038 | 7600 s | ~90 |
| 60 | 11108 m | 30.2 m | 1.0e-05 | 0.0032 | 9400 s | ~110 |

`q_sq` correctly collapses to `Q_SQ_MIN` above the boundary layer. `l` does not: Eq. 71
`l = l0 kappa z / (kappa z + l0)` is purely geometric and asymptotes to `l0` all the way
to the lid. So `tau = l/q` explodes and the algebraic system is solved two orders of
magnitude outside its validity range. Run-wide: median `N·tau` = 76.6 over all points
with `q_sq > Q_SQ_MIN`, but 0.05 restricted to `q_sq > 0.1`.

### The omission

The buoyancy limit is present in every length-scale option **except the default one**:

| `pbl3d_l_opt` | scheme | buoyancy limit |
|---|---|---|
| 1 | MY74 | **none** (until this change) |
| 2 | MYNN / Nakanishi 2001 | `l_f = alpha_2 * q / N`, `alpha_2 = 1.0` |
| 3 | Messinger | `l_d = c_r * q / N`, `c_r = 0.25` |

Two comments in `module_pbl3d_my.F` (the `SK_EPS_MAX` block and the Tier 1 block) already
asserted that `Calc_l_master_algebra` applies `l <= 0.53 q / N`. It did not. Those
comments are now true.

### The change

In `Calc_l_master_algebra`, `pbl3d_l_opt == 1` branch, immediately after Eq. 71:

```fortran
if (dthetav_dz(i, k, j) > 0.0) then
  N = Sqrt (G_OVER_TREF * dthetav_dz(i, k, j))
  l_master(i, k, j) = Min (l_master(i, k, j), N_TAU_MAX * Sqrt (q_sq(i, k, j)) / N)
end if
```

- **Constant.** `N_TAU_MAX` default 0.53 = Deardorff (1980) `l = 0.76 sqrt(e)/N` rewritten
  with `e = q^2/2`. Not invented for this purpose, and it is the value the code's own
  comments already claimed. `alpha_2 = 1.0` from the MYNN branch (issue A2) was the
  alternative; 0.53 is the more defensible published value and A2 is thereby closed too.
- **Placement.** Applied to `l_master` itself, not as a local fix-up inside the solver,
  because in `pbl3d_l_opt = 2` and `3` it is part of how the length scale is *defined*.
  It therefore also reaches `l_dissip`, the dissipation rate, and the WRFlux budget terms,
  consistently.
- **`q_sq` is used as stored** (floored at `Q_SQ_MIN`), not reduced by `q_min` as in the
  `l0` integral. `l` appears as `1/tau = q/l` in `A` and as a divisor in the dissipation,
  so it must stay strictly positive. With `q_min = 3.16e-3` and `N = 0.012` this floors
  `l` at ~0.14 m aloft, giving `tau ~ 45 s` and `N·tau ~ 0.53` instead of ~110.
- **Inert in equilibrium.** Substituting `l = N_TAU_MAX q / N` into the level-2 balance
  `q^2 = b_1 l^2 S^2 (1 - Rif) Sm` gives `b_1 N_TAU_MAX^2 (1-Rif) Sm / Ri = 1`, i.e. it
  only binds above `Ri ~ O(1)` — far beyond the `Ri = 0.195` cutoff where the closure
  already returns no turbulence. It acts **only** where `l` and `q` have genuinely
  decoupled, which is what it is for. This is the argument for why it is a consistency
  constraint rather than a tuning knob.
- **Namelist.** `pbl3d_n_tau_max`, real, single value (not per-domain), default 0.53.
  Validated in `module_check_a_mundo.F`: fatal if `<= 0`, warning if `> 5` (which
  effectively disables it). Documented in `run/README.namelist`.

### Two bugs found alongside

1. **`Calc_l_messinger_master_algebra` computed `N = Sqrt(G_OVER_TREF * dthetav_dz)`
   unguarded.** In unstable or neutral layers the argument is negative and `N` is a NaN;
   `l_d` is then NaN and whether the following `Min` propagates it is processor
   dependent. Guarded with `dthetav_dz > 0`, `l_d = 1e10` otherwise, matching how the
   `pbl3d_l_opt = 2` branch already handles it. Affects `pbl3d_l_opt = 3` only.
2. **`phys/physics_mmm/sf_sfclayrev.F90` — upstream, issue U1 in `KNOWN_ISSUES.md`.**
   Applied the one-line lower-bound guard to all four table lookups
   (`if(nzol .ge. 0 .and. nzol+1 .lt. 1000)`). Carried locally because it has blocked two
   runs; it converts an out-of-bounds read into the analytic fallback the `else` branch
   already exists for, and changes nothing for any in-range value. **Should still be
   reported upstream** — see `KNOWN_ISSUES.md`.
   **This file is inside the `phys/physics_mmm` submodule and cannot be committed to
   this repo.** It is carried as `patches/physics_mmm-sf_sfclayrev-table-lower-bound.patch`
   (commit 2); see the submodule section at the top.

### Verification result (job 26586607; `run_moist` = limit on, `run_a1off` = limit off,
otherwise identical; both `SUCCESS COMPLETE WRF`)

**The limit does exactly what it says.** `|N*tau|` p99 = **0.520** against the cap of
0.53 - the 99th percentile sits on the cap, which is the signature of a limiter that is
binding by design rather than by accident.

| over all points with `q^2 > Q_SQ_MIN` | limit off | limit on |
|---|---|---|
| n | 874,132 | **272,016** |
| median `|N*tau|` | 76.591 | **0.047** |
| p99 `|N*tau|` | 322.455 | **0.520** |
| median `Sk/eps` | 38.238 | **3.378** |
| Tier 1 binds | 72.28% | **4.67%** |
| Tier 2 escalates | 23.90% | **0.35%** |
| median `l` aloft (k>=43) | 44.75 m | **0.135 m** |

**The turbulent core is essentially untouched**, which is the important control:

| over `q^2 > 0.1` | limit off | limit on |
|---|---|---|
| n | 255,945 | 227,127 (-11%) |
| median `|N*tau|` | 0.049 | 0.037 |
| median `Sk/eps` | 3.488 | 3.414 |

Both sit at the homogeneous-shear equilibrium value of 3.3. The limit removes the
pathology without redefining the turbulence.

**Unanticipated: it roughly halves the cost.** 0.372 s/step with the limit against
0.763 s/step without - **2.05x** - each run on 42 dedicated cores throughout. The
mechanism is Tier 2: unbounded `N*tau` gives near-singular matrices, each escalation
costs another `dgesvx`, and escalations fall from 23.90% to 0.35%. The point count above
the TKE floor also drops from 874k to 272k, i.e. **69% fewer solves**, because with a
sane `l` the free atmosphere falls to `Q_SQ_MIN` instead of sitting just above it.
This largely supersedes the "raise the laminar/turbulent gate" idea: those solves are
gone, and the ones that remain are single-pass and well conditioned.

**The one substantive physical change, reported honestly.** The limit does not only act
aloft. Domain-mean `q^2`, limit on / limit off, final frame:

| z AGL | `q^2` on | `q^2` off | ratio | `l` on | `l` off |
|---|---|---|---|---|---|
| 54 m | 1.936 | 2.322 | 0.83 | 10.20 | 11.95 |
| 233 m | 1.378 | 1.850 | 0.74 | 20.63 | 29.29 |
| 516 m | 0.701 | 1.181 | 0.59 | 23.97 | 36.52 |
| 793 m | 0.051 | 0.343 | 0.15 | 1.04 | 39.20 |
| 1405 m | 0.0001 | 0.0084 | 0.01 | 0.15 | 41.67 |

Boundary-layer TKE is 17-41% lower. **This is not the direct buoyancy limit** - at 233 m
the raw `N*tau` is 0.174, well inside the 0.53 cap, so the limit does not bind there. It
is an **indirect effect through `l0`**: with the limit off, the oversized `l` in the
stably stratified free atmosphere *manufactures* turbulence there (`q^2 = 8.4e-3` at
1.4 km, 840x the floor), that spurious turbulence enters the MY74 Eq. 72 column integral,
and the inflated `l0` raises `l` throughout the column including inside the boundary
layer. A1 cuts it off at the source.

**So A1 and A0 interact**, and the interaction is the larger effect. The direction is
defensible - the scheme should not generate turbulence in a `Ri -> infinity` free
atmosphere, and `l0` is meant to measure the depth of the *turbulent* layer - but whether
the resulting 17-41% reduction in boundary-layer TKE is a correction or an over-correction
**cannot be settled by this run**. It needs an LES or observational reference.
Logged as the top open question.

---

## Group F — Remaining open items worked through after E
*(2026-07-30; `dyn_em/module_pbl3d_my.F`, `dyn_em/module_pbl3d.F`, `dyn_em/start_em.F`, `Registry/Registry.EM_COMMON`, `run/README.namelist`, `share/module_check_a_mundo.F`)*

Commit 3 body bullet: **`Fix l_dissip in the 1D q^2 closure, expose the Tier 1 tolerance, document dead stability functions`**

### First, re-measured Tier 1/2/3 activation now that `l0` is fixed

3000 random 3D strain tensors per regime, `l` and `q` from the post-E regime table,
`|S|` and `dthetav_dz` set per regime:

| regime | `Sk/eps` | `N·tau` | T1 binds | T2 fires | mean steps | **T3 zeroes `w'2`** | median `cond(A)` |
|---|---|---|---|---|---|---|---|
| nocturnal SBL | 6.16 | 0.60 | 100% | 37.7% | 0.38 | **0.0%** | 1.7e1 |
| valley cold pool | 1.56 | 0.96 | 0% | 0.0% | 0.00 | **0.0%** | 1.1e1 |
| slope drainage | 23.2 | 1.06 | 100% | 43.9% | 0.44 | **0.0%** | 2.2e1 |
| residual / LLJ | 14.8 | 0.83 | 100% | 41.5% | 0.42 | **0.0%** | 5.5e1 |
| CBL capping inv | 3.96 | 0.63 | 0% | 13.4% | 0.13 | **0.0%** | 3.1e1 |
| CBL mixed layer | 2.77 | −0.33 | 0% | **68.9%** | 0.92 | **0.0%** | 4.2e2 |

Median `cond(A)` is now 11–420, against 1e5–1e8 before E. Two consequences:

- **D1 is closed by E.** Tier 3 drives `w'2` to zero at **0.0%** of points in every
  regime, against the ~16% estimated pre-E. The patchiness concern is gone, and
  Tier 3 is now a genuine last resort rather than a routine occurrence.
- **`COND_MAX` is deliberately not exposed** (see C2 below): eight orders of
  margin means there is nothing to scan.

New finding logged: **the convective mixed layer is now the worst regime for
Tier 2** (68.9%, 0.92 extra solves). Tier 1 does not bind there (`Sk/eps` = 2.77),
and the unrealizability comes from the buoyancy coupling in the *unstable*
direction — the `(w'thetav', thetav'^2)` 2x2 has determinant
`q^2/(3 a_2 b_2 l^2) + N^2`, which vanishes at `|N| tau = 1/sqrt(3 a_2 b_2) = 0.21`
when `N^2 < 0`. **No length-scale limit can address this**, because a buoyancy
limit is undefined for `N^2 < 0` (the code sets `l_b = 1e10` there). It is Tier 2
and Tier 3's job, and they are handling it. Not actionable without a different
mechanism.

### B2 — `l_dissip` was passed in and never used

The 1D level 2 balance is `Sm q l S^2 (1 - Rif) = q^3/(b_1 l_dissip)`, so

    q^2 = b_1 * l_dissip * l_master * S^2 * (1 - Rif) * Sm

The two length scales are **not the same one**: the production side carries the
mixing length, the dissipation side carries `l_dissip`, which is exactly what
`Fill_dissip_length_scale` is called to supply. Both `Calc_q_sq_l2_pbl_approx` and
the 1D fallback added in group B used `l_master ** 2.0` for both, so `l_dissip` was
computed, passed in, and referenced only inside a disabled debug print. Fixed in
both places so they stay bit-identical to each other.

Identical for `pbl3d_l_opt < 3` (where `l_dissip == l_master`); changes results only
for `pbl3d_l_opt >= 3`, where `l_dissip` is the BouLac length. Previously deferred
to protect the validated approximate baseline — that argument no longer applies,
since group E already changes that baseline substantially and this affects a
non-default `l_opt` only.

### C1 — documented, not changed

`sm`, `sh`, `sm_l2`, `sh_l2` and `q_ratio` are returned to `Calc_fluxes` and never
read. This is **not** a missing realizability constraint and must not be wired in:
stability functions are how the *approximate* closure forms its fluxes, whereas the
full 3D path forms them by solving the 10x10 system, so there is no place for an
`Sm` or an `Sh` in it. HL88 is the level 2.5 realizability limiter for the stability
function formulation; its full 3D counterpart is `Enforce_realizability`.

Left in place rather than special cased: the wasted work is one 3D sweep of a few
tens of flops per point against two dense linear solves per point — well under 1%
of the scheme — and the same prep routines are shared with
`Calc_fluxes_pbl_approx`, where `sm` and `sh` are live. A comment now records this
so a future reader does not "fix" it. Note that group B made `sm`/`sm_l2` partly
live again: `Calc_q_sq_l2` consumes them for its 1D fallback.

### C2 — `SK_EPS_MAX` exposed, `COND_MAX` not

`SK_EPS_MAX` changed from a `parameter` to a namelist-set module variable, following
the existing `Q_SQ_MIN` / `TURB_FLUX_MIN` convention in this file. Justified by the
measurement: it binds at **100% of points** in the nocturnal SBL, slope drainage and
LLJ regimes, so it is the active control on `l` in exactly the regimes of interest,
and 6.0 is deliberately ~2x the homogeneous-shear equilibrium value of 3.3.

Threaded through the init path (`start_em.F` -> `Init_pbl3d` ->
`Set_init_turb_state_driver` -> `Set_init_turb_state_my`) rather than assigned inside
`Calc_fluxes`, which would be an OpenMP write race on a module variable for no
benefit. Guarded at `<= 0` in both `check_a_mundo` (fatal) and the setter (falls back
to 6.0 with a warning), because at or below zero Tier 1 would force `l -> 0` and the
closure would silently return isotropic turbulence everywhere.

`N_PSD_BISECT`, `L_BACKOFF` and `MAX_SOLVE_ATTEMPTS` remain compiled in — they have
no business being user facing.

| new option | default | scope |
|---|---|---|
| `pbl3d_sk_eps_max` | 6.0 | domain-independent (`1`, not `max_domains`); used only by `pbl3d_opt = 2` |

---

## Group E — Fix `l0` so it is set by the turbulence, not by the model lid
*(2026-07-30; `dyn_em/module_pbl3d_my.F`, `Registry/Registry.EM_COMMON`, `run/README.namelist`, `share/module_check_a_mundo.F`, `OPEN_ISSUES.md`)*

Commit 3 body bullet: **`Stop the Q_SQ_MIN floor from dominating the MY74 l0 integral`**

MY74 Eq. 72 gives the asymptotic length scale as the q-weighted mean height of
the turbulence. `Calc_l_master_algebra` and `Calc_l_messinger_master_algebra`
both integrate it over the **whole column** weighting by `q = Sqrt(q_sq)` — but
`q_sq` is floored at `Q_SQ_MIN = 1e-5`, so every quiescent free-atmosphere level
contributes `q_min = 3.16e-3` instead of nothing. The numerator then grows like
`H^2` while the denominator grows like `H`, giving

    l0  ->  alpha * H / 2

Verified exactly: a column carrying nothing but the floor yields `l0` =
250 / 500 / 1000 / 1500 m for model tops of 5 / 10 / 20 / 30 km. **The boundary
layer length scale was set by where the model lid is.** MY74's integral converges
because `q -> 0` above the turbulence; the numerical floor destroys that.

Confirmed against the reference implementation: MYNN in this same tree
(`phys/module_bl_mynnedmf.F:1661`) carries the comment
`!originally integrated to model top, not just pblh.` — integrating to the top
*was* the original MY behaviour, and MYNN fixed it. MYNN also subtracts the floor
from the weight (`qdz = MAX(qkw(k)-qmin, 0.03)*dzk`) and caps the result at
`elt_max = 400 m`. This code was written from MY74 Eq. 71/72 directly
(`alpha = 0.1`, versus MYNN's `alp1 = 0.23`) and never inherited the correction.

Why it survived: `Q_SQ_MIN` is set in a different routine; `1e-5` looks
negligible but `Sqrt(1e-5) = 3.2e-3` is not, and it accumulates over ~20 km; and
it is **invisible in a shallow domain** — at a 2 km top `l0 = 31 m`, entirely
plausible. Development and testing were at LES scale (see item 2 further down),
which is exactly the blind spot. It never crashes.

Magnitude (20 km top, `alpha = 0.1`, stretched 60 level column):

| regime | `l0` before | `l0` after | `N*tau` before | `N*tau` after |
|---|---|---|---|---|
| nocturnal SBL (h=100 m) | 802 m | 3.5 m | 3.95 | 0.60 |
| valley cold pool (h=50 m) | 962 m | 1.7 m | **6.33** | 0.94 |
| shallow stable (h=30 m) | 987 m | 1.0 m | **6.82** | 1.00 |
| residual layer (h=600 m) | 378 m | 20.7 m | 4.25 | 0.83 |
| CBL + capping inversion | 122 m | 34.6 m | 1.83 | 0.63 |

Median `cond(A)` grows roughly as `(N*tau)^3` and crosses `COND_MAX = 1e8` near
`N*tau = 5`, so **cold pools and shallow stable layers were failing `solve_ok`,
exhausting all six Tier 2 escalations and returning the isotropic fallback**
`u'2 = v'2 = w'2 = q^2/3` with every covariance zero.

Fix: weight by `Max(q - q_min, 0)`. Chosen over MYNN's `pblh`-truncation on
purpose — `pblh` is ill posed over complex terrain and a single truncation height
would cut off elevated turbulent layers (cold pool top, foehn shear layer). The
excess weighting is local, needs no PBL depth, and includes every genuinely
turbulent layer weighted by its own `q`. Tested for continuity: as an SBL top
sweeps across a grid level the largest step in `l0` is 0.027 m, against 0.049 m
for a hard `q > q_min` mask and 1.0 m for the previous code.

MYNN's `elt_max` cap was **not** adopted: with the fix `l0` comes out at 1–35 m in
every regime tested, far below 400 m, so the cap would be inactive, and its value
is calibrated for MYNN's `alp1 = 0.23` rather than MY74's `alpha = 0.1`.

New namelist option, default **1**:

| `pbl3d_l0_opt` | behaviour |
|---|---|
| `1` (default) | weight by `Max(q - q_min, 0)` |
| `0` | legacy whole-column `q` weighting; `l0` depends on the model top |

**Cost, and it is real.** `l0` feeds `pbl3d_l_opt = 1`, `2` and `>= 4`, and both
routines serve the approximate *and* full-3D paths. This changes the validated
`pbl3d_opt = +-1` baseline: `l` drops by a factor 3–7 in stable conditions and
about 3 in the CBL (92 m -> 32 m at the capping inversion). Expect a visibly
shallower PBL and stronger nocturnal inversions in the approximate configuration
too. Any tuning previously done against this behaviour was tuning against a lid
artefact. `pbl3d_l0_opt = 0` reproduces the old results in the same executable.

~~**Supersedes A1** (buoyancy limit on `l`): after this fix `N*tau` peaks at ~1.0,
which is where a limiter with `alpha_2 = 1.0` would cap it, so the limiter would
barely bind. The large `N*tau` values that motivated A1 were a symptom of this
bug. A1 and A2 are both closed as unnecessary unless a run says otherwise.~~

> **Retracted by group G.** This paragraph was wrong, and the reason is worth
> keeping: the offline table it rests on was built from *consistent* `(l, q)` pairs,
> so it could not represent the actual failure mode, which is `l` and `q` being
> computed by independent routes and decoupling. `run_u20_l0fix` measured a median
> `N*tau` of 76.6, not 1.0. E and G address different halves of the same problem and
> **both are needed** — G's verification section quantifies how strongly they
> interact.

**Suggested empirical check on a real domain.** `l_master` is a Registry state
variable and is written to output. In a nocturnal column, at 2–5 km AGL where
`kappa z >> l0` so `l_master -> l0`, compare `pbl3d_l0_opt = 0` against `1`: the
first should show O(800–900 m), the second a few metres. One short run, no code
change, and it confirms or refutes the whole diagnosis on the actual grid and
vertical levels.

---

## Group A — Tier 0–3 solvability and realizability safeguards for `pbl3d_opt=2`
*(2026-07-28; `dyn_em/module_pbl3d_my.F`, `OPEN_ISSUES.md`)*

Commit 3 body bullet: **`Add solvability and realizability safeguards to the full-3D closure`**

All changes are inside `Diagnose_fluxes` / `Solve_turb_system` /
`Solve_turb_system_moist`, reached only from `Calc_fluxes`, i.e. only when
`pbl3d_opt == 2`. The approximate branch is bit-for-bit unchanged.

| tier | change | why |
|---|---|---|
| 0 | `dgesvx` `FACT='N'` → `'E'`; `info` actually checked; `iwork` typed `integer` | `A`'s columns carry mixed units so the raw system is badly scaled by construction; `info` in `[1,N]` means `X` was never computed, so the old code used uninitialised memory |
| 1 | Durbin (1996) strain limit `l <= (2·SK_EPS_MAX/b_1)·q/|S|`, always on | keeps the closure inside its own stated validity range; no-op at equilibrium |
| 2 | escalate (halve `l`, retry) while the solve is degenerate **or** the stress tensor is not positive semi-definite | every step returns an *exact* solution of the closure at shorter `l`; a singular `A` is rare (~0.005%) but an unrealizable solution is common (6–40%) |
| 3 | `Enforce_realizability`: variance floor, exact trace identity, Cauchy–Schwarz, and a new determinant-based common-factor covariance shrink | completes Sylvester's criterion — pairwise Cauchy–Schwarz alone is necessary but not sufficient |

New: `pure logical function Is_realizable` (full Sylvester PSD test, used as the
Tier 2 acceptance test); parameters `SK_EPS_MAX=6.0`, `COND_MAX=1.0E8`,
`L_BACKOFF=0.5`, `MAX_SOLVE_ATTEMPTS=6`, `N_PSD_BISECT=20`; `wrf_debug(100,…)`
reporting of escalation counts.

Also fixed here: `l_use` is only halved when another attempt follows, so on
exhaustion it still describes the state actually returned — which matters because
Tier 3's trace target and the whole moisture solve consume it.

Verification: 200 000 adversarial random states, Fortran expressions transcribed
verbatim and run in the code's actual order — `Is_realizable` vs a true PSD test
0/200000 disagreements; tensor still non-PSD after steps 3+4 0/200000; step 4
broke a Cauchy–Schwarz bound 0/200000.

~~**Not validated by any model run.**~~ Superseded: job 26586607 exercises all four
tiers. Tier 1 binds at 4.67% of points and Tier 2 escalates at 0.35% with the
group G limit on (72.28% / 23.90% with it off), and the Tier 3 heat bit fires
11,749 times in `run_dry` alone. See the group G and group H verification sections.

---

## Group B — Self-consistent `q²` for the full-3D closure, `pbl3d_qsq_opt`
*(2026-07-30; `dyn_em/module_pbl3d_my.F`, `Registry/Registry.EM_COMMON`, `run/README.namelist`, `share/module_check_a_mundo.F`, `OPEN_ISSUES.md`)*

Commit 3 body bullet: **`Close q^2 on the full 3D production and add pbl3d_qsq_opt`**

`q` sets every diagonal entry of `A` and hence the relaxation time
`tau = l/q` that decides whether the 10×10 system is diagonally dominant. It was
being supplied by a **1D** closure (`q² = b_1 l² (du/dz² + dv/dz²) (1−Rif) Sm`)
that cannot see the anisotropy the system exists to represent. The author's
self-consistent alternative closes the same level-2 balance on the full 3D
production, evaluated with the stress tensor the system itself returned — but it
was commented out as "unstable".

Three defects found and fixed in that dead code:

1. **It never took the cube root.** `q = q ** 1./3.` parses as `(q**1.0)/3.0`,
   because Fortran binds `**` tighter than `/`. The variable held
   `b_1·l·production`, dimensionally `q³`, so `q_sq = q*q` evaluated to
   `q_true⁶/9`. Now `q_sq = max(q_cubed, 0)**(2.0/3.0)` in one step. Every other
   cube root in the file is correctly parenthesised, so this was a typo.
2. **Negative production → NaN.** The 3D production is nine shear terms plus
   buoyancy and can go negative; the only guard is the *1D* `rif < rif_c`, which
   cannot know its sign. A negative base with a real exponent is a NaN, so fixing
   (1) alone would have traded a blow-up for a NaN. Hence the `max(…, 0)`.
3. **Cold-start dead-lock** (new finding, not in the author's comment).
   `q²` is diagnosed *from* the fluxes and the fluxes *from* `q²`, both
   initialised at their floors, with no independent source in the cycle — level 2
   could never spin up. Now falls back on the 1D local-equilibrium value wherever
   the 3D estimate does not clear `Q_SQ_MIN`, written to agree bit-for-bit with
   `Calc_q_sq_l2_pbl_approx`. Never fires in a spun-up boundary layer.

`Calc_q_sq_l2` now also uses `l_dissip` rather than `l_master` for the
dissipation length scale, which is what `Fill_dissip_length_scale` computes it
for. `sm` added as an argument (needed by the fallback).

New namelist option, `namelist,dynamics`, `max_domains`, default **1**:

| `pbl3d_qsq_opt` | behaviour |
|---|---|
| `1` (default) | self-consistent full-3D production |
| `0` | legacy 1D surrogate, for testing and bisecting |

Only read on the `pbl3d_opt = 2` path, and **only consequential for
`pbl3d_prog = 0`**: for `pbl3d_prog > 0` the branches differ only in
`q_sq_hl88`, which feeds the HL88 limiter on `sm`/`sh`, and `sm`/`sh` are never
read on the full-3D path. `module_check_a_mundo.F` validates the range and warns
when `pbl3d_qsq_opt=0` is combined with `pbl3d_opt=2`.

---

## Group C — Audit fixes
*(2026-07-30; `dyn_em/module_pbl3d_my.F`)*

Commit 3 body bullet: **`Fix uninitialised l_boulac and per-gridpoint heap allocation`**

1. **`l_boulac` read uninitialised in the default configuration.**
   `Calc_l_master_algebra` declares it `intent(out)` but only assigned it in the
   `pbl3d_l_opt == 2` branch, then read it unconditionally at
   `l_boulac(i,kte,j) = l_boulac(i,ktf,j)`. `pbl3d_l_opt = 1` is the Registry
   default, so **every default run read uninitialised memory**, and
   `Make_scale_aware` then multiplied it into a state array that is written to
   output. Now set to `l_master` on that branch — MY74 makes no distinction
   between the mixing and the dissipation length scale.
2. **Per-gridpoint heap allocation.** `Solve_turb_system` and
   `Solve_turb_system_moist` did `allocate`/`deallocate` of `a`, `af`, `b`, `x`
   on every grid point every timestep — 4 mallocs + 4 frees per point. `N_VARS`
   is a `parameter`, so these are now fixed-size locals. Behaviour-identical.
3. Removed the unused `iter` in `Calc_fluxes` and the uninitialised `ri` read in
   `Calc_q_sq_l2`'s debug block.

---

## Group D — Robustness cleanups (zero result change)
*(2026-07-30; `dyn_em/module_pbl3d_my.F`, `dyn_em/module_pbl3d.F`)*

Commit 3 body bullet: **`Close latent traps in the 3D PBL scheme`**

Agreed as batch "all five" on 2026-07-30. None changes results today.

| id | site | change |
|---|---|---|
| B1 | `Calc_sm_sh_l2_or_l2p5` | `write(90,*)` NaN diagnostic → `wrf_debug(100,…)`. Unit 90 is **never opened**: gfortran auto-creates `fort.90`, every MPI rank targets the same name, and there is no frequency limit, so one NaN field could fill the run directory mid-run. |
| B3 | `Calc_q_sq_rhs` (`module_pbl3d.F`) | `intent(out)` → `intent(in)` on `turb_flux_u2 … wtheta_v`, which are only ever read. Worked only because the actual arguments are contiguous full arrays. |
| B4 | `Calc_fluxes` | `q_sq == Q_SQ_MIN` → `<= Q_SQ_MIN`. Exact float equality as the no-turbulence flag would silently stop firing after any refactor reaching the floor by another route. |
| B5 | both `Prep_for_fluxes_l2p5*` | Removed the `use_hl88` local `parameter`. Fixed at `.true.` with no else branch; flipping it would have left `rif`, `sm_l2`, `sh_l2`, `q_sq_hl88` undefined while still passing all four to a routine that reads them. There is no defined physics for "HL88 off", so the flag is removed rather than given an invented meaning. Also removed a dead `use_hl88` declaration in `Calc_fluxes`. |
| C3 | `Set_init_turb_state_my` | `l_master` and `l_master_at_mass` were seeded with `Q_SQ_MIN`, a TKE floor in m²s⁻², into a length. Now seeded with `dz`. Overwritten before first read, so this fixes units only. |

---

## Still open — decided against, or not yet decided

Full pros/cons in `OPEN_ISSUES.md`. Status as of 2026-07-31.

### The top open question

**Is the 17–41% reduction in boundary-layer `q^2` a correction or an
over-correction?** Group G's verification shows A1 and A0 interact, and that the
interaction — spurious free-atmosphere turbulence inflating `l0` and therefore `l`
throughout the column — is a larger effect than the buoyancy limit acting directly.
The *direction* is defensible on physical grounds. The *magnitude* cannot be settled
by any run in this series, because both configurations are the same model. It needs
an **LES or observational reference**. Nothing else on this list blocks progress the
way this does.

### Issue table

| id | item | status |
|---|---|---|
| ~~A0~~ | `l0` is set by the model top, not the turbulence (`l0 -> alpha*H/2`; 802 m in a nocturnal SBL where the turbulence supports 3.5 m) | **DONE in group E** — weight the Eq. 72 integral by `Max(q - q_min, 0)`; `pbl3d_l0_opt` |
| ~~A1~~ | buoyancy limit `l <= N_TAU_MAX q/N` for `pbl3d_l_opt=1` | **DONE in group G.** Reopened by `run_u20_l0fix`: the offline table that closed it used consistent `(l,q)` pairs and could not see local `l`–`q` decoupling |
| ~~A2~~ | choice of the constant | **closed by group G** — 0.53 (Deardorff 1980), not the MYNN `alpha_2 = 1.0` |
| A3 | `q_sq`/`l_master` updated in sequence, not iterated as a fixed point | **open, and more relevant than before** — group G makes `l` an explicit function of `q`, so the two are now directly coupled rather than merely both stale |
| ~~A4~~ | no `qv'^2`, so no realizability constraint of any kind on the moisture fluxes | **DONE in group H.** Closed form, not a 5x5 — the `qv'^2` column is empty so the extended system is block triangular |
| ~~B2~~ | `Calc_q_sq_l2_pbl_approx` ignores its `l_dissip` argument | **DONE in group F.** The deferral argument ("protect the validated baseline") lapsed once group E changed that baseline anyway |
| ~~C2~~ | solver tunables are compile-time `parameter`s | **partly done.** `SK_EPS_MAX` exposed as `pbl3d_sk_eps_max` in group F, `N_TAU_MAX` as `pbl3d_n_tau_max` in group G. `COND_MAX`, `L_BACKOFF`, `MAX_SOLVE_ATTEMPTS`, `N_PSD_BISECT` deliberately left compiled in |
| ~~D1~~ | Tier 3 drives `w'^2` to zero at ~16% of points in strong strain, patchy in space | **closed by group E's measurement.** Re-measured at **0.0%** in all six regimes once `cond(A)` fell from 1e5–1e8 to 11–420 |
| C1 | `sm`/`sh`/`rif`/`q_sq_hl88`/`q_ratio` computed in `Calc_fluxes` and never read | **documented in group F, deliberately not changed.** Not a missing constraint — there is no place for a stability function on the full-3D path. Comment added so it is not "fixed" later |
| C4 | the init block in `Set_init_turb_state_my` is commented out and would not compile as written | deferred |
| F1 | convective mixed layer is now the worst regime for Tier 2 (68.9%, 0.92 extra solves) — the `(w'thetav', thetav'^2)` 2x2 determinant vanishes at `\|N\|tau = 0.21` when `N^2 < 0` | **not actionable by any length-scale limit** (a buoyancy limit is undefined for `N^2 < 0`). Tier 2/3 are handling it |
| U1 | `sf_sfclayrev` table lookup has no lower bound — segfaults | patched locally, **not reported upstream yet** |

### Not yet tested at all

- **A nocturnal / cold-pool case.** This is where the original problem lives and
  where groups E and G should matter most. Everything verified so far is a daytime
  convective `em_les` run.
- **Real terrain.** The Inn Valley target. Group J's mountain reaches 35° but is a
  single idealized cosine bell. **`realcase/` now holds the complete setup for
  this** — ICON-forced, 500 m, 2025-07-18, paired against MYNN. See
  `realcase/README.md`; nothing has been run yet.
- **`pbl3d_l_opt = 3` (Messinger).** Group F's `l_dissip` fix and group G's NaN guard
  both change this path and neither has been run.

---

## Verification state

| | |
|---|---|
| build | `./clean` + `./compile em_les`, 2026-07-31 10:27 — `Executables successfully built`, 0 compile errors. (The earlier `em_real` build of 2026-07-30 10:57 covered groups A–F; executables saved at `/work/bm1236/b301097/pbl3d_test/em_real_exe/`.) |
| toolchain | `gcc/11.2.0-gcc-11.2.0`, `openmpi/4.1.2-gcc-11.2.0`, `netcdf-c/4.8.1-openmpi-4.1.2-gcc-11.2.0`, `netcdf-fortran/4.5.3-openmpi-4.1.2-gcc-11.2.0` (resolves to `netcdf-fortran-4.5.3-jlxcfz`, matching `configure.wrf`) |
| contamination | zero gcc-12/mambaforge objects across `dyn_em`/`frame`/`share`/`phys`/`main` |
| offline numerics | group A verified on 200 000 adversarial states; A-matrix trace identity to 7e-14 |
| **model run** | **job 26586607**, three `em_les` runs (`run_dry`, `run_moist`, `run_a1off`), all `SUCCESS COMPLETE WRF`, 5400/5400 steps, 13 frames each. Results in the group G and group H sections. |

`configure.wrf` currently carries `-DMTN` and is set up for `em_les`; backups at
`configure.wrf.em_les_backup` and `configure.wrf.em_real_backup`. Neither is tracked
and neither should be committed.

### Build gotchas

Moved to `KNOWN_ISSUES.md` (sections E1-E5, G1-G3), which also tracks the upstream
`sf_sfclayrev` segfault found during the 35 deg terrain runs. Summary:

- `module load` must be **redirected**, never piped — piping runs it in a
  subshell and silently discards it, after which `mpif90` resolves to mambaforge
  gcc 12 and the link fails with `EXIT=0` and no executables.
- Do not wait on the build with `pgrep -f "compile em_real"`: the monitor's own
  command line contains that string, so it self-matches and never sees the
  process exit. Key on `Executables successfully built` in the log instead.
- `git` is not on the default `PATH` here:
  `export PATH=/sw/spack-levante/git-2.43.7-2ofazl/bin:$PATH`

---

## Committed history (for reference)

```
da0c5ef88  Document horizontal SGS flux completion and diagnose the full-3D instability
cd1cb48e2  Wire pbl3d's native turbulent fluxes into WRFlux's horizontal SGS budget
b5d1ad7ab  Document WRFlux integration progress and validation in OPEN_ISSUES.md
5462557ea  Fix mass-point/w-level mismatch in pbl3d-to-WRFlux vertical flux code
f51607318  Wire pbl3d's native turbulent fluxes into WRFlux's vertical SGS budget
8c3195c98  Fix missing doing_q_sq argument in dry-theta advect_scalar call
```
