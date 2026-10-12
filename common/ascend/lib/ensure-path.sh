#!/usr/bin/env bash
# ascend_ensure_path -- make ~/.local/bin available PERMANENTLY, not just warn.
# Appends one guarded export line to the user's shell rc file (zsh / bash /
# other) unless that file already mentions .local/bin, then -- since a script
# can never alter its parent shell -- prints the one command that activates it
# in the current terminal. Safe to call repeatedly (idempotent). bash-3.2 safe.
ascend_ensure_path(){
  local rc line='export PATH="$HOME/.local/bin:$PATH"'
  case "${SHELL##*/}" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) if [ "$(uname -s)" = Darwin ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
    *)    rc="$HOME/.profile" ;;
  esac
  if ! grep -qs '\.local/bin' "$rc"; then
    printf '\n# added by the ASCEND installer -- ascend commands live in ~/.local/bin\n%s\n' "$line" >> "$rc"
    printf '\033[1m==>\033[0m added ~/.local/bin to PATH in %s\n' "${rc/#$HOME/\~}"
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) printf '\033[1m==>\033[0m to use the ascend commands in THIS terminal:  source %s   (new terminals pick it up automatically)\n' "${rc/#$HOME/\~}" ;;
  esac
}
