#!/usr/bin/env bash
# Installs ascend-hazel (Hazel login-node model, Mac-driven) on this Mac. Idempotent.
# Run: bash install.sh
set -Eeuo pipefail
BUNDLE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.local/bin" "$HOME/.claude" "$HOME/.claude/skills"

# 1. launcher
ln -sf "$BUNDLE/bin/ascend-hazel" "$HOME/.local/bin/ascend-hazel"

# 2. statusline
cp -f "$BUNDLE/ascend-hazel-statusline.sh" "$HOME/.claude/ascend-hazel-statusline.sh"
chmod +x "$HOME/.claude/ascend-hazel-statusline.sh"

# 3. skill (hazel-remote, Mac-side). Resolve the Unity ID from the hazel alias
#    (else $USER) and substitute it so /share/<user> and squeue -u <user>
#    examples point at THIS user's paths.
UNITYID="$(awk '/^Host hazel$/{b=1;next} b&&/^Host /{b=0} b&&$1=="User"{print $2;exit}' "$HOME/.ssh/config" 2>/dev/null)"
UNITYID="${UNITYID:-$USER}"
rm -rf "$HOME/.claude/skills/hazel-remote"
cp -R "$BUNDLE/skills/hazel-remote" "$HOME/.claude/skills/hazel-remote"
find "$HOME/.claude/skills/hazel-remote" -type f -name '*.md' -print0 | while IFS= read -r -d "" f; do
  sed "s/@@UNITYID@@/$UNITYID/g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
echo "  hazel-remote skill installed for user: $UNITYID"

grep -q "^Host hazel$" "$HOME/.ssh/config" 2>/dev/null || \
  echo "note: no 'hazel' alias in ~/.ssh/config — ascend-hazel needs the multiplexed alias to login.hpc.ncsu.edu (see README-hazel.md)"
command -v jq >/dev/null || echo "note: jq not found — statusline degrades gracefully; brew install jq for full detail"
echo "installed. Warm the link once (ssh hazel), then:  ascend-hazel --check   then:  cd <project> && ascend-hazel"
