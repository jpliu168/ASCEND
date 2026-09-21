# ASCEND-HURRICANE

ASCEND on **hurricane** (`hurricane.meas.ncsu.edu`) — a single-GPU Lenovo
Blackwell server at NC State MEAS. It's the simplest ASCEND model: **no
scheduler**, so the agent runs directly on the box, using the one local GPU.

## Layout
- `skills/gpu-local/` — the single-GPU, no-scheduler skill (Blackwell build
  notes, shared-GPU etiquette, MEAS house rules). Overlaid onto the harness.
- `ascend-hurricane/` — the Mac launcher (`bin/ascend-hurricane`, SSHes to the
  box), the on-box twin (`bin/ascend-hurricane-node`, installed as
  `~/bin/ascend-hurricane`), and `AGENTS-template.md` (ASCEND-HURRICANE).
- `deploy.sh` — rsync `common/ascend` + `skills/gpu-local` to the box and run
  the harness `install.sh` with `ASCEND_HERE=1`.

## One-time deploy (from the Mac, over the warm `hurricane` link)
```
cd ~/agents/hurricane && bash deploy.sh
```
Installs `~/bin/{ascend,hpcrun,hpcrepro,fetch-paper,ascend-hurricane}`, the
`gpu-local`/`paper-fetch`/`repro` skills, Claude Code permissions, and the
knowledge base — all under `/home/<you>` (working dir `$HOME/agents`).

Then link the Mac launcher into your PATH:
```
ln -sf ~/agents/hurricane/ascend-hurricane/bin/ascend-hurricane ~/.local/bin/ascend-hurricane
```

## Use
```
ascend-hurricane --check      # from the Mac: link + claude + GPU
ascend-hurricane              # from the Mac: agent starts ON the box
ascend-hurricane --tmux       # long runs that survive closing the laptop
```
Already on the box (via `ssh hurricane`)?  just run `ascend-hurricane` (or
`ascend`) there — same agent, same skills.

## The box
One RTX PRO 6000 Blackwell (98 GB, index 0), 72 CPU, 125 GB RAM, Ubuntu 22.04,
conda + `module load cuda`, full egress. Working dir on a 1.9 TB NVMe.
**Shared GPU, no queue** — check `nvidia-smi` before heavy runs. **MEAS rules**:
per-semester usage summary + cite the Lenovo server in publications.
