# `hpcrepro` command reference

Version 0.4.0. Stdlib Python 3.6+, no dependencies. **Every subcommand prints
one JSON object on stdout.** Errors go to stderr and exit non-zero.

`hpcrepro` never calls `sbatch` itself. It clones, scans, records, generates
specs, and submits **through `hpcrun`** — including the environment build and
the data fetch, which run as ordinary CPU jobs so they leave a log and are
charged against a budget.

## Where things live

Rooted at `$HPCREPRO_ROOT`, default `/work/$USER/agent-projects`:

```
<name>/
    recipe.json         source, understanding, environment, plan, claims, stages
    repo/               pinned clone -- never edited in place
    env/                this reproduction's own environment
    data/               inputs fetched for it
    results/            what came out
    build/              generated build_env.sh, fetch_data.sh and their specs
    notes.md            free-text findings, appended with `note --append`
    spec-smoke.json     written by `hpcrepro spec --for smoke`
    spec-run.json       written by `hpcrepro spec --for run`
    env-manifest.txt    resolved package versions, written by the build job
    data-manifest.txt   what was downloaded, written by the fetch job
    report.md           written by `hpcrepro report`
```

`recipe.json` carries a `stages` map — `clone`, `scan`, `review`, `env`,
`fetch`, `smoke`, `run` — each with a state, the job id that ran it, and its
hpcrun workspace. That is what makes `auto` resumable.

Project names must match `[A-Za-z0-9._-]{1,64}` and cannot be `.` or `..`.
`--name` may be omitted if `HPCREPRO_PROJECT` is set.

## Cost tiers

| tier | name | what it covers | gate |
|---|---|---|---|
| 0 | read-only | clone, read, scan. No allocation. | auto |
| 1 | environment | build an env, fetch small inputs. CPU + disk. | auto |
| 2 | smoke | one tiny GPU job, ≤10 GPU-minutes. | auto |
| 3 | real run | the actual reproduction. | **ask a human** |

## Commands

### `new`

```bash
hpcrepro new --name NAME [--url GIT_URL] [--paper /path/to.pdf]
```

Creates the directory tree and `recipe.json`. Idempotent — re-running on an
existing project returns `{"existed": true}` and changes nothing. A `--paper`
file is SHA-256 hashed and the digest stored, so the record says which version
of the paper was read.

### `clone`

```bash
hpcrepro clone --name NAME [--url URL] [--commit SHA] [--force]
```

Clones into `repo/` and records the resolved HEAD in `source.commit`.
**Always pass `--commit`** unless you are deliberately taking the tip — a
reproduction against a moving branch is not a reproduction.

Refuses URLs that are not plain `https://` or `git@` remotes. Will not
overwrite an existing clone without `--force`. 15-minute timeout.

### `scan`

```bash
hpcrepro scan --name NAME
```

A deterministic string scan of the clone. Walks up to 4000 files, skipping
`.git`, `__pycache__`, virtualenvs, `node_modules`, build dirs. Reads the
first 200 KB of each text file and skips files over 8 MB.

Reports under `scan.findings`:

- `dep_files` — `pyproject.toml`, `requirements.txt`, `environment.yml`,
  `setup.py`, `poetry.lock`, `uv.lock`, `Pipfile`, `conda.yaml`, …
- `frameworks` — jax / pytorch / tensorflow / sklearn / xarray
- `entrypoints` — `.py` files with a `__main__` guard or an argparse/click/
  typer/absl parser, each with up to 25 extracted `--flags`, sorted so
  argparse-with-main comes first, capped at 25 files
- `data_hints` — keyed by source (`google-arco`, `s3`, `gcs`, `huggingface`,
  `cmems`, `cds`, `ecmwf-opendata`, `earthdata`, `zenodo`, `generic-url`),
  each with `needs_credentials`, example strings, and which files they came from
- `credential_env` — credential-shaped environment variable names referenced
- `readme`, `docs`, `notebooks`, `scripts`, `makefile_targets`, `dockerfiles`
- counts: `total_files`, `python_files`, `tests`, `repo_mb`

And a top-level `flags` block worth reading every time:

```json
"flags": {
  "credentialed_data_sources": ["cds"],
  "credential_env_vars_referenced": ["CDSAPI", "API_KEY"],
  "no_dependency_file": false,
  "no_entrypoint_found": false
}
```

`credentialed_data_sources` non-empty means **stop and ask** — Paul
authenticates, you do not.

The scan reports which strings are present, not what the code does. Read the
README and the entrypoint yourself.

### `note`

```bash
hpcrepro note --name NAME --set key.path=VALUE [--set ...] [--append TEXT]
```

`--set` writes a dotted path into `recipe.json`. The value is JSON-decoded if
possible, otherwise kept as a string — so quote strings for the shell *and*
for JSON: `--set understanding.framework='"jax"'`, or just
`--set understanding.data.needs_credentials=false`.

