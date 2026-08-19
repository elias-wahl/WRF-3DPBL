# Inn Valley / Radfeld, 500 m, ICON-forced — real case with the 3D PBL scheme

Everything needed to set this run up on a cluster that already has the ICON
forcing and the geogrid static data. Clone the branch, source an env file, build,
set up a run directory, submit.

This is the first test of the scheme on **real terrain**. Everything verified so
far (`CHANGES.md`, job 26586607) is an idealized daytime convective `em_les` run
with a single cosine-bell mountain. Read *Known unknowns* at the bottom before
you interpret any of the output.

---

## Quick start

```bash
git clone -b 3dpbl_wrflux_v4.8.0 git@github.com:elias-wahl/WRF-3DPBL.git
cd WRF-3DPBL

cp realcase/env/template.sh realcase/env/mycluster.sh
$EDITOR realcase/env/mycluster.sh          # compiler, netCDF, LAPACK, SLURM, output root

realcase/scripts/build_em_real.sh realcase/env/mycluster.sh --reconfigure

realcase/scripts/setup_rundir.sh realcase/env/mycluster.sh \
    /scratch/$USER/innval_pbl3d_smoke pbl3d \
    --geo  /path/to/geo_em_d01.nc \
    --met-dir /path/to/met_em \
    --smoke

cd /scratch/$USER/innval_pbl3d_smoke
$EDITOR submit_real.slurm submit_wrf.slurm   # account + partition
sbatch submit_real.slurm
python3 <wrf>/realcase/scripts/check_wrfinput.py wrfinput_d01
sbatch submit_wrf.slurm
```

`--smoke` gives a 1 h run. Do that one first — it costs almost nothing and tells
you the throughput, which you need before choosing `--nodes` and `--time` for the
24 h run. Drop `--smoke` for the real thing.

---

## What is here

| | |
|---|---|
| `namelist.input.pbl3d` | the 3D PBL run (`pbl3d_opt=2`) |
| `namelist.input.mynn` | the MYNN control, identical everywhere else |
| `namelist.wps` | WPS template, only needed if geo_em must be regenerated |
| `Vtable.ICONm`, `Vtable.ICONp` | ICON Vtables, copied from `icon2wrf` so this is self-contained |
| `iofields.txt` | optional output thinning (off by default) |
| `env/levante.sh` | filled-in, verified environment (DKRZ Levante) |
| `env/template.sh` | copy this for your cluster |
| `scripts/build_em_real.sh` | configure + compile, with the LAPACK wiring WRF's own configure omits |
| `scripts/setup_rundir.sh` | assemble a run directory |
| `scripts/prepare_namelist.py` | sync the namelist to geo_em/met_em and check it |
| `scripts/check_wrfinput.py` | sanity-check `wrfinput_d01` before burning core-hours |
| `scripts/submit_real.slurm`, `scripts/submit_wrf.slurm` | SLURM templates |

---

## Three things that are easy to get wrong

### 1. LAPACK must be linked in by hand

The closure solves a 10×10 momentum–heat system and a 4×4 moisture system with
LAPACK `dgesvx` at **every grid point on every timestep**. WRF's `configure` has
no notion of LAPACK, so `LIB_LOCAL` in `configure.wrf` has to be set after
configuring. `build_em_real.sh` does that from `$LAPACK_LIBS`, and link-tests
`dgesvx` before starting the hour-long compile rather than after.

Any LAPACK works. On Levante it is `netlib-lapack-3.9.1`; with MKL use
`-lmkl_gf_lp64 -lmkl_sequential -lmkl_core`.

**Include `-Wl,-rpath` in `LAPACK_LIBS`** unless the library is on the runtime
loader path anyway. Without it the link succeeds and `wrf.exe` dies at startup
on the compute node with `error while loading shared libraries: liblapack.so.3`
— a miserable thing to discover from inside a queued job. `build_em_real.sh`
both links *and runs* a small `dgesvx` program, so it catches this before the
hour-long compile rather than after.

### 2. Six namelist values belong to WPS, not to you

`e_we`, `e_sn`, `dx`, `dy`, `num_land_cat` come from `geo_em_d01.nc`;
`num_metgrid_levels` and `num_metgrid_soil_levels` come from `met_em`. Two of
them are specific to this setup and differ from the usual defaults:

