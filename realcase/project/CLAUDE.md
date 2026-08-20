# Project instructions — Inn Valley ICON-forced WRF-3DPBL on VSC-5

You are picking up an operational WRF setup that spent 2026-08-19 on **MUSICA**
(Innsbruck) and moved **back here** the same day, because MUSICA's queue starved
(a single user held 626 concurrent jobs; our account is forced to exclusive whole
nodes and so could not use the fragments). Nothing about the science or the build
failed there — the move is purely about queue access.

## How to report back

- **Physics first.** Lead with what a number means for the flow — eddy size,
  dissipation rate, wind speed, stratification. Numerics matter only through
  their effect on a physical quantity; name that effect.
- **Define every variable on first use in an answer**: full name, what it
  physically is, units. Not "`q_sq` rose" but "`q_sq` — twice the turbulence
  kinetic energy, m² s⁻² — rose".
- **Concise.** Answer what was asked; offer detail rather than dumping it.
- **No internal labels in output.** Commit-group letters, internal change
  numbering, agent names — keep them in the repo, name a change by what it does.
- **Separate measured from inferred.** State which is which, and retract a
  number the moment its method fails a sanity check.

## Read these first, in this order

0. **`HANDOVER_2026-08-20.md`** — current state. The 3D closure now completes a
   real-terrain run; what was fixed, what is still open, and five corrections to
   the earlier record. **Start here.**
1. **`HANDOVER_MUSICA_TO_VSC5.md`** — what was learned, what is ruled out, what
   to do next. Written for whoever picks this up.
2. `DECISIONS.md` — why non-obvious science/config choices were made. **Append to
   it in the same turn as the work**, newest first.
3. `branko/OPEN_ISSUES.md` **section A9** — the diagnosis of the current blowup.
4. `branko/KNOWN_ISSUES.md` **U2, E11, E12, E13** — the traps that cost time.
5. `ARCHITECTURE.md`, then `branko/realcase/README.md` (the authoritative
   build/run guide) and `CHANGES.md`.

`MIGRATION_MUSICA.md` is now history — read it only for how the data was moved.

## The immediate task

The `pbl3d_opt=2` runaway is **fixed** — job 8476273 completed the first
real-terrain run of the full 3D closure. The problem now is the opposite one: the
closure carries far too little turbulence energy. Twice the turbulence kinetic
energy (`q_sq`, m² s⁻²) in the lowest ~100 m sits at 0.085 against the MYNN
control's 0.316, still rising after an hour, with the energy-containing eddies
0.42 m across at 85 m above ground against the control's 6.7 m.

**Read `HANDOVER_2026-08-20.md` and the top entry of `DECISIONS.md`.** They carry
the mechanism (every bound on the eddy size scales with the turbulence velocity,
the run cold-starts at the floor), the two default-off fixes, the six 6 h
experiments and the decision rule for adopting them.

### Do NOT

- **Do not apply U2's index guard as "the fix".** It converts a loud, perfectly
  deterministic crash into a NaN propagating silently through the radiative
  tendency. It should land *after* the blowup is understood, never as the thing
  that resolves it.
- **Do not treat `pbl3d_opt=1` as the production answer.** It is the diagnostic.
  The whole point of this configuration is the full 3D closure.
- **Do not set `ra_lw_physics=0` to get the run through.** Longwave cooling is
  part of the cold-pool mechanism under study.
- **Do not re-test what is already excluded** (see A9 and the handover): terrain,
  dx=500 m, `time_step=2`, `epssm=0.9`, ICON forcing, Thompson/RRTMG/Noah-MP, the
  `dgesvx` solve, `hybrid_opt=0`, `diff_opt=0`.
- **Do not run more than one experiment with the same `WRF_OUTPUT_ROOT`** — use
  `realcase/env/vsc5_X<n>.sh`. Concurrent runs otherwise clobber each other's
  `temp/branko/wrfout_d01_<date>.nc` live, mid-run.

## A rebuild is mandatory after any Registry change

The five q² terms were promoted `r` → `rh` in `Registry/Registry.EM_COMMON`
(commit `b7b2c76ae`) so they reach `wrfout`. **Use `--reconfigure`:**

```bash
cd /gpfs/data/fs72996/ewahl/branko
realcase/scripts/build_em_real.sh realcase/env/vsc5.sh --reconfigure
```

Only `./clean -a` (which `--reconfigure` triggers) removes the generated
`Registry/Registry` and `inc/*.inc`. A plain `./clean` keeps them, and a stale
registry produces a binary that builds, runs, and writes an output stream with
the new fields **silently missing** — the same quiet-wrong failure mode as
`SMOIS`. ~30-60 min; run under `tmux`.

Keep `WRF_BUILD_JOBS=1`. `./compile -j N` **races** — WRF's own `phys/`
dependency graph is incomplete, and a race can compile against a half-written
`.mod` and yield a subtly wrong binary, which would corrupt exactly the evidence
being gathered. See `KNOWN_ISSUES.md` E12; never resume a raced build without
`./clean`. `build_em_real.sh` does not trust `./compile`'s exit code — **trust
its verdict**, not the return status.

## Working here

- `$DATA` = `/gpfs/data/fs72996/ewahl` = the project root. `branko/` is the WRF
  fork (branch `3dpbl_wrflux_v4.8.0`); `branko_runs/` holds run directories.
- The project docs are version-controlled at `branko/realcase/project/` because
  `$DATA` is not a git repo. **Edit the copy in the project root, then sync it
  back** to `realcase/project/` and commit, or the next migration loses it.
- **Push to GitHub works from here** (SSH remote, `gh` is installed at
  `~/bin/gh`) — unlike MUSICA, where the HTTPS clone had no credentials and the
  work was nearly stranded on one disk. Commit and push anything you care about.

