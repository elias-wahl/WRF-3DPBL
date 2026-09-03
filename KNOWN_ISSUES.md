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

## U2. RRTMG-LW `taumol` species-fraction indices have upper bounds only — a NaN anywhere upstream becomes a wild read

**Status:** confirmed by disassembly of the faulting instruction; **not yet fixed**
**Severity:** high — crashes the model, and (worse) the near-miss case corrupts silently
**File:** `phys/module_ra_rrtmg_lw.F` (`taumol`, ~line 5298 onward)
**Affects:** `ra_lw_physics = 4`. Independent of the PBL scheme. `module_ra_rrtmg_sw.F`
has the same construction and should be assumed to share the defect.

### The code

```fortran
speccomb = colh2o(lay) + rat_h2oco2(lay)*colco2(lay)
specparm = colh2o(lay)/speccomb
if (specparm .ge. oneminus) specparm = oneminus   ! UPPER bound only
specmult = 8._rb*(specparm)
js = 1 + int(specmult)
...
ind0 = ((jp(lay)-1)*5+(jt(lay)-1))*nspa(3) + js   ! js used unguarded
```

The same pattern repeats for `js1`, `jmn2o` and `jpl` in every `taugbNN` band. This is
the **identical defect class as U1**: a one-sided guard on a table index.

Everything else feeding these lookups *is* clamped — `jp`, `jt`, `jt1`, `indself`,
`indfor` and `indminor` are all `min`/`max`-bounded in `setcoef` (verified by reading
it). The `specparm`-derived indices are the only unbounded ones in the routine.

### Why it is worse than it looks

`int()` of a NaN or Inf is **not** a large-but-plausible integer — on x86-64
`cvttss2si` returns `INT_MIN`:

```
int(NaN) = -2147483648   ->   js = -2147483647
int(Inf) = -2147483648   ->   js = -2147483647
int(8*(-0.5)) =      -4   ->   js =          -3
```

So the two cases behave completely differently, and only one of them is survivable
as a *diagnosis*:

| upstream value | resulting `js` | what happens |
|---|---|---|
| NaN / Inf | ~ -2.1e9 | address ~8.6 GB below the table -> **immediate SIGSEGV** |
| finite but out of range | small negative | reads just before the table -> **silently wrong radiation, no crash** |

**The segfault is the lucky outcome.** The same defect with a slightly-out-of-range
finite value produces a run that completes and is quietly wrong — the same failure mode
`realcase/README.md` warns about for `SMOIS`.

### Observed

Inn Valley `pbl3d` smoke run, MUSICA job 88703, 2026-08-19. Crashed at model time
2025-07-18_01:38:00 (step 1141, which is a radiation step: `radt=1`, `dt=2` -> `stepra=30`,
and radiation fires on `mod(itimestep-1,stepra)==0`). **81 of 190 ranks segfaulted
simultaneously at the byte-identical instruction** `0x24fcd83`
(`__rrtmg_lw_taumol_MOD_taumol+0x2fd3`, `movss -0x24(%r12),%xmm14` — the
`X(j+1)-X(j)` interpolation on the fastest-varying dimension). Backtrace:

```
__rrtmg_lw_taumol_MOD_taumol
__rrtmg_lw_rad_MOD_rrtmg_lw
__module_ra_rrtmg_lw_MOD_rrtmg_lwrad
__module_radiation_driver_MOD_radiation_driver
__module_first_rk_step_part1_MOD_first_rk_step_part1
solve_em_ / solve_interface_
```

That 81 ranks fault at one address is itself the evidence for the NaN branch of the
table above: a finite bad index would not fault at all, let alone identically.

The failing ranks form a contiguous block that matches **where cloud and precipitation
were spinning up**, not where terrain is steepest (SEGV patches average 1360 m terrain vs
1223 m for surviving ones, and their *max* terrain is lower). The run initialises
cloud-free and clouds develop over the first half hour:

| model time | cloudy columns | max QCLOUD | max QRAIN |
|---|---|---|---|
| 01:00 | 0 | 0 | 0 |
| 01:10 | 6537 | 1.05e-3 | 2.51e-6 |
| 01:20 | 7185 | 1.47e-3 | 2.32e-5 |
| 01:30 | 8317 | 1.25e-3 | 1.35e-4 |

State variables were still **fully finite** in the 01:30 history frame (0 non-finite in
`T`, `QVAPOR`, `P`, `PH`, `U`, `V`, `W`), so whatever goes non-finite does so in the
final 8 minutes.

### What is not yet established

**Which physics produces the NaN.** `qv1d` is clamped (`max(0.,...)`, then
`AMAX1(...,1.E-12)`) in the RRTMG driver, so it is not simply negative water vapour
arriving from advection. Three candidates, and all three are exercised here for the
first time — see the `OPEN_ISSUES.md` entry.

### Suggested fix

Guard the index rather than the fraction, in every band, so a NaN cannot become a
pointer:

```fortran
-        js = 1 + int(specmult)
+        js = min(8, max(1, 1 + int(specmult)))
```

As with U1, this routes a bad value to a valid table entry instead of corrupting memory.
It changes nothing for in-range values. Note this makes a NaN propagate as a NaN through
the radiative tendency (visible) rather than crashing — which is the correct behaviour,
but means it must be paired with an actual check on the state, not treated as a fix for
the underlying physics.

---

## U3. Noah-MP (WRF 4.8 driver) passes an undefined albedo (-9999) to radiation; with topographic shading RRTMG-SW then cools shaded columns at 80 K h^-1

**Status:** measured 2026-08-21 (VSC-5), **fixed locally 2026-08-21**
(`phys/module_surface_driver.F`, commit `1fc2fa464`), **not yet reported upstream**
**Severity:** high — no crash, no warning; the model runs on with a short-wave heating
rate two orders of magnitude too large and of the wrong sign over shaded terrain
**Files:** `phys/noahmp/drivers/wrf/EnergyVarOutTransferMod.F90:140` (4.8, unguarded);
`phys/module_sf_noahmpdrv.F:1231` (4.6, guarded: `IF (SALB > -999)`)
**Affects:** `sf_surface_physics = 4` (Noah-MP) together with `topo_shading = 1`, and any
short-wave scheme that consumes `ALBEDO` (`ra_sw_physics = 4` here). Nothing about this is
specific to `pbl3d` — any PBL scheme reproduces it.

### The code

The refactored 4.8 driver copies the Noah-MP albedo out unconditionally:

```fortran
 NoahmpIO%ALBEDO(I,J) = AlbedoSfc      ! EnergyVarOutTransferMod.F90:140
```

`AlbedoSfc` is the undefined marker **-9999** wherever the land surface receives no
short-wave — the albedo is simply not defined without an incident beam. WRF 4.6's driver
never let that leave the surface scheme:

```fortran
 IF (SALB > -999) ALBEDO(I,J) = SALB   ! module_sf_noahmpdrv.F:1231
```

At night the marker is harmless: the sun is below the horizon and the short-wave scheme is
not called. **With working topographic shading it is not**: a shaded cell has
cos(zenith) > 0, so RRTMG-SW runs there and reflects `-9999 x` the diffuse beam.

### Observed (run 8478327, 2025-07-18, Inn valley, 300 000 columns)

| quantity at 07:00 UTC (09:00 local) | value |
|---|---|
| columns with `ALBEDO` = -9999 and cos(zenith) > 0 | **27 740** (9.3 % of domain), all land, median terrain 1660 m |
| their `SWDOWN` | median 16 W m^-2 (diffuse only — they are in terrain shadow) |
| diffuse surface flux there | **-480 W m^-2**; slope-normal -127 W m^-2 |
| `RTHRATEN` (potential-temperature radiative tendency, K h^-1) | median ~0, 1st percentile **-85**, extreme **-232** (at 04:00: -0.15 / -2) |
| cooling profile | **-80 K h^-1** at the surface, -40 K h^-1 at 750 m AGL, smooth |
| clouds in those columns | only 17 % have any |
| lit land `ALBEDO` for comparison | 0.145 |

