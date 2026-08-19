# Migration to MUSICA (Innsbruck) — read this first

You are picking up an operational WRF setup that was moved off **VSC-5**
(`/gpfs/data/fs72996/ewahl`) because that cluster became unavailable. A 24 h
production run was sitting in the queue and never started. The goal is to get
that run going here.

Read this file, then `branko/realcase/README.md` — that one is the authoritative
build-and-run guide and it travels with the repo. This file only covers what is
*different* because of the move.

Throughout: **`$MBASE`** is the project root on MUSICA (the directory this file
is in).

---

## The run that was stuck

| | |
|---|---|
| job | `8464723`, `wrf_innval_pbl3d_18th` |
| why it never ran | `ReqNodeNotAvail` — the whole `zen3_0512` partition was down |
| config | `pbl3d` (3D PBL scheme, `pbl3d_opt=2`) |
| run dir on VSC-5 | `branko_runs/innval_pbl3d_18th` |
| domain | 601 × 501 × 80, `dx = dy = 500 m`, `time_step = 2` |
| window | 2025-07-18 **01:00** → 2025-07-19 00:00 UTC, `run_hours = 23` |
| forcing | hourly ICON, 48 `met_em` files, `num_metgrid_levels = 12`, `num_metgrid_soil_levels = 8` |
| resources used on VSC-5 | 2 nodes, 200 tasks, 30 h wall limit |

Note the window starts at **01:00, not 00:00**, `e_vert` is **80, not 81**, and
`time_step` is **2, not 3** — all deliberate, taken from the ICON namelist. The
values in `realcase/README.md` describe the template defaults, not this run.

`real.exe` **already completed on VSC-5**. `branko_runs/innval_pbl3d_18th/`
carries `wrfinput_d01` (2.7 G) and `wrfbdy_d01` (4.5 G) as real files. These are
plain NetCDF and portable across clusters, so in principle you can skip straight
to `wrf.exe`. Re-running `real.exe` after the rebuild is still the safer default
— do that unless you are short on time, and if you do reuse them, run
`check_wrfinput.py` on the copied file first.

---

## What must happen here, in order

### 0. Prerequisites

Confirm before starting: quota for ~100 GB, your SLURM account and partition
names, and what `module avail` offers for gcc / OpenMPI / netcdf-c /
netcdf-fortran / lapack / jasper / python3 + netCDF4.

### 1. A rebuild is mandatory

**No binary from VSC-5 is valid here.** Different modules, different LAPACK,
different toolchain. The `branko/` tree should be a fresh `git clone`, precisely
so no stale `.o` files or `configure.wrf` survive:

```bash
git clone --recursive -b 3dpbl_wrflux_v4.8.0 \
    https://github.com/elias-wahl/WRF-3DPBL.git $MBASE/branko
```

The submodules `phys/noahmp` and `phys/physics_mmm` carry local fixes (a
33-category CORINE-as-USGS table; a `sfclayrev` table lower-bound guard that
prevents a **segfault over steep terrain**). They were pushed to forks under
`elias-wahl/` and `.gitmodules` points there, so a recursive clone gets them.
Verify rather than assume:

```bash
git -C $MBASE/branko submodule status | grep -E 'noahmp|physics_mmm'
# expect c5b6dbc (noahmp) and 7071724 (physics_mmm)
```

If those SHAs are missing the clone is incomplete and the build will either fail
or silently produce a WRF that segfaults on the slopes. Stop and fix it first.

### 2. `realcase/env/musica.sh` — already written, one value to confirm

**It exists and comes down with the clone.** Every value in it was probed on
MUSICA on 2026-08-19, and `dgesvx` was compiled, linked and *run* there against
FlexiBLAS before the file was written. Sourcing it resolves `NETCDF`, `HDF5`,
`LAPACK_LIBS`, `JASPERLIB` and `FC` correctly.

Settled already: EESSI 2025.06, toolchain `gompi-2024a` (GCC 13.3.0 +
OpenMPI 5.0.3), `netCDF-Fortran/4.6.1`, `FlexiBLAS/3.4.4` (which replaces
`-llapack -lblas` with `-lflexiblas`), `JasPer/4.2.4`, account `p201110`,
partition `zen4_0768` (devel: `dev_zen4_0768`), `CORES_PER_NODE=192`,
`WRF_OUTPUT_ROOT=/data/fs201110/ew24501`.

`WRF_CONFIGURE_OPTION=34` is **confirmed on this machine**, not inherited: read
off `./configure`'s own menu here, where it is the only gfortran/dmpar entry
(`32. (serial) 33. (smpar) 34. (dmpar) 35. (dm+sm)  GNU (gfortran/gcc)`).
Re-check it only after a WRF version bump — the numbering moves between releases.

