# Decisions log

Append-only, newest first. One entry per judgment call on this project's
science/config setup — not process fixes (those go in the assistant's
lessons file) and not things `branko/realcase/README.md`,
`CHANGES.md`, or `OPEN_ISSUES.md` already document in depth.

---

**2026-08-29, ~11:40 — Precision to the 07:40 judgement (Elias asked whether the observed soundings were in it): they were, at three launches; against them every variant is still far too stable at 11 UTC, and the mixed-layer-depth row is withdrawn as evidence.**

Launches inside 07–13: Kolsass 08:01, Innsbruck 10:57, Kolsass 11:01 (θ profile → RMSE/bias row; Δθ(500−50 m); parcel ML depth; valley-wind depth). Δθ(500−50 m), obs / `Dctl` / `Dsq06` / `Dbc1` / `Dsq06bc1` / MYNN (K): Kolsass 08:01 1.68 / 3.78 / 3.87 / 3.61 / 3.34 / 1.64; Innsbruck 10:57 0.09 / 4.59 / 4.20 / 4.10 / 2.91 / −0.24; Kolsass 11:01 0.69 / 3.30 / 2.71 / 3.58 / 3.19 / 0.33. The best variant closes a third of the stability gap at Innsbruck and a tenth at Kolsass; MYNN sits on the observation. The × 4–7 transport gain is therefore a small step against a large deficit. **Withdrawn:** the "ML depth + 100 m, deeper than MYNN" reading. Parcel ML depths at the sites are incoherent (`Dctl` 2133 m at Kolsass 11:01 with a 3.3 K stable lowest 500 m; `Dbc1` 191 m at Innsbruck and 2617 m at Kolsass four minutes apart; obs 892 / 955): the parcel is launched from a surface that carries the +0.5–1 K warm bias and punches through a layer the θ profile shows is stable — the diagnostic is biased by the near-surface error, not merely noisy, and the domain-wide median inherits it. The entrainment fluxes and transport terms (computed from the fields) stand; depth statements need a stability-based definition (θ-gradient maximum or Δθ threshold) before they are used again. Pseudo-job order for the record: 9999101 `Dctl`, 9999102 `Dsq06bc1`, 9999103 `Dsq06`, 9999104 `Dbc1`.

---

**2026-08-29, ~07:40 — D1/D2 ladder judged (07→13 UTC, `Dctl` / `Dsq06` / `Dbc1` / `Dsq06bc1`, 1 × 128, gate 1e4): S_q × 3 raises the interface TKE transport × 4–5 and the surface q² condition adds × 1.4 in mixed-layer TKE; together × 6–7 in transport and × 1.6 in entrainment flux — real, and still × 9 below MYNN. The 100 m wind excess is untouched. Verdict: D1 is transport-limited as diagnosed; the explicit q² diffusion (E28) is the wall; D2's q²-only condition does not reach the 100 m wind.**

Numbers (`proc` stages `soundings entrainment surface`, job 8542178; pseudo-jobs 9999101–04; valley-floor interface 0.8 < z/h < 1.2, m² s⁻³ unless stated):

| | `Dctl` | `Dsq06` (S_q 0.6) | `Dbc1` (q² wall) | `Dsq06bc1` | MYNN |
|---|---|---|---|---|---|
| TKE transport at the interface, 10 / 11 UTC | 1.8e-6 / 1.5e-6 | 6.9e-6 / 7.2e-6 | 2.4e-6 / 2.0e-6 | 9.9e-6 / 1.0e-5 | 9.4e-5 / 9.1e-5 |
| transport / \|buoyancy destruction\| | 0.21 / 0.12 | 0.64 / 0.46 | 0.22 / 0.11 | 0.74 / 0.48 | 3.5 / 2.9 |
| entrainment buoyancy destruction, 11 UTC | −1.26e-5 | −1.56e-5 | −1.77e-5 | −2.07e-5 | −3.19e-5 |
| mixed-layer TKE maximum, 11 UTC (m² s⁻²) | 0.36 | 0.35 | 0.52 | 0.51 | 1.30 |
| valley-floor median ML depth, 11 / 12 UTC (m) | 1242 / 1439 | 1320 / 1443 | 1336 / 1534 | 1339 / 1546 | 1303 / 1420 |
| Δθ(500−50 m), Innsbruck 10:57 (obs 0.09 K) | 4.59 | 4.20 | 4.10 | 2.91 | −0.24 |
| Δθ(500−50 m), Kolsass 11:01 (obs 0.69 K) | 3.30 | 2.71 | 3.58 | 3.19 | 0.33 |
| θ RMSE / bias below 1 km, day launches (K) | 1.07 / +0.47 | 1.02 / +0.49 | 1.29 / +1.04 | 1.18 / +1.04 | 1.85 / +1.79 |
| q²(face 1) / 8.3 u*², land median (diagnostic × 2, see below) | 0.33 | 0.35 | 0.63 | 0.64 | 1.2 (mass level) |
| l / κz at 9 and 26 m | 0.57 / 0.49 | 0.57 / 0.51 | 0.86 / 0.70 | 0.86 / 0.72 | 1.2 / 1.3 |
| Kolsass 10:30–13:00: u10 / u100 (obs 2.56 / 2.52 m s⁻¹) | 3.40 / 6.10 | 3.14 / 5.96 | 3.49 / 6.17 | 3.54 / 6.10 | 1.80 / 2.05 |

*Mechanism.* S_q acts where it was aimed: the vertical q² transport at the inversion scales more than linearly with S_q (× 3 → × 4–5, the q² gradient steepens with the flux) and the transport-to-destruction ratio rises from 0.2 to 0.6; alone it neither adds mixed-layer TKE nor deepens the layer much (+80 m median). The surface condition feeds TKE in from the wall (mixed-layer maximum + 40 %, l/κz 0.57 → 0.86 in the lowest 30 m) but transports none of it upward; combined, the two multiply (more TKE × a larger transport coefficient): × 6–7 in transport, entrainment flux at 65 % of MYNN's, ML depth + 100 m. Still an order of magnitude short of MYNN's interface transport — MYNN's carries the EDMF mass flux, a non-local term this closure lacks. The sounding scalars at single sites are noisy (control vs stitched X9a day differ by 1.6 K at Innsbruck 10:57 — convective onset at the site), so the domain-wide entrainment table is the judge; both agree in sign.

*D2.* The q²-only wall condition (`pbl3d_sfc_qsq_bc = 1`) doubles the near-wall q² and lengthens l toward κz but leaves the 100 m wind at 6.1 m s⁻¹ against 2.5 observed (shear ratio 100 m/10 m 1.79 → 1.72, obs 0.99) and warms the lowest km by 0.5 K (bias +0.47 → +1.04). Near-wall q² is not what sets the 100 m wind; the momentum mixing in 30–100 m is, and `bc = 2` (l ≥ κz below 100 m) was not in the ladder. A16 stays open with that as the next test.

*Diagnostic caveat.* `sfc_tke_check` samples the first mass level; the closure's q² lives on faces with face 0 at the floor, so the printed ratio is half the face-1 value (0.16 ↔ the smoke's 0.37; 0.32 ↔ 0.65). Table above already doubled.

*Next (recommendation, not done).* (1) Implement implicit vertical q² diffusion (default-off `pbl3d_sq_implicit`) so S_q = 1–2 can be tested — the trend says transport is the lever and E28 is the wall; (2) test `pbl3d_sfc_qsq_bc = 2` on a 07→13 pair; (3) the remaining × 9 argues for a non-local (mass-flux-like) q² transport term, to be designed after (1). Nothing changes in production: all switches stay default-off; the candidate configuration is `pbl3d_sq = 0.6, pbl3d_sfc_qsq_bc = 1` only if the 0.5 K warm bias is accepted — not yet.

---

**2026-08-29, ~03:30 — `Dsq10` (S_q = 1.0) crashed at 08:48: the explicit vertical q² diffusion crossed its stability limit (E28). The S_q ladder stops at 0.6 unless the diffusion is made implicit; D1 is judged from `Dsq06`.**

