#!/usr/bin/env bash
# Deploy ASCEND to Hazel over the multiplexed `hazel` alias (login node,
# ASCEND-HAZEL model): universal harness (common/ascend) + Hazel's hpc-slurm
# skill, composed in a remote staging dir, then install.sh runs there.
# File installs only -- no compute on the login node.
# Needs a warm 'hazel' link (ssh hazel once: password + Duo, persists 8h).
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
REMOTE="${HAZEL_REMOTE:-hazel}"
STAGE="ascend-deploy"
if ! ssh -O check "$REMOTE" >/dev/null 2>&1; then
  echo "link to $REMOTE is COLD -- run:  ssh $REMOTE   (password + Duo, once), then re-run." >&2; exit 1
fi
UNITY="$(ssh "$REMOTE" 'whoami' 2>/dev/null)"
[ -n "$UNITY" ] || { echo "could not resolve the Hazel username over the link." >&2; exit 1; }
echo "==> staging harness + ncsuhpc/skills/hpc-slurm -> $REMOTE:~/$STAGE"
ssh "$REMOTE" "rm -rf ~/$STAGE && mkdir -p ~/$STAGE"
rsync -a --delete "$ROOT/common/ascend/" "$REMOTE:~/$STAGE/"
rsync -a --delete "$HERE/skills/hpc-slurm/" "$REMOTE:~/$STAGE/skills/hpc-slurm/"
if [ -n "${ASCEND_SHARE:-}" ]; then
  echo "==> running install.sh on the login node (file install into ~/bin, ~/.claude, $ASCEND_SHARE/agents)"
  ssh "$REMOTE" "ASCEND_SCRATCH='$ASCEND_SHARE/agents' ASCEND_SITE_NAME=ASCEND-HAZEL bash ~/$STAGE/install.sh"
else
  # No override -- let install.sh auto-detect the writable /share/<group>/$UNITY
  # dir on the node itself (it knows every group the account belongs to; this
  # script does not, so it must not guess a bare /share/$UNITY here).
  echo "==> running install.sh on the login node (it will auto-detect your /share/<group>/$UNITY working directory)"
  ssh "$REMOTE" "ASCEND_SITE_NAME=ASCEND-HAZEL bash ~/$STAGE/install.sh"
fi
echo "==> done. (staging copy left at ~/$STAGE; safe to delete)"
