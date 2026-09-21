# Failure modes and what they mean

Generated from the `RULES` table in `hpcrun` (v0.5.0). `hpcrun diagnose`
matches these against a job's stdout+stderr and ranks the hits, most
specific first.

**Auto-repairable** means the loop may apply a bounded fix on its own —
only memory, walltime, and transient node failures qualify. Everything
else halts for human judgement, deliberately: doubling the memory does
not fix a bug in the training loop.

| rule | category | auto-repair | what it means / what to do |
|---|---|---|---|
| `oom_slurm` | memory | **yes** — mem_per_node_gb ×2 | The job exhausted its memory allocation -- either killed by the Slurm cgroup, or the allocator failed inside the process. Both mean the --mem request was too small for the work. |
| `oom_cuda` | gpu_memory | no | The GPU ran out of device memory. Reduce batch size / model shard, enable gradient checkpointing, or request a larger-memory GPU. |
| `timeout` | walltime | **yes** — walltime_minutes ×2 | The job hit its walltime limit before finishing. |
| `module_not_found` | environment | no | A Python dependency is missing from the active environment. Fix the conda env / module list / container image rather than pip-installing at runtime. |
| `cmd_not_found` | environment | no | An executable was not on PATH. A required module was probably not loaded, or the conda env was not activated. |
| `module_load_fail` | environment | no | A requested environment module could not be loaded. NOTE: NCShare has no Lmod/environment-modules system at all -- if a spec lists environment.modules, that is the bug. Use environment.conda_env (plus conda_sh) or a container instead. |
| `bad_partition` | config | no | The requested partition is wrong or cannot satisfy the requested resources. Re-probe the site and pick a valid partition. |
| `bad_account` | config | no | The Slurm account/QOS is not one of your associations. |
| `quota` | storage | no | The filesystem is full or the project quota is exhausted. This needs human cleanup -- do not auto-retry. |
| `permission` | permissions | no | A path was not writable/readable by this user. Check that all paths are inside the project workspace. |
| `input_missing` | inputs | no | An input file the code expected was not present in the job workdir. It probably was not staged into the revision's code/ directory. |
| `segfault` | code | no | The program crashed with a segmentation fault -- a genuine bug or a bad input, not a resource problem. |
| `node_fail` | transient | **yes** — resubmit as-is | A compute node failed. This is infrastructure, not your code -- resubmitting the identical revision is appropriate. |
| `preempted` | transient | **yes** — resubmit as-is | The job was preempted by a higher-priority workload. Resubmit unchanged, ideally with checkpointing enabled. |
| `mpi_abort` | mpi | no | An MPI rank aborted. Check rank/task geometry against the node layout and look for the first failing rank's message. |
| `nan_divergence` | numerics | no | The computation went numerically unstable. Usually a timestep, learning rate, or initial-condition problem. |
| `python_exception` | code | no | The program raised an unhandled Python exception. Read the traceback and the exception message, fix the code in a new revision, and resubmit. This is not a resource problem -- do not just add memory or walltime. |
| `numpy_abi` | environment | no | NumPy 2.x got pulled in and broke torch's ABI. A known trap with ocean-data stacks: copernicusmarine/zarr/cdsapi declare numpy>=2. Fix by re-pinning with the env’s own pip: <env>/bin/pip install 'numpy<2' (target 1.26.4). Never auto-retry without re-pinning. |
| `cpu_baseline` | environment | no | NumPy built for a newer CPU baseline than the login node provides (the X86_V2 crash). Same root cause as the numpy>=2 upgrade: re-pin numpy<2, or run on a compute node instead of the login node. |
| `dist_info_corrupt` | environment | no | Package metadata is corrupt from repeated force-reinstalls. Scan for empty Version fields; if more than one distribution is corrupt, REBUILD the env from scratch rather than patching -- it is faster. Do not attempt automated repair. |
| `bad_shebang` | environment | no | Console-script shebangs point at an old env path (the env2->env rename). Fix with: sed -i '1s|.../env2/bin|.../env/bin|' env/bin/* |
| `no_gpu` | gpu | no | No usable GPU. On NCShare the login node has no GPU at all -- this work must run under srun/sbatch on interactive-gpu or gpu-hp. If it already is, the allocation did not include --gres=gpu:h200:N. |
| `nested_srun` | config | no | Nested srun -- a step was launched inside an allocation that already holds one. Launch chunk scripts from a LOGIN node, or run torchrun directly inside an allocation you already hold. Never both. |
| `nccl_fail` | distributed | no | A DDP/NCCL collective failed or timed out -- usually one rank died first (read the earliest rank's traceback, not the watchdog), or the granted GPU count does not match --nproc. |
| `ckpt_shape_mismatch` | checkpoint | no | A checkpoint does not fit the current architecture. LATENT / PROC_STEPS / MESH_REFINE changed in config.py, so the old weights cannot load. Retrain the stage fresh (--fresh) rather than deleting ckpt/ wholesale. |
| `root_disk_full` | storage | no | The ~31 GB root partition overflowed -- almost always pip's temp/cache during a CUDA wheel install. Redirect TMPDIR/PIP_TMPDIR/PIP_CACHE_DIR to /work/$USER/tmp before retrying. Needs a human decision. |
| `conda_activate_fail` | environment | no | conda activation failed. conda is a shell function, so a batch job must source conda.sh by absolute path first -- set environment.conda_sh (on NCShare: /hpc/home/$USER/miniforge3/etc/profile.d/conda.sh). Check the '[hpcrun] python' line in the log to see which interpreter actually ran. |
| `wrong_interpreter` | environment | no | The job ran under the system python, not the project env -- the activation did not take. Frequently caused by ~/.bashrc auto-activating a different env AFTER the script's own 'conda activate'. Do not trust any result from this run. |
| `torchrun_port` | distributed | no | torchrun's rendezvous port is taken -- usually two jobs sharing a node, or a chunk script running at the same time as a batch job against the same checkpoints. Check for a concurrent run before resubmitting. |
| `gres_unavailable` | config | no | The scheduler cannot satisfy the GPU request. On NCShare the device type is required: --gres=gpu:h200:N. Set spec.gpu_type='h200', and check the count against what the partition advertises. |
| `preflight_missing_input` | inputs | no | A preflight assertion failed: a prepared input the config enables is not on disk. Build it (python -m src.data_ssh / data_flux / data_mld) before resubmitting -- more walltime will not help. |
| `stale_means_cache` | checkpoint | no | The Stage-1 rollout-mean cache does not match the current Stage-1 weights. Regenerate with 'python -m src.gen_rollout_means' and retrain Stage 2b from scratch -- a stage2b checkpoint trained on old means must not be resumed. |
| `cmems_auth` | credentials | no | A data-portal login expired or a licence was not accepted (CMEMS / CDS). This needs a human to re-authenticate -- never put credentials in a job script or prompt. |

## Slurm states

Treated as still-running: `PENDING`, `RUNNING`, `CONFIGURING`, `COMPLETING`, `REQUEUED`, `RESIZING`, `SUSPENDED`.

Success requires state `COMPLETED` **and** an exit code starting `0:`.
A job can reach `COMPLETED` with a nonzero payload exit in some
configurations, so never infer success from the state alone.

## Adding a rule

Append a 6-tuple to `RULES` in `hpcrun`:

```python
("rule_id", r"(?i)regex", "category",
 "What it means and what the human should do about it.",
 {"scale": {"mem_per_node_gb": 2.0}},  # or None, or {"resubmit_unchanged": True}
 True)  # auto_repairable
```

Put specific rules **before** general ones — the first match ranks first
(`python_exception` is explicitly demoted last as a fallback). Default
`auto_repairable` to `False` unless the fix is genuinely mechanical and
the failure has exactly one plausible cause.
