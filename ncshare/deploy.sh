#!/usr/bin/env bash
# Deploy ASCEND to NCShare: universal harness (common/ascend) + NCShare's own
# hpc-slurm skill, composed in a remote staging dir, then install.sh runs there.
# Run from the Mac. Source stays unmixed; only the staging copy is composed.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
REMOTE="${NCSHARE_REMOTE:-${USER}@login.ncshare.org}"
STAGE="ascend-deploy"
echo "==> staging harness + ncshare/skills/hpc-slurm -> $REMOTE:~/$STAGE"
ssh "$REMOTE" "rm -rf ~/$STAGE && mkdir -p ~/$STAGE"
rsync -a --delete "$ROOT/common/ascend/" "$REMOTE:~/$STAGE/"
rsync -a --delete "$HERE/skills/hpc-slurm/" "$REMOTE:~/$STAGE/skills/hpc-slurm/"
echo "==> running install.sh on NCShare"
ssh "$REMOTE" "bash ~/$STAGE/install.sh"
echo "==> done. (staging copy left at ~/$STAGE on the cluster; safe to delete)"
