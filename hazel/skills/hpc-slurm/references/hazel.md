# Hazel (NCSU HPC) — site profile

Facts for running ASCEND on NC State's Hazel cluster (`login.hpc.ncsu.edu`),
gathered from hpc.ncsu.edu docs 2026-09-09, primarily the
[Hazel Slurm QuickStart guide](https://hpc.ncsu.edu/QuickStart/QuickStart-slurm.php).
Where this file and `hpcrun site --probe` output disagree, trust the probe —
it reads the live cluster. This file is a working summary, not a substitute
for the QuickStart guide or Hazel's [Acceptable Use Policy](https://hpc.ncsu.edu/Accounts/GetAccess.php) — read both before
running real work here.

## Scheduler

Slurm, production since 2026-08-17. LSF still visible but retiring end of
Fall 2026 — ignore `bsub`/`bjobs` entirely; everything goes through Slurm.

## Storage — sharply different from NCShare

`$ASCEND_SHARE` is your writable /share dir, always $GROUP-scoped: `/share/<group>/<unity>` -- `<group>` is a faculty member's own group or a project group a student was added to, never bare `/share/<unity>`; `$ASCEND_SCRATCH` = `$ASCEND_SHARE/agents`. Both are exported in the shell (`echo $ASCEND_SHARE`). Examples below use them.


| Path | Quota | Policy |
|---|---|---|
| `/home/$USER` | **15 GB, 10K files** | backed up daily; scripts/configs ONLY |
| `/share/$GROUP` | 20 TB, 1M files | scratch; **30-day-access purge**, no backup |
| `/usr/local/usrapps/$GROUP` | 100 GB, 250K files | software/envs; backed up; **compute nodes cannot write here** |

`quota_display` (system tool, no args needed) reports live usage against
these limits with a 🟢/🟡/🔴 status per filesystem plus an overall STATUS
line. Run it first, every session, before real work — see the Quota check
rule in AGENTS.md for the pass/stop policy (warnings are fine; a 🔴 critical
result is a hard stop). **On a VCL node it degrades to `NFS mounted - quota
information not available`** for every path, because VCL mounts these
filesystems over NFS rather than native GPFS and `mmlsquota` isn't present
there — a known, deliberate limitation in the tool, not a bug; on the login
node (native GPFS) it always reports real numbers.

Consequences the agent must respect:
- ASCEND scratch root is `/share/$GROUP/$USER/agents` (installer sets
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

## Partitions and QOS — **`sqos` is the live source of truth, not this table**

Names below are structural and change rarely; max-wall and GrpTRES caps are
not — they've drifted since this file was last hand-updated (e.g. the `gpu`
QOS below was recorded as 4 d and is actually 3 d as of this check). **Run
`sqos` yourself before choosing `--partition`/`--qos` for anything that
matters** — it prints exactly this table, live, for your account:

| Partition | QOS | Max wall (per `sqos`, may drift) | Notes |
|---|---|---|---|
| compute | normal (default) | 4 d | CPU; `--qos=long` → 10 d |
| compute_partners | short (DEFAULT) / scavenger | 2 h / 4 d | idle partner nodes; preemptable (REQUEUE) |
| gpu | gpu (default) | **3 d** | all users |
| gpu_partners | short_gpu / scavenger_gpu | 2 h / 4 d | idle partner GPUs; **short_gpu caps h100/a100 group usage at 0 — those types are only reachable via scavenger_gpu**, not short_gpu, despite being nominally in the partition |
| xfer | xfer | 4 d | data transfers, 4 cores / 24 GB cap |

Helper commands on the cluster: `si` (free cores/GPUs), `sq` (queue), `sa`
(your accounts), `sqos` (your QOS limits) — none of these are optional
extras, they're how you find out where to actually run instead of guessing.

## GPUs — typed gres is MANDATORY, and availability changes by the hour

`--gres=gpu:1` is REJECTED. Type names as Slurm actually spells them (NOTE
the underscores in the consumer cards). **Total capacity per type (below)
is a structural fact and drifts slowly; how much of it is free RIGHT NOW
does not — it can be fully allocated one hour and wide open the next.**
Before requesting any type, check BOTH `si --gpus --qos <qos>` (e.g.
`si --gpus --qos short_gpu`, `si --gpus --qos gpu`) for `Avail > 0`, AND
`sqos` for that type's `GrpTRES` group cap under the QOS you're requesting.
**`Avail > 0` alone is not enough** — a type can show availability in
`si --gpus` and still be zero-capped (or capped lower than expected) for
the specific QOS you picked, which submits fine but then sits pending on
`QOSGrpGRES` instead of running. Never pick a type just because it's
"usually" free or "usually" the cheapest; that reasoning, or checking only
`Avail`, is exactly what produces a job that sits pending for hours or
days because the type you assumed was open isn't, under that QOS:

| partition | gres types (total capacity, per `si --gpus`, may drift) |
|---|---|
| gpu | `h100` (4), `l40` (4), `a100` (4), `a30` (8), `p100` (4), `rtx_2080` (4), `gtx_1080` (2) |
| gpu_partners | `h200` (8), `l40s` (20 under short_gpu / 32 under scavenger_gpu), `rtx_6000_pro` (24, uncapped by QOS), `a100`/`a10`/`h100` (scavenger_gpu only) |

So: `--gres=gpu:h100:1 -p gpu --qos=gpu`, or for a short smoke on idle
partner hardware `--gres=gpu:l40s:1 -p gpu_partners --qos=short_gpu` (2 h,
higher priority — **but check `si --gpus --qos short_gpu` (or `--qos gpu`
for the `gpu` partition) first**: l40s has the largest total allocation on
gpu_partners, which is not the same as having free capacity at this moment,
and `rtx_6000_pro` is easy to miss
since it isn't QOS-capped at all). **h200, l40s, and rtx_6000_pro exist
ONLY in gpu_partners**; the gpu partition's Ada card is `l40`.
TRES billing weights (allocation cost per GPU-hour): h200=120, h100=90,
a100=50, l40s=40, l40=32, a30=30, a10=18, p100=10 — a smoke on l40/l40s
costs a fraction of an H100 run, when one is actually free. DefaultTime is
1 h everywhere; walltime caps come from the QOS, not the partition.
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
