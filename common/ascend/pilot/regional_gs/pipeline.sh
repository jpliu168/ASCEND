#!/bin/bash
# regional_gs full pipeline, driven by hpcrun.
#
# Ported from run_ostia_8gpu.sbatch. The #SBATCH directives, conda activation,
# and environment come from spec.json and the rendered wrapper; this script is
# only the science.
#
# RESUBMIT-SAFE BY CONSTRUCTION. Every stage auto-resumes from its own
# _last.pt. Nothing here deletes a checkpoint unless it is provably stale.
# If this job hits its walltime, resubmitting the SAME revision continues
# where it stopped.
#
# The one destructive path -- starting a genuinely fresh run -- is opt-in via
# FRESH=1, and it takes a timestamped backup of ckpt/ before touching anything.
set -Eeuo pipefail

: "${GS_ROOT:?GS_ROOT must be set by the spec}"
cd "$GS_ROOT"
CK="$GS_ROOT/ckpt"
mkdir -p "$CK" "$GS_ROOT/logs"

# ---- run knobs. KEEP IDENTICAL ACROSS RESUBMITS OF A RUN ----
# The cosine LR total is derived from --epochs/--batch/--nproc, so changing
# one of these mid-curriculum silently corrupts the schedule.
E_R2="${E_R2:-150}"; E_R3="${E_R3:-40}"; E_R4="${E_R4:-30}"; E_R5="${E_R5:-0}"
S2B_EPOCHS="${S2B_EPOCHS:-400}"
BATCH="${BATCH:-4}"                 # PER-GPU; effective = BATCH x NPROC
S2B_BATCH="${S2B_BATCH:-16}"
DIFF_BASE="${DIFF_BASE:-64}"
NPROC="${NPROC:-8}"
LR_R3="${LR_R3:-3e-4}"; LR_R4="${LR_R4:-2e-4}"; LR_R5="${LR_R5:-1.5e-4}"
FRESH="${FRESH:-0}"

run() { torchrun --standalone --nproc_per_node="$NPROC" "$@"; }
hr()  { echo; echo "================ $* ================"; }

hr "JOB ${SLURM_JOB_ID:-interactive} on $(hostname)"
nvidia-smi -L || true
echo "config: R2=$E_R2 R3=$E_R3 R4=$E_R4 R5=$E_R5 S2B=$S2B_EPOCHS "\
     "BATCH=$BATCH NPROC=$NPROC FRESH=$FRESH"

