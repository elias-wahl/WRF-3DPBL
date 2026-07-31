# Known issues — external to this fork

Problems found while working on the 3D PBL scheme that are **not** ours to fix in the
scheme itself: upstream WRF bugs, environment and toolchain hazards, and behaviours
that look like bugs but are not.

Kept separate on purpose:

| file | scope |
|---|---|
| `OPEN_ISSUES.md` | open questions and defects **in the 3D PBL scheme** |
| `CHANGES.md` | changes we have made, grouped into proposed commits |
| `KNOWN_ISSUES.md` | **this file** — upstream bugs and environment traps |

---

## U1. `sf_sfclayrev` stability-function lookup has no lower bound check — segfaults

**Status:** confirmed, reproduced deterministically, **fix now carried locally
(2026-07-31), still not reported upstream**
**Severity:** high — crashes the model, and the crash site is nowhere near the cause
**File:** `phys/physics_mmm/sf_sfclayrev.F90` (symlinked into `phys/`)
**Affects:** `sf_sfclay_physics = 1` (revised MM5 Monin-Obukhov). Any PBL scheme, any
configuration — nothing about this is specific to `pbl3d`.

### The code

```fortran
 real(kind=kind_phys),dimension(0:1000),save:: psim_stab,psim_unstab,psih_stab,psih_unstab
 ...
 real(kind=kind_phys) function psim_stable(zolf)
 real(kind=kind_phys),intent(in):: zolf
 integer:: nzol
 real(kind=kind_phys):: rzol
 nzol = int(zolf*100.)
 rzol = zolf*100. - nzol
 if(nzol+1 .lt. 1000)then
    psim_stable = psim_stab(nzol) + rzol*(psim_stab(nzol+1)-psim_stab(nzol))
 else
    psim_stable = psim_stable_full(zolf)
 endif
```

The tables are dimensioned `0:1000`. The guard `nzol+1 .lt. 1000` **only checks the
upper bound**. If `zolf` is negative, or NaN, or large-negative, `nzol` is negative or
garbage and `psim_stab(nzol)` reads outside the array. With bounds checking off (the
normal build) that is an unguarded wild read, and it segfaults.

**All four functions have the identical flaw**: `psim_stable`, `psih_stable`,
`psim_unstable`, `psih_unstable`.

### Reproduction

Idealized `em_les` (`ideal_case = 9`), 120x120x65, dx = 500 m, 3D cosine-bell mountain
1560 m high / 7 km wide (35 deg max slope), `sf_sfclay_physics = 1`,
`sf_surface_physics = 0`, `isfflx = 2`. Setup in
`/work/bm1236/b301097/pbl3d_test/`.

Crashes deterministically at the same model time on the MPI ranks covering the
mountain. Backtrace (`addr2line` against `wrf.exe`; the build has no `-g`, so the
raw trace is address-only):

```
__sf_sfclayrev_MOD_psim_stable
__sf_sfclayrev_MOD_sf_sfclayrev_run
__module_sf_sfclayrev_MOD_sfclayrev
__module_surface_driver_MOD_surface_driver
__module_first_rk_step_part1_MOD_first_rk_step_part1
solve_em_ / solve_interface_ / integrate
```

Observed twice, on unrelated flow configurations:

| case | crashed at | failing ranks (8x8 decomposition) |
|---|---|---|
| U = 8 m/s, `N h/U = 2.4` | 00:21:38 | 20, 27, 28, 29, 35, 36, 37 |
| U = 20 m/s, `N h/U = 0.95`, `pbl3d_l0_opt = 0` | 02:05:54 | 19, 26, 27, 28, 35, 36 |

Both rank sets are a contiguous block centred on the mountain.

### Why it matters here

