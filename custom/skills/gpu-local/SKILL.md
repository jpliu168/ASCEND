---
name: gpu-local
description: Run compute directly on this NO-scheduler workstation (custom ASCEND site). Use whenever the task runs GPU/CPU work directly on the box - training, inference, CUDA, data prep. There is no Slurm here - you run in place and may share the hardware with other users, so check the GPU/load before you launch.
---

# gpu-local — running ASCEND on a no-scheduler workstation (custom site)

This is a **custom workstation** linked to ASCEND by its user: no job
scheduler (no `sbatch`/`srun`/`squeue`), work runs now, in place. That makes
two things your responsibility that a scheduler would normally handle: not
colliding with other users on the hardware, and keeping your own long jobs
alive.

## Know THIS box before assuming anything

Concrete facts (GPU count/model/VRAM, cores, RAM, disk, how software loads,
whether others share it) come from:

1. **`references/` in this skill folder** — any notes or policy the person who
   linked the box provided. Read them first.
2. **Live probing** — `nvidia-smi` (GPUs, who's using them), `nproc`,
   `free -h`, `df -h $HOME "$ASCEND_SCRATCH"`, `module avail 2>&1 | head`
   (Lmod?), `command -v conda`, `who`.
3. **`references/site-profile.md`** — the distilled profile. If it doesn't
   exist, write it on the first real session from the sources above (GPUs and
   VRAM, sharing rules, storage, environments, internet access) and date it.

## Share the hardware like a good citizen (there is no queue)

- `nvidia-smi` BEFORE every heavy launch; if another user's process holds most
  of a GPU, wait or ask — never evict.
- Pin yourself: `CUDA_VISIBLE_DEVICES=<free index>` on multi-GPU boxes.
- Nice long CPU jobs (`nice -n 10`), bound thread counts.
- Long runs go in `tmux` (or `nohup`) so a dropped ssh doesn't kill them;
  checkpoint anything longer than an hour.

## Keep provenance anyway

No scheduler doesn't mean no discipline: keep work under `$ASCEND_SCRATCH`,
use `hpcrun` revisions where it applies, log what ran with which env, and
clean up large checkpoints — workstation disks are small and unpurged.
