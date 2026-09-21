#!/usr/bin/env bash
# Install ASCEND on a compute resource. Site-detecting; normally invoked by a
# resource's deploy.sh rather than by hand.
#
#   ASCEND — Autonomous Scientific Computing Engine for Novel Discovery
#   an AI-powered automation system for scientific computing and discovery
#
#   bash ~/agents/<resource>/deploy.sh    # from the Mac; runs this remotely
#
# Installs into ~/bin, ~/.claude, ~/.ascend and the site scratch root
# (auto-detected: NCShare /work/$USER, Hazel /share/$GROUP/agents). Touches
# nothing else. The knowledge base lives in ~/.ascend: scratch is purged
# after 75 days, and a memory that evaporates is worse than none.
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ---- site detection ---------------------------------------------------------
# NCShare: scratch is /work/$USER (75-day purge), partition "common".
# Hazel (NCSU): scratch is /share/$GROUP/agents (30-day purge), partition
# "compute"; $HOME has a hard 15 GB / 10K-file quota, so nothing big or
# file-heavy (node_modules, conda envs) may live there -- envs and software
# belong in /usr/local/usrapps/$GROUP (writable from LOGIN nodes only).
if [ -n "${ASCEND_SCRATCH:-}" ]; then
  WORK="$ASCEND_SCRATCH"; SHARE="$(dirname "$WORK")"; SITE="custom"; PURGE_DAYS="site-specific"
  DEFAULT_PART="${ASCEND_PARTITION:-common}"
  # ASCEND_HERE=1 (passed by e.g. the hurricane deploy for a no-scheduler box) makes
  # the agent run in place instead of trying to srun/sbatch. Other sites do not pass it.
  IA_PART=""; IA_QOS=""; IA_TIME=""; AGENT_HERE="${ASCEND_HERE:-}"
elif [ -d "/work/${USER}" ]; then
  WORK="/work/${USER}"; SHARE="/work/${USER}"; SITE="ncshare"; PURGE_DAYS=75; DEFAULT_PART="common"
  IA_PART=""; IA_QOS=""; IA_TIME=""; AGENT_HERE=""
elif [ -d /share ]; then
  SITE="hazel"; PURGE_DAYS=30; DEFAULT_PART="compute"; WORK=""
  # Hazel policy: INTERACTIVE jobs (srun/salloc) must use qos short on
  # compute_partners (2 h cap); batch (sbatch) may use any QOS.
  IA_PART="compute_partners"; IA_QOS="short"; IA_TIME="02:00:00"
  # Hazel compute nodes have NO internet egress (verified 2026-09-09, curl
  # exit 28 to api.anthropic.com): the agent runs on the login node.
  AGENT_HERE=1
  # A faculty member's writable dir is /share/$USER; a student added to a
  # faculty project has /share/<project>/$USER (e.g. /share/riverdelta/davidliu).
  # Prefer a dir literally named after the user; the deepest writable match wins.
  SHARE=""
  for c in "/share/$USER" /share/*/"$USER"; do
    [ -d "$c" ] && [ -w "$c" ] && SHARE="$c"
  done
  if [ -z "$SHARE" ]; then   # fall back to a writable group dir
    for g in $(id -Gn); do [ -d "/share/$g" ] && [ -w "/share/$g" ] && { SHARE="/share/$g"; break; }; done
  fi
  if [ -z "$SHARE" ]; then
    echo "ERROR: no writable /share dir found for $USER (tried /share/$USER and /share/*/$USER)." >&2
    echo "       Pass it explicitly:  ASCEND_SCRATCH=/share/<proj>/$USER/agents  bash install.sh" >&2
    exit 1
  fi
  WORK="$SHARE/agents"
else
  echo "ERROR: no scratch root found (/work/\$USER or /share/<group>)." >&2
  echo "       Set ASCEND_SCRATCH=/path/to/scratch and re-run." >&2
  exit 1
