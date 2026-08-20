# Findings — the `pbl3d_opt=2` q² runaway (OPEN_ISSUES A9)

Status as of **2026-08-20**, VSC-5. This file is the resume point: it carries the
answer to A9, the measurement that closes it, two corrections to earlier text,
and the ranked fix that is **deliberately not implemented**.

Source of record for the narrative is `branko/OPEN_ISSUES.md` A9. This file is
the numerical snapshot, so a later session does not have to re-derive it.

---

## 1. The question, and the answer

**A9 asked:** at the deterministic blowup (`2025-07-18_01:38:00`, step 1141), is
q² production rising or is dissipation failing — and does Tier 1 (the Durbin
strain limiter) bind at the runaway cell or is it blind to the strain?

**Answer:** production rises, dissipation keeps pace but never catches up, and
**Tier 1 binds hard the whole way down**. Branch 1 of A9 is confirmed; branch 2
(Tier 1 blind to strain because `strain_mag` is built from terrain-following
gradients) is dead — those gradients *are* metric-corrected
(`dyn_em/module_pbl3d.F:1100`).

The mechanism is a **split master length scale**. Production scales with the
Tier-1-limited `l_use`; dissipation uses the *unlimited* `l_master`:

```fortran
! dyn_em/module_pbl3d.F:6322-6327   (Fill_dissip_length_scale)
if (l_opt == 3) then
  l_dissip(i, k, j) = (l_boulac(i, k, j) + l_boulac(i, k + 1, j)) / 2.
else
  l_dissip(i, k, j) = l_master(i, k, j)
end if
```

We run `pbl3d_l_opt = 1`, so the `else` branch is taken and `l_dissip` is the
scale Tier 1 never touched. `l_use` is a **local scalar**
(`dyn_em/module_pbl3d_my.F:1531`) and is never written back. Since
`ε = 2q³/(b₁ l_dissip)` (`module_pbl3d.F:6368-6369`), `ε ∝ 1/l` — so **Tier 1
firing widens the very imbalance it exists to close**. At the blowup cell the
closure transports momentum as if the eddies were ~2.4 m and dissipates them as
if they were 6.05 m.

---

## 2. Run provenance

| | |
|---|---|
| Job | **8472687**, VSC-5, 2026-08-20 04:43:35 → 05:15:14, `FAILED 11:0` (SIGSEGV in RRTMG — the expected terminal symptom, U2) |
| Run dir | `/gpfs/data/fs72996/ewahl/branko_runs/innval_pbl3d_qsq` |
| Namelist | that dir's `namelist.input` — `pbl3d_opt=2`, `pbl3d_l_opt=1`, `pbl3d_l0_opt=1`, `pbl3d_prog=1`, `pbl3d_qsq_opt=1`, `pbl3d_sfc_opt=0`, `pbl3d_nsteps=1`, `pbl3d_scale_aware=1`, `pbl3d_constants='MY82'`, `pbl3d_sk_eps_max=6.0`, `pbl3d_n_tau_max=0.53`; `bl_pbl_physics=0`, `diff_opt=0`, `hybrid_opt=0`, `time_step=2`, `epssm=0.9` |
| Resources | 2 nodes × 128 ranks, `--hint=nomultithread`; **1.43 s/step** |
| Diagnostics | `auxhist23` at 1 min via `branko/realcase/iofields_qsq.txt` |
| Frames | 39, `01:00` … `01:38`, all written; `qsqdiag_d01_2025-07-18_01:38:00.nc` is complete |
| iofields warnings | **zero** `W A R N I N G` lines in `rsl.error.0000` — every requested field was recognised |

`iofields_qsq.txt` (three directive lines, no blank line — a blank line ends
parsing):

```
+:h:23:Q_SQ_SHEAR,Q_SQ_BUOYANCY,Q_SQ_DISSIP,Q_SQ_VDIFF,Q_SQ_HDIFF
+:h:23:Q_SQ,W
+:h:23:PBL3D_T1_RATIO,PBL3D_SK_EPS,PBL3D_T2_STEPS,PBL3D_T3_FLAGS,L_MASTER
```

