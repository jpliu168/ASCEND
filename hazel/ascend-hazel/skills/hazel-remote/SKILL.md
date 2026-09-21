---
name: hazel-remote
description: Drive NC State's Hazel HPC from this Mac via the multiplexed `hazel` ssh alias to the shared login node — schedule Slurm jobs and build environments there, run all compute through sbatch. Use whenever a task needs Hazel CPUs/GPUs, Slurm jobs, files under /share/@@UNITYID@@, or the cluster tools hpcrun, hpcrepro, fetch-paper (ASCEND-HAZEL model; the VCL-node model is the hpc-remote skill).
---

# Hazel remote execution from the Mac (login-node model)

The ssh alias `hazel` is a ControlMaster-multiplexed link to the shared login
node `login.hpc.ncsu.edu` (ControlPersist 8h). The agent stays on the Mac;
every cluster command is `ssh hazel '<cmd>'`.

## Hard rules

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
- **Duo: the agent never answers it.** A cold link (new connection) prompts
  password + Duo. If `ssh -O check hazel` shows no socket, STOP and ask the
  user to run a plain `ssh hazel` in another terminal; setup persists 8h.
  Never let a hazel command sit at an auth prompt.

| Want | Use |
|---|---|
| is the link warm? | `ssh -O check hazel` (local, instant, never prompts) |
| my queue | `ssh hazel 'squeue -u @@UNITYID@@'` |
| live GPU capacity | `ssh hazel 'si --gpus --qos short_gpu'` |
| QOS list | `ssh hazel 'sqos'` |
| submit | `ssh hazel 'sbatch /share/@@UNITYID@@/agents/<proj>/job.sbatch'` |

## Patterns

- **Batch commands** — each `ssh hazel` call costs ~12 s of login-shell init
  on GPFS: `ssh hazel 'cd /share/@@UNITYID@@/agents/<proj> && cmd1 && cmd2'`.
- Fresh shell per call — no cwd/env carryover. Absolute paths or `cd ... &&`;
  conda: `ssh hazel 'source ~/.bashrc && conda activate /share/@@UNITYID@@/envs/<env> && ...'`.
- All compute via sbatch (prefer `~/bin/hpcrun`): submit, then poll
  `ssh hazel 'squeue -u @@UNITYID@@'`, read logs with `ssh hazel 'tail -50 <log>'`.
- **Typed gres mandatory** (`--gres=gpu:l40s:1`); l40s + QOS short_gpu on
  gpu_partners allocates near-instantly. Accounts: @@UNITYID@@_cpu / @@UNITYID@@_gpu.
- Job scripts `module load cuda` before GPU code; a silent GPU log usually
  means old CUDA on a new GPU. GPU timings need `torch.cuda.synchronize()`.
- Files: `rsync -av <local>/ hazel:/share/@@UNITYID@@/agents/<proj>/` up;
  scp back only small results/figures.
- Conda/pip: pkgs_dirs + pip cache under /share/@@UNITYID@@; envs with
  `--prefix`, never bare `-n` ($HOME is 15 GB / 10k files, scripts only).
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
