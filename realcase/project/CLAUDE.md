# Project instructions — Inn Valley ICON-forced WRF with the 3D Mellor–Yamada closure (VSC-5)

`$DATA` = `/gpfs/data/fs72996/ewahl` is the project root; `branko/` is the WRF fork
(branch `3dpbl_wrflux_v4.8.0`, SSH remote, `gh` at `~/bin/gh` — commit and push
anything you care about); `branko_runs/` holds run directories; `exp/X<n>/` holds
per-experiment output roots. The project docs live in the root and are
version-controlled as a copy at `branko/realcase/project/` — **edit the root copy,
sync it back, commit.** (`MIGRATION_MUSICA.md` and `HANDOVER_MUSICA_TO_VSC5.md` are
history; nothing in them applies here except the data layout.)

## Who you are working with, and how to report

Elias is an atmospheric scientist, fluent in turbulence closures; he wants the
**mechanism**, not the process, and he notices diff size.

- **Physics first.** Lead with what a number means for the flow — eddy size,
  dissipation rate, wind speed, stratification. Numerics matter only through
  their effect on a physical quantity; name that effect.
- **Define every variable on first use**: full name, what it physically is,
  units — "`q_sq`, twice the turbulence kinetic energy, m² s⁻²".
- **Concise; tables for comparisons.** Answer what was asked; offer detail.
- **Separate measured from inferred**, and retract a number the moment its
  method fails a sanity check. Record retractions, do not quietly drop them.
- **No internal labels in prose** (commit-group letters, "Tier 1", "X2", agent
  names). Name a change by what it does; issue numbers only as pointers.
- **State the behavioural footprint first** for any code change: what changes by
  default (ideally nothing) versus what is opt-in.

## How work is done here (learned 2026-08-20/21)

1. **Plan → soundness review → approval → implement.** Before proposing a fix,
   check it against the closure's own assumptions *and* against archived data;
   one of four proposed fixes was withdrawn that way (a "balance limiter" aimed
   at cells that the data showed were not the problem). He will ask for this
   check if you skip it.
2. **Every new switch defaults to the previous behaviour, bit for bit.** A rebuilt
   binary must reproduce the last good run exactly before anything else is
   trusted; one rewritten single-precision factor was enough to break that once.
3. **Validate the binary on the devel QOS first** (`zen3_0512_devel`, 10 min,
   ≤5 nodes, starts within minutes): a 12-minute run from the standard `wrfinput`
   shows whether new fields are written and finite. The bit-for-bit check needs
   the *same* MPI layout as the reference (2 nodes × 128 here).
4. **Compare runs statistically, never cell by cell** — slope × height bins,
   Ri bins, floor fractions, medians. The configuration is not bit-reproducible
   across decompositions or after any last-bit change (`KNOWN_ISSUES.md` E14).
5. **Record in the same turn**: `DECISIONS.md` (newest first, why), the handover
   (state), `OPEN_ISSUES.md` (defects), `KNOWN_ISSUES.md` (traps). Sync, commit, push.
6. **Delegation when asked**: mechanical chores and scripts → a sonnet worker;
   writing the record → an opus worker with the numbers in the prompt; source
   edits, builds and physics judgement stay with you.
7. **Queue reality**: priority estimates say days; backfill starts 2-node jobs
   within hours. A shorter wall time is the only lever (`scontrol update
   JobId=… TimeLimit=…`). Hold pending jobs during a rebuild (E16).

## Read these first, in this order

0. **`HANDOVER_2026-08-20.md`** — current state; the 2026-08-21 evening update at
   the top carries the pairing result. **Start here.**
1. `DECISIONS.md` — the three 2026-08-21 entries, then the 2026-08-20 ones.
2. `branko/OPEN_ISSUES.md` **A10** (slope-factor pairing, fixed), **A11**
   (bootstrap trap — real, not the lever), **A12** (morning runaway, diagnosed).
3. `branko/KNOWN_ISSUES.md` **U2, E11–E17** — the traps that cost time.
4. `ARCHITECTURE.md`, `branko/realcase/README.md` (build/run guide), `CHANGES.md`.

## Where the science stands (2026-08-21) and the standing rules

