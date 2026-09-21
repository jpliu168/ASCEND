# ascend-hazel — ASCEND on Hazel via the login node (Mac-driven)

The third Hazel operating model, alongside ASCEND-VCL. Claude Code runs on
YOUR laptop; Hazel is reached per-command over the multiplexed `hazel` ssh
alias to the shared login node `login.hpc.ncsu.edu`. No VCL reservation
needed. The login node is used only for **job scheduling** and **environment
builds** — every real computation runs inside a Slurm job.

## Prerequisites

1. Claude Code installed and logged in on the laptop (`claude`).
2. The `hazel` multiplexed alias in `~/.ssh/config`:

   ```
   Host hazel
     HostName login.hpc.ncsu.edu
     User <unityID>
     ControlMaster auto
     ControlPath ~/.ssh/cm-%r@%h-%p
     ControlPersist 8h
     ServerAliveInterval 30
     ServerAliveCountMax 4
   ```

3. The ASCEND harness on Hazel (`~/bin`: hpcrun, hpcrepro, fetch-paper) —
   already there if any Hazel model was deployed before (shared home).

## Install & run

```
bash install.sh          # symlinks launcher, installs statusline + skill
ssh hazel                # warm the link once: password + Duo, persists 8h
ascend-hazel --check     # socket probe + login node / slurm / tools check
cd <project> && ascend-hazel
```

`ascend-hazel -d <dir>` picks the project; first run seeds AGENTS.md (the
ASCEND-HAZEL policy, Unity ID substituted) and the statusline.

## vs the other Hazel model

| | ascend-hazel | ascend-vcl |
|---|---|---|
| agent runs | on the Mac | on the VCL node |
| needs | `hazel` alias (Duo per 8h) | VCL reservation + `hazel-vcl` alias |
| good for | scheduling batch jobs, light staging, env builds | interactive/persistent on-cluster work, big installs, survives laptop close (`--tmux`) |
