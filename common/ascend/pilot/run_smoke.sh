#!/usr/bin/env bash
# End-to-end proof that the harness works on the real cluster.
#
#   bash run_smoke.sh          # happy path only  (~2 min of queue + 1 min run)
#   bash run_smoke.sh --full   # also the crash + OOM paths (~10 min)
#
# Costs a few GPU-minutes on interactive-gpu. Run this ONCE before trusting
# the harness with real science.
set -Eeuo pipefail

WORK="${ASCEND_SCRATCH:-/work/${USER}}"
PILOT="${WORK}/agent-pilot/smoke"
export HPCRUN_ROOT="${WORK}/agent-workspaces"
export PATH="${HOME}/bin:${PATH}"
FULL=0; [ "${1:-}" = "--full" ] && FULL=1

command -v hpcrun >/dev/null || { echo "hpcrun not on PATH; run install.sh" >&2; exit 1; }
[ -d "$PILOT" ] || { echo "pilot not found at $PILOT; run install.sh" >&2; exit 1; }

jq_() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
hr() { printf '\n\033[1m--- %s\033[0m\n' "$*"; }

hr "1/6  probing the cluster"
hpcrun site --probe | jq_ "'scheduler=%s partitions=%s accounts=%s' % (
    d['site']['scheduler'],
    ','.join(p['partition'] for p in d['site']['partitions']) or '-',
    ','.join(sorted({a['account'] for a in d['site']['accounts'] if a['account']})) or '-')"

ACCT=$(python3 -c "
import json,os
s=json.load(open(os.environ['HPCRUN_ROOT']+'/site.json'))
a=sorted({x['account'] for x in s.get('accounts',[]) if x.get('account')})
print(a[0] if a else '')")
[ -n "$ACCT" ] && echo "    using account: $ACCT" || echo "    no account found; leaving it unset"

hr "2/6  creating workspace"
SMOKE_WS="${HPCRUN_ROOT}/smoke/pilot"
if [ -f "$SMOKE_WS/workspace.json" ]; then
  python3 - "$SMOKE_WS/workspace.json" <<'RESETPY'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p))
spent, budget = cfg.get("spent", {}), cfg.get("budget", {})
if spent.get("attempts", 0) >= budget.get("max_attempts", 5):
    print("    NOTE: this disposable smoke workspace had used %s/%s attempts;"
          % (spent.get("attempts"), budget.get("max_attempts")))
    print("    resetting its counters so the test can run again. This is only")
    print("    ever done for the smoke pilot -- never for a real workspace.")
    cfg["spent"] = {"attempts": 0, "node_hours": 0.0, "gpu_hours": 0.0}
    json.dump(cfg, open(p, "w"), indent=2, sort_keys=True)
RESETPY
fi
hpcrun ws --project smoke --experiment pilot --max-attempts 4 \
          --max-node-hours 2 --max-gpu-hours 2 | jq_ "d['workspace']"
export HPCRUN_WS="${HPCRUN_ROOT}/smoke/pilot"

hr "3/6  creating a new revision (happy path)"
# The shipped spec is written for NCShare (interactive-gpu, h200, /work
# paths). Other sites get an adapted copy: a real GPU spec if the site has
# a fast interactive-style GPU path (Hazel: gpu_partners/short_gpu, type
# picked live from 'si --gpus' so the smoke test actually proves GPU access,
# not just the harness loop), else CPU-only (the harness loop still proves
# out fine with no GPU).
SPEC="$PILOT/spec.json"
MODE="ncshare"
if ! python3 -c "
import json, os
s = json.load(open(os.environ['HPCRUN_ROOT'] + '/site.json'))
raise SystemExit(0 if any(p['partition'] == 'interactive-gpu'
                          for p in s.get('partitions', [])) else 1)
" 2>/dev/null; then
  MODE="cpu"
  GPU_TYPE=""
  if python3 -c "
import json, os
s = json.load(open(os.environ['HPCRUN_ROOT'] + '/site.json'))
raise SystemExit(0 if any(p['partition'] == 'gpu_partners'
                          for p in s.get('partitions', [])) else 1)
