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
#    (else $USER) and substitute it so /share/<group>/<user> and
#    squeue -u <user> examples point at THIS user's paths.
UNITYID="$(awk '/^Host hazel$/{b=1;next} b&&/^Host /{b=0} b&&$1=="User"{print $2;exit}' "$HOME/.ssh/config" 2>/dev/null)"
UNITYID="${UNITYID:-$USER}"

# Every writable Hazel share dir is $GROUP-scoped (/share/<group>/<unity>) --
# never bare /share/<unity> -- so resolve it over the warm link. Prefer the
# remote account's own $GROUP (the primary group; fast, and correct for the
# common case) over enumerating every group it belongs to: a real account
# can belong to a dozen+ groups for unrelated reasons (software licenses,
# other PIs' projects it has courtesy access to), and searching all of them
# for a writable match is how "unambiguous" stopped being true in practice
# (one real account had 3 genuine matches). Fall back to that full search,
# single-match only, if $GROUP's own path isn't there -- a student's
# primary group is sometimes a generic default, not their project group.
# Best-effort throughout: if the link is cold or nothing resolves, fall
# back to a placeholder rather than guess (the harness itself still
# resolves this correctly at runtime; this only affects the example paths
# written into the skill below).
SHAREDIR=""
if ssh -o BatchMode=yes -O check hazel >/dev/null 2>&1; then
  remote='u="$(id -un)"; g="${GROUP:-$(id -gn)}"; d="/share/$g/$u"; if [ -d "$d" ] && [ -w "$d" ]; then printf "%s" "$d"; else c=""; n=0; for gg in $(id -Gn); do dd="/share/$gg/$u"; [ -d "$dd" ] && [ -w "$dd" ] && { c="$dd"; n=$((n+1)); }; done; [ "$n" -eq 1 ] && printf "%s" "$c"; fi'
  SHAREDIR="$(ssh hazel "bash -lc '$remote'" 2>/dev/null || true)"
fi
SHAREDIR="${SHAREDIR:-/share/<your-group>/$UNITYID}"

rm -rf "$HOME/.claude/skills/hazel-remote"
cp -R "$BUNDLE/skills/hazel-remote" "$HOME/.claude/skills/hazel-remote"
find "$HOME/.claude/skills/hazel-remote" -type f -name '*.md' -print0 | while IFS= read -r -d "" f; do
  sed -e "s/@@UNITYID@@/$UNITYID/g" -e "s#@@SHAREDIR@@#$SHAREDIR#g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
echo "  hazel-remote skill installed for user: $UNITYID   (share dir: ${SHAREDIR})"

grep -q "^Host hazel$" "$HOME/.ssh/config" 2>/dev/null || \
  echo "note: no 'hazel' alias in ~/.ssh/config — ascend-hazel needs the multiplexed alias to login.hpc.ncsu.edu (see README-hazel.md)"
command -v jq >/dev/null || echo "note: jq not found — statusline degrades gracefully; brew install jq for full detail"
echo "installed. Warm the link once (ssh hazel), then:  ascend-hazel --check   then:  cd <project> && ascend-hazel"
