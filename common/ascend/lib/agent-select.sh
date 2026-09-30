#!/usr/bin/env bash
# agent-select.sh -- shared ASCEND helper: choose the AI agent CLI.
#
# ASCEND can drive either Claude Code (Anthropic, the default) or Codex
# (OpenAI). Both read the same AGENTS.md project instructions and both run
# over the same multiplexed ~/.ssh/config aliases, so the choice is purely
# which CLI does the reasoning.
#
# Usage from a launcher (after the banner has printed):
#     . "<path>/agent-select.sh"
#     agent_select <site-slug> "$AGENT_CHOICE"   # "" | claude | codex
#     agent_ensure_local                          # for laptop-run agents
#     LABEL="$(agent_version_label)"              # e.g. "Claude Code v2.1.270"
#
# The choice is asked EVERY launch (nothing is remembered). Resolution order:
#   1. explicit flag  (--claude / --codex)  -- skips the question
#   2. ASCEND_AGENT_DEFAULT env var (claude|codex) -- for scripting
#   3. interactive prompt (tty)
#   4. claude (non-interactive: never block)
#
# The prompt shows each CLI's install status. The optional 3rd argument to
# agent_select says where to check: "local" (default, this computer),
# "remote:<ssh-alias>" (one combined ssh call -- for arrangements where the
# agent runs on the remote), or "none" (no status lines).
#
# Written for macOS bash 3.2 (no arrays, no ${var,,}).

ASCEND_AGENT="claude"
ASCEND_AGENT_LABEL="Claude Code"
CLAUDE_INSTALL_CMD='curl -fsSL https://claude.ai/install.sh | bash'
CODEX_INSTALL_CMD='curl -fsSL https://chatgpt.com/codex/install.sh | sh'

_agent_set() {
  case "$1" in
    codex)  ASCEND_AGENT="codex";  ASCEND_AGENT_LABEL="Codex" ;;
    *)      ASCEND_AGENT="claude"; ASCEND_AGENT_LABEL="Claude Code" ;;
  esac
}

# Turn a raw `<cli> --version` line into a status tag for the menu.
_agent_fmt_status() {
  if [ -n "$1" ]; then
    _as_v="$(printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -n "$_as_v" ]; then printf 'v%s installed — ready to use' "$_as_v"
    else printf 'installed — ready to use'; fi
  else
    printf 'not installed — we can install it for you'
  fi
}

agent_select() {
  _as_site="$1"; _as_choice="${2:-}"; _as_where="${3:-local}"
  case "$_as_choice" in claude|codex) : ;; *) _as_choice="" ;; esac
  if [ -z "$_as_choice" ]; then
    case "${ASCEND_AGENT_DEFAULT:-}" in claude|codex) _as_choice="$ASCEND_AGENT_DEFAULT" ;; esac
  fi
  if [ -z "$_as_choice" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      # install status for each CLI (checked where the agent will actually run)
      _as_cst=""; _as_xst=""
      case "$_as_where" in
        local)
          case ":$PATH:" in *:"$HOME/.local/bin":*) : ;; *) PATH="$HOME/.local/bin:$PATH"; export PATH ;; esac
          _as_c=""; command -v claude >/dev/null 2>&1 && _as_c="$(claude --version 2>/dev/null | head -1)" && : "${_as_c:=installed}"
          _as_x=""; command -v codex  >/dev/null 2>&1 && _as_x="$(codex --version 2>/dev/null | head -1)" && : "${_as_x:=installed}"
          _as_cst="  [$(_agent_fmt_status "$_as_c")]"
          _as_xst="  [$(_agent_fmt_status "$_as_x")]"
          ;;
        remote:*)
          _as_r="${_as_where#remote:}"
          _as_out="$(ssh -o BatchMode=yes "$_as_r" "bash -lc 'claude --version 2>/dev/null | head -1; echo @@ASCEND@@; codex --version 2>/dev/null | head -1'" 2>/dev/null || true)"
          if printf '%s' "$_as_out" | grep -q '@@ASCEND@@'; then
            _as_c="$(printf '%s\n' "$_as_out" | sed '/@@ASCEND@@/,$d' | head -1)"
            _as_x="$(printf '%s\n' "$_as_out" | sed '1,/@@ASCEND@@/d' | head -1)"
            _as_cst="  [$(_agent_fmt_status "$_as_c") on $_as_r]"
            _as_xst="  [$(_agent_fmt_status "$_as_x") on $_as_r]"
          fi
          ;;
      esac
      echo "    Which AI agent for this session?"
      echo "      1) Claude Code  (Anthropic)$_as_cst"
      echo "      2) Codex        (OpenAI)   $_as_xst"
      printf '    Choose [1/2]: '
      read -r _as_ans || _as_ans=""
      case "$_as_ans" in
        2|codex|Codex|CODEX) _as_choice="codex" ;;
        *)                   _as_choice="claude" ;;
      esac
    else
      _as_choice="claude"   # non-interactive: never block
    fi
  fi
  _agent_set "$_as_choice"
}


# Ensure the chosen CLI exists on THIS computer (laptop-run arrangements).
# Offers the official installer when it is missing and we have a tty.
agent_ensure_local() {
  command -v "$ASCEND_AGENT" >/dev/null 2>&1 && return 0
  case ":$PATH:" in
    *:"$HOME/.local/bin":*) : ;;
    *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
  esac
  command -v "$ASCEND_AGENT" >/dev/null 2>&1 && return 0
  if [ "$ASCEND_AGENT" = "codex" ]; then _as_inst="$CODEX_INSTALL_CMD"; else _as_inst="$CLAUDE_INSTALL_CMD"; fi
  echo "$ASCEND_AGENT is not on PATH -- the $ASCEND_AGENT_LABEL CLI is needed on this computer." >&2
  if [ -t 0 ] && [ -t 1 ]; then
    printf 'Install it now?  (%s)  [Y/n]: ' "$_as_inst"
    read -r _as_a || _as_a=""
    case "$_as_a" in
      n|N|no|NO|No) : ;;
      *)
        sh -c "$_as_inst" || true
        hash -r 2>/dev/null || true
        if command -v "$ASCEND_AGENT" >/dev/null 2>&1; then
          echo "$ASCEND_AGENT_LABEL installed. If this is its first run, it will walk you through login."
          return 0
        fi
        ;;
    esac
  fi
  echo "Install $ASCEND_AGENT_LABEL yourself first:   $_as_inst" >&2
  echo "Then run it once to log in, and re-run this launcher." >&2
  echo "(Or launch with the other agent:  --claude / --codex)" >&2
  exit 1
}

agent_version_label() {
  _as_v="$("$ASCEND_AGENT" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [ -n "$_as_v" ]; then printf '%s v%s' "$ASCEND_AGENT_LABEL" "$_as_v"; else printf '%s' "$ASCEND_AGENT_LABEL"; fi
}
