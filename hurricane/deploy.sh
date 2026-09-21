#!/usr/bin/env bash
# Deploy ASCEND to hurricane (NC State MEAS single-GPU box, NO scheduler):
# universal harness (common/ascend) + hurricane's gpu-local skill, composed in a
# remote staging dir, then install.sh runs there with ASCEND_HERE=1 so the agent
# runs IN PLACE (there is no Slurm to submit to). Needs the passwordless
# 'hurricane' ssh alias. Run from the Mac.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
REMOTE="${HURRICANE_REMOTE:-hurricane}"
STAGE="ascend-deploy"
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" true 2>/dev/null; then
  echo "cannot reach '$REMOTE' non-interactively (try: ssh $REMOTE true)." >&2
  echo "fix the alias/key first (ssh-copy-id $REMOTE), then re-run." >&2; exit 1
fi
echo "==> staging harness + hurricane/skills/gpu-local -> $REMOTE:~/$STAGE"
ssh "$REMOTE" "rm -rf ~/$STAGE && mkdir -p ~/$STAGE"
rsync -a --delete "$ROOT/common/ascend/" "$REMOTE:~/$STAGE/"
rsync -a --delete "$HERE/skills/gpu-local/" "$REMOTE:~/$STAGE/skills/gpu-local/"
echo "==> running install.sh on the box (ASCEND_HERE=1: no scheduler, run in place)"
ssh "$REMOTE" "ASCEND_SCRATCH=\"\$HOME/agents\" ASCEND_HERE=1 ASCEND_SITE_NAME=ASCEND-HURRICANE bash ~/$STAGE/install.sh"
echo "==> installing on-box ascend-hurricane launcher -> ~/bin/ascend-hurricane"
rsync -a "$HERE/ascend-hurricane/bin/ascend-hurricane-node" "$REMOTE:~/bin/ascend-hurricane"
ssh "$REMOTE" "chmod +x ~/bin/ascend-hurricane"
echo "==> done. (staging copy left at ~/$STAGE; safe to delete)"
