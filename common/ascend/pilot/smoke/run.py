#!/usr/bin/env python3
"""
hpcrun smoke test -- proves submit -> poll -> log -> diagnose -> results works
end to end on NCShare before any real science is attached to the harness.

Modes (env FAIL_MODE):
  none      succeed, write results/metrics.json           (happy path)
  memory    allocate until the cgroup OOM-kills us        (auto-repairable)
  walltime  sleep past the requested walltime             (auto-repairable)
  crash     raise a Python exception                      (human review)
  gpu       assert a CUDA device is visible               (checks the alloc)
"""
import json
import os
import platform
import socket
import sys
import time

MODE = os.environ.get("FAIL_MODE", "none").strip().lower()

print("[smoke] host=%s python=%s" % (socket.gethostname(), platform.python_version()))
print("[smoke] FAIL_MODE=%s" % MODE)
for k in ("SLURM_JOB_ID", "SLURM_JOB_PARTITION", "SLURM_NNODES",
          "SLURM_NTASKS", "SLURM_CPUS_PER_TASK", "SLURM_MEM_PER_NODE",
          "CUDA_VISIBLE_DEVICES"):
    print("[smoke] %s=%s" % (k, os.environ.get(k, "<unset>")))

gpu = {"torch_importable": False, "cuda_available": False, "devices": []}
try:
    import torch  # noqa: F401
    gpu["torch_importable"] = True
    gpu["torch_version"] = torch.__version__
    gpu["cuda_available"] = bool(torch.cuda.is_available())
    if gpu["cuda_available"]:
        gpu["devices"] = [torch.cuda.get_device_name(i)
                          for i in range(torch.cuda.device_count())]
    print("[smoke] torch %s cuda=%s devices=%s"
          % (gpu.get("torch_version"), gpu["cuda_available"], gpu["devices"]))
except ImportError as exc:
    print("[smoke] torch not importable: %s" % exc)

if MODE == "gpu":
    assert gpu["cuda_available"], (
        "torch.cuda.is_available() is False -- either this ran on a login "
        "node or the allocation had no --gres=gpu:h200:N")

if MODE == "memory":
    print("[smoke] allocating until the memory cgroup kills us...")
    blocks = []
    while True:
        blocks.append(bytearray(256 * 1024 * 1024))
        print("[smoke] allocated %d MiB" % (len(blocks) * 256)); sys.stdout.flush()
        time.sleep(0.2)

if MODE == "walltime":
    print("[smoke] sleeping past the walltime limit on purpose...")
    for i in range(10000):
        print("[smoke] tick %d" % i); sys.stdout.flush()
        time.sleep(20)

if MODE == "crash":
    raise RuntimeError("deliberate smoke-test failure to exercise diagnosis")

result = {
    "ok": True,
    "hostname": socket.gethostname(),
    "python": platform.python_version(),
    "slurm_job_id": os.environ.get("SLURM_JOB_ID"),
    "partition": os.environ.get("SLURM_JOB_PARTITION"),
    "gpu": gpu,
    "finished_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
}
with open("metrics.json", "w") as fh:
    json.dump(result, fh, indent=2)
print("[smoke] wrote metrics.json")
print("[smoke] SUCCESS")