## This cluster

- Account `p72996`; partition `zen3_0512`, QOS `zen3_0512` (MaxWall 3 days).
  Devel is a **QOS**, `zen3_0512_devel`: MaxWall 00:10:00, 5 nodes.
- 638 nodes × **128 physical cores** (8 sockets × 16, `ThreadsPerCore=2`, so
  SLURM reports `CPUTot=256`), 500 GB. Use `--hint=nomultithread`.
- Toolchain: Spack, gcc 12.2.0 + OpenMPI 4.1, sourced by `realcase/env/vsc5.sh`.
  Note the env ends up with **both** `openmpi/4.1.6` (explicit) and
  `openmpi/4.1.4` (pulled in as a dependency); 4.1.4 wins on `PATH`. Left alone
  deliberately — 4.1.x is ABI-stable and this is the env that produced working
  binaries. See `DECISIONS.md`.
- `module purge` at the top of `vsc5.sh` is fine here. (The "never `module
  purge`" rule was MUSICA-specific: it stripped EESSI's `MODULEPATH`.) The EESSI
  `set +u` workaround is likewise MUSICA-only.
- `check_wrfinput.py` and `prepare_namelist.py` run in the **same** environment
  as the build — `python/3.9.15` and `py-netcdf4/1.5.8` are loaded by `vsc5.sh`,
  and `ncdump` comes with `netcdf-c`. No separate shell, unlike MUSICA.

**Do NOT carry over from MUSICA**: 190 cores/node, `--qos=zen4_0768`, account
`p201110`, the `dev_zen4_0768` QOS, or MUSICA's 1.26 s/step sizing. Re-measure
throughput with a `--smoke` run; `submit_wrf.slurm` prints mean s/step at the end.

## Output layout — do not let this drift

One variable, `WRF_OUTPUT_ROOT` (set in the env file to `/gpfs/data/fs72996/ewahl`).
Everything below it is fixed and identical on every cluster:

| | |
|---|---|
| `$WRF_OUTPUT_ROOT/temp/branko/wrfout_d<domain>_<date>.nc` | history |
| `$WRF_OUTPUT_ROOT/temp/branko/meanout_d<domain>_<date>.nc` | `auxhist24`, WRFlux averages |
| `$WRF_OUTPUT_ROOT/temp/branko/qsqdiag_d<domain>_<date>.nc` | `auxhist23`, q² budget (`--qsq-diag`) |
| `$WRF_OUTPUT_ROOT/wrf_output/<jobid>/` | archive, written by `submit_wrf.slurm` |

Both live streams use `frames_per_outfile = 1`. **If you find yourself editing
`history_outname` by hand, that is the bug** — set `WRF_OUTPUT_ROOT` instead. The
templates carry an `@OUTPUT_ROOT@` token that `prepare_namelist.py --output-root`
expands; an unexpanded token is FATAL by design.

`namelist.input.mynn` is a known, deliberate exception: relative
`auxhist24_outname`, no `history_outname`, so the MYNN control writes into its own
run directory. `prepare_namelist.py` warns. Left alone so as not to strand
post-processing that expects it there — change it on purpose or not at all.

## Things that will cost you a day if you get them wrong

- **The one check to actually read** is `check_wrfinput.py`'s `SMOIS` range: must
  be **0.02–0.6**, not 1–100. ICON's `W_SO` is a mass (kg m⁻²), WRF's `SMOIS` a
  volumetric fraction. Wrong, and the soil is saturated everywhere, the Bowen
  ratio collapses, the daytime heating that erodes the cold pool never happens —
  and the run completes and is wrong. The conversion lives in `icon2wrf`; fix it
  there, not downstream. (The script asserts `0 ≤ SMOIS ≤ 1`; a max of exactly
  1.000 is the water-body fill value, not a bug. A healthy run here: mean 0.284.)
- **Check a reused run dir for dangling symlinks**: `find <rundir> -maxdepth 1
  -xtype l`. They are invisible to `real.exe` and only fail deep inside `wrf.exe`
  (KNOWN_ISSUES E11). `setup_rundir.sh` now checks automatically and prints the
  `rm` lines — but it cannot remove them for you.
- **`module load` must be redirected, never piped** (KNOWN_ISSUES E1).
- **Do not poll the build with `pgrep -f "compile em_real"`** — the poller's own
  command line self-matches and it never sees the process exit (E2).
- **Check rsync/pipeline exit codes properly.** `$?` after a pipeline reads the
  *last* command; a leg once transferred nothing while reporting `rc=0`.
- `fg_name` must not contain `'PRES'` — ICON carries pressure natively, so
  `calc_ecmwf_p.exe` never runs and `metgrid.exe` aborts on the missing files.
- **An unknown variable in an `iofields` file is a WARNING, not an abort.** Grep
  `rsl.error.0000` for `W A R N I N G` the first time you use one, or you get an
  empty stream and no error. Also: a blank line **ends** parsing of that file.

## Open items carried over

- The shared `data/WRF/run/wrfinput_d01`/`wrfbdy_d01` were overwritten by
  branko's first `real.exe` run (stale symlinks, since removed) and never
  restored. Still open; see `DECISIONS.md`.
- **MUSICA job 89435 may still be queued there.** Cancel it (`scancel 89435`)
  from a MUSICA session so it does not run unattended — it cannot be cancelled
  from VSC-5.
- U2 should be reported upstream to `wrf-model/WRF`, as should U1, which is still
  carried locally and unreported.
- Science caveats: read *Known unknowns* in `realcase/README.md` before
  interpreting any output. This is the first real-terrain and first
  nocturnal/cold-pool run of this scheme, and the magnitude of the boundary-layer
  q² reduction is unresolved.
