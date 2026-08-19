# Project-level operational docs

These are the **operational** documents for the ICON-forced Inn Valley
campaign. They are not part of WRF and not really part of this fork's source —
they live here so they are version-controlled and travel between clusters with
`git` instead of needing a separate `rsync` leg.

That matters: `$DATA` (the directory these are normally read from) is **not** a
git repository on any cluster so far, so before this directory existed the only
copy of `DECISIONS.md` was on one disk. `CLAUDE.md` warns about exactly that
situation, having nearly lost two submodule commits to it during the VSC-5 →
MUSICA move.

| file | what |
|---|---|
| `CLAUDE.md` | working agreement + the traps that cost a day if you get them wrong |
| `ARCHITECTURE.md` | project layout and the ICON→WRF forcing chain |
| `DECISIONS.md` | why non-obvious science/config choices were made, newest first |
| `MIGRATION_MUSICA.md` | the VSC-5 → MUSICA move |
| `HANDOVER_MUSICA_TO_VSC5.md` | the move back, and the state of the `pbl3d_opt=2` diagnosis |

## These are copies, and copies drift

At runtime these files are read from the **working directory root** (`$DATA`),
not from here — `CLAUDE.md` in particular is only auto-loaded from the root, and
the "read these first" paths inside it are relative to the root. So each cluster
keeps its own root copy and **that copy is what is actually in force there.**

This directory is the *transport and history* copy. When you change one of these
documents, change the root copy (that is the one that takes effect) and then
refresh it here in the same commit as the work it describes — the same rule
`CLAUDE.md` already sets for `DECISIONS.md`.

Deliberately **not** symlinked from the root into here: `branko/` is a fresh
clone on every cluster, and a symlink pointing into a re-cloned tree is exactly
the dangling-symlink failure recorded as `KNOWN_ISSUES.md` E11 — which cost a
`wrf.exe` run before it was understood.

## Setting these up on a new cluster

```bash
cd $DATA
cp branko/realcase/project/*.md .
rm README.md            # this file belongs to the repo, not the root
```

Then edit the root `CLAUDE.md` for the new cluster (account, partition, QOS,
cores per node, paths) before trusting anything in it. `HANDOVER_MUSICA_TO_VSC5.md`
lists the MUSICA-specific values that must **not** be carried over.
