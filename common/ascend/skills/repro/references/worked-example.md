# Worked example — Keisler 2022, from a URL to a claims ledger

This is the tier-0/tier-1 walkthrough that was actually run while building the
`repro` skill, against
[`rkeisler/keisler-2022`](https://github.com/rkeisler/keisler-2022) and
[arXiv:2202.07575](https://arxiv.org/abs/2202.07575) ("Forecasting Global
Weather with Graph Neural Networks"). It is here because every interesting
decision in a reproduction shows up in it.

## Tier 0 — clone, pin, scan, read

```bash
hpcrepro new   --name keisler2022 --url https://github.com/rkeisler/keisler-2022
hpcrepro clone --name keisler2022        # pinned to d46ba88e49ed5f90f...
hpcrepro scan  --name keisler2022
```

The scan reported: 38 files, 16 python, 38.2 MB; frameworks `jax`, `xarray`;
dep files `pyproject.toml`, `uv.lock`; four entrypoints, the primary being
`forecast.py` with flags `--init --input --out --steps --timing`, plus
`scripts/01_evaluation.py`, `02_sensitivity.py`, `03_hurricane.py`; a data hint
`gcs` pointing at `gs://gcp-public-data-arco-era5/...`.

The two flags that mattered most were the empty ones:

```json
"credentialed_data_sources": [],
"credential_env_vars_referenced": []
```

Public data, no logins. That is what made this a good first target — nothing to
stop and ask about, so the whole path to a smoke test is unattended-safe.

**Then reading the code changed the plan**, which is the point of tier 0. The
scan saw a 38 MB repo; reading `src/keisler_2022/data/` showed *why* — the
trained weights are **shipped in the repository** as a 27 MB pickle
(`good_era5_forecast_batch001_feats0256_blocks009_...pkl`), loaded by
`resolve_artifact()` from the package path. There is no weights download step
at all. A mechanical tool cannot tell you that; it also cannot tell you that
`ModelConfig` says `n_features=256`, `n_processor_blocks=9`,
`n_channels_out=78`, `GraphConfig` says `reso_era5_deg=1.0, h3_level=2`, and
the levels are `[50,100,150,200,250,300,400,500,600,700,850,925,1000]` — all of
which are checkable against the paper before a single GPU-second is spent.

The README also supplied the single most valuable line in the whole
reproduction, and it went straight into the gotchas:

> If JAX falls back to CPU, make sure `LD_LIBRARY_PATH` is **not set**.

```bash
hpcrepro note --name keisler2022 \
  --set environment.gotchas='["LD_LIBRARY_PATH must be UNSET or JAX silently falls back to CPU","uv sync --extra cuda12 for GPU","login node has no GPU so jax.devices() showing CPU there is expected"]'
```

## Extracting claims from the paper

Eleven went into the ledger. They fall into three groups, and the groups
behave completely differently:

**Structural — exactly checkable, and free.** Parameter count (6.7 M), weights
size in float32 (27 MB), output channels (78 = 6 vars × 13 levels), mesh nodes
vs lat/lon grid (5882 vs 65160). These need no GPU. A mismatch here means you
are not running the same model, and you find that out in tier 0 instead of
after a tier-3 run.

**Performance — checkable, but not comparable as stated.** 0.04 s per 6-hour
step and 0.8 s for a 5-day forecast, *on an A100*. NCShare has H200s. A number
that differs is expected and is not a reproduction failure — it is a hardware
difference, and the note field has to say so or the verdict is misleading.

**Skill — the actual scientific claims, and mostly unverifiable.** "Beats GFS
v15.2 and comparable to ECMWF in the 2020 extratropics" is the paper's headline
result. **The RMSE values appear only in figures, not in tables.** There is no
number to compare against at the precision needed. You can recompute your own
RMSE curves with `scripts/01_evaluation.py` and eyeball the shape, but you
cannot honestly write `matched`.

```
| 10 | Beats GFS v15.2 (2020), comparable to ECMWF | qualitative | not computed | **unverifiable** |
```

That verdict is the correct answer. Recording it as `matched` because curves
"look similar", or leaving it `open` while writing a summary that says the
reproduction succeeded, is the failure mode this whole tool exists to prevent.

## The plan

```
[tier 0 read-only   gate=auto] clone + scan + read README                    free
[tier 1 environment gate=auto] build conda env + uv sync --extra cuda12      ~10 min CPU, ~5 GB disk
[tier 2 smoke       gate=auto] GPU smoke: print jax.devices() in a job       ~2 GPU-minutes
[tier 2 smoke       gate=auto] 10-day forecast from 2020-01-01, ERA5 init    ~5 GPU-minutes
[tier 3 real run    gate=ask ] scripts/01_evaluation.py RMSE curves + q850   ~15 GPU-minutes + ARCO download
```

Note that even the tier-3 step here is small — fifteen GPU-minutes. It is
still gated, because the ARCO-ERA5 download attached to it is not small and
because "the real run" is a decision, not a size threshold.

Note also what is *absent*: retraining. The paper reports 5.5 days on one A100
(~$370 of GCP). Reproducing training is a different project with a different
budget conversation. The reproduction target here is **inference from the
released weights**, and the report has to say that plainly, because "we
reproduced Keisler 2022" and "we ran Keisler's released model" are different
claims.

## Generating the job spec

```bash
hpcrepro spec --name keisler2022 --entrypoint forecast.py \
              --partition interactive-gpu --gpus 1 --walltime 10 \
              --outputs 'results/*.nc' \
              -- --init 2020-01-01 --steps 4
```

Everything after `--` goes to the entrypoint verbatim (`--arg=--steps
--arg=4` does the same thing without ordering rules). The generated spec sets
`workdir` to the clone — project mode — because `resolve_artifact()` loads the
weights from a path relative to the installed package. In a sandbox copy that
lookup changes, which is exactly the kind of silent difference that produces a
run that "works" and is not the paper's model.

Two things the generator cannot know and you must fix by hand before
submitting:

- `environment.conda_sh` is `null` unless you recorded it. Without it a batch
  job cannot activate conda at all — `hpcrun` will hard-fail with exit 78
  rather than silently using the system python, but you still have to set it.
- `LD_LIBRARY_PATH` — the README's warning. The spec's `environment.vars` is
  where that gets handled, and the smoke job must **print `jax.devices()`** so
  you can see whether it took.

Then it is an ordinary `hpcrun` job. Note `--allow-write`: the clone lives
outside the hpcrun workspace, and project mode means the job writes there.

```bash
hpcrun ws --project keisler2022 --experiment smoke --allow-write <project>/repo
hpcrun rev new --from-dir <project>/repo --spec <project>/spec.json --reason "tier-2 smoke"
hpcrun validate && hpcrun submit
```

`validate` will warn that project mode makes provenance advisory rather than
reproducible-by-construction. That is correct and is the reason the pinned
commit is in the recipe.

## What the report looked like

```
1 matched, 1 differed, 1 not attempted, 1 unverifiable, 7 open.

> **7 claim(s) were never answered.** This reproduction is incomplete:
> nothing below should be read as confirming or refuting those claims.
```

That banner is generated, not written by hand, and it is the honest summary of
a reproduction stopped at tier 1. Lead with it.
