# Open issues / questions — 3D PBL rebase (WRF v4.4 -> v4.8.0)

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
