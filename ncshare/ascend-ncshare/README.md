# ASCEND-NCSHARE

ASCEND with the agent on the Mac and the compute on NCShare. Claude Code runs
locally (Mac login, Mac network, Mac skills); every cluster command is routed
through the `ncshare-agent` / `ncshare-agent-gpu` ssh aliases, which provision
or reuse SLURM jobs automatically. Complement to `../../common/ascend/`, which runs the
agent on a cluster compute node.

```
ascend-ncshare --check        # verify both cluster aliases end-to-end
cd ~/regional_gs
ascend-ncshare                # banner, then Claude Code in this project
```

## What install.sh puts where

- `~/.local/bin/ascend-ncshare` → symlink to `bin/ascend-ncshare` (edits here are live)
- `~/.claude/ascend-ncshare-statusline.sh` — ASCEND-NCSHARE statusline (copy)
- `~/.claude/skills/ncshare-remote/` — the remote-execution skill (copy;
  re-run install.sh after editing the bundle's copy)

Per project, the launcher adds (only if absent): `AGENTS.md` from
`AGENTS-template.md`, and `.claude/settings.json` wiring the statusline.

## Division of labor

- **ascend-ncshare**: day-to-day driving, GPU jobs (allocated only while a command
  runs), anything needing the Mac's network or skills.
- **ascend (on cluster)**: heavy interactive editing of files under /work.

Knowledge base stays canonical on the cluster (`~/.ascend`); the Mac reads the
`../ncshare-sync/` mirror — refresh with `../sync-ncshare.sh` after projects.