" 2>/dev/null && command -v si >/dev/null 2>&1; then
    # si's Avail column already nets out the GrpTRES cap (Avail = min(Total-
    # Alloc, GrpTRES-Used)), confirmed live 2026-09-23, so it's a reliable
    # pick -- occasional staleness right at the submit instant is acceptable
    # here (a pending job is informative for a smoke test, not a silent
    # failure, and not worth retry/fallback logic over).
    GPU_TYPE="$(si --gpus --qos short_gpu 2>/dev/null \
      | awk '$1=="gpu_partners" && $5+0>0 {print tolower($2); exit}')"
  fi
  [ -n "$GPU_TYPE" ] && MODE="hazel_gpu"

  if [ "$MODE" = "hazel_gpu" ]; then
    echo "    Hazel site: live-picked '$GPU_TYPE' (Avail>0 under gpu_partners/short_gpu)"
  else
    echo "    non-NCShare site: adapting smoke spec (CPU-only, partition ${ASCEND_PARTITION:-compute})"
  fi

  python3 - "$PILOT/spec.json" "$PILOT/spec.local.json" "$MODE" "${GPU_TYPE:-}" <<'ADAPTPY'
import json, os, sys
spec = json.load(open(sys.argv[1]))
scratch = os.environ.get("ASCEND_SCRATCH") or os.path.expanduser("~")
mode, gpu_type = sys.argv[3], sys.argv[4]
if mode == "hazel_gpu":
    spec["partition"] = "gpu_partners"
    spec["qos"] = "short_gpu"
    spec["gpus_per_node"] = 1
    spec["gpu_type"] = gpu_type
    spec["cpus_per_task"] = 2
    spec["walltime_minutes"] = 10
else:
    spec["partition"] = os.environ.get("ASCEND_PARTITION") or "compute"
    spec["gpus_per_node"] = 0
    spec.pop("gpu_type", None)
spec["mem_per_node_gb"] = 8
spec["environment"]["conda_env"] = None
spec["environment"]["vars"]["TMPDIR"] = os.path.join(scratch, "tmp")
spec["entrypoint"] = ["python3", "run.py"]
json.dump(spec, open(sys.argv[2], "w"), indent=2)
ADAPTPY
  SPEC="$PILOT/spec.local.json"

  # Hazel splits accounts into _cpu/_gpu halves; the pick above is type-
  # agnostic (alphabetically first), which is wrong once a GPU spec is in
  # play -- submitting it under the _cpu account is rejected at validate
  # time ("is the CPU half of the tree, but this is a GPU job"). Re-pick an
  # account matching what this spec actually needs.
  WANT_SUFFIX="_cpu"; [ "$MODE" = "hazel_gpu" ] && WANT_SUFFIX="_gpu"
  TYPED_ACCT="$(python3 -c "
import json, os
s = json.load(open(os.environ['HPCRUN_ROOT'] + '/site.json'))
accts = sorted({a['account'] for a in s.get('accounts', []) if a.get('account')})
m = [a for a in accts if a.endswith('$WANT_SUFFIX')]
print(m[0] if m else '')")"
  if [ -n "$TYPED_ACCT" ] && [ "$TYPED_ACCT" != "$ACCT" ]; then
    echo "    re-picked account for a $WANT_SUFFIX job: $TYPED_ACCT"
    ACCT="$TYPED_ACCT"
  fi
fi
SETS=(--set 'environment.vars.FAIL_MODE="none"')
[ -n "$ACCT" ] && SETS+=(--set "account=\"$ACCT\"")
hpcrun rev new --from-dir "$PILOT" --spec "$SPEC" \
    "${SETS[@]}" --reason "smoke test: verify the harness end to end" \
    | jq_ "'%s  files=%s' % (d['rev'], ','.join(d['revision']['code_files']))"

hr "4/6  validating (this is what catches mistakes before they cost hours)"
if hpcrun validate | jq_ "'ok=%s errors=%s warnings=%s est=%s' % (
        d['ok'], d['errors'] or '-', d['warnings'] or '-', d['estimated'])"; then
  :
