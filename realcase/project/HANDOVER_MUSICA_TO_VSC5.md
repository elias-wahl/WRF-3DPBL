# Handover — MUSICA → VSC-5, 2026-08-19

Written on MUSICA at the end of the session that diagnosed the `pbl3d_opt=2`
blowup. Read this **first**, then `DECISIONS.md`, then `branko/OPEN_ISSUES.md`
section A9.

The reason for the move is mundane: MUSICA's queue became unusable (see
*Why we left* below). Nothing about the science or the build failed.

---

## TL;DR — what was learned

`pbl3d_opt=2` blows up **deterministically** on real terrain, and we now know
where the fault is and where it is not.

- It dies at model `2025-07-18_01:38:00` (step 1141), on the **same 81 of 190
  ranks**, at the **same instruction**, in two independent runs from
  byte-identical inputs. It is fully reproducible, which makes any fix directly
  testable.
- The proximate crash is a SIGSEGV inside RRTMG longwave. **That is only the
  terminal symptom** — an upstream unguarded table index (`KNOWN_ISSUES.md` U2).
- The real failure is a **runaway near-surface vertical velocity in nocturnal
  katabatic drainage flow** on 33.6° slopes. `max|W|` climbs 9.65 → 22.44 m/s
  over eight minutes; `W / (u·∇h)` climbs 1.68 → 2.96, so it is a positive
  feedback, not terrain-following kinematics.
- **The `dgesvx` solve is NOT the cause.** `COND_A` stays below 1e5 essentially
  everywhere (threshold `COND_MAX` = 1e8) until *after* the state has already
  gone non-finite. This was the obvious suspect and the evidence excludes it.
- **The discriminating variable is `Q_SQ`, and it diverges earlier than `W`:**
  30 → 43 → 82 → **247** then blowup, while `pbl3d_opt=1` holds flat at 9–11.

## What is ruled out (do not re-test these)

| ruled out by | what it excludes |
|---|---|
| the user's stock-WRF **MYNN control, 47 h**, identical terrain/forcing/`dx`/`e_vert`/`eta_levels`/`time_step`/`epssm` | terrain, dx=500 m, `time_step=2`, `epssm=0.9`, ICON forcing, soil moisture, Thompson/RRTMG/Noah-MP themselves |
| **`pbl3d_opt=1` survived** the same point (0 non-finite in 41 frames) with `hybrid_opt=0` and `diff_opt=0` **unchanged** | the pure sigma coordinate, the absent Smagorinsky backstop, and "katabatic flow is unrepresentable" — at another column opt=1 holds `W = -12.5 m/s` flat for ten minutes |

**The fault is inside the full 3D flux path (`Calc_fluxes`, `pbl3d_opt == 2`).**

## The immediate next step

Find **which q² budget term** drives the runaway. `pbl3d_opt=1` and `=2` differ
in exactly three q²-relevant places (`dyn_em/module_pbl3d.F` ~5790–5810):

1. **`Calc_q_sq_shear`** vs `Calc_q_sq_shear_pbl_approx` — full stress-tensor
   shear production vs a 1D form. **Prime suspect**: it is a *production* term
   scaling with the full strain tensor, and strain is what steep-slope drainage
   flow maximises.
2. **`Calc_q_sq_horizontal_diffusion`** — only called for `pbl3d_opt > 1`.
   Nominally a sink, but on sloping coordinate surfaces can act as a spurious
   source.
3. The flux computation itself, which feeds (1).

**Everything needed to answer this is already committed and built.** The five
budget terms were promoted `r` → `rh` in `Registry/Registry.EM_COMMON` so they
reach `wrfout`: `q_sq_shear`, `q_sq_buoyancy`, `q_sq_dissip`, `q_sq_vdiff`,
`q_sq_hdiff`. **This requires a rebuild on VSC-5** (Registry change).

Then run `pbl3d_opt=2` with 1-minute output and tabulate the five terms over
01:25→01:38. The question to answer: **is production rising, or is dissipation
failing?**

