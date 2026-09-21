#!/usr/bin/env bash
# ASCEND-ALL setup -- the laptop front door for the three LAPTOP-DRIVEN ASCEND
# models: ascend-hazel (NCSU Hazel via the login node), ascend-ncshare
# (NCShare via the SLURM-provisioning proxy aliases), and ascend-hurricane
# (the MEAS single-GPU box). Claude Code runs on YOUR laptop for all three;
# each resource is reached over multiplexed ssh. Also installs the
# `ascend-all` router (one command that picks the right resource per job).
# Runs on macOS, Linux, and Windows via WSL (Ubuntu). Re-run any time to add
# another resource. Requires: bash, ssh, rsync.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m warn:\033[0m %s\n' "$*" >&2; }
ask(){ local p="$1" d="${2-}" a; printf '%s%s: ' "$p" "${d:+ [$d]}" >&2; IFS= read -r a </dev/tty || true; printf '%s' "${a:-$d}"; }

# self-heal execute bits (files copied through the Windows side lose them)
find "$HERE" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
find "$HERE" -type d -name bin -exec sh -c 'chmod +x "$1"/* 2>/dev/null || true' _ {} \; 2>/dev/null || true

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && OS=wsl || OS=linux ;;
  *) echo "Unsupported OS. On Windows, run this inside WSL (Ubuntu)."; exit 1 ;;
esac
say "platform: $OS"
for t in ssh rsync; do command -v "$t" >/dev/null || { echo "missing '$t' -- install it and re-run."; exit 1; }; done

# Claude Code on THIS computer (all three models run the agent on the laptop)
if command -v claude >/dev/null 2>&1; then
  say "Claude Code found: $(claude --version 2>/dev/null || echo version unknown)"
else
  warn "Claude Code is not installed on this computer -- the agent runs HERE for all three models."
  a="$(ask 'Install it now (curl -fsSL https://claude.ai/install.sh | bash)? [Y/n]' Y)"
  case "$a" in [Nn]*) echo "  Install it first, run 'claude' once to log in, then re-run this script."; exit 1 ;; esac
  command -v curl >/dev/null || { echo "missing 'curl' -- install it and re-run."; exit 1; }
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"
  command -v claude >/dev/null 2>&1 || { echo "install didn't complete -- fix that, then re-run."; exit 1; }
  echo "  NOTE: when setup finishes, run 'claude' once and log in (subscription login)."
fi
mkdir -p "$HOME/.ssh/sockets"; chmod 700 "$HOME/.ssh/sockets"


DONE=""
while :; do
  echo
  echo "Which resource do you want to set up next?"
  echo "  1) Hazel (NCSU HPC, via the login node -- needs a Hazel account)"
  echo "  2) NCShare (needs an NCShare account)"
  echo "  3) hurricane (NC State MEAS single-GPU box -- needs an account on it)"
  echo "  4) done"
  c="$(ask 'Choice [1-4]' 4)"
  case "$c" in
    1) bash "$HERE/hazel/setup-hazel.sh" && DONE="$DONE hazel" ;;
    2) bash "$HERE/ncshare/setup.sh"     && DONE="$DONE ncshare" ;;
    3) bash "$HERE/hurricane/setup-hurricane.sh" && DONE="$DONE hurricane" ;;
    4|'') break ;;
    *) echo "  1, 2, 3 or 4." ;;
  esac
done

# the ascend-all router (recommends a resource per job; needs >=1 set up)
mkdir -p "$HOME/.local/bin"
for l in "$HERE/common/ascend-all/bin/ascend-all" "$HERE/common/ascend-all/bin/ascend-probe"; do
  [ -f "$l" ] && ln -sf "$l" "$HOME/.local/bin/$(basename "$l")"
done
say "ascend-all router installed (ascend-all / ascend-probe)"
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *)
  echo "  NOTE: add ~/.local/bin to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

echo
say "Done.${DONE:+ Set up:$DONE}"
echo "   Verify from a NEW terminal:"
echo "     ascend-hazel --check   ·  ascend-ncshare --check   ·  ascend-hurricane --check"
echo "   One front door for everything:   ascend-all"
echo "   (Keep this folder -- the installed commands link into it.)"
