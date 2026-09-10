# DKRZ Levante application — 20 m WRF-LES of the Radfeld transect

Working folder for the DKRZ compute-time proposal (with the DFG-funded
Tübingen UAS group). Created 2026-09-08.

## Files

| file | what it is |
|---|---|
| `antrag_bullets.md` | The five core bullets, the original 50 k arithmetic, and the DKRZ process constraints |
| `antrag_sections.md` | **Paste-ready sections** (2026-09-10): Verwendete Software, Suitability to HLRE-4, Scalability, Computing time and storage — with the **revised 22 k node-hour** budget and its justifications |
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

- **Ask (revised 2026-09-10): 22 000 node-h** on Levante CPU (post-processing
  included), **15 TB work / 5 TB archive**.
- Basis: measured 190 core-h per simulated hour at 500 m; the 20 m nest is
  ≈97 % of the chain cost (156 node-h per simulated hour), so the parent chain
  runs full diurnal cycles while the **LES nest runs only the windows the
  science needs** — 3 cases with the night (14 h each), 3 daytime-only (10 h
  each), a 3-member sensitivity suite on a 6 h window, an on-machine scaling
  test, ×1.3 margin, 2 000 node-h post-processing.
- Reviewer fallback: ≈18 000 node-h (two sensitivity members, two nights).
- Superseded: the 50 k version (full-day nesting, 60 TB) — the storage there
  was not derived from measured frame sizes.
- Scalability (measured, 500 m domain, 128-core nodes): 1.5 s/step on
  2 nodes, ~0.8 on 4, 0.65 on 5 — near-linear to 5 nodes.
