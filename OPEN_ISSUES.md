# Open issues / questions — 3D PBL rebase (WRF v4.4 -> v4.8.0)

## MAIN PROBLEM: full-3D (pbl3d_opt=2) closure has no realizability safeguard
(investigated 2026-07-28, not yet fixed)

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