- **`num_metgrid_soil_levels = 8`.** ICON/TERRA has eight soil layers. The ECMWF
  value of 3 or 4 that most namelists carry is wrong here.
- **`num_land_cat`** is whatever the CORINE dataset in your `GEOGRID.TBL` says,
  not 21 (MODIS) and not 24 (USGS). `prepare_namelist.py` reads the actual
  `NUM_LAND_CAT` attribute out of `geo_em_d01.nc` and warns if it looks like
  stock MODIS, which would mean the CORINE entry did not win in `geog_data_res`.

`num_metgrid_levels` ships as **0** on purpose. A run set up without the sync
step then fails immediately instead of quietly interpolating onto the wrong
number of levels. Do not "fix" it by hand — run `prepare_namelist.py`.

### 3. `fg_name` must not contain `'PRES'`

ICON carries pressure natively on its model levels, so `calc_ecmwf_p.exe` is
never run and no `PRES:` files exist. Listing `'PRES'` in `&metgrid` makes
`metgrid.exe` abort on the missing files.

---

## The hard constraints the 3D PBL scheme imposes

`module_check_a_mundo.F` enforces the first three; the others are documented in
`run/README.namelist`. `prepare_namelist.py` checks all of them, so you find out
before the job is queued rather than after.

| setting | value | why |
|---|---|---|
| `bl_pbl_physics` | `0` | `pbl3d_opt` replaces the 1D PBL scheme entirely |
| `hybrid_opt` | `0` | the scheme's metric terms assume the original WRF coordinate. **The WRF default is 2**, so this must be set explicitly |
| `diff_opt` | `0` | with `pbl3d_opt=2` the scheme does the vertical *and* horizontal SGS mixing; Smagorinsky must not also run |
| `sf_sfclay_physics` | `1` | surface fluxes come from `sfclayrev`. This is the pairing the scheme was developed and tested against |
| `tke_budget` | `0` | MYNN-only diagnostic, inert with `bl_pbl_physics=0` |

`diff_6th_opt` is *not* gated on `diff_opt` — the 6th-order filter still runs, and
it is kept on (`diff_6th_opt=2`, `diff_6th_slopeopt=1`, `diff_6th_thresh=0.10`)
because with 35° slopes it is the only remaining numerical noise control.

The scheme's own tunables are all left at the values group E/F/G settled on:

```
pbl3d_l_opt      = 1      MY centre-of-mass (Blackadar) length scale
pbl3d_l0_opt     = 1      weight the MY74 Eq. 72 integral by max(q - q_min, 0)
pbl3d_prog       = 1      level 2.5, prognostic q^2
pbl3d_qsq_opt    = 1      close q^2 on the full 3D stress tensor
pbl3d_sk_eps_max = 6.0    Durbin (1996) strain limit
pbl3d_n_tau_max  = 0.53   Deardorff (1980) buoyancy limit
```

`pbl3d_l_opt = 3` (Messinger) is deliberately not used: group F's `l_dissip` fix
and group G's NaN guard both changed that path and neither has ever been run.

---

## The paired experiment

`namelist.input.pbl3d` and `namelist.input.mynn` are identical outside the
turbulence configuration — same domain, same vertical levels, same
microphysics, radiation, land surface, advection, damping, and the same
`hybrid_opt = 0`, so the two runs share a vertical coordinate and the difference
is attributable to the closure.

They do differ in the surface layer: MYNN with `sf_sfclay_physics=5`, pbl3d with
`sf_sfclay_physics=1`. Each scheme is in its intended pairing, which is the
defensible reference, but it means the comparison is PBL + surface layer rather
than PBL alone. To remove that confound, set `sf_sfclay_physics = 1` in
`namelist.input.mynn` too — WRF permits MYNN with `sfclayrev`.

Run both. Interpreting the pbl3d run on its own is not possible: `CHANGES.md`
records a 17–41% reduction in boundary-layer `q²` relative to the pre-group-E/G
scheme whose magnitude no run in this series can settle.

---

## Time window

Default is **2025-07-18 00:00 → 2025-07-19 00:00 UTC**, hourly ICON forcing,
matching the run initialized `20250718_00`. `prepare_namelist.py` overrides this
from the actual `met_em` file list, so if your forcing covers a different window
it adapts.

