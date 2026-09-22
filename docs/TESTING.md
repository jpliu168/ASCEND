# Tester checklist

Thank you for testing. The goal is to find out whether someone who is not the
author can go from nothing to a working agent on their own resource, following
only the written instructions. **Please follow the steps literally and do not
work around problems silently.** A step you had to guess at is the finding.

Record the result of every step. Anything that made you pause, re-read, or
search elsewhere is worth reporting even if you eventually got past it.

---

## Before you start

Tell us your setup, because almost every failure so far has been
platform-specific:

- Machine and OS (macOS version, Ubuntu version, or Windows + WSL distro)
- Which resource you are testing: **Hazel**, **NCShare**, or **hurricane**
- Whether you already had Claude Code installed
- Whether you already had working SSH to that resource

---

## Step 0 — Get the code

Take **one** of these two paths. Say which one you used.

**Path A, git clone.** Needs a GitHub account that has been invited to the
repository.

    git clone https://github.com/jpliu168/ASCEND.git
    cd ASCEND

GitHub will ask for a username and password. **The password is not your GitHub
password.** HTTPS requires a personal access token: make one at
https://github.com/settings/tokens (classic token, `repo` scope), and paste that
as the password. If you use GitHub Desktop or have SSH keys on GitHub already,
either of those works too and is less painful.

**Path B, zip.** Needs no GitHub account at all. Unzip the archive you were
sent and `cd` into it. Use this path if the GitHub side is fighting you; the
installer is identical either way, and we would rather learn about installer
problems than token problems.

**Report:** did you get the code? How long did the auth part take, and what did
you have to look up?

---

## Step 1 — Read before running

Open `README.md` and read the Quick start and Prerequisites sections, and the
standalone guide for your resource in `docs/`.

**Report:** after reading and before running anything, did you know what was
about to happen to your machine? Was anything missing that you needed?

---

## Step 2 — Install

    ./install.sh

This gives an interactive menu. Or go straight to one resource:

    ./install.sh hazel
    ./install.sh ncshare
    ./install.sh hurricane

Expect it to check your platform, check for Claude Code and offer to install it
if missing, create the SSH alias if you do not have one, open a second terminal
so you can authenticate once, copy files out to the resource, and symlink the
launcher into `~/.local/bin`.

> [!warning]
> Do not run `install.sh` from a TMUX session on your machine as it will not open a new terminal to warm up the SSH connection. Run it from a regular terminal session.

**Report:** every prompt you were unsure how to answer. Every point where you
did not know whether it was working or stuck. Anything that failed outright,
with the exact message.

---

## Step 3 — Verify from a NEW terminal

This matters: open a **fresh** terminal window, not the one you installed from.

    ascend-hazel --check
    ascend-ncshare --check
    ascend-hurricane --check

A healthy Hazel check reports `link: WARM`, then `login node: OK` with the
hostname, a Slurm version, and the paths to `hpcrun` and `hpcrepro`. If it says
`link: COLD`, that is expected behaviour, not a bug: run `ssh hazel` once in
another terminal to authenticate, then re-run the check.

Known stumbles, all documented in the README's Troubleshooting section. Please
check whether the documented fix actually worked for you:

- `command not found` right after installing
- NCShare exiting 255 with no message
- NCShare appearing to hang for minutes on the first connection
- hurricane failing to resolve its hostname

**Report:** did `--check` pass? If it failed, did the README's troubleshooting
entry fix it, and was the entry easy to find?

---

## Step 4 — Start the agent on a real project

    mkdir -p ~/ascend-test && cd ~/ascend-test
    ascend-hazel          # or ascend-ncshare / ascend-hurricane

First start in a directory seeds an `AGENTS.md` with your own username
substituted in. Open that file and read it.

**Report:** is your username correct everywhere in `AGENTS.md`? Does any path
in it point somewhere that does not exist for you? Do any of the rules look
wrong for your account or project?

---

## Step 5 — Give the agent a real job

Ask it to do something small but genuine on your resource. Suggestions:

- Ask it what GPUs are available and to explain what it would request for a
  single-GPU PyTorch training run.
- Ask it to build a small Conda environment and report where it put it.
- Ask it to submit a trivial job, wait for it, and read the output log.

**Report:** did it respect the site rules? Specifically, on Hazel, did it keep
computation off the login node and use a typed GPU request? Did it create the
Conda environment with `--prefix` under `/share`, not a bare `-n`? Did it do
anything that would have annoyed your site administrator?

---

## Step 6 — The front door

    ascend-all

Describe a job in plain language. It probes live capacity, recommends a
resource with reasoning, and asks you to confirm. Try answering `0`, which
should discard the recommendation and let you describe a different job.

**Report:** was the recommendation sensible? Was the reasoning it gave true?
Did the confirmation prompt make it clear what was about to happen?

---

## What to send back

Open an issue at https://github.com/jpliu168/ASCEND/issues (there is a template
for this), or just email the answers. Either is fine.

Please include, for anything that went wrong, the **exact terminal output**
rather than a description of it. Redact your username if you prefer, but keep
error messages verbatim; a paraphrased error is usually not diagnosable.

The most valuable things you can tell us, in order:

1. A step where you got stuck and had to ask someone or search elsewhere.
2. An instruction that was ambiguous, even if you guessed right.
3. Something the agent did on the cluster that it should not have done.
4. A step that worked but that you did not trust while it was running.