- The nocturnal runaway is fixed (one master length scale, `db3b9176c`).
- **The turbulence deficit against the MYNN control is the closure's
  stable-regime equilibrium, not spin-up or bootstrap**: it is flat above
  Ri ≈ 0.3, where 69 % of the nocturnal valley cells sit, and absent in neutral
  and unstable air. **MYNN is the control, not the truth** — it over-mixes at
  night and under-forecasts the valley wind. **Rule: no change to constants, the
  buoyancy-limit coefficient or the strain cap before a full 23 h run is held
  against the TEAMx observations** (`$DATA/TEAMx_sEOP_IOP17`, `…IOP18-20`).
- **Slope-factor energy pairing — fixed and validated (2026-08-21).** ~90 % of the
  horizontal-pairing shear production (a third of all production, essentially all
  on slopes) was never paid by the resolved flow. `pbl3d_sf_pair` (Registry
  default 0, **template now 1**) credits q² only with what the slope-tapered
  tendency extracts: the energy residual falls from +14…+37 % to **+0.3 %**, and
  nocturnal q² halves (0.33 → 0.17 of MYNN at 04:00, uniform across slope bins —
  the slope structure *was* the spurious source).
- **Morning runaway (A12) — diagnosed: the same defect.** A 1-minute budget from a
  04:00 restart shows the terminal ridge-top cluster fed 77–164 % by horizontal
  pairing with only 6–10 % paid; the strain cap holding l ∝ q at P/ε ≈ 2 is the
  amplifier, not the source. With the fix the run reaches **07:00 complete**, the
  first one ever and as far as anything is tested.
- **Retracted**: the slope-dependent 10 m wind bias is *not* a q² effect (halving
  q² left it unchanged to 0.01 m/s); cause unknown. Unexamined: 3D is +2.4…+3.9 m/s
  faster at 10 m at 07:00 on every slope class, with 0.4–0.5 of MYNN's q² aloft.
- **The strain cap (`pbl3d_sk_eps_max = 6`) is load-bearing**: 12 or off brings the
  nocturnal runaway back within 45 min. The asymptotic-length floor (`pbl3d_l0_min`),
  the equilibrium start (`pbl3d_init_opt`) and the Ri-aware cap
  (`pbl3d_limiter_opt=2`) stay default-off: the first two buy 2–4 % of q², the
  third is unrun.

### Do NOT

- Apply U2's index guard as "the fix" (it turns a loud crash into a silent NaN).
- Treat `pbl3d_opt=1` as the production answer — it is the diagnostic.
- Set `ra_lw_physics=0` to get a run through — longwave cooling is the mechanism.
- Re-test what is excluded (A9, handover): terrain, dx=500 m, `time_step=2`,
  `epssm=0.9`, ICON forcing, Thompson/RRTMG/Noah-MP, the `dgesvx` solve,
  `hybrid_opt=0`, `diff_opt=0`.
- Loosen `pbl3d_sk_eps_max` above 6, or tune the stable regime before the 23 h
  run is held against the TEAMx observations.
- Add an output stream to a restart run without `override_restart_timers=.true.`
  — it never opens, silently, and the run's wall time is wasted (E17).
- Run more than one experiment with the same `WRF_OUTPUT_ROOT` (they clobber each
  other live in `temp/branko/`) — one env file per run → `exp/X<n>`.
- Compare two runs cell by cell (E14).
- Start a rebuild with jobs pending that link `main/wrf.exe` (E16).
- Set `auxhist24_interval = 0` to silence the WRFlux stream — fatal at start
  (E15); use 360 min.

## Tools that exist — use them rather than rewriting

- `realcase/scripts/setup_experiments_20260820.sh [--only X6] [--submit]` —
  builds the X-run dirs (per-run output root, 2 nodes, thinned history, WRFlux
  stream at 6 h) from `namelist.input.pbl3d`; table of runs in its header.
- `realcase/scripts/compare_mynn.py` — `slope`, `spinup`, `lscale`, `t1`, `cap`,
  and `exp --runs NAME=DIR … --mynn-dir … --times …` (slope × height bins, wind
  bias, length scales, limiter footprint, energy-closure residual, `--csv`).
- `realcase/scripts/setup_rundir.sh <env> <rundir> pbl3d --met-dir … --hours N
  [--smoke] [--qsq-diag]`; `prepare_namelist.py` validates every `pbl3d_*` key.
