#!/usr/bin/env bash
# ASCEND-HURRICANE setup -- one-time install for the NC State MEAS single-GPU
# box (RTX PRO 6000 Blackwell). The agent runs on YOUR laptop and reaches the
# box over a multiplexed ssh alias; there is no scheduler, so work runs in
# place, one heavy job at a time. Runs on macOS, Linux, and Windows via WSL.
# Requires: bash, ssh, rsync.
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"

say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m warn:\033[0m %s\n' "$*" >&2; }
ask(){ local p="$1" d="${2-}" a; printf '%s%s: ' "$p" "${d:+ [$d]}" >&2; IFS= read -r a </dev/tty || true; printf '%s' "${a:-$d}"; }

mkdir -p "$HOME/.ssh/sockets" "$HOME/.local/bin"; chmod 700 "$HOME/.ssh/sockets"

SSHCFG="$HOME/.ssh/config"
if ! grep -q "^Host hurricane\$" "$SSHCFG" 2>/dev/null; then
  warn "No 'hurricane' alias in ~/.ssh/config."
  echo "  hurricane is NC State MEAS's single-GPU box (hurricane.meas.ncsu.edu)." >&2
  echo "  Its DNS is campus-internal: if the name doesn't resolve for you, pin it" >&2
  echo "  in /etc/hosts (ask the box's admin for the current IP), e.g.:" >&2
  echo "      sudo sh -c 'echo \"<ip-from-the-box-admin>  hurricane.meas.ncsu.edu\" >> /etc/hosts'" >&2
  a="$(ask 'Create the hurricane alias now? [Y/n]' Y)"
  case "$a" in [Nn]*) echo "  skipped hurricane."; exit 1 ;; esac
  U="$(ask 'Your Unity ID on hurricane')"
  [ -n "$U" ] || { echo "  Unity ID required -- skipped hurricane."; exit 1; }
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$SSHCFG"; chmod 600 "$SSHCFG"
  { printf '\n'
    cat <<EOF
# added by ASCEND setup-hurricane.sh ($(date +%F)) -- MEAS hurricane (single-GPU box)
Host hurricane
  HostName hurricane.meas.ncsu.edu
  User $U
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 8h
  ServerAliveInterval 30
  ServerAliveCountMax 4
EOF
  } >> "$SSHCFG"
  say "added 'hurricane' to ~/.ssh/config"
  echo "  For passwordless use, put your key on the box:  ssh-copy-id hurricane"
fi
say "testing the hurricane link..."
if ! ssh -o ConnectTimeout=10 hurricane true 2>/dev/null; then
  warn "cannot reach hurricane non-interactively. On campus? key installed (ssh-copy-id hurricane)?"
  warn "Off campus it needs a jump host -- see docs/INSTALL-ascend-all.txt. Skipped; re-run when 'ssh hurricane true' works."
  exit 1
fi
say "deploying the harness + gpu-local skill to hurricane..."
bash "$HERE/deploy.sh"
ln -sf "$HERE/ascend-hurricane/bin/ascend-hurricane" "$HOME/.local/bin/ascend-hurricane"
say "hurricane ready:  ascend-hurricane --check"
