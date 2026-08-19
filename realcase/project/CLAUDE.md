# Project instructions — Inn Valley ICON-forced WRF-3DPBL on MUSICA

You are picking up an operational WRF setup migrated here from **VSC-5** on
2026-08-19, because that cluster became unavailable mid-campaign. Everything is
in place and verified. **The model has not been built here yet** — that is the
next action.

## Read these first, in this order

1. **`MIGRATION_MUSICA.md`** — what moved, what did not, the resume sequence.
2. `ARCHITECTURE.md` — project layout and the ICON→WRF forcing chain.
3. `DECISIONS.md` — why non-obvious science/config choices were made. **Append to
   it in the same turn as the work**, newest first.
4. `branko/realcase/README.md` — the authoritative build/run guide. Also
   `CHANGES.md`, `KNOWN_ISSUES.md`, `OPEN_ISSUES.md` in `branko/`.

## Working here

- `$DATA` = `/data/fs201110/ew24501` = this directory. Aliases `data` and
  `scratch` jump to `$DATA` / `$SCRATCH` (defined in `~/.bashrc.d/user-aliases`).
- `$SCRATCH` is only 500 GB and purgeable — **never put run output there.**
- Claude Code lives in the conda env `claude`
  (`miniforge3/envs/claude`, Claude Code 2.1.235). Relaunch with
  `./start_claude.sh` from this directory.
- `miniforge3/` in this directory is that install. It is tooling, not project
  data — do not treat it as something to preserve or migrate.

## The immediate task

Resume the 24 h production run that was stuck in the VSC-5 queue (job `8464723`,
`wrf_innval_pbl3d_18th`): 601×501×80 at dx=500 m, `time_step=2`, 2025-07-18
**01:00** → 07-19 00:00 UTC (`run_hours=23`), hourly ICON forcing,
`num_metgrid_levels=12`, `num_metgrid_soil_levels=8`, `pbl3d` config.

Those values differ from the template defaults in `realcase/README.md` (which
says 00:00, `e_vert=81`, `dt=3`) — the run's values came from the ICON namelist
and are deliberate.

**A rebuild is mandatory.** MUSICA is zen4 with an entirely different toolchain;
no VSC-5 binary is valid. `branko/` is a fresh clone with no stale objects.

```bash
cd /data/fs201110/ew24501/branko
realcase/scripts/build_em_real.sh realcase/env/musica.sh --reconfigure
```

Roughly an hour. Run it under `tmux` — do not let it die with your session.

Then set up a run directory and **smoke-test first**:

```bash
realcase/scripts/setup_rundir.sh realcase/env/musica.sh \
    /data/fs201110/ew24501/branko_runs/innval_pbl3d_smoke pbl3d \
    --geo /data/fs201110/ew24501/WPS/geogrid_smoothed_output/geo_em.d01.nc \
    --met-dir /data/fs201110/ew24501/WPS/metgrid_output --smoke
```

One MUSICA node is 192 cores — roughly the entire 2-node/200-task job VSC-5 was
running — so **the old sizing does not transfer**. `submit_wrf.slurm` prints mean
s/step at the end; size `--nodes`/`--time` from that, not from a guess.

## What is already verified (do not redo this work)

Checked on this machine on 2026-08-19, not assumed:

- **`realcase/env/musica.sh` needs no edits.** Every value probed here.
  `WRF_CONFIGURE_OPTION=34` was read off `./configure`'s own menu (the only
  gfortran/dmpar entry). `dgesvx` was compiled, linked **and run** against
  FlexiBLAS, returning the correct solution — the 3D PBL closure calls it at
  every grid point, so this was the riskiest unknown.
- **Submodules are correct.** `git submodule status` shows `c5b6dbc` (noahmp) and
  `7071724` (physics_mmm); `NoahmpReadTableMod.F90` has `MVT = 33`.
- **Data is complete.** 89 GB, every leg re-checked with `rsync -an` reporting 0
  differences. `geo_em.d01.nc`, `wrfinput_d01`, `wrfbdy_d01` byte sizes match
  VSC-5 exactly; 48/48 `met_em`; 24+24 `icon2wrf` in/out.

What is **not** verified: nothing has been compiled or run. The build, `real.exe`,
and `wrf.exe` are all untried here.

## Output layout — do not let this drift

One variable, `WRF_OUTPUT_ROOT` (set in the env file to `/data/fs201110/ew24501`).
Everything below it is fixed and identical on every cluster:

| | |
|---|---|
| `$WRF_OUTPUT_ROOT/temp/branko/wrfout_d<domain>_<date>.nc` | history |
| `$WRF_OUTPUT_ROOT/temp/branko/meanout_d<domain>_<date>.nc` | `auxhist24`, WRFlux averages |
| `$WRF_OUTPUT_ROOT/wrf_output/<jobid>/` | archive, written by `submit_wrf.slurm` |

Both live streams use `frames_per_outfile = 1`. **If you find yourself editing
`history_outname` by hand, that is the bug** — set `WRF_OUTPUT_ROOT` instead. The
templates carry an `@OUTPUT_ROOT@` token that `prepare_namelist.py --output-root`
expands; an unexpanded token is FATAL by design.