00 UTC is 02:00 CEST, so the run starts with the ICON cold pool already in place
and has roughly four hours before sunrise for WRF's own turbulence to spin up.
That is thin for the science target — the morning erosion phase, ~04–10 UTC. If
forcing from `20250717_12` is available, starting twelve hours earlier gives the
cold pool a full night to form in WRF's own dynamics rather than being inherited
from ICON. Worth doing if you can.

---

## Where the output goes

One variable, `WRF_OUTPUT_ROOT`, is set in the env file. Everything below it is
fixed by convention and is **the same on every cluster**:

| | |
|---|---|
| `$WRF_OUTPUT_ROOT/temp/branko/wrfout_d<domain>_<date>.nc` | history, while the run is going |
| `$WRF_OUTPUT_ROOT/temp/branko/meanout_d<domain>_<date>.nc` | `auxhist24` (the WRFlux averages) |
| `$WRF_OUTPUT_ROOT/wrf_output/<jobid>/` | archive — `submit_wrf.slurm` moves both here at the end, with `job_info.txt` and a copy of the namelist |

Both live streams use `frames_per_outfile = 1`, so one file per output time.
The archive step runs even if `wrf.exe` fails, so a crashed run's partial output
is still collected. This matches `run_files/RUN_WRF.sh`, which is what the
post-processing in `proc/` expects — output from this fork lands next to the
other forks' and is found the same way.

The namelist templates ship with a literal `@OUTPUT_ROOT@` token, not a path.
`setup_rundir.sh` passes `--output-root "$WRF_OUTPUT_ROOT"` to
`prepare_namelist.py`, which expands it and creates
`$WRF_OUTPUT_ROOT/temp/branko` (`wrf.exe` does not create its own output
directory and dies partway into the run if it is missing). An unexpanded token
is a **FATAL** finding, so a run set up without the sync step fails immediately
rather than writing into a literal `@OUTPUT_ROOT@` directory.

**If you find yourself editing `history_outname` by hand, that is the bug** —
set `WRF_OUTPUT_ROOT` instead. Porting to a new cluster changes the root and
nothing else.

One known inconsistency: `namelist.input.mynn` still carries a *relative*
`auxhist24_outname` and no `history_outname` at all, so the MYNN control writes
into its own run directory instead of the shared tree. `prepare_namelist.py`
warns about it. Left as-is deliberately rather than relocating output the
existing post-processing may already expect there.

## Cost and output volume

601 × 501 × 81 at `dx = 500 m` is 24.4 M grid points, and `dt = 3 s` over 24 h is
28 800 timesteps. `pbl3d_opt=2` does a 10×10 and a 4×4 LAPACK solve at every point
on every step, so expect it to be substantially slower per step than the MYNN
control. **Measure it with `--smoke` rather than guessing** — `submit_wrf.slurm`
prints the mean s/step at the end.

Output is the other constraint. With all five flux components on, `auxhist24`
carries on the order of 150 3D arrays; at this domain size that is roughly
**10 GiB per frame**, and 48 frames of it. `prepare_namelist.py` prints an
estimate. Three ways to cut it, in order of how much they cost you
scientifically:

1. Turn off flux components you will not use. Cold-pool erosion is a heat budget
   question, so `output_t_fluxes` is the one that must stay; `output_u/v_fluxes`
   matter for the slope-flow momentum budget; `output_q_fluxes` and
   `output_w_fluxes` are the first to go.
2. Point `iofields_filename` at `iofields.txt` — with `cu_physics=0` and
   `bl_pbl_physics=0`, twelve accumulated-tendency arrays are identically zero
   for the whole run.
3. Lengthen `auxhist24_interval_m` (and `avg_interval` with it — `avg_interval`
   must stay ≤ the output interval or `check_a_mundo` aborts).

`restart_interval = 180` (3 h) is set so the run can be chained across a queue
limit. To continue: set `restart = .true.`, move the start time to the restart
file's time, resubmit.

---

## Diagnosing the run

The scheme writes per-gridpoint solver diagnostics into `wrfout` (group I):

