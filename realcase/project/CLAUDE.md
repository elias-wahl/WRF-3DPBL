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
   **And the cards**: new mechanisms, terms, variables, equations and traps of the
   session go into `$DATA/wrf-turbulence-cards/cards/*.md` (3–10 cards, `S:` = the
   DECISIONS/KNOWN_ISSUES entry), commit + push there — the Action rebuilds the Anki
   deck (`releases/tag/latest`, AnkiDroid). Repo: github.com/elias-wahl/wrf-turbulence-cards.
6. **Delegation when asked**: mechanical chores and scripts → a sonnet worker;
   writing the record → an opus worker with the numbers in the prompt; source
   edits, builds and physics judgement stay with you.
7. **Queue reality**: priority estimates say days; backfill starts 2-node jobs
   within hours. A shorter wall time is the only lever (`scontrol update
   JobId=… TimeLimit=…`). Hold pending jobs during a rebuild (E16).
8. **Automation survives only inside SLURM.** Background monitors die with the
   session (three restarts on 2026-08-21). Chain runs with
   `sbatch --dependency=afterok:<jobid>`; first action of every session is
   `squeue -u $USER` + re-arming monitors on whatever is pending. Automatic
   follow-on runs are allowed once a quality gate is written down
   (`DECISIONS.md` 2026-08-21 22:30: X8 behind X7).
9. **Impossible budget term ⇒ raw arrays first** (E18): a short-wave *cooling*
   in the WRFlux θ budget was a −9999 albedo (U3), found in an hour from the
   restart file after a day of physics hypotheses.

## Read these first, in this order

0. **`HANDOVER_2026-08-20.md`** — current state; the **2026-08-22 session-end block at the
   top** (segmented 23 h run in flight, what X7 showed), then the 2026-08-21 night block
   (the albedo bug and what it retracts). **Start here.**
1. `DECISIONS.md` — the 2026-08-22 entries (17:45 sfclay bounds measured, 21:25 morning
   clean, 22:20 convective partition, 22:40/22:55 segmented run), then 2026-08-21 22:15.
2. `branko/OPEN_ISSUES.md` **A10** (slope-factor pairing, fixed), **A11**
   (bootstrap trap — real, not the lever), **A12/A13** (the morning — closed/withdrawn, U3).