`namelist.input.mynn` is a known, deliberate exception: relative
`auxhist24_outname`, no `history_outname`, so the MYNN control writes into its own
run directory. `prepare_namelist.py` warns. Left alone so as not to strand
post-processing that expects it there — change it on purpose or not at all.

## This cluster

- Account `p201110`; partition `zen4_0768`, devel `dev_zen4_0768` (smoke tests there)
- 45 nodes × 192 **physical** cores (SLURM reports 384; `ThreadsPerCore=2`), 770 GB
- `zen4_0768` has `MaxTime=UNLIMITED`, 1-day default — unlike VSC-5, the 24 h run
  does not need chaining across a queue limit
- EESSI 2025.06, toolchain `gompi-2024a` (GCC 13.3.0 + OpenMPI 5.0.3)

## You cannot push to GitHub from here — read this before committing

`branko/` and `icon2wrf/` are cloned over **HTTPS with no credentials**, and `gh`
is not installed on MUSICA. Pull works; **push fails**. Any commit you make is
local-only until you fix that.

This matters more than it sounds: the migration was nearly blocked because two
submodule commits existed on exactly one disk and could not be cloned anywhere.
Do not recreate that situation. Either set up push before committing anything you
care about, or treat this checkout as read-only.

To enable push, install `gh` (single static binary, no root):

```bash
V=2.97.0
curl -sSL -o /tmp/gh.tgz https://github.com/cli/cli/releases/download/v${V}/gh_${V}_linux_amd64.tar.gz
tar xzf /tmp/gh.tgz -C /tmp && install -m755 /tmp/gh_${V}_linux_amd64/bin/gh ~/bin/gh
gh auth login --hostname github.com --git-protocol https --web
```

The device flow prints a code and a URL — the **user** must complete it in a
browser. Alternatively switch the remote to SSH and register a MUSICA key with
GitHub. Outbound HTTPS to github.com and registry.npmjs.org both work from here.

## Things that will cost you a day if you get them wrong

- **The one check to actually read** is `check_wrfinput.py`'s `SMOIS` range: must
  be **0.02–0.6**, not 1–100. ICON's `W_SO` is a mass (kg m⁻²), WRF's `SMOIS` a
  volumetric fraction. Wrong, and the soil is saturated everywhere, the Bowen
  ratio collapses, the daytime heating that erodes the cold pool never happens —
  and the run completes and is wrong. The conversion lives in `icon2wrf`; fix it
  there, not downstream. It needs its own shell:
  `module load netcdf4-python/1.7.2-foss-2025a` after the EESSI init, since those
  bindings only exist for `foss-2025a` and would conflict with the build toolchain.
- **Do not `module purge` after the EESSI init** in the env file — it strips
  `MODULEPATH` and every subsequent load fails silently.
- **`module load` must be redirected, never piped** (KNOWN_ISSUES E1).
- **Do not poll the build with `pgrep -f "compile em_real"`** — the poller's own
  command line self-matches and it never sees the process exit.
- **`./compile` returns 0 even when it produced nothing.** `build_em_real.sh`
  checks for `Executables successfully built` plus an actual stat of the
  binaries, and screens for mixed-GCC and conda libraries. Trust it, not the
  exit code.
- **Check rsync/pipeline exit codes properly.** During the migration a leg
  silently transferred nothing while reporting `rc=0`, because `$?` was reading a
  trailing `grep` in the pipeline. Also: rsync 3.1.3 creates only one missing
  directory level (`--mkpath` needs 3.2.3).
- `fg_name` must not contain `'PRES'` — ICON carries pressure natively, so
  `calc_ecmwf_p.exe` never runs and `metgrid.exe` aborts on the missing files.

## Open items carried over

- The shared `data/WRF/run/wrfinput_d01`/`wrfbdy_d01` on VSC-5 were overwritten
  by branko's first `real.exe` run (stale symlinks, since removed) and never
  restored. Still open; see `DECISIONS.md`.
- **`ARCHITECTURE.md` still describes VSC-5** in its title and "Cluster notes"
  section. Update it for MUSICA once the build works, and keep it short per its
  own header.
- Science caveats are unchanged by the move: read *Known unknowns* in
  `realcase/README.md` before interpreting any output. This is the first
  real-terrain and first nocturnal/cold-pool run of this scheme, and the
  magnitude of the boundary-layer `q²` reduction is unresolved.

## `real.exe`, and the VSC-5 fallback

`branko_runs/innval_pbl3d_18th/` carries `wrfinput_d01` (2.7 G) and `wrfbdy_d01`
(4.5 G) produced on VSC-5. They are plain NetCDF and portable, so they *can* be
reused — but re-running `real.exe` after the rebuild is the safer default. If you
do reuse them, run `check_wrfinput.py` on them first. That directory's symlinks
point back into the VSC-5 tree and dangle: recreate run dirs with
`setup_rundir.sh` rather than repairing them.

VSC-5 still holds the originals at `/gpfs/data/fs72996/ewahl` and is the fallback
if something here turns out to be missing. Note there is **no automated link from
MUSICA back to VSC-5** — the transfer ran the other direction, pushed from VSC-5
over an SSH ControlMaster socket. MUSICA is certificate-only for inbound SSH and
`authorized_keys` is refused there, so re-establishing a link means working from
the VSC-5 side again.
