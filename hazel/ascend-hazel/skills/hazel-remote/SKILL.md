---
name: hazel-remote
description: Drive NC State's Hazel HPC from this Mac via the multiplexed `hazel` ssh alias to the shared login node — schedule Slurm jobs and build environments there, run all compute through sbatch. Use whenever a task needs Hazel CPUs/GPUs, Slurm jobs, files under @@SHAREDIR@@, or the cluster tools hpcrun, hpcrepro, fetch-paper (ASCEND-HAZEL model; the VCL-node model is the hpc-remote skill).
---

# Hazel remote execution from the Mac (login-node model)

The ssh alias `hazel` is a ControlMaster-multiplexed link to the shared login
node `login.hpc.ncsu.edu` (ControlPersist 8h). The agent stays on the Mac;
every cluster command is `ssh hazel '<cmd>'`.

## Hard rules

- **Run `ssh hazel 'quota_display'` FIRST, every session**, before real
  work. Warnings (🟡) are fine; a critical (🔴, over-quota) result on any
  filesystem is a hard stop until the user clears it and a re-run comes
  back clean. See AGENTS.md's Quota check rule for the full policy.
- **`hazel` is the only route.** Never `ssh @@UNITYID@@@login.hpc.ncsu.edu`
  directly, never another Hazel host, never a timeout/short-circuit flag to
  route around the alias.
- **The login node is shared — two uses only:**
  1. **Scheduling**: sbatch, squeue, sacct, scancel, sinfo, scontrol,
     si, sq, sa, sqos, hpcrun.
  2. **Environment builds**: conda/pip (it has internet; compute nodes don't),
     module ops, git clones, editing/staging files.
  **Nothing else computes there.** No Python data processing, training,
  inference, heavy compiles, or trial runs — those go into Slurm jobs.
- **Every command that can use more than trivial CPU is capped to 4 cores.**
  The login node is shared with everyone else's interactive sessions, and
  SSH itself has no option for this (it's just a transport) — so the cap is
  applied inside the remote command with `taskset`, not on the `ssh` call.
  Prefix any conda/pip solve, compile, git operation on a large repo, or
  similar with `$HAZEL_THROTTLE` (defined below):
  ```
  HAZEL_THROTTLE='taskset -c 0-3 nice -n 10 env OMP_NUM_THREADS=4 MKL_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4 NUMEXPR_NUM_THREADS=4 VECLIB_MAXIMUM_THREADS=4 NUMBA_NUM_THREADS=4'
  ssh hazel "$HAZEL_THROTTLE conda env create --prefix @@SHAREDIR@@/agents/<proj>/env_X -f X.yml"
  ```
  `taskset -c 0-3` is the hard guarantee (the OS will never schedule the
  command's threads/processes onto more than 4 cores, however many it
  spawns); the env vars stop BLAS/OMP-based libraries from spinning up far
  more threads than that and thrashing inside the cap. Plain scheduling
  commands (sbatch, squeue, sinfo, ...) and light file ops (ls, cat, cd,
  editing) don't need it — they're already cheap. **This cap is specific to
  the shared login node and does not apply to the VCL arrangement**
  (`ascend-vcl`, hpc-remote skill): a VCL node is a personal reservation, not
  shared with other users, so there is nothing to protect it from.
- **Duo: the agent never answers it.** A cold link (new connection) prompts
  password + Duo. If `ssh -O check hazel` shows no socket, STOP and ask the
  user to run a plain `ssh hazel` in another terminal; setup persists 8h.
  Never let a hazel command sit at an auth prompt.

| Want | Use |
|---|---|
| is the link warm? | `ssh -O check hazel` (local, instant, never prompts) |
| my queue | `ssh hazel 'squeue -u @@UNITYID@@'` |
| live GPU capacity | `ssh hazel 'si --gpus --qos short_gpu'` (or `--qos gpu`) |
| QOS list | `ssh hazel 'sqos'` |
| submit | `ssh hazel 'sbatch @@SHAREDIR@@/agents/<proj>/job.sbatch'` |

## Patterns

- **Batch commands** — each `ssh hazel` call costs ~12 s of login-shell init
  on GPFS: `ssh hazel 'cd @@SHAREDIR@@/agents/<proj> && cmd1 && cmd2'`.
- Fresh shell per call — no cwd/env carryover. Absolute paths or `cd ... &&`;
  conda: `ssh hazel 'source ~/.bashrc && conda activate @@SHAREDIR@@/envs/<env> && ...'`.
- All compute via sbatch (prefer `~/bin/hpcrun`): submit, then poll
  `ssh hazel 'squeue -u @@UNITYID@@'`, read logs with `ssh hazel 'tail -50 <log>'`.
- **Typed gres mandatory** (e.g. `--gres=gpu:l40s:1`) — pick the type by
  checking BOTH `ssh hazel 'si --gpus --qos short_gpu'` (or `--qos gpu`) for
  `Avail > 0` AND `ssh hazel 'sqos'` for that type's `GrpTRES` cap under the
  QOS you're requesting. `Avail > 0` alone is not enough — a type can show
  availability and still be zero-capped under that QOS, landing the job
  pending on `QOSGrpGRES`. A type with the most total capacity (l40s) is
  routinely fully allocated and is not a safe default to assume. Accounts:
  @@UNITYID@@_cpu / @@UNITYID@@_gpu.
- Job scripts `module load cuda` before GPU code; a silent GPU log usually
  means old CUDA on a new GPU. GPU timings need `torch.cuda.synchronize()`.
- Files: `rsync -av <local>/ hazel:@@SHAREDIR@@/agents/<proj>/` up;
  scp back only small results/figures.
- Conda/pip: pkgs_dirs + pip cache under @@SHAREDIR@@; envs with
  `--prefix`, never bare `-n` ($HOME is 15 GB / 10k files, scripts only).
  Solves are a CPU cost on a shared node — run them through
  `$HAZEL_THROTTLE` (see Hard rules).
- /share purges after 30 days without access; /rsstu is a third shared FS.

## Gotchas

- **exit 255 / hang on a cold link** = no ControlMaster socket → warm it
  (`ssh hazel` by the user), never retry in a loop and never add
  `-o BatchMode=yes` to "fix" it (that only masks the Duo prompt).
- ControlPath is `~/.ssh/cm-%r@%h-%p` (no subdir) — nothing to mkdir.
- Compute nodes have NO internet: every download happens on the login node
  (or the Mac, then rsync up) BEFORE the job runs.
- Interactive GPU sessions, huge installs, or a persistent on-cluster agent
  are the VCL node's job → suggest `ascend-vcl` (hpc-remote skill) instead.
