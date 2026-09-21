# Hazel (NCSU HPC) — site profile

Facts for running ASCEND on NC State's Hazel cluster (`login.hpc.ncsu.edu`),
gathered from hpc.ncsu.edu docs 2026-09-09. Where this file and `hpcrun site
--probe` output disagree, trust the probe — it reads the live cluster.

## Scheduler

Slurm, production since 2026-08-17. LSF still visible but retiring end of
Fall 2026 — ignore `bsub`/`bjobs` entirely; everything goes through Slurm.

## Storage — sharply different from NCShare

`$ASCEND_SHARE` is your writable /share dir (faculty `/share/<unity>`, student `/share/<project>/<unity>`); `$ASCEND_SCRATCH` = `$ASCEND_SHARE/agents`. Both are exported in the shell (`echo $ASCEND_SHARE`). Examples below use them.


| Path | Quota | Policy |
|---|---|---|
| `/home/$USER` | **15 GB, 10K files** | backed up daily; scripts/configs ONLY |
| `/share/$GROUP` | 20 TB, 1M files | scratch; **30-day-access purge**, no backup |
| `/usr/local/usrapps/$GROUP` | 100 GB, 250K files | software/envs; backed up; **compute nodes cannot write here** |

Consequences the agent must respect:
- ASCEND scratch root is `/share/$GROUP/agents` (installer sets
  `ASCEND_SCRATCH`); jobs run from there. The purge is 30 days since last
  ACCESS — faster than NCShare's 75 — so `hpcrepro learn` promptly, and keep
  anything durable in `~/.ascend` or the skill directories.
- The 10K-FILE home quota is the trap NCShare never had: a stray
  `node_modules`, pip cache, or conda env in `$HOME` bricks the account's
  home. Node + Claude Code and all conda/venv environments belong in
  `/usr/local/usrapps/$GROUP/...`, on PATH via `~/.bashrc`.
- Environments must be BUILT from a login node (usrapps is read-only on
  compute nodes) — the opposite of the NCShare habit of building inside the
  allocation. Build on login (it is I/O, not compute), run on compute.
- `quota_display` shows usage. Check it before and after big installs.
- A third shared filesystem, `/rsstu` (per-project research storage), is also
  visible from this node AND from compute nodes — job scripts can read/write
  it directly. Quota is per project (`quota_display` / hpc.ncsu.edu).

## Partitions and QOS

| Partition | QOS | Max wall | Notes |
|---|---|---|---|
| compute | normal (default) | 4 d | CPU; `--qos=long` → 10 d |
| compute_partners | short (DEFAULT) / scavenger | 2 h / 4 d | idle partner nodes; preemptable (REQUEUE) |
| gpu | gpu (default) | 4 d | all users |
| gpu_partners | short_gpu / scavenger_gpu | 2 h / 4 d | idle partner GPUs |
| xfer | xfer | — | data transfers, 4 cores / 24 GB cap |

Helper commands on the cluster: `si` (free cores/GPUs), `sq` (queue), `sa`
(your accounts), `sqos` (your QOS limits).

## GPUs — typed gres is MANDATORY (live-probed 2026-09-09, scontrol)

`--gres=gpu:1` is REJECTED. Type names as Slurm actually spells them
(NOTE the underscores in the consumer cards):

| partition | gres types (count) |
|---|---|
| gpu | `h100` (8), `l40` (8), `a100` (4), `a30` (8), `p100` (4), `rtx_2080` (4), `gtx_1080` (2) |
| gpu_partners | `h200` (8), `h100` (8), `l40s` (60), `a100` (4), `a10` (8) |

So: `--gres=gpu:h100:1 -p gpu --qos=gpu`, or for a short smoke on idle
partner hardware `--gres=gpu:l40s:1 -p gpu_partners --qos=short_gpu` (2 h,
higher priority; l40s is the most plentiful GPU on the cluster). **h200 and
l40s exist ONLY in gpu_partners**; the gpu partition's Ada card is `l40`.
TRES billing weights (allocation cost per GPU-hour): h200=120, h100=90,
a100=50, l40s=40, l40=32, a30=30, a10=18, p100=10 — a smoke on l40/l40s
costs a fraction of an H100 run. DefaultTime is 1 h everywhere; walltime
caps come from the QOS, not the partition.
CPU node types via `--constraint=` (genoa 192c/768GB, turin, sapphirerapids,
icelake_8358/6326, skylake, cascadelake, broadwell, haswell).

## CUDA

`module load cuda` in every GPU job script — default is 13.2. Jobs on
updated GPUs with OLD cuda versions appear to run but stop producing
output (announced banner issue): if a GPU job runs but its log goes
silent, check the cuda module version FIRST, before any deeper diagnosis.

