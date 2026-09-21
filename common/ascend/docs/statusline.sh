#!/usr/bin/env bash
# ASCEND status line for Claude Code.
#
# Claude Code's startup banner cannot be replaced, but the status line can, and
# unlike the banner it stays on screen for the whole session. This is where the
# system's name actually lives.
#
# Installed by install.sh and wired into ~/.claude/settings.json as:
#   "statusLine": { "type": "command", "command": "~/.claude/ascend-statusline.sh" }
#
# Claude Code pipes a JSON blob in on stdin; every field is read defensively so
# a schema change degrades to a plainer line rather than an error.
set -uo pipefail

input=$(cat 2>/dev/null || true)

get() {  # get <jq-path> <fallback>
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

C_NAME=$'\033[38;5;31m'      # deep blue
C_DIM=$'\033[38;5;245m'
C_WARN=$'\033[38;5;179m'
C_OFF=$'\033[0m'

# The system's display name. Set per-resource at install time so the line says
# where you actually are: ASCEND-HURRICANE, ASCEND-VCL, ASCEND-NCSHARE ...
# Order: explicit env override > the file install.sh wrote > plain "ASCEND".
NAME="${ASCEND_NAME:-}"
if [ -z "$NAME" ]; then
  SF="${ASCEND_HOME:-$HOME/.ascend}/site-name"
  [ -r "$SF" ] && NAME=$(head -1 "$SF" 2>/dev/null | tr -d '\r\n')
fi
NAME="${NAME:-ASCEND}"

line="${C_NAME}${NAME}${C_OFF}"
[ -n "$MODEL" ] && line="$line ${C_DIM}·${C_OFF} $MODEL"
[ -n "$CCV" ]   && line="$line ${C_DIM}(Claude Code v${CCV})${C_OFF}"
line="$line ${C_DIM}·${C_OFF} ${DIR##*/}"

# Slurm context, when there is any — which node you are on matters here.
if [ -n "${SLURM_JOB_ID:-}" ]; then
  line="$line ${C_DIM}· job ${SLURM_JOB_ID} on $(hostname -s 2>/dev/null)${C_OFF}"
fi

# Accumulated memory: the count is the point of the learning loop being real.
KB="${ASCEND_HOME:-$HOME/.ascend}/knowledge/lessons.jsonl"
if [ -s "$KB" ]; then
  N=$(grep -c . "$KB" 2>/dev/null) || N=0
  [ "${N:-0}" -gt 0 ] && line="$line ${C_DIM}· ${N} lessons${C_OFF}"
fi

# Context pressure is worth seeing before it bites mid-task.
if [ -n "$PCT" ]; then
  P=${PCT%%.*}
  if [ "${P:-0}" -ge 75 ]; then
    line="$line ${C_WARN}· ctx ${P}%${C_OFF}"
  else
    line="$line ${C_DIM}· ctx ${P}%${C_OFF}"
  fi
fi

printf '%s\n' "$line"