The proximate crash is upstream, but what *drives* `z/L` out of range can be ours.
In the second case above the only difference from a run that did **not** crash was
`pbl3d_l0_opt`: with the broken `l0` integral (issue A0 in `OPEN_ISSUES.md`) the master
length scale is set by the model lid rather than the turbulence, the near-surface eddy
diffusivity is far too large, and the surface-layer `z/L` goes out of range. So this
bug converts a *physics* error somewhere upstream of it into a segfault in a completely
different module, which makes any such error very hard to diagnose.

**For the Inn Valley runs this is a live hazard** regardless of which PBL scheme is
used: steep terrain plus stable stratification is exactly where `z/L` excursions happen.

### Suggested fix

One line in each of the four functions:

```fortran
-    if(nzol+1 .lt. 1000)then
+    if(nzol .ge. 0 .and. nzol+1 .lt. 1000)then
```

That routes out-of-range values to the `*_full` analytic form, which is what the `else`
branch is already for. It does not change results for any in-range value. A NaN `zolf`
would still fall through to the analytic branch and produce NaN rather than a segfault,
which is the correct behaviour — a NaN should propagate visibly, not corrupt memory.

**Applied to this fork on 2026-07-31** (all four functions), because it has now blocked
two runs. It is still a one-line *upstream* fix and should be reported to
`wrf-model/WRF`; the local carry is a stopgap, and whoever rebases next should check
whether upstream has fixed it and drop the local change if so.

---

## E1. mambaforge shadows the spack netCDF and LAPACK at both link and run time

**Severity:** high — silently produces a broken or wrongly-linked build

`/sw/spack-levante/mambaforge-*/lib` ships `libnetcdf.so.19`, `libnetcdff.so.7`,
`liblapack.so.3` and `libblas.so.3` with the **same SONAMEs** as the spack builds
`configure.wrf` links against, and mambaforge is on `PATH` by default on Levante.

Two distinct failure modes seen:

1. **Build time.** `module load ... | something` runs the `module load` in a *subshell*
   and silently discards it. `mpif90` then resolves to
   `/sw/spack-levante/mambaforge-*/bin/mpif90`, the build uses gcc 12, and the link
   fails while `./compile` still exits 0 with no executables.
   **Always redirect, never pipe:** `module load ... > /dev/null 2>&1`.
2. **Run time.** The executables are linked with `-L` but no RPATH, so
   `LD_LIBRARY_PATH` must be set explicitly at run time or `srun` fails with exit 127.
   Setting it from a `find` result is dangerous: `find /sw/spack-levante -name
   libnetcdf.so.19` returns the **mambaforge** copy first.

Correct runtime setting:

```bash
export LD_LIBRARY_PATH=/sw/spack-levante/netcdf-fortran-4.5.3-jlxcfz/lib:\
/sw/spack-levante/netcdf-c-4.8.1-6qheqr/lib:\
/sw/spack-levante/netlib-lapack-3.9.1-y24c4j/lib64:${LD_LIBRARY_PATH:-}
```

Worth asserting in any job script:

```bash
ldd wrf.exe | grep -q "not found" && exit 1
ldd wrf.exe | grep -q mambaforge && exit 1
```

Verify a build with:
`readelf -p .comment dyn_em/module_pbl3d_my.o | grep GCC`  ->  must be
`GCC: (Spack GCC) 11.2.0`, never `GCC: (GNU) 12.x`.

---

## E2. SLURM `srun --exclusive -n1` caps a step's memory and OOM-kills serial `ideal.exe`

`--exclusive` on a *job step* allocates memory in proportion to the CPUs requested, so
`srun --exclusive -N1 -n1 ./ideal.exe` gets roughly `node_memory/128` (~2 GB). Serial
`ideal.exe` holding a 120x120x65 domain with the pbl3d arrays needs more, and is
OOM-killed with no useful message.

Use plain `srun -N1 -n1` for the serial pre-processor and add `#SBATCH --mem=0`.
Keep `--exclusive` on the parallel `wrf.exe` steps, where it correctly partitions the
node between concurrent runs.

