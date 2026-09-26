#!/usr/bin/env bash
# Deploy ASCEND to a CUSTOM site: universal harness (common/ascend) + the
# generic skill for the site's kind, composed in a remote staging dir, then
# install.sh runs there. Normally invoked by setup-custom.sh; can be re-run
# standalone to push updates:
#
#   ./deploy-custom.sh <site-slug> <ssh-alias> <slurm|gpu|cpu> [refs-dir]
#
# refs-dir (optional): a local folder of site docs (user guide, policies) to
# copy into the skill's references/ on the remote.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"

SITE="${1:?site slug (e.g. unc-longleaf)}"
REMOTE="${2:?ssh alias}"
KIND="${3:?kind: slurm | gpu | cpu}"
REFS="${4:-}"
STAGE="ascend-deploy"

case "$KIND" in
  slurm) SKILL="hpc-slurm";  HEREFLAG="" ;;      # agent on login node; compute via Slurm
  gpu|cpu) SKILL="gpu-local"; HEREFLAG="ASCEND_HERE=1 " ;;  # no scheduler: run in place
  *) echo "kind must be slurm, gpu, or cpu" >&2; exit 1 ;;
esac

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE" true 2>/dev/null; then
  echo "cannot reach '$REMOTE' non-interactively (try: ssh $REMOTE true)." >&2
  echo "fix the alias/key first (ssh-copy-id $REMOTE), then re-run." >&2; exit 1
fi

SITELABEL="$(printf '%s' "$SITE" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9-')"

echo "==> staging harness + custom/skills/$SKILL -> $REMOTE:~/$STAGE"
ssh "$REMOTE" "rm -rf ~/$STAGE && mkdir -p ~/$STAGE"
rsync -a --delete "$ROOT/common/ascend/" "$REMOTE:~/$STAGE/"
rsync -a --delete "$HERE/skills/$SKILL/" "$REMOTE:~/$STAGE/skills/$SKILL/"
if [ -n "$REFS" ] && [ -d "$REFS" ]; then
  echo "==> copying site docs from $REFS -> skill references/"
  ssh "$REMOTE" "mkdir -p ~/$STAGE/skills/$SKILL/references"
  rsync -a "$REFS/" "$REMOTE:~/$STAGE/skills/$SKILL/references/"
fi

echo "==> running install.sh on the remote (${HEREFLAG:-scheduler site})"
ssh "$REMOTE" "ASCEND_SCRATCH=\"\${ASCEND_SCRATCH:-\$HOME/agents}\" ${HEREFLAG}ASCEND_SITE_NAME=ASCEND-$SITELABEL bash ~/$STAGE/install.sh"
echo "==> done. (staging copy left at ~/$STAGE; safe to delete)"
