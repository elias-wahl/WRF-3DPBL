# DKRZ Levante application — 20 m WRF-LES of the Radfeld transect

Working folder for the DKRZ compute-time proposal (with the DFG-funded
Tübingen UAS group). Created 2026-09-08.

## Files

| file | what it is |
|---|---|
| `antrag_bullets.md` | The five core bullets (50 k node-h version), the cost arithmetic, and the DKRZ process constraints |
| `dkrz_rules.md` | The allocation rules (eligibility, windows, expiry, limits) — condensed from dkrz.de, 2026-09-08 |
| `proposal_outline.md` | Skeleton of the ≤ 8-page request document in DKRZ's required section order, with our content and character budget per section |

## Open decisions (blocking the writing)

1. **Which window**: current one (deadline **2026-10-31**, start 2027-01-01,
   forces ~12.5 k node-h consumption per quarter from January) vs. spring
   (Mar 1 – Apr 30, start 2027-07-01, matches the H2-2027 production
   schedule). → Elias + Platis.
2. **PI**: must be at a German institution → Platis leads; agree the split of
   writing duties.
3. **Numbers to firm up**: Freddi's 100 m domain extent and time step; the
   20 m nest extent (25×15 km assumed); whether one case needs the
   stratification rehearsal.

## Key numbers (agreed)

- **Ask: 50 000 node-h** (+ ≈ 3 000 node-h pre/post-processing) on Levante
  CPU, ≈ 60 TB work / 15 TB archive.
- Basis: measured 190 core-h per simulated hour at 500 m; chain
  500 → 100 → 20 m ≈ 160 node-h per simulated hour; 6 diurnal cycles +
  3-member sensitivity + ×1.33 margin. Fallback floor: 42 k.
- Scalability (measured, 500 m domain, 128-core nodes): 1.5 s/step on
  2 nodes, ~0.8 on 4, 0.65 on 5 — near-linear to 5 nodes.
