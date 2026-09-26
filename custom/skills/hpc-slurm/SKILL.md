---
name: hpc-slurm
description: Run and iterate on Slurm HPC jobs on THIS cluster through the hpcrun harness — probe the site, create an immutable revision, validate, submit, poll, read logs, classify the failure, propose a bounded fix, resubmit. Use whenever the task involves sbatch, srun, squeue, sacct, a Slurm job, a GPU allocation, module load, or "run this on the cluster / check the job / why did it fail / resubmit it".
---

# Running HPC jobs on this Slurm cluster (custom ASCEND site)

Get scientific work through the Slurm scheduler correctly and iterate on it
when it fails — without burning allocation, losing provenance, or hiding what
happened.

**This is a CUSTOM site**: ASCEND was linked to this cluster by its user, so
nothing below assumes NC State specifics. Every concrete fact about THIS site
(partitions, accounts, QOS, wall-time limits, gres names, module system,
storage layout, purge policy, login-node etiquette) must come from one of:

1. **`references/` in this skill folder** — the site's own user guide / policy
   docs, if the person who linked the site provided them. Read what's there
   FIRST.
2. **The live probe** — `hpcrun site --probe` (authoritative), plus direct
   read-only queries: `sinfo -o '%P %a %l %D %t %G'`, `sacctmgr show qos
   format=Name,MaxWall,MaxTRESPU -P`, `sacctmgr show assoc where user=$USER
   format=Account,Partition,QOS -P`, `module avail 2>&1 | head` (does Lmod
   exist?), `df -h $HOME .`, and the site's own MOTD/login banner.
3. **`references/site-profile.md`** — the distilled profile of THIS site (see
   below). If it exists and is dated, trust the live probe over it where they
   disagree.

## First session on this site: build the site profile

If `references/site-profile.md` does NOT exist yet, spend the first minutes of
the first real session creating it: read everything in `references/`, run the
probes above, and write a one-page profile covering — login-node rules (what
may run there), partitions + their gres/GPU types, the account/QOS pairs this
user actually has, wall-time limits per QOS, how software is loaded (Lmod?
conda? spack?), whether compute nodes have internet, storage tiers (home,
scratch, project) with quotas and purge windows, and how to ask for
interactive nodes. Date it. Every later session reads it first and re-verifies
only what looks stale. This file is the site-specific "agent/skill" for this
cluster — generated from the site's own documentation plus live probing, not
assumed.

## The one rule

**Never call `sbatch`, `scancel`, or `srun` directly for real work. Use
`hpcrun`.** `hpcrun` (`~/bin/hpcrun`) prints one JSON object per subcommand:
immutable revisions, pre-submit validation, provenance, bounded fix loops.

Workflow: `hpcrun site --probe` → `hpcrun rev new` (immutable revision) →
`hpcrun validate` → `hpcrun submit` → `hpcrun poll` → on failure `hpcrun
logs` + classify → propose ONE bounded fix → new revision → resubmit. Never
edit a submitted revision in place.

## Login-node etiquette (default to strict)

Until the site profile says otherwise, assume the login node is shared and
watched: use it only for scheduling, small edits, and environment builds; cap
anything CPU-heavy; never run real computation there. Assume compute nodes may
lack internet until proven otherwise — download datasets/repos/papers on the
login node.

## Safety

- Ask before anything that spends significant allocation (multi-GPU, long
  wall-time, many jobs).
- One heavy job at a time until the site's queueing behavior is understood.
- Respect the site's own acceptable-use policy in `references/` over anything
  here.
