#!/usr/bin/env bash
# warm-link.sh -- shared setup helper: get a multiplexed ssh link warm.
# Instead of telling the user "open another terminal and run ssh <alias>",
# it OFFERS TO OPEN that terminal automatically (macOS Terminal.app, Linux
# GUI terminals, WSL -> Windows Terminal / cmd), runs `ssh <alias>` in it so
# the user only types password/Duo there, and polls until the master socket
# is warm. Manual instructions remain as the fallback everywhere.
# Sourced by the setup scripts. bash 3.2 (macOS) safe: no arrays.
#   warm_link <alias> [note-line]   -> returns 0 once the link is warm

wl_ask(){ local p="$1" d="${2-}" a; printf '%s%s: ' "$p" "${d:+ [$d]}" >&2; IFS= read -r a </dev/tty 2>/dev/null || true; printf '%s' "${a:-$d}"; }
wl_say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }

wl_is_warm(){
  ssh -o BatchMode=yes -O check "$1" >/dev/null 2>&1 && return 0
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$1" true >/dev/null 2>&1
}

# wl_open_terminal <command> : open a NEW terminal window running <command>.
# Returns 0 only if a window was (apparently) launched.
wl_open_terminal(){
  local cmd="$1" t
  case "$(uname -s)" in
    Darwin)
      osascript >/dev/null 2>&1 <<EOT
tell application "Terminal"
    activate
    do script "$cmd"
end tell
EOT
      return $? ;;
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        # WSL: open a Windows-side terminal that drops back into this distro
        if command -v wt.exe >/dev/null 2>&1; then
          ( cd /mnt/c 2>/dev/null || cd /; wt.exe wsl.exe -e bash -lc "$cmd" ) >/dev/null 2>&1 && return 0
        fi
        if command -v cmd.exe >/dev/null 2>&1; then
          ( cd /mnt/c 2>/dev/null || cd /; cmd.exe /c start "" wsl.exe -e bash -lc "$cmd" ) >/dev/null 2>&1 && return 0
        fi
        return 1
      fi
      [ -n "${DISPLAY-}${WAYLAND_DISPLAY-}" ] || return 1
      for t in x-terminal-emulator gnome-terminal konsole xfce4-terminal xterm; do
        command -v "$t" >/dev/null 2>&1 || continue
        case "$t" in
          gnome-terminal) "$t" -- bash -lc "$cmd; exec bash" >/dev/null 2>&1 & ;;
          *)              "$t" -e  bash -lc "$cmd; exec bash" >/dev/null 2>&1 & ;;
        esac
        return 0
      done
      return 1 ;;
    *) return 1 ;;
  esac
}

warm_link(){
  local al="$1" note="${2-}" a i
  if wl_is_warm "$al"; then wl_say "'$al' link is warm."; return 0; fi
  echo >&2
  echo "  The '$al' link needs one interactive login (password/Duo) in its own terminal." >&2
  [ -n "$note" ] && echo "  $note" >&2
  a="$(wl_ask "  Open a new terminal running 'ssh $al' for you now?" Y)"
  case "$a" in
    [Nn]*) : ;;
    *)
      if wl_open_terminal "ssh $al"; then
        echo "  A new terminal window is opening -- complete the password/Duo prompt THERE." >&2
        echo "  (Once you see the far-side shell you can close that window; the link stays warm.)" >&2
        printf '  waiting for the link to come up ' >&2
        i=0
        while [ "$i" -lt 100 ]; do
          if ssh -o BatchMode=yes -O check "$al" >/dev/null 2>&1; then
            printf '\n' >&2; wl_say "'$al' link is warm."; return 0
          fi
          printf '.' >&2; sleep 3; i=$((i+1))
        done
        printf '\n' >&2
        echo "  (still cold after ~5 minutes -- falling back to the manual steps)" >&2
      else
        echo "  Couldn't open a terminal window automatically here -- some Mac" >&2
        echo "  terminal apps (iTerm2 etc.) need Automation permission to control" >&2
        echo "  Terminal.app. Terminal.app itself always works, so try running this" >&2
        echo "  from Terminal instead. Or, just authenticate by hand:" >&2
      fi ;;
  esac
  echo "  1. Open a new terminal window" >&2
  echo "  2. Run:  ssh $al" >&2
  echo "  3. Enter your password, then approve Duo" >&2
  echo "  4. Once you see a shell prompt on the far side, come back to THIS terminal" >&2
  echo "  5. Press Enter below" >&2
  wl_ask '  Press Enter here once that is done' >/dev/null
  if wl_is_warm "$al"; then wl_say "'$al' link is warm."; return 0; fi
  return 1
}
