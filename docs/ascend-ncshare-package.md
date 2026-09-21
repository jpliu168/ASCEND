# ASCEND (NCShare) — an AI research agent on NC State's NCShare HPC

Run Claude Code as a research agent that drives the **NCShare** cluster from
your **laptop** (the ASCEND-NCSHARE model): the agent reasons locally, and every
cluster command is routed through the `ncshare-agent` / `ncshare-agent-gpu`
ssh aliases, which provision or reuse a SLURM job automatically. A typed
harness (`hpcrun`) on the cluster enforces validation, budgets, and provenance.

Works on **macOS, Linux, and Windows (WSL/Ubuntu)**. On Windows, do everything
inside the WSL shell — Claude Code, ssh, and the `~/.ssh` config all live in
WSL's Linux home, never the Windows side.

## Before you start (one-time, outside this bundle)
1. An **NCShare account** (username, e.g. `rhe1`) with a `/work/<user>` dir.
2. The **`ncshare-agent` and `ncshare-agent-gpu` ssh aliases** working, set up
   per NCShare's own guide: https://userguide.ncshare.org/guides/ai
   (This bundle detects them; it does not create the NCShare proxy.)
3. **Claude Code** installed on your laptop (`npm i -g @anthropic-ai/claude-code`
   or the native installer), and logged in (`claude` → `/login`).

---

## One command

From the unzipped bundle:

```
bash ncshare/setup.sh
```

It will:
- confirm your ncshare-agent aliases exist and read your username from them,
- create `~/.ssh/sockets` (the missing-dir bug that causes exit-255 on ssh),
- warm the cluster link once,
- **install on NCShare** — the harness (`hpcrun`, `hpcrepro`, `fetch-paper`) and
  the skills (`hpc-slurm`, `paper-fetch`, `repro`), auto-detecting `/work/<user>`,
- **install on your laptop** — the `ascend-ncshare` launcher, the `ncshare-remote`
  skill, and the statusline,
- link `ascend-ncshare` / `fetch-paper` / `paper-grab` into `~/.local/bin`.

Then:

```
ascend-ncshare --check          # verify both cluster aliases end-to-end
cd <your project>
ascend-ncshare                  # agent starts here; cluster work goes over the aliases
```

Prefer the agent **on** a compute node instead? `ssh ncshare-agent`, then
`ascend` — same tools, same skills, running on the node.

---

## What lands where (do it by hand if you skip setup.sh)

**A. On NCShare** (the cluster side — harness + skills + AGENTS/CLAUDE guidance):
```
scp -r common/ascend ncshare-agent:~/ascend-install
ssh ncshare-agent 'cd ~/ascend-install && ./install.sh'   # detects /work/<user>
```
Installs `~/bin/{hpcrun,hpcrepro,ascend,fetch-paper}`, `~/.claude/skills/{hpc-slurm,paper-fetch,repro}`,
Claude Code permissions (stops the Yes/No prompting), the knowledge base in
`~/.ascend`, and the `/work/<user>` work dirs.

**B. On your laptop / WSL** (the launcher + remote skill):
```
bash ncshare/ascend-ncshare/install.sh
```
Installs `~/.local/bin/ascend-ncshare`, `~/.claude/skills/ncshare-remote/`, and the
statusline. Requires the `ncshare-agent` aliases + `~/.ssh/sockets` to already
exist.

The only per-user setting is your NCShare username, which drives `/work/<user>`
everywhere. Rebuild the shareable zip any time with `bash build-package.sh`.

## What's inside
- `common/ascend/` — the site-detecting harness (hpcrun, hpcrepro, fetch-paper),
  generic skills (paper-fetch, repro), and `install.sh`.
- `common/mac/bin/` — laptop paper tools (paper-drop, paper-grab).
- `ncshare/skills/hpc-slurm/` — NCShare-native Slurm skill (H200, no modules).
- `ncshare/ascend-ncshare/` — the laptop launcher, `ncshare-remote` skill, statusline,
  and the agent instruction template.
- `ncshare/{setup.sh, deploy.sh}` — the one-command install / re-deploy.