**Nothing in the env file needs editing before the first build.**

Two gotchas already handled in the file, but worth knowing if you edit it:
**do not add `module purge`** after the EESSI init (it strips `MODULEPATH` and
every load then fails silently), and **do not load `netcdf4-python` in this
file** — it only exists for `foss-2025a` and would drag GCC 14.2.0 in against
the build toolchain. `check_wrfinput.py` gets its own shell; the file explains how.

If you ever do need to rebuild this from scratch, the reference material is
`realcase/env/template.sh` (documents each field) with `env/vsc5.sh` and
`env/levante.sh` as worked examples. The fields that actually bite:

- **`module load` must be redirected (`> /dev/null 2>&1`), never piped.** Piping
  runs it in a subshell and silently discards it; `mpif90` then resolves to a
  different compiler and the link fails with `EXIT=0` and no executables.
- **`LAPACK_LIBS` is required and is not optional.** The 3D PBL closure calls
  `dgesvx` at every grid point on every timestep; WRF's `configure` knows nothing
  about LAPACK. **Include `-Wl,-rpath`** — without it the link succeeds and
  `wrf.exe` dies at startup on the compute node with
  `error while loading shared libraries: liblapack.so.3`.
- **`WRF_CONFIGURE_OPTION`** — run `./configure` once by hand here and read the
  number off. `34` is a VSC-5-verified value for gfortran/dmpar, not a portable
  one; the entry moves between WRF releases.
- **`LD_LIBRARY_PATH`** — VSC-5 needed it seeded from `LIBRARY_PATH` because its
  Spack modules do not export it. Check whether MUSICA's do; keeping the line is
  harmless.
- **`WRF_OUTPUT_ROOT`** — see the output section below. Set it to `$MBASE`.
- `SLURM_ACCOUNT_DEFAULT`, `SLURM_PARTITION_DEFAULT`, `CORES_PER_NODE`,
  `MPI_LAUNCHER` (`srun` vs `mpirun -np $SLURM_NTASKS`).

### 3. Build, set up, submit

```bash
cd $MBASE/branko
realcase/scripts/build_em_real.sh realcase/env/musica.sh --reconfigure

realcase/scripts/setup_rundir.sh realcase/env/musica.sh \
    $MBASE/branko_runs/innval_pbl3d_smoke pbl3d \
    --geo $MBASE/WPS/geogrid_smoothed_output/geo_em.d01.nc \
    --met-dir $MBASE/WPS/metgrid_output --smoke

cd $MBASE/branko_runs/innval_pbl3d_smoke
$EDITOR submit_real.slurm submit_wrf.slurm     # account, partition, nodes
sbatch submit_real.slurm
python3 $MBASE/branko/realcase/scripts/check_wrfinput.py wrfinput_d01
sbatch submit_wrf.slurm
```

`build_em_real.sh` link-tests *and runs* a `dgesvx` program before starting the
hour-long compile, checks for `Executables successfully built` plus an actual
stat of the binaries, and screens the linked `wrf.exe` for mixed-GCC and conda
libraries. Let it do that work. Do **not** poll it with
`pgrep -f "compile em_real"` — the poller's own command line self-matches and it
never sees the process exit.

Run `--smoke` (1 h) first. It costs almost nothing and `submit_wrf.slurm` prints
the mean s/step at the end, which is what you need to size `--nodes` and
`--time` for the 23 h run. VSC-5's 2 nodes / 30 h is a starting guess, not a
measurement that transfers.

**The one check to actually read** is `check_wrfinput.py`'s `SMOIS` range: it
must be **0.02–0.6**, not 1–100. ICON's `W_SO` is a mass (kg m⁻²), WRF's `SMOIS`
is a volumetric fraction. If it comes out 1–100 the soil is saturated
everywhere, the Bowen ratio collapses, the daytime heating that erodes the cold
pool never happens — and the run completes and is wrong. The conversion lives in
`icon2wrf` (`fix_soil_levels`); if it is wrong, fix it there, not downstream.

Then drop `--smoke` and set up the real run with the window in the table above.

---

## Output layout — do not let this drift

This is a hard requirement carried over from VSC-5. One variable,
`WRF_OUTPUT_ROOT`, is set in the env file. **Everything below it is fixed and
must be identical on every cluster:**