`ALBEDO < 0` on **every** land cell with `SWDOWN` < 50 W m^-2: all land at night
(297 582 at 03:00, harmless), then 55 011 at 05:30 and 39 859 at 07:00 after sunrise. The
cold cells (`T2` < 270 K) are a subset of the shaded ones: 1 222 of 1 391 at 05:30,
13 713 of 20 933 at 07:00.

The stock 4.6.0 MYNN control (job 8320565) never meets the case — no negative albedo — and
its topographic shading is *effectively inert*: 196 shaded land cells at 07:30 local and 0
at 09:00, against 55 000 / 40 000 here. That is implausibly few for this valley, so the
**control's morning insolation is itself suspect** and is not a clean reference after
sunrise either.

### Reproduction

`sf_surface_physics = 4`, `topo_shading = 1`, any PBL scheme, real terrain with slopes that
shade after sunrise. In any post-sunrise frame compare the count of land cells with
`ALBEDO < 0` against the count with `SWDOWN < 50 W m^-2`: they coincide. Then read
`RTHRATEN` in the same columns — a 4.6 run has O(1) K h^-1 there, a 4.8 run O(-80).

### The fix carried here

At the point where the value enters WRF, `phys/module_surface_driver.F`, immediately after
the Noah-MP call:

```fortran
 IF (ALBEDO(I,J) < 0.) ALBEDO(I,J) = ALBBCK(I,J)
```

`ALBBCK` is the background (climatological) albedo. The lit value is not available at that
point, and the short-wave in such a cell is a few W m^-2 of diffuse light, so the fallback
is immaterial to the energy budget. **No namelist switch**: the previous behaviour is not a
physics choice, it is garbage radiation. The nocturnal reference is unaffected — `ALBEDO`
changes in the output at night, not in the physics, because no short-wave is computed.

Upstream this belongs in the driver: restore the 4.6 guard in
`EnergyVarOutTransferMod.F90`, or define `AlbedoSfc` from the background albedo when no
beam is incident.

### What it explained

Everything the 3D-closure runs did after ~04:00: the shaded high terrain cooling instead of
warming, a 2 m temperature 11 K below the control at the first percentile by 07:00, fog and
low stratus over 10 % of the cells (which then shade further cells), skins decoupled from
the air, cold air draining at 15-25 m s^-1, and the 07:54 column collapse with the
surface-layer NaN. None of it was closure physics — see `OPEN_ISSUES.md` A12/A13. The
nocturnal results are untouched, since no short-wave is used at night.

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

## E6. EESSI's own init chain is not `nounset`-safe — breaks any script sourcing an env file under `set -u`

**Severity:** high — the build script exits after one line of output, with no error
message printed, which looks like a hang or a silent crash rather than what it is.

`realcase/scripts/build_em_real.sh` and `setup_rundir.sh` both start with
`set -u -o pipefail` and then source the cluster env file. On MUSICA that env file's
first line is `source /cvmfs/.../init/bash`, which chains into
`init/eessi_environment_variables` -> `init/minimal_eessi_env` -> `init/eessi_defaults`.
That last file references `EESSI_VERSION_OVERRIDE` with no default:

```
/cvmfs/.../init/eessi_defaults: line 14: EESSI_VERSION_OVERRIDE: unbound variable
```

Under `set -u` this is fatal and the sourcing shell exits immediately — silently, because
the error text goes to stderr of a redirected/logged pipeline and is easy to lose (e.g.
`build_em_real.sh ... 2>&1 | tee log` inside a `tmux new-session -d "..."` swallows it
entirely if the pane closes before the log flushes). The symptom is a build log
containing only `=== environment: <envfile>` and nothing after.

**Fix applied 2026-08-19** to both `build_em_real.sh` and `setup_rundir.sh` (the latter
in two places: its own direct sourcing, and the `env.sh` it generates for
`submit_real.slurm`/`submit_wrf.slurm`, which also run under `set -u`): wrap the env-file
sourcing in `set +u` / `set -u`, e.g.

```bash
set +u
. "$ENVFILE"
set -u
```

This is an EESSI-side bug (or at least an undocumented assumption that consumers don't
run `set -u`), not something to fix in the env file itself — `musica.sh` never referenced
the unbound variable; it only sourced something that does. Re-check this if EESSI is
upgraded past 2025.06.

---

## E7. No `/usr/bin/time` on MUSICA — every `./compile` object silently fails to build

**Severity:** high — same failure mode as G4: `make -i` ignores it, `./compile` exits 0,
and the build looks like it ran for the full 30-60 min while producing zero `.o` files.

WRF's `./compile` prefixes every single compiler invocation with `time` (for the
per-file build-time logging in the log), e.g. `time mpif90 -o module_comm_dm_4.o -c ...`.
MUSICA has no `/usr/bin/time` (or any GNU `time` binary) anywhere on `PATH`. Because that
recipe line has no shell metacharacters, GNU Make applies its direct-exec optimization
and `execvp`s `time` as a literal program instead of going through a shell (where `time`
would be a builtin keyword) — so it needs an actual binary on `PATH`, not just a shell
that understands the word. Every compile line then fails with:

```
make[2]: time: No such file or directory
make[2]: [../configure.wrf:376: module_comm_dm_4.o] Error 127 (ignored)
```

`build_em_real.sh`'s own verification caught this correctly on the first attempt
(reported `BUILD FAILED`, no `main/wrf.exe`) rather than falsely reporting success — but
700 Error-127 lines and a full run through `./compile` were needed to reach that point,
and a plain `./compile em_real; echo $?` would have shown `0` and hidden it entirely.

**Fix applied 2026-08-19:** a two-line `time` shim at `~/bin/time` (which is on `PATH`)
that just `exec`s its arguments, dropping the timing report:

```bash
#!/bin/sh
exec "$@"
```

Confirmed to close the gap: re-running the same build afterward showed 0 `Error 127`
lines and objects accumulating normally. `~/bin` is not part of this repo, so a fresh
account/cluster needs this shim recreated — check for it before assuming a `./compile`
run that reports "Executables successfully built" is trustworthy without it.

---

## E8. EESSI's compat layer trips `build_em_real.sh`'s mixed-GCC check — false positive, not KNOWN_ISSUES E1

**Severity:** medium — the build itself is fine; only the automated verdict is wrong,
and it says `BUILD FAILED` even though `real.exe`/`wrf.exe`/`ndown.exe` all linked.

`build_em_real.sh`'s toolchain check (added to catch the real VSC-5 mambaforge
contamination in E1) ran `strings main/wrf.exe | grep 'GCC: (...)'` and failed the
build because it found two GCC signatures: `GCC: (GNU) 13.3.0` (the GCCcore module
used to build WRF, correct) and `GCC: (Gentoo 13.4.0 p5) 13.4.0`. The second one is
**not application-code contamination** — `ldd main/wrf.exe` shows `libgfortran.so.5`,
`libgcc_s.so.1`, `libc.so.6` etc. all resolving into
`/cvmfs/.../compat/linux/x86_64/...`, EESSI's compat layer, which is deliberately
built with its own (Gentoo Prefix) toolchain, separate from the GCCcore modules used
for application software. The final binary statically links C runtime startup
objects (`crt1.o` etc.) from that layer, which legitimately carry its GCC signature.
This is expected EESSI architecture, not a build defect.