## Interactive vs batch — a Hazel policy with teeth

srun/salloc (interactive) must request `--qos=short` on `compute_partners`
(CPU) or `--qos=short_gpu` on `gpu_partners` (GPU) — a bare interactive
srun on `compute` warns today and WILL become an error. Batch (`sbatch`)
may use any QOS. Consequences:
- The `ascend` launcher session (interactive) runs on
  `compute_partners --qos=short`, capped at 2 h — set via
  `ASCEND_INTERACTIVE_PARTITION` / `ASCEND_INTERACTIVE_QOS` /
  `ASCEND_TIME` (installer writes them). Re-launch `ascend` when the 2 h
  allocation ends; the session state lives on disk, nothing is lost.
- Batch jobs through `hpcrun` keep partition `compute` + QOS normal (4 d)
  or `gpu` + QOS gpu — unaffected.
- Partner partitions preempt by REQUEUE — an interactive session can be
  preempted; treat it as normal, re-launch.

## Where the agent runs

Policy: no resource-intensive processes on the shared login nodes
(login01-03). Three facts shaped where ASCEND's agent lives:
1. `hpcrun site --probe` first — partitions/QOS/binaries as the cluster
   reports them; then `sqos` and `sa` for what this account may submit.
2. Compute nodes have NO internet — ANSWERED 2026-09-09: curl exit 28 /
   timeout to api.anthropic.com from job 776184 on compute_partners. Claude
   Code needs the Anthropic API, so it cannot run inside a job; anything it
   downloads (datasets, repos, papers via fetch-paper) is fetched on the
   login/xfer/VCL side, never inside a job.
3. The shared login nodes must stay light — a runaway install once
   fork-bombed login03 (see the PATH trap below) — and OIT's directive is
   that installs and heavy/interactive agent work go on an **HPC-VCL node**,
   NOT login01-03.

**Preferred model (ASCEND-VCL):** the agent runs on a personal **HPC-VCL
node** — a dedicated, login-class VM (e.g. `vclhpc10`) with the same
`/home`, `/share`, `/usr/local/usrapps` and `/rsstu` mounts, its own
internet, and local `sbatch` (no SSH hop to the node or to compute). Because
it is personal, interactive CPU work, installs and env builds run there
freely — nothing there can disturb other users. GPU/heavy work still goes to
Slurm via `hpcrun`. This is where installs and interactive iteration belong.

**On-cluster fallback:** where no VCL node is used, the agent runs on a
shared login node (`ASCEND_HERE=1`, set by the installer) as a lightweight
API client ONLY — all computation as Slurm batch through `hpcrun`, and no
installs or heavy work on the shared node.

## Verified on Hazel

- 2026-09-09: full harness smoke PASSED on login03 (job 776118, partition
  compute, account <acct>_cpu): probe -> workspace -> revision -> validate ->
  submit -> COMPLETED 0:0 -> diagnose -> artifacts. Validation correctly
  rejected the NCShare spec first (partition 'interactive-gpu' not offered),
  and run_smoke.sh now writes a site-adapted CPU spec automatically.
- Accounts: yours from `sa` (faculty `<unity>_cpu`/`_gpu`; students inherit the project's) -- the probe reads them live.
- 2026-09-09: ASCEND-VCL verified — Claude Code + agent running ON a personal
  HPC-VCL node (`vclhpc10`, RHEL 9.8, same shared home/mounts); full GPU
  diagnose-fix-resubmit loop passed (job 776515 COMPLETED 0:0 on an l40s via
  gpu_partners/short_gpu). This is the preferred model (see 'Where the agent
  runs').
- Partner partitions PREEMPT by REQUEUE: a short_gpu/scavenger job that
  disappears and reappears pending was preempted, not broken — treat requeue
  as normal there, don't diagnose it as a failure.
- PATH trap seen in the wild here: a directory on PATH shipping its own
  `install` script (git-lfs) shadowed /usr/bin/install and fork-bombed any
  script calling bare `install` (SHLVL 1000 warnings). ASCEND's installer now
  uses its own `put()`; if some other tool loops with SHLVL warnings, check
  `type -a <cmd>` for PATH shadowing first.

## Duo 2FA and file transfer (from the user's Mac)

Every new SSH connection costs a password + Duo push; there are no user SSH
keys. Fix: ControlMaster multiplexing in `~/.ssh/config` on the Mac — one
authenticated master connection, then every ssh/scp/rsync for the next N
hours rides it with no prompt. Bulk data should use the `xfer` partition /
`hpc-xfer` guidance rather than hammering the login node.
