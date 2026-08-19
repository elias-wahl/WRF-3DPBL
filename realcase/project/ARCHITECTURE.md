# Project architecture (Inn Valley ICON-forced WRF, VSC-5)

Keep this short. Update it when structure changes; don't let it grow past
this length — trim before adding.

## Top-level layout (`/gpfs/data/fs72996/ewahl/`)

- **WRF forks** — each is a full WRF source checkout + its own `run/`:
  - `branko/` — WRF-3DPBL fork (`elias-wahl/WRF-3DPBL`), branch
    `3dpbl_wrflux_v4.8.0`. The active one. 3D-PBL scheme (Juliano/NCAR,
    supervisor Branko Kosović) rebased to WRF v4.8.0 + WRFlux SGS-flux
    integration (both by the user, 2026). See `branko/realcase/` below.
  - `goger18WRF/`, `goger19WRF/` — other forks (`elias-wahl/wrf-hotspot`
    lineage), MYNN-based, used for comparison runs on the same domain.
  - `WRF/` — another fork/checkout, `sf_urban_physics=0`, stock 27-cat
    VEGPARM/MPTABLE despite `num_land_cat=33` (silently wrong for
    categories 28/31-33 — see below). Has produced completed production
    runs (e.g. job 8320565).
  - `WRF_arc/` — archived/alternate WRF tree (CMake-based build), not
    actively used this session.
- **WPS pipeline** — `WPS/` (primary), `WPS_ecmwf/`, `WPS_arc/` are
  parallel WPS checkouts/outputs for different forcing sources.
  `WPS_GEOG/` holds static geog datasets, including `corine`,
  `CORINE_2018_GaspardSimonet`, and `landuse_30s_with_lakes`.
- **Forcing data**: `ICON/TEAMx_sEOP_IOP18-20/` (and `IOP17/`) — raw
  ICON GRIB2 (`*_sfc`, `*_soil_temp`, `*_soil_moist`, `*_3d`).
  `icon2wrf/` — separate git repo/tool (own remote,
  `elias-wahl/icon2wrf`) that reformats raw ICON GRIB2 for WPS ungrib;
  fixes belong there, not in WPS or the WRF forks.
- **Orchestration**: `run_files/` — generic, fork-agnostic scripts
  (`RUN_WPS.sh`, `RUN_WRF_*.sh`, `check_*.py` sanity checks) used across
  all forks except branko, which has its own `realcase/` tooling instead.
- **Run directories**: `branko_runs/` (branko's per-experiment run dirs,
  e.g. `innval_pbl3d_smoke/`), `wrf_output/` (archived production output
  by job ID), `temp/` (scratch history/aux output paths referenced by
  namelists — must exist before `wrf.exe` runs).
- **Other**: `data/` = observational validation data (soundings,
  stations, lidar, UAS), not model output. `proc/` = Python
  post-processing pipeline.

## The ICON→WRF forcing chain

```
ICON/*.grib2 → icon2wrf (reformat) → WPS ungrib (Vtable.ICONp/m)
  → WPS metgrid → met_em.*.nc → real.exe → wrfinput_d01/wrfbdy_d01 → wrf.exe
```
`run_files/RUN_WPS.sh` runs ungrib+metgrid end to end from raw GRIB2.
`WPS/geo_em.d01.nc` (601×501, dx=500m) is the shared domain — regenerating
it affects every fork.

## branko internals

- Branch `3dpbl_wrflux_v4.8.0`. `pbl3d_opt=2` hard-requires
  `bl_pbl_physics=0`, `hybrid_opt=0`, `diff_opt=0`, `tke_budget=0`,
  `sf_sfclay_physics=1` (enforced by `module_check_a_mundo.F`).
- Submodules (each its own git repo, upstream NCAR remotes, no personal
  fork — local-only commits possible, can't be pushed): `phys/noahmp`
  (refactored Noah-MP, reads `parameters/NoahmpTable.TBL`, driver in
  `drivers/wrf/NoahmpReadTableMod.F90`), `phys/physics_mmm`,
  `phys/MYNN-EDMF`, `phys/MYNN-SFC`, `phys/GFL`, `phys/TEMPO`,
  `phys/fire_behavior`, `.ci/hpc-workflows`.
- `realcase/` — branko's own build/run tooling (not `run_files/`):
  `env/vsc5.sh` (cluster env — VSC-5 Spack modules need
  `LD_LIBRARY_PATH` seeded from `LIBRARY_PATH` manually), `namelist.input.pbl3d`
  (ICON-merged template), `scripts/build_em_real.sh`,
  `scripts/setup_rundir.sh`, `scripts/submit_real.slurm`/`submit_wrf.slurm`,
  `scripts/check_job.sh` (job status + RSL log check), `scripts/check_wrfinput.py`.
- Land use gotcha: this project's `WPS_GEOG` CORINE data is remapped onto
  33 categories but declared `MMINLU="USGS"`. Stock Noah-MP hardcodes 27
  categories for "USGS" — branko's `NoahmpTable.TBL`/`MVT` were extended
  to 33 (categories 28/31-33 ≈ lake + Innsbruck urban, ~5% of domain).
  Other forks still use the stock 27-cat tables (silently wrong for those
  cells, not crashing, because their older Noah-MP driver doesn't
  hard-fail on the size mismatch).

## Cluster notes (VSC-5)

- `zen3_0512_devel` QoS: 10 min wall cap, shared CPU-count cap across
  users (can queue for a while) — always smoke-test here before a
  production submission (8 nodes, 12h+ typical).
- Shared files: `/home/fs72996/ewahl/data/WRF/run/wrfinput_d01`/`wrfbdy_d01`
  are used by multiple forks — never let a rundir's setup script
  symlink/overwrite them; branko's `real.exe` output should stay in its
  own rundir as real files, not links back into `WRF/run/`.
