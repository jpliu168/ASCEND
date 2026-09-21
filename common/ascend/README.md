# ASCEND

**Autonomous Scientific Computing Engine for Novel Discovery** — an AI-powered
automation system for scientific computing and discovery. The harness is
site-detecting: the same bundle installs on a Slurm cluster or on a
single-GPU workstation with no scheduler at all.

Hand it a task, a repository, or a published paper. It writes and validates the
code, submits jobs to Slurm, reads the logs, diagnoses failures, repairs what is
mechanically repairable, resubmits, and reports what actually happened — inside
limits it cannot raise on its own. Then it records what the project taught, so
the next one starts further along.

```
ascend                     # the front door: claims a compute node, starts the agent
hpcrun                     # submit / diagnose / iterate on Slurm jobs
hpcrepro                   # paper or repo -> running reproduction -> verdict -> lessons
```

ASCEND is built on **Claude Code** (the version is shown in the banner and the
status line) plus the `hpc-slurm` and `repro` skills. Claude Code's own startup
banner cannot be replaced — there is no setting for it — so ASCEND prints above
it, and the status line carries the name for the rest of the session.

Originally written from the gateway as-built report, now kept at
`~/agents/_archive-2026-09/ncshare-login-node-era/hpc-agent-gateway-architecture.md`.
That report describes the retired model in which Claude Code ran on the NCShare
login node; this harness no longer works that way.

## It gets better with use

Every finished project ends with `hpcrepro learn`, which harvests what was
demonstrated — environment gotchas, build recipes that worked, failure-to-fix
chains, and what each reproduction actually settled — into a knowledge base at
`~/.ascend/knowledge`. Not `/work`: that is purged after 75 days, and a memory
that evaporates is worse than none.

At the start of the next project, `auto` hands that experience back. A new JAX
repo immediately inherits "LD_LIBRARY_PATH must be unset or JAX falls back to
CPU" from the project that discovered it, with the job ID that proved it.

The design problem is that an accumulating store turns into confident folklore,
so the rules are deliberate:

- **Provenance on everything** — which project, which job, when. No anonymous claims.
- **A lesson is a `hypothesis` until a job actually succeeded with it in force.**
- **A repair is credited as a fix only if the *next* attempt succeeded** — otherwise
  it is recorded as tried-and-did-not-resolve, which is just as worth knowing.
- **Re-learning the same project does not raise confidence.** Only independent
  re-observation does.
- **Contradictions are surfaced, never merged.** Two lessons disagreeing about the
  same thing is a finding, not something to average.
- **Lessons go stale and say so** — unconfirmed for six months and they are flagged.
- **Nothing is auto-applied.** `recall` surfaces; the agent checks; you decide.
- **Wrong lessons are retired with a recorded reason**, so the same mistake is not
  learned again from scratch.

`learn` also regenerates `references/learned.md` inside the installed skill,
which is how the accumulated experience actually reaches the next session's
context rather than sitting in a database nobody reads.

## Install

You do not copy this directory or run `install.sh` by hand. Each resource has a
`deploy.sh` that composes this harness with that resource's skill, stages it,
and runs the installer remotely. Run it **from your Mac**:

```bash
bash ~/agents/ncshare/deploy.sh      # NCShare   (Slurm)
bash ~/agents/ncsuhpc/deploy.sh      # Hazel VCL (Slurm)
bash ~/agents/hurricane/deploy.sh    # hurricane (no scheduler, ASCEND_HERE=1)
```

`deploy.sh` is the one thing that connects to a login node directly, because it
rsyncs and installs; you run it yourself. The agent never does — all of its
cluster work goes through the ssh aliases.

New users install from a package instead — `universal/dist/ascend-universal.zip`,
whose `setup.sh` walks through ssh multiplexing, the resource choice, and the
deploy in one pass.

Then start a session with the launcher for the destination you want, **not** by
sshing anywhere yourself:

```bash
ascend-ncshare      # agent on the Mac, compute on NCShare via the ssh aliases
ascend-vcl          # Hazel VCL node
ascend-hurricane    # the MEAS single-GPU box
ascend-all          # routes you to the right one
```

It installs `ascend`, `hpcrun` and `hpcrepro` to `~/bin`, the `hpc-slurm` and
`repro` skills to `~/.claude/skills`, the status line to `~/.claude`, the
knowledge base to `~/.ascend`, creates
`/work/$USER/{tmp,.pipcache,agent-workspaces,agent-projects}`, adds a `~/.bashrc`
block that keeps pip's temp off the 31 GB root partition, and probes the
cluster. It also warns if `~/.bashrc` auto-activates a conda env, which is the
cause of the "wrong interpreter" class of bug in the regional_gs docs.