Fields the skill expects you to fill:

| path | |
|---|---|
| `understanding.what_it_does` | one or two sentences |
| `understanding.entrypoints` | the ones that matter, after reading |
| `understanding.framework` | |
| `understanding.data.source` | exact dataset + access path |
| `understanding.data.needs_credentials` | |
| `understanding.data.approx_size_gb` | |
| `understanding.weights.needed` / `.source` | are pretrained weights required, and from where |
| `understanding.hardware_claimed` | what the paper says it ran on |
| `environment.python` / `.installer` / `.packages` | |
| `environment.gotchas` | **the highest-value field** — every README warning and every trap found the hard way |
| `environment.conda_sh` | read by `hpcrepro spec` |

`--append TEXT` appends a timestamped section to `notes.md`. Use it as a
running log so a session that dies mid-way leaves a trail.

### `plan`

```bash
hpcrepro plan --name NAME --add "STEP" --tier N [--cost "10 GPU-minutes"]
hpcrepro plan --name NAME --list
```

Records a step with its tier. Tier ≥ 3 gets `gate: "ask"`. `--list` prints the
plan and the tier table.

### `claim`

```bash
hpcrepro claim --name NAME --add "CLAIM" [--value V] [--units U] [--source "Table 2"]
hpcrepro claim --name NAME --verify ID --result R --verdict VERDICT [--note N] [--evidence E]
hpcrepro claim --name NAME --list
```

`--verdict` must be one of `matched | differed | not_attempted | unverifiable`.
New claims start `open`; `report` counts anything still `open` separately, so
an unfinished ledger cannot masquerade as a clean result.

Record the claims **before** building anything. Include the cheap structural
ones — parameter count, model file size, wall-clock per step — they are often
the only claims checkable exactly, and a parameter-count mismatch tells you
immediately that you are not running the same model.

### `env`

```bash
hpcrepro env --name NAME --plan               # print commands, change nothing
hpcrepro env --name NAME --write              # write build/build_env.sh only
hpcrepro env --name NAME --build [--wait]     # submit it as a CPU job
      [--partition common] [--cpus 8] [--mem 32] [--walltime 60]
```

Picks the installer from the scan: a conda yaml → `conda env create`;
`uv.lock`/`pyproject.toml` → `conda create` + `uv sync`; otherwise
`pip install -r` and, if the repo is a package, `pip install -e .`. Override
with `environment.installer` (`conda` | `uv` | `pip`), `environment.python`,
and `environment.uv_extra` (for `uv sync --extra ...`).

`--plan` reports `executes_repo_code` — the files whose contents run during the
build. **`--build` refuses until `environment.build_files_reviewed` is true**,
and refuses without `environment.conda_sh`.

The generated script:

- sources `conda.sh` by absolute path and exits 78 if it is missing —
  `command -v conda` is not a valid test in a batch job
- reuses an existing `<project>/env` instead of rebuilding
- **verifies after activation that `python` really is the env's python**, and
  exits 78 if not; a silent fall-through to the system python builds an
  environment that looks fine and breaks every later job
- points `TMPDIR`/`PIP_TMPDIR`/`PIP_CACHE_DIR` into `/work`
- writes `env-manifest.txt` (`pip freeze` + `conda list`)

It runs as a job so it survives your session ending and leaves a readable log.

### `data` and `fetch`

```bash
hpcrepro data  --name NAME --add URL --kind KIND --dest REL --approx-gb N [--note ...]
hpcrepro data  --name NAME --list
hpcrepro fetch --name NAME --plan
hpcrepro fetch --name NAME [--wait] [--approve] [--max-gb 50]
```

Kinds: `gcs`, `s3`, `http`, `hf`, `zenodo`. The credentialed kinds — `cds`,
`cmems`, `earthdata` — are **refused**: those credentials belong to the user.
Ask them to authenticate and fetch, then declare the local result.

Guards, all of which have a reason:

- `--approx-gb` is required. An unsized download is the one that fills `/work`.
- Over `--max-gb` in total needs `--approve` — a person's decision.
- Refuses if the total exceeds 80% of the free space at the project.
- `--dest` must be a simple relative path; `..` and shell metacharacters in the
  URL or destination are rejected.
- The generated script checks its tools exist *before* downloading a byte
  (`gcloud` or `gsutil` for `gcs` — either is enough).

Writes `data-manifest.txt` so a later run can tell whether the inputs changed.

### `auto`

```bash
hpcrepro auto --name NAME [--approve] [--retry] [--max-steps 10]
              [--max-gb 50] [--max-attempts 3] [--timeout 7200]
```

