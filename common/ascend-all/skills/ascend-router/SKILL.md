---
name: ascend-router
description: Choose the best NC State compute resource for a job and hand off to it. Use when the user has a compute task and hasn't said WHERE to run it — decide between ncshare (Slurm H200), hazel-vcl (Slurm typed GPUs), and hurricane (one Blackwell, no scheduler) by matching job nature to each profile and checking live availability with ascend-probe.
---

# ascend-router — pick the right ASCEND resource, then hand off

When the user brings a compute task without naming a resource, route it. Never
guess blind — check what's free right now, then recommend and confirm.

## Step 1 — understand the job
Get (ask briefly only if unclear): does it need a GPU? how much VRAM? how many
GPUs? a specific GPU type? how long (interactive/short vs batch/long)? does it
need to start now?

## Step 2 — see what's free
Run **`ascend-probe`** (`ascend-probe --json` for parsing). It returns, per
resource: reachable, free_now, and a note. It is read-only — nothing is
submitted. hurricane answers instantly (passwordless); ncshare needs a
passwordless login-node ssh for the queue view; hazel-vcl can only be checked
when its link is warm (otherwise it reports "cold — needs Duo").

## Step 3 — match job to resource

| Resource | It is | Best for |
|---|---|---|
| **hurricane** | ONE RTX PRO 6000 Blackwell (~96 GB), NO scheduler, agent on the box, zero queue | one-GPU jobs that fit ~96 GB, interactive/short-to-medium, **when you want it now and its GPU is free**. Shared by courtesy. |
| **ncshare** | Slurm cluster, H200, laptop-driven | batch/long single-GPU, needs H200, or when hurricane is busy. May queue. |
| **hazel-vcl** | Slurm cluster, typed GPUs (l40s/h100/a100), agent on the VCL node | multi-GPU, a specific non-Blackwell type, or very long queued runs. Cold link needs one Duo. |
| **local** | the Mac | no GPU, light work. |

Decision order:
1. No GPU / light → **local**.
2. Multi-GPU or a specific non-Blackwell type (h100/a100/l40s) → **hazel-vcl**.
3. Needs H200 → **ncshare**.
4. One GPU, fits ~96 GB, not a very-long run, and `hurricane.free_now` → **hurricane** (no queue).
5. hurricane busy, or long/batch single-GPU → **ncshare** (H200).
Break ties with the live snapshot: **free_now beats queued**; a warm hazel beats a cold one for a quick job.

## Step 4 — recommend, confirm, hand off
State the pick and one sentence of why (job nature + live availability), plus
any caveat (hazel cold → one Duo; hurricane GPU busy). On the user's OK, hand
off by launching that resource's front door: `ascend-hurricane` /
`ascend-ncshare` / `ascend-vcl` (with `-d <project>` if given). The agent then
runs on/through the chosen resource — this router's job is done.

`ascend-all` automates steps 2–4 (probe → local-Claude reasoning → confirm →
exec). Use this skill's policy when reasoning inside a live session instead.