fi
BIN="${HOME}/bin"
SKILLS="${HOME}/.claude/skills"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
# PATH-shadow-proof file install: on Hazel, a git-lfs dir on PATH shadows
# coreutils `install` with a self-recursing script (observed 2026-09-09:
# SHLVL fork-bomb). Never call bare `install`.
put() { cp "$2" "$3.tmp.$$" && chmod "$1" "$3.tmp.$$" && mv -f "$3.tmp.$$" "$3"; }
warn() { printf '\033[33m warn:\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------- sanity ---
mkdir -p "$WORK" || { echo "ERROR: cannot create $WORK" >&2; exit 1; }
say "site: $SITE   share: ${SHARE:-?}   scratch: $WORK   (purge: $PURGE_DAYS days)   partition: $DEFAULT_PART"

# Confirm the working directory interactively -- but ONLY on the node's own
# terminal (a real TTY) and when it was NOT already confirmed upstream
# (deploy.sh / the Mac passes ASCEND_SCRATCH, meaning the user already chose).
if [ -z "${ASCEND_SCRATCH_CONFIRMED:-}" ] && [ -z "${ASCEND_SCRATCH:-}" ] && [ "$SITE" = "hazel" ] && [ -t 0 ]; then
  printf 'Your Hazel working directory is detected as: %s\n' "$SHARE"
  printf '  (faculty: /share/<unityID>   student: /share/<project>/<unityID>)\n'
  printf '  Press Enter to use it, or type a different /share path: '
  IFS= read -r _ans || true
  if [ -n "$_ans" ]; then SHARE="$_ans"; WORK="$SHARE/agents"; fi
  say "using: share $SHARE   scratch $WORK"
fi
[ -w "$WORK" ] || { echo "ERROR: $WORK is not writable." >&2; exit 1; }
command -v sbatch >/dev/null || warn "sbatch not on PATH -- is this a login node?"
command -v python3 >/dev/null || { echo "ERROR: python3 not found." >&2; exit 1; }
PYV=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
say "python3 $PYV, user $USER, work $WORK"

# ------------------------------------------------------------- hpcrun ------
say "installing hpcrun -> $BIN/hpcrun"
mkdir -p "$BIN"
put 0755 "$SRC/bin/hpcrun" "$BIN/hpcrun"
say "installing hpcrepro -> $BIN/hpcrepro"
put 0755 "$SRC/bin/hpcrepro" "$BIN/hpcrepro"
say "installing ascend -> $BIN/ascend"
put 0755 "$SRC/bin/ascend" "$BIN/ascend"
say "installing claude-node -> $BIN/claude-node   (legacy alias for ascend)"
put 0755 "$SRC/bin/claude-node" "$BIN/claude-node"
put 0755 "$SRC/bin/fetch-paper" "$BIN/fetch-paper"

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) warn "$BIN is not on PATH. Add to ~/.bashrc:  export PATH=\"\$HOME/bin:\$PATH\"" ;;
esac