---

## E3. `pgrep -f "compile em_real"` matches its own command line

A monitor loop such as

```bash
while pgrep -f "compile em_real" >/dev/null; do sleep 30; done
```

never terminates: the monitoring shell's own command line contains the pattern, so it
matches itself. The same pattern in `pkill` kills the monitoring shell (exit 143/144).

Key on the build log instead:

```bash
until grep -q "Executables successfully built\|Problems building" build.log; do sleep 30; done
```

---

## E4. `git` is not on the default `PATH` on Levante

```bash
export PATH=/sw/spack-levante/git-2.43.7-2ofazl/bin:$PATH
```

---

## E5. `/tmp` is node-local; login nodes differ

Files written to `/tmp` on one login node are invisible from another (a session may be
on `levante4` while an interactive shell is on `levante6`). `/home` and `/work` are
shared. Anything that needs to be seen from a different shell must go there.

Related: there is no clipboard tool installed (`xclip`, `xsel`, `wl-copy` all absent),
so `/copy` in Claude Code can only write its file fallback. `~/bin/osc52` was added as
an OSC 52 helper that works over plain SSH.

---

## G1. WRF requires at least 10 grid cells per MPI patch in each direction

A 120x120 domain on 128 tasks gives an 8x16 decomposition = 7 cells in y, and WRF
aborts with

```
Minimum decomposed computational patch size, either x-dir or y-dir, is 10 grid cells.
--- ERROR: Reduce the MPI rank count, or redistribute the tasks.
```

64 tasks gives 8x8 = 15x15 and is fine. This also bounds useful scaling: past ~64 tasks
a 120x120 domain is mostly halo exchange.

---

## G2. Namelist variables must be in their Registry-declared group

A Fortran namelist read fails if a variable is not a member of the group it appears in.
The error message points at neighbouring lines, not the offending variable:

```
------ ERROR while reading namelist physics ------
Maybe here?:      isfflx                              = 2,
Maybe here?:      tke_heat_flux                       = 0.10,
```

`tke_heat_flux` belongs to `&dynamics`, not `&physics`. Rather than guessing, check
every variable at once against the Registry:

```bash
grep -E '^rconfig\s+\S+\s+<name>\s+namelist,(\w+)' Registry/Registry.EM_COMMON
```

A script that validates a whole namelist this way is worth keeping; it found the one
misplacement in a 149-line file immediately.

---

## G4. Editing `Registry.EM_COMMON` alone does not regenerate `inc/*.inc`

**Severity:** high — the build reports errors but *keeps going* and produces a stale
executable, so it is easy to miss.

`compile` regenerates `Registry/Registry` only if `Registry/Registry.EM` is newer, and
the registry program is re-run only if `Registry/Registry` is newer than the generated
`inc/*.inc`. **`Registry.EM_COMMON` is not in either dependency chain**, even though it
is where essentially every `rconfig` and `state` line actually lives. Edit it on its own
and nothing downstream notices.

The symptom is a compile error in a file that is *not* the one you edited:

```
Error: 'pbl3d_n_tau_max' at (1) is not a member of the 'model_config_rec_type' structure;
       did you mean 'pbl3d_sk_eps_max'?
make[2]: [../configure.wrf:377: module_check_a_mundo.o] Error 1 (ignored)
```

Note `(ignored)`: WRF builds with `make -i`, so this does **not** stop the build and does
**not** set a non-zero exit code. `./compile` finishes with `exit=0` and leaves the
previous `wrf.exe` in place.

After any `Registry.EM_COMMON` edit:

```bash
touch Registry/Registry Registry/Registry.EM Registry/Registry.EM_COMMON
```

and verify afterwards that the new variable actually reached the generated code:

```bash
grep -c pbl3d_n_tau_max inc/namelist_defines.inc   # must be > 0
```

Checking `main/wrf.exe`'s timestamp is not sufficient — it is relinked either way.

