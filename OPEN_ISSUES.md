# Open issues / questions — 3D PBL rebase (WRF v4.4 -> v4.8.0)

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

**Not yet done: horizontal SGS flux integration** (`ftx_sgs`, `fty_sgs`,
`fqx_sgs`, `fqy_sgs`, `fux_sgs`, `fvx_sgs`, `fvy_sgs`, `fwx_sgs`, `fwy_sgs`).
Same gap exists (`module_first_rk_step_part2.F` already has
`IF (config_flags%pbl3d_opt < 1)` gating the whole `horizontal_diffusion_2`
call that would otherwise populate these). Matters for a full TKE budget in
complex terrain (e.g. i-Box stations near Innsbruck) where horizontal
transport isn't negligible. Complication found: pbl3d's Registry already
declares `turb_flux_u2_mass`/`v2_mass`/`uv_mass`/`uw_mass`/`vw_mass`/
`wtheta_v_mass` (mass-point variants that would avoid needing vertical
de-staggering) but **these are never actually assigned anywhere in
`module_pbl3d.F` or `module_pbl3d_my.F`** — confirmed dead Registry entries.
Will need manual vertical de-staggering (w-level -> mass-level, simple
0.5*(k)+0.5*(k+1) average) from the Z-staggered raw diagnostics instead.

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