---

## 3. The blowup cell

Domain 600 × 500 × 80 (mass), dx = dy = 500 m.

| | |
|---|---|
| Indices | `j = 111`, `i = 161`; q² peak at stag `k = 1`, |W| peak at `k = 0` |
| Position | **46.639 N, 10.806 E**, terrain 1549.1 m |
| Local slope | `∂h/∂x = 0.020`, `∂h/∂y = 0.664` → **33.6°** |
| Layer depth | `dz ≈ 16.8 m` (first five layers 16.77, 16.80, 16.18, 16.85, 17.53) |
| `L_MASTER` at k=1 | **6.05 m** ≈ `κ·z` for z ≈ 15 m — surface-layer limited |

This is a **different cell** from the earlier job's 01:30 peak (`k=0, j=54,
i=38`) and from the MUSICA q² peak (`k=4, j=182, i=514`, `L_MASTER ≈ 16 m`).
The mechanism is not cell-specific.

Vertical structure at 01:36 — the runaway is confined to the first two
half-levels, and Tier 1 stops binding above them:

| k | L_MASTER | T1_RATIO | SK_EPS | Q_SQ | W | κ·z |
|---|---|---|---|---|---|---|
| 0 | 0.000 | 1.0000 | 0.00 | 1e-05 | −17.53 | 0.00 |
| 1 | 6.043 | **0.3981** | 15.07 | 18.14 | −1.56 | 6.71 |
| 2 | 11.441 | 0.6453 | 9.30 | 11.62 | +2.57 | 13.43 |
| 3 | 16.139 | 1.0000 | 3.05 | 6.385 | +1.51 | 19.90 |
| 4 | 20.576 | 1.0000 | 4.61 | 3.006 | +1.31 | 26.64 |
| 5 | 23.059 | 0.9527 | 6.30 | 1.474 | +0.90 | 33.66 |

---

## 4. The measurement (1-minute, at the blowup cell)

`Q_SQ`, `T1_RATIO`, `SK_EPS`, `L_MASTER` at stag `k=1`; `W` at `k=0`;
`SHEAR`, `DISSIP` at mass `k=0`. `P/ε consistent` = `(P/ε) × T1_RATIO`, i.e.
what the ratio would be if dissipation used the same `l` production does.

| time | Q_SQ | W | T1_RATIO | SK_EPS | L_MASTER | SHEAR | DISSIP | P/ε as built | P/ε consistent |
|---|---|---|---|---|---|---|---|---|---|
| 01:25 | 0.0164 | −2.12 | 0.1982 | 30.28 | 6.10 | 2.96e-4 | 1.91e-6 | 154.9 | 30.7 |
| 01:26 | 0.0238 | −2.55 | 0.1965 | 30.54 | 6.09 | 3.16e-4 | 1.28e-6 | 246.0 | 48.3 |
| 01:27 | 0.0251 | −2.57 | 0.3033 | 19.79 | 3.68 | 2.05e-4 | 3.13e-7 | 653.7 | 198.2 |
| 01:28 | 0.0241 | −2.82 | 0.3187 | 18.83 | 2.82 | 1.92e-4 | 5.34e-7 | 358.8 | 114.3 |
| 01:29 | 0.0345 | −3.59 | 0.2310 | 25.98 | 3.07 | 3.84e-4 | 1.17e-7 | 3271 | 755.5 |
| 01:30 | 0.0710 | −4.11 | 0.1795 | 33.43 | 4.28 | 2.03e-3 | 3.53e-8 | 57471 | 10316 |
| 01:31 | 0.2259 | −5.00 | 0.1770 | 33.90 | 6.06 | 1.12e-2 | 9.25e-4 | 12.12 | 2.15 |
| 01:32 | 1.144 | −6.07 | 0.2913 | 20.60 | 6.06 | 9.15e-2 | 4.46e-2 | 2.05 | 0.60 |
| 01:33 | 3.708 | −8.80 | 0.3638 | 16.49 | 6.06 | 0.4275 | 0.3102 | 1.378 | 0.501 |
| 01:34 | 7.710 | −11.85 | 0.3857 | 15.56 | 6.06 | 1.207 | 0.9804 | 1.232 | 0.475 |
| 01:35 | 12.28 | −14.94 | 0.3862 | 15.54 | 6.05 | 2.479 | 2.114 | 1.173 | 0.453 |
| 01:36 | 18.14 | −17.53 | 0.3981 | 15.07 | 6.04 | 4.568 | 3.986 | 1.146 | 0.456 |
| 01:37 | 29.50 | −22.18 | 0.3916 | 15.32 | 6.06 | 9.949 | 8.823 | 1.128 | 0.442 |
| 01:38 | 44.54 | −26.47 | 0.3919 | 15.31 | 6.05 | 18.67 | 17.19 | 1.086 | 0.426 |

Read it in three parts.

**Ignition (01:25 → 01:30).** q² is at/near the floor, so `ε = 2q³/(b₁l)` is
negligible and `P/ε` is meaningless as a ratio — but Tier 1 is *already* binding
at 0.18–0.32 and `SK_EPS` is already 19–33. The limiter is saturated before
anything visible happens.

**Runaway (01:31 → 01:38).** `P/ε` sits at **1.09–1.23 for eight consecutive
minutes**. A persistent few-percent excess is exactly an exponential, and it is:
fitting `ln q²` over 01:32–01:38 gives an **e-folding time of 105 s** (doubling
73 s), i.e. a net imbalance of **9.5e-3 s⁻¹**. (The instantaneous `(P−ε)/q²` at
01:36 is 3.2e-2 s⁻¹; the difference is the diffusive export, `VDIFF` + `HDIFF`,
which is a genuine sink here.)

**The counterfactual.** With a consistent length scale, `P/ε` is **0.43–0.60**
through the entire runaway window — below unity, so q² decays and the runaway
never starts. This holds at *every* frame, not just the one A9 quoted.

### Domain-wide budget, 01:25 → 01:38

`max` is max |value|; `mean` is the signed domain mean. Units m² s⁻³.

| time | SHEAR max | SHEAR mean | BUOY max | BUOY mean | DISSIP max | DISSIP mean | VDIFF max | HDIFF max |
|---|---|---|---|---|---|---|---|---|
| 01:25 | 4.72 | 1.41e-4 | 0.079 | −1.55e-5 | 3.50 | 1.38e-4 | 1.37 | 0.19 |
| 01:30 | 3.75 | 1.76e-4 | 0.141 | −1.58e-5 | 2.95 | 1.69e-4 | 0.89 | 0.14 |
| 01:33 | 3.04 | 1.98e-4 | 0.102 | −1.61e-5 | 1.99 | 1.87e-4 | 1.11 | 0.18 |
| 01:35 | 9.42 | 2.16e-4 | 0.132 | −1.65e-5 | 5.85 | 2.02e-4 | 2.83 | 0.43 |
| 01:36 | 10.84 | 2.25e-4 | 0.140 | −1.66e-5 | 5.08 | 2.09e-4 | 3.78 | 1.19 |
| 01:37 | 45.23 | 2.43e-4 | 0.144 | −1.67e-5 | 20.64 | 2.24e-4 | 18.21 | 8.12 |
| 01:38 | 18.67 | 2.27e-4 | 0.183 | −1.64e-5 | 17.19 | 2.13e-4 | 1.48 | 0.36 |

The domain **means** are flat and tiny throughout — SHEAR/DISSIP ≈ 1.05, moving
by 5 % over the whole window. Only the maxima explode. This is a point failure,
not a domain-wide imbalance. `Q_SQ_BUOYANCY` never exceeds ±0.19 anywhere and is
a net *sink* in the mean: buoyancy is not driving this.

---

## 5. Two corrections to earlier text

### 5.1 Tier 2 and Tier 3 are **not** globally dead

`OPEN_ISSUES.md` A9 and the 2026-08-19 `DECISIONS.md` entry state that
`T2_STEPS = T3_FLAGS = 0`. Domain-wide at 01:36 that is **wrong**:

- `PBL3D_T2_STEPS` non-zero in **294 398** cells, max **5**
- `PBL3D_T3_FLAGS` non-zero in **60 156** cells, max **240** (bits 8+16+32+64+128)

The true statement is narrower, and worse: at the **runaway column** they are
silent. `T3_FLAGS = 0` at every level in every frame; `T2_STEPS` is 0 at k=0,1,2
and only sporadically 1–2 at k=3. The backstops work — they simply do not see
this failure mode. Tier 2 escalates on *solver distress* (`info /= 0`,
`cond(A) > 1e8`) and on *non-realizability*; Tier 3 enforces PSD. A q² budget
running 15 % hot is neither. **The closure has no feedback path from
"production is outrunning dissipation" back onto `l`.**

### 5.2 The Tier-1 footprint is ~4 %, not ~20 %

At 01:36, `PBL3D_T1_RATIO < 0.999` in **977 518 of 24 000 000** cells = **4.1 %**;
`< 0.5` in **1.06 %**. `SK_EPS` max 4144, mean 1.352, above 6.0 in 4.08 %.

The "~20 % / 899 613 cells" figure in the 2026-08-19 entry came from a different
frame of a different job. The fix is still a broad science change, but the
affected fraction is five times smaller than recorded.

### 5.3 Resolved: the honest-limit caveat from 2026-08-19

That entry noted `T1_RATIO = 0.345` was derived from a *peak* `SK_EPS = 17.4`,
not a co-located value, and that the correction suffices at 01:36 only if
`SK_EPS > 12.6` there. **Measured: `SK_EPS = 15.07`, `T1_RATIO = 0.398` at the
blowup cell at 01:36.** Condition met. The conclusion no longer rests on the
identity alone.

---

## 6. Recommended fix, ranked — NOT implemented

**1. Make the dissipation length scale consistent with the transport one.**
Primary. No new parameter. Write Tier 1's `l_use` back so `l_dissip` sees it —
equivalently `ε → ε / T1_RATIO`. Takes `P/ε` from 1.09–1.23 to 0.43–0.60 at the
blowup cell in every frame.

*Why this and not a production cap:* in Mellor-Yamada the master length scale is
singular by construction — the same `l` sets the stress closure and
`ε = q³/(b₁l)`. The k-ε analogy that would justify leaving dissipation alone
does not transfer, because there `ε` is prognostic and here it is *diagnosed
from `l`*. This removes an inconsistency; it does not add a mechanism. That is
what makes it different in kind from the shear-production cap A9 rules out.

**2. Add a budget-based escalation test to Tier 2.** Secondary, and it addresses
§5.1 directly: Tier 2 should also escalate when `P/ε` exceeds a threshold at the
point, not only on solver distress and realizability.

**3. Lower `pbl3d_sk_eps_max`.** Fallback only. The measured effective `c_μ`
implies runaway is excluded only below `Sk/ε ≈ 4.1`, and `c_μ` varies with
stratification, so this trades one arbitrary bound for another.

### Why it is not implemented

It is a science change, not a bug fix: it alters the solution wherever Tier 1
fires (4.1 % of cells at 01:36, and much more in the strongly-strained
regimes — the Group F table has Tier 1 binding at 100 % in nocturnal SBL,
slope drainage and residual-LLJ). It needs validating against the 47 h MYNN
control and the idealised regressions before it goes in. That is a scope call
for the user, so the evidence and the falsification condition are written down
instead.

---

## 7. Grey-zone context (why this bites here specifically)

- **Honnert scale-awareness is inert.** `pbl3d_scale_aware = 1`, dx = 500 m,
  nocturnal PBL depth ~100 m → `dxdh ≈ 12.5` → `Psig_bl = 1.0009`, clipped to
  1.0 (`module_pbl3d_my.F:3880-3883`). The taper is derived for convective PBLs
  and does nothing in a shallow stable one.
- **The grid is ~30:1 anisotropic at the failure level** (dx 500 m, dz 16.8 m),
  and a single scalar `l ≈ 6 m` is used for both directions.
- **Richardson number collapses.** At 75 m AGL, `N = 0.0168 s⁻¹`, `Ri` goes
  ~0.39 → ~0.03 as the shear runs away. Tier 1 combined with the Deardorff limit
  gives `Sk/ε ≤ 4.40/√Ri`, so Tier 1 can never activate for `Ri ≳ 0.54` — the
  regime where it *does* activate is exactly this one.
- **Terrain-following metric cancellation** was measured at ~2.2× error
  amplification in `du_dx` at 01:30 — real, but an order too small to be the
  driver, and it does not reach the blowup window.

---

## 8. How to reproduce these numbers

All read-only. From `/gpfs/data/fs72996/ewahl`, after
`source branko/realcase/env/vsc5.sh`.

Locate the blowup cell in the final frame:

```python
import netCDF4 as nc, numpy as np
d = nc.Dataset('temp/branko/qsqdiag_d01_2025-07-18_01:38:00.nc')
q = d['Q_SQ'][0]
print(np.unravel_index(np.nanargmax(q), q.shape))   # -> (1, 111, 161)
```

Cell time series (§4, upper table): loop the frames from `01:25`, read
`Q_SQ[0,1,J,I]`, `W[0,0,J,I]`, `PBL3D_T1_RATIO[0,1,J,I]`, `PBL3D_SK_EPS[0,1,J,I]`,
`L_MASTER[0,1,J,I]`, `Q_SQ_SHEAR[0,0,J,I]`, `Q_SQ_DISSIP[0,0,J,I]` with
`J,I = 111,161`; `P/ε = SHEAR/DISSIP`, consistent `= (P/ε)·T1_RATIO`.

Domain budget (§4, lower table): per frame, `nanmax(abs(v))` and `nanmean(v)`
for each of the five `Q_SQ_*` terms.

Tier statistics (§5): `(t1 < 0.999).sum()`, `(t1 < 0.5).sum()`,
`(sk > 6).sum()`, `(t2 != 0).sum()`, `(t3 != 0).sum()` on the 01:36 frame.

Growth rate (§4): `np.polyfit(t, np.log(q), 1)[0]` over 01:32–01:38 →
9.516e-3 s⁻¹, e-folding 105.1 s.

Terrain and slope: from `branko_runs/innval_pbl3d_qsq/wrfinput_d01`, `HGT`,
centred differences over dx = 500 m; levels from `(PH+PHB)/9.81`.

`branko/realcase/scripts/qsq_budget.py` does the tabulation with
`--from/--to/--level/--cell K,J,I`.

---

## 9. Still open

- The fix itself (§6) — awaiting a scope decision.
- **MUSICA job 89435** may still be queued at Innsbruck; it can only be
  cancelled from a MUSICA session (`scancel 89435`).
- **U2** (RRTMG-LW `taumol` index guard) and **U1** (`sf_sfclayrev` table lower
  bound) should be reported upstream to `wrf-model/WRF`. Do **not** land U2's
  guard as the fix for A9 — it converts a loud deterministic crash into a NaN
  propagating silently through the radiative tendency.
- No `pbl3d_opt=1` run exists on VSC-5; all opt=1 evidence is from MUSICA job
  89167.
- The 17–41 % boundary-layer q² reduction from the Group E/G length-scale fixes
  is unresolved and needs an LES or observational reference.