- `realcase/iofields_lscale.txt` (stream 0 additions), `iofields_a12.txt` (+ the
  1-minute stream 23). No blank lines in an iofields file; an unknown name is
  only a WARNING — grep `rsl.error.0000` for `W A R N I N G`.
- MYNN control: job 8320565, `wrf_output/8320565/`, 01:00 start, 30-min frames.
  3D runs: `exp/X0..X5/wrf_output/`; compare against 8478327 (`exp/X6/…`, paired,
  01:00→07:00 complete), not the older ones.

## A rebuild is mandatory after any Registry change

```bash
cd /gpfs/data/fs72996/ewahl/branko
realcase/scripts/build_em_real.sh realcase/env/vsc5.sh --reconfigure   # 30-40 min
```

Only `./clean -a` (which `--reconfigure` triggers) regenerates the Registry and
`inc/*.inc`; a stale registry builds and runs with new fields **silently missing**.
Keep `WRF_BUILD_JOBS=1` — `-j N` races (E12). Trust the script's verdict, then
`ldd` with the env sourced, then the devel-QOS smoke. For a source-only change:
`source realcase/env/vsc5.sh && ./compile -j 1 em_real` (~12 min; relinks).
`tmux` is not available in this session type — use `nohup … &` and a monitor
keyed on the script's PID (not on `pgrep -f "compile em_real"`, E2).

## This cluster

- Account `p72996`; partition `zen3_0512`, QOS `zen3_0512` (MaxWall 3 days);
  devel QOS `zen3_0512_devel` (10 min, 5 nodes). `zen3_1024`/`zen3_2048` are also
  allowed but no less loaded. 128 physical cores/node; use `--hint=nomultithread`.
- Toolchain: Spack gcc 12.2.0 + OpenMPI 4.1 via `realcase/env/vsc5.sh` (`module
  purge` is fine here); python + netCDF4 + `ncdump` come with it. Two OpenMPI
  versions land on `PATH`; 4.1.4 wins; left alone deliberately.
- Sizing measured: **1.5 s/step on 2 nodes × 128** (6 h = 10 800 steps ≈ 5 h
  wall; request 5:30), 0.65 s/step on 5 nodes. A 6.4 GB history frame every
  30 min; the WRFlux frame is 12.6 GB — budget disk, the filesystem runs >80 %.

## Output layout — do not let this drift

One variable, `WRF_OUTPUT_ROOT`; everything below it is fixed:
`temp/branko/wrfout_d<domain>_<date>.nc` (history), `…/meanout_…` (`auxhist24`,
WRFlux averages), `…/qsqdiag_…` (`auxhist23`, 1-min budget), and
`wrf_output/<jobid>/` (archive, written by `submit_wrf.slurm` even on failure).
**If you are editing `history_outname` by hand, that is the bug** — set
`WRF_OUTPUT_ROOT` in the env file. `namelist.input.mynn` is the one deliberate
exception (writes into its run dir).

## Things that cost a day if wrong

- `check_wrfinput.py`'s `SMOIS` range must be **0.02–0.6** (ICON `W_SO` is a mass,
  WRF `SMOIS` a volume fraction; fix in `icon2wrf`, not downstream). Healthy mean 0.284.
- Dangling symlinks in a reused run dir (`find <rundir> -maxdepth 1 -xtype l`)
  fail only deep inside `wrf.exe` (E11); pass `--met-dir` as an absolute path.
- `module load` redirected, never piped (E1); `$?` after a pipeline is the last
  command's; `fg_name` must not contain `'PRES'`.
- A restart file (`restart_interval=180`) is the cheap way to re-enter a run just
  before an event on the same layout — the blow-up reproduces there.

## Open items carried over

- The shared `data/WRF/run/wrfinput_d01`/`wrfbdy_d01` were overwritten by
  branko's first `real.exe` run and never restored (see `DECISIONS.md`).
- MUSICA job 89435 may still be queued there; cancel from a MUSICA session.
- U1 and U2 should be reported upstream to `wrf-model/WRF`.
- *Known unknowns* in `realcase/README.md` apply to every interpretation: first
  real-terrain, first nocturnal cold-pool run of this scheme.
