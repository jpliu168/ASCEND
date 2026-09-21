#!/usr/bin/env bash
# Install ascend-all + ascend-probe on this Mac (the multi-resource router).
# Assumes the per-resource launchers (ascend-ncshare / ascend-vcl /
# ascend-hurricane) are already installed. Run: bash install.sh
set -Eeuo pipefail
BUNDLE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.local/bin" "$HOME/.claude/skills"
ln -sf "$BUNDLE/bin/ascend-all"   "$HOME/.local/bin/ascend-all"
ln -sf "$BUNDLE/bin/ascend-probe" "$HOME/.local/bin/ascend-probe"
rm -rf "$HOME/.claude/skills/ascend-router"
cp -R "$BUNDLE/skills/ascend-router" "$HOME/.claude/skills/ascend-router"
echo "installed: ascend-all, ascend-probe, and the ascend-router skill."
# Nudge if any per-resource launcher is missing.
for l in ascend-ncshare ascend-vcl ascend-hurricane; do
  command -v "$l" >/dev/null || echo "note: '$l' not on PATH yet — install that resource so ascend-all can hand off to it."
done
command -v claude >/dev/null || echo "note: local 'claude' not found — ascend-all uses it to reason (falls back to a rule-based pick)."
echo "Try:  ascend-all --probe      then:  ascend-all \"train one-GPU model ~4h\""