If Claude Code isn't installed, the script prints the commands.

### Upgrading

Re-run that resource's `deploy.sh`. It is
idempotent and **preserves your state**: workspaces, revisions, ledgers, and
`site.json` are untouched, the `~/.bashrc` block is not duplicated, and an
edited `CLAUDE.md` is left alone (the new one lands beside it as
`CLAUDE.md.new`). **The knowledge base in `~/.ascend` is never touched** — an
upgrade that forgot what the system had learned would defeat the point.

```bash
bash ~/agents/ncshare/deploy.sh     # or ncsuhpc/ , hurricane/
```

Nothing needs uninstalling first.

## Verify

```bash
ssh ncshare-agent 'bash ~/ascend-deploy/pilot/run_smoke.sh'          # happy path, ~3 min
ssh ncshare-agent 'bash ~/ascend-deploy/pilot/run_smoke.sh --full'   # + crash and OOM paths
```

This costs a few GPU-minutes on `interactive-gpu`. Run it once before pointing
the harness at real science. It should end with `succeeded=True` and a real
H200 device name.

## What's here

```
bin/ascend                  the front door: banner, allocation, agent
bin/hpcrun                  the job harness (stdlib python3, no dependencies)
bin/hpcrepro                reproduction harness + the learning loop
bin/claude-node             legacy alias for ascend
install.sh                  site-detecting installer (run by deploy.sh)
skills/hpc-slurm/           the skill Claude Code loads for Slurm work
    SKILL.md                how to drive the loop, and the judgement calls
    references/hpcrun.md    command reference + job-spec schema
    references/regional-gs.md   project specifics: env traps, curriculum, causality
    references/failure-modes.md generated from the diagnosis rule table
skills/repro/               the skill for "reproduce this paper / this repo"
    SKILL.md                claims-first method, cost tiers, when to stop and ask
    references/hpcrepro.md  command reference + recipe schema
    references/worked-example.md  Keisler 2022, URL to ledger, including the
                            claims that turned out to be unverifiable
pilot/smoke/                smoke-test job with selectable failure modes
pilot/regional_gs/          the real Gulf Stream pipeline as a worked example
                            (spec.json + pipeline.sh, resubmit-safe)
pilot/run_smoke.sh          end-to-end verification against the real cluster
pilot/mockslurm/            fake sbatch/squeue/sacct for offline testing
docs/CLAUDE.md              working agreement, installed to /work/$USER/CLAUDE.md
docs/claude-settings.json   permission rules, merged into ~/.claude/settings.json
docs/statusline.sh          the ASCEND status line
docs/ascend-architecture.md   the as-built design report
docs/ascend-architecture.pptx seminar deck
```

## Authentication — do not pay twice

A Claude Pro or Max subscription **covers Claude Code**. But
`ANTHROPIC_API_KEY` sits above subscription OAuth in the precedence order and
**silently overrides it**, so having the key set means per-token billing on
top of a plan you already pay for. `install.sh` warns if it finds one.

`/login` needs a browser callback and does not work over SSH. The headless
route:

```bash
claude setup-token                       # on a machine with a browser
export CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.config/anthropic/oauth-token)"
```

Check with `/status`: a "Login method" row means the subscription is in use;
an "API key" row means it is not.

Keep the token at mode `600` — `/hpc/home` is group-readable, and a one-year
OAuth token is worth more than a rotatable API key.

Max limits are caps, not charges. The scarce resource is **Opus hours**, so
`/model sonnet` for routine harness driving makes the plan go much further —
`hpcrun` enforces the safety properties deterministically, so it does not
depend on the model tier.

## Permissions — stopping the Yes/No prompting

By default Claude Code asks before every tool call, which makes the loop
unusable. `install.sh` writes `~/.claude/settings.json` (merging, never
clobbering — your previous file is kept as `settings.json.bak`):

- **`defaultMode: "auto"`** — Claude Code runs commands without prompting, with
  a background classifier reviewing them instead. Available on Pro/Max/Team.
  Press **Shift+Tab** in a session to cycle modes if you want something
  stricter for a while.
- **allow** — `hpcrun` and `hpcrepro` in full, Slurm queries, git, the package
  managers, the download tools, web search and fetch, ordinary file work,
  `python3`, and the file-editing tools.
