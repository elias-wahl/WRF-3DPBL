# Paste-ready Antrag sections (drafted 2026-09-10)

Numbers marked **measured** come from the VSC-5 production runs; everything else is
scaled from them with the assumption stated. Two items still to verify before
submission are marked **[verify]**.

---

## Verwendete Software

- **Model:** WRF (ARW) 4.8.0, institutional fork carrying a three-dimensional
  Mellor–Yamada boundary-layer closure (`pbl3d_opt=2`) developed in this project;
  Fortran 90, **pure MPI (`dmpar`, configure option 34 — Linux x86_64 / gfortran)**,
  no OpenMP, basic nesting (`nest_option 1`).
- **Compiler and MPI (production build, VSC-5):** GCC **12.2.0** with **OpenMPI 4.1.6**.
  The build is Spack-provided and version-pinned; the same combination (GCC 11/12 +
  OpenMPI 4.1) is available in Levante's module stack, so no porting work is
  requested. **[verify: exact Levante module strings]**
- **I/O and numerics libraries:** netCDF-C 4.9.0, netCDF-Fortran 4.6.0, HDF5 (via
  `nc-config`), zlib 1.2.13, and **netlib-LAPACK 3.10.1** — the closure solves a dense
  10×10 second-moment system per grid point and time step with LAPACK `dgesvx`
  (equilibrated, condition-estimated), which is why a tuned LAPACK/BLAS matters for
  throughput.
- **LES configuration:** Deardorff 1.5-order TKE closure in the nested LES domains;
  RK3 split-explicit dynamics on the terrain-following grid; Thompson microphysics,
  RRTMG radiation, Noah-MP land surface, topographic shading active.
- **Pre-processing:** WPS (ungrib/metgrid) plus an in-house ICON converter
  (`icon2wrf`, Python + ecCodes) that reads the ICON-500 m forecasts on their 65
  native model levels and writes WPS-ready GRIB2 — the step that removed a
  documented initialization deficiency of the pressure-level product.
- **Post-processing:** Python 3 (netCDF4, NumPy, SciPy, matplotlib, xarray/dask) in a
  version-pinned Conda environment, plus WRFlux for online flux/budget decomposition.
  All pre- and post-processing runs through SLURM, hence its own compute request.
- **Workflow:** restart-segmented chains with SLURM dependencies (`afterok`) and
  automatic per-segment quality gates; no interactive steps in production.

---

## Suitability to HLRE-4 (Levante)

- **The problem needs a machine of this class.** The target is a two-stage nested
  large-eddy simulation, 500 m → 100 m → **20 m**, over the instrumented Radfeld
  transect: ≈131 × 10⁶ grid points in the innermost domain at Δt ≈ 0.1 s. It must run
  as one coherent, restart-continuous chain — not as independent short jobs — which
  places it beyond local/institutional resources within the project's lifetime.
- **The code matches the architecture.** Pure-MPI Fortran with a regular Cartesian
  decomposition maps directly onto Levante's CPU partition (AMD EPYC Milan,
  128 cores per node **[verify]**); throughput is **measured** on the same processor
  generation, so the request rests on measurement rather than estimate. Communication
  is nearest-neighbour halo exchange plus the per-step pressure solve — well served by
  the HDR InfiniBand fabric.
- **Resource type requested: CPU only.** The model has no GPU port, so the A100
  partition is explicitly not requested. Remote visualization is not required.
- **Memory and I/O fit the machine.** The standard 256 GB nodes are sufficient at the
  planned decomposition; the fat-memory nodes exist as a fallback if the LES domain
  grows. Output is thinned at source (field-selection lists), one file per output time,
  and the aggregate write rate is well inside what Levante's Lustre `/work` sustains.
- **The scientific environment is at DKRZ.** The driving data are ICON forecasts —
  a DKRZ-native model whose data holdings and tooling live on the same system — so the
  forcing branch of the workflow is at home here; the analysis chain (virtual UAS
  flights, spectra, statistics) runs in the same SLURM environment as the simulations.
- **Why HLRE-4 rather than the applicants' national systems:** the principal
  investigator, the UAS observations and the processing software are with the
  DFG-funded partner group in Germany, and the LES production volume exceeds what the
  Austrian allocation can absorb alongside the 500 m ensemble it already carries.

---

## Scalability

- **Measured strong scaling**, 500 m domain (601 × 501 × 80 = 24.1 × 10⁶ points,
  Δt = 2 s), 128 MPI ranks per node:

  | nodes | ranks | s per time step | node-hours per 6 h segment |
  |---|---|---|---|
  | 2 | 256 | 1.50 | 9.0 |
  | 4 | 512 | 0.80 | 9.6 |
  | 5 | 640 | 0.65 | 9.8 |

  Near-linear to 640 ranks: a 2.3× speed-up for 2.5× the nodes, i.e. ~92 % parallel
  efficiency, at ≈38 000 grid points per rank.
- **Extrapolation to the LES nest:** holding the points-per-rank figure at which the
  above efficiency was measured, the 131 × 10⁶-point domain implies ≈3 500 ranks —
  **20–32 nodes per LES segment**, the size planned for production. The
  halo-to-compute ratio at that decomposition is no worse than in the measured cases
  because the subdomain column count is comparable.