Walks clone → scan → review → env → fetch → smoke → run, one stage per
iteration, and stops at the first gate. State lives in `recipe.json` under
`stages`, so it is resumable across sessions and allocations.

Every stop returns `blocked_at`, `why`, and `what_to_do` — the exact command
that unblocks it. It stops for: an unpinned commit, an unrecorded
understanding of the code, unreviewed build files, undeclared credentialed data,
an oversized download, the tier-3 run without `--approve`, and any stage that
failed (which needs `--retry` plus an actual fix).

`--approve` authorizes the tier-3 run only. It does not lift the download cap,
the credential refusal, or the build-review gate.

Job stages run through `hpcrun loop`, so bounded auto-repair — more memory,
more walltime, transient node failure — happens without asking, and anything
else halts as `human_review`.

### `spec`

```bash
hpcrepro spec --name NAME [--entrypoint PATH] [--args ...] \
              [--partition interactive-gpu] [--gpus 1] [--gpu-type h200] \
              [--cpus 8] [--mem 64] [--walltime 15] [--outputs GLOB ...]
```

Writes `spec.json` in the hpcrun jobspec schema. `--entrypoint` is relative to
`repo/`; if omitted it takes the first scanned entrypoint, which is a guess.
`workdir` is set to `repo/` (project mode) because reproductions almost always
need the clone's own package data and relative paths. `conda_env` points at
`<project>/env`; `conda_sh` comes from `environment.conda_sh` in the recipe and
must be set for a batch job to activate conda at all.

Refuses an entrypoint that is absolute, contains `..`, has shell metacharacters,
or does not exist in the clone.

The result carries two lists worth reading:

- `next` — the exact hand-off commands, including
  `hpcrun ws ... --allow-write <project>/repo`. The clone sits outside the
  hpcrun workspace, so without that flag `validate` rejects the job with
  "workdir is outside the allowed write roots".
- `before_you_submit` — what the generator can tell is missing: no
  `conda_sh` recorded, no environment built yet, no `outputs` declared, plus
  every gotcha already in the recipe, restated so it is in front of you at the
  moment it matters.

**This is a starting point from a mechanical scan.** Check the entrypoint,
arguments, memory and walltime against what the code actually does before
submitting. Then:

```bash
hpcrun ws --project NAME --experiment smoke --allow-write <project>/repo
hpcrun rev new --from-dir <project>/repo --spec <project>/spec.json --reason "..."
hpcrun validate
```

### `learn`, `recall`, `forget`, `promote`

```bash
hpcrepro learn  --name NAME [--dry-run]
hpcrepro recall [--framework F] [--query Q] [--kind K] [--all] [--limit N] [--stale-days D]
hpcrepro forget --id ID --reason "why it is wrong"
hpcrepro promote --file PATH --name NAME [--description D] [--project P] [--force]
```

The knowledge base lives at `$ASCEND_HOME/knowledge` (default `~/.ascend`),
**not** on `/work` — that is purged after 75 days.

`learn` harvests four kinds from a finished project: `gotcha`, `env_recipe`,
`failure_fix`, `reproduction`. It **refuses on a project where no stage
completed** — nothing there was demonstrated.

Confidence rules, which are the whole design:

| rule | why |
|---|---|
| a lesson is `hypothesis` until a job succeeded with it in force | otherwise the store fills with untested guesses |
| a repair is a fix only if the *next* attempt succeeded | otherwise it records "tried, did not resolve" |
| re-running `learn` on the same project changes nothing | confidence must come from independent re-observation |
| same trigger, different lesson → flagged as a contradiction | never silently merged or averaged |
| unconfirmed for `--stale-days` (180) → marked `STALE` | clusters change, packages move |

`recall` ranks verified first, then most-confirmed. It hides retired lessons
unless `--all`. **Nothing is ever auto-applied** — it surfaces, you check, you
decide.

`forget` requires `--reason` and keeps the row, marked retired, so the same
wrong lesson is not learned again from scratch.

`promote` copies a helper script into `$ASCEND_HOME/tools` with a SHA-256 and
a note of where it came from. Scripts only — it refuses files over 2 MB.

Every `learn` and `forget` regenerates `knowledge/learned.md` and copies it to
`~/.claude/skills/repro/references/learned.md`, which is how the accumulated
experience reaches the next session's context. That file is generated — never
edit it by hand.

### `status`, `list`, `report`

```bash
hpcrepro status --name NAME     # dump recipe.json
hpcrepro list                   # all projects: status, tier reached, open claims
hpcrepro report --name NAME     # write report.md
```

`report` renders the claims table, a "where it differed" section, the gotchas,
and `notes.md`. With no claims it says so explicitly: *a reproduction with no
claims ledger has not been verified against anything — it has only been run.*

The report is only as honest as the verdicts entered. Read it before sending it.