Verified before concluding this, not assumed: scanned every `*.o` file compiled
during the build (`find . -name '*.o' -newer configure.wrf | xargs strings | grep
'GCC:'`) — 100% show only `GCC: (GNU) 13.3.0`, including the `io_grib1`
bare-`gcc`-invoked C files that were the actual failure mode in E1. Zero objects
carry the Gentoo signature; it only appears once everything is linked together.

**Fix applied 2026-08-19:** `build_em_real.sh`'s toolchain check now scans `find . -name
'*.o' -newer configure.wrf | xargs strings` (our own compiled objects) instead of
`strings main/wrf.exe` (the linked binary). This is also a strictly better test for
what E1 actually cares about — whether *our* compilation was toolchain-consistent —
and no longer false-positives on EESSI's two-tier compat-layer design. If a future
build genuinely mixes toolchains in application code (the real E1 scenario), this
version of the check still catches it.

---

## E9. MUSICA has no devel *partition* — `dev_zen4_0768` is a QOS, and `--qos` is not optional

**Severity:** high — a job submitted the way `CLAUDE.md`/`MIGRATION_MUSICA.md` originally
described (`--partition=dev_zen4_0768` for smoke tests) is rejected by `sbatch` outright,
and a job submitted with no `--qos` at all is *also* rejected, not silently defaulted.

`sinfo -a` / `scontrol show partition` on MUSICA list exactly three partitions:
`musica_login`, `zen4_0768`, `zen4_0768_h100x4`. There is no `dev_zen4_0768` partition.
"devel" here is a **QOS** layered on top of `zen4_0768`
(`scontrol show partition zen4_0768` → `AllowQos=admin_musica_inn,dev_zen4_0768,
fast_zen4_0768,idle_zen4_0768,long_zen4_0768,zen4_0768`), and `sacctmgr show qos` shows
`dev_zen4_0768` capped at `MaxWall=00:10:00`, `MaxTRESPU=node=2`.

Separately: `zen4_0768`'s `AllowQos` list does not include the default `normal` QOS, so
any `sbatch` script that (like the shipped `submit_real.slurm`/`submit_wrf.slurm`
templates) only sets `--account`/`--partition` and never `--qos` fails at submission —
this project's SLURM templates never had a `--qos=` line at all before this was found,
because neither Levante nor VSC-5 needed one explicitly.

**Practical consequence for smoke tests:** the 10-minute cap on `dev_zen4_0768` is a real
hazard for a `pbl3d` smoke run specifically, because the whole point of a smoke run is
that its per-step cost is *not yet known* — if it is slow, the job is killed by the QOS
wall limit before `wrf.exe` prints the mean s/step, wasting the run. Prefer the plain
`--qos=zen4_0768` (3-day cap, no node cap; see `sacctmgr show qos`) with an explicit
`--time` bound for the first, unmeasured smoke run; `dev_zen4_0768` is fine once a rough
per-step cost is already known and the run is expected to comfortably finish in 10 min.

**Fix applied 2026-08-19:**
- `realcase/env/musica.sh`: `SLURM_PARTITION_DEVEL` now points at `zen4_0768` (there is
  no separate partition to point at); added `SLURM_QOS_DEVEL=dev_zen4_0768` and
  `SLURM_QOS_DEFAULT=zen4_0768`.
- `realcase/scripts/submit_real.slurm` / `submit_wrf.slurm` (the templates
  `setup_rundir.sh` copies into every run directory): added a `#SBATCH --qos=CHANGEME`
  line to the edit-before-running block, plus a MUSICA-specific comment block explaining
  the above.
- `branko_runs/innval_pbl3d_smoke/submit_real.slurm` / `submit_wrf.slurm`: filled in
  directly for this smoke run (`--account=p201110 --partition=zen4_0768
  --qos=zen4_0768`, one node, `--ntasks-per-node=192 --hint=nomultithread`).

---

## E10. MUSICA's "full cpu node" policy grants 190 cores/node, not 192 — OpenMPI refuses to bind the rest

**Severity:** high — fails at MPI launch, before `real.exe`/`wrf.exe` does anything,
with no useful information beyond an OpenMPI binding error.

MUSICA's `zen4_0768` nodes have 192 physical cores (CLAUDE.md, `musica.sh`'s own
comments), but requesting `--ntasks-per-node=192` on an exclusive-node allocation
fails at `mpirun`/`srun` launch:

```
A request was made to bind to that would result in binding more
processes than cpus available in your allocation:
   Application:     ./real.exe
   #processes:      192
   Binding policy:  CORE
```

`sbatch` itself warns about this at submission time and is easy to miss among the
other job-submit output:

```
sbatch: applying job settings for >> full cpu node(s) <<
sbatch: setting --ntasks-per-node=190
```

The site's job-submit plugin silently reserves 2 cores/node for OS overhead on a
full/exclusive-node allocation, so the allocation actually granted only has 190 usable
slots — but `$SLURM_NTASKS` (and therefore `mpirun -np $SLURM_NTASKS`) still reflects
whatever `--ntasks-per-node` was requested in the `#SBATCH` header, not what was
silently granted. Request 192 and the mismatch surfaces at MPI launch, after the job
has already waited in queue.

**Fix applied 2026-08-19:** `--ntasks-per-node=190`, not `192`, in both
`realcase/scripts/submit_real.slurm`/`submit_wrf.slurm` (the templates) and this run's
`branko_runs/innval_pbl3d_smoke/submit_real.slurm`/`submit_wrf.slurm`. Re-check this
number if MUSICA's job-submit policy ever changes, or on any partition other than
`zen4_0768`.

---

## E11. Stale VSC-5-path symlinks in a run dir survive `setup_rundir.sh` reruns and only fail deep into `wrf.exe`, not `real.exe`

`setup_rundir.sh` links every file in `$WRF/run/*` into the run dir
(`ln -sfn "$f" "$RUNDIR/$b"`), which correctly re-points anything that exists
in the source `run/` tree on every rerun. It does **not** remove entries in
the run dir that aren't in that loop's source list — so any file placed there
by something else (an older version of this script, a bulk copy, a prior
migration pass) survives untouched across every later `setup_rundir.sh`
rerun, including the "corrected, fixed the E6-E10 bugs" reruns done on
MUSICA in this session.

`branko_runs/innval_pbl3d_smoke` had exactly this: four symlinks dated
2026-08-17 (two days before this session's build), all pointing into the
unreachable VSC-5 path `/gpfs/data/fs72996/ewahl/branko/run/...` —
`freezeH2O.dat`, `qr_acr_qs.dat`, `qr_acr_qg.dat`, `namelists`. None of the
four exist in this checkout's `branko/run/` (confirmed: `qr_acr_qs.dat` /
`qr_acr_qg.dat` aren't even referenced by `module_mp_thompson.F` — they
belong to a different microphysics scheme — and `freezeH2O.dat` is never
shipped as a static file; Thompson MP computes and caches it on first use).

The trap: `real.exe` never opens any of these, so `check_wrfinput.py` and
the whole `real.exe` smoke stage passed clean. The dangling symlink only
surfaced when `wrf.exe` actually initialized Thompson MP microphysics
(`mp_physics=8`), immediately (`FATAL CALLED ... Error writing
freezeH2O.dat`, MPI_ABORT, <1 min wall time) — `INQUIRE` on a broken symlink
correctly reports `exist=.false.`, so the code takes the compute-and-write
branch, then `OPEN(63,file="freezeH2O.dat",...)` follows the symlink into
the unreachable VSC-5 mount and the `WRITE` fails.