If it is the shear term, the fix likely already exists in form — Tier 1
(`pbl3d_sk_eps_max`, Durbin) limits `Sk/eps` but that limiter is **not applied
to the q² budget**.

### Do NOT do these

- **Do not apply U2's index guard as "the fix".** It converts a loud,
  perfectly deterministic crash into a NaN propagating silently through the
  radiative tendency. The guard is correct and should land *after* the blowup is
  understood, never as the thing that resolves it.
- **Do not treat `pbl3d_opt=1` as the answer for production.** It is the
  diagnostic. The whole point of this configuration is the full 3D closure.
- **Do not set `ra_lw_physics=0` to "get the run through".** Longwave cooling is
  part of the cold-pool mechanism under study, and without the segfault the
  instability would run silently.

---

## Reproducing on VSC-5

The run is **fully deterministic** from these inputs, so the crash should
reproduce exactly. If it does not, that is itself a finding — say so.

- Domain 601×501×80, dx=dy=500 m, `time_step=2`, start 2025-07-18 **01:00** UTC,
  `num_metgrid_levels=12`, `num_metgrid_soil_levels=8`, `pbl3d` config.
- `wrfinput_d01` / `wrfbdy_d01`: VSC-5 already holds the originals at
  `/gpfs/data/fs72996/ewahl`. The MUSICA copies used for every run in this
  session are byte-identical to those (verified by size at migration).
- Blowup at step 1141 = model `01:38:00`. A 1 h `--smoke` run reaches it in
  ~25–30 min on 190 ranks.
- Run `check_wrfinput.py` first. **`SMOIS` must be 0.02–0.6**, not 1–100. Note
  the script's actual assertion is `0 ≤ SMOIS ≤ 1`; a max of exactly 1.000 is the
  water-body fill value, not a bug. Our run: mean 0.284 — healthy.

## Evidence left on MUSICA (not transferred — large)

| path | what | size |
|---|---|---|
| `wrf_output/88703/` | first opt=2 crash, incl. `rsl_crash_logs.tar.gz` (all 190 rank logs with backtraces) | 60 G |
| `wrf_output/88971/` | opt=2 rerun, 1-min frames, **the primary evidence** | 119 G |
| `wrf_output/89167_opt1_baseline/` | **opt=1 surviving baseline**, 1-min frames | 148 G |
| `wrf_output/wrf.exe.bak_pre_qsq_rh` | binary before the Registry change | 58 M |

All quantitative results from these are written up in `OPEN_ISSUES.md` A9, which
**is** in git. The raw files are only needed to re-examine something A9 does not
already state. If you want one thing, take `rsl_crash_logs.tar.gz` (61 K).

---

## What travels how

**In git** (`branko/`, branch `3dpbl_wrflux_v4.8.0`, commit `b7b2c76ae`):
`KNOWN_ISSUES.md` (U2, E11, E12, E13), `OPEN_ISSUES.md` (A9),
`Registry/Registry.EM_COMMON`, `realcase/env/musica.sh`,
`realcase/scripts/{build_em_real.sh,build_em_real.slurm,setup_rundir.sh,submit_real.slurm,submit_wrf.slurm}`.

**NOT in git — `/data/fs201110/ew24501` is not a repository.** These four files
must be copied over SSH or they are lost:

```
ARCHITECTURE.md   CLAUDE.md   DECISIONS.md   MIGRATION_MUSICA.md
```

plus this handover file. `DECISIONS.md` matters most — it carries the reasoning
that is deliberately not in the code.

---

## Traps that cost time here (all now in `KNOWN_ISSUES.md`)

- **E12 — `./compile -j N` races.** WRF's own `phys/` Makefile dependencies are
  incomplete. `-j 16` failed in 4.5 min with missing `.mod` files. Worse, a race
  can also compile against a half-written `.mod` and produce a *subtly wrong*
  binary. `build_em_real.sh` now defaults to serial; keep it that way, and never
  resume a raced build without `./clean`.
