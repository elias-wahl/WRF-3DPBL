# DKRZ allocation rules — condensed (from dkrz.de, retrieved 2026-09-08)

- **Who**: resources go to projects in climate/earth-system modeling;
  non-commercial only. PI should be affiliated with a German research
  institution; international groups need a significant German contribution or
  services in compensation to German groups.
- **Windows**: Sep 1 – Oct 31 → start Jan 1; Mar 1 – Apr 30 → start Jul 1.
  Allocations run 12 months. Additional resources can be requested at either
  date (justified in the request document); renewals require a report.
  Partially submitted proposals that miss the deadline are deleted.
- **Request document must cover**: project overview; planned work
  (scientific); mathematical/computational aspects; numerical methods;
  suitability for HLRE-4; **scalability (performance vs. CPU count)**;
  computing time + storage derivation (each scientific part → specific
  requirement); added value vs. other projects.
- **Page limits** (normal project): first proposal ≤ 8 pages, additional
  resources ≤ 5, report ≤ 2; ≤ 4 000 characters/page average.
  (Joint project: 20 / 15 / 15.)
- **Data storage usage plan** required only if CPU+GPU ≥ 1 000 000 node-h or
  disk ≥ 1 024 TiB or tape ≥ 1 024 TiB — not triggered by our request.
- **Compute expires after three months** — consumption must be roughly even
  across the allocation year (check on luv.dkrz.de).
- **Disk** is per allocation period (re-request on renewal; default: move
  data to archive within the period). **Archive** grants expire if unused;
  data already in archive stays until project end + 1 year (long-term
  archive: 10 years).
- **Pre-/post-processing** runs through SLURM and needs its own requested
  compute time.
- **GPU nodes** (4× A100): request only for GPU-enabled code or
  hardware-accelerated remote visualization.
- **Review**: by the Scientific Steering Committee; outcome shortly before
  the allocation period starts.
