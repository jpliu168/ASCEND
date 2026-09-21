---
name: ncshare-remote
description: Run compute on the NCShare HPC cluster from this Mac via the ncshare-agent / ncshare-agent-gpu ssh aliases. Use whenever a task needs cluster CPUs/GPUs, SLURM jobs, files under /work/@@NCUSER@@, or the cluster tools hpcrun, hpcrepro, fetch-paper.
---

# NCShare remote execution from the Mac

The ssh aliases `ncshare-agent` (CPU) and `ncshare-agent-gpu` (one H200) each
transparently provision or reuse a SLURM job on NCShare and run the command on
a compute node. Never wrap the aliases in `srun`/`sbatch`.

## Hard rule — the aliases are the ONLY route to NCShare

This is a ban on **connecting**, not merely on running compute.

- **NEVER run `ssh @@NCUSER@@@login.ncshare.org` (or any direct `ssh` to
  `login.ncshare.org`)** — not for compute, and not for "quick" read-only
  checks either. `squeue`, `sinfo`, `scontrol`, `ls`, `cat`, `test -f`,
  reachability probes and "is the cluster up" checks are all covered.
- **NEVER add `-o BatchMode=yes`, `-o ConnectTimeout=<n>`, or any other
  timeout/short-circuit flag to reach the cluster by a different path.** If an
  alias is slow, it is provisioning — wait for it (see cold start below).
  Routing around the alias is never the fix.
- **There is no "other terminal" and no fallback host.** You have one route.
  Every cluster command, status checks included, goes through an alias.

Correct forms for the checks that tempt a direct connection:

| Want | Use |
|---|---|
| my queue | `ssh ncshare-agent 'squeue -u @@NCUSER@@'` |
| partitions / gres | `ssh ncshare-agent 'sinfo'` |
| node detail | `ssh ncshare-agent 'scontrol show node <node>'` |
| is the link warm? | `ssh -O check ncshare-agent` |

`ssh -O check ncshare-agent` probes the local ControlMaster socket only. It
returns instantly, never connects, and never provisions a job — it is the one
safe "is anything alive" probe, and it is the correct substitute for a direct
login-node ping.

## Patterns

- One-off command: `ssh ncshare-agent 'cd /work/@@NCUSER@@/<proj> && python x.py'`
- GPU command: `ssh ncshare-agent-gpu 'cd /work/@@NCUSER@@/<proj> && python train.py'`
- First command after idle takes up to ~1 min (job provisioning); later
  commands reuse the connection (ControlPersist 30m).
- Fresh shell per call — no cwd/env carryover. Use absolute paths or `cd ... &&`.
  Conda envs must be activated inside the same command:
  `ssh ncshare-agent 'source ~/.bashrc && conda activate <env> && ...'`
- Long jobs (>~30 min): write an sbatch script under /work/@@NCUSER@@, submit with
  `ssh ncshare-agent 'sbatch <script>'`, poll with
  `ssh ncshare-agent 'squeue -u @@NCUSER@@'`, read logs with
  `ssh ncshare-agent 'tail -50 <log>'`. Do not hold long jobs open in an
  interactive ssh command.
- Files: push code with `rsync -av <local>/ ncshare-agent:/work/@@NCUSER@@/<proj>/`
  (aliases work with scp/rsync too); pull back only small results/figures.
- ASCEND tools live in `~/bin` on the cluster:
  `ssh ncshare-agent '~/bin/hpcrun <args>'`, `~/bin/hpcrepro`, `~/bin/fetch-paper`.
  Prefer them over hand-rolled SLURM handling; end finished projects with
  `hpcrepro learn`.

## Cold start — the alias is SUPPOSED to be slow

A first connect with no warm job is **silent for up to `--wait 240`s** while
SLURM provisions. This is normal, not a hang, and not a reason to find another
route.

- Set your command timeout to **at least 300s (5 min)** for the first cluster
  call of a session. Raising the timeout is the fix; a second connection is not.
- Do **not** Ctrl-C or kill it — that cancels the provision and restarts the
  wait from zero.
- To watch progress without opening a second route, background the call and
  poll the socket locally:

      ssh ncshare-agent 'hostname' >/tmp/nc.out 2>&1 &
      sleep 30; ssh -O check ncshare-agent && echo "socket up"; cat /tmp/nc.out

  `ssh -O check` is local-only, so this costs nothing and provisions nothing.
- Once the socket is up, every later command in the session is fast
  (ControlPersist 30m).

## Gotchas

- **`ssh ncshare-agent` hangs after `Server accepts key` (verified 2026-09-10):**
  the agent job landed on a SATURATED node (compute-06: 128/128 CPUs allocated,
  load ~114, shared with the `osg` backfill partition). The node runs Slurm
  steps fine (`srun --jobid=<id> hostname` returns instantly) but a full ssh
  login (PAM: user lookup, home mount, session setup) starves under that load
  and never completes. A 2-CPU/4G agent job fits anywhere, so Slurm keeps
  cramming it onto the full node. FIX: request enough that a saturated node
  can't host you — append `--cpus 4 --mem 16G` to the ProxyCommand (the guide
  supports appending), then `scancel` the stuck job and reconnect; it lands on
  a node with headroom. Diagnose with
  `ssh ncshare-agent 'scontrol show node <node>'` (CPUAlloc vs CPUTot, CPULoad)
  and the srun-vs-ssh contrast above. Report the node to NCShare.
- **exit 255 with NO message** = `~/.ssh/sockets/` missing (ssh won't create
  it; `LogLevel ERROR` hides the bind error). `mkdir -p ~/.ssh/sockets &&
  chmod 700 ~/.ssh/sockets`.
- **Reading a live ssh's verbose log:** never pipe it through `| tail` — tail
  prints nothing until exit. Background it and read the file afterwards:
  `ssh -v ncshare-agent hostname >/tmp/nc.log 2>&1 & sleep 30; tail -30 /tmp/nc.log`.
  The `sleep` here is only how long to wait before reading the log — it is NOT
  a connection timeout, and must never be turned into `-o ConnectTimeout=`.
- The GPU alias requests `--gres gpu:h200:1`; if it stalls, check partition/gres
  in ~/.ssh/config against `ssh ncshare-agent 'sinfo'`.
- nvidia-smi on the node shows all 8 GPUs; the job is allocated one —
  CUDA_VISIBLE_DEVICES scopes actual code.
- /work purges after 75 days; durable outputs go to cluster $HOME or the Mac.
- The cluster has restricted egress; downloads that fail there (e.g. paper
  fetches blocked by Cloudflare) can often be done on the Mac and pushed up.