- **ask** — `rm`, `rmdir`, `git push`, `git reset`, `git clean`. Deletion and
  history rewriting only.
- **deny** — `sbatch`, `scancel`, `srun`, `salloc`, `sudo`, `chown`, and reads
  of credential files.

**An `ask` rule beats an `allow` rule** — across every settings file, at every
scope. That makes a stale `ask` entry the usual cause of "why is it still
prompting?", because it silently cancels the matching allow. `install.sh`
detects that case and removes the stale rule, keeping any `ask` you added
yourself. It also upgrades a `defaultMode` of `acceptEdits` (what earlier
versions of this bundle shipped) to `auto`, since `acceptEdits` auto-approves
file edits but still asks for every single shell command.

Earlier versions put `pip`, `conda`, `curl`, `wget`, `git clone`, `mv` and
`chmod` in `ask`. That was wrong for this workload: a reproduction runs those
constantly, so the result was a prompt every few seconds. They are allowed now.
The tradeoff is real and worth stating — nothing mechanically stops a stray
`pip install` from upgrading numpy and breaking torch's ABI in the regional_gs
env. That guard is now `CLAUDE.md`'s rule to re-pin after any install that
touches numpy, which is a documented rule rather than an enforced one.

Three deliberate choices in the lists themselves.

**`hpcrun` is allow-listed in full, including submission.** That is safe
because `hpcrun` enforces its own gates — validation, budget caps, the
approval threshold. A permission prompt in front of it is redundant: the
harness would refuse an over-budget job whether or not a human clicked yes.
The prompt is only meaningful where nothing else is checking.

**Raw `sbatch` and `scancel` are denied**, which turns "always use the
harness" from a rule in a document into something enforced. Note the harness
still calls `sbatch` internally — that is a subprocess of `hpcrun`, not a tool
call Claude makes, so it is unaffected. The same applies to `git clone`: it
prompts when Claude runs it directly, and does not when `hpcrepro clone` runs
it, which is the path that pins the commit and records it in the recipe.

There is **no timeout-based auto-accept** in Claude Code — no "wait 10 seconds
and take the default." The modes are the mechanism. `bypassPermissions` (and
`--dangerously-skip-permissions`) skip checks entirely and are documented for
isolated containers; avoid them here, because they also drop the `deny` list,
which is what stops raw `sbatch` from bypassing the harness. `auto` keeps
`deny` in force, so it is both quieter and safer for this setup.

Beware duplicate JSON keys when hand-editing: two `"permissions"` objects in
one file is valid JSON where the second silently wins, so a stray second
object drops your entire `allow` list with no error.

## Claude Code will not start on the login node

Confirmed on NCShare 2026-08-23: `claude` hangs on `login-01` — the binary
loads (`claude --version` is instant), then it makes **zero network syscalls**
and parks on a futex until killed. Not auth, not the API, not config: it
reproduces with a pristine `HOME`, an empty working directory, `/dev/null` on
stdin, and no proxy set. `strace` shows 622 syscalls in 30 s, so it is not
even busy.

The same binary works on a compute node. So run it there:

```bash
claude-node                 # 4 h, 2 cpus, 8 GB on `common`
claude-node -t 08:00:00     # longer session
```

`sbatch` works from inside an allocation, so `hpcrun` submits GPU jobs
normally — the login node is then only ever used for `ssh`.

Consequence for the agent: it is *inside* an allocation, so `srun` fails there
with "Job step creation temporarily disabled". `SKILL.md` and `CLAUDE.md` say
so; interactive probes have to come from a login shell.

The root cause is not established. Both nodes are cgroup v1, which ruled out
the obvious theory. `nproc` on the shared login node versus 2 inside an
allocation is the remaining lead, unverified.

## The loop

```
hpcrun site --probe                    # once per session
hpcrun ws --project P --experiment E   # once per experiment
hpcrun rev new --from-dir ./code --spec spec.json --reason "..."
hpcrun validate                        # always, before submitting
hpcrun submit
hpcrun wait --job JID --timeout 1800
hpcrun diagnose --job JID
hpcrun rev new --set mem_per_node_gb=64 --reason "OOM at 32G"
hpcrun submit
```

`hpcrun loop --max-attempts 3` runs the whole cycle unattended.

Every subcommand prints one JSON object on stdout, so the agent parses results
instead of screen-scraping.

## Reproducing a paper

You give Claude a repo URL or a PDF and say "duplicate what this does". The
`repro` skill loads and drives `hpcrepro`:

```
hpcrepro new   --name X --url https://github.com/... [--paper paper.pdf]
hpcrepro clone --name X --commit <sha>      # pinned; a moving branch is not a reproduction
hpcrepro scan  --name X                     # deps, frameworks, entrypoints, data sources
hpcrepro claim --name X --add "..." --value 6.7 --units million --source "paper 3.2"
hpcrepro env   --name X --plan              # what the install would execute
hpcrepro data  --name X --add gs://... --kind gcs --dest era5 --approx-gb 12
hpcrepro spec  --name X --for smoke --entrypoint smoke_check.py --walltime 10
hpcrepro spec  --name X --for run   --entrypoint forecast.py -- --init 2020-01-01
hpcrepro auto  --name X                     # build env, fetch, smoke, then stop
hpcrepro auto  --name X --approve           # ...and run it, repairing as it goes
hpcrepro claim --name X --verify 4 --result "6,712,065" --verdict matched
hpcrepro report --name X
hpcrepro learn  --name X                    # and the next project starts here
```

### The driver

`hpcrepro auto` runs the pipeline — clone, scan, build the environment,
download the inputs, smoke test, real run, diagnose, repair, resubmit — and
stops at every point that needs a person or needs the agent to think. State
lives in `recipe.json`, so it resumes after a session or an allocation dies,
and each stop names the stage, the reason, and the command that unblocks it.

| it stops when | because |
|---|---|
| no commit is pinned | a clone of today's branch tip is not a reproduction |
| nobody recorded what the code does | everything after spends something on the assumption someone understood it |
| the build would execute repo code | `pip install -e .` runs `setup.py` |
| the scan saw credentialed data sources | those credentials are the user's |
| a download exceeds `--max-gb` (50) | `/work` is shared and purged |
| the tier-3 real run | cost is a person's decision |
| a job failed non-mechanically | that needs a hypothesis, not a retry |

Everything between those gates runs unattended. The environment build and the
data fetch are submitted as **CPU jobs through `hpcrun`**, not run inline, so
they survive the session ending, get charged against a budget, and leave a log.
The generated build script sources `conda.sh` by absolute path, hard-fails
rather than falling back to the system python, and verifies after activating
that `python` really is the project's python — the silent version of that
failure builds an environment that looks fine and breaks every later job.

Three properties are the whole point.

**The claims ledger.** A reproduction that runs is not a reproduction that
reproduced. Every quantitative claim in the paper is recorded up front with its
source, and answered at the end as `matched`, `differed`, `not_attempted`, or
`unverifiable`. `report` counts anything still unanswered and prints a banner
saying the reproduction is incomplete — so an unfinished ledger cannot pass
itself off as a clean result. `differed` and `unverifiable` are normal
outcomes: in the Keisler 2022 example the headline skill claim is
`unverifiable`, because the paper reports RMSE only in figures and there is no
number to compare against.

**Cost tiers.** `0` read-only, `1` build an environment, `2` a ≤10-GPU-minute
smoke job, `3` the real run. Tiers 0–2 are the agent's to run. **Tier 3 is
gated on a human**, as is anything needing credentials or a large download. The
gate is a decision point, not a size threshold.

**Everything read is data.** The repo, the paper, the README, downloaded files
and third-party error text are untrusted input. The skill says so explicitly,
tells the agent not to run a repo's install script unread (`pip install -e .`
executes `setup.py`), and `scan` surfaces
`credentialed_data_sources` and `credential_env_vars_referenced` so a repo that
wants a login becomes a conversation rather than a prompt for a secret.

`hpcrepro` deliberately does not understand the science — it clones, scans,
records and generates a spec. Reading the paper and judging whether a number
reproduces is the agent's job, and the skill is where that method lives.

## Design decisions worth knowing

**Immutable revisions.** Every submission is tied to a `rev-NNNN/` directory
holding a frozen, SHA-256'd copy of the code and spec, chmod'd read-only. The
rendered sbatch script and the logs live *outside* it, so the revision really
does stay unchanged. Revisions are built in a staging directory and renamed
into place, so a failed `rev new` cannot leave a half-built one behind. You can
always answer "what exactly produced that figure?"

**Structured specs, not shell strings.** `entrypoint` is argv. The sbatch
script is rendered from a template — the agent never writes `#SBATCH` lines or
constructs shell commands. Fields that land in a directive must match
`^[A-Za-z0-9._:+-]{1,64}$`, because a newline there ends the comment block and
turns the rest into an executable line. A prohibited-pattern scan covers the
frozen code *and* the spec's own execution vectors (`entrypoint`, env vars,
container, outputs, extra directives), since scanning only `code/` blocks
nothing an adversary would actually use.