- **E11 — stale run-dir symlinks.** Four dangling VSC-5-path symlinks survived
  `setup_rundir.sh` reruns and only failed inside `wrf.exe`, never `real.exe`.
  Check `find <rundir> -maxdepth 1 -xtype l` when reusing a directory.
- **E13 — `LIB_LOCAL` grew on every rebuild** because the LAPACK guard sniffed
  library *names* and missed FlexiBLAS. Fixed; would not have bitten on VSC-5
  (its LAPACK is named conventionally), but the fix is general.
- **E6 — EESSI's init is not `nounset`-safe.** MUSICA-specific; harmless on VSC-5.
- **E10 / E9 — MUSICA's 190-cores-per-node and QOS-not-partition.**
  MUSICA-specific. **On VSC-5 revert to its own conventions**: `zen3_0512`,
  128 cores/node, `--qos=zen3_0512`. Do not carry the 190 over.
- **`check_wrfinput.py`'s `SMOIS` check is the one to actually read.**

## Sizing for VSC-5

Do **not** carry MUSICA's sizing over. Measured here: **~1.26 s/step** on one
190-core MUSICA node for `pbl3d_opt=2` (`pbl3d_opt=1` is ~0.78 s/step — the
10×10 solve is most of the cost). VSC-5 nodes are 128 cores and a different
generation. Re-measure with a `--smoke` run; `submit_wrf.slurm` prints mean
s/step at the end.

For reference, the full production target is 23 h at `time_step=2` = 41,400
steps. At MUSICA's 1.26 s/step on a single node that is ~14.5 h — so the
production run **does** need more than one node, sized from a fresh smoke test.

## Why we left MUSICA

Not a technical failure — the build works and every diagnostic run completed.
The queue became unusable:

- A single user (account `p201209`) ran **626 concurrent 8-core jobs**, ramping
  up from ~15:00, fragmenting all 45 nodes. 3,500+ cores idle, **zero** whole
  nodes free.
- Our account `p201110` is forced to **exclusive whole nodes** by a job-submit
  plugin — requests below 190 tasks are *rejected outright*, verified by
  `sbatch --test-only` at 8/32/64/96/128 tasks. So we cannot use the idle
  fragments; they can.
- The production QOS `zen4_0768` has **no per-user limits at all** (no
  `MaxJobsPU`, `MaxSubmitPU` or `MaxTRESPU`) and `MaxWall` of 3 days. 243 of
  their jobs hold 3-day limits.
- Estimated start for a 40-minute job: **2026-08-21**.

**Worth raising with MUSICA support** before returning: grant `p201110` either
shared allocations or the `fast_zen4_0768` QOS (10× priority, 3-day wall — the
partition's `AllowQos` permits it but our account is not entitled), or ask for a
`MaxTRESPU` on the production QOS. This will recur, and it matters more for the
23 h production run than it did for these 30-minute diagnostics.

**Job 89435 is still queued on MUSICA.** Cancel it (`scancel 89435`) if the work
has moved to VSC-5, so it does not run unattended and produce output nobody reads.

---

## Still open, carried forward

- **`ARCHITECTURE.md` still describes VSC-5** in its title and cluster notes —
  which is now accidentally correct again. Read it with that in mind.
- The shared `data/WRF/run/wrfinput_d01`/`wrfbdy_d01` on VSC-5 were overwritten
  by branko's first `real.exe` and never restored. Still open; see `DECISIONS.md`.
- U2 should be reported upstream to `wrf-model/WRF`, as should U1, which is still
  carried locally and unreported.
- Science caveats unchanged: this is still the first real-terrain and first
  nocturnal/cold-pool run of this scheme, and the magnitude of the boundary-layer
  `q²` reduction remains unresolved. Read *Known unknowns* in
  `realcase/README.md` before interpreting any output.
