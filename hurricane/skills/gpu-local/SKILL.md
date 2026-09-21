---
name: gpu-local
description: Run compute on a single-GPU, NO-scheduler workstation (NC State MEAS "hurricane" — one RTX PRO 6000 Blackwell, 98 GB). Use whenever the task runs GPU/CPU work directly on the box: training, inference, CUDA, data prep. There is no Slurm here — you run in place and share one GPU by courtesy, so check the GPU before you launch.
---

# gpu-local — running ASCEND on a single-GPU, no-scheduler box

This is **hurricane** (`hurricane.meas.ncsu.edu`), a departmental Lenovo GPU
server at NC State MEAS. It is NOT a cluster: there is **no job scheduler**
(no `sbatch`/`srun`/`squeue`) and **one GPU shared with other users** by
courtesy, not by a queue. The agent runs directly on the box; work runs now,
in place. That makes two things your responsibility that a scheduler would
normally handle: not colliding with other users on the GPU, and keeping your
own long jobs alive.

## The box
- **GPU**: 1× NVIDIA RTX PRO 6000 Blackwell Max-Q, ~98 GB VRAM, driver 610.
  It is index 0 — the only one. `CUDA_VISIBLE_DEVICES=0`.
- **CPU/RAM**: 72 cores, 125 GB RAM. **Disk**: everything lives under
  `$ASCEND_SCRATCH` (`/home/<you>/agents`) on a ~1.9 TB NVMe; no scheduler
  scratch purge, but it is not infinite — clean up big checkpoints.
- **Environments**: conda is the base; `module load cuda` (lmod) for the
  system toolkit. No internet restriction — pip/conda/git all reach out.

## Share the GPU like a good citizen (there is no queue)
1. **Before any heavy GPU work, look first:**
   ```
   nvidia-smi
   ```
   Read who/what is already on the card and how much of the 98 GB is in use.
   If another user's process holds most of the VRAM, do NOT launch a run that
   will OOM theirs — size down, or wait, or coordinate. You are sharing.
2. **Fit your footprint to what's free**, not to the whole card. Cap it when
   you can: set batch size / model size to your slice, and for frameworks that
   grab all memory, limit it (e.g. PyTorch `PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:...`,
   TF memory growth).
3. **One heavy job at a time.** Don't fan out parallel GPU jobs on a single
   shared card.
4. **Watch a running job** without hammering: `nvidia-smi dmon` or
   `watch -n 15 nvidia-smi`.

## Run directly — there is no sbatch
- Just run it: `CUDA_VISIBLE_DEVICES=0 python train.py`. Do NOT write
  `srun`/`sbatch` wrappers — there is no scheduler to accept them.
- **Blackwell needs a recent stack.** The RTX PRO 6000 Blackwell is compute
  capability sm_120; it needs CUDA 12.8+/13.x and a matching framework build
  (e.g. PyTorch cu128/cu130 wheels). An older cu118 build will fail with "no
  kernel image is available for execution on the device" or fall back to CPU.
  Check `torch.cuda.get_device_capability()` and `nvidia-smi` after install.
- **Environments off base**: create a per-project env rather than mutating
  base — `conda create --prefix $ASCEND_SCRATCH/<proj>/env python=3.11` (or a
  named env), then activate it. Keep pip caches under `$ASCEND_SCRATCH`
  (`TMPDIR`/`PIP_CACHE_DIR` are pointed there by install).

## Keep long jobs alive (no scheduler = no babysitter)
If your ssh session or the agent dies, a foreground job dies with it. For
anything long:
- Run inside **tmux**: `tmux new -s run` … start the job … detach `Ctrl-b d`;
  reattach later with `tmux attach -t run`. (`ascend-hurricane --tmux` starts
  the whole agent session in tmux for you.)
- Or `nohup … &` with logs redirected to a file under `$ASCEND_SCRATCH`.

## MEAS house rules — REQUIRED, do not skip
Using this server carries two standing obligations. Honor them in how you work:
1. **Per-semester usage summary.** Keep a short running log of what was run on
   hurricane (project, dates, rough GPU-hours, outcome) so a brief summary can
   be handed to the server admins each semester. Append to
   `$ASCEND_SCRATCH/hurricane-usage-log.md` as projects finish.
2. **Acknowledge the server in publications/products.** Any paper, poster, or
   product that used hurricane must acknowledge the NC State MEAS Lenovo GPU
   server. When a project produces a manuscript, add the acknowledgment and
   note it in the usage log.

## Provenance
Log what ran, when, on which GPU, and the outcome — same ASCEND rule as the
clusters. A result you can't trace to a command and a date is a result you
can't defend.

## Escalation: jobs this box cannot serve
One GPU only. Multi-GPU, typed-GPU (H100/A100/L40S), or H200 jobs belong on
Hazel VCL or NCShare — recognize this mid-task, stop, and suggest the user
re-route via `ascend-all` from their Mac (this box cannot reach the clusters).
Write a handoff note (state, files to stage, next commands) before they go.