else
  echo >&2
  echo "VALIDATION FAILED. The errors printed above are the actual reason --" >&2
  echo "read them rather than guessing. Common causes:" >&2
  echo "  * budget exhausted -> the guard working as intended, not a fault;" >&2
  echo "    reset with: rm -rf \$HPCRUN_ROOT/smoke/pilot" >&2
  echo "  * partition/account invalid for you -> check 'hpcrun site --show'" >&2
  exit 1
fi

hr "5/6  submitting and waiting (queue time varies)"
JID=$(hpcrun submit | jq_ "d['job_id']")
echo "    job $JID submitted; polling with backoff..."
hpcrun wait --job "$JID" --timeout 1800 \
  | jq_ "'state=%s exit=%s elapsed=%s' % (d['state'], d.get('exit_code'), d.get('elapsed'))" || true

hr "6/6  diagnosing and collecting results"
hpcrun diagnose --job "$JID" | jq_ "'succeeded=%s findings=%s' % (
    d['succeeded'], [f['rule'] for f in d['findings']] or '-')"
hpcrun results --job "$JID" | jq_ "'artifacts=%s' % ([a['path'] for a in d['artifacts']] or '-')"
echo
echo "    GPU seen by the job:"
hpcrun logs --job "$JID" --stream stdout --tail 40 \
  | python3 -c "
import json,sys
t=json.load(sys.stdin)['streams']['stdout']['text']
for l in t.splitlines():
    if 'torch' in l or 'CUDA' in l or 'SUCCESS' in l: print('      '+l)"

if [ "$FULL" = "1" ]; then
  hr "BONUS  crash path -- must halt for human review, not auto-repair"
  hpcrun rev new --set 'environment.vars.FAIL_MODE="crash"' \
      --reason "deliberate crash to exercise diagnosis" >/dev/null
  hpcrun loop --max-attempts 2 --timeout 1800 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('    halted_because:', d.get('halted_because'))
print('    (expected: human_review -- a code bug must NOT be auto-retried)')" || true

  hr "BONUS  OOM path -- must auto-repair by doubling memory"
  hpcrun rev new --set 'environment.vars.FAIL_MODE="memory"' \
      --set mem_per_node_gb=4 --reason "deliberate OOM" >/dev/null
  hpcrun loop --max-attempts 3 --timeout 1800 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d.get('transcript',[]):
    if t.get('step')=='repair':
        print('    repair:', t.get('action'), t.get('changes'))
print('    halted_because:', d.get('halted_because'))" || true
fi

hr "done"
cat <<EOF
    Workspace : ${HPCRUN_WS}
    Ledger    : hpcrun ledger --tail 30
    Budget    : hpcrun status
EOF
case "$MODE" in
  hazel_gpu)
    cat <<EOF

This ran a live GPU spec on Hazel (gpu_partners/short_gpu, type '$GPU_TYPE',
picked from 'si --gpus --qos short_gpu' at submit time). If step 6 printed
succeeded=True and step 6's GPU line showed a real CUDA_VISIBLE_DEVICES
value (not <unset>), the harness proves out on real Hazel GPU access, not
just the harness loop. GPU availability changes by the hour -- a pending
job here means nothing was free at submit time, not a harness fault; check
'sqos' / 'si --gpus --qos short_gpu' and retry.
EOF
    ;;
  cpu)
    cat <<EOF

This ran the site-adapted CPU-only spec (partition ${ASCEND_PARTITION:-compute},
no GPU) -- the smoke test proves the harness loop, not GPU access, so there
is no device name to look for here. If step 6 printed succeeded=True, the
harness works end to end on this site and you can point it at real work.
For a GPU check, pick a type live with 'sqos' / 'si --gpus --qos <qos>' and
run a real GPU revision -- this smoke test does not exercise gres selection.
EOF
    ;;
  *)
    cat <<EOF

If step 6 printed succeeded=True and a real H200 device name, the harness
works end to end and you can point it at real work.
EOF
    ;;
esac
