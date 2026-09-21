#!/usr/bin/env python3
"""Mock compute node: runs the job script, enforces fake walltime + memory."""
import os
import resource
import subprocess
import sys
import time

script, jid = sys.argv[1], sys.argv[2]
STATE = os.environ["MOCKSLURM_STATE"]
wall = int(os.environ.get("MOCK_WALL") or 600)
mem = os.environ.get("MOCK_MEM") or ""


def preexec():
    if mem:
        lim = int(mem)
        resource.setrlimit(resource.RLIMIT_AS, (lim, lim))


start = time.time()
proc = subprocess.Popen(["bash", script], preexec_fn=preexec,
                        stdout=sys.stdout, stderr=sys.stderr)
state, rc = None, None
while True:
    rc = proc.poll()
    if rc is not None:
        break
    if time.time() - start > wall:
        proc.kill()
        proc.wait()
        sys.stderr.write("\nslurmstepd: error: *** JOB %s ON mock-node-01 "
                         "CANCELLED AT %s DUE TO TIME LIMIT ***\n"
                         % (jid, time.strftime("%Y-%m-%dT%H:%M:%S")))
        sys.stderr.flush()
        state, rc = "TIMEOUT", 1
        break
    time.sleep(0.5)

if state is None:
    if rc == 0:
        state = "COMPLETED"
    elif rc in (-9, 137):
        sys.stderr.write("\nslurmstepd: error: Detected 1 oom-kill event(s). "
                         "Some of your processes may have been killed by the "
                         "cgroup out-of-memory handler.\n")
        state = "OUT_OF_MEMORY"
    else:
        state = "FAILED"

elapsed = time.time() - start
with open(os.path.join(STATE, jid + ".state"), "w") as fh:
    fh.write(state)
with open(os.path.join(STATE, jid + ".exit"), "w") as fh:
    fh.write("%d:0" % (abs(rc) if rc else 0))
with open(os.path.join(STATE, jid + ".elapsed"), "w") as fh:
    fh.write("00:%02d:%02d" % (int(elapsed) // 60, int(elapsed) % 60))
