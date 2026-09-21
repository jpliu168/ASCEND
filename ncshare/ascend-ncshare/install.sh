#!/usr/bin/env bash
# Installs ascend-ncshare (NCShare, Mac-driven) on this Mac. Idempotent.
# Run: bash install.sh
set -Eeuo pipefail
BUNDLE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.local/bin" "$HOME/.claude" "$HOME/.claude/skills"

# 1. launcher
ln -sf "$BUNDLE/bin/ascend-ncshare" "$HOME/.local/bin/ascend-ncshare"
ln -sf "$BUNDLE/../../common/ascend/bin/fetch-paper" "$HOME/.local/bin/fetch-paper"
ln -sf "$BUNDLE/../../common/mac/bin/paper-grab" "$HOME/.local/bin/paper-grab"   # browser fallback (Playwright)   # harness tool, works off-campus too (OA + render fallback)

# 2. statusline
cp -f "$BUNDLE/ascend-ncshare-statusline.sh" "$HOME/.claude/ascend-ncshare-statusline.sh"
chmod +x "$HOME/.claude/ascend-ncshare-statusline.sh"

# 3. skill (NCShare remote, Mac-side). Resolve the NCShare username from the
#    ncshare-agent alias (else $USER) and substitute it into the skill so the
#    /work/<user> and squeue -u <user> examples point at THIS user's paths.
NCUSER="$(awk '/^Host ncshare-agent$/{b=1;next} b&&/^Host /{b=0} b&&$1=="User"{print $2;exit}' "$HOME/.ssh/config" 2>/dev/null)"
NCUSER="${NCUSER:-$USER}"
rm -rf "$HOME/.claude/skills/ncshare-remote"
cp -R "$BUNDLE/skills/ncshare-remote" "$HOME/.claude/skills/ncshare-remote"
find "$HOME/.claude/skills/ncshare-remote" -type f -name '*.md' -print0 | while IFS= read -r -d "" f; do
  sed "s/@@NCUSER@@/$NCUSER/g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
echo "  ncshare-remote skill installed for user: $NCUSER"

grep -q "Host ncshare-agent" "$HOME/.ssh/config" 2>/dev/null || \
  echo "note: no 'ncshare-agent' alias in ~/.ssh/config — ascend-ncshare needs it (see README.md)"
command -v jq >/dev/null || echo "note: jq not found — statusline degrades gracefully; brew install jq for full detail"
echo "installed. Try:  ascend-ncshare --check   then:  cd <project> && ascend-ncshare"
