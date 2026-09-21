#!/usr/bin/env bash
# ASCEND-NCSHARE status line for Claude Code (installed to ~/.claude/ by install.sh,
# wired per-project via .claude/settings.json by the ascend-ncshare launcher).
set -uo pipefail
input=$(cat 2>/dev/null || true)
get() {
  local v=""
  if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
    v=$(printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null)
  fi
  [ -n "$v" ] && [ "$v" != "null" ] && printf '%s' "$v" || printf '%s' "$2"
}
MODEL=$(get '.model.display_name' "")
CCV=$(get '.version' "")
DIR=$(get '.workspace.current_dir' "$PWD")
PCT=$(get '.context_window.used_percentage' "")
C_NAME=$'\033[38;5;31m'; C_DIM=$'\033[38;5;245m'; C_WARN=$'\033[38;5;179m'; C_OFF=$'\033[0m'
line="${C_NAME}Wolfpack ASCEND-NCSHARE${C_OFF}"
[ -n "$MODEL" ] && line="$line ${C_DIM}·${C_OFF} $MODEL"
[ -n "$CCV" ]   && line="$line ${C_DIM}(Claude Code v${CCV})${C_OFF}"
line="$line ${C_DIM}·${C_OFF} ${DIR##*/}"
# Cluster link state: warm socket means an allocation is backing the alias.
if ssh -o BatchMode=yes -O check ncshare-agent >/dev/null 2>&1; then
  line="$line ${C_DIM}· ncshare warm${C_OFF}"
else
  line="$line ${C_DIM}· ncshare cold${C_OFF}"
fi
KB="$HOME/agents/ncshare/ncshare-sync/ascend-home/knowledge/lessons.jsonl"
if [ -s "$KB" ]; then
  N=$(grep -c . "$KB" 2>/dev/null) || N=0
  [ "${N:-0}" -gt 0 ] && line="$line ${C_DIM}· ${N} lessons${C_OFF}"
fi
if [ -n "$PCT" ]; then
  P=${PCT%%.*}
  if [ "${P:-0}" -ge 75 ]; then line="$line ${C_WARN}· ctx ${P}%${C_OFF}"
  else line="$line ${C_DIM}· ctx ${P}%${C_OFF}"; fi
fi
printf '%s\n' "$line"