3. `branko/KNOWN_ISSUES.md` **U2, U3, E11–E19** — the traps that cost time (E19: the
   restart tool's template values).
4. `ARCHITECTURE.md`, `branko/realcase/README.md` (build/run guide), `CHANGES.md`.

## Where the science stands (2026-08-22) and the standing rules

- The nocturnal runaway is fixed (one master length scale, `db3b9176c`).
- **The turbulence deficit against the MYNN control is the closure's
  stable-regime equilibrium, not spin-up or bootstrap**: it is flat above
  Ri ≈ 0.3, where 69 % of the nocturnal valley cells sit, and absent in neutral
  and unstable air. **MYNN is the control, not the truth** — it over-mixes at
  night and under-forecasts the valley wind. **Rule: no change to constants, the
  buoyancy-limit coefficient or the strain cap before a full 23 h run is held
  against observations** — but `$DATA/TEAMx_sEOP_*` holds **ECMWF analyses (GRIB)**;
  station observations for the IOPs are **not** on disk — ask for them.
- **Slope-factor energy pairing — fixed and validated (2026-08-21).** ~90 % of the
  horizontal-pairing shear production (a third of all production, essentially all
  on slopes) was never paid by the resolved flow. `pbl3d_sf_pair` (Registry default
  0, **template now 1**) credits q² only with what the slope-tapered tendency
  extracts: residual +14…+37 % → **+0.3 %**, nocturnal q² halves (0.33 → 0.17 of
  MYNN at 04:00, flat across slope bins — that structure *was* the spurious source).
- **The morning failures were a WRF bug, not the closure** (`KNOWN_ISSUES.md` **U3**,
  22:15 entry of `DECISIONS.md`): the 4.8 Noah-MP driver hands radiation its
  undefined albedo (−9999) wherever the surface gets no direct beam, so with
  `topo_shading=1` RRTMG-SW cools the shaded terrain at **−80 K/h** at the ground
  (9.3 % of the domain at 07:00). The fog, the −11 K cold bias, the drainage jets,
  the 07:54 collapse and the +3 m/s 10 m wind excess are downstream of it and are
  **withdrawn as closure physics**; guarded in `1fc2fa464` (no switch; night
  unaffected). **Confirmed by X7 (job 8483386, 01:00→10:00, 2026-08-22): the
  morning is clean** — past the old 07:54:30 crash point, no negative albedo, one
  cold cell, no drainage jets, T2 within 0.2 K of MYNN in every terrain class.
  Also retracted: the slope-dependent 10 m wind bias is not a q² effect (halving
  q² left it unchanged to 0.01 m/s); cause unknown.
- **Convective regime (new, 2026-08-22 22:20): the subgrid q² ratio to MYNN of 0.28
  in the morning mixed layer is a grey-zone partition, not a deficit** — subgrid +
  resolved kinetic energy is equal to MYNN's (3.9 vs 3.7 m² s⁻² at 43 m), the 3D
  run resolves 85–91 % of it, its mixed layer is deeper (820 vs 631 m) and its
  heat flux larger. **This does not rescue the nocturnal 0.16** — no resolved
  turbulence at 500 m in stable air. Compare subgrid *and* resolved TKE in
  unstable air, never subgrid alone.
- **The surface-layer bounds (`sfclay_ust_min = 0.03`, `sfclay_zol_max = 10`) are
  in the production namelist**; the u* floor is active in 18 % of land cells at
  night with no footprint in HFX, T2 or any q² bin (measured 2026-08-22) — but it
  makes X7/X8 not bit-comparable with X6; compare statistically.
- **The 23 h run is a chain of restart segments** (X7 01→10, X8a 10→16, X8b 16→22,
  X8c 22→00; `exp/X7`, `exp/X8a|b|c`), chained inside SLURM by
  `chain_segment.slurm` — ≤ 5:30 h 2-node jobs start within minutes here, an
  18 h job waits days. **WRFlux means at 30 min from now on** (Elias 2026-08-22);
  the 6-h X8 job is cancelled automatically once X8a is submitted.
- **The strain cap (`pbl3d_sk_eps_max = 6`) is load-bearing**: 12 or off brings the
  nocturnal runaway back within 45 min. The asymptotic-length floor (`pbl3d_l0_min`),
  the equilibrium start (`pbl3d_init_opt`) and the Ri-aware cap
  (`pbl3d_limiter_opt=2`) stay default-off: the first two buy 2–4 % of q², third unrun.

### Do NOT

- Apply U2's index guard as "the fix" (it turns a loud crash into a silent NaN).
- Treat `pbl3d_opt=1` as the production answer — it is the diagnostic.
- Set `ra_lw_physics=0` to get a run through — longwave cooling is the mechanism.
- Re-test what is excluded (A9, handover): terrain, dx=500 m, `time_step=2`,
  `epssm=0.9`, ICON forcing, Thompson/RRTMG/Noah-MP, the `dgesvx` solve,
  `hybrid_opt=0`, `diff_opt=0`.
- Interpret any morning (post-04:00) result of a run built before `1fc2fa464` as
  closure physics — it is U3's radiation (this includes every X-run and the MYNN
  control's inert topographic shading).
- Loosen `pbl3d_sk_eps_max` above 6, or tune the stable regime before the 23 h
  run is held against observations.
- Add an output stream to a restart run without `override_restart_timers=.true.`
  — it never opens, silently, and the run's wall time is wasted (E17).
- Run more than one experiment with the same `WRF_OUTPUT_ROOT` (they clobber each
  other live in `temp/branko/`) — one env file per run → `exp/X<n>`.
- Compare two runs cell by cell (E14).
- Build a continuation with `setup_restart_run.sh` without
  `--set restart_interval=180 --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0` and a
  namelist diff against the parent run (E19) — `chain_segment.slurm` does this.
- Judge the convective regime by subgrid q² alone (see the partition result).
- Start a rebuild with jobs pending that link `main/wrf.exe` (E16).
- Set `auxhist24_interval = 0` to silence the WRFlux stream — fatal at start
  (E15); use 360 min.

## Tools that exist — use them rather than rewriting

- `realcase/scripts/setup_experiments_20260820.sh [--only X6] [--submit]` —
  builds the X-run dirs (per-run output root, 2 nodes, thinned history, WRFlux
  stream at 6 h) from `namelist.input.pbl3d`; table of runs in its header.
- `realcase/scripts/compare_mynn.py` — `slope`, `spinup`, `lscale`, `t1`, `cap`,
  `exp --runs NAME=DIR … --mynn-dir … --times …` (slope × height bins, wind
  bias, length scales, limiter footprint, energy-closure residual, `--csv`), and
  `fog` (low cloud, cold cells, insolation, drainage — the morning gate).
- `realcase/scripts/setup_rundir.sh <env> <rundir> pbl3d --met-dir … --hours N
  [--smoke] [--qsq-diag]`; `prepare_namelist.py` validates every `pbl3d_*` key.
- `realcase/scripts/setup_restart_run.sh <NAME> --rst <wrfrst> --start HH
  --hours H [--minutes M] [--stream23-min N] [--iofields F] [--set key=val]
  [--qos devel] [--submit]` — restart-based diagnosis/continuation runs (sets
  `override_restart_timers`, per-run env + output root). Read its header.
- `realcase/scripts/chain_segment.slurm` — SLURM-resident link for restart-segmented
  long runs (reads its header); `gate_x7_to_x8.{slurm,py}` — report-only morning
  checks on a run archive.
- `realcase/iofields_lscale.txt` (stream 0 additions), `iofields_a12.txt` /
  `iofields_a13.txt` (+ the 1-minute stream 23), `iofields_fog.txt` (5-min
  stream 23 for the morning). No blank lines in an iofields file; an unknown
  name is only a WARNING — grep `rsl.error.0000` for `W A R N I N G`.
- MYNN control: job 8320565, `wrf_output/8320565/`, 01:00 start, 30-min frames.
  3D runs: `exp/X6` (8478327, paired, night only — morning has U3), **`exp/X7`
  (8483386, the clean 01→10 reference)**, `exp/X8a|b|c` (the 23 h continuation).
  X0–X5, A12, A13, smoke were deleted 2026-08-22 for disk (F1 kept).

## A rebuild is mandatory after any Registry change

```bash
cd /gpfs/data/fs72996/ewahl/branko
realcase/scripts/build_em_real.sh realcase/env/vsc5.sh --reconfigure   # 30-40 min
```

**Always build serially on the login node with `nohup … &` (Elias, 2026-08-27) — never submit
`build_em_real.slurm`: the compute-node job waited 5+ h in the queue while the login node builds
in 40–60 min.** Record the PID (`.build_login.pid`) and wait on it.
Only `./clean -a` (which `--reconfigure` triggers) regenerates the Registry and
`inc/*.inc`; a stale registry builds and runs with new fields **silently missing**.
Keep `WRF_BUILD_JOBS=1` — `-j N` races (E12). Trust the script's verdict, then
`ldd` with the env sourced, then the devel-QOS smoke. For a source-only change:
`source realcase/env/vsc5.sh && ./compile -j 1 em_real` (~12 min; relinks).
`tmux` is not available in this session type — use `nohup … &` and a monitor
keyed on the script's PID (not on `pgrep -f "compile em_real"`, E2).
- The assistant's auto-mode classifier blocks `scancel`/`scontrol update` in some
  forms; if it refuses, hand the exact command to Elias with the `!` prefix.

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
- MUSICA: `ssh musica` works through a live master socket (`~/.ssh/config`, key
  `id_ed25519_musica`; the socket needs Elias to log in once per 12 h). The tree at
  `/data/fs201110/ew24501/branko` was pulled to HEAD and rebuilt 2026-08-22; env
  `realcase/env/musica_X8.sh` exists; nothing was submitted. Job 89435 may still be
  queued there; cancel from a MUSICA session.
- U1, U2 and U3 should be reported upstream to `wrf-model/WRF`.
- *Known unknowns* in `realcase/README.md` apply to every interpretation: first
  real-terrain, first nocturnal cold-pool run of this scheme.