- **A short on-machine scaling test (16/32/64 nodes, one simulated hour) is planned in
  the first weeks of the allocation** before production starts, to confirm the
  extrapolation on Levante's fabric and to fix the production node count. Its cost is
  included in the request.
- **Time-step constraint, stated openly:** the LES nest is limited by the vertical
  Courant number in thin near-surface layers over steep terrain — a limit this project
  has measured directly and mitigates with WRF's targeted vertical-velocity damping
  rather than a globally shorter time step, which is what keeps the cost estimate
  stable.
- **I/O scaling:** one file per output time and per domain; field selection at source
  reduces a full 3-D frame by roughly a factor three. Output cadence is a tunable, not
  a fixed cost.

---

## Computing time and storage (with justification)

**Cost per simulated hour, from the measured 500 m throughput scaled by grid points
and time step:**

| domain | points | Δt | cost per simulated hour |
|---|---|---|---|
| 500 m parent | 24.1 × 10⁶ | 2 s | ≈190 core-h = **1.5 node-h** (measured) |
| 100 m nest | ≈12 × 10⁶ | 0.6 s | ≈320 core-h = **2.5 node-h** |
| 20 m nest | ≈131 × 10⁶ | 0.1 s | ≈20 000 core-h = **156 node-h** |

The 20 m nest is ≈97 % of the cost. **This dictates the design of the request: the
cheap parent chain runs the full diurnal cycles, while the expensive LES nest runs
only in the windows the science actually needs.**

| item | scope | node-hours |
|---|---|---|
| parent chain (500 m + 100 m) | 6 cases × 26 simulated hours (24 h + spin-up) | 620 |
| **LES nest, night cases** | 3 cases × 14 h (18–06 UT + 2 h LES spin-up) | 6 550 |
| **LES nest, daytime cases** | 3 cases × 10 h (09–17 UT + 2 h spin-up) | 4 680 |
| sensitivity suite | 3 members × 6 h nest window, one case | 2 810 |
| on-machine scaling test | 16/32/64 nodes × 1 h | ≈250 |
| margin (restarts, failed segments, I/O) | × 1.3 | +5 700 |
| **pre-/post-processing (SLURM)** | virtual-flight resampling along the real trajectories, spectra, statistics | 2 000 |
| **Total requested** | | **≈22 000 node-hours** |

**Justification of each choice**

- **Why 6 cases:** two TEAMx intensive observation periods, three cases each, to span
  the flow regimes the UAS flights sampled; fewer would not separate case-to-case
  scatter from the correction functions being derived.
- **Why only 3 cases carry the night:** the nocturnal window doubles the LES hours per
  case, and the night serves the secondary objective (the cold-pool budget), not the
  UAS correction functions, which are flown by day. Three nights are enough to show
  whether the nocturnal result is robust; the remaining three cases stop at the evening
  transition.
- **Why the nest runs windows, not whole days:** the virtual-flight comparison needs
  the LES only where flights exist, plus ~2 h of LES spin-up before them. Running the
  nest for 26 h per case would triple the cost and add no measurement.
- **Why a 30 % margin:** the chain is restart-segmented and has run in production for
  months, so failure recovery is cheap; 30 % covers first-weeks setup on a new machine
  and lost segments.
- **Why the post-processing line item:** all analysis runs through SLURM at DKRZ;
  resampling ~40 flight trajectories through several TB of LES frames and computing
  spectra over the nest volume is not a login-node task.

**Storage**, derived from **measured** file sizes (500 m: 6.4 GB per full 3-D history
frame at 24.1 × 10⁶ points, 14.5 GB per restart; both scale with grid points):

| product | derivation | volume |
|---|---|---|
| 20 m nest history | 72 nest-hours, 15-min cadence, thinned (≈12 GB/frame) | 3.5 TB |
| 20 m nest restarts | every 3 h, ≈78 GB each | 1.9 TB |
| 100 m + 500 m output | 156 simulated hours, 30-min cadence, thinned | 0.9 TB |
| sensitivity suite | 3 × 6 h nest + restarts | 1.1 TB |
| virtual-flight and spectral products | high-frequency columns and trajectories | < 0.1 TB |
| working copies, derived diagnostics | × 1.5 on the above | ≈4 TB |
| **Disk (`/work`) requested** | | **15 TB** |
| **Archive requested** | documented case set + virtual-flight products + one reference LES case | **5 TB** |

Neither figure approaches the thresholds that would require a separate data-storage
plan (10⁶ node-hours, 1 024 TiB disk or tape).

---

## Proportionality (for the internal discussion, not for the Antrag)

- Levante's CPU partition is ≈2 800 nodes **[verify]**, i.e. ≈24.5 × 10⁶ node-hours per
  year. The request is **≈0.09 % of a machine-year** and **2.2 %** of the volume at
  which DKRZ demands a data-storage plan.
- For a DFG project funding one doctoral position, whose computational core this is,
  ≈22 000 node-hours over twelve months is proportionate: it is one PhD-year of
  production, not a community campaign. The earlier 50 000-hour version was defensible
  but harder to argue and, under DKRZ's quarterly expiry of unused compute, less likely
  to be fully consumed — which matters for the renewal.
- If reviewers ask for less: dropping the sensitivity suite to two members and one night
  case gives ≈18 000 node-hours without touching the primary objective. If more becomes
  possible later, the natural extensions are the three additional nights and a 10 m
  stable-night pilot, both requestable mid-period.