| | |
|---|---|
| `$WRF_OUTPUT_ROOT/temp/branko/wrfout_d<domain>_<date>.nc` | history, during the run |
| `$WRF_OUTPUT_ROOT/temp/branko/meanout_d<domain>_<date>.nc` | `auxhist24`, the WRFlux averages |
| `$WRF_OUTPUT_ROOT/wrf_output/<jobid>/` | archive; `submit_wrf.slurm` moves both here at the end, with `job_info.txt` and the namelist |

Both live streams use `frames_per_outfile = 1`. The archive step runs even when
`wrf.exe` fails, so a crashed run's partial output is kept. This mirrors
`run_files/RUN_WRF.sh`, which is what the post-processing in `proc/` expects.

The namelist templates carry a literal `@OUTPUT_ROOT@` token, expanded by
`prepare_namelist.py --output-root` (which `setup_rundir.sh` passes from
`$WRF_OUTPUT_ROOT`). An unexpanded token is a **FATAL** finding, so a run set up
without the sync step fails immediately instead of writing into a directory
literally named `@OUTPUT_ROOT@`.

**Set `WRF_OUTPUT_ROOT`. If you find yourself editing `history_outname` by hand,
that is the bug.**

Known inconsistency, inherited and left alone deliberately:
`namelist.input.mynn` has a relative `auxhist24_outname` and no
`history_outname`, so the MYNN control writes into its own run directory rather
than the shared tree. `prepare_namelist.py` warns about it. It was not
"fixed" because relocating that output could strand post-processing that already
expects it there — decide on purpose if you change it.

---

## What did NOT transfer and must be recreated here

- **`icon2wrf` FTP credentials.** `icon2wrf/config/credentials.toml` and
  `icon2wrf/.ftp_pass` are gitignored secrets. If they were not copied by hand,
  recreate them — see `icon2wrf/README.md` §"Deploying on a New Cluster". Never
  commit them.
- **`branko_runs/*` symlinks.** Those run dirs link back into the VSC-5 `branko/`
  tree for executables and tables; the links are dangling here. They were copied
  for their *output and logs*, not to run from. Recreate run dirs with
  `setup_rundir.sh`, do not repair them by hand.
- **`LIBS/jasper`** was built against VSC-5's toolchain. Prefer a MUSICA `jasper`
  module (`JASPERLIB`/`JASPERINC`, needed for WPS ungrib only); treat the copied
  build as a fallback.
- **The WRF build itself** — see step 1.

## Regenerating WPS output, if you need to

You should not need to: `WPS/geogrid_smoothed_output/geo_em.d01.nc` and the 48
`met_em` files came along. If you do:

- `WPS/FILE:*` are ungrib intermediates, regenerable from `icon2wrf/output/` via
  `run_files/RUN_WPS.sh`.
- `geo_em.d01.nc` needs `WPS_GEOG/` (came along, 43 G) and
  `realcase/namelist.wps`. Regenerating it **affects every fork**, not just this
  one — see `ARCHITECTURE.md`.
- `fg_name` must not contain `'PRES'`. ICON carries pressure natively, so
  `calc_ecmwf_p.exe` never runs and no `PRES:` files exist; listing it makes
  `metgrid.exe` abort.

---

## Open items carried over

- **The shared `wrfinput_d01`/`wrfbdy_d01` under
  `data/WRF/run/` were overwritten on VSC-5 and never restored** (branko's first
  `real.exe` run followed stale symlinks, since removed). Still open. If another
  fork's run depends on the originals, they need regenerating. See `DECISIONS.md`.
- `ARCHITECTURE.md` still describes VSC-5 in its title and "Cluster notes"
  section. **Update it for MUSICA once the build works here** — partitions, QoS,
  the devel-queue smoke-test advice — and keep it short, per its own header.
- The science caveats are unchanged by the move and still apply: read
  *Known unknowns* in `realcase/README.md` before interpreting any output. This
  is the first real-terrain and first nocturnal/cold-pool run of this scheme.

## Where the context lives

**Install the memory files first**: `.claude/memory/` holds the Claude memory
files from the VSC-5 session, staged for transfer. They are not read from there
— see `.claude/memory/README-INSTALL.md` for the one-command copy into
`~/.claude/projects/<slug>/memory/` (the slug is derived from `$MBASE`, so it
differs from VSC-5's).


- `ARCHITECTURE.md` — project layout and the ICON→WRF forcing chain. Read early.
- `DECISIONS.md` — why non-obvious science/config choices were made. Append to it
  in the same turn as the work, newest first.
- `branko/realcase/README.md` — the build/run guide. `CHANGES.md`,
  `KNOWN_ISSUES.md`, `OPEN_ISSUES.md` in `branko/` alongside it.
- `icon2wrf/README.md` — the ICON GRIB2 → ungrib reformatter, including its own
  new-cluster deployment section.
