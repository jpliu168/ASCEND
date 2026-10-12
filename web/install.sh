#!/bin/bash
# Install the ascend-web launcher: symlink bin/ascend-web into ~/.local/bin
# (same convention as the other ASCEND launchers). bash-3.2 safe.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HOME/.local/bin"
chmod +x "$HERE/bin/ascend-web" "$HERE/ascend-web.py" 2>/dev/null
ln -sfn "$HERE/bin/ascend-web" "$HOME/.local/bin/ascend-web"
echo "Linked: ~/.local/bin/ascend-web -> $HERE/bin/ascend-web"

. "$HERE/../common/ascend/lib/ensure-path.sh"; ascend_ensure_path
case ":$PATH:" in *":$HOME/.local/bin:"*) echo "Ready — run: ascend-web" ;; esac