# ------------------------------------------------------------- skill -------
# The harness ships the generic skills (repro, paper-fetch). The CLUSTER-SPECIFIC
# hpc-slurm skill lives outside this bundle (ncshare/skills or ncsuhpc/skills on
# the Mac) and is overlaid into $SRC/skills/ by that cluster's deploy.sh before
# this installer runs -- so install every skill dir present here.
say "installing skills -> $SKILLS/ (all of: $(ls "$SRC/skills" | tr '\n' ' '))"
mkdir -p "$SKILLS"
for d in "$SRC"/skills/*/; do
  s="$(basename "$d")"
  rm -rf "$SKILLS/$s"
  cp -R "$d" "$SKILLS/$s"
done
[ -d "$SRC/skills/hpc-slurm" ] || warn "no hpc-slurm skill in this bundle -- deploy.sh should have overlaid the cluster's copy (ncshare/skills or ncsuhpc/skills)"

# ---------------------------------------------------- claude permissions ----
# Without this, Claude Code prompts Yes/No for every single tool call, which
# makes the harness unusable. hpcrun is allow-listed because it enforces its
# OWN gates (validation, budgets, approval) -- the prompt is redundant there.
# Raw sbatch/scancel/srun are denied so the harness cannot be bypassed, and
# the operations that have actually cost this project time -- deletions and
# environment mutation -- still ask.
CSET="${HOME}/.claude/settings.json"
mkdir -p "${HOME}/.claude"
say "configuring Claude Code permissions -> $CSET"
python3 - "$SRC/docs/claude-settings.json" "$CSET" <<'MERGEPY'
import json, os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
new = json.load(open(src))
if not os.path.exists(dst):
    json.dump(new, open(dst, "w"), indent=2)
    print("    wrote a new settings.json")
    raise SystemExit
try:
    cur = json.load(open(dst))
except ValueError as exc:
    shutil.copy(dst, dst + ".bak")
    json.dump(new, open(dst, "w"), indent=2)
    print("    existing settings.json was not valid JSON (%s)" % exc)
    print("    backed it up to settings.json.bak and wrote a fresh one")
    raise SystemExit
shutil.copy(dst, dst + ".bak")
cp = cur.setdefault("permissions", {})
added = 0
for key in ("allow", "ask", "deny"):
    have = cp.setdefault(key, [])
    for rule in new["permissions"][key]:
        if rule not in have:
            have.append(rule); added += 1

# An 'ask' rule beats an 'allow' rule, so a stale 'ask' left over from an
# earlier version silently cancels the allow we just added -- which is exactly
# the "why is it still prompting?" bug. If a rule is allowed now, it cannot
# also be asked about.
allow = set(cp.get("allow", []))
moved = []
for key in ("ask", "deny"):
    keep = []
    for rule in cp.get(key, []):
        if rule in allow and rule not in new["permissions"][key]:
            moved.append("%s: %s" % (key, rule))
        else:
            keep.append(rule)
    cp[key] = keep
if moved:
    print("    removed %d stale rule(s) that were overriding an allow:" % len(moved))
    for m in moved[:12]:
        print("      %s" % m)

want = new["permissions"]["defaultMode"]
have_mode = cp.get("defaultMode")
if have_mode is None:
    cp["defaultMode"] = want
    print("    set defaultMode = %s" % want)
elif have_mode == "acceptEdits" and want != "acceptEdits":
    # acceptEdits is what earlier versions of this bundle shipped, and it still
    # prompts for every Bash command. Upgrade it rather than leaving the user
    # with the setting that caused the complaint.
    cp["defaultMode"] = want
    print("    upgraded defaultMode: acceptEdits -> %s" % want)
    print("    (acceptEdits auto-approves file edits but still asks for every"
          " shell command)")
elif have_mode != want:
    print("    kept your defaultMode = %s (bundle suggests %s)"
          % (have_mode, want))

json.dump(cur, open(dst, "w"), indent=2)
print("    merged %d new rules (previous file saved as settings.json.bak)" % added)
MERGEPY

# ------------------------------------------------------------- dirs --------
say "creating work directories"
mkdir -p "$WORK/tmp" "$WORK/.pipcache" "$WORK/agent-workspaces" "$WORK/agent-projects"

# ------------------------------------------------------- knowledge base -----
# NOT on scratch. This is the one thing that must outlive the scratch purge.
ASCEND="${ASCEND_HOME:-$HOME/.ascend}"
say "knowledge base -> $ASCEND/knowledge   (survives the scratch purge)"
mkdir -p "$ASCEND/knowledge" "$ASCEND/tools"
touch "$ASCEND/knowledge/lessons.jsonl"

# Display name for the status line. A resource's deploy.sh can name itself with
# ASCEND_SITE_NAME; otherwise derive it from the detected site, falling back to
# the box's own hostname so two workstations are never both just "ASCEND".
if [ -n "${ASCEND_SITE_NAME:-}" ]; then
  SITE_NAME="$ASCEND_SITE_NAME"
else
  case "$SITE" in
    ncshare) SITE_NAME="ASCEND-NCSHARE" ;;
    hazel)   SITE_NAME="ASCEND-VCL" ;;
    *)       SITE_NAME="ASCEND-$(hostname -s 2>/dev/null | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9-')" ;;
  esac
  [ "$SITE_NAME" = "ASCEND-" ] && SITE_NAME="ASCEND"
fi
printf '%s\n' "$SITE_NAME" > "$ASCEND/site-name"
if [ -s "$ASCEND/knowledge/lessons.jsonl" ]; then
  say "  carrying forward $(grep -c . "$ASCEND/knowledge/lessons.jsonl") lesson(s) from earlier projects"
fi

# --------------------------------------------------------- status line ------
# Claude Code's startup banner cannot be replaced, but the status line can --
# and unlike the banner it stays on screen all session.
say "installing status line -> ${HOME}/.claude/ascend-statusline.sh  (name: $SITE_NAME)"
put 0755 "$SRC/docs/statusline.sh" "${HOME}/.claude/ascend-statusline.sh"
python3 - "$CSET" <<'SLPY'
import json, os, sys
dst = sys.argv[1]
try:
    cur = json.load(open(dst))
except Exception:
    cur = {}
sl = cur.get("statusLine")
if isinstance(sl, dict) and sl.get("command") and    "ascend-statusline" not in str(sl.get("command")):
    print("    kept your existing statusLine (%s)" % sl.get("command"))
else:
    cur["statusLine"] = {"type": "command",
                         "command": "~/.claude/ascend-statusline.sh",
                         "padding": 0}
    json.dump(cur, open(dst, "w"), indent=2)
    print("    statusLine set to the ASCEND line")
SLPY

# -------------------------------------------------------- shell profile ----
MARK="# >>> hpc-agent >>>"
if ! grep -qF "$MARK" "${HOME}/.bashrc" 2>/dev/null; then
  say "appending environment block to ~/.bashrc"
  cat >> "${HOME}/.bashrc" <<EOF

$MARK
# Keep pip's temp and cache off the ~31 GB root partition.
export TMPDIR="$WORK/tmp"
export PIP_TMPDIR="$WORK/tmp"
export PIP_CACHE_DIR="$WORK/.pipcache"
export HPCRUN_ROOT="$WORK/agent-workspaces"
export HPCREPRO_ROOT="$WORK/agent-projects"
export ASCEND_SCRATCH="$WORK"
export ASCEND_SHARE="$SHARE"
export ASCEND_PARTITION="$DEFAULT_PART"
$( [ -n "$IA_PART" ] && printf 'export ASCEND_INTERACTIVE_PARTITION="%s"\nexport ASCEND_INTERACTIVE_QOS="%s"\nexport ASCEND_TIME="%s"' "$IA_PART" "$IA_QOS" "$IA_TIME" )
$( [ -n "$AGENT_HERE" ] && printf 'export ASCEND_HERE=%s   # agent on login node: compute nodes have no egress' "$AGENT_HERE" )
export ASCEND_HOME="\$HOME/.ascend"
export PATH="\$HOME/bin:\$PATH"
# <<< hpc-agent <<<
EOF
else
  say "~/.bashrc already has the hpc-agent block; leaving it alone"
  # Upgrades from before hpcrepro existed have no HPCREPRO_ROOT line. Nothing
  # breaks -- hpcrepro's own default is the same path -- so this is a note,
  # not a warning, and the block is not rewritten under the user.
  if ! grep -q 'HPCREPRO_ROOT' "${HOME}/.bashrc" 2>/dev/null; then
    say "  (no HPCREPRO_ROOT in it; hpcrepro defaults to the same"
    say "   $WORK/agent-projects, so there is nothing to do)"
  fi
fi

if grep -q 'conda activate' "${HOME}/.bashrc" 2>/dev/null; then
  warn "~/.bashrc auto-activates a conda env. That re-activates AFTER a"
  warn "script's own 'conda activate' inside 'bash -lc' and silently swaps"
  warn "the interpreter. Check:  grep 'conda activate' ~/.bashrc"
fi

# -------------------------------------------------------------- pilot ------
say "staging pilots -> $WORK/agent-pilot"
mkdir -p "$WORK/agent-pilot"
cp -R "$SRC/pilot/smoke" "$WORK/agent-pilot/"
cp -R "$SRC/pilot/regional_gs" "$WORK/agent-pilot/"

# CLAUDE.md is the working agreement and the user may well have edited it.
# Never silently overwrite an edited copy.
if [ ! -f "$WORK/CLAUDE.md" ]; then
  cp "$SRC/docs/CLAUDE.md" "$WORK/CLAUDE.md"
  say "wrote $WORK/CLAUDE.md"
elif cmp -s "$SRC/docs/CLAUDE.md" "$WORK/CLAUDE.md"; then
  : # identical, nothing to do
else
  cp "$SRC/docs/CLAUDE.md" "$WORK/CLAUDE.md.new"
  warn "$WORK/CLAUDE.md differs from the bundled version and was NOT changed."
  warn "The new one is at $WORK/CLAUDE.md.new -- diff and merge if you want it."
fi

# --------------------------------------------------------------- probe -----
export HPCRUN_ROOT="$WORK/agent-workspaces"
say "probing the cluster"
if "$BIN/hpcrun" site --probe > /tmp/hpcrun_probe.$$ 2>&1; then
  python3 - "$WORK/agent-workspaces/site.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
print("    scheduler : %s" % s.get("scheduler"))
print("    partitions: %s" % (", ".join(p["partition"] for p in s.get("partitions", [])) or "(none)"))
accts = sorted({a["account"] for a in s.get("accounts", []) if a.get("account")})
print("    accounts  : %s" % (", ".join(accts) or "(none found)"))
print("    container : %s" % (s.get("container_runtime") or "(none)"))
print("    NCShare   : %s" % ("recognized" if s.get("known_site", {}).get("matched") else "not matched"))
PY
else
  warn "site probe failed; see /tmp/hpcrun_probe.$$"
fi

# ------------------------------------------------------------- claude ------
echo
if [ -n "${ANTHROPIC_API_KEY:-}" ] && [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  warn "BOTH ANTHROPIC_API_KEY and CLAUDE_CODE_OAUTH_TOKEN are set."
  warn "The API key WINS, so you are billing per token despite having a"
  warn "subscription token. Unset ANTHROPIC_API_KEY and check with /status."
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  warn "ANTHROPIC_API_KEY is set -- Claude Code will bill per token."
  warn "If you pay for Claude Pro/Max, that plan already covers Claude Code:"
  warn "run 'claude setup-token' on a machine with a browser and export"
  warn "CLAUDE_CODE_OAUTH_TOKEN here instead. Verify with /status."
fi
if command -v claude >/dev/null 2>&1; then
  say "Claude Code found: $(command -v claude)"
else
  say "Claude Code is NOT installed. To install it:"
  cat <<'EOF'

    Claude Code needs Node 18+. Keep it OUT of your conda base env -- put it
    in a small dedicated env so base stays clean:

        conda create -n claude -c conda-forge 'nodejs>=20' -y
        conda activate claude
        npm install -g @anthropic-ai/claude-code

    (NCShare has no module system -- conda is the only option here.)

    Where to put it depends on the site:
      NCShare -> $HOME (NOT /work -- purged after 75 days); no module system,
                 conda is the only option.
      Hazel   -> $HOME has a 15 GB / 10K-FILE quota. npm's node_modules would
                 blow the file quota, so EITHER use the native installer
                 (single binary, quota-friendly, installs to ~/.local/bin):
                     curl -fsSL https://claude.ai/install.sh | bash
                 OR put node+npm under /usr/local/usrapps/<group>/ (writable
                 from login nodes only) and npm install there.
        export NPM_CONFIG_PREFIX="$HOME/.npm-global"
        export PATH="$HOME/.npm-global/bin:$PATH"

    AUTHENTICATION -- read this before setting an API key.

    If you already pay for Claude Pro or Max, that subscription covers Claude
    Code and you should NOT use an API key here. ANTHROPIC_API_KEY silently
    OVERRIDES subscription auth, so setting it means paying per token on top
    of a plan you already have.

    /login needs a browser callback, which does not work over SSH. Use the
    headless flow instead:

        # on your laptop, which has a browser:
        claude setup-token          # approve, copy the one-year token

        # here, on the cluster:
        mkdir -p ~/.config/anthropic
        cat > ~/.config/anthropic/oauth-token    # paste, then Ctrl-D
        chmod 600 ~/.config/anthropic/oauth-token
        # in ~/.bashrc:
        export CLAUDE_CODE_OAUTH_TOKEN="$(cat ~/.config/anthropic/oauth-token)"

    Then check with /status -- it should show a "Login method" row, not an
    "API key" row.

    Only if you have no subscription, use an API key the same careful way
    (file at mode 600, never typed on the command line where it lands in
    ~/.bash_history):

        printf '%s' 'sk-ant-...' > ~/.config/anthropic/key
        chmod 600 ~/.config/anthropic/key
        export ANTHROPIC_API_KEY="$(cat ~/.config/anthropic/key)"

    Your home directory is group-readable on NCShare, so mode 600 matters --
    a one-year OAuth token is worth more than a rotatable API key.
EOF
fi

cat <<EOF

$(printf '\033[1m==>\033[0m') ASCEND installed.

  ascend      -> $BIN/ascend
                 the front door. Claims a compute node and starts the agent.
  hpcrun      -> $BIN/hpcrun
                 submit / diagnose / iterate on Slurm jobs
  hpcrepro    -> $BIN/hpcrepro
                 reproduce a paper or a repo, with a claims ledger, and
                 learn from it so the next project starts further along
  skills      -> $SKILLS/{hpc-slurm,repro,paper-fetch}
  status line -> ${HOME}/.claude/ascend-statusline.sh
  perms       -> ${HOME}/.claude/settings.json  (stops the Yes/No prompting)
  memory      -> $ASCEND/knowledge   (in \$HOME -- it must outlive the scratch purge)
  workspaces  -> $WORK/agent-workspaces
  projects    -> $WORK/agent-projects
  pilots      -> $WORK/agent-pilot/{smoke,regional_gs}

Next:  source ~/.bashrc
       bash $SRC/pilot/run_smoke.sh     # verify against the real cluster
       ascend                           # then start working

Note: Claude Code's own startup banner cannot be replaced -- there is no
setting for it. ASCEND prints above it, and the status line carries the
name for the rest of the session, which is the part that stays on screen.

EOF