Mechanism: `Calc_q_sq_vertical_diffusion` is forward-Euler with the full Δt = 2 s; stability number r = S_q·l·q·Δt/(Δz_face·Δz_layer) ≤ ½. Measured per face from the archives at 08:30: r_max 0.10 (`Dctl`, 0.2), 0.24 (`Dsq06`, 0.6), 0.45 (`Dsq10`, 1.0; 7345 faces above 0.25, rising 931 → 2806 → 7345 over 07:30–08:30 as the convective layer grows: l ≈ 30 m, q ≈ 3 m s⁻¹ at Δz = 20 m). No CFL warning, no A14 signature, clean 08:30 frame, NaN at 08:48 on two ridge cells — the explicit limit is the only candidate; the ignition face is not pinned (no 1-min stream). Physics reading: the diffusivity a 5× S_q asks for, K_q ≈ 100 m² s⁻¹ over 20 m layers, is exactly the transport the D1 hypothesis wants at the inversion, and the scheme cannot carry it at this Δt/Δz. Options, not yet chosen: (1) implicit vertical q² diffusion (tridiagonal like MYNN's QKE), a default-off switch `pbl3d_sq_implicit`; (2) sub-stepping the diffusion (`pbl3d_nsteps` exists but sub-steps the whole closure); (3) a stability clip K_q ≤ Δz²/(2Δt) — rejected: it clips where the transport matters. Recommendation: judge D1 from `Dsq06` (3× MY82, r_max 0.24) first; implement (1) only if 0.6 shows a real but insufficient effect on the 11 UTC mixed-layer depth. `Dsq10`'s 07:30–08:30 frames remain usable for the early-morning footprint of S_q = 1; its chain link 8539592 cancelled; no rerun.

---

**2026-08-29, ~00:30 — Measured: the A14 gate is active all morning (2–4 × 10⁻⁴ of live faces per frame from 07:30), so no gated run is bit-comparable with X7 at any hour; the earlier bitcompare for this question is retracted (decompositions differed).**

From the ungated `Dctl` archive (8531824, 07:30–10:00): faces whose accepted moist-flux solve has condition number `PBL3D_COND_M` > 10⁴ number 2142 → 4036 per frame (max 7 × 10⁶–8 × 10⁷; 207 → 421 faces above 10⁵), 0.2–0.3 % above 10³ — the same footprint measured for X9a on 2026-08-24. The gated half `Dctl`-a (8539583) has max 10⁴ in every frame. Physics: the unbounded solves are a permanent small population of the convective morning, not a 10:18 event; the crash needs one of them to hit a θ-gradient zero crossing at the right face and step. Consequence: X7's morning contains those solves (harmless there: none ignited before 10:00), and the D runs are judged against `Dctl` only. Retracted: my bitcompare `8539583` vs `8531824` (NOT identical) was between 1 × 128 and 2 × 128 layouts — meaningless (E14); the record line saying "identical = gate never fires" is withdrawn.

---

**2026-08-28, ~16:50 — The D segments split into 3-h halves on `zen3_2048`, 1 × 128, 5:00 h each; second halves chained inside SLURM. Why the earlier moves did not help: the backfill scan is global and ~1750 jobs deep.**

`sdiag` explains the day: each backfill cycle examines ~1750 jobs in priority order *across all partitions*; with ~2250 jobs above ours on `zen3_0512` and ~225 on `zen3_1024` our jobs sat near position 2500 and were never examined in either lane (yesterday's `Dctl` started at 07:37 only because the eligible queue thins at night). `assoc_limit_stop` additionally closes a lane to the main scheduler when its top pending job is blocked by a group limit — the case on `zen3_1024` (a 7-day job at `QOSGrpCpuLimit`); its 26 "idle" nodes were `IDLE+PLANNED` for higher-priority jobs. `zen3_2048` (20 nodes) is the lane where every pending job is below ours, so the main scheduler (per-partition depth 500) takes us as soon as a node frees: 19:57 (1), 06:27 (1), 10:22 (4). Elias: move there and split. Done by `realcase/scripts/split_d_zen3_2048.sh`: first halves = the existing run dirs cut to 07→10 with `restart_interval=180` (Dctl 8539583, Dsq06bc1 8539585, Dsq06 8539587, Dbc1 8539589, Dsq10 8539591; 1 × 128, 5:00 h — ≈3.1 s/step → 4.7 h incl. restart read); second halves `<run>b` (10→13, `exp/<run>b`) are built and submitted by `chain_segment.slurm` links 8539584/86/88/90/92 (`afterok` the first half, devel QOS, SLURM-resident). Tool changes: `setup_restart_run.sh --partition P` (QOS follows), `chain_segment.slurm` takes `NODES`, `PARTITION`, `IOFIELDS` (defaults = previous behaviour). Soundness: a test build of `Dctlb` from X7's 10:00 restart reproduced the parent namelist except start/length/paths/restart_interval; restart continuation is bit-exact (BBA vs BBA2). Halves are not harmful to the science: 30-min WRFlux means, boundary at 10:00 is a mean boundary; the diagnostics read per-time archives (`exp/<run>` for 07:30–10:00, `exp/<run>b` for 10:30–13:00) as with the X7/X8/X9 chain. Expected: Dctl-a ~20:00–00:45 tonight, then the freed node serves the next pending half by priority (age → the older first halves before Dctl-b), all ten done by ~24 h from now.

---

**2026-08-28, ~16:15 — The five D segments moved to `zen3_1024` on 2 × 128, 5:00 h (8539492–96); not split.**

After 18 h without a start on `zen3_0512` (3429 pending, 2249 ahead of us, 264 nodes drained, 178 earmarked for large jobs), the lanes were compared: `zen3_1024` had 27 idle nodes and 224 jobs ahead, `zen3_2048` 14 pending. The lanes differ only in RAM (same Zen3 CPUs, same cost). Elias: move to the fast lane; consider 2 nodes and halving the runs. Done by `realcase/scripts/resubmit_d_zen3_1024.sh` (cancel 8539159/8533211–14, headers → `--nodes=2 --time=05:00:00 --partition=zen3_1024 --qos=zen3_1024`, A14 gate verified in every namelist, submitted control first: Dctl 8539492, Dsq06bc1 8539493, Dsq06 8539494, Dbc1 8539495, Dsq10 8539496). Why 2 nodes: with idle nodes the constraint is the backfill *time* window; 1.34–1.5 s/step on 256 ranks → 4.0–4.5 h + restart read, request 5:00 (was 9:30 on one node). Why not split: restart transparency is proven bit-exact (BBA vs BBA2), so halving would not change results, but it adds a second queue wait and a 10:00 restart cycle for little gain once the jobs are 5 h on an idle lane — the fallback if they have not started within ~1 h (`chain_segment.slurm`, 07→10 and 10→13). Layout note: 2 × 128 on `zen3_1024` is the reference decomposition again, but the D runs remain not bit-comparable with X7 (E26); nothing changes in how they are judged. Recorded as a standing rule in CLAUDE.md ("This cluster") and the assistant's memory.

---

**2026-08-28, ~14:00 — `Dctl` blew up at 11:04 (A14 gate off — my setup error); the bit-for-bit gate against X7 failed for a different reason: WRFlux's flux-output mode itself is not bit-neutral (E26). The added code is bit-neutral; the reference-build check passed: the new binary is bit-identical to `cf08b0463` with every switch off (rule 2 satisfied).**

*What happened.* `Dctl` (8531824, 2 × 128) crashed at simulation time 11:04:10 with the A14 signature (W +13 → −77 m s⁻¹ in one step at a 1255 m slope cell under 332 W m⁻² of heating; E27). All five D namelists had `pbl3d_moist_cond_max = 0.` — set deliberately on 08-27 to match X7 bit for bit, forgetting that the 07→13 segments cross the window that killed X8a at 10:18. Fixed in the four pending namelists (10000.0, the X9 production value) before they started; `setup_d1d2_segments.sh` now writes it.

*The bit-for-bit gate.* `Dctl` archived 07:30–11:00, so the check ran: NOT identical from the first frame, domain-wide (99 % of cells, max |ΔU| 8 m s⁻¹ at 07:30, ΔMU 131 Pa at 10:00) — a trajectory divergence seeded at the restart. Attribution with six-minute 2 × 128 devel runs from the same restart (`exp/BB*`, ≈8 min each, per-variable `bitcompare.py`):

| pair | differs by | verdict |
|---|---|---|
| BBT2 vs BBB | WRFlux flux outputs off vs on (new binary, moments off) | NOT identical |
| BBT1 vs BBB | `output_tke_moments` 1 vs 0 (flux outputs on) | identical |
| BBA vs BBT2 | `output_tke_moments` 1 vs 0 (flux outputs off) | identical |
| BBA2 vs BBA | restart at 07:03 vs continuous | identical |
| BBC vs BBB | reference build `cf08b0463` vs new binary, X7 settings | **identical** (14:22) |

The seed is WRFlux's flux mode (its `u/v/w_save` halo exchange is the only flux-only solver code; mechanism plausible, not proven), an upstream property; the added averaging code and the restart path are bit-neutral. Hence the D runs (flux outputs off, to keep the 30-min WRFlux frame at 1.7 GB instead of 9.5 GB) can never be bit-compared with X7; their control is `Dctl` with the same stream settings, X7/X9 remain the statistical references only — which is how the comparisons were planned anyway.

*Verdict (14:22).* BBC (reference binary, X7 settings) vs BBB (new binary, same settings): bit-for-bit identical on every variable at 07:03 and 07:06 — the rebuilt binary reproduces the last good binary exactly with the switches off; rule 2 of the working method is satisfied. The whole non-reproducibility of `Dctl` against X7 is WRFlux's flux mode (E26) plus the A14 gate after 10:00.

*Queue.* The four switch jobs (8533211–14) were held until 14:10, then released on Elias's call before the BBC verdict (the new code paths were already proven bit-neutral); `Dctl` resubmitted as 8539159 (1 node, 9:30, gate on, held). Reference build: worktree `branko_ref` at `cf08b0463` (parent of the switch commit; includes the A14 fix), serial login-node build, `branko/main/wrf.exe` untouched. Disk: BB* archives ≈ 8 GB each (six-minute runs), `exp/Dctl/wrf_output/8531824` (48 GB, 07:30–11:00 of the crashed run) kept until the rerun archives.

---

**2026-08-28, ~09:00 — `Dctl` running (started 07:37, 1.34 s/step, finish ≈12:00); the four 1-node jobs trimmed to 9:30 h and un-handicapped.**

`Dctl` (8531824) started on the 2-node reference layout; the bitcompare job fires on its completion. The four 1-node switch jobs had not backfilled — their 10:30 request was the obstacle, not the node count (a node free for < 10.5 h before the forming reservation can take a 5:30 2-node job but not a 10:30 1-node one). Elias: trim the time, drop the `--nice` handicap. Done by `realcase/scripts/requeue_tune_d_1node.sh` (`scontrol update TimeLimit=9:30:00 Nice=0` on the four pending jobs). Why 9:30: 1.34 s/step measured on 256 ranks; ranks-per-node is 128 either way, so per-rank memory bandwidth is unchanged and the step time scales ≈ linearly with subdomain size → 2.7–2.9 s/step on 128 ranks, 8.1–8.7 h + ~15 min restart read; 9:30 keeps ≈45 min margin (9:00 would not, and running out of wall late in the segment wastes it all). With nice gone all four sit at the same priority (109532); SLURM breaks the tie by job ID, so submission order still ranks **Dsq06bc1 > Dsq06 > Dbc1 > Dsq10** — the candidate keeps first claim.

---

**2026-08-27, ~19:10 — The four switch segments move to ONE node each (10:30 h); only the control keeps the 2-node reference layout; the combined run gets the highest priority.**

Nothing had started after two hours (4791 jobs pending, 264 nodes drained, no backfill estimate). Elias: put every run that is not bit-for-bit checked on one node, and rank the most promising one first. Feasibility measured: X7 used 122 GB per node on 2 × 128 (`sacct MaxRSS`) → ≈250 GB on one 500 GB node; 1.5 s/step on 256 cores → ≈3.1 s/step on 128, 10 800 steps ≈ 9.5 h, request 10:30 (MaxWall 3 d). `Dctl` (8531824) stays on 2 × 128 — the bit-for-bit comparison with X7 is only meaningful on X7's decomposition (E14). The four 1-node jobs are submitted by `realcase/scripts/resubmit_d_1node.sh` (cancel 8531825–28, then `sbatch --nice`) in the order **Dsq06bc1 (nice 0) > Dsq06 (500) > Dbc1 (1000) > Dsq10 (1500)** — SLURM users can only *lower* priority, so the ranking is done by handicapping the others. Why the combined run first: it is the candidate configuration; the entrainment soundness check (14:00) showed S_q alone cannot close a ×50 transport gap, while the surface condition had the one immediate footprint in the smoke (q²(face 1)/8.3u*² 0.37 → 0.65 in 12 min). The single-switch runs attribute, they are not the candidates. Submitted 19:25: Dsq06bc1 8533211, Dsq06 8533212, Dbc1 8533213, Dsq10 8533214 (priorities 109192/108692/108192/107692 vs Dctl 109363). Results of 1-node runs are compared with X7/MYNN statistically as before; the decomposition change makes them not bit-comparable with `Dctl`, which changes nothing (E14 already forbids cell-by-cell comparison). Side finding: `setup_restart_run.sh` never inserted `#SBATCH --hint=nomultithread` — its unanchored grep matched the MUSICA comment in the template (E25); X7 and every D run so far ran without it (binding only, no effect on results); fixed (anchored), the four 1-node scripts carry the hint now, `Dctl` deliberately left as X7 was.

---

**2026-08-27, ~17:25 — Rebuilt binary validated through the smoke; the five D1/D2 segments are queued (8531824–28); bit-for-bit check armed in SLURM.**

Build on the login node 16:24→16:57 (serial, `BUILD OK`, `ldd` clean; G4 gate: `pbl3d_sq`, `qsq_mean`, `output_tke_moments` all in the generated `inc/`). Smoke 8531803 (07:00→07:12 from X7's restart, 5 nodes, `pbl3d_sq = 0.6`, `pbl3d_sfc_qsq_bc = 2`, `output_tke_moments = 1`, flux switches off): SUCCESS; both init messages in `rsl.error.0000`; the only history warning is the harmless `athcuten` reset. `check_tke_moments.py`: **PASS** — `QSQ_MEAN`, `W2/UW/VW_SGS_MEAN` (80 faces), `QKE_MEAN` (79, all zero as it must be in a pbl3d run), `RHOD_MEAN`, `Z_MEAN`, `MUT_MEAN` present at full shape with every `output_*_fluxes = 0` (the package carries them — the stub trap is closed); all finite; `w'² ≤ q²` on 100 % of cells; `QSQ_MEAN` / end-point mean q² over the 6-min window median 0.997 (10–90 % 0.90–1.08, n = 4.0 M cells). Footprint of the surface condition after 12 min: q² at face level 1 over land, in units of B1^(2/3) u*² (8.3 u*²), median 0.37 in X7 at 07:00 → **0.65** (p10 0.49, p90 1.49) — the floor sits on the lowest mass level, face 1 is the interpolation above it, so < 1 there is expected.

*Correction to the disk estimate:* a subgrid-means meanout is **2.1 GB**, not < 1 GB (the packaged `rhod_mean, mut_mean, z_mean` plus five 3D fields at 0.1–0.3 GB each); a segment is ≈ 47 GB history + 25 GB WRFlux ≈ 72 GB, five ≈ 360 GB — fine after Elias freed the July `WRF/run` restarts and `wrf_output/7995376` (1.2 TB free).

*Queued:* `Dctl` 8531824, `Dsq06` 8531825, `Dbc1` 8531826, `Dsq10` 8531827, `Dsq06bc1` 8531828 (2 × 128, 5:30 h each, one wave). A devel-QOS job with `--dependency=afterok:8531824` runs `bitcompare.py` on `Dctl` vs X7 (07:30–10:00, six frames) and writes `exp/Dctl/bitcompare_vs_X7.<job>.out`; its last line must read *bit-for-bit identical on every compared variable* before any physics from the other four is read (meanout not compared: `QQ_MEAN` differs by design, and X7's WRFlux means are 6-hourly). Two sessions were active at once this afternoon; the segments were submitted from the other one — the run dirs and namelists are the ones checked here (only the expected keys differ from X7).

---

**2026-08-27, ~15:20 — D1/D2 test switches implemented (commit `8e92feaaf`, build job 8529206) and how they act; five 07→13 UTC restart segments from X7's 07:00 restart.**

Both switches default to the previous behaviour bit for bit (`pbl3d_sq = 0.2`, `pbl3d_sfc_qsq_bc = 0`); the WRFlux switch `output_tke_moments = 0` likewise. The only intentional change to a default output is `QQ_MEAN` in the meanout, which accumulated onto `Q_MEAN` instead of itself (WRFlux bug, `module_avgflx_em.F`).

*D1 — `pbl3d_sq`.* `S_q`, the coefficient of the q² vertical diffusivity `K_q = S_q l q` (MY82 Eq. 24; `q` = √q², `l` = master length), was a compile-time constant 0.20 in `Calc_q_sq_vertical_diffusion`. It is now the module variable `SQ_DIFF` set once at init. Pure transport: a larger `S_q` moves q² from the mixed layer into the interface faster, it creates none. Test values 0.6 and 1.0 (MYNN's q² diffusivity is 3 K_m, 1.5–7 × this closure's in a convective layer, entry 14:00).

*D2 — `pbl3d_sfc_qsq_bc`.* The closure had **no lower boundary condition on q²**: the ground flux of q² in the vertical diffusion is zero and `Fill_q_sq_with_q_sq_prog` only floors the ground face at `Q_SQ_MIN` — q² next to the wall is whatever local production leaves there (0.17 of the surface-layer value by day, entry 14:30). Option 1 holds the **lowest prognostic level** at or above the neutral surface-layer equilibrium `q² = B1^(2/3) u*²` (MY82 Eq. 47b; 6.5 u*² for the MY82 constant set in use, B1 = 16.6; MYNN’s B1 = 24 gives 8.3 u*²), the condition the MYNN family imposes at its lowest level. Three implementation decisions, each checked in the source:
- **Delivered as a tendency, not a clamp.** The driver receives the temporary copy `q_sq_tmp` (`module_first_rk_step_part2.F:1263`), so a value written into `q_sq_prog` inside the closure never reaches the dynamics; only `q_sq_tend` does. The source `(c1 μ + c2)·(q²_sfc − q²)/dt` on level `kts` is added in `Calc_q_sq_rhs` after dissipation, in the same μ-coupled form as the shear/buoyancy/dissipation terms, and closes the gap within one step. Not divided by `pbl3d_nsteps` on purpose (the first sub-step closes the gap, the later ones see none; production uses `nsteps = 1` anyway).
- **A floor, not a prescription.** MYNN sets equality; here `Max`. The deficiency is one-signed (too little q² at the wall by day) and a floor cannot remove q² at night, where the closure is already the best of the five against observations and the cap must not be touched.
- **Energy bookkeeping.** The q² this adds is not paid by the resolved flow — it is the surface-layer source MYNN has as well. The energy-closure residual diagnostic (`compare_mynn.py exp`) will show it as unexplained gain near the wall; that is expected, not a pairing defect like A10.
Option 2 adds `l ≥ κz` in unstable air below `pbl3d_sfc_qsq_zmax` (100 m) in the Blackadar branch (`Calc_l_master_algebra`, after the buoyancy limit) — Eq. 71 gives `l < κz` whenever `l0` is not ≫ κz, and `l = 0.6 κz` was measured in the lowest levels by day. Option 2 is built and smoke-tested but **not** in the five segments (one lever at a time).

*WRFlux subgrid time means.* `QSQ_MEAN`, `W2_SGS_MEAN`, `UW_SGS_MEAN`, `VW_SGS_MEAN` (face levels, pbl3d) and `QKE_MEAN` (mass, MYNN) as plain running means in stream 24 — no Hesselberg weighting, no last-step correction (the closure variables are kinematic already). Guarded by the physics switch, not by data (`pbl3d_used == 1`, `bl_pbl_physics == MYNNPBLSCHEME`). Package `mean_tke_1` carries `rhod_mean, mut_mean, z_mean` so the switch works with every `output_*_fluxes = 0` (otherwise those three are written into (1,1,1) stubs — the plan's trap); `check_a_mundo` turns `output_avgfluxes` on for it. The resolved moments planned earlier are not needed (entry 15:30).

*Runs.* Disk decides the shape: 345 GB free at 97 %. Five segments **07→13 UTC** (not 14: 13 UTC is where the up-valley excess ends, and 6 h fits the 5:30 h backfill window), history every 30 min thinned by `iofields_d1d2.txt` (21 unread 3D fields dropped, 5.6 → ~3.6 GB/frame; every name the diagnostics open was checked), WRFlux every 30 min with the flux switches off and `output_tke_moments = 1` (< 1 GB/frame), no restart files, `pbl3d_init_opt = 0`, `pbl3d_l0_min = 0.0` (E19). Two waves: control + `pbl3d_sq = 0.6` + `pbl3d_sfc_qsq_bc = 1` (~170 GB), then `pbl3d_sq = 1.0` and the combination. `realcase/scripts/setup_d1d2_segments.sh` builds them and diffs each namelist against X7's.

*Validation results (17:20).* Login-node build OK (16:56; G4 gate: `pbl3d_sq` in `namelist_defines.inc`, `qsq_mean` in `state_struct.inc`, `ldd` clean). Smoke 8531656 (12 min from the 07:00 restart, `pbl3d_sq = 0.6`, `pbl3d_sfc_qsq_bc = 2`, `output_tke_moments = 1`, flux switches off): `SUCCESS COMPLETE WRF`; both init messages printed; the seven iofields warnings are "already on history stream". **WRFlux means pass**: all five fields full-shape (no (1,1,1) stub), `RHOD/MUT/Z_MEAN` carried by the package alone, `W2_SGS_MEAN ≤ QSQ_MEAN` on 100 % of cells, `QKE_MEAN` = 0, and `QSQ_MEAN` over the last 6 min equals the end-point mean of `Q_SQ` to a median ratio **0.997** (10–90 %: 0.90–1.08) in the lowest 20 levels. Smoke 8531729 (`pbl3d_sfc_qsq_bc = 1` alone, `Q_SQ_PROG` in the history): **the floor holds** — the lowest prognostic level sits at **0.94** of the wall value 6.5 u*² over land (X7 at 07:30: 0.24), the level above at 0.59 (X7: ≈ 0.3), steady from 07:02 to 07:12. The 6 % shortfall is the same-step sink: dissipation and the diffusive flux to the level above act on the floored value within the step, so a tendency-delivered floor settles a few per cent below the target rather than on it; accepted. **Correction:** the MY82 constant set in use has B1 = 16.6, so the wall value is 6.5 u*², not 8.3 u*² (that is MYNN's B1 = 24); the first footprint number (0.32, measured against 8.3 u*² and on face 1 rather than the level) is superseded by the 0.94 above. Segments submitted 17:15 on 2 × 128, 5:30 h each: `Dctl` 8531824, `Dsq06` 8531825, `Dbc1` 8531826, `Dsq10` 8531827, `Dsq06bc1` 8531828 — both waves at once, 1.2 TB were free after Elias's clean-up. Smoke frames: 3.8 GB thinned wrfout, 2.1 GB meanout.

*Validation before any physics is read.* (1) `grep -c pbl3d_sq inc/namelist_defines.inc`, `grep -c qsq_mean inc/state_struct.inc` > 0 (G4). (2) 12-min devel smoke from the 07:00 restart with every switch on (`pbl3d_sq = 0.6`, `pbl3d_sfc_qsq_bc = 2`, `output_tke_moments = 1`), `check_tke_moments.py` on its 6-min meanouts. (3) The control segment's 07:30–10:00 frames against X7's own, per variable (`wrf3dpbl-diag/bitcompare.py`): identical ⇒ the rebuilt binary and the restart path are both proven in one run; not identical ⇒ a fresh 01→04 run from `wrfinput` on 2×128 to separate the two causes before anything else. Judges: `meta_sounding_stats` (Kolsass 08/11 UTC, Innsbruck 10 UTC), `meta_entrainment` (interface transport 09–11 UTC, ML depth at 11 UTC), `meta_surface_wind` (100 m up-valley onset time, 10:30–13 UTC excess).

---

**2026-08-27, ~15:30 — Correction: the resolved (temporal, 30-min) TKE IS in the existing WRFlux stream. No rebuild is needed for it; the plan's Part 1 shrinks to the subgrid time means.**

Elias asked for a recheck of goger18/19. goger19 adds nothing beyond goger18's `QHSP_MEAN` either.
But the 10:00 statement "no velocity variances in the meanout" was wrong in substance: WRFlux writes
the time-mean advective momentum fluxes `F{U,V,W}{X,Y,Z}_ADV_MEAN` (kinematic, m² s⁻², the product
the advection scheme transported, Hesselberg-weighted) and its own post-processing (`wrflux/tools.py`,
`adv_tend`) forms the mean part as `UX_MEAN·U_MEAN` etc. and the resolved turbulent flux as the
residual — for the diagonal terms that residual is the resolved variance:
var_u = FUX_ADV_MEAN − UX_MEAN·⟨U⟩, var_v = FVY_ADV_MEAN − VY_MEAN·⟨V⟩, var_w = FWZ_ADV_MEAN − WZ_MEAN·⟨W⟩,
tke_res_t = ½(var_u+var_v+var_w). Verified on the 13:00 frames (lowest 30 levels): 97–99 % of cells
non-negative (residual noise of order 0.05 m² s⁻²), floor-class medians at 150–350 m:

| 13 UTC, floor 150–350 m | temporal resolved TKE | w-box ±2 km (1.5 σ_w²) | u,v,w box ±5 km | subgrid |
|---|---|---|---|---|
| 3D closure | **0.36** | 0.38 | 1.12 | 0.20 |
| ICON-MYNN | **0.07** | 0.18 | 0.65 | 1.25 |

So the 3D closure resolves 64 % of the daytime floor TKE and MYNN 5 % — the temporal answer to the
partition question; the ±2 km w-based proxy was right on the floor (2× high on slopes), the ±5 km
u,v,w box 3× high (mesoscale). The 3D closure's total (0.56) is 40 % of ICON-MYNN's (1.32), as the
w-proxy said. At a single column (Kolsass) the temporal value is noisy (0.04–0.1 at 120 m by day,
1.8 in the 11 UTC onset burst) — class medians are the robust use. Level-1 reader written:
`proc/pre/wrflux_loader.py` + `df/meanframe.py` (`tke_res_t`, `var_*_t`, `ua_t`…; classic netCDF ⇒ no
dask). Still missing from the stream: the *subgrid* time mean (`QSQ_MEAN`, `W2_SGS_MEAN`) — a third
of the planned Fortran, to be bundled with the D1/D2 switches; until then the two bracketing wrfout
frames give it to 30-min sampling accuracy. The X7 10:00 meanout reads zero (6-h WRFlux setting of
that segment) — use the 30-min frames from 10:30 on.

**Addendum (16:00) — the temporal partition through the day and against the lidar.** Survey with
`tke_res_t` (floor, 150–400 m; temporal / w-box fraction): 3D closure **0.64 / 0.66** at 13 UTC,
**0.57 / 0.56** at 16 UTC; ICON-MYNN 0.05 / 0.15 and 0.05 / 0.11; goger-18 0.11 / 0.17, goger-19 0.05 / 0.09,
ECMWF-MYNN 0.09 / 0.16 — the ±2 km w-box proxy is calibrated to ±0.02 on the floor by day (on slopes it
runs 0.2 high: 0.50 vs 0.68). Lidar, Kolsass 100–1500 m, log₁₀(model/obs) with the temporal resolved part
(`tke_total_t`): 3D closure **−0.20 by day** (factor 1.6 low), −0.40 evening, −0.56 all; against −0.39 /
−0.41 / −0.83 with the w-box proxy and +0.84 / +0.97 with the ±5 km u,v,w box. D3 (A17) weakens
accordingly: the daytime shortfall is a factor 1.6, the evening one 2.5, the night unreadable. Trap: the X7
segment's meanouts are 6-h means (07, 10 UTC; the 10 UTC one all zero) — `MeanFrame.avg_interval_s`
guards them; the 3D run's temporal partition therefore starts at 10:30.

---

**2026-08-27, ~14:30 — D2 soundness check done with the i-Box, the lidar and Radfeld: the 3D closure's excess wind sits between 10 and 100 m (shear ratio 1.68 vs 1.21 observed), its q² at the lowest level is 0.17 of the surface-layer value B₁^{2/3}u*², and its master length in the lowest 60 m is 0.6 κz. Both halves of the D2 hypothesis hold.**

`proc/meta/meta_surface_wind.py` (devel-node job 8527188, 24 workers, ~1 min): the Kolsass i-Box wind at
2/4/6/12 m (1-min → 30-min means), the lidar from its first gate (57 m), the Radfeld TAWES 10 m wind,
against every run's diagnosed 10 m wind `U10/V10` and the level winds at the sites (3×3 mean, 47 half
hours); plus, hourly over the valley floor, q²(k₀)/(B₁^{2/3}u*²) with B₁ = 24 (the Mellor–Yamada
surface-layer equilibrium MYNN imposes as its lower boundary condition) and `L_MASTER`/(κz) at k₀…k₃.
Figures/CSVs: `plot_output/diagnostics/surface_wind/`.

| Kolsass, day class (local solar 09–16), mean | obs | 3D closure | ICON-MYNN | g18 | g19 | ECMWF-MYNN |
|---|---|---|---|---|---|---|
| 12 m (i-Box) / 10 m (`U10`) wind (m s⁻¹) | 3.30 | 3.62 | 2.11 | 1.39 | 1.01 | 1.53 |
| 100 m wind (lidar / model level) | 4.00 | **6.06** | 2.64 | 1.61 | 1.21 | 1.80 |
| shear ratio 100 m / 10 m | **1.21** | **1.68** | 1.25 | 1.16 | 1.20 | 1.18 |
| Radfeld 10 m, day class | 3.23 | 3.60 | 2.96 | 2.19 | 2.04 | 2.28 |
| floor, 12–16 UTC: q²(k₀)/(8.3 u*²) median (fraction < 0.5) | (1 by construction in MYNN) | **0.17 (0.91)** | 1.21 (0.00) | 1.31 (0.01) | 1.60 (0.01) | 1.28 (0.00) |
| floor, 12–16 UTC: L/(κz) at k₀ (9–11 m) … k₃ (60–75 m) | — | **0.61 … 0.70** | 1.16 … 1.36 | 1.15 … 1.35 | 1.14 … 1.35 | 1.14 … 1.35 |

Reading. At 10 m the 3D closure is the best of the five and slightly *fast* (+0.3 m s⁻¹ at Kolsass,
+0.4 at Radfeld — the earlier "6.4 vs 7.2" was the 15:00 maximum, not the day mean); at 100 m it is
2.1 m s⁻¹ too fast; the observed profile between 12 and 100 m is nearly logarithmic-flat (ratio 1.21) and
the MYNN family reproduces that shape at half the amplitude. The 3D run's error is therefore *shear in the
lowest 100 m*, not the wind aloft — the signature of momentum not being extracted from 30–150 m to the
ground. The two closure quantities that set the near-wall eddy viscosity K_m = l q S_M are both short:
q² at the lowest level is a factor 6 below the surface-layer equilibrium (the closure only floors q²,
`module_pbl3d_my.F:306`; MYNN imposes q² = B₁^{2/3}u*² and sits at 1.2–1.6 of it), and the master length
is 40 % below the wall scaling κz through the lowest four levels (MYNN's blended length is 15–35 % above
it). K_m ∝ l·q is thus roughly (0.6 × √0.17 ≈ 0.25) a quarter of what a surface layer in equilibrium
would give. This is the D2 fix as planned — `pbl3d_sfc_qsq_bc` (q²(k_ts) ≥ B₁^{2/3}u*²) plus a κz blend
of `L_MASTER` in the lowest levels — and the check now says both are needed, not either. Caveats: the
i-Box and the lidar are one site; the lidar's first gate is 57 m, so the 12→57 m gap is bridged by the
model levels only; `U10` is the surface-layer scheme's diagnostic and follows k₀ (9 m) closely in every
run.

**Addendum (windowed, 14:45) — the excess is the onset, not the regime.** Kolsass, obs 12 m / 100 m (ratio):
onset 10:30–13 UTC 2.6 / 2.5 (0.99); afternoon 14–17 UTC 6.4 / 10.0 (1.56); evening 17:30–20 UTC 3.3 / 6.1
(1.84). 3D closure: 3.2 / **6.0 (1.91)**; **6.0 / 9.4 (1.58)**; **3.5 / 6.0 (1.75)**. ICON-MYNN: 1.8 / 2.1;
4.3 / 6.4; 4.2 / 6.6. First half hour with 100 m wind > 4 m s⁻¹: observed 13:00, 3D closure **11:00**,
ICON-MYNN 13:00, goger-18/ECMWF 14:30, goger-19 15:00; at 10 m (> 3 m s⁻¹): observed 12:00, 3D 11:30, ICON-MYNN
13:00. In the established afternoon and evening regimes the 3D closure's profile is right at both levels
(within 0.5 m s⁻¹, ratio 1.58 vs 1.56 and 1.75 vs 1.84) — the best of the five by far (MYNN family 2–4 m s⁻¹
low aloft). The day-class excess comes from the onset window, where the 3D run accelerates the wind **aloft
two hours early** (6 m s⁻¹ at 100 m at 11 UTC against 1.6 observed) while the surface is only 30 min early;
the observed layer is then still coupled and calm (ratio 0.99), the 3D run's is sheared (1.91). This ties D2
to D1: the same morning in which the 3D layer is too shallow (D1) is the one in which its 100 m wind runs
away from the surface — a thin, strongly heated layer (largest HFX of the five) builds the along-valley
pressure gradient earlier, and the under-mixed surface layer (q²(k₀) = 0.17 of equilibrium, L = 0.6 κz) does
not couple the accelerating flow aloft to the ground. The near-wall deficit is persistent all day; its
observable footprint is confined to the onset because in the afternoon the resolved eddies do the coupling.
Consequence for the fix plan: the D2 test segment should be **09→13 UTC** (the onset), not 12→16; D1(1) and
D2 are judged together on that segment, with the up-valley onset time at 100 m (lidar) as the second
criterion next to the mixed-layer depth. Radfeld: the 3D run is the only one to reach the observed afternoon
10 m wind (4.5 vs 3.8; MYNN family 2.4–3.7) and the closest in the evening collapse (2.3 vs 1.0; others
3.0–3.4); no run has the observed 06–08 UTC outflow peak (3.8 m s⁻¹) — shared, hence forcing/surface.

---

**2026-08-27, ~14:00 — D1 soundness check done from the archive: the slow morning growth of the 3D closure is transport-limited. Its vertical turbulent transport of TKE at the inversion is 50× weaker than MYNN's; TKE at the interface is not at the floor; from 11 UTC every interface cell has its length scale at the buoyancy cap.**

Check as planned (plan of 2026-08-27, D1), but no restart segment was needed: the budget terms are
instantaneous fields in the half-hourly `wrfout`. `proc/meta/meta_entrainment.py`
(`entrainment_check`, 74 s on the login node): valley-floor columns with a TKE-defined layer
h ≥ 150 m, composites in normalised height z/h at 06–12 UTC of subgrid TKE, resolved w-variance
(1.5 σ_w², ±2 km), the TKE budget terms (3D: 0.5·`Q_SQ_*`; MYNN: `QSHEAR/QBUOY/QWT/QDISS`) and
the at-cap fraction (`PBL3D_N_TAU` ≥ 0.52); interface layer 0.8 < z/h < 1.2. Figure and CSV:
`plot_output/diagnostics/entrainment/entrainment_18.{png,csv}`.

| interface layer, floor class | 3D closure 09 / 10 / 11 UTC | ICON-MYNN 09 / 10 / 11 UTC |
|---|---|---|
| turbulent transport of TKE (m² s⁻³) | +2.1e-6 / +1.6e-6 / +1.4e-6 | +8.2e-5 / +9.4e-5 / +9.1e-5 |
| buoyancy destruction | −1.2e-5 / −0.9e-5 / −1.3e-5 | −2.4e-5 / −2.7e-5 / −3.2e-5 |
| shear production | +5.2e-5 / +4.2e-5 / +4.0e-5 | +3.9e-5 / +3.1e-5 / +3.9e-5 |
| transport / |buoyancy destruction| | **0.17 / 0.18 / 0.11** | **3.4 / 3.5 / 2.9** |
| TKE(h) / TKE_max | 0.17 / 0.16 / 0.14 (TKE(h) ≈ 0.05 m² s⁻²) | 0.09 / 0.09 / 0.09 (0.09–0.12) |
| resolved 1.5 σ_w² at h (m² s⁻²) | 0.088 / 0.091 / 0.092 | 0.010 / 0.019 / 0.025 |
| fraction of interface cells at the cap | 0.5 / 0.5 / **1.0** | — |
| h (median, m) | 759 / 1054 / 1244 | 879 / 1106 / 1303 |

Verdict: **transport-limited, not production-limited.** TKE at the interface is 3× the floor-class
median floor and relatively larger than MYNN's; what is missing is the flux of TKE into the
interface: in MYNN the transport term is the largest positive term there (3.4× the buoyancy
destruction it feeds — the composite shows transport removing 10⁻³ m² s⁻³ from z/h 0.2–0.4 and
depositing it at 0.5–1.1), in the 3D closure it is 50× smaller at the interface and ≥ 10× smaller
throughout the column. The interface is fed by local shear production alone and the layer grows
only as fast as the resolved eddies allow — which by 09 UTC already carry 0.09 m² s⁻² at h, twice
the subgrid TKE there. Two mechanisms, both real: (i) the q² diffusivity K_q = S_q l q with the
hard-coded S_q = 0.20 against MYNN's 3 K_m; (ii) the length scale at the interface is at the
buoyancy cap in half the cells at 08–10 UTC and in all of them from 11 UTC, which shrinks the same
K_q. Consequence for the fix order of the plan: (1) `pbl3d_sq` stays first, **but a factor 3–5 on
S_q cannot close a factor-50 gap on its own** — MYNN's transport term carries the EDMF mass-flux
(non-local) part, which no local diffusivity reproduces; expect (1) to move the 10–11 UTC depth by
a fraction of the 400 m deficit, and read the remainder as the case for (2)/(3) or a non-local
term. Also measured: the 3D closure's interface buoyancy destruction is 2–3× weaker than MYNN's —
less warm air is being entrained, consistent with the over-stable 50–500 m layer at 08–11 UTC in
the soundings.

---

**2026-08-27, ~12:00 — observation side complete for all five runs; two new diagnostics: the 3D closure is the best of the five against the radiosondes (θ RMSE 1.05 K vs 1.4–1.8; it halves the low-level warm bias), matches the lidar wind where every MYNN variant under-forecasts the afternoon up-valley wind by 2–4 m s⁻¹, but grows its morning mixed layer too slowly *as a response, not for lack of forcing*, and lets nocturnal TKE collapse with Ri faster than any MYNN variant because its length scale sits at the buoyancy cap.**

Runs: `og` ICON-MYNN 8320565, `3dpbl` stitched 9999999, `g18` 7992604, `g19` 8011253, `ecmwf`
7703194. Diagnostics extended (`wrf-proc` fb36122…da138c9): total TKE and at-cap cubes, night and
low-total masked in the fraction panels, PBLH (MYNN only — the 3D run's PBLH is a dead constant)
and radiosonde parcel depths on the BL-depth plot, closure's own N τ on the length plot, two-panel
slope wind, 50 m sounding layers, time-of-day split of the sounding biases, w-based resolved TKE in
the lidar comparison; **new**: `bl_growth` (BL depth vs cumulative kinematic heat input, by class)
and `tke_vs_ri` (median subgrid TKE per Ri_g bin, day/night). Stages run on compute nodes; the
stitched day's frames are classic 64-bit-offset netCDF and abort under the threaded scheduler
(`load_vertical_profiles` now computes single-threaded).

**Radiosondes** (9 launches, layer means, lowest 1.5 km; |bias| / RMSE):

| | 3D closure | ICON-MYNN | g18 | g19 | ECMWF-MYNN |
|---|---|---|---|---|---|
| θ (K) | **0.72 / 1.05** | 1.20 / 1.38 | 1.40 / 1.54 | 1.62 / 1.76 | 1.39 / 1.53 |
| q (g kg⁻¹) | 0.40 / 0.77 | **0.36 / 0.79** | 0.91 / 1.13 | 1.01 / 1.25 | 0.87 / 1.10 |
| wind vector RMSE (m s⁻¹) | **2.34** | **2.34** | 3.08 | 3.54 | 3.13 |

Mechanisms: the 3D run's θ bias at 50 m is +0.3 K where the others are +1.7…+2.5 K, and by day it
is −0.8 K at 50 m / +1 K at 250–750 m against +2.3…+2.9 K — weaker subgrid mixing keeps the surface
layer cooler and the residual layer less warmed; moisture follows the forcing (ICON runs −0.5 g kg⁻¹
at 100–500 m, ECMWF runs −1.5). Per-launch scalars: the 3D run's parcel mixed layer is the only one
*shallower* than observed at 10–11 UTC (330–550 m vs 900–950; the others 1100–2300 m) and matches at
13 UTC (600 vs 550); its 50–500 m stability at 08–11 UTC is 3–4.4 K against observed 0.7–1.7 K —
**the nocturnal inversion is eroded too slowly**. **`bl_growth`** shows why it is not the forcing:
the 3D run's floor sensible heat flux peaks at 175 W m⁻² (ICON-MYNN 115, goger/ECMWF 215; on slopes
315 vs 250–285), yet at equal cumulative heat input its TKE-defined layer is the shallowest of the
five (2000 K m → 1100 m vs 1400 ICON-MYNN, 1800 goger) — a closure response (weak subgrid
entrainment while the resolved eddies are still spinning up). **Lidar** (Kolsass, 100–1500 m, all
half hours): wind-speed bias 3D +0.20 m s⁻¹ (RMSE 1.6), ICON-MYNN −0.06 (1.9), goger/ECMWF −0.5
(2.1–2.4); in the afternoon the MYNN family is 2–4.7 m s⁻¹ too weak (up-valley wind), the 3D run
+1…+1.5 at 12–14 UTC and 6 m s⁻¹ at 100 m by day against 4 observed (too strong near the ground);
the evening jet (obs 9.3 m s⁻¹ at 400 m) is 8 in the 3D run, 6.5–7.5 elsewhere; at night every run
has a 3–4.5 m s⁻¹ down-valley jet at 500 m where the lidar has 2 (3D closest). TKE, log₁₀(model/obs):
3D subgrid −1.5 (day −1.1); + u,v,w box ±5 km **+0.87** (factor 7 high — the mesoscale contamination
in numbers); + 1.5 σ_w² box ±2 km **−0.39 day / −0.41 evening** (factor 2.5 low), −1.4 at night;
goger runs +0.5…+0.9 by day, ICON-MYNN −0.5→+0.3. The lidar TKE is preliminary (readme) and its
night values (0.1–1 m² s⁻² column-wide) are suspect — night TKE ratios are not to be read.
**`tke_vs_ri`**: by day the MYNN family's TKE is Ri-independent (1–2.5 m² s⁻²) out to Ri_g ≈ 2, the
3D run's 0.4–0.8; at night from Ri_g 0 to 1.5 the TKE falls by a factor 2 (ICON-MYNN), 5 (goger,
ECMWF) and **20 (3D closure, 0.28 → 0.013)** — the most Ri-sensitive scheme, and `capped` shows 80–100 %
of its live stable floor cells at the buoyancy cap through the lowest 2 km at night. Standing rule
unchanged: the cap coefficient is the lever, and it stays untouched until Elias decides on this
evidence. Figures: `plot_output/diagnostics/{turbulence,soundings,lidar}/`.

---

**2026-08-27, ~11:00 — boundary-layer diagnostics built into `proc` in three levels; first model-only survey of five runs: the 3D closure resolves 50–80 % of the daytime TKE, its nocturnal length scale sits *at* the buoyancy cap, its slope winds are the strongest and longest-lived; the sounding statistics put the ICON-forced control closest to the radiosondes.**

Elias asked for grey-zone diagnostics in the package's three-level structure (extraction →
calculation → output) and for a run over the latest g18 (7992604), g19 (8011253), ICON-MYNN
(8320565, `og`), the 3D closure (stitched day 9999999) and the latest unmodified ECMWF-MYNN run
(**7703194**, `ecmwf`; 8306272 is the `scf=5` variant and was left out). Built and committed
(`wrf-proc` 782fb45…4341982, design in `proc/docs/DIAGNOSTICS.md`): level 1 `DomainFrame` /
`DomainLoader` (full-domain fields on the mass grid, face/mass read from the array — MYNN's
`EL_PBL`/`TKE_PBL` are face fields, contrary to `compare_mynn.py`'s header; `tke` from `Q_SQ` or
`QKE`), level 2 `proc/turbulence.py` + `proc/stats.py`, level 3 `meta_sounding_stats`,
`meta_lidar_stats`, `meta_turbulence` with their plot modules. Validation: the loader reproduces
`compare_mynn`'s 04:00 / 13:00 lowest-100 m subgrid ratios (0.17 / 0.318 vs 0.17 / 0.32). Long
stages run on a compute node (`wrf3dpbl-diag/diag.slurm`; the frame loop is a process pool — 120
frames in 71 s on 24 workers; login-node dask clusters collided on the process limit).
`compare_mynn`'s `slope/spinup/lscale/exp[1–3]` are now level-2 functions; `t1/cap/exp[4–5]/fog`
stay in `wrf3dpbl-diag` (they interrogate the limiter machinery, not the boundary layer).

**Model-only survey, 18 July, hourly, lowest 2 km, terrain classes by 5 km local relief (floor
31 %, slope 62 %, ridge 3 %):**

| quantity (floor class unless noted) | 3D closure | ICON-MYNN | g18 | g19 | ECMWF-MYNN |
|---|---|---|---|---|---|
| subgrid TKE 150–350 m, 13 UTC (m² s⁻²) | **0.21** | 1.25 | 1.86 | 2.58 | 1.90 |
| resolved TKE from w (1.5 σ_w², ±2 km box), same | **0.41** | 0.22 | 0.38 | 0.26 | 0.37 |
| resolved fraction (w), 13 UTC | **0.66** | 0.15 | 0.17 | 0.09 | 0.16 |
| BL depth from TKE, 07 / 10 / 13 UTC (m) | 231 / 949 / 1536 | 474 / 1106 / 1529 | 577 / 1703 / 2002 | 633 / 1840 / 2159 | 527 / 1578 / 1885 |
| median upslope wind < 50 m on slopes, 13 / 16 UTC (m s⁻¹) | **1.24 / 0.73** | 0.98 / 0.60 | 0.80 / 0.44 | 0.65 / 0.34 | 0.77 / 0.43 |
| downslope at 04 / 19 UTC | −0.64 / −0.77 | −0.57 / −0.78 | −0.68 / −1.00 | −0.70 / −1.08 | −0.71 / −1.04 |
| L·N/q median, live stable cells, 04 UTC (resolved-gradient N) | **0.50** | 0.33 | 0.34 | 0.33 | 0.55 |

Mechanisms: (1) **Partition.** With the isotropic w-based estimate the 3D closure resolves two
thirds of the daytime floor TKE and MYNN 10–17 %; the 3D run's *total* by this measure (0.62) is
40 % of ICON-MYNN's (1.47), whereas the ±5 km u,v,w box used on 08-22/24 gave parity — the
difference is the mesoscale u,v structure inside a 10 km box. Both are stored; the w-based one is
the turbulence measure, the full one the lidar's counterpart. At night every "resolved fraction"
reads ~1 in every run: the box variance of w at night (σ_w ≈ 0.1 m s⁻¹) is gravity-wave/drainage
vertical motion over terrain, not turbulence — the night columns of the fraction panels are
uninformative by construction. (2) **BL depth.** The 3D run's TKE-defined layer grows latest and
shallowest in the morning (231 m at 07 UTC vs 470–630 m; 949 m at 10 vs 1100–1840) and peaks at
the same 1.5 km as ICON-MYNN; the goger runs and ECMWF-MYNN reach 1.9–2.3 km. The Innsbruck 10 UTC
radiosonde's parcel mixed layer is 900 m — closest to the 3D run's 949 m (different definitions,
same order). (3) **Length scale.** In the 3D run the closure's own `PBL3D_N_TAU` has p99 = max =
0.53 exactly (the cap holds) and a nocturnal median of 0.50: **at night the master length is
buoyancy-limited in at least half of the live stable cells** — the nocturnal deficit is tied to
`pbl3d_n_tau_max`, which the standing rule keeps untouched until the observations are held.
MYNN's blended length sits at 0.33 q/N at night (its α₂ = 1 cap is inert) and rises to 0.8–0.9 in
the morning transition. (4) **Slope winds** are physically ordered in every run (up by day, down
by night, 60–73 % of slope cells upslope at 10–13 UTC); the 3D closure's daytime upslope flow is
the strongest and persists two hours longer — consistent with its stronger up-valley wind at the
stations (08-24). (5) **Ri–TKE**: by day all runs keep TKE 0.1–1 m² s⁻² beyond Ri_g = 0.25 (resolved
gradients on a 500 m grid smooth thin shear layers — Ri_g is biased high); at night the 3D
closure's TKE at Ri_g > 1 spans 10⁻⁴–10⁻¹ with its bulk at 10⁻³–10⁻², MYNN's sits at its floor.
**Sounding statistics** (9 launches, layer means; the 3D run's virtual soundings are on the
compute-node job): all four MYNN-family runs are +2.4 K too warm below 500 m, fading to 0 by
1.5 km (the station warm bias, not a closure signature); the ICON-forced control is 1 g kg⁻¹
moister than the three ECMWF-forced runs below 1 km and closest to the soundings (θ RMSE 1.5 K,
wind-vector RMSE 2.3 m s⁻¹ vs 1.7–1.9 K and 3.1–3.5 m s⁻¹); the 500–50 m θ difference is captured
by all; parcel mixed-layer depths are over-deepened by all at midday. The "valley-wind layer
depth" scalar (first reversal of the along-valley component) is too noisy and will be replaced
by the height and strength of the along-valley wind maximum. Figures and CSVs under
`plot_output/diagnostics/{turbulence,soundings,lidar}/`.

---

**2026-08-27, ~10:00 — the `proc` package could not see the 3D closure's turbulence: every `3dpbl` TKE figure before today is zero. Fixed; first valid Kolsass TKE-lidar comparison running. Diagnosis scripts collected into their own repo.**

Measured on the stitched day `wrf_output/9999999`: the 3D-PBL binary writes MYNN's `QKE`,
`TKE_PBL`, `EL_PBL` as **all zeros** (max 0 at 04:00 and 13:00) while `Q_SQ` (q², twice the
TKE, m² s⁻², face levels) is 13.8 / 16.1. `proc` reads subgrid TKE only through `QKE`
(`tke = 0.5·qke`) and drops unknown names silently, so the 08-24 Kolsass TKE-lidar figure
(`plot_output/lidar/obs_VL_kol_250718_tke_obs.png`, 14:47) shows a zero curve for the 3D
closure and is **withdrawn**; the 08-24 *station* hold (T2, Q2, 10 m wind) uses no TKE and
stands. Fix (`util/wrf.py`): `"qke": ["Q_SQ", "QKE"]` — MYNN has no `Q_SQ` and falls through;
the sampler's η-linear `z_stag→z` interpolation is exactly the `0.5·(q[k]+q[k+1])`
face-to-mass average `compare_mynn.py` uses. Second fix (`proc/vars.py`): MYNN's budget names
derived from the closure's q² budget, `QSHEAR/QBUOY/QDISS = 0.5·Q_SQ_{SHEAR,BUOYANCY,DISSIP}`,
`QWT = 0.5·(Q_SQ_VDIFF+Q_SQ_HDIFF)` — factor verified in `module_bl_mynnedmf.F` (the transport
term is built from `tke_up = 0.5·qke`; Registry: "TKE production"), both schemes store
dissipation as a positive magnitude; no counterpart for `QHSP` (horizontal shear is inside
`Q_SQ_SHEAR`; `QHSP` exists only in the Goger runs) or `DTKE` — the budget plot enters them as
zero and says so. **Not fixed, by design**: `Vars.res_*` (resolved TKE/fluxes) assume
`UX_MEAN = ⟨uu⟩` etc.; WRFlux's `{U,V,W}{X,Y,Z}_MEAN` are *positional* time means (a component
moved to the flux-staggering point; there is no `W_MEAN`, no velocity variances), so resolved
TKE for the lidar needs a decision: box variance of instantaneous fields (matches a 30-min lidar
window only under Taylor's hypothesis at ≥ 5 m/s — not at night) or WRFlux's `F*_ADV_MEAN`
decomposition for fluxes. First re-run (obs + MYNN `og` + `3dpbl` + goger-19; **g18 dropped
from the overview** per Elias, login node, 8 dask workers × 6 GB): per-curve sanity numbers,
24 h × column up to ~2 km, TKE m² s⁻² — lidar mean 0.70 (max 37.5, gate outliers), MYNN 0.098,
3D closure **0.086** (no longer zero; 43 of 49 half-hours present before X9c was stitched),
goger-19 0.338. **Figure done** (`plot_output/lidar/obs_VL_kol_250718_tke_obs.png`, 09:55,
all 47 frames; 3D column mean 0.080). Reading, **subgrid only for the 3D run** (rule: judge
the grey zone by subgrid + resolved; the resolved half is not in `proc` yet, T3): the lidar
has its TKE maximum **near the ground, 17–19 UTC** (> 2.7 m² s⁻² below 300 m — the
up-valley jet's shear layer after the 15:00 wind maximum) with a mixed layer reaching
1.5–2 km by 15–19 UTC; MYNN puts its maximum in a 11–16 UTC convective column
(0.5–1.6, to 1.6 km) and has nothing in the evening shear layer; the 3D closure's *subgrid*
TKE is weak (≤ 1.1), sits in elevated plumes 600–1800 m at 12–17 UTC, and shows a faint
near-surface band 15–18 UTC where the lidar maximum is — timing right, amplitude a fraction,
as the partition predicts; goger-19 over-predicts the whole 10–17 UTC column (> 2.7).
At night all three models are near zero while the lidar shows 0.5–1 pockets at 200–800 m
(01–06 UTC) — consistent with the nocturnal deficit being real in the closure *and* MYNN
being no better here. Next: add the resolved part to the virtual lidar before reading
amplitudes.
**Numbers (10:05, `wrf3dpbl-diag/tke_lidar_bands.py`)** — Kolsass column (nearest cell),
layer-mean TKE per frame, median over the frames of each time band, m² s⁻²; models = subgrid
only, ( ) = model/lidar:

| UTC band | height | lidar | MYNN | 3D closure | goger-19 |
|---|---|---|---|---|---|
| night 01–05 | 50–200 m | 0.28 | 0.0005 (0.00) | 0.0000 (0.00) | 0.009 (0.03) |
| night 01–05 | 200–500 m | 0.19 | 0.0005 (0.00) | 0.0000 (0.00) | 0.007 (0.04) |
| morning 07–10 | 50–200 m | 0.71 | 0.37 (0.52) | 0.0005 (0.00) | 0.54 (0.77) |
| morning 07–10 | 200–500 m | 0.35 | 0.11 (0.33) | 0.0004 (0.00) | 0.33 (0.95) |
| afternoon 12–17 | 50–200 m | 1.10 | 0.69 (0.63) | 0.46 (0.42) | 1.33 (1.21) |
| afternoon 12–17 | 200–500 m | 0.48 | 0.75 (1.57) | 0.22 (0.45) | 1.62 (3.39) |
| afternoon 12–17 | 500–1000 m | 0.45 | 0.65 (1.44) | 0.35 (0.77) | 2.08 (4.62) |
| evening 18–21 | 50–200 m | 0.94 | 0.09 (0.09) | 0.31 (0.32) | 0.26 (0.28) |
| evening 18–21 | 200–500 m | 0.85 | 0.02 (0.03) | 0.18 (0.22) | 0.16 (0.18) |

Three things the figure only hinted at. (1) **At the valley floor both closures are
laminar at night**: MYNN's subgrid TKE at Kolsass is 5·10⁻⁴, three orders below the
lidar's 0.2–0.3 — the domain-wide "3D = 0.17 of MYNN" nocturnal ratio is a slope/ridge
statistic, and "MYNN over-mixes at night" is not what this column shows; whether the
lidar's 0.2–0.3 is turbulence or the VAD product's noise floor (EDR is in the same files)
must be settled before it becomes a target. (2) **The 3D closure's subgrid TKE stays at
the floor through the morning transition (07–10 UTC, 5·10⁻⁴) while MYNN carries half the
lidar's** — the 08-22 partition result (subgrid 0.28 of MYNN, 85–91 % resolved) was at
08:00 domain-wide; at this column the subgrid part is 10⁻³ of MYNN's, so either the
resolved motions carry it all here or the morning onset at the valley floor is late.
Decidable from a Kolsass box variance at 08:00–10:00 — not yet run. (3) **Evening**:
after the 15:00 wind maximum the lidar holds 0.9 m² s⁻² below 500 m until 21 UTC; MYNN
collapses to 0.03–0.09 of it, the 3D closure keeps 0.2–0.3 — 3–7× MYNN, the same
direction as its better daytime up-valley wind at the stations. Housekeeping:
`synthesize_day.sh` re-run — X9c (8502167) is now in the stitched day, **47/47 half-hour frames**;
X9n (8492417, night under the fix) completed 08-24 21:57, not yet compared with X7. New repo
**`$DATA/wrf3dpbl-diag`** (github.com/elias-wahl/wrf3dpbl-diag, private): `compare_mynn.py`,
`qsq_budget.py`, `compare_lfix.py`, `gate_x7_to_x8.py`, `check_wrfinput.py`,
`synthesize_day.sh`, `run_tke_lidar.py`, README with question/usage/reference numbers;
edit there, `sync_to_branko.sh` copies the SLURM-referenced ones back. `proc/README.md`
written (package map, traps T1–T9); conda env is `proc`, not `wrf`.

---

**2026-08-24, ~14:30 — first hold against station observations: the 3D closure captures the daytime up-valley wind that MYNN under-forecasts. Station data ARE on disk.**

Correction to a standing note: **i-Box/TAWES station observations for 18 July are on disk**
(`data/stations/kol`, `data/stations/rad`) and the `proc` package reads them — the "ask for
observations" item was wrong for stations (soundings/lidar also present: `data/lidar/kol`).
Ground-station comparison (`meta_station.plot_kol_station_comparison` / `_rad_`, obs vs
ICON-MYNN control 8320565 "og", the stitched 3D day 9999999 "3dpbl", goger 18/19), 2 m
temperature, 2 m mixing ratio, 10 m wind, 15-min running mean, day 01:00 → 20:30 (evening
pending X9c):

| 10 m wind, daytime maximum | Kolsass | Radfeld |
|---|---|---|
| observed | 7.2 m s⁻¹ (15:00) | 5.2 m s⁻¹ (15:00) |
| **3D closure (9999999)** | **6.4** | **5.4** |
| MYNN control (og) | 4.4 | 4.2 |
| goger 18 / 19 | 4.3 / 5.3 | 3.5 / 3.5 |

**This is the observational hold the standing rule required before touching constants**: the
valley-wind deficit is MYNN's, not the closure's — the 3D run is within 0.8 m s⁻¹ of the
observed maximum at Kolsass where MYNN is 2.8 m s⁻¹ low, and it reproduces the 12:00–16:00
plateau shape at both stations. Moisture: 3dpbl is the moistest model and the closest to
observations all day (Kolsass 8.5–10.3 vs obs 10–12 g kg⁻¹; MYNN 6.9–9.6). Temperature:
daytime maximum best of the four at Kolsass (25.0 vs obs 25.8; goger 19 27.4), but **all
four models share the nocturnal and evening warm bias** (obs 9–10 °C at 02:00, models
12–15; after 18:00 obs cools to 12.5, models hold 16–20) — not a closure signature.
**Two failures to chase**: (1) at Radfeld every model, the 3D run worst (~0.2 m s⁻¹),
misses an observed 3.5–4 m s⁻¹ wind between 06:00 and 09:00; (2) a single-frame spike in
3dpbl 2 m mixing ratio at Kolsass at **10:30** to 13.1 g kg⁻¹ (neighbours 8–10) — the frame
right after the X7→X9a seam and inside the old A14 window; check `PBL3D_COND_M` and the
seam before reading anything into it. Figures:
`plot_output/stations/obs_og_3dpbl_g18_g19_obs_07-18_01_{Kolsass_i-Box,Radfeld}_24h_…png`.
Package changes: `pre/setup.py` skips missing frames instead of aborting the whole
comparison (a partial day used to kill it); `config.yaml` carries `9999999` + the ICON run
with `3dpbl` colour; login-node runs must throttle the dask cluster (48 workers × 4.5 GB in
the config is a compute-node setting).

---

**2026-08-24, ~11:00 — X9n (the night under the fix) queued; the segmented day stitched into pseudo-job `wrf_output/9999999` for post-processing.**

**X9n** (8492417, 01→10, 7:45 wall): the X7 run dir replicated symlink for symlink, X7's
namelist bit for bit plus only `pbl3d_moist_cond_max = 1e4` (diff verified: one line), same
binary, same 2×128 layout, output root `exp/X9n`. X7's night frames stay untouched — X9n vs
X7 is the statistical answer to whether the moist acceptance shifts the stable-regime
equilibrium (expectation: no — cond ≥ 1e3 was 0.25 % of solves even in convective air).
**Pseudo-job 9999999**: `realcase/scripts/synthesize_day.sh` symlinks the segmented day
(X7 01→10, X9a 10→16, X9b/X9c as they archive) into `$DATA/wrf_output/9999999/` next to the
MYNN control, first segment wins at seams, provenance in its `job_info.txt`; idempotent —
re-run it after each segment archives (16 of 47 half-hour frames pending X9b/X9c as of
11:00). Smoke-tested through `compare_mynn.py`: 04:00 gives the known nocturnal ratio 0.17,
13:00 the daytime partition 0.32. Caveat carried in the script header: 01→10 is the pre-A14
binary, 10→24 the fixed one — the composite is for post-processing convenience, not a claim
of one continuous integration.

---

**2026-08-24, ~10:15 — X9a passed the A14 crash window in production; gate footprint measured and small; the chain completed with X9c; interpretation gate for the daytime fluxes considered met.**

X9a (8489332, 10→16 from X7's 10:00 restart, switch 1e4) COMPLETED through the window
that killed X8a five times; X9b (8492003, 16→22) running; the missing last segment
**X9c 22→00 queued this session as chain link 8492402** (afterok X9b, same EXTRA_SETS) —
the 23 h day is now SLURM-resident end to end. Gate measurements (wrfout 10:30/12:00/16:00):
`PBL3D_COND_M` — the condition number of the *accepted* moist solve — maxes at 9 998–9 999,
i.e. pinned just under the 1e4 threshold: the acceptance fires and the length-scale back-off
always lands the solve back inside validity; **zero faces ever reached the terminal
no-transport state in 6 h**. Accepted solves with cond ≥ 1e3 are 0.25 % of ~12 M solves per
frame; ~600–800 faces/frame sit within 10 % of the threshold. Total back-off activity
(`PBL3D_T2_STEPS` > 0): 1.42–1.53 M faces vs 1.35 M in X7's pre-fix 10:00 frame — the moist
gate adds a few percent on top of the heat-side gates, mean escalation depth unchanged
(1.22 steps). Verdict: the fix is a small-population length-scale nudge, not a regime change;
the daytime fluxes are interpretable. **Afternoon energy partition confirms the 08-22
convective result**: at ~43 m, resolved+subgrid TKE (10.5 km box-mean perturbations) is
4.13 vs MYNN 3.65 m² s⁻² at 12:00 and 3.14 vs 2.64 at 16:00, 86–87 % resolved — the
subgrid ratio 0.36 (lowest 100 m) is grey-zone partition all afternoon. 10 m wind bias
−0.2…−0.4 m/s, flat across slope bins. Also this session: `setup_restart_run.sh` never
linked the *default* `iofields_lscale.txt` into the run dir (E21) — X9a/X9b ran with 62
"Problem opening" warnings; harmless to the science (every addition is already a Registry
history field) but the `A*TEN` removals didn't apply, so their frames are ~10 % fatter;
fixed in the script, X9c gets the file. Open: whether the night statistics shift under the
fix needs an X9 night segment (01→10) — not queued; disk 516 GB free at 95 %, X9b+X9c need
~270 GB.

---

**2026-08-24, 01:15 — A14 fix implemented, validated bit-for-bit, and the first 6 h segments queued with it enabled (Elias approved).**

`pbl3d_moist_cond_max` (Registry default 0 = off): moist-solve acceptance gains a raw
condition-number test feeding the existing length-scale back-off; exhausted escalation now
terminates in no organised moisture transport; new PBL3D_COND_M history field. Rebuild
`--reconfigure` clean (ldd clean). Validation on devel from the 10:17 re-entry restart:
**switch off = FAILED at 10:18:00 with the exact old fingerprint (25 pts, (467,107,3),
W -22.07 / -161.94) — bit-for-bit equivalence of the default proven; switch = 1e4 =
COMPLETED through 10:19, zero CFL, killer column physical (theta' 2.42 K, qv 7.5/6.7 g/kg,
q^2 unchanged).** Queued: **X9a** 8489332 (10->16 from X7's 10:00 restart, 2x128, 5:30,
WRFlux 30 min, switch 1e4, exp/X9a) and chain link 8489333 (afterok) building **X9b**
16->22 the same way (chain_segment.slurm now forwards EXTRA_SETS). Gate for interpreting
X9a/X9b: check PBL3D_COND_M and the T2 back-off statistics before trusting the fluxes;
compare against MYNN 8320565 statistically. X8a/X8b/X8c naming retired; X9* is the
fixed-binary series.

---

**2026-08-23, late — A14 mechanism confirmed and closed to a pole of the moist flux system; fix proposed, not implemented.**

Print-only instrumented rerun (bit-identical) caught the killer call: wqv = +2.0167 kg/kg m/s
accepted with mat_cond_moist = 5.97e7 (heat-side condA 100 — the only one ever output);
standalone replay reproduces it exactly and maps a simple pole of the moist 4x4 determinant
at dthetav_dz = -0.02313 K/m (unstable-side N tau ~ 0.27) for the killer cell's l, q^2.
Routine background: 90 accepted calls with wqv >= 500x physical in 45 steps. The dry-theta
flux is reconstructed from wqv, so the moist pole poisons theta too. Proposed (review
pending): cond-number acceptance for the moist solve feeding the existing l back-off +
moist terminal state, one default-off switch `pbl3d_moist_cond_max`; PBL3D_COND_M output.
No source changed; production binary untouched.

---

**2026-08-23 (VSC-5) — X8a crashed at 10:18; 23 h chain halted; the blow-up is the moist/heat flux solve returning an unbounded solution at an unstable-side neutral crossing (OPEN_ISSUES A14). Diagnosis campaign, all on the devel QOS.**

X8a (8483962) backfilled at 16:46 and died 18 simulated minutes in: at (i=467, j=107), a
1500 m slope cell, between 10:17:58 and 10:18:00 one closure call returned a vertical
moisture flux ~10^4 x physical at the k=1/2 face (qv: 7.47 g/kg -> 0 clamped at k=1,
240.9 g/kg at k=2) with the matching virtual-heat flux; theta' +224 / -111 K on the two
levels, |W| > 160 m/s two steps later, sfclay NaN, MPI abort. q^2, the stresses, L, and
all q^2 budget terms stayed frozen through the event; the theta gradient at that face was
crossing zero at exactly that step.

Established today, each point measured:
- **Deterministic**: five bit-identical reproductions on 2x128 (X8a, R2 8487343, S3 8487735,
  S3R 8488056, S3FR 8488057 — identical CFL prints to the last digit). A 5-node (8487342)
  and an 8-node (8487817) run pass the window but were observed only 60-80 s beyond it —
  decomposition shifts where/when the critical crossing lands (E14), it does not remove it.
- **Not a restart artifact**: write/read cycles are bit-transparent — R2 (continuous from
  10:00) equals the S1->S2 chain (seams at 10:06/10:12) exactly, field by field, at 10:12.
  Devel-queue segment chaining (6-min segments, restart each end) is now a validated
  instrument; 10:17 re-entry restart exists (`innval_pbl3d_X8aT17/wrfrst_..._10:17:00`).
- **Not memory**: a bounds-checked + snan-initialized build (`branko_dbg`, production tree
  untouched) ran 10:17->10:19 with zero out-of-bounds and no uninitialized-local traps.
- **Why every gate passes** (code, `module_pbl3d_my.F`): acceptance tests PSD of the
  *stresses* only (they stay sane); `dgesvx` `FACT='E'` returns the *equilibrated* rcond, so
  the near-critical buoyancy coupling is scaled away (condA ~100 at the killer cell); the
  moisture variance that should bound `wqv` by Cauchy-Schwarz is *diagnosed from the same
  fluxes* — the bound inflates with the violation.

Retraction: a non-determinism scare (one "surviving" repeat) was my submission error — the
run was on 8 nodes via the template SBATCH header (KNOWN_ISSUES E20). Retracted same session.

Consequences: X8b/X8c stay down (X8b link 8483963 cancelled by hand); any convective segment
would hit its own crossing within minutes. Next: offline single-cell replay of
`Solve_turb_system_moist` with the exact 10:17:58 frame inputs to confirm the critical-point
divergence, then a fix proposal (an absolute, gradient-based bound on the scalar fluxes,
default-off) for soundness review. Runs kept: `exp/X8aR2` (1-min budget 10:00->10:18),
`exp/X8aS3FR` + `exp/X8aS3F` (2-s frames around ignition), `exp/X8aR5` (5-node control).

---

**2026-08-22 (VSC-5), 22:55 — Amendment: WRFlux means at 30 min from now on; segments start at X7's end (10:00), no boundary alignment needed.**

Elias: 6-h means are not interesting; 30-min means for every run from here on. With 30-min means
the 6-h alignment argument of the 22:40 entry lapses, so the overlap with X7 is dropped: the
07:00-based X8a (8483937) and its link were cancelled before starting; the chain is now
**X8a 10→16, X8b 16→22, X8c 22→00** (`--wrflux-min 30`, 5:30/5:30/2:00 limits), first link
8483940 `afterok` X7 (8483386) from X7's 10:00 restart. `chain_segment.slurm` carries
`WRFLUXMIN` and a second look-ahead (`NEXT2_*`). X8 (18 h, 6-h means — now also the wrong
output configuration) is cancelled once X8a runs.

Disk: `/gpfs/data` at 93 %, 724 GB free; the 14 h of segments at 30-min WRFlux (10.1 GB per
frame) + 30-min history (5.6 GB) + restarts ≈ 485 GB. Proposed to Elias: delete `exp/A12`,
`exp/A13` (withdrawn), `exp/X0–X5` (pre-fix; night statistics recorded), `exp/smoke` ≈ 620 GB;
keep F1 (bug documentation) pending his decision; his own `wrf_output/` archives (~700 GB each)
untouched. **Elias: delete A12, A13, X0–X5, smoke — done 23:00** (≈ 620 GB freed). Restart-fidelity check now runs X8a's 10:30 frame onward against nothing directly
(X7 ends at 10:00) — instead it is the X8a 10:00 initial frame vs X7's 10:00 history frame
(must be identical by construction) and the continuity of the slope × height statistics across
10:00; recorded when available.

---

**2026-08-22 (VSC-5), 22:40 — The 23 h run is done as restart segments on the WRFlux boundaries, chained inside SLURM; MUSICA dropped; X8 (18 h) to be cancelled once the first segment runs.**

Elias's proposal, checked against the queue record: every 2-node job of ≤ 5:30 h submitted since
2026-08-20 started within 20 min (A12/A13/F1/X6r in seconds, X6 at 5:30 in 19 min); 7:00–8:00 h
waited 1–18 h; the 18 h X8 is estimated for Tuesday. `--test-only` gives "30 Aug" for *every*
limit — it models priority, not backfill, and is useless for this. MUSICA (connection works via
the live master socket; tree pulled to HEAD and rebuilt; 12 h estimate Sun 17:49) is not needed
at that rate and is dropped — nothing was submitted there.

Design. X7 (01→10) *is* the first 9 h of the X8 configuration (identical namelist). Continuation
segments start from restart files and **must sit on the WRFlux 6-h averaging boundaries**
(07, 13, 19, 01): the mean fields are `h{24}` only, not restart-carried, so a restart inside a
window truncates that window's budgets. Segments: **X8a 07→13** (from X7's 07:00 restart, job
8483937, 5:30 limit; redoes 3 h of X7 = 2 h wall, the price of clean budgets), **X8b 13→19**,
**X8c 19→00** (5:00 limit). X8b/X8c are built and submitted by `chain_segment.slurm`
(devel QOS, `afterok` the previous segment; link for X8b = job 8483938, which queues the X8c link
itself). Output roots `exp/X8a`, `exp/X8b`, `exp/X8c`; night and 07–10 from X7.

Restart fidelity (asked): the closure's prognostic state — `q_sq`, `tsq`/`qsq`/`cov`,
`l_master`, `l0_asym`, `el_pbl`, the pairing accumulators `ke_loss_h`/`qsq_shear_h` — is in the
restart stream (`r` in the Registry); only the per-step limiter diagnostics are not, and they are
recomputed every step. Noah-MP, RRTMG and Thompson carry their state in the restart. On the same
2 × 128 layout a WRF restart is designed to be exact; the 2026-08-21 continuations reproduced
X6's 07:54 collapse from the 07:00 file. The direct test is free: X8a's 07:30–10:00 frames
against X7's — if the restart is exact they are bit-identical; if not, the statistics say how
far apart. To be run when X8a's 08:00 frame lands; result goes here.

Trap found on the way: the restart tool's namelist came out with `pbl3d_l0_min = 8.0`,
`pbl3d_init_opt = 1` (template values) and `restart_interval = 0` — fixed in X8a's namelist
before it started, passed as `--set` in the chain, recorded as KNOWN_ISSUES E19. The diff of
X8a's namelist against X8's is now empty apart from dates, length and paths.

---

**2026-08-22 (VSC-5), 22:20 — The convective-regime q² ratio (0.28 of MYNN) is a resolved/subgrid partition, not a mixing deficit; the nocturnal 0.16 is not covered by this.**

X7 08:00 (10:00 local), land cells with HFX > 50 W m⁻², medians. Surface heat flux 177 vs 158 W m⁻²
(MYNN), mixed-layer depth by θ + 0.5 K 820 vs 631 m, w* 1.57 vs 1.36 m s⁻¹ — the 3D run's boundary
layer is deeper and more vigorous, yet its subgrid q² in the lowest 100 m is 0.54 vs 1.95 m² s⁻²
(q²/w*² 0.22 vs 0.97; observed lower-CBL value ≈ 1). Resolved kinetic energy (11 × 11-cell box
variance of u, v, w; 2·TKE_res) at 43 / 96 / 177 / 315 m: X7 3.29 / 2.76 / 2.29 / 2.11, MYNN
1.77 / 1.67 / 1.50 / 1.36; resolved σ_w² X7 0.13 → 0.22, MYNN 0.07 → 0.10. **Subgrid + resolved:
X7 3.89 / 3.19 / 2.58 / 2.31, MYNN 3.72 / 3.62 / 3.33 / 2.88** — equal near the surface, the 3D
total falling off faster with height. Resolved share 0.85–0.91 in X7, 0.46–0.48 in MYNN (the
latter largely terrain mean-flow variance the 5.5 km box cannot separate; the *difference* between
runs is the convective part). Reading: at dx = 500 m the closure lets the convection be resolved
(grey zone), MYNN mixes it subgrid; the 0.28 subgrid ratio is partitioning, consistent with the
deeper mixed layer and larger HFX. This does *not* apply at night — no resolved turbulence at
500 m in stable air — so the nocturnal 0.16 remains the closure's stable-regime equilibrium
(or MYNN over-mixing), as before. Whether the deeper 3D morning boundary layer is right needs
profile/mixed-layer observations; 2 m fields agree with MYNN to 0.2 K in both. Also at 08:00:
10 m wind bias −0.1…−0.25 m s⁻¹ by slope; strain cap active in 17 % of live cells (night: 56 %).
Method caveat: box variance over complex terrain is an upper bound on resolved turbulence.

---

**2026-08-22 (VSC-5), 21:25 — X7's morning is clean: the withdrawn morning results were the albedo bug; what remains is a q² deficit of 0.25–0.35 of MYNN in the young convective layer.**

Measured on X7's 06:00 and 07:00 frames (`compare_mynn.py fog`, gate script), against X6 (bug) and
the MYNN control:

| 06:00, land | X6 (bug) | X7 (guard) | MYNN |
|---|---|---|---|
| fog fraction (cloud below level 12) | 3.1 % | 0.2 % | 0.0 % |
| cells with T2 < 270 K | 5 199 | 1 | 2 |
| drainage cells (> 15 m s⁻¹ at level 1) | 120 | 0 | — |
| T2 1st percentile, 2000–2500 m N-facing | 268.5 K | 277.1 K | 277.2 K |
| T2 median, < 1000 m flat | 288.0 K | 289.1 K | 289.1 K |
| HFX / LH, 1000–1500 m N-facing (W m⁻²) | 138 / 49 | 109 / 53 | 89 / 57 |
| skin − air temperature, same band | 1.7 K | 1.2 K | 0.9 K |
| q², same band (m² s⁻²) | 0.82 | 0.30 | 1.04 |

07:00 gate (b): 0 land cells with negative albedo, T2 1st percentile 276.1 K, 0 cells < 270 K,
0 cells > 15 m s⁻¹ at level 1 — all pass with wide margin. The bug's footprint started with the
first diffuse beam, not at 07:00: at 04:00 X6 already had 89 177 land cells (30 %) with albedo
−9999 and 30 % of the land dark in SWDOWN; X7 none.

Conclusions. (1) Every morning result retracted on 2026-08-21 is confirmed as U3: 2 m temperature
of the closure agrees with MYNN to 0.1–0.2 K in all 15 terrain-band × aspect classes, fog, cold
cells and drainage jets are absent. (2) The closure's own morning signature is a q² of 0.25–0.35
of MYNN in the young convective layer (08:00 local, HFX 60–110 W m⁻²), less than the nocturnal
deficit (0.16) but present; the weaker near-surface mixing shows as a 0.3 K warmer skin, ≈ 20 %
more sensible and 5–10 % less latent heat flux than MYNN. Whether the ratio closes as the mixed
layer deepens is what 08:00–10:00 of X7 and the afternoon of X8 will show. (3) X6's larger morning
q² (0.6–0.8) was the spurious drainage shear, not a healthier closure. The old crash point
(07:54:30) is passed at ≈ 21:45 wall; X8 stays queued on its own (Priority).

---

**2026-08-22 (VSC-5), 17:45 — X8 released from the X7 gate; the gate is report-only; the surface-layer bounds stay.**

Elias: queue the 23 h run now, it will not start soon anyway. Two findings from X7's first hour
forced a change to the 22:30 gate:

1. **X7 is not bit-identical to X6** (02:00: max |ΔT| 3.2 K, |ΔU| 9.4 m s⁻¹, rms ΔT 0.005 K,
   99 % of cells differ in the last bits). Binary and `wrfinput` are md5-identical; the cause is
   the namelist: X7/X8 carry the 17:00 surface-layer bounds (`sfclay_ust_min = 0.03 m s⁻¹`, floor
   on the friction velocity u* = surface-stress scale; `sfclay_zol_max = 10`, cap on z/L), X6 did
   not. Measured at 02:00 over 297 582 land cells: X6 has u* < 0.03 in 19 % of them (< 0.01 in
   3.7 %); in X7 18 % sit exactly on the floor. Footprint: domain-mean sensible heat flux
   −31.89 → −31.88 W m⁻², mean ΔT2 in the floor cells −0.0006 K, u* median 0.102 unchanged; the
   1.1 % of cells with |ΔT2| > 0.1 K are *not* the floor cells (chaotic spread). So the floor is
   active over a fifth of the nocturnal land but thermodynamically inert; what it changes is the
   surface stress (and so the lower q² boundary) in the calmest cold-pool cells — to be read in
   the 03:30 night statistics (`compare_mynn.py exp`), not assumed. The "harmless, bit-neutral at
   night" statement of the 17:00 entry was an inference and is retracted as *bit*-neutral;
   *physically* harmless stands on the numbers above. Decision (Elias): no unphysical behaviour
   seen → X8 keeps the bounds, identical to X7.
2. Criterion (a) of `gate_x7_to_x8.py` (03:30 frame bit-identical to X6) would therefore have
   failed and cancelled X8 at ≈ 23:00 for a wrong reason. (a) is now report-only (max and rms
   printed); (b) the 07:00 albedo-signature checks and (c) a finite 10:00 frame remain the
   verdict on X7's morning, but the gate no longer cancels anything unless `X8_JOB` is exported.
   X8 (8483404) was released (`scontrol update Dependency=`); the gate job was resubmitted
   report-only behind X7. If X7's morning fails, X8 (queued, 20 h limit) is to be cancelled by
   hand — it will not have started by then.

**Measured at 03:00 and 03:30 (18:30):** the night is statistically the same run. q² in the lowest
100 m: 0.0476 → 0.0469 m² s⁻² (−1.5 %), both 0.16 of MYNN; the 20 slope × height ratios agree to
two decimals (largest bin change +2 %); 10 m wind bias by slope identical to 0.01 m s⁻¹;
length-scale floor fractions and median master length scale identical at every level; strain-cap
footprint 0.560 in both. The u* floor does not reach q² in any bin — the stable-regime deficit is
unchanged, and X7's night stands in for X6's. (The lowest-100 m shear/KE-loss residual of
`compare_mynn.py exp [5]` differs more, 0.87 vs 1.01, but that number moves by 0.15 between X6's
own 03:00 and 03:30 frames — a transport-limited diagnostic, not evidence.)

X7 timeline (1.43 s/step = 43 min wall per simulated hour, started 16:36): 03:30 ≈ 18:20,
07:00 ≈ 20:50, the old 07:54:30 crash point ≈ 21:30, end 10:00 ≈ 23:00.

---

**2026-08-21 (VSC-5), 22:30 — The 23 h run is queued behind X7, with an automatic gate.**

Agreed with the user: if X7 (job 8483386, paired configuration + albedo guard, 01:00→10:00) runs
without obvious flaws, the 23 h run starts without a further decision. Implemented so that it
survives a session restart: **X8** = job 8483404 (`branko_runs/innval_pbl3d_X8`, output root
`exp/X8`, same configuration, 2025-07-18 01:00 → 2025-07-19 00:00, `restart_interval=180`,
history 30 min, WRFlux averages every 6 h, 2 nodes, 20 h wall requested) is submitted with
`--dependency=afterok:8483386`, so SLURM starts it only if X7 exits successfully. The session
monitor adds the quality gate and cancels X8 if X7 fails it: (a) X7's 03:30 frame must be
bit-identical to X6 (U, T, q², TSK — the night has no short-wave, so the albedo guard must change
nothing); (b) at 07:00: all temperatures finite, no negative land albedo, 2 m temperature first
percentile above 271 K (the buggy run had 265.0, MYNN 276.2), fewer than 2 000 cells below 270 K
(20 933), fewer than 200 cells with more than 15 m s⁻¹ at 8 m (1 458). If X7 crashes, the
dependency alone prevents X8. The control question stands: the MYNN control's topographic shading
is inert, so a MYNN run on this build (with the guard) is the like-for-like morning reference —
not queued, the user's call.

*Addendum 23:05 — gate moved into SLURM.* The session monitor that held the gate does not
survive a session restart (three restarts today), so the gate is now a job of its own:
**8483413** (`realcase/scripts/gate_x7_to_x8.slurm` → `gate_x7_to_x8.py`, devel QOS, 1 node,
`--dependency=afterok:8483386`), and X8's dependency was re-pointed to `afterok:8483413`. The
script applies the criteria above — (a) 03:30 U, T, q², TSK bit-identical to X6, (b) the 07:00
thresholds, (c) a finite 10:00 frame — and `scancel`s X8 on failure. Tested on the X6 archive:
(a) passes, (b) fails on all four counts (39 859 negative land albedos, T2 p1 265.0 K, 20 933
cold cells, 1 458 fast cells), (c) fails — i.e. it detects the bug it is meant to exclude.
Output: `branko_runs/innval_pbl3d_X7/gate_X7_8483413.out`.

---

**2026-08-21 (VSC-5), 22:15 — ROOT CAUSE of the morning failures: an undefined land-surface albedo (−9999) reaches the short-wave radiation scheme in terrain-shaded cells. A model bug, not closure physics. Guarded; the morning has to be re-run.**

**How it was found.** The θ budget of the cloud layer from the WRFlux averages (06:30–07:00,
run 8478327 vs MYNN 8320565, same columns): long-wave, microphysics and turbulence terms are
ordinary, but the **short-wave radiative tendency is −10 to −14 K h⁻¹ throughout the lowest 750 m
at 09:00 local — in cloud-free high-terrain columns as much as under the fog** (MYNN: +0.06 K h⁻¹).
Short-wave radiation cannot cool. The raw `RTHRATEN` in the 07:00 restart: median ≈ 0, 1st
percentile −85 K h⁻¹, extreme −232 K h⁻¹ (04:00: a normal −0.15 / −2). The columns: 27 740
(9.3 % of the domain), all land, median 1660 m, **all in terrain shadow (median SWDOWN 16 W m⁻²,
diffuse only)**; the cooling profile is smooth, −80 K h⁻¹ at the surface to −40 at 750 m; only
17 % have any cloud. In those columns **`ALBEDO` = −9999** (lit land 0.145), diffuse surface flux
−480 W m⁻², slope-normal flux −127 W m⁻²: RRTMG-SW reflects −9999 × the beam.

**The chain.** `ALBEDO < 0` on every land cell with SWDOWN < 50 W m⁻² — all land at night
(297 582 at 03:00) and the shaded cells after sunrise (55 011 at 05:30, 39 859 at 07:00); the
cold cells (T2 < 270 K) are a subset (1 222 of 1 391 at 05:30; 13 713 of 20 933 at 07:00). The
refactored Noah-MP driver of 4.8 writes `NoahmpIO%ALBEDO(i,j) = AlbedoSfc` unconditionally
(`phys/noahmp/drivers/wrf/EnergyVarOutTransferMod.F90:140`), and `AlbedoSfc` is the undefined
marker wherever the land surface receives no short-wave; WRF 4.6's driver guarded it
(`IF (SALB > -999) ALBEDO = SALB`, `module_sf_noahmpdrv.F:1231`). Harmless at night; with working
topographic shading a shaded cell has cos(zenith) > 0 and the SW scheme uses the value. The
control (stock 4.6.0) never meets the case: no negative albedo, and its topographic shading is
effectively inert (196 shaded land cells at 07:30 local, 0 at 09:00, against 55 000 / 40 000 here —
implausibly few for the Inn valley, so the *control's* morning insolation is also suspect).

**Consequences (all measured before, now explained).** From ~04:00 the shaded high terrain cools at
80 K h⁻¹ in the radiation term; by 07:00 7 % of the domain is below −3 °C, the air saturates into
fog/stratus over 10 % of the cells (which then shades more cells), skins decouple, cold air drains
at 15–25 m s⁻¹, a column collapses numerically (07:54 in the continuation; the ridge-top shear
runaways of 05:52–06:14 in the unpaired runs sat on top of it). The **nocturnal results stand**
(no short-wave, albedo unused): the stable-regime q² deficit, its Ri dependence, the energy-pairing
measurement, the strain-cap result. Everything said about the *morning* — the fog feedback, the
decoupling statistics, the +3 m s⁻¹ wind bias at 07:00, the surface-layer NaN — was downstream of
this bug and is withdrawn as closure physics; the surface-layer guard and bounds stay (harmless;
the detector found the NaN in minutes).

**Decision.** Guard at the point where the value enters WRF, `phys/module_surface_driver.F` after
the Noah-MP call: `IF (ALBEDO(I,J) < 0.) ALBEDO(I,J) = ALBBCK(I,J)` (background albedo; the lit
value is not available there, and the short-wave in such a cell is a few W m⁻² of diffuse light,
so the fallback is immaterial). No switch: the previous behaviour is garbage radiation, and the
nocturnal reference is unaffected (ALBEDO at night changes in the output, not in the physics).
Upstream report as **U3** (Noah-MP refactor dropped the albedo guard; reproduces with
`sf_surface_physics=4`, `topo_shading=1`, any PBL scheme). Incremental rebuild, then **X7** =
paired configuration, 01:00→10:00 — the first morning of the 3D closure free of the bug; its night
must be bit-identical to X6 through 03:30 (a verification), its morning is new information.
F2/F3 of the fog plan are dropped (their premise is gone); F1 (job 8483357, running) documents the
bug's time evolution at 5 min and is kept.

---

**2026-08-21 (VSC-5), 18:50 — With the surface-layer guard the continuation reaches 07:54, then the atmosphere itself blows up; the morning failure is a fog / cold-air feedback over the high terrain that the weak stable-regime mixing lets run away.**

**Measured.** The 12-minute guard test (job 8481844) passes 07:10 without NaN; every land cell
has u* ≥ 0.030 exactly (the floor acts; Noah-MP does not overwrite u*). The 07:00→10:00
continuation (job 8482046) then dies at 07:54:30 with the new NaN detector firing in the
surface layer at i = 221, j = 22 — a valley-floor cell at 294 m — with **air at 217 K and 29 m s⁻¹
at the lowest level** under a 284 K skin: the atmospheric column had already collapsed; the
surface NaN is a symptom. At 07:30 that column was a neutral 282 K easterly jet of 13 m s⁻¹
at 17 m AGL, q² ≈ 5 m² s⁻², unremarkable.

**The domain-wide picture after sunrise** (3D paired run vs MYNN):

| | T2 1st pct (K) | cells T2 < 270 K | cells wind > 15 m s⁻¹ at 8 m | land with SWDOWN < 50 W m⁻² | cells with low cloud |
|---|---|---|---|---|---|
| MYNN 05:30 | 275.3 | 7 | 16 | 0.1 % | 0.3 % |
| 3D 05:30 | 271.2 | 1 394 | 6 | 18.6 % | 2.5 % |
| MYNN 07:00 | 276.2 | 0 | 3 | 0.0 % | 0.0 % |
| 3D 07:00 | 265.0 | 20 933 | 1 458 | 13.5 % | 10.1 % |
| 3D 07:30 | 263.8 | 25 225 | 2 750 | — | — |

(both runs use the same radiation, `slope_rad=1`, `topo_shading=1`; low cloud = qc+qi > 1e-5 kg kg⁻¹
below ~k25, max qc 2.1 g kg⁻¹ in the 3D run.) After sunrise the 3D closure's high shaded terrain
does not warm but cools: at 09:00 local, 7 % of the domain is below −3 °C, 11 K colder than MYNN
at the first percentile, under **fog / low stratus that covers 10 % of the cells and cuts the
insolation to < 50 W m⁻² over 13.5 % of the land (MYNN: 0 %)**; the cold air drains at 15–24 m s⁻¹
(MYNN: 3 cells) and eventually a column collapses numerically. The coldest cells are *not* the
deeply decoupled ones (their skin is only 3 K below the air, wind 7 m s⁻¹, u* 0.34): they are cells
under the cloud, receiving 18 W m⁻² of sunlight against 560 in MYNN's coldest cells.

**Mechanism (inferred, with the numbers above).** In the weakly mixed stable air of the 3D closure
the near-surface layer over the high terrain cools and moistens unopposed through the night;
around sunrise it saturates into fog / low stratus, which blocks the morning sun, so the layer
keeps cooling while its neighbours warm — a positive feedback the closure enters and MYNN, with
its stronger stable-regime mixing, never does. The decoupled skins (previous entry) and the
ridge-top shear runaways are side effects of the same cold, unmixed layer; the surface-layer
bounds (kept; they are harmless and the detector earned its keep) cannot touch it because the
fog forms in the air, not at the surface.

**What it means for the cold pool.** "Less mixing than MYNN at night" is physically defensible —
until it produces fog over a third of the high terrain that observations do not show. This makes
the **morning low-cloud / fog cover and the shaded-slope 2 m temperature** the first observables
for the 23 h comparison, ahead of the nocturnal q² level: TEAMx radiation and cloud observations
(and webcams) at the IOP sites decide whether the 3D run's fog is real. If it is not, the stable
regime is too weak in the sense that matters — moisture and heat are not mixed away from the
surface — and the constants / buoyancy limit / Ri-aware cap discussion opens with a target.

**Operational.** No run passes 08:00 yet. The continuation's archive holds the 07:30 frame
(`exp/X6/wrf_output/8482046/`). Next diagnostic, if wanted: the 1-minute stream 07:30→07:54 from
X6's 07:00 restart with the moisture/cloud fields, plus a comparison of the nocturnal fog onset
(where and when QCLOUD first appears below 200 m AGL in the 3D runs vs MYNN).

---

**2026-08-21 (VSC-5), 17:00 — The 07:10 crash is surface decoupling: shaded slopes the closure cannot recouple after sunrise; a NaN detector, a robustness fix and two loose physical bounds in the surface layer.**

**Measured** (run A13, job 8481309: 12-minute restart of the paired run from 07:00, 1-minute
frames). Every field is finite and unremarkable at 07:09; at 07:10 a cone of ~3 000 NaN columns
expands from a point on the southern lateral boundary (j = 0–1, i ≈ 95–104, a 2.0–2.5 km ridge
on the boundary, lowest level). Order of events read from which fields are NaN where: the
interior stresses `u'²`, `w'²` nowhere; the **surface** stress `u'w'`, `v'w'` (face k = 0) first;
`u*`, skin temperature and heat flux NaN in the same strip; then production, diffusion, the
length scale, W, T, humidity. The seed cells at 07:09: skin temperature 10–26 K below the air at
8 m (TSK − θ = −35…−53 K, ~24 K of it the θ–T offset at 2.4 km), wind 0.5–1.3 m s⁻¹,
**u\* = 0.010–0.017 m s⁻¹** (scheme floor 0.001), sensible heat flux −30…−90 W m⁻²: a surface that
has decoupled radiatively — no turbulence to carry the warming air down to it, a colder skin
making the layer more stable still. The surface-layer scheme (`sf_sfclayrev`, bulk Richardson
number of order 40) and/or Noah-MP then return NaN, which enters the closure through the surface
stress and the dynamics through T, and the long-wave radiation lookup segfaults two steps later.

**Decoupling statistics** (skin minus lowest-level air temperature, K; cells of 300 000):

| | min ΔT | ΔT < −10 K | ΔT < −20 K | HFX < −50 W m⁻² |
|---|---|---|---|---|
| MYNN 04:00 | −20.6 | 7 122 | 2 | 23 108 |
| 3D (X0 / X6) 04:00 | −18.9 | 4 377 / 4 454 | 0 | 44 297 / 43 783 |
| MYNN 05:30 | −17.6 | 1 063 | 0 | 5 591 |
| 3D (X0 / X6) 05:30 | −32.7 / −33.1 | 6 647 / 6 671 | 157 / 152 | 39 509 / 39 323 |
| MYNN 07:00 | −12.1 | 21 | 0 | 3 518 |
| 3D (X6) 07:00 | −37.0 | 2 117 | 180 | 21 349 |

At night the two closures couple the surface about equally; after sunrise MYNN's surfaces recouple
within two hours, the 3D closure's shaded slopes do not — six times as many cells with a strong
downward heat flux 3.5 h after sunrise. X0 and X6 are identical in this, so the pairing fix did
not cause it; the unpaired runs simply died earlier by the other route.

**What it means for the cold pool.** This is the second face of the weak stable-regime turbulence:
too little mixing ⇒ surfaces that cannot recouple. A clamp that only keeps the surface-layer
scheme finite changes no physics — the exchange is already ~0 in that limit — but leaves the model
producing skins 20–37 K below the air, which in a July valley is not plausible (5–10 K is), and
delays the morning erosion of the cold pool; that bias becomes a primary observable of the 23 h run
against the TEAMx surface and 2 m temperatures. A *minimum coupling* does change the physics and is
what most schemes carry against exactly this runaway. Agreed with the user: add the NaN guard and a
**very loose** physical lower bound.

**Implemented (commit follows the build).** (1) `sf_sfclayrev`: the z/L solver `zolri` had an
undefined result on its early-return paths (now 0 = neutral); **`sfclay_zol_max`** caps z/L in stable
conditions (Registry default 1e30 = no cap; template **10**, which is bulk Ri ≈ 0.4 in this scheme —
beyond it the exchange coefficients stay at their z/L = 10 value instead of vanishing); **`sfclay_ust_min`**
floors u* over land (default 0.001 = the scheme's own; template **0.03 m s⁻¹**). Both set once from
the namelist through `sf_sfclayrev_set_limits` (called in `start_em`). (2) A NaN detector in
`module_surface_driver` after the surface-layer call and after Noah-MP: on the first non-finite
`u*`/`HFX`/`CHS` or `TSK`/`HFX`/`QFX` it prints the cell, its inputs and stops — a loud, informative
crash instead of a radiation segfault two steps later; no effect on a healthy run. (3) Numbers for
the record: with u* = 0.03 and z/L ≤ 10 in 0.5 m s⁻¹ wind, the heat exchange coefficient is
~6·10⁻⁴ m s⁻¹, i.e. ~20 W m⁻² at a 30 K skin–air difference, ~7 W m⁻² at 10 K — a gentle recoupling
that cannot by itself erase a cold pool. Test: the 12-minute restart from 07:00 must pass 07:10;
then the 07:00→10:00 continuation; then the 23 h run.

---

**2026-08-21 (VSC-5), evening — The pairing fix closes the energy budget to 0.3 %, halves nocturnal
q², and is what the morning runaway was made of — first run through 07:00.**

**Addendum, 18:20 — the continuation from 07:00 dies at 07:10.** Run X6r (job 8481238),
a restart of X6 from its 07:00 restart file on the same layout, segfaults after 300 steps
in the long-wave radiation table lookup (`rrtmg_lw taumol`, 7 adjacent ranks in the
south-west block, j ≲ 94, i ≈ 37–150) with **no CFL warning** — the signature of a NaN
appearing and spreading through the halos, not of a vertical-velocity runaway. At 07:00 that
block is unremarkable (q² ≤ 32 m² s⁻², |W| ≤ 11 m s⁻¹, T 221–294 K, humidity normal). The
restart is bit-faithful (the 04:00 restart reproduced the 05:52 blow-up exactly), so X6 itself
would have died at 07:10. **Read "first run through 07:00" literally: the paired closure
survives 1.3 h longer than the unpaired one and then fails by a different route, in the
morning convective growth, cause not yet measured.** Diagnosis run A13 (job 8481309): 12-minute
restart from 07:00 with the 1-minute budget stream plus humidity/pressure, output `exp/A13`.
Until it is read, the standing rule holds: no run is expected to complete past 07:00.

`q_sq` = twice the turbulence kinetic energy, m^2 s^-2. `l` = master length scale, the size of the
energy-containing eddies, m. `sf_alpha` = the slope factor (|grad h| dx/dz, the number of coordinate
layers a surface crosses per grid cell, median 5.2 here), the divisor WRF's core applies to the
horizontal turbulent momentum tendency for stability. `KE_LOSS_H` = the resolved kinetic-energy
tendency from horizontal turbulent momentum mixing, m^2 s^-3 — what the mean flow actually pays.
`QSQ_SHEAR_H` = the six horizontal-pairing production terms of `q_sq`, m^2 s^-3, i.e. twice the TKE
production, so the pairing residual is `KE_LOSS_H + QSQ_SHEAR_H/2` and is zero in a consistent
closure. `P/eps` = production over dissipation of `q_sq`. Measured unless marked inferred.

**Behavioural footprint.** The Registry default of `pbl3d_sf_pair` stays 0, so the reference
configuration and its bit-reproducibility are untouched; the run template
`realcase/namelist.input.pbl3d` now carries `pbl3d_sf_pair = 1`, so every new run is paired. The
applied momentum tendency is unchanged — only the production credited to `q_sq` changes.

| run | job | difference from the reference | reached | s/step |
|---|---|---|---|---|
| X0 (reference = previous form) | 8477283 | — | 05:52 (CFL, then SIGSEGV) | 1.50 |
| X6 (paired) | 8478327 | `pbl3d_sf_pair=1` only | **07:00, complete, 13 frames** | 1.50 |
| A12 (diagnosis) | 8479338 | restart of X0 from 04:00, 1-min budget | 05:51:54 (same column, same `W`) | — |

**The acceptance test passed, and by a wide margin.** Residual as a percentage of total shear
production, mass-weighted over the lowest ~100 m:

| pairing residual / total shear production | 02:00 | 04:00 | 05:30 |
|---|---|---|---|
| X0 | +28 % | +37 % | +14 % |
| X6 | **+0.4 %** | **+0.3 %** | **+0.3 %** |

**Removing the spurious source halves the nocturnal turbulence, as predicted, and the two closures
converge after sunrise.** `q_sq` in the lowest ~100 m, domain mean:

| | 02:00 | 04:00 | 05:30 | 06:00 | 07:00 |
|---|---|---|---|---|---|
| X0 / MYNN control (8320565) | 0.27 | 0.33 | 0.51 | — | — |
| **X6 / MYNN** | **0.14** | **0.17** | **0.38** | **0.57** | **0.84** |
| X6 absolute, m^2 s^-2 | 0.043 | 0.052 | 0.27 | 0.52 | 1.20 |
| MYNN absolute, m^2 s^-2 | 0.316 | 0.316 | 0.72 | 0.91 | 1.42 |

At 07:00 the ratio is 0.94-1.18 in the lowest 50 m on every slope class — the convective boundary
layer is the same in both closures near the ground — and 0.4-0.5 at 200-400 m above ground, where
MYNN grows a deeper mixed layer.

**The slope structure of the deficit *was* the spurious source.** At 04:00 the paired run's ratio is
**0.15-0.19 in every slope x height bin**, flat. The previous form gave 0.19 on flat ground against
~0.5 on 22-40 deg slopes; that steep-slope excess was the unpaid production, not physics. The median
`l` at 04:00 over faces 17-121 m is 0.46-0.92 m paired, against 1.0-2.1 m unpaired and 1.5-6.7 m in
the control — `l` follows `q` through the buoyancy and strain limits, so halving the energy shortens
the eddies proportionally.

**Retraction.** The 2026-08-20 inference that the slope-dependent 10 m wind bias is one deficit
"acting as a brake on slopes and a conveyor on flat ground" is **retracted**. Halving `q_sq` left the
bias at 04:00 unchanged to 0.01 m s^-1: -0.35 m s^-1 on 0-3 deg slopes and +0.54 on 22-40 deg paired,
against -0.35 and +0.61 unpaired. The bias is not a function of the turbulence level; its cause is
elsewhere — the surface-layer scheme or the resolved slope-flow dynamics, both shared by the two runs
(**candidates, not measured**).

**New and open: a daytime wind discrepancy.** At 07:00 the paired run is **+2.4 to +3.9 m s^-1**
faster than the control at 10 m on *every* slope class, flat ground included — a daytime, not a
slope, signature. Not examined; it is a target for the 23 h run, together with the 0.4-0.5 `q_sq`
ratio at 200-400 m after sunrise.

**The morning runaway is the same defect, made explosive by daytime shear (measured).** The
diagnosis restart reproduced the blow-up at 05:51:54 at the same column with the same vertical
velocity. It is not one bad column but a growing population of ridge-top hotspots: cells with
`q_sq` > 5 m^2 s^-2 go 4 126 at 05:00 to 31 500 at 05:52. The terminal cluster (j 204-206, i 182-189;
30.5 deg slope at 2107 m, `sf_alpha` ~ 17), budget over +-5 cells and the lowest six mass levels:

| cluster, lowest 6 mass levels | 05:30 | 05:35 | 05:40 | 05:45 | 05:50 | 05:51 |
|---|---|---|---|---|---|---|
| horizontal pairing / total shear production | 97 % | 77 % | 86 % | 95 % | 141 % | 164 % |

The resolved flow pays **6-10 %** of that horizontal production at every one of those times. (The
vertical part turns negative in the last two minutes, hence the values above 100 %.) Dissipation
tracks the total production; buoyancy is ~1 %. In the single column at mass level 4, in `q_sq` units (these are
d(`q_sq`)/dt divided by 2):

| column j=205 i=185, k=4 | 05:48 | 05:50 | 05:51 |
|---|---|---|---|
| `q_sq`, m^2 s^-2 | 3.5 | 25.7 | **146** |
| total production, m^2 s^-3 | 0.03 | 1.07 | 14.9 |
| of it, untapered horizontal | 0.03 | 2.3 | 33 |
| paid (`KE_LOSS_H`) | 0.007 | 0.12 | 1.04 |

The strain limiter is binding throughout (ratio 0.73 -> 0.48), `P/eps` holds at 2.0-2.4, and no
Tier-2 back-off fires. A single column flickers between the floor and O(1) m^2 s^-2 from 05:28 to
05:48, so the cluster sum is the robust quantity. **Conclusion: the earlier inferred mechanism — the
strain cap keeping `l ~ q` so `P/eps` stays above 1 — is the amplifier, not the source. The source is
the unpaid horizontal production, and with the pairing fixed the runaway does not occur through
07:00** (as far as any run has been carried).

**Decision: `pbl3d_sf_pair = 1` becomes the value in the run template**, Registry default still 0.
The fix was agreed in principle before it was built, the acceptance test passed, and it is
energetically consistent rather than tuned. **Next: the 23 h run against the TEAMx observations** —
now possible for the first time, since this is the first configuration to survive the morning. No
change to the closure constants, the buoyancy-limit coefficient or the strain cap before it.

**Trap found on the way** (`KNOWN_ISSUES.md` E17): a restart restores its output timers from the
restart file, so a newly added stream never opens unless `override_restart_timers = .true.` — job
8478325 ran 1.6 h and wrote no 1-minute frames because of it.

**Archives.** X6: `exp/X6/wrf_output/8478327/`, 13 half-hourly frames. The 1-minute diagnosis frames
(53 frames 05:00-05:52, ~50 GB) sit in `exp/A12/temp/branko/` and were **not** archived by the submit
script — keep or subset them deliberately.

---

**2026-08-21 (VSC-5), later — Two follow-ups started the same day: the slope-factor energy pairing is fixed in its minimal form, and the morning runaway gets a 1-minute budget from a restart.**

**Pairing fix, and why the minimal form.** The measurement (previous entry) is that about
90 % of the horizontal-pairing shear production — a third of all production, essentially all of
it on slopes — is never extracted from the resolved flow, because the horizontal turbulent
momentum tendency is divided by the slope factor (|∇h|·Δx/Δz, median 5.2, a WRF-core stability
device) and the production is not. Two ways to pair them: (a) divide the six horizontal
production terms by the same factor at the mass point, leaving the applied momentum tendency
untouched; (b) taper the stresses before the horizontal divergence is formed and reuse those
stresses in production — the WRF-core design, in which the transport term is an exact
divergence. The two differ by a transport term, (u·τ)·∇(1/α), of order (u/L_h)/S ≈ 5 % of the
production, second order to the 90 % being fixed. (b) changes the momentum tendency the model
applies and needs the slope factor on the wide high-order stencil halos (its−2:ite+2), i.e. a
dozen declarations and the stencil arithmetic. (a) is ~20 lines in `Calc_q_sq_shear` plus one
call to `Calc_slope_factor` from `Calc_q_sq_rhs`, and the dynamics stay bit for bit. Chosen: (a),
behind `pbl3d_sf_pair` (0 = previous behaviour, default; 1 = paired). The diagnostic field
`QSQ_SHEAR_H` now reports what is credited, so the in-model residual `KE_LOSS_H + QSQ_SHEAR_H/2`
must fall from ~0.9 to ~0 of the production when the switch is on — that is the acceptance test,
run X6 = reference settings + `pbl3d_sf_pair=1` (the only difference from the bit-validated X0).
Scalar (heat, moisture) horizontal mixing is also tapered but has no energy pairing in the q²
budget; left as is. One more reconfigure (the switch is a Registry entry).

**Stable-regime deficit: no tuning before observations.** Agreed with the user: less turbulence
than MYNN at Ri ~ 1 may be the better answer — MYNN is known to under-forecast the valley wind,
consistent with too much nocturnal mixing. The rule now is: a full 23 h run against the TEAMx
observations before any change to constants, the buoyancy-limit coefficient, or the cap.

**Morning runaway: diagnose from a restart.** The reference run wrote `wrfrst_d01_2025-07-18_04:00:00`
(`restart_interval=180`). Run A12 (`branko_runs/innval_pbl3d_A12`, job 8478217) restarts from it
on the same 2-node layout (so the same columns blow up — KNOWN_ISSUES E14), 04:00→06:30, with the
1-minute stream from 05:00 carrying the q² budget terms, `Q_SQ`, `W`, `U`, `V`, `T`, the length
scale and its limiters, `PBL3D_P_EPS`, the six stresses, `HFX` and `UST` (`realcase/iofields_a12.txt`,
~1 GB per frame, ~60 GB). Output root `exp/A12`. The diagnosis question is the same one A9 had:
at the ridge-top column, is production outrunning dissipation at constant P/ε because the strain
cap makes l ∝ q (the inferred mechanism), or is something else — the Tier-2 split length scale,
the buoyancy term in the transition, the high-order stencil — driving it. Until answered, no run
is expected to pass 06:00.

---

**2026-08-21 (VSC-5) — Six-run result: the bootstrap trap is real but not the lever — the deficit
is the closure's stable-regime equilibrium; a third of production is unpaid on slopes; the strain
cap is load-bearing; and every run blows up two hours after sunrise.**

`q_sq` = twice the turbulence kinetic energy, m^2 s^-2. `l` = master length scale, the size of the
energy-containing eddies, m. `l0` = the asymptotic scale the Blackadar blend relaxes to away from
the wall, m. `Ri` = gradient Richardson number, buoyant suppression over shear production. `N` =
buoyancy frequency, s^-1. `P/eps` = production over dissipation of `q_sq`. `Sk/eps` = strain rate
times eddy turnover time, what the strain cap bounds. `sf_alpha` = the slope taper, layers a
coordinate surface crosses per grid cell. Six 6 h runs, 2025-07-18 01:00 -> 07:00 UTC (sunrise
~03:40), `pbl3d_opt=2`, 2 nodes x 128 ranks, backfilled 2026-08-20 20:41; archives
`exp/X<n>/wrf_output/<jobid>/`. Measured unless marked inferred.

| run | job | init | `l0` floor | cap `Sk/eps` | reached | s/step |
|---|---|---|---|---|---|---|
| X0 (reference = previous code) | 8477283 | floor | 0 | 6 | 05:52 (CFL, `W` = -334 m/s in one column, then SIGSEGV) | 1.50 |
| X1 | 8477284 | equilibrium | 0 | 6 | 05:59 (SIGSEGV) | 1.47 |
| X2 (candidate) | 8477285 | equilibrium | 8 m | 6 | 06:02 (SIGSEGV) | 1.50 |
| X3 | 8477286 | equilibrium | 4 m | 6 | 06:14 (SIGSEGV) | 1.49 |
| X4 | 8477287 | equilibrium | 8 m | 12 | 01:47 (SIGSEGV) | 1.33 |
| X5 | 8477288 | equilibrium | 8 m | off (1000) | 01:43 (SIGSEGV) | 1.32 |

**Predicted vs measured.** Yesterday's entry predicted a laminar fixed point: with `q` at its floor
the asymptotic scale degenerates to 0.1 m at every level, the run cold-starts there, so starting at
equilibrium and flooring `l0` should lift `q_sq` toward the control. **It does not.** The reference
run, the equilibrium start and both floor values agree on the layer-mean ratio to within +-0.01 at
every output time — 2-4 %.

| ratio 3D / MYNN control (job 8320565), `q_sq` domain mean, lowest ~100 m | 02:00 | 03:00 | 04:00 | 05:00 | 05:30 |
|---|---|---|---|---|---|
| all four science runs, agreeing within +-0.01 | 0.27 | 0.34 | 0.33 | 0.32 | 0.51 |

Absolute: the closure plateaus at 0.11 m^2 s^-2 from 02:30 to 04:00 against the control's 0.31-0.32;
0.39 vs 0.72 at 05:30; the candidate run 0.74 vs 0.91 at 06:00 as the convective boundary layer takes
over. **Correction to yesterday's record: "still rising after an hour" was the tail of spin-up.** The
closure equilibrates by ~02:30 at one third of the control, so numbers taken at 02:00 measured
spin-up, not equilibrium.

**The trap was measured, and it is not rate-limiting.** At 03:00 the median `l0` is already 22.6 m in
the reference run (10th percentile 2.5 m, which the 8 m floor lifts), yet the median `l` in the
lowest five faces is 1.3 m without the floor, 1.4 m with it, against the control's 3.1 m: `l` is set
by the buoyancy and strain limits, not by `l0`. The 10 m wind bias against the control at 04:00 is
unchanged, -0.33 m s^-1 on 0-3 deg slopes and +0.60 on 22-40 deg.

**Where the deficit lives: stable stratification.** At 04:00, faces 17-140 m above ground, binned by
the 3D run's own local `Ri`:

| `Ri` | <0 | 0-0.1 | 0.1-0.2 | 0.2-0.3 | >0.3 (every bin to >5) |
|---|---|---|---|---|---|
| `q_sq` ratio 3D / MYNN | 0.96 | 0.54 | 0.34 | 0.27 | 0.22-0.23 (flat) |

The nocturnal valley air in the lowest 8 levels has median `Ri` 0.68; 69 % of cells exceed 0.25, 42 %
exceed 1 (`N` ~ 0.017 s^-1). Median `l` there, 3D vs control: 9.4 vs 8.5 m for `Ri` < 0, 1.0 vs 3.8 m
for `Ri` 1-2. Where the flow is neutral or unstable the two closures agree within 4 %. **The deficit
is the stable-regime equilibrium of Mellor-Yamada level 2.5 with the 1982 constants, which loses its
turbulence beyond `Ri` ~ 0.2, against MYNN, which holds `q_sq` at 0.15-0.3 there.** That is the
branch named in yesterday's falsification condition, and it is now the live one.

**Caveat, and the next decision turns on it: MYNN is the control, not the truth.** Whether 0.1 or
0.3 m^2 s^-2 is right for this valley at `Ri` ~ 1 is an observational question; the TEAMx
intensive-observation data under `$DATA/TEAMx_sEOP_IOP17` and `$DATA/TEAMx_sEOP_IOP18-20` are the
natural reference (pointer only, not analysed).

**A third of shear production is never paid for by the resolved flow (measured in-model).** The new
diagnostics `KE_LOSS_H` (resolved kinetic-energy tendency from horizontal turbulent momentum mixing,
m^2 s^-3) and `QSQ_SHEAR_H` (the six horizontal-pairing production terms of `q_sq`, m^2 s^-3) close
the check the offline reconstruction could not. Mass-weighted over the lowest ~100 m,
`KE_LOSS_H + QSQ_SHEAR_H/2` leaves a residual of **0.87-0.91 of |QSQ_SHEAR_H/2|** at every time from
02:00 to 05:30 in every run: ~90 % of horizontal-pairing production is created from nothing. At
04:00 that pairing is 36 % of total shear production in the lowest six mass levels, so ~33 % of
total production is spurious domain-wide; on 22-40 deg slopes it is ~120 % of the total with 92 %
unpaid, on 0-3 deg slopes ~0. Consistent (**inferred**) with the 1/`sf_alpha` taper applied to the
tendency but not to the stresses entering production, median `sf_alpha` 5.2. **Note the sign:** a
spurious *source* pushes `q_sq` up and the closure is still 3x low — a consistent closure is lower
still, and part of the 0.5 ratio on steep slopes is this source, not physics.

**The strain cap is load-bearing, and yesterday's analytic claim about it is wrong.** Loosening the
cap to 12, or removing it, brings the nocturnal runaway back within 45 min (crashes 01:47 and 01:43
at the known fragile column near j=54, i=37-38 in the 01:30 frame; max `q_sq` 30 and 20 m^2 s^-2 at
j=49, i=134; 348k / 359k cells with a length-scale back-off and 163k / 199k with `P/eps` > 3 at
01:30, against 36k with `P/eps` > 3 in the reference run at 05:30). **Correction:** the claim that
growth saturates harmlessly once `l` reaches its geometric bound holds in the algebra and fails in
practice — the run hits the CFL limit before the saturated state is reached. The cap stays at 6.

**A new failure, pre-existing: every run blows up 2-2.5 h after sunrise.** All four science runs die
between 05:52 and 06:14 UTC at ridge-top columns, the unchanged code included — not an artefact of
the new switches, and a 47 h run would have failed at ~06:00 regardless. Worst column, reference run
at 05:30: terrain 2513 m, 29 deg slope, sensible heat flux -179 W m^-2 (still downward), friction
velocity 0.51 m s^-1, `q_sq` 8.1 / 23.1 / 34.0 m^2 s^-2 at 17 / 33 / 50 m above ground, `l` 4-7 m,
vertical velocity -7.7 m s^-1 at 17 m, potential temperature 300.5-301.3 K through the lowest 14
levels (neutral). Cells with `q_sq` > 5 m^2 s^-2 go 3-6k through the night, 11k at 05:30, 47k at
06:00. **Inferred mechanism:** neutral, strongly sheared plunging flow over a ridge; the strain cap
binds, so `l ~ q` and `P/eps` stays above 1, and growth is exponential until `l` meets the geometric
bound, where the closure's own equilibrium `q_sq` = b1 l^2 S_m S^2 is O(100) m^2 s^-2 at a strain
rate of 0.5 s^-1. Opened as its own issue in `branko/OPEN_ISSUES.md`.

**The rebuild is bit-for-bit (measured), and reproducibility is fragile.** The reference run's 01:30
frame is identical to job 8476273's in `U`, `V`, `W`, `T`, `Q_SQ`, `L_MASTER`, `PBL3D_T1_RATIO` —
maximum difference exactly 0 — so every difference above is physics, not the build. It cost one
round: a first devel-queue smoke (5 nodes) differed by up to 0.6 m s^-1 in `U` after 10 min because
one factor of the strain-cap bound had been rewritten single -> double precision; reverted (commit
`16fa7407b`). Two 640-rank smokes with and without that change then differed from each other as much
as either differed from the 256-rank reference. **Consequence:** any last-bit change reaches the
whole domain within ten minutes and is amplified locally to O(0.1-1 m s^-1) — attributed
(**inferred**) to the closure's discrete backstops (length-scale halving on solver distress,
realizability projections, floors). Compare runs statistically, never cell by cell; bit reproduction
needs identical decomposition *and* identical arithmetic.

**Decisions.**

(a) **The decision rule is not met; neither fix becomes a default.** The candidate run was not finite
to 07:00, did not hold `q_sq` within 0.5-2x of the control in every slope bin, and did not shrink the
slope-wind bias. The floor on the asymptotic length scale (`pbl3d_l0_min`) and the equilibrium start
(`pbl3d_init_opt`) **stay default-off options** — harmless, they remove a real trap, worth +2-4 %,
and not to be called the fix. The balance limiter stays withdrawn; the cap stays at 6.

(b) **Priority, in this order.** (1) **Fix the slope-factor pairing** — now justified by measurement
rather than code reading: taper the stresses before the horizontal divergence is taken and reuse
those same stresses in production, as WRF core applies the factor to the diffusivity. It changes the
answer, so it must land before any tuning, or tuning rewards the compensating error. (2) **Diagnose
and contain the morning runaway** before any run goes past 05:30. (3) **Then the stable-regime
equilibrium**: first decide the reference (the control is not truth; the TEAMx observations are the
candidate), and only then the closure constants, the buoyancy-limit coefficient (`pbl3d_n_tau_max`,
0.53) or the stratification-aware strain cap (`pbl3d_limiter_opt=2`, built, never run) — one
sensitivity run each, namelist only.

(c) **All six archives are kept**, `exp/X<n>/wrf_output/<jobid>/`, ~280 GB total. Analysis:
`branko/realcase/scripts/compare_mynn.py`, subcommand `exp`.

---

**2026-08-20 (VSC-5) — The closure is turbulence-starved: the asymptotic length scale
collapses to a constant when q² sits at its floor, the run cold-starts at that floor, and the
strain limiter throttles ignition.**

`q_sq` = twice the turbulence kinetic energy, m^2 s^-2. `l` = the master length scale, the size
of the energy-containing eddies, m. `alpha` = the asymptotic-scale constant, 0.1 here. All rows
below are **measured** from job 8476273 (3D closure) against job 8320565 (MYNN-EDMF control) —
same grid, forcing, levels, timestep and surface-layer scheme, both from the state at 01:00.

| at 02:00 | 3D closure | MYNN control |
|---|---|---|
| `q_sq`, lowest ~100 m | 0.085, still rising linearly | 0.316, equilibrated by 01:30 |
| ratio 3D/MYNN, flat 0-3 deg / steep 22-40 deg | 0.14 / 0.36 | — |
| 10 m wind bias 3D - MYNN, flat / steep | -0.32 / +0.56 m s^-1 | — |
| median `l` at 85 m AGL | **0.42 m** | **6.7 m** |
| `l` where `q_sq` sits at its floor (1e-5) | **0.09-0.10 m** (= `alpha`) | n/a |
| cells at the floor, lowest 5 levels, 01:10 / 01:30 / 02:00 | 65% / 41% / 27% | — |
| strain limiter binding, lowest 5 levels, 01:38 | 38% (15% with `l` cut >2x) | no such limiter |

A 0.42 m eddy at 85 m above ground is not a boundary-layer eddy; it is what the formula returns
when it has no turbulence to integrate. **Inferred:** the three open items — "is the damping too
strong", the slope-factor pairing, the "unexplained" slope-dependent wind bias — are one problem,
far too little turbulence energy everywhere. The length-scale unification is not the cause: it
moved `q_sq` by 20-30%, and the deficit is 3.7x.

**Mechanism (code reading, `dyn_em/module_pbl3d_my.F`).** Every bound on `l` in the full-3D path
scales with `q = sqrt(q_sq)`: small `q` gives tiny `l`, hence tiny stresses (they go as `l q`),
hence tiny production, hence `q` stays small. A closed loop with a laminar fixed point.

1. **The asymptotic scale collapses to a constant.** `l0 = alpha * int (q-q_min) z dz /
   int (q-q_min) dz` (`:410-422`) — `alpha` times the energy-weighted height centroid of the
   turbulent layer. With `q` at the floor both integrals degenerate to their 1e-5 seeds, the
   height weighting cancels, and `l0 = alpha = 0.1 m` exactly (**measured** 0.09-0.10). The
   Blackadar blend `l = l0 kz/(kz+l0)` (`:431`) then returns ~0.1 m at *every* level, surface to
   model top. MYNN bounds its equivalent to [8, 400] m (`phys/module_bl_mynnedmf.F:1791`).
2. **The run cold-starts exactly at that fixed point:** `q_sq = 1e-5` everywhere (`:4292`). The
   friction-velocity seed that would break it is dead code (`:4327-4341`) and inert anyway — the
   lowest level never enters the `l0` integral and the level-2 routine overwrites it.
3. The Deardorff stable limit `l <= 0.53 q/N` (`:441-445`; `N` = buoyancy frequency, s^-1) is
   correct physics, MYNN has the same one, and at the floor it gives 0.08 m — it adds nothing to
   the trap once (1) has fired. The strain cap (`:1603-1612`) is the third `l ~ q` bound; below.

**Spin-up is a first-order part of the deficit (measured).** MYNN initialises turbulence at local
equilibrium — five passes of `q_sq = (b1 l P)^(2/3)`, length scale recomputed each pass — and its
layer mean is flat by 01:30. The 3D closure starts at 1e-5 and is still rising *linearly* an hour
later. Every run so far has measured the approach to this closure's equilibrium, not equilibrium.

**The strain limiter throttles ignition; it does not laminarise equilibrium turbulence
(measured).** Fixed run, 01:38, lowest five levels, live cells: where the cap binds, production
over dissipation has median **1.19** (63% above 1) — those cells are *growing*; where it does not
bind, 0.81; without the cap they would sit at median **3.0**. So it slows ignition ~2.5x and holds
nothing down at equilibrium: under any `l ~ q` bound P/eps is independent of `q`, so growth is
exponential until `l` meets a geometric bound (`kz` or `l0`), and with the unified length scale it
saturates (the old blowup cell reaches `q_sq ~ 0.8`, not 44). Its equilibrium footprint duplicates
the Deardorff limit — both shut turbulence off above Ri ~ 0.13 for these constants. It is a
defensible shear length scale, the strain analogue of `q/N`.

**A correction before the fact: the production/dissipation balance limiter designed earlier today
is withdrawn, not deferred.** Its premise was that limited cells sit in decay and should be held
at balance. They sit at 1.19, above balance — the premise is false. A P/eps controller also
carries no physical content of its own and would discard the realizability pre-filter the strain
cap gives the algebraic solve.

**Two corrections to the record.** The strain limiter's footprint was reported as 4.1% of cells;
that was diluted over all 80 levels, most of them free atmosphere — in the lowest five, the
drainage layer where the physics is, it binds in **38%**. And the slope-dependent wind bias was
recorded as unexplained; it needs no slope-dependent cause (**inferred**): turbulence is the
*brake* on a locally forced drainage wind, so too little of it leaves the 3D run fast on slopes
(+0.56 m s^-1), and the *conveyor* feeding momentum down to a remotely forced valley-floor wind,
so too little of it leaves the run slow on flat ground (-0.32). One deficit, two signs.

**Decisions.**

(a) **Floor the asymptotic length scale** — new namelist `pbl3d_l0_min`, default 0.0 = current
behaviour. It removes the laminar fixed point without touching what should bind: `kz` and the
Deardorff limit still apply after the blend, so stable free air stays laminar and only sheared
layers ignite. The value is a judgement — 8 m is `alpha` x 80 m, asserting a turbulent layer with
its energy centroid 80 m up; 4 m is also run, because MYNN's 8 m sits at `alpha = 0.23` and so
corresponds to a ~35 m centroid, not 80.

(b) **Equilibrium initialisation** — `pbl3d_init_opt`, default 0 = current floor start. Option 1
runs the closure's own level-2 solution to equilibrium against the initial shear and
stratification: the same assumption the MYNN control already makes, self-consistent, and required
for the 47 h comparison to be fair. It does not cover re-ignition after turbulence dies mid-run —
the length-scale floor does.

(c) **New diagnostics** `PBL3D_P_EPS` (production over dissipation as built; free, it reuses the
accepted solve), `L0_ASYM` (so the collapse is visible in output), and `KE_LOSS_H` /
`QSQ_SHEAR_H` — the resolved kinetic energy horizontal turbulent mixing actually takes out of the
wind, m^2 s^-3, against the horizontal-pairing part of shear production. Those two are the
subgrid energy-closure check the slope-factor pairing needs. **Compare domain or column integrals,
never points:** pointwise the resolved-KE loss differs from production by a transport divergence,
which integrates away but is large locally.

(d) A **stratification-aware strain cap** (`pbl3d_limiter_opt = 2`, default 1 = present fixed cap)
is built in the same reconfigure but not run this round — it scales the cap by the closure's own
equilibrium `Sk/eps` at the local Richardson number, so "twice equilibrium" means the same thing
at every stratification. Built now only to avoid a second 30-60 min rebuild if the cap turns out
to matter.

(e) **Every new switch defaults to current behaviour**, so the rebuilt binary must reproduce job
8476273 — 1.70 s/step, `q_sq` 0.0847 at 02:00 in a smoke run. That check separates "the fix
changed the answer" from "the rebuild changed the answer".

(f) **One `WRF_OUTPUT_ROOT` per experiment**: `realcase/env/vsc5_X<n>.sh` sources `vsc5.sh` and
sets the root to `$DATA/exp/X<n>`. Concurrent runs otherwise write the same
`temp/branko/wrfout_d01_<date>.nc` and clobber each other *live*, mid-run. Hand-editing
`history_outname` is not the knob; this is.

(g) **Six 6 h runs, 01:00 -> 07:00 through sunrise**, against the MYNN control, every comparison
stratified by slope bin x height bin:

| run | init | strain cap `Sk/eps` | `l0` floor | answers |
|---|---|---|---|---|
| X0 | floor | 6 | 0 m | does the present code reach MYNN if given 6 h? |
| X1 | equilibrium | 6 | 0 m | how much of the deficit is spin-up alone |
| X2 | equilibrium | 6 | 8 m | **the candidate**: floor plus equilibrium start |
| X3 | equilibrium | 6 | 4 m | floor-value sensitivity |
| X4 | equilibrium | 12 | 8 m | does the ignition throttle still matter once `l0` is floored |
| X5 | equilibrium | off | 8 m | upper bound on the cap's role |

Decision rule: adopt the floor and the equilibrium start as defaults if the candidate run (i) is
finite to 07:00, (ii) holds `q_sq` in the lowest 100 m within ~0.5-2x MYNN at 04:00 and 06:00 in
**every** slope bin, and (iii) shrinks the slope-wind bias in both signs. The 4 m run picks the
floor value. If either cap run differs materially from the candidate, the cap is a lever after all
and the stratification-aware version earns its own run. Then the 47 h run; only after that the
slope-factor pairing fix.

**Build state:** `main/wrf.exe` and `main/real.exe` are **missing** — an incremental build was
interrupted at 18:03, objects recompiled and never linked; tracked source is clean at HEAD.
Nothing runs until the next build, and that build is the `--reconfigure` these Registry entries
require anyway.

---

**2026-08-20 (VSC-5) — The length-scale fix works: `pbl3d_opt=2` completed its first
real-terrain run. And the `sf_alpha` defect is now the bigger problem.**

Job 8476273: `COMPLETED 0:0`, 1800 steps, 01:00 -> 02:00, zero errors, 1.696 s/step. At
01:38:00, where every previous run died: 0 non-finite cells against 8.3e6, max `Q_SQ` 30.3
against 44.5, max `|W|` 14.2 against 26.5 m/s. Domain max `Q_SQ` at 01:37 went 150.5 -> 18.5,
and the argmax stopped locking onto one cell. The mechanism diagnosed in A9 was the cause, and
unifying the master length scale removed it. Ten lines, no new parameter.

**Two of my own predictions failed, and both are recorded in A9 rather than quietly dropped.**
The predicted `P/eps` of ~0.46 at the blowup cell measured 24.6 — because the cell never
reached the runaway state at all (`Q_SQ` 0.43 against 18.1), making it a ratio of two near-zero
numbers. The prediction was linearised: it assumed the flow would arrive at the same state and
only the ratio would change, when in fact the fix is active from 01:05 and the trajectories
diverge for half an hour first. A counterfactual at fixed state is not a forecast and should
not have been written as one. Separately, an interim comparison table showed baseline and rerun
identical at 01:38 because the rerun had not yet overwritten the baseline's file — filter by
mtime when comparing against `temp/branko/`.

**The `sf_alpha` footprint was badly underestimated, and this changes the priority order.**
A9 described it as affecting the 208 points steeper than 30 deg. Measured across all 300,000
columns: median `sf_alpha` is **5.2**, and it exceeds 2 over **67%** of the domain and 5 over
**51%**. The reason is the grid, not the terrain — `dx/dz ~ 30`, so a 2 deg slope already gives
1.05 and 10 deg gives 5.3. Horizontal turbulent mixing is suppressed five-fold or more over half
this domain, while the production computed from the same stresses is not. Opened as A10.

**An attempt to quantify the resulting energy error failed, and the number is retracted.**
Reconstructing `P_vert` offline from `TURB_FLUX_UW/VW/W2` plus gradients from U, V, W, and
taking the residual against `Q_SQ_SHEAR`, gave "59% of production is spurious". Its sanity check
then showed correlation 0.067 between the reconstructed `P_vert` and the model's own
`Q_SQ_SHEAR` — so the residual was reconstruction error, not physics. Reported here because a
plausible-looking number from a failed method is worse than no number.

**Revised priority: build the SGS energy-closure diagnostic BEFORE the 47 h control run.**
I previously argued it could be deferred, on the grounds that a surviving run would be indirect
evidence about `sf_alpha`. The run survived and told us nothing about it — exactly as the
falsification condition said it would. The stronger argument is now this: the A9 fix *damps*,
`sf_alpha` is a spurious *source*, and two large errors of opposite sign may be partially
cancelling. Tuning against MYNN in that state would reward the cancellation rather than expose
it. The diagnostic costs one Registry field and one reconfigure, and it measures the mismatch
inside the model where the offline reconstruction cannot reach.

**Still unsettled:** domain `Q_SQ` runs 20-30% below baseline through the window. Whether that
is correct damping or over-damping remains the open 17-41% boundary-layer question, and only the
47 h MYNN comparison answers it.

---

**2026-08-20 (VSC-5) — Implemented the unified master length scale. This reverses yesterday's
"deliberately not implemented".**

Yesterday's entry deferred this fix because it is a science change and the scope call was the
user's. That call has now been made, after a physical re-derivation that made three things
clearer than they were.

**Why it is a bug fix and not a tuning change.** In Mellor-Yamada the master length scale does
two jobs that come from the *same* picture — an eddy of size `l` moving at speed `q`. It is the
displacement that sets the flux (`P ~ q l`), and it is the lifetime `l/q` that sets the cascade
rate (`eps = q^3/(b_1 l)`). Those are one geometry read twice. So an eddy that transports like a
2.41 m eddy and dissipates like a 6.04 m one is not a defensible modelling choice; it is not a
physical object. Tier 1's finding is "the eddies are smaller than you assumed", and smaller
eddies both transport less *and* die sooner. The code implemented the first and dropped the
second, leaving turbulence that is simultaneously weakly-mixing and long-lived — which is the
opposite of what strong shear produces.

**The size of the error is the size of the failure.** At the blowup cell the turbulence is given
a lifetime of 11.8 s when its own asserted 2.41 m permits 4.7 s. At 01:25, where the instability
is seeded, 1.21 m eddies are given 395 s against a permitted 78 s — five times too long. The
runaway e-folds in 105 s. An error of two-to-five-fold in the lifetime of the energy-containing
eddies, in a process whose own timescale is the same order, is not a bookkeeping detail.

**Blast radius, measured rather than assumed.** Yesterday's entry worried this changes the
solution broadly. It does, but less than feared: at 01:36 Tier 1 is active in 4.1% of cells, and
among those the *median* `T1_RATIO` is 0.71 — a 40% increase in dissipation for the typical
affected cell, not the 5.6x seen at the blowup point. Only the worst 5% (`T1_RATIO ~ 0.10`) see a
tenfold correction, and that tail is exactly where the runaway lives. Tier 1 activity is 0% at
01:00 and grows monotonically to 4.1% by 01:36 as the drainage layer spins up.

**Implementation choice worth recording: `dg_t1_ratio`, not the final `l_use`.** `dg_t1_ratio` is
set at `module_pbl3d_my.F:1584`, before both Tier 2 loops, so it carries the Tier 1 result alone.
That is what we want. Tier 1 is a physical claim about eddy size; Tier 2 shortens `l` in response
to solver distress or non-realizability, and a failed linear solve is not evidence that the
eddies got smaller. Feeding numerical distress into the dissipation would be a different bug.
A happy consequence: `Diagnose_fluxes` needed no modification at all — the write is one line in
the caller, where the `pbl3d_*` diagnostics are already stored.

**A trap that would have failed quietly.** `Calc_l_master_algebra` copies `ktf` up to `kte`
*before* the point loop runs. Without redoing that copy afterwards, the model-top face keeps the
unlimited value while `ktf` holds the limited one — and `Fill_l_mass_with_l_face` and both
`xkxavg` blocks read index `kte`. It would not have crashed; it would have been subtly wrong at
one level. Edit B exists for that.

**Deliberately still out of scope.** Three other changes were designed and are not in this
commit: the SGS energy-closure diagnostic (needs a Registry field, hence a full reconfigure), a
budget-based `P/eps` limiter threshold (insurance for near-neutral regimes; it would not fire at
this blowup cell once the length scale is unified), and pairing the `sf_alpha` slope taper with
its production terms (larger, and it depends on the diagnostic to justify). A fourth — using
perpendicular rather than vertical wall distance in `kappa*z` — was dropped: the geometry is
right, but it is ~17% at the steepest points, it is inconsistent with WRF's vertical-height
surface layer, and it would have muddied attribution of the first test.

**No namelist switch, on purpose.** A new namelist variable is a Registry change and would have
forced a 30-60 min reconfigure for a ten-line source edit. The old behaviour is reproducible by
reverting the commit, and the baseline output is preserved
(`wrf_output/8472687/baseline_qsq_subset_k0-9_0125-0138.nc`, 1.1 GB, lowest 10 levels,
01:25-01:38) because the rerun overwrites `temp/branko/`.

**Falsifiable predictions, recorded before the result.** At `j=111, i=161`, stag `k=1`, 01:36:
`P/eps` 1.146 -> ~0.46; cascade timescale 11.8 s -> ~4.7 s; `L_MASTER` 6.04 -> ~2.41 m; and the
run clears `2025-07-18_01:38:00`. If it still dies there, the split length scale is not
sufficient and the `sf_alpha` energy-pairing hypothesis becomes primary. If it clears but a
different cell runs away, the budget limiter is needed. If it clears but boundary-layer q^2 falls
further below the MYNN control, this over-damps and the budget limiter should replace the fixed
`SK_EPS_MAX` so limited cells sit at balance rather than decay. Job 8476273.

---

**2026-08-20 (VSC-5) — A9 closed by measurement; two earlier statements corrected; still not implementing the fix.**

Job 8472687 ran ahead of its estimated start and completed all 39 one-minute `qsqdiag`
frames through 01:38 before the terminal RRTMG segfault. The measurement A9 was waiting
for exists, and it lands on **branch 1**: at the blowup cell (`j=111, i=161`, 46.639 N
10.806 E, 33.6 deg slope) `T1_RATIO` runs 0.18-0.40 for the entire event and `SK_EPS`
15-34 against a limit of 6.0. Tier 1 is not blind to the strain; it binds hard and the
binding is what fails. `P/eps` as built sits at 1.09-1.23 for eight consecutive minutes
(e-folding 105 s, doubling 73 s); with a consistent length scale it is 0.43-0.60 in every
frame. Snapshot written to `FINDINGS_QSQ_RUNAWAY.md` (root + `realcase/project/`).

**Correction 1 — Tier 2 and Tier 3 are not globally dead.** A9 and the 2026-08-19 entry
say `T2_STEPS = T3_FLAGS = 0`. Domain-wide at 01:36 that is wrong: T2 fires in 294,398
cells (max 5), T3 in 60,156 (max 240). The true statement is narrower and worse - they
are silent *at the runaway column* (T3 zero at every level, every frame; T2 only
sporadically 1-2 at k=3). Tier 2 escalates on solver distress and non-realizability;
Tier 3 enforces PSD. A budget running 15% hot is neither, so nothing in the ladder can
see this. Recorded because "the backstops never fire" and "the backstops cannot see this
failure" lead to different fixes, and only the second is true.

**Correction 2 — the Tier-1 footprint is 4.1%, not ~20%.** `T1_RATIO < 0.999` in 977,518
of 24,000,000 cells at 01:36; `< 0.5` in 1.06%. The ~20% / 899,613 figure was a different
frame of a different job. It does not change the recommendation - Group F still has Tier 1
binding at 100% in nocturnal SBL, slope drainage and residual-LLJ - but the number in the
previous entry was five times too large and would have overstated the blast radius.

**Resolved:** that entry's honest-limit caveat asked for `SK_EPS > 12.6` co-located at
01:36. Measured 15.07. The conclusion no longer rests on the `T1_RATIO = min(1,
SK_EPS_MAX/SK_EPS)` identity alone.

**Why a snapshot file rather than the fix.** The ask was to save findings so work can
resume later, and the fix remains what the 2026-08-19 entry said it was: a science change
touching every cell where Tier 1 fires, needing revalidation against the 47 h MYNN control
and the idealized regressions. Writing it down with its falsification condition keeps the
scope decision with the user and on evidence. Committed locally, not pushed, at the user's
instruction.

**Also corrected, on a separate point:** an exploration pass flagged that
`realcase/namelist.input.mynn` and `namelist.input.pbl3d` are not matched (24 h vs 47 h,
`time_step` 3 vs 2, `epssm` 0.7 vs 0.9, `sf_sfclay_physics` 5 vs 1) and inferred the MYNN
control was therefore not a controlled comparison. It was. The 47 h control is job 8320565
run from `WRF/run/namelists/namelist.input_inn_inner_dom_ICON`, which uses `time_step=2`,
`epssm=0.9`, 47 h and `sf_sfclay_physics=1` - the same surface layer as pbl3d. The tracked
`namelist.input.mynn` is a template that was never the control. Left alone; the confound
noted in its header does not apply to the run the exclusions rest on.

---

**2026-08-19 (VSC-5) — Diagnosed the blowup as a split master length scale, and did NOT
implement the fix.**

The deep dive landed on a structural inconsistency rather than a missing limiter:
`Q_SQ_SHEAR` scales with Tier 1's limited `l_use` (a local scalar in the solver, never
written back), while `Calc_q_sq_dissip` uses `l_dissip = l_master`, the unlimited scale.
Because `eps ~ 1/l`, Tier 1 firing reduces production and simultaneously leaves dissipation
under-estimated by the same factor — it widens the imbalance it exists to close. Making the
scales consistent takes `P/eps` at the blowup cell from 2.11 to 0.73, below unity, with no
new parameter. Full reasoning and the grey-zone measurements are in `OPEN_ISSUES.md` A9.

**Why this and not a production cap:** in Mellor-Yamada the master length scale is singular
by construction — the same `l` sets the stress closure and `eps = q^3/(B_1 l)`. The k-epsilon
analogy that would justify leaving dissipation alone does not transfer, because there `eps`
is prognostic and here it is *diagnosed from `l`*. So this is removing an inconsistency, not
adding a mechanism, which is what makes it different in kind from the shear-production cap
A9 rules out.

**Deliberately not implemented.** Tier 1 was active in ~20% of the domain at 01:30, so this
changes the solution broadly and is a science change, not a bug fix. Implementing it
unasked would have put an unvalidated physics modification into a tree whose whole purpose
is diagnosing a numerical instability — and it needs checking against the 47 h MYNN control
and the idealized regressions, which is the user's call on scope and priority. Written up
with the falsification conditions instead, so the decision is theirs on evidence.

**Honest limit of the result:** `T1_RATIO = 0.345` derives from A9's `SK_EPS = 17.4`, which
is quoted as a *peak*, not co-located at 01:36. The correction suffices at that frame iff
`SK_EPS > 12.6` there. Job 8472687 carries both at 1-minute resolution; its estimated start
slipped to 2026-08-20T21:30, so the conclusion is on the identity and the source reading
until then, both of which are checkable without it.

**2026-08-19 (VSC-5) — Read the limiter's source before waiting 33 minutes for its
output, and the run became a confirmation rather than the measurement.**

A9 framed `PBL3D_T1_RATIO` as a missing measurement costing one rerun. Reading the Tier 1
block first showed it is not independent data at all: `l_use`, `dg_sk_eps` and
`dg_t1_ratio` are computed from the same `strain_mag`, `l` and `q` in one pass, which
forces `T1_RATIO = min(1, SK_EPS_MAX/SK_EPS)` algebraically. Confirmed on archived
`wrfout` across 4.3e6 cells at 9.5e-08 maximum deviation, so it is an identity in
practice and not just on paper. `SK_EPS = 17.4` at the blowup cell was already measured
in job 89435, so `T1_RATIO = 0.345` there and the branch was already decided.

**Judgment: report it now rather than wait for the queue.** The derivation is checkable
in ten lines of source and was verified against millions of cells; holding it back until
job 8472687 lands would delay a result that redirects the next piece of work, and the run
still serves as independent confirmation at 01:36-01:37 where no `wrfout` frame exists.
The run was left queued rather than cancelled for exactly that reason — a derived result
and a measured one disagreeing would itself be important.

**Consequence for the fix, recorded because it narrows the search:** branch 2 is dead.
`strain_mag` is not misreading the terrain-following gradients — it reports `S k/eps`
at ~3x the limit and Tier 1 cuts `l` to 34.5%, and q^2 explodes anyway. Meanwhile Tier 2
and Tier 3 never fire, because they escalate on solver degeneracy and stress
realizability, and at that cell the solve stays well conditioned and admissible
throughout. So no tier is triggered by the thing that actually goes wrong. That is a
design gap in the escalation ladder rather than a coding bug, which also explains why
`pbl3d_opt=1` survives untouched: its 1D shear production never gets large enough to
need a tier that does not exist.

**Not done, deliberately:** no fix attempted. The next question — whether
`SK_EPS_MAX = 6.0` is simply the wrong bound in strong katabatic strain, or whether Tier
2 needs a budget-based escalation test beside its solver/realizability ones — is a
science decision for the user, and the crash is a clean deterministic regression test for
whichever is chosen.

**2026-08-19 (VSC-5, job 8472687) — Added four fields alongside `PBL3D_T1_RATIO`, and
did not rebuild.**

*No rebuild.* A9 asks for one iofields line and no code change, and that is right, but it
was worth confirming rather than assuming: `pbl3d_t1_ratio` is registered for history in
the **built** binary (`streams(1) = 1` in `inc/allocs_*.f90`), the pull touched only two
`.md` files, and no source is newer than `main/wrf.exe`. So the VSC-5 build from earlier
today stands. (Minor correction to A9's wording: `pbl3d_t1_ratio` is flagged `h`, not
`rh` — history without restart. Irrelevant to this measurement, which only needs history.)

*Carried four extra fields.* `PBL3D_SK_EPS`, `PBL3D_T2_STEPS`, `PBL3D_T3_FLAGS` and
`L_MASTER` were added to stream 23 next to `PBL3D_T1_RATIO`, at ~96 MB/field/frame
(~44 GB total instead of ~25 GB). Reason: A9 itself notes `SK_EPS` is computed from the
**pre-limit** `l`, so it shows Tier 1 had work to do but **not** whether `l_use` was
applied — only `T1_RATIO` and `SK_EPS` *together* separate "the limiter bound and failed"
from "the limiter never bound". Reading them from different frames, or inferring `SK_EPS`
from 10-minutely `wrfout` while `T1_RATIO` comes at 1 minute, would reintroduce exactly
the non-co-located comparison that made `Q_SQ_HDIFF` look like a source. `T2_STEPS` and
`T3_FLAGS` confirm at 1-minute resolution what `wrfout` could only show at 10, and
`L_MASTER` shows whether `l` moved at all. The marginal cost is one run's disk, against
the risk of needing a second 33-minute run to answer a follow-up.

*Already true from a free reading of archived `wrfout` (job 8464723, 01:30):* at A9's
blowup cell (4,182,514) `T1_RATIO = 1`, `SK_EPS = 4.611`, `T2_STEPS = T3_FLAGS = 0`,
`L_MASTER = 15.95`. `SK_EPS` is **below** the 6.0 limit there, so `T1_RATIO = 1` is Tier 1
correctly doing nothing rather than failing to act — which pins down that `T1_RATIO = 1`
is the "did not bind" value, and confirms the cell is still quiet eight minutes out. It
also confirms A9's claim that no `wrfout` frame covers 01:36-01:37: the last one before
death is 01:30.

*Analysis tooling gained a `--cell K,J,I` mode* that reports every term co-located at one
cell and sums them to a net, because "a domain maximum is not a budget" is the lesson A9
paid for once already and the tool should make the right comparison the easy one.

**2026-08-19 (VSC-5) — Staged the q^2 diagnostic run: reused `real.exe` output, and let
the validator overrule a sizing "optimisation".**

*Skipped `real.exe`.* Linked the existing `wrfinput_d01`/`wrfbdy_d01` from
`branko_runs/innval_pbl3d_18th` rather than regenerating them, which saves a whole queue
cycle. `CLAUDE.md` calls re-running `real.exe` after a rebuild the safer default, and that
is right in general — but here the only change is `r -> rh`, which is an **output** stream
mask. Verified rather than assumed: in `inc/allocs_4.f90` the promoted `Q_SQ_SHEAR` now has
`streams(1) = 1`, identical to `TURB_FLUX_UW` (already proven to reach `wrfout`), while
still-`r` `Q_SQ_TMP` has `streams(1) = 0`. Input membership is untouched, so `wrfinput`
cannot have changed. `check_wrfinput.py` passes on the linked files (SMOIS mean 0.284,
slope max 34.2 deg). These are also the exact files job 8464723 crashed from, which makes
the rerun a direct comparison rather than a fresh trajectory.

*This also explains a scare:* all four rebuilt binaries have byte-identical sizes to the
Aug 18 ones. That is not a stale build — WRF's field registry is a runtime data table, so
promoting a variable to history flips a bitmask constant without changing code volume.

*Rank count 256, not 200.* Running 2 nodes x 128 = 256 ranks per the VSC-5 convention,
where job 8464723 used 200 (2 x 100). The decomposition therefore differs, so **the exact
crash step may shift by a step or two — that is decomposition sensitivity, not a failure of
the determinism A9 documents.** Accepted because the question ("which q^2 term runs away")
is about a feedback developing over eight minutes and is not sensitive to a step, and
because a fresh throughput number at the full node was explicitly wanted. Baseline to beat,
measured here rather than imported from MUSICA: **1.405 s/step on 200 ranks**, 1140 steps
to the blowup, ~27 min.

*Reverted an "optimisation" the validator caught.* Set `auxhist24_interval_m = 0` to skip
~75 GiB of WRFlux means that have nothing to do with A9 — and `prepare_namelist.py`
correctly refused it: `flux output is on but no auxhist24 interval is set`. Restored to 10.
The saving was never real (the run dies at 01:38, so only ~4 frames are written) and the
alternative — also disabling WRFlux flux output — would have changed the model
configuration relative to every reference run to save under a minute of I/O. Logged because
the instinct to trim a diagnostic run's output is a good one that was wrong here, and
because it is a clean case of the namelist validator earning its place.

**2026-08-19 (VSC-5, back from MUSICA) — Rebuilt with `--reconfigure`, not a plain
`./clean`, and recorded that the blowup is cross-cluster.** Two calls worth keeping.

*Why the full clean.* The rebuild here exists to get the five `q_sq_*` budget terms into
`wrfout` via the `r -> rh` promotion. This checkout's generated `Registry/Registry` and
`inc/*.inc` were dated Aug 17-18, i.e. **stale against the Aug 19 Registry commit**, and
reading `clean` shows only the `-a` branch removes them. A plain `./clean` would very
plausibly have produced a binary that builds, runs, costs a 30-minute queue slot and
writes an `auxhist23` stream with five silently missing fields — the failure mode this
project keeps meeting (`SMOIS`, E13, U2) where the wrong answer is quiet. The extra few
minutes of `./configure` is not a tradeoff worth thinking about. Verified afterwards that
`q_sq_shear` appears in exactly the same generated files as `turb_flux_uw`, a variable
already proven to reach `wrfout`.

*The crash is not MUSICA's.* Checked the archived VSC-5 job **8464723** (2026-08-19 16:06,
`pbl3d_opt=2`, this cluster, gcc 12.2 / OpenMPI 4.1 / zen3): its `rsl.out.0000` stops at
`Timing for main: time 2025-07-18_01:38:00` — the **same step** as MUSICA jobs 88703 and
88971 under an entirely different toolchain (EESSI gcc 13.3 / OpenMPI 5.0.3 / zen4). This
was free — the evidence was already on disk — and it retires the residual "MUSICA
compiler artifact" hypothesis that would otherwise have shadowed every result from the
rerun. A9 is updated. Note `rsl.error.0000` is clean because rank 0 was not among the 81
that faulted, which is consistent with A9 and not evidence of a different failure.

*Deliberately not touched:* the env loads **both** `openmpi/4.1.6` (explicit) and
`openmpi/4.1.4` (pulled in as a dependency by a later module), and 4.1.4 wins on `PATH`,
so `mpif90` is 4.1.4. Left alone: 4.1.x is ABI-stable, this is the exact env that produced
the working Aug 18 binaries, and re-picking modules mid-campaign would invalidate the one
build configuration known to work here while changing nothing about the physics question.
Recorded rather than fixed, so it is not rediscovered as a surprise.

*Config, reverted from MUSICA:* account `p72996`, partition/QOS `zen3_0512`
(devel `zen3_0512_devel`, MaxWall 10 min), **128 physical cores/node** (8 sockets x 16,
`ThreadsPerCore=2`, so SLURM reports `CPUTot=256`) — all read off `sacct`/`scontrol`, not
assumed. `CORES_PER_NODE` went 100 -> 128; earlier VSC-5 jobs here used 100 ranks/node
(job 8464711), so **throughput is not comparable with those without scaling**, any more
than it is with MUSICA's 1.26 s/step on 190 ranks. Also made `SLURM_ACCOUNT_DEFAULT` /
`_PARTITION_` / `_QOS_` actually do something: they were dead variables, and
`setup_rundir.sh` now substitutes them into the `CHANGEME` slots, so the values live in
the env file instead of being retyped into every run dir. `CHANGEME` survives when the env
file is silent, so the guard against submitting to the wrong project is intact.

**2026-08-19 (later) — Resolved: the crash IS in the scheme's domain, and the earlier
entry below is half wrong.** The 1-minute diagnostic rerun (job 88971) settles what the
entry below deliberately left open. Radiation is only where the corpse fell: the model
blows up over eight minutes beforehand as runaway near-surface `|W|` in nocturnal
katabatic drainage on 33.6-degree slopes, and `W / u.grad(h)` climbs 1.68 -> 2.96 while
the downslope wind accelerates 3.5x, so it is a genuine feedback and not terrain-following
kinematics. Recording this rather than quietly editing the entry below: the instinct to
resist blaming our own scheme was right as a *method* (it stopped a guess becoming a
conclusion) but wrong as a *prediction*, and the log is more useful if it shows that.

What the entry below still got right: refusing to set `ra_lw_physics = 0`. Had we done
that, the run would have proceeded past 01:38 with the drainage-flow instability intact
and no segfault to announce it — the silently-wrong outcome, on the first nocturnal case
this project has ever run.

Deliberately **not** applying the U2 index guard yet, for the same reason. It would
convert a loud, perfectly deterministic crash (same step, same 81 ranks, same address
across two runs) into a NaN quietly propagating through the radiative tendency. The guard
is correct and should land eventually — but after the blowup is understood, not before,
and never as the thing that "fixes" this.

Next discriminator chosen: **run the MYNN control on identical terrain** before touching
any `pbl3d` code. It is cheap, it is already a supported configuration, and it separates
"this closure under-damps slope flow" from "dx=500 m cannot resolve a 34-degree slope at
all" — a distinction that decides whether the fix is in the scheme or in the terrain
treatment. Guessing between those two would be expensive in both directions.

**2026-08-19 — Not treating the first real-terrain crash as a `pbl3d` regression, and
not disabling radiation to get the run through.** The smoke run (MUSICA job 88703)
segfaulted at 01:38 inside RRTMG-LW. It would have been quick to blame the 3D PBL
scheme, since this is its first real-terrain and first nocturnal case; and quicker still
to set `ra_lw_physics = 0` and "make it run". Both rejected. Disassembly puts the fault
on an upstream one-sided bounds guard (`KNOWN_ISSUES.md` U2), and the physics question —
which component emits the NaN that guard turns into a wild pointer — is logged as A9 in
`OPEN_ISSUES.md` rather than assumed. Turning radiation off would not be a workaround
but a different experiment: this is a cold-pool case, and longwave cooling is part of
the mechanism under study. Rationale for the ordering: U2's own guard converts the crash
into a *silent* NaN in the radiative tendency, so applying it before knowing the NaN
source would trade a loud failure for a quiet wrong answer — the exact failure mode the
`SMOIS` check in `realcase/README.md` exists to prevent.

**2026-08-19 — Migrating the operation to MUSICA (Innsbruck); VSC-5 job 8464723
never ran (`ReqNodeNotAvail`, whole `zen3_0512` partition down).** Moving
everything (~100 GB) rather than a minimal working set, so MUSICA is a
self-contained replica and nothing has to be re-fetched later. `branko/` and
`icon2wrf/` go over git (a fresh clone also guarantees no stale VSC-5 `.o` files
survive into the mandatory rebuild); bulk data goes by rsync over SSH.

**2026-08-19 — MUSICA builds against EESSI `gompi-2024a` (GCC 13.3.0), not the
newest toolchain available.** EESSI 2025.06 also offers `gompi-2025a` (GCC
14.2.0) and `gompi-2025b` (GCC 14.3.0). Chose the oldest because the scheme is
verified with gcc 11.2 and was built on VSC-5 with 12.2, so 13.3 is the smallest
step available; `gompi-2025b` ships no netCDF-Fortran at all; and GCC 14 tightens
argument-mismatch diagnostics further while WRF's configure only knows to pass
`-fallow-argument-mismatch` for GCC ≥ 10. Escalate to `2025a`, not `2025b`, if
13.3.0 fails.

**2026-08-19 — LAPACK on MUSICA is FlexiBLAS (`-lflexiblas`), replacing
`-llapack -lblas`.** EESSI ships no standalone LAPACK; FlexiBLAS provides both
APIs in one library. Verified rather than assumed: `dgesvx_` is in
`libflexiblas.so`, and a test program calling `dgesvx('E','N',...)` compiled,
linked and ran on MUSICA returning the correct solution — the check that matters,
since the closure calls it at every grid point on every timestep.

**2026-08-19 — MUSICA transfer used SSH connection multiplexing, not a `step`
certificate.** MUSICA is certificate-only for external logins (`authorized_keys`
is refused — verified with a byte-perfect key), and `step ssh login`/`step ssh
certificate` both fail at Authentik with "failed to resolve application" despite
the OIDC discovery document resolving and the device endpoint returning HTTP 200.
Rather than block on ASC support, one interactive device-auth login establishes a
`ControlMaster` socket that every subsequent rsync reuses. Constraint: the socket
is node-local, so the master and the transfers must run on the same VSC-5 login
node (l55 here).

**2026-08-19 — Output root parameterized as `WRF_OUTPUT_ROOT` instead of
hand-editing namelists per cluster.** `history_outname`/`auxhist24_outname` and
`submit_wrf.slurm`'s archive destination all carried absolute VSC-5 paths, which
contradicted `realcase/env/template.sh`'s own rule that nothing cluster-specific
belongs in namelists or SLURM scripts. The templates now carry an
`@OUTPUT_ROOT@` token expanded by `prepare_namelist.py --output-root`; the layout
below the root (`temp/branko/`, `wrf_output/<jobid>/`, `frames_per_outfile=1`)
is unchanged and deliberately identical on every cluster, so `proc/` keeps
finding this fork's output the same way. Expanding with the VSC-5 root reproduces
the previous paths byte for byte. An unexpanded token is FATAL, matching the
existing `num_metgrid_levels = 0` convention: fail at setup, not mid-run.

**2026-08-19 — `namelist.input.mynn`'s relative `auxhist24_outname` left as-is,
not brought into the shared output tree.** It writes into its own run directory
while `pbl3d` writes to `temp/branko/`, so the two configs are not actually
"identical outside the turbulence configuration" as `realcase/README.md` claims.
Rejected fixing it: relocating output could strand post-processing that already
expects it there, and it is not what this migration is about.
`prepare_namelist.py` now warns instead, so the inconsistency is visible rather
than silent.

**2026-08-19 — `phys/noahmp` and `phys/physics_mmm` pushed to personal forks
rather than carried as bundles or rsync'd `.git` dirs.** Both had exactly one
local commit (the 33-category CORINE table; the `sfclayrev` lower-bound guard)
on submodules whose remote is NCAR upstream, so those SHAs existed only on the
VSC-5 disk and `git clone --recursive` would abort anywhere else. Forking makes
the tree reproducibly cloneable on any future cluster; the bundle and
rsync-the-`.git` alternatives both work once and leave the same trap set for
next time. Gitlink SHAs are unchanged — forking copies commits byte for byte, so
only `.gitmodules` moved.

**2026-08-18 — Land-use categories 28/31-33 (CORINE-as-USGS) get copied
parameter rows, not distinct values or new physics.** Category 28 (lake)
copies row 16 (Water Bodies); 29-30 (unused in this domain) copy row 19
(Barren) as inert placeholders; 31-33 (urban) copy row 1 (Urban and
Built-Up). Rejected: building true CORINE-specific values (no CORINE
VEGPARM table exists anywhere in the project) and enabling urban/lake
physics (`sf_urban_physics`/lake scheme are off everywhere in this
project; out of scope for a grey-zone PBL run, not what's being studied).

**2026-08-18 — `MVT=27→33` bumped only in `phys/noahmp/drivers/wrf/`, not
`hrldas`/`lis`/`erf`.** Only the WRF driver is exercised by this build;
touching the others would be an unrequested, unverified change.

**2026-08-18 — Namelist merge is a union of ICON's namelist and the stock
`pbl3d` template; ICON's value wins on overlap.** Exceptions: the pbl3d
hard constraints (`bl_pbl_physics`/`hybrid_opt`/`diff_opt`/`tke_budget`,
enforced by `module_check_a_mundo.F`) stay at their required values, and
the WPS-synced placeholders (`e_we`/`e_sn`/`dx`/`dy`/`num_metgrid_*`/
`num_land_cat`) are left unmanaged for `prepare_namelist.py` to fill in.

**2026-08-18 — SMOIS unit fix (kg m⁻² → m³ m⁻³) went into `icon2wrf`
itself, not just a one-off patch of already-generated GRIB2/met_em.**
So future runs are correct from the start rather than needing the fix
reapplied. Pushed as an isolated commit on `icon2amundsen`, deliberately
not bundled with unrelated in-progress work already in that tree.

**2026-08-18 — Did not regenerate the shared `wrfinput_d01`/`wrfbdy_d01`
under `/home/fs72996/ewahl/data/WRF/run/`** after branko's first
`real.exe` run accidentally overwrote them (stale symlinks in
`branko/run/`, since removed). Per explicit instruction to focus on
branko only for now — **open item**, may still need restoring if another
fork's run depends on the original files.
