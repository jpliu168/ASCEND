#!/usr/bin/env bash
# ASCEND-HAZEL setup -- one-time install for a new Hazel user driving the
# cluster from a laptop (agent runs on the laptop; Hazel is reached through
# the multiplexed `hazel` ssh alias to login.hpc.ncsu.edu; the login node is
# used ONLY for job scheduling and environment builds -- all compute via Slurm).
# No VCL reservation needed. Runs on macOS, Linux, and Windows via WSL (Ubuntu).
# Requires: bash, ssh, rsync.
#
# Prereqs you must already have:
#   * a Hazel (NCSU HPC) account: Unity ID + membership in an HPC project
#     (you can log in to login.hpc.ncsu.edu with password + Duo)
#   * (Windows) WSL installed; run this INSIDE the Ubuntu shell, and put the
#     ssh config in WSL's Linux home, not Windows %USERPROFILE%.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"

say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m warn:\033[0m %s\n' "$*" >&2; }
ask(){ local p="$1" d="${2-}" a; printf '%s%s: ' "$p" "${d:+ [$d]}" >&2; IFS= read -r a </dev/tty || true; printf '%s' "${a:-$d}"; }

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && OS=wsl || OS=linux ;;
  *) echo "Unsupported OS. On Windows, run this inside WSL (Ubuntu)."; exit 1 ;;
esac
say "platform: $OS"
for t in ssh rsync; do command -v "$t" >/dev/null || { echo "missing '$t' -- install it and re-run."; exit 1; }; done

# 0. Claude Code on THIS computer (the ASCEND-HAZEL agent runs on the laptop).
if command -v claude >/dev/null 2>&1; then
  say "Claude Code found: $(claude --version 2>/dev/null || echo version unknown)"
else
  warn "Claude Code is not installed on this computer -- the ASCEND-HAZEL agent runs HERE."
  a="$(ask 'Install it now (curl -fsSL https://claude.ai/install.sh | bash)? [Y/n]' Y)"
  case "$a" in
    [Nn]*)
      echo "  Install it yourself first:   curl -fsSL https://claude.ai/install.sh | bash"
      echo "  then run 'claude' once and log in, and re-run this script."
      exit 1 ;;
  esac
  command -v curl >/dev/null || { echo "missing 'curl' -- install it and re-run."; exit 1; }
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"   # the native installer's location, for this run
  command -v claude >/dev/null 2>&1 \
    || { echo "install didn't complete (no 'claude' on PATH) -- fix that, then re-run."; exit 1; }
  say "Claude Code installed: $(claude --version 2>/dev/null || echo ok)"
  echo "  NOTE: when setup finishes, run 'claude' once and log in (subscription login)."
fi

SSHCFG="$HOME/.ssh/config"

# 1. the `hazel` multiplexed alias (ControlMaster to login.hpc.ncsu.edu).
#    Detected if already set up; otherwise we offer to create it.
if grep -q "^Host hazel\$" "$SSHCFG" 2>/dev/null; then
  say "found 'hazel' alias in ~/.ssh/config"
else
  warn "No 'hazel' alias in ~/.ssh/config."
  cat >&2 <<'GUIDE'

  ASCEND-HAZEL reaches Hazel through one multiplexed ssh alias: `hazel`.
  You authenticate (password + Duo) ONCE; the connection then persists 8h and
  every further command rides it with no prompt.

  This script can set it up for you. If you say yes, it will:
    * create ~/.ssh and ~/.ssh/config if they don't exist yet
      (anything already in the config is left untouched)
    * append the Host block below, filled in with your Unity ID
  (On WSL, the ssh config lives in ~/.ssh/config inside Ubuntu -- not the
  Windows side.)
GUIDE
  a="$(ask 'Create the hazel alias now? [Y/n]' 'Y')"
  case "$a" in
    [Nn]*)
      echo "  OK -- add the Host block yourself (see README), then re-run this script." >&2
      exit 1 ;;
  esac
  UNITY="$(ask 'Your Unity ID (e.g. jdoe2)')"
  [ -n "$UNITY" ] || { echo "Unity ID required."; exit 1; }
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$SSHCFG"; chmod 600 "$SSHCFG"
  { printf '\n'
    cat <<EOF
# added by ASCEND ncsuhpc/setup-hazel.sh ($(date +%F)) -- multiplexed Hazel login-node alias
Host hazel
  HostName login.hpc.ncsu.edu
  User $UNITY
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h-%p
  ControlPersist 8h
  ServerAliveInterval 30
  ServerAliveCountMax 4
EOF
  } >> "$SSHCFG"
  say "added 'hazel' to ~/.ssh/config"
fi
# derive the Unity ID from the alias (the 'User' line in the hazel block)
UNITY="$(awk '/^Host hazel$/{b=1;next} b&&/^Host /{b=0} b&&$1=="User"{print $2;exit}' "$SSHCFG")"
UNITY="$(ask 'Your Unity ID' "${UNITY:-}")"
[ -n "$UNITY" ] || { echo "Unity ID required."; exit 1; }

# 2. warm the link (password + Duo once; persists 8h).
#    warm_link (common/ascend/lib/warm-link.sh) offers to OPEN the extra
#    terminal for you and waits until the link is up; you only type the
#    password/Duo in that window. Manual instructions are its fallback.
. "$ROOT/common/ascend/lib/warm-link.sh" 2>/dev/null || true
command -v warm_link >/dev/null 2>&1 || warm_link(){ echo "  Open a NEW terminal, run:  ssh $1   -- complete the password/Duo prompt." >&2; ask 'Press Enter once done' >/dev/null; ssh -O check "$1" >/dev/null 2>&1; }
say "Warming the hazel link (password + Duo, once -- then it persists 8h)..."
warm_link hazel "(answer password + Duo in the window that opens)" \
  || { echo "link still cold -- get 'ssh hazel true' working, then re-run."; exit 1; }

# 3. deploy the harness + Hazel hpc-slurm skill to the cluster (file install
#    on the login node -- no compute -- into ~/bin, ~/.claude, /share/<user>/agents)
say "Installing the harness + skills on Hazel..."
HAZEL_REMOTE=hazel bash "$HERE/deploy-hazel.sh"

# 4. install the laptop side: ascend-hazel launcher + hazel-remote skill
say "Installing the laptop side (ascend-hazel launcher + hazel-remote skill)..."
bash "$HERE/ascend-hazel/install.sh"

# 5. put launchers on PATH
say "Linking launchers into ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for l in "$HERE/ascend-hazel/bin/ascend-hazel" \
         "$ROOT/common/ascend/bin/fetch-paper"; do
  [ -f "$l" ] && ln -sf "$l" "$HOME/.local/bin/$(basename "$l")"
done
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) echo "  NOTE: add ~/.local/bin to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac

say "Done. Hazel user: $UNITY   (cluster work dir: /share/$UNITY/agents)"
echo "   Check:      ascend-hazel --check     (socket probe + login node / slurm / tools)"
echo "   Start it:   cd <project> && ascend-hazel"
echo "   Remember:   the login node is for scheduling + env builds ONLY;"
echo "               all compute goes through Slurm jobs (hpcrun / sbatch)."