### The touch is necessary but NOT sufficient

Adding a field to `grid_config_rec_type` / `model_config_rec_type` / `domain` changes the
layout of derived types that essentially every module `USE`s. An **incremental** rebuild
compiles part of the tree against the old `frame/module_configure.mod` and part against
the new one, and `make -i` walks straight through the wreckage:

```
Fatal Error: Mismatch in components of derived type 'grid_config_rec_type' from
             'module_configure' at (1): expecting 'pbl3d_scalar_mix',
             but got 'pbl3d_n_tau_max'
```

Note the two directions of the same message (`expecting A but got B` in one file,
`expecting B but got A` in another) — that is the signature of a half-updated object tree,
not of a source error. Chasing the individual files is futile.

**A Registry field addition requires `./clean` before recompiling.** Not `./clean -a`,
which also deletes `configure.wrf` (and with it the `-DMTN` in `ARCHFLAGS`) and the
generated `inc/*.inc`. Plain `./clean` removes `*.o`, `*.mod`, `*.f90` and the
executables, which is exactly the scope needed. Back up `configure.wrf` anyway
(`/work/bm1236/b301097/pbl3d_test/configure.wrf.em_les_backup`).

Cost: a full rebuild is ~40-60 min on a Levante login node, against ~5 min incremental.
Changing only a *default value* or an existing variable's metadata does not change the
type layout and does not need the clean.

---

## G5. A Registry description containing an apostrophe breaks the build

The description field is emitted verbatim into generated Fortran as a single-quoted
string, so an apostrophe inside it terminates the literal:

```
state real pbl3d_qv2 ikj misc 1 Z h "pbl3d_qv2" "Water vapour variance <qv'2> ..." "kg2 kg-2"
```

produces

```
../inc/allocs_4.f90:6626:3:
 6626 |   grid%tail_statevars%Description = 'Water vapour variance <qv'2> diagnosed ...'
Error: Unclassifiable statement at (1)
```

The error is reported in a *generated* file, several thousand lines in, with no reference
to the Registry line that caused it. Write `qv^2`, not `<qv'2>`, in descriptions and
units.

---

## G6. Never run two builds in the same tree at once

Symptom:

```
f951: Fatal Error: Cannot rename module file 'module_comm_dm.mod0' to
      'module_comm_dm.mod': No such file or directory
```

`configure.wrf` sets no `J`, so WRF's own make is serial and cannot race with itself.
This error means **two `./compile` invocations were running concurrently** — easy to
cause accidentally when a background build is believed dead and a second one is started.
gfortran writes `X.mod0` and renames it to `X.mod`; the other build's `rm -f` removes the
temporary first.

Guard any scripted build with a lock file, and confirm
`ps -u $USER -o comm= | grep -cE '^(make|f951|gfortran)$'` returns 0 before starting.

---

## G3. Things that look wrong but are not

- **Variable names are uppercased in `wrfout`.** `pbl3d_t1_ratio` in the Registry
  appears as `PBL3D_T1_RATIO` in the netCDF file. Searching lowercase makes fields look
  absent when they are present.
- **`auto_levels_opt`, `dzbot`, `max_dz`, `dzstretch_s/u` are `real.exe` only.** They do
  nothing for idealized cases. Idealized cases take explicit `eta_levels` instead
  (`em_les` reads them when `eta_levels(1) /= -1`).
- **`./compile` rewrites `run/namelist.input`.** The `namelist.input.backup.*` files
  accumulating there with build-time timestamps are the stock distribution namelist
  being rotated, not user edits.
- **These `wrf_message` lines at startup are normal auto-resets**, not errors:
  `--- NOTE: bl_pbl_physics /= 4, implies mfshconv must be 0, resetting`,
  `Need MYNN PBL for icloud_bl = 1, resetting to 0`,
  `--- NOTE: RRTMG radiation is not used, setting: o3input=0`.
