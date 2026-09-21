#!/usr/bin/env bash
# ASCEND (NCShare) setup -- one-time install for a new NCShare user driving the
# cluster from a laptop (the ASCEND-NCSHARE model: agent runs on the laptop, compute
# goes to NCShare through the ncshare-agent / ncshare-agent-gpu ssh aliases).
# Runs on macOS, Linux, and Windows via WSL (Ubuntu). Requires: bash, ssh, rsync.
#
# Prereqs you must already have:
#   * an NCShare account (username, e.g. rhe1) with a /work/<user> directory
#   * ssh access to NCShare (login.ncshare.org). The ncshare-agent +
#     ncshare-agent-gpu aliases (userguide.ncshare.org/guides/ai) are detected
#     if present; this script OFFERS TO CREATE any that are missing.
#   * Claude Code installed locally (the laptop is where the agent runs)
#   * (Windows) WSL installed; run this INSIDE the Ubuntu shell, and put the
#     ssh config + sockets in WSL's Linux home, not Windows %USERPROFILE%.
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

# 0. Claude Code on THIS computer (the ASCEND-NCSHARE agent runs on the laptop).
#    If it's missing, offer to install it with Anthropic's official installer.
if command -v claude >/dev/null 2>&1; then
  say "Claude Code found: $(claude --version 2>/dev/null || echo version unknown)"
else
  warn "Claude Code is not installed on this computer -- the ASCEND-NCSHARE agent runs HERE."
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

# 1. the ncshare-agent aliases (NCShare's SLURM-provisioning proxy). Detected
#    if already set up; otherwise we offer to create them, with the exact Host
#    blocks from NCShare's guide: https://userguide.ncshare.org/guides/ai
have_alias(){ grep -q "^Host $1\$" "$SSHCFG" 2>/dev/null; }
MISSING=""
have_alias ncshare-agent     || MISSING="ncshare-agent"
have_alias ncshare-agent-gpu || MISSING="$MISSING ncshare-agent-gpu"

if [ -n "$MISSING" ]; then
  warn "Missing ssh alias(es) in ~/.ssh/config:$( printf ' %s' $MISSING )"
  cat >&2 <<'GUIDE'

  ASCEND-NCSHARE drives NCShare through two ssh aliases that provision SLURM
  jobs for you:  ncshare-agent (CPU) and ncshare-agent-gpu (GPU).

  This script can set them up for you. If you say yes, it will:
    * create ~/.ssh and ~/.ssh/config if they don't exist yet
      (anything already in the config is left untouched)
    * append the missing Host block(s) exactly as given in NCShare's own
      guide (https://userguide.ncshare.org/guides/ai), filled in with your
      NCShare username
    * then continue with the rest of the setup
  (On WSL, the ssh config lives in ~/.ssh/config inside Ubuntu -- not the
  Windows side.)
GUIDE
  a="$(ask 'Create the missing alias(es) now? [Y/n]' 'Y')"
  case "$a" in
    [Nn]*)
      echo "  OK -- set them up yourself per https://userguide.ncshare.org/guides/ai," >&2
      echo "  then re-run this script." >&2
      exit 1 ;;
  esac
  UNITY="$(ask 'Your NCShare username (e.g. rhe1)')"
  [ -n "$UNITY" ] || { echo "username required."; exit 1; }
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  touch "$SSHCFG"; chmod 600 "$SSHCFG"
  for m in $MISSING; do
    case "$m" in
      ncshare-agent)     PROXY_ARGS="--name agent" ;;
      ncshare-agent-gpu) PROXY_ARGS="--name agent-gpu --partition interactive-gpu,gpu --gres gpu:h200:1 --time 1:00:00" ;;
    esac
    { printf '\n'
      cat <<EOF
# added by ASCEND ncshare/setup.sh ($(date +%F)) -- from userguide.ncshare.org/guides/ai
Host $m
    User $UNITY
    ProxyCommand ssh %r@login.ncshare.org bash /usr/local/bin/ncshare-ssh-proxy.sh $PROXY_ARGS
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 30
    ControlMaster auto
    ControlPersist 30m
    ControlPath ~/.ssh/sockets/%r@%h-%p
EOF
    } >> "$SSHCFG"
    say "added '$m' to ~/.ssh/config"
  done
fi
# derive the username from the alias (the 'User' line in the ncshare-agent block)
UNITY="$(awk '/^Host ncshare-agent$/{b=1;next} b&&/^Host /{b=0} b&&$1=="User"{print $2;exit}' "$SSHCFG")"
UNITY="$(ask 'Your NCShare username' "${UNITY:-}")"
[ -n "$UNITY" ] || { echo "username required."; exit 1; }

# 2. socket dir the aliases need (missing dir == exit-255 on every ssh)
mkdir -p "$HOME/.ssh/sockets"; chmod 700 "$HOME/.ssh/sockets"
say "ssh socket dir ready: ~/.ssh/sockets"

# 3. warm the link (one provisioning + Duo/password if the proxy asks).
#    warm_link (common/ascend/lib/warm-link.sh) offers to OPEN the extra
#    terminal for you and waits until the link is up; you only type the
#    password/Duo in that window. Manual instructions are its fallback.
. "$ROOT/common/ascend/lib/warm-link.sh" 2>/dev/null || true
command -v warm_link >/dev/null 2>&1 || warm_link(){ echo "  Open a NEW terminal, run:  ssh $1   -- complete any password/Duo prompt." >&2; ask 'Press Enter once done' >/dev/null; ssh -o BatchMode=yes -O check "$1" >/dev/null 2>&1 || ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" true >/dev/null 2>&1; }
say "Warming the ncshare-agent link (this may provision a SLURM job)..."
warm_link ncshare-agent "(the first connect provisions a SLURM job -- it can take a minute)" \
  || { echo "link still cold -- get 'ssh ncshare-agent true' working, then re-run."; exit 1; }

# 4. deploy the harness + NCShare hpc-slurm skill to the cluster (file install
#    on the login node -- no compute -- into ~/bin, ~/.claude, /work/<user>)
say "Installing the harness + skills on NCShare (login.ncshare.org)..."
NCSHARE_REMOTE="${UNITY}@login.ncshare.org" bash "$HERE/deploy.sh"

# 5. install the laptop side: ascend-ncshare launcher + ncshare-remote skill
say "Installing the laptop side (ascend-ncshare launcher + ncshare-remote skill)..."
bash "$HERE/ascend-ncshare/install.sh"

# 6. put launchers on PATH
say "Linking launchers into ~/.local/bin"
mkdir -p "$HOME/.local/bin"
for l in "$HERE/ascend-ncshare/bin/ascend-ncshare" \
         "$ROOT/common/ascend/bin/fetch-paper" \
         "$ROOT/common/mac/bin/paper-grab"; do
  [ -f "$l" ] && ln -sf "$l" "$HOME/.local/bin/$(basename "$l")"
done
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) echo "  NOTE: add ~/.local/bin to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac

say "Done. NCShare user: $UNITY   (cluster work dir: /work/$UNITY)"
echo "   Check:      ascend-ncshare --check     (tests both cluster aliases end-to-end)"
echo "   Start it:   cd <project> && ascend-ncshare"
echo "   On cluster: ssh ncshare-agent   then  ascend   (agent runs on a compute node)"
[ "$OS" = mac ] || echo "   (browser paper tools: 'pip install playwright && playwright install chromium' for paper-grab)"