# ---------------- guard: another run already touching ckpt/? ----------------
# A chunk_interactive run and a batch job sharing ckpt/ will corrupt each
# other. Cheap lock, released on exit.
LOCK="$CK/.hpcrun.lock"
if [ -e "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
  echo "ERROR: another run (pid $(cat "$LOCK")) is using $CK. Refusing to" >&2
  echo "       run two pipelines against the same checkpoints." >&2
  exit 75
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# ---------------- preflight ----------------
hr "PREFLIGHT"
python - <<'PY'
import numpy as np, os, sys
from src.config import PREP_PATH, CONFIG
assert os.path.exists(PREP_PATH), f"missing {PREP_PATH} -- run src.data_prep"
d = np.load(PREP_PATH, allow_pickle=True)
H, W = len(d["LAT"]), len(d["LON"])
print(f"[preflight] grid {H}x{W}={H*W} | train_frames={len(d['train_idx'])} | "
      f"LATENT={CONFIG['LATENT']} PROC_STEPS={CONFIG['PROC_STEPS']} "
      f"MESH_REFINE={CONFIG['MESH_REFINE']}")
need = {"USE_SSH": "prep_ssh.npz", "USE_FLUX": "prep_flux.npz",
        "USE_MLD": "prep_mld.npz"}
for flag, fn in need.items():
    if CONFIG.get(flag):
        p = os.path.join(os.path.dirname(PREP_PATH), fn)
        assert os.path.exists(p), (
            f"{flag}=True but {fn} missing -- build it before submitting")
        print(f"[preflight] {flag}=True  {fn} present")
print("[preflight] OK")
PY

# ---------------- optional fresh start, with a backup ----------------
if [ "$FRESH" = "1" ]; then
  BK="$GS_ROOT/ckpt_backup_$(date +%Y%m%d_%H%M%S)"
  hr "FRESH RUN -- backing up ckpt/ to $BK"
  cp -a "$CK" "$BK"
  rm -f "$CK"/gnn_stage1*.pt "$CK"/diffusion_stage2b*.pt \
        "$CK"/stage1.done "$CK"/stage2b.done "$CK"/spread_infl.npy
  echo "[fresh] previous checkpoints preserved in $BK"
  FRESH_FLAG="--fresh"
else
  FRESH_FLAG=""
  echo "[resume] continuing from existing checkpoints (set FRESH=1 to restart)"
fi

# ---------------- Stage 1: rollout curriculum ----------------
hr "STAGE 1  R=2  (epochs=$E_R2 batch=$BATCH)"
run -m src.train_stage1 --epochs "$E_R2" --batch "$BATCH" --rollout 2 $FRESH_FLAG

hr "STAGE 1  R=3  (epochs=$E_R3) warm-start from R=2"
run -m src.train_stage1 --epochs "$E_R3" --batch "$BATCH" --rollout 3 \
    --lr "$LR_R3" --ckpt gnn_stage1_r3.pt --init-from gnn_stage1.pt

hr "STAGE 1  R=4  (epochs=$E_R4) warm-start from R=3"
run -m src.train_stage1 --epochs "$E_R4" --batch "$BATCH" --rollout 4 \
    --lr "$LR_R4" --ckpt gnn_stage1_r4.pt --init-from gnn_stage1_r3.pt

if [ "$E_R5" -gt 0 ]; then
  hr "STAGE 1  R=5  (epochs=$E_R5) warm-start from R=4"
  run -m src.train_stage1 --epochs "$E_R5" --batch "$BATCH" --rollout 5 \
      --lr "$LR_R5" --ckpt gnn_stage1_r5.pt --init-from gnn_stage1_r4.pt
fi

# ---------------- promote the best val@5 ----------------
hr "PROMOTE best Stage-1 checkpoint"
python - <<'PY'
import os, shutil, sys, torch
CK = os.path.join(os.environ["GS_ROOT"], "ckpt")
# (tag, last-state file, deliverable file)
cands = [("r2", "gnn_stage1_last.pt",    "gnn_stage1.pt"),
         ("r3", "gnn_stage1_r3_last.pt", "gnn_stage1_r3.pt"),
         ("r4", "gnn_stage1_r4_last.pt", "gnn_stage1_r4.pt"),
         ("r5", "gnn_stage1_r5_last.pt", "gnn_stage1_r5.pt")]
best = None
for tag, last, deliv in cands:
    p = os.path.join(CK, last)
    if not os.path.exists(p):
        continue
    try:
        v = float(torch.load(p, map_location="cpu",
                             weights_only=False).get("best", float("inf")))
    except Exception as exc:
        print(f"[promote] {tag}: unreadable ({exc})"); continue
    print(f"[promote] {tag}: best val@5 = {v:.4f}")
    if best is None or v < best[1]:
        best = (tag, v, deliv)
if best is None:
    sys.exit("[promote] FATAL: no Stage-1 checkpoint found to promote")
tag, v, deliv = best
src = os.path.join(CK, deliv)
if not os.path.exists(src):
    sys.exit(f"[promote] FATAL: winner {tag} has no deliverable at {src}")
dst = os.path.join(CK, "gnn_stage1.pt")
if os.path.abspath(src) != os.path.abspath(dst):
    shutil.copyfile(src, dst)
print(f"[promote] winner = {tag} (val@5 {v:.4f}) -> gnn_stage1.pt")
PY

# ---------------- Stage 2b ----------------
# If Stage 1 moved, the rollout-mean cache is stale. A stage2b checkpoint
# trained on old means must NOT be resumed, and the spread calibration
# derived from it is invalid too.
MEANS_META="$GS_ROOT/prep/means2b_meta.npz"
if [ ! -f "$MEANS_META" ] || [ "$CK/gnn_stage1.pt" -nt "$MEANS_META" ]; then
  hr "GEN 2b ROLLOUT MEANS (Stage 1 changed -> cache is stale)"
  python -m src.gen_rollout_means
  echo "[stage2b] invalidating stage2b checkpoints and spread calibration"
  rm -f "$CK"/diffusion_stage2b.pt "$CK"/diffusion_stage2b_last.pt \
        "$CK"/stage2b.done "$CK"/spread_infl.npy
else
  echo "[stage2b] rollout means are current; reusing them"
fi

hr "STAGE 2b  (epochs=$S2B_EPOCHS batch=$S2B_BATCH base=$DIFF_BASE)"
run -m src.train_stage2b --epochs "$S2B_EPOCHS" --batch "$S2B_BATCH" \
    --base "$DIFF_BASE"

# ---------------- calibrate + evaluate ----------------
hr "SPREAD CALIBRATION (val year)"
if [ ! -f "$CK/spread_infl.npy" ]; then
  python -m src.tune_spread
else
  echo "[calib] spread_infl.npy already present; reusing"
fi

hr "EVALUATE (deterministic)"
python -m src.evaluate
hr "EVALUATE (ensemble)"
python -m src.eval_ensemble

# ---------------- collect the figures hpcrun will stage ----------------
if [ -n "${HPCRUN_RESULTDIR:-}" ]; then
  mkdir -p "$HPCRUN_RESULTDIR/figs"
  cp -f "$GS_ROOT"/figs/*.png "$HPCRUN_RESULTDIR/figs/" 2>/dev/null || true
  cp -f "$CK"/spread_infl.npy "$HPCRUN_RESULTDIR/" 2>/dev/null || true
  echo "[collect] figures copied to $HPCRUN_RESULTDIR/figs"
fi

hr "ALL DONE -> figs in $GS_ROOT/figs"