**Fix applied 2026-08-19:** `rm` the four dangling symlinks directly (they
are not managed by `setup_rundir.sh`'s loop, so removing them is safe and
permanent — the next `wrf.exe` run creates a real `freezeH2O.dat` in the run
dir itself). If setting up a **new** run dir from an old one (rather than
fresh via `setup_rundir.sh`), check for broken symlinks first:
`find <rundir> -maxdepth 1 -xtype l`. `branko_runs/innval_pbl3d_18th/` is
already flagged elsewhere as having dangling VSC-5 symlinks throughout —
recreate it with `setup_rundir.sh` rather than hand-repairing it, per the
same reasoning.

---

## E12. WRF's `phys/` Makefile dependencies are incomplete — a parallel `./compile -j N` races

**Severity:** high — the loud failure wastes a build; the quiet failure produces a subtly
wrong binary
**Observed:** MUSICA, 2026-08-19, job 89218, `./compile -j 16 em_real`, failed after 4.5 min

`./compile` accepts `-j N` and passes it to `make`, which makes a 30-60 minute serial
build look like an easy 10-minute win. It is not reliable in this tree:

```
Fatal Error: Cannot open module file 'ccpp_kind_types.mod' for reading
Fatal Error: Cannot open module file 'bl_shinhong.mod' for reading
Fatal Error: Cannot open module file 'module_bl_shinhong.mod' for reading
Fatal Error: Cannot open module file 'module_physics_init.mod' for reading
Fatal Error: Cannot open module file 'module_pbl_driver.mod' for reading
Fatal Error: Cannot open module file 'module_first_rk_step_part1.mod' for reading
...then at link: undefined reference to `__module_bep_bem_helper_MOD_nurbm'
```

This is the standard Fortran parallel-build race: a source file is compiled before the
`.mod` produced by the module it `USE`s has been written. **Every module that raced is a
stock WRF `phys/` module** — `ccpp_kind_types`, `bl_shinhong`, `module_pbl_driver`,
`module_physics_init` — so this is WRF's own dependency graph being incomplete and relying
on serial ordering. It is **not** caused by the `pbl3d` sources this fork adds, and
lowering `-j` will not fix the underlying graph, only make the race less likely to be hit.

### Why this matters more than a wasted build

A missing `.mod` fails loudly, which is the *good* case. The same race can also compile a
file against a `.mod` that is being written concurrently, yielding an object that links
cleanly and runs but is subtly wrong. This tree exists to diagnose a numerical instability
(`OPEN_ISSUES.md` A9); a miscompiled binary would corrupt exactly the evidence being
gathered, and would be very hard to distinguish from a real physics result.

For the same reason, **do not resume a raced build** by re-running `./compile` without
cleaning to "just fill in the missing objects". The objects already on disk were produced
under the race and cannot be trusted. `./clean` first.

**Fix applied 2026-08-19:** `build_em_real.sh` defaults to `WRF_BUILD_JOBS=1` (serial) and
documents why inline. The variable still exists so the behaviour can be re-tested if
upstream ever fixes the `phys/` dependencies, but the default must stay serial.

The legitimate way to speed this up is **not** `-j`: use
`realcase/scripts/build_em_real.slurm`, which builds on an exclusive compute node instead
of a contended login node, and survives losing the session without tmux.

---

## E13. `build_em_real.sh` appended FlexiBLAS to `LIB_LOCAL` on every rebuild

**Severity:** low — cosmetic, but unbounded, and it hides a real detection gap
**Observed:** MUSICA, 2026-08-19, after three rebuilds `LIB_LOCAL` carried
`-lflexiblas` (with its `-L` and `-Wl,-rpath`) **three times**

The `configure.wrf` patch step decided whether LAPACK was already present by sniffing
library *names*:

```python
if 'lapack' in cur or 'mkl' in cur or 'openblas' in cur:
    ...leave alone
else:
    ...append $LAPACK_LIBS