| field | reading |
|---|---|
| `PBL3D_COND_A` | condition number of the 10×10 system. Healthy is 10–500. 10⁵ and up means it is being solved far outside its validity range |
| `PBL3D_T1_RATIO` | `l_use/l_master` after the Durbin strain limit; 1 means it did not bind |
| `PBL3D_T2_STEPS` | length-scale back-off steps on a degenerate system |
| `PBL3D_T3_FLAGS` | realizability bitmask: 1 variance floor, 2 trace, 4 Cauchy–Schwarz, 8 determinant, 16 heat |
| `PBL3D_SK_EPS`, `PBL3D_N_TAU` | strain and stratification time-scale ratios before limiting |
| `L_MASTER`, `Q_SQ` | master length scale and twice the TKE |

In the idealized runs the worst regime for Tier 2 was the convective mixed layer
(68.9% of points, 0.92 extra solves — issue F1). Real terrain will produce
something different. If Tier 3 activation is high in the drainage layer on the
slopes, that is new information and worth recording.

---

## Known unknowns

Carried over from `CHANGES.md`, and they bear directly on how you should read
this run:

- **The magnitude of the boundary-layer `q²` reduction is unresolved.** Groups E
  and G reduced it by 17–41%. The direction is defensible; the magnitude cannot
  be settled by comparing the model to itself. This run does not settle it
  either — it needs an LES or observational reference (PIANO / CROSSINN /
  TEAMx).
- **A nocturnal / cold-pool case has never been run**, idealized or otherwise.
  This is the first.
- **Real terrain has never been run.** Group J's 35° mountain is a single
  idealized cosine bell.
- **Issue A3 is open**: `q_sq` and `l_master` are updated in sequence rather than
  iterated to a fixed point. Group G made `l` an explicit function of `q`, so the
  two are now directly coupled and the sequencing matters more than it used to.
  If the run shows oscillatory `L_MASTER`, this is the first place to look.
- **Soil moisture units.** ICON's `W_SO` is a mass, kg m⁻²; WRF's `SMOIS` is a
  volumetric fraction. Nothing in the `icon2wrf` → ungrib → metgrid chain
  converts between them. `check_wrfinput.py` checks the range explicitly, and
  this is the single check to read: if `SMOIS` comes out of order 1–100 instead
  of 0.02–0.6, the soil is saturated everywhere, the Bowen ratio collapses, and
  the daytime heating that erodes the cold pool never happens. The run will
  complete and be wrong.

---

## Build notes

From `KNOWN_ISSUES.md`, the ones that cost time:

- **`module load` must be redirected, never piped.** Piping runs it in a subshell
  and silently discards it, after which `mpif90` resolves to a different
  compiler and the link fails with `EXIT=0` and no executables. The env files
  all use `> /dev/null 2>&1`.
- **`./compile` returns 0 even when it produced nothing.** `build_em_real.sh`
  keys on `Executables successfully built` plus an actual stat of the binaries,
  and additionally checks the linked `wrf.exe` for objects from more than one
  GCC and for conda/mambaforge libraries.
- **Do not poll the build with `pgrep -f "compile em_real"`** — the poller's own
  command line contains that string, so it self-matches and never sees the
  process exit.
- **Two submodules carry local fixes**, and both now come down with a plain
  recursive clone — `phys/physics_mmm` a `sfclayrev` table lower-bound guard
  (without it `sf_sfclay_physics=1`, which this case uses, **segfaults** over
  steep terrain), and `phys/noahmp` the USGS table extended to 33 categories for
  the CORINE-as-USGS land use. Both were local-only commits until 2026-08-19,
  which meant `git clone --recursive` failed outright anywhere else — the SHAs
  existed on one disk. They now live on forks (`elias-wahl/MMM-physics`,
  `elias-wahl/noahmp`) that `.gitmodules` points at over HTTPS, so no GitHub
  credentials are needed to clone.

  ```bash
  git submodule update --init --recursive
  git submodule status | grep -E 'noahmp|physics_mmm'   # expect c5b6dbc / 7071724
  ```

  Check those two SHAs before building. If they are missing the clone is
  incomplete, and the build either fails or silently produces a WRF that
  segfaults on the slopes.

  `patches/physics_mmm-sf_sfclayrev-table-lower-bound.patch` is kept as a record
  of the fix; **you no longer need to apply it by hand.** This is upstream issue
  U1 and is not yet reported to `wrf-model/WRF`.