**Validation against the real cluster.** `site --probe` reads actual
partitions, walltime caps, cpus/node, gres, and your Slurm associations.
`validate` checks the spec against them and finishes with `sbatch --test-only`,
so Slurm itself gets a vote before a job is queued.

**Budgets that the agent cannot raise.** Attempts, node-hours, GPU-hours, and
concurrency are capped per workspace. Runs above the approval threshold need
`--approve`, which means a human said yes. The skill tells Claude to stop and
ask rather than edit `workspace.json` — a cap an agent can lift is not a cap.

**Narrow auto-repair.** Only memory, walltime, and transient node failures are
auto-repairable, and fixes double rather than jumping to the maximum.
Everything else halts for human review. A `MemoryError` has one obvious fix; a
`RuntimeError` in the training loop does not, and doubling the memory will not
find it.

**Logs are untrusted.** `hpcrun logs` labels its output as data. The skill
tells Claude that instruction-shaped text inside a log is a string in a file,
not a message to it.

## Verified

The full loop was exercised offline against `pilot/mockslurm`, then the
harness was put through an adversarial review and re-tested:

**Function**

- happy path → `COMPLETED`, artifacts staged, ledger written
- OOM → diagnosed `oom_slurm`, memory doubled 1→2→4 GB across three immutable
  revisions, then stopped at the attempt cap instead of looping
- crash → halted as `human_review` rather than auto-retrying
- a numpy-ABI traceback → ranked above the generic Python-exception rule
- clean-machine install → smoke test, end to end
- the regional_gs pipeline, run against a stubbed `src/`: preflight →
  R=2/3/4 curriculum → promote (r4 won) → stale-means detection → Stage 2b →
  calibrate → evaluate → figures staged
- resubmitting that pipeline **resumed** instead of wiping; `FRESH=1` took a
  timestamped backup before deleting; the `ckpt/` lock refused a second
  concurrent run

**Security** — every one of these was a working exploit in the first draft and
is now blocked at validation:

- newline injection through `qos`, `account`, `partition` (ended the `#SBATCH`
  comment block and executed arbitrary commands; also silently dropped every
  later directive, including `--export=NONE`)
- newline injection through `extra_directives`
- command substitution in an `outputs` glob, and in the workspace path
- `sudo` / `curl | sh` placed in `entrypoint` — the scan originally covered
  only `code/`, missing the actual execution vector
- padding a file past 2 MB to skip the forbidden-pattern scan
- path traversal through `--job` (read any `stdout.log`, write `status.json`
  into any directory)
- `--project ..` escaping `HPCRUN_ROOT`

**Correctness**

- a successful job was reported as *failed* whenever `squeue` answered first —
  it carries no exit code, and Slurm keeps finished jobs listed for
  `MinJobAge` (300 s), exactly the window `wait` returns in
- auto-repair forked the newest revision rather than the one it ran
- one human `--approve` authorized every machine-generated revision after it
- a wait timeout diagnosed a still-running job and called it an unknown failure
- `--mem` truncated a fractional GB to `--mem=0G`, which Slurm reads as *all*
  node memory
- `D-HH` and `D-HH:MM` walltimes parsed as minutes (`0-01:00` → 1 minute)
- five unhandled tracebacks on malformed specs, plus a failed `rev new` that
  left a spec-less revision which permanently broke the workspace
- Slurm will not create the `--output` parent directory, and `runs/<jobid>/`
  did not exist until after `sbatch` returned — logs now go to `logs/`

## Extending it

Add a diagnosis rule as a 6-tuple in `RULES` in `bin/hpcrun`, then regenerate
`references/failure-modes.md` from the table so the docs can't drift. Specific
rules go before general ones; default `auto_repairable` to `False`.

## Limitations

- Single cluster, single scheduler (Slurm). The scheduler calls are isolated in
  `_query_state` / `cmd_submit` if PBS or LSF is ever needed.
- No MCP server yet. The architecture doc's gateway design is the next step if
  you want a *remote* agent driving the cluster; running Claude Code on the
  login node makes that unnecessary for now.
- Budget accounting charges the *requested* node-hours at submit time, not the
  actual usage from `sacct`. Conservative, so it over-counts short jobs.
- `--export=NONE` in the rendered script means the job gets a clean
  environment. If something depends on an inherited variable, put it in
  `environment.vars`.