```

`flexiblas` matches none of those three, so the check never fired on MUSICA and every
single rebuild appended another full copy. Harmless to the link — `ld` tolerates repeated
`-l` — but it grows without bound across rebuilds and would eventually be a genuine
problem for command-line length, quite apart from making `configure.wrf` unreadable.

Worth noting *why* it went unseen: it only bites on a toolchain whose LAPACK is named
something other than the three sniffed strings, i.e. exactly the FlexiBLAS situation that
`DECISIONS.md` records as new for this cluster. On Levante and VSC-5 the sniff worked.

**Fix applied 2026-08-19:** test for the exact `$LAPACK_LIBS` string already being present
in `LIB_LOCAL` rather than guessing at library names, keeping the name sniff (now with
`flexiblas` added) only as a fallback for the case where `configure.wrf` already carries a
*different* LAPACK. The accumulated triple entry in the existing `configure.wrf` was
de-duplicated in place (9 tokens -> 3).

---

## E14. WRF is not bit-reproducible here across MPI decompositions, nor after any last-bit arithmetic change

**Severity:** medium — it does not break a run, it breaks the *comparison method*
**Observed:** VSC-5, 2026-08-21, smokes 8477302 / 8477313 against job 8476273

Two smoke runs of the same source at 640 ranks (5 nodes, devel QOS) were compared with the
256-rank reference run of job 8476273. All three start from an identical 01:00 state. After
**ten minutes of model time** they differ by up to **0.6 m s^-1 in `U`**, spread over the
whole domain rather than confined to any one region.

The trigger was found and removed — one factor of the strain-cap bound in
`dyn_em/module_pbl3d_my.F` had been rewritten from single to double precision, reverted in
commit `16fa7407b`. But the removal did not restore reproducibility across rank counts:
**two 640-rank smokes with and without that change differ from each other as much as either
differs from the 256-rank reference.** So the precision edit was not special; any change in
the last bit does this.

Amplification is fast and local. Attributed (**inferred**) to the closure's own discrete
backstops — the length-scale halving on solver distress, the realizability projections, the
floors — each of which is a branch, so a last-bit difference flips a cell to a different
branch and the O(1e-16) perturbation becomes O(0.1-1 m s^-1) in a few hundred timesteps.
This is a property of a branchy closure in a chaotic flow, not a bug.

**Consequences for how runs are compared:**

- Compare runs **statistically** — stratified means, medians, distributions by slope bin,
  height bin, Richardson-number bin. Never cell by cell, never a single column, never a
  point time series, unless both runs used the identical decomposition *and* identical
  arithmetic.
- A "the fix changed the answer" check must hold decomposition and rank count fixed. The
  2026-08-21 validation did: same 2 nodes x 128 ranks as job 8476273, and the 01:30 frame
  then matched **bit for bit** (max difference exactly 0 in `U`, `V`, `W`, `T`, `Q_SQ`,
  `L_MASTER`, `PBL3D_T1_RATIO`).
- A devel-QOS smoke on 5 nodes is fine for "does it run", useless for "does it reproduce".

---

## E15. `auxhist24_interval = 0` does not switch the WRFlux averaged stream off — it aborts the run at start

**Severity:** low — fails loudly and immediately, but the message names a variable that was
never set by hand
**Observed:** VSC-5, 2026-08-21, while preparing the six experiment namelists

Setting `auxhist24_interval = 0` looks like the natural way to disable the averaged output
stream for a run that does not need it. WRF instead aborts in `module_check_a_mundo` at
initialisation, because WRFlux requires

```
avg_interval <= auxhist24_interval
```

and `avg_interval` is still at its template value. The check is correct; the trap is that
`0` reads as "off" everywhere else in a WRF namelist and here reads as an interval of zero.

**Either** leave the stream enabled with an interval longer than the run (360 min was used
for the 6 h experiments, so exactly one frame is written), **or** turn off the
`output_*_fluxes` flags, which is what actually stops WRFlux from doing the work. The
namelist template says so in a comment above the variable — read it before editing.

---

## E16. A pending job whose `wrf.exe` is a symlink into `main/` fails at start if a rebuild is running

Run directories link `real.exe`/`wrf.exe` into `branko/main/` on purpose (a rebuild is picked up
without redoing the run dir). The flip side: `build_em_real.sh` runs `./clean -a`, which removes
`main/*.exe` for the whole 30-60 min of the build, and a queued job that gets backfilled in that
window dies in `mpirun` with "Executable: ./wrf.exe ... while attempting to start process rank 0"
— job 8478217 (2026-08-21 11:04, the morning-runaway diagnosis restart) did exactly that, 23 min
into a reconfigure. Before starting any rebuild: `scontrol hold <jobid>` every pending job that
links the binary (release after `BUILD OK`), or copy the executables into the run dir for runs
that must not move with the tree. Resubmit the casualty; nothing in the run dir is damaged.

---

## E17. A restart ignores a newly added output stream unless `override_restart_timers = .true.`

**Severity:** high — the run succeeds, writes nothing, and costs its whole wall time
**Observed:** VSC-5, 2026-08-21, adding the 1-minute q^2 budget stream to the morning-runaway
diagnosis restart

WRF stores the output timers (alarms) of every stream in the restart file and restores them on
restart. A stream that did not exist when the restart file was written has no stored alarm, and
WRF does not create one from the namelist: the stream simply never opens. `auxhist23_interval`,
`auxhist23_begin_m`, `iofields_filename` and the `io_form` are all read and all ignored.

Job 8478325 ran the full 1.6 h from the 04:00 restart file, exited cleanly, and wrote **zero**
1-minute frames — no error, no warning in `rsl.error.0000`, only the missing `qsqdiag_*` files.

The fix is one namelist line in `&time_control`:

```
override_restart_timers = .true.
```

which makes WRF rebuild every alarm from the namelist instead of the restart file. Devel-QOS job
8479232 confirmed it: frames appear from `auxhist23_begin_m` onward. `branko_runs/innval_pbl3d_A12`
carries the line, and the comment above the variable in the namelist template now says why.

Note the scope: this affects the *timers*, so it also re-arms `history_interval` and
`restart_interval` from the namelist — intended here, but check the other streams' intervals in the
same file before setting it.

---

## E18. A physically impossible tendency in a WRFlux budget term is worth an hour on the raw model array

**Severity:** none to the model — this is a diagnostic habit that saved a week
**Observed:** VSC-5, 2026-08-21, tracking the morning failures down to `U3`

The WRFlux θ budget of the fog layer (06:30-07:00, run 8478327 against the MYNN control)
showed a **short-wave radiative tendency of -10 to -14 K h^-1** through the lowest 750 m,
in cloud-free high-terrain columns as much as under the fog, where the control had
+0.06 K h^-1. Short-wave radiation cannot cool. That single impossible sign — not any
turbulence quantity — was the whole lead: the next step was the raw `RTHRATEN` array in the
07:00 restart file (1st percentile -85 K h^-1), then the columns it lived in (all land, all
in terrain shadow), then `ALBEDO` in those columns (-9999). About an hour from the budget
term to the upstream bug, after two days of interpreting the same fields as closure physics.

Two practical points:

- **The restart files carry the diagnostic arrays** — `RTHRATEN`, `ALBEDO`, `SWDOWN`,
  `SWDDIF`, `TSK`, `HFX` — at full precision and at `restart_interval` (180 min here), so
  a suspicious tendency can be traced without re-running anything.
- **When a morning goes cold, check `ALBEDO < 0` against `SWDOWN < 50 W m^-2` first**
  (`U3`). It is one line of Python and it decides immediately whether the radiation or the
  physics is at fault.

The general rule: in a budget, trust the term whose *sign* is impossible over the term whose
*magnitude* merely looks wrong. A magnitude can be a closure being bad at its job; an
impossible sign is a bug, and it points at a specific array.

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

## E19. A continuation built with `setup_restart_run.sh` silently carries the template's `pbl3d_init_opt=1` / `pbl3d_l0_min=8.0` and `restart_interval=0`

**Symptom.** A restart segment meant to continue an X-run (`pbl3d_init_opt=0`, `pbl3d_l0_min=0.0`,
restarts every 180 min) comes out with the asymptotic-length floor **on** (8 m — a physics change
in the stable regime) and writes **no** restart file, so the next segment cannot start.
Found 2026-08-22 on the first segment of the 23 h run, before it started.

**Cause.** `setup_restart_run.sh` builds from `realcase/namelist.input.pbl3d`, whose template
values since 2026-08-20 are `pbl3d_init_opt=1`, `pbl3d_l0_min=8.0`; the X runs override them to
0 / 0.0 in `setup_experiments_20260820.sh`. The restart tool's own default `restart_interval`
is 0 (diagnosis runs do not need restarts) and it overwrites the template's 180.

**Rule.** For any continuation of the X configuration pass
`--set restart_interval=180 --set pbl3d_init_opt=0 --set pbl3d_l0_min=0.0` (done in
`chain_segment.slurm`), and diff the segment's namelist against the parent run's before
submitting — everything except dates, `run_hours`, `restart*` and the output paths must be
identical. `pbl3d_init_opt` is inert on a restart (q² comes from the file); `pbl3d_l0_min` is not.

## E20. `setup_restart_run.sh` aborts on an unknown `--set` key *after* writing the namelist but *before* patching the SBATCH header — a manual `sbatch` then runs the template layout

Observed 2026-08-23: `--set auxhist23_begin_m=5` (key not in the template) made the script
exit at "!!! namelist key not found" with the namelist half-configured and
`submit_wrf.slurm` still carrying the template's **8 nodes** and QOS. Submitting that by
hand produced a run on 8x128 that "survived" a crash five 2x128 runs reproduce
bit-identically — a day-grade non-determinism scare that was actually E14
(decomposition sensitivity). Rule: after any script abort, do not `sbatch` by hand until
`grep -E "nodes|qos|time" submit_wrf.slurm` matches the intent; the script only patches the
header in its final phase (look for its "=== SBATCH header" section in the output).
Missing begin keys are inserted into the namelist manually (`auxhist23_begin_m/_s` are
valid WRF keys; the script simply cannot `--set` keys absent from its template).

## E21. `setup_restart_run.sh` pointed the namelist at the default `iofields_lscale.txt` without linking it into the run dir — per-rank "Problem opening" warnings, and the file's `-:` removals silently never apply

Observed 2026-08-24 on X9a/X9b (both built by `chain_segment.slurm`, which passes no
`--iofields`): 62 `W A R N I N G : Problem opening iofields_lscale.txt` lines in
`rsl.out.0000`, run otherwise healthy. Science impact none — every field the file *adds*
is already a Registry history field — but the `A*TEN` accumulated-tendency removals did
not apply, so the wrfout frames are ~10 % fatter than budgeted (7 GB vs 6.4 GB) on a
filesystem at 95 %. The symlink was only created in the explicit `--iofields` branch;
fixed 2026-08-24 (the default file is now linked too). Rule: any "Problem opening" for an
iofields file means the *whole* file was inert, removals included — check frame sizes,
not just field presence.

## E22. A 3D-PBL run carries MYNN's `QKE`, `TKE_PBL`, `EL_PBL` as all-zero fields — any name-based reader that asks for `QKE` gets a valid, silent zero

Observed 2026-08-27 on the stitched day `wrf_output/9999999`: `QKE` max 0 at 04:00 and
13:00 while `Q_SQ` (q², twice the TKE, face levels) is 13.8 / 16.1 m² s⁻². The Registry
still allocates the MYNN arrays under `pbl3d_used`, so they exist with the right name,
dimensions and units and are never touched. `$DATA/proc` (`wrf-proc`) read subgrid TKE
only via `QKE` and drops unknown names silently — every `3dpbl` TKE figure it produced
before 08-27 (the 08-24 Kolsass TKE-lidar comparison) is a zero curve; withdrawn. The
station comparison uses no TKE and stands. Fixed in `proc/util/wrf.py`
(`"qke": ["Q_SQ", "QKE"]`) and `proc/vars.py` (budget names, 0.5 factor). Rule: before
any turbulence panel from a 3D run, check `max(field) > 0`; `compare_mynn.py` reads
`Q_SQ`/`L_MASTER` directly and was never affected. The same applies to `EL_PBL`
(use `L_MASTER`) and to the MYNN budget names (`Q_SQ_SHEAR` etc., rates of q²).

## E23. Inside the 3D closure, `q_sq_prog` is a temporary copy — writing a value into it is silently inert

**Symptom.** A lower boundary condition on q² written as a clamp on `q_sq_prog(i, kts, j)` in the
closure driver (or in `Fill_q_sq_with_q_sq_prog`) compiles, runs, and changes nothing.

**Cause.** `module_first_rk_step_part2.F:1263` hands `Calc_turb_fluxes_driver` `q_sq_prog = grid%q_sq_tmp`,
a per-step copy of `q_sq_prog_2` made by `Update_wrf_tends_temp_state_and_zero_tends`; the copy is
discarded. Only `q_sq_tend` (μ-coupled, `(c1 μ + c2) · S / pbl3d_nsteps` for a kinematic source `S`)
reaches `rk_scalar_tend`. The MYNN analogue (`qke` set in place) does not carry over because `qke`
is a physics state, not an RK-advected dyn_em variable.

**Rule.** Any condition on q² that must survive the step is a tendency in `Calc_q_sq_rhs` (the
2026-08-27 surface condition `pbl3d_sfc_qsq_bc` is written that way, after the dissipation term,
before the tendency bound). A Dirichlet value on the *face* array `q_sq(kts)` is inert too: the
ground flux in `Calc_q_sq_vertical_diffusion` is hard zero.

## E24. `setup_restart_run.sh --set key=val` only patches keys that already exist in `namelist.input.pbl3d`

**Symptom.** `--set pbl3d_sq=0.6` for a freshly added Registry key aborts with `namelist key not
found: pbl3d_sq` (E20's failure point), although the binary knows the key.

**Cause.** `sedset` edits the generated namelist in place and refuses unknown keys by design (a
typo must not pass silently). The template is the whitelist.

**Rule.** Every new `rconfig` key gets a line in `realcase/namelist.input.pbl3d` (and `.mynn`
where it applies) with its default and a one-line comment, in the same commit as the Registry
change; `prepare_namelist.py` gets its range check in the same commit. Done for `pbl3d_sq`,
`pbl3d_sfc_qsq_bc`, `pbl3d_sfc_qsq_zmax`, `output_tke_moments` (2026-08-27).

## E25. `setup_restart_run.sh` never wrote `#SBATCH --hint=nomultithread` — its grep matched a comment

**Symptom (2026-08-27):** no run directory made by `setup_restart_run.sh` (X7, X8*, D*) has the `--hint=nomultithread` line, although the script "adds it if missing". `sacct` shows 512 CPUs allocated for the 256 ranks of X7 — both hyperthreads, binding left to SLURM's default. No effect on results or, measurably, on speed (1.5 s/step as sized), but the run headers did not say what the project rules claim.

**Cause:** `grep -q -- '--hint=nomultithread' "$SB"` is unanchored; the template's MUSICA note on line 18 (`#           --hint=nomultithread and set --ntasks-per-node=190 …`) contains the string, so the check always "passed".

**Fix:** anchored to `^#SBATCH --hint=nomultithread` (same commit as `resubmit_d_1node.sh`). Rule: a grep that gates an edit of a SLURM header must anchor on `^#SBATCH`. `Dctl` was deliberately left as X7 (no hint) — same allocation as the reference for the bit-for-bit check; the 1-node D runs carry the hint.


## E26. WRFlux's flux-output mode is not bit-neutral: `output_*_fluxes = 1` vs `0` changes the model trajectory

**Symptom (2026-08-28):** the control segment `Dctl` (new binary, all switches off, WRFlux flux outputs OFF,
`output_tke_moments = 1`) was not bit-identical to X7 (flux outputs ON) from its first frame: 99 % of
cells differ at 07:30, max |ΔU| 8 m s⁻¹, ΔT2 up to 6 K, growing to ΔMU 131 Pa by 10:00.

**Attribution (six-minute 2×128 devel runs from X7's 07:00 restart, `exp/BB*`, per-variable
`bitcompare.py`):** flux outputs off vs on with everything else equal (BBT2 vs BBB) → NOT identical from
step 90; `output_tke_moments` 1 vs 0 with flux outputs on (BBT1 vs BBB) → identical; the same with flux
outputs off (BBA vs BBT2) → identical; restart at 07:03 vs continuous (BBA2 vs BBA) → identical.
So the seed is upstream WRFlux, not the added averaging code and not the restart path. The only solver-side
code that runs exclusively in flux mode is the halo exchange `HALO_EM_WRFLUX` of `u_save, v_save, w_save,
dph_x, dph_y` inside the Runge–Kutta loop (`Registry.EM_COMMON:3660`, `solve_em.F:1754`); `u/v/w_save`
are the solver's own working arrays, so halo cells read afterwards differ. Whether that is the whole
mechanism is not proven; that flux mode changes bits is measured.

**Consequence:** a run with the flux outputs off is never bit-comparable with one that has them on; the
difference is a last-bit seed that grows chaotically in the convective boundary layer (E14 class), so
statistics are unaffected. **Rules:** (1) a bit-for-bit gate must hold the WRFlux stream settings fixed
between the two runs; (2) the control of an experiment set is a run with the *same* stream settings
(`Dctl`), never X7/X9 from the archive; (3) the six-minute devel-run design of 2026-08-28 (same restart,
same layout, one namelist key changed) is the cheap way to attribute any future bit difference.

## E27. Restart segments that cross 10:18 need the A14 gate — the template default `pbl3d_moist_cond_max = 0.` is the pre-fix behaviour

**Symptom (2026-08-28):** `Dctl` (07→13 from X7's 07:00 restart, `pbl3d_moist_cond_max = 0.`) blew up at
11:04:10 at (i=419, j=292, k=8), a 1255 m slope cell, sensible heat flux 332 W m⁻², 11:00 state
unremarkable (|W| ≤ 2.8 m s⁻¹, q² ≤ 2.9 m² s⁻²): W +13 → −77 m s⁻¹ in one 2-s step, w-CFL 7.2, sfclay NaN
two cells away — the A14 signature (X8a, 10:18, same run window). The four switch segments carried the
same 0 and were held before they started.

**Cause:** `setup_d1d2_segments.sh` set the gate to 0 on purpose, to keep the bit-for-bit match with X7
(pre-A14) — forgetting that the segments run through the A14 window. The template
`namelist.input.pbl3d` still carries `0.` ("1e4 recommended when enabled"), so any run built from it
without `--set pbl3d_moist_cond_max=10000.0` is a pre-fix run.

**Fix:** the five D namelists set to 10000.0 before launch; `setup_d1d2_segments.sh` writes the gate. The
bit-for-bit question is answered by the six-minute devel runs (E26), not by a segment. **Measured 2026-08-29:**
the gate fires from 07:30 on (2–4 × 10⁻⁴ of live faces per frame have cond > 10⁴ in the ungated run;
DECISIONS 2026-08-29 00:30), so a gated run is not bit-comparable with X7 at any hour. Rule: any run that
enters convective daytime (anything past ~10:00) carries `pbl3d_moist_cond_max = 10000.0`, the production
value since X9a (DECISIONS 2026-08-24 10:15).

## E28. The q² vertical diffusion is explicit: S_q·l·q·Δt/Δz² must stay below ½ — S_q = 1.0 blows up in the convective morning

**Symptom (2026-08-29):** `Dsq10`-a (S_q = 1.0, 07→10 from X7's 07:00 restart, 1 × 128) died at 08:48:20 with
`SFCLAYREV produced NaN` at (547,179) and (537,189) — ridge cells at 2167/2302 m — with **no CFL warning** on
any rank and no A14 signature (`PBL3D_COND_M` gated at 10⁴). The 08:30 frame is clean everywhere.

**Cause:** `Calc_q_sq_vertical_diffusion` (`dyn_em/module_pbl3d.F:5940`) forms the face flux
−S_q·l·q·∂q²/∂z and adds its divergence to the tendency; q² is then advanced with the full model step
(`module_pbl3d.F:603`, `pbl3d_nsteps = 1`) — a forward-Euler diffusion with stability number
r = S_q·l·q·Δt/(Δz_face·Δz_layer) ≤ ½. Per-face r from the archived frames: `Dctl` (0.2) max 0.10, `Dsq06`
(0.6) max 0.24 at 08:30; `Dsq10` (1.0) max 0.37 → 0.39 → 0.45 at 07:30/08:00/08:30 with 931 → 7345 faces
above 0.25 (l ≈ 30 m, q ≈ 3 m s⁻¹, Δz = 20 m) — convective growth crosses ½ within the next half hour.
The horizontal q² diffusion is explicit too but harmless at Δx = 500 m.

**Rule:** with Δt = 2 s and Δz = 16–20 m in the lowest 200 m, S_q ≤ 0.6 is the usable range of the
explicit scheme (r_max ≈ 0.25 in the convective morning); S_q ≥ 1 needs an implicit vertical q² diffusion
(tridiagonal, as MYNN does for QKE) or a substep — both are code changes, default-off (DECISIONS
2026-08-29 03:30). Any q² NaN with no CFL warning and a clean last frame: compute r first.

## E29. The first WRFlux mean written after a restart is all zeros; X7's WRFlux stream was 6-hourly, so the 3D control has no 30-min flux means before 10:00

**Symptom (2026-08-29):** `exp/X9a/wrf_output/8489332/meanout_d01_2025-07-18_10:00:00.nc` (the first
`auxhist24` frame of the 10:00 restart segment) has `TZ_MEAN`, `ZWIND_MEAN`, `FTZ_ADV_MEAN`, `FTZ_SGS_MEAN`,
`Z_MEAN` identically zero: the accumulators are reset at the restart start and the frame is written
before any accumulation (zero-length averaging window). Any diagnostic that reads it silently gets zeros
(the grey-zone partition of 2026-08-29 produced an all-NaN row; a sum would have produced a plausible
number). Second symptom: X7 (01→10) wrote WRFlux means at 01:00 and 07:00 only (`auxhist24_interval_m = 360`,
DECISIONS 2026-08-22: "30-min from now on" applies from X8a/X9a), so the stitched control day
`wrf_output/9999999` has no 30-min flux means for 07:30–09:30 — the hours where h < 1 km and the partition
between resolved and subgrid transport matters most.

**Rule:** skip the frame stamped at a segment's start time when reading WRFlux means of a restart
segment (or test that `Z_MEAN` is non-zero); a restart chain's mean frames are those stamped strictly
after the restart time. The 07:30–09:30 window of the control needs a dedicated 07→10 run with the flux
outputs on (the D runs have them off, E26).

## E30. The "valley floor" terrain class is 83 % Alpine foreland — every valley-floor statistic before 2026-08-29 is a foreland statistic

**Symptom (2026-08-29):** the grey-zone partition gave a valley-floor median mixed-layer depth of
1.1 km at 11 UTC in the 3D control while the two Inn-valley radiosonde sites showed 3–4 K of stability
between 50 and 500 m in the same run. `terrain_classes(hgt, dx) == 0` (`proc/proc/turbulence.py`:
within 150 m of the 5-km-box minimum and slope < 5°) is true for every cell of flat terrain: of
91 560 "floor" cells, 75 607 (83 %) have a 20-km relief ≤ 800 m (the foreland north of the Alps and the
low-relief margins, HGT median 541 m), 15 953 are in-mountain valley floors, and the Inn valley proper
(HGT < 800 m, 47.1–47.6 °N, 10.8–12.5 °E) is ≈ 1 060 cells — 1 %.

**Affected:** the D1 soundness check (DECISIONS 2026-08-27 14:00), the D-ladder entrainment table
(2026-08-29 07:40), the first grey-zone partition (11:50) — all "valley-floor interface" numbers
describe the flat foreland, where a 500-m grid resolves the convection early and the closure's
subgrid transport matters least. The sounding comparisons (site-based) are unaffected.

**Rule:** split floor statistics by 20-km relief — foreland (≤ 800 m), mountain valley floors
(> 800 m), Inn valley (the lat/lon box above) — and judge the valley physics on the last two. A
diagnostic that reports one "valley-floor" number must say which mask it used.

## E31. `scontrol update Partition=` breaks a pending job on VSC-5 — the lane GRES is stamped at submit time

**Symptom:** a pending job moved between Zen3 lanes with `scontrol update JobId=… Partition=zen3_2048
QOS=zen3_2048` goes to `Reason=BadConstraints, Priority=0` and never starts (X10c, job 8550557,
2026-08-31).

**Cause:** VSC-5's job-submit plugin stamps every job with a partition-specific GRES
(`gres/cpu_zen3_1024=…`). `scontrol update` changes Partition/QOS but does not re-stamp the GRES,
so the moved job requests a resource the new lane's nodes do not advertise. Patching the GRES by
hand (`scontrol update … Gres=cpu_zen3_2048:256`) leaves both tags in the job's TRES accounting
and the scheduler flips it back to BadConstraints.

**Rule — moving a chain job to an emptier lane:** (1) `scontrol hold` the old job (so two copies
can never write the same output root), (2) `cd <rundir> && sbatch --partition=<lane> --qos=<lane>
submit_wrf.slurm` (the plugin stamps the right GRES; sbatch from the rundir, E32), (3) retarget
every dependent job — `scontrol update JobId=<link> Dependency=afterok:<new>` and the afternotok
ping likewise — (4) `scancel` the held job. Verified: 8550557 → 8551230 started in seconds on
zen3_2048 with links d and the failure ping following the new ID.

## E38 — cdo cannot decode the ICON model-level fields (CCSDS/AEC packing); it silently writes fill values (2026-09-02)
Neither cdo on VSC-5 (conda `icon` env; spack `cdo/2.5.2-gcc-12.2.0`) is built with AEC: any cdo operator touching the `generalVertical` (65-level) fields of the raw ICON GRIBs aborts with `CCSDS support not enabled` for some messages and yields fill-value output for the rest — a downstream `ap2pl` then warns `Surface pressure out of range (9.97e36)` and produces garbage without failing. The 11 isobaric levels decode (not CCSDS-packed), which is why icon2wrf's pressure-level path never noticed. Decode model levels with python-eccodes (2.47.3 in the `icon` env): `codes_get_double_element(gid, "values", cell)` per message, or `codes_get_values` for full fields. `module load cdo` must not be piped (E1) or the PATH change is lost.

## E37 — `sbatch` SPOOLS the script: a fix committed to a `.slurm` file does not reach jobs already armed with it — resubmit them (2026-09-01)
The CANCELLED guard added to `notify_x10.slurm` (E34) at midday did not protect the pings submitted at 08:52: SLURM copies the batch script into its spool at submission, so an armed job runs the pre-fix version forever. Cost today: when the self-cancelling twin pair resolved (8552760 started, cancelled 8552759), the cancelled twin's pre-guard ping fired and wrote a false wake flag — caught and neutralized before the crontab watcher consumed it, but only because a session happened to be live. **Rule: after changing a script that armed jobs reference, `scancel` those jobs and resubmit them with the same dependencies** (`squeue -u $USER -h -o "%i %j %E"` finds them). The same applies to namelists in reverse: `wrf.exe` reads `namelist.input` at START, so run-dir edits DO reach a pending job — which is how the filter experiment was repurposed without losing its queue position.

## E36 — i-Box ECPY quality flags: a value with `qcflag_* <= -1` is invalid, and two station-levels are fully flagged for the IOP night (2026-09-01)
Every flux/variance column in `data/stations/ibox_ecpy/*.csv` has a companion `qcflag_*` column (e.g. `qcflag_wt1`, `qcflag_ust1`); **valid data has flag > −1** (Elias; flags 0/1/2 are quality grades, −1 is invalid). For the night 2025-07-17 18 UT → 07-18 07 UT, nf27 level 1 and sf8 level 1 are flagged −1 in all 27 half-hours — sf8 has no other sonic level, so it contributes nothing to that night; nf27 must be read at level 2. All other station-levels pass in full and unfiltered medians are unchanged. Filter *before* computing any statistic; the unflagged raw columns contain plausible-looking numbers.

## E35 — WRFlux semantics: `T_TEND_DAMP_MEAN` is the 6th-order filter (not Rayleigh damping) whenever `damp_opt /= 2`; and the `F*_ADV_MEAN_2ND` fields exist in the output but are NEVER FILLED (all zero) (2026-09-01)
Two traps in the same stream. (1) The registry describes `t_tend_damp` as "Rayleigh damping and 6th-order diffusion", but the θ-Rayleigh accumulation lives in `rk_rayleigh_damp`, which is called only under `damp_opt = 2` (`dyn_em/module_em.F:1203`); with this project's `damp_opt = 3` the field is **purely the `diff_6th_opt` hyperdiffusion tendency** — which is exactly what made the pool-budget decomposition possible (DECISIONS 2026-09-01 16:30), but would silently mislabel a numerics term as "damping" in any budget that assumes Rayleigh. (2) `FTX/FTY/FTZ_ADV_MEAN_2ND` (and the q/u/v/w counterparts) are registry state on stream 24 with **no Fortran computing them** — they read back as exact zeros (checked in the CPB probe archives). The advertised built-in 2nd-order-scheme comparison does not exist in this build; use the offline stencil reconstruction (`wrf3dpbl-diag/pool_upwind_diffusion.py`) instead, or implement the accumulation before trusting those names.

## E34 — an `afternotok` failure-ping fires when YOU cancel the job: CANCELLED satisfies "not ok" (2026-09-01)
`scancel` on a job that carries an armed `--dependency=afternotok:<job>` ping releases that ping, which then writes a wake-up flag and starts a headless session to diagnose a failure that never happened (here: 8551893/8552124 cancelled at 08:30 while rebuilding the CPB twins; both pings fired at once with identical timestamps, and the run dirs contained no `rsl.error.0000` and no archive — the tell that the job never ran). **Rule: cancel the ping together with its job.** Find them with `squeue -u $USER -h -o "%i %j %E" | grep afternotok:<jobid>`; a cleanup script that cancels jobs must cancel their dependants in the same pass.

## E33 — `ATHRATEN{LW,SW}` are per-output-bucket accumulations in KELVIN, not cumulative K s-1: differencing consecutive frames gives ~zero radiative cooling (2026-09-01)
With `acc_phy_tend = 1` WRF accumulates the physics tendencies into a bucket that is **reset at every history write**, and the field's unit is K (the temperature change over that bucket), not a rate. The natural-looking `(A[t2]-A[t1])/dt` therefore returns the difference of two nearly equal bucket totals: 0.001 K/h of longwave cooling on a clear night, which is impossible and would have been read as "the radiation scheme is broken". Correct rate = `A[t] / history_interval`. Check: on a quasi-steady night consecutive frames hold nearly the SAME value (-0.1362, -0.1384 K here); a cumulative accumulator would double. Same applies to the other `A*` physics accumulators. Cross-check any budget term against a physical magnitude before interpreting (E18).

## E32. The submit scripts `cd "$SLURM_SUBMIT_DIR"` — `sbatch --chdir` does not change it, so always `cd <rundir> && sbatch`

**Symptom:** `real.exe`/`wrf.exe` fail instantly with `execve …/./real.exe: No such file or
directory` when submitted via `sbatch --chdir=<rundir> submit_real.slurm` from elsewhere
(both X10 real jobs, 8549398/8549400, 2026-08-31).

**Cause:** `SLURM_SUBMIT_DIR` is the directory `sbatch` was *invoked* from, not what `--chdir`
sets; the submit scripts' first action is `cd "$SLURM_SUBMIT_DIR"`, which silently undoes
`--chdir` and leaves the job in the invocation directory, where `./real.exe` does not exist.

**Rule:** every scripted submission is `jid=$(cd "$RUNDIR" && sbatch --parsable …)` — never
`sbatch --chdir`. `chain_x10.slurm` and `launch_x10.sh` do this; any new driver must too.

## E39 — the icon2wrf *surface* product carried geopotential on the 11 isobaric levels; any 3-D product on other levels made metgrid abort with "Error in ext_pkg_write_field" (2026-09-03)

**Symptom.** `metgrid.exe` stops at the first 3-D field of the first time with only `ERROR: Error in ext_pkg_write_field`; the met_em file is a 239-byte empty header. ungrib reports success for every file. Old (11-level) products were unaffected — the failure appeared the moment the 3-D product changed to the 36-level ladder or the 65 native levels (`icon2wrf --vertical plevs|native`).

**Cause.** `extract_surface` merged `z` into the surface dataset ("HSURF fallback"), so every `*_sfc.grib2` also carried ICON's geopotential on the 11 isobaric levels. `Vtable.ICONp` turns that into GHT at those levels in the SFC intermediate file, and metgrid takes the union of GHT levels over FILE and SFC. With the old product the sets were identical and merged silently; with the ladder the foreign 975 hPa level gave GHT 38 levels against 37 for TT/UU/VV/RH (native: 65 + 11). The WRF-IO layer then refuses to redefine `num_metgrid_levels` — visible only at `debug_level = 1000` as `WRF_DEBUG: Warning DIM 4, NAME num_metgrid_levels REDEFINED by var GHT 37 38 in wrf_io.F90`. Found with gdb on `ext_ncd_write_field_` (GHT arrived with 38 levels); disk space, level count, netCDF libraries and shell environment were all ruled out first.

**Fix.** (a) icon2wrf commit `9069aee`: `z` no longer enters the surface product. (b) For surface files made before 2026-09-03, ungrib the SFC and ICON_INIT steps with `Vtable.ICONsfc` (= `Vtable.ICONp` without the level-100 rows; `RUN_WPS_1712ML.sh` does this). The 3-D step keeps `Vtable.ICONp` (ladder) or `Vtable.ICONm` (native, level type 150).

**Observation to check (not yet a defect).** The surface level (200100) of TT/UU/VV/RH in *every* met_em so far, old and new, is fill (±1e30): the ICON surface product has no 2 m/10 m fields (they are `heightAboveGround`, the extractor filters `typeOfLevel = surface`). real.exe has always run on this; how it fills the surface level should be verified before trusting the lowest wrfinput level.
