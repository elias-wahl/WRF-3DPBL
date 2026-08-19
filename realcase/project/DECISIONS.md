# Decisions log

Append-only, newest first. One entry per judgment call on this project's
science/config setup — not process fixes (those go in the assistant's
lessons file) and not things `branko/realcase/README.md`,
`CHANGES.md`, or `OPEN_ISSUES.md` already document in depth.

---

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
