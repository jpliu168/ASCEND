#!/usr/bin/env bash
# ASCEND installer -- run straight from a git clone.
#
#   git clone https://github.com/jpliu168/ASCEND.git
#   cd ASCEND && ./install.sh              # interactive: pick one or more resources
#
# Non-interactive resource selection:
#   ./install.sh all                       # same as interactive setup
#   ./install.sh hazel                     # NCSU Hazel only
#   ./install.sh ncshare                   # NCShare only
#   ./install.sh hurricane                 # MEAS single-GPU box only
#   ./install.sh router                    # just the ascend-all front door
#
# Everything installs into ~/.local/bin (symlinks) and ~/.claude (skills and
# statusline). Nothing is copied out of this clone, so KEEP THE CLONE -- a
# `git pull` then updates every installed command in place.
#
# macOS, Linux, or Windows + WSL (Ubuntu). Requires: bash, ssh, rsync, git.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
die(){ printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin|Linux) : ;;
  *) die "Unsupported OS. On Windows, run this inside WSL (Ubuntu)." ;;
esac
for t in ssh rsync; do command -v "$t" >/dev/null || die "missing '$t' -- install it and re-run."; done

# files that came through a Windows share lose their execute bits
find "$HERE" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
find "$HERE" -type d -name bin -exec sh -c 'chmod +x "$1"/* 2>/dev/null || true' _ {} \; 2>/dev/null || true

install_router(){
  mkdir -p "$HOME/.local/bin"
  bash "$HERE/common/ascend-all/install.sh"
}

TARGET="${1:-all}"
case "$TARGET" in
  all|"")     exec bash "$HERE/setup.sh" ;;
  hazel)      bash "$HERE/hazel/setup-hazel.sh";          install_router ;;
  ncshare)    bash "$HERE/ncshare/setup.sh";              install_router ;;
  hurricane)  bash "$HERE/hurricane/setup-hurricane.sh";  install_router ;;
  router)     install_router ;;
  -h|--help|help)
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown target '$TARGET' (expected: all, hazel, ncshare, hurricane, router)" ;;
esac

case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) say "add ~/.local/bin to your PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
say "done -- verify from a NEW terminal:  ascend-$TARGET --check   (front door: ascend-all)"
