#!/usr/bin/env bash
# ASCEND CUSTOM-SITE setup -- link YOUR OWN HPC or workstation to ASCEND:
# a Slurm cluster at any campus (UNC, Duke, anywhere) or another GPU/CPU box.
# The agent runs on the remote (login node or box) over a multiplexed ssh
# alias; this wizard:
#   1. sets up (or reuses) the ssh alias with connection multiplexing
#   2. detects what the site is (Slurm cluster / GPU workstation / CPU box)
#   3. optionally takes the site's user guide or policy docs -- the agent reads
#      them plus a live probe on its first session and writes the site profile
#   4. deploys the ASCEND harness + the matching generic skill to the remote
#   5. generates an `ascend-<site>` launcher and registers the site so the
#      `ascend-all` router can route jobs to it
# Runs on macOS, Linux, and Windows via WSL. Requires: bash, ssh, rsync.
# Re-run any time to add more sites or update one (same name = update).
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"

say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m warn:\033[0m %s\n' "$*" >&2; }
die(){ printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
ask(){ local p="$1" d="${2-}" a; printf '%s%s: ' "$p" "${d:+ [$d]}" >&2; IFS= read -r a </dev/tty || true; printf '%s' "${a:-$d}"; }

for t in ssh rsync python3; do command -v "$t" >/dev/null || die "missing '$t' -- install it and re-run."; done
mkdir -p "$HOME/.ssh/sockets" "$HOME/.local/bin" "$HOME/.ascend/sites"; chmod 700 "$HOME/.ssh/sockets"

# warm-link helper (auto-opens a terminal for the one interactive login)
[ -f "$ROOT/common/ascend/lib/warm-link.sh" ] && . "$ROOT/common/ascend/lib/warm-link.sh" || true

echo
say "Link your own HPC or workstation to ASCEND"
echo "   Examples: UNC Longleaf, Duke DCC, a lab GPU server, a cloud VM."
echo "   You need: an account there, and ssh access from this computer."
echo

# ---- 1. site name -------------------------------------------------------------
while :; do
  SITE="$(ask 'Short name for this site (letters/digits/dashes, e.g. longleaf, dcc, lab-box)')"
  SITE="$(printf '%s' "$SITE" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  [ -n "$SITE" ] || { echo "  a name is required."; continue; }
  case "$SITE" in
    hazel|ncshare|hurricane|vcl|all|probe|local|router|custom)
      echo "  '$SITE' is reserved -- pick another name."; continue ;;
  esac
  break
done
SITELABEL="$(printf '%s' "$SITE" | tr '[:lower:]' '[:upper:]')"
SITEVAR="$(printf '%s' "$SITELABEL" | tr '-' '_')"

# ---- 2. ssh alias -------------------------------------------------------------
SSHCFG="$HOME/.ssh/config"
DEFALIAS="$SITE"
ALIAS="$(ask "ssh alias for the site (existing alias, or new one to create)" "$DEFALIAS")"
if ssh -G "$ALIAS" 2>/dev/null | grep -q '^hostname ' && grep -qE "^Host[[:space:]]+.*\b$ALIAS\b" "$SSHCFG" 2>/dev/null; then
  say "using existing ssh alias '$ALIAS'"
else
  HOSTN="$(ask "Remote hostname (e.g. longleaf.unc.edu, dcc-login.oit.duke.edu)")"
  [ -n "$HOSTN" ] || die "hostname required."
  U="$(ask "Your username on $HOSTN")"
  [ -n "$U" ] || die "username required."
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$SSHCFG"; chmod 600 "$SSHCFG"
  { printf '\n'
    cat <<EOF
# added by ASCEND setup-custom.sh ($(date +%F)) -- custom site '$SITE'
Host $ALIAS
  HostName $HOSTN
  User $U
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 8h
  ServerAliveInterval 30
  ServerAliveCountMax 4
EOF
  } >> "$SSHCFG"
  say "added '$ALIAS' to ~/.ssh/config (multiplexed: one login, then hours of reuse)"
  echo "  For passwordless use, put your key on the site:  ssh-copy-id $ALIAS"
fi

# ---- 3. warm + test the link --------------------------------------------------
say "testing the link to '$ALIAS'..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$ALIAS" true 2>/dev/null; then
  if command -v warm_link >/dev/null 2>&1 || type warm_link >/dev/null 2>&1; then
    warm_link "$ALIAS" "log in once (password/Duo if the site uses it); the multiplexed link then stays warm" \
      || die "could not warm the link. Get 'ssh $ALIAS true' working, then re-run."
  else
    warn "cannot reach '$ALIAS' non-interactively."
    echo "  In ANOTHER terminal run:  ssh $ALIAS true   (log in once), then press Enter here." >&2
    ask 'Press Enter when done' >/dev/null
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$ALIAS" true 2>/dev/null \
      || die "still can't reach '$ALIAS'. Get 'ssh $ALIAS true' working (ssh-copy-id $ALIAS helps), then re-run."
  fi
fi
say "link is up."

# ---- 4. detect what the site is ----------------------------------------------
say "probing what kind of site this is..."
DETECT="$(ssh -o BatchMode=yes "$ALIAS" 'command -v sinfo >/dev/null 2>&1 && echo slurm && exit; command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 && echo gpu && exit; echo cpu' 2>/dev/null | tail -1)"
case "$DETECT" in slurm|gpu|cpu) : ;; *) DETECT=cpu ;; esac
case "$DETECT" in
  slurm) echo "   detected: Slurm cluster (sinfo present) -- ASCEND will schedule via hpcrun/sbatch" ;;
  gpu)   echo "   detected: GPU workstation, no scheduler (nvidia-smi present) -- work runs in place" ;;
  cpu)   echo "   detected: no scheduler, no GPU -- CPU box; work runs in place" ;;
esac
K="$(ask 'Site kind [slurm/gpu/cpu]' "$DETECT")"
case "$K" in slurm|gpu|cpu) KIND="$K" ;; *) KIND="$DETECT" ;; esac
case "$KIND" in
  slurm) KINDDESC="Slurm cluster, agent on the login node" ;;
  gpu)   KINDDESC="GPU workstation, no scheduler" ;;
  cpu)   KINDDESC="CPU box, no scheduler" ;;
esac

# ---- 5. site docs (optional but recommended) ----------------------------------
SITED="$HOME/.ascend/sites/$SITE"
REFS="$SITED/references"
mkdir -p "$REFS"
echo
echo "Site documentation (recommended): the agent reads these on its FIRST"
echo "session there -- together with a live probe -- and writes the site profile"
echo "(partitions, QOS/wall-time limits, storage + purge rules, login-node"
echo "etiquette). Without docs it relies on probing alone, which still works."
while :; do
  D="$(ask 'User-guide/policy doc: URL, local file/folder path, or Enter to finish' '')"
  [ -n "$D" ] || break
  case "$D" in
    http://*|https://*)
      F="$REFS/$(printf '%s' "$D" | sed 's|[^A-Za-z0-9._-]|_|g' | tail -c 80).html"
      if command -v curl >/dev/null && curl -fsSL --max-time 60 "$D" -o "$F"; then
        echo "   saved: $(basename "$F")"
      else
        warn "could not fetch $D -- skipped (you can copy docs into $REFS later)"
      fi ;;
    *)
      P="${D/#\~/$HOME}"
      if [ -d "$P" ]; then cp -R "$P/." "$REFS/" && echo "   copied folder."
      elif [ -f "$P" ]; then cp "$P" "$REFS/" && echo "   copied: $(basename "$P")"
      else warn "no such file or folder: $D -- skipped"; fi ;;
  esac
done

# ---- 6. deploy the harness + skill to the remote ------------------------------
say "deploying the ASCEND harness to '$ALIAS'..."
bash "$HERE/deploy-custom.sh" "$SITE" "$ALIAS" "$KIND" "$REFS"

# ---- 7. generate the launcher --------------------------------------------------
mkdir -p "$SITED/bin"
sed -e "s|@@SITE@@|$SITE|g" \
    -e "s|@@SITELABEL@@|$SITELABEL|g" \
    -e "s|@@SITEVAR@@|$SITEVAR|g" \
    -e "s|@@REMOTE@@|$ALIAS|g" \
    -e "s|@@KIND@@|$KIND|g" \
    -e "s|@@KINDDESC@@|$KINDDESC|g" \
    "$HERE/templates/ascend-site.tpl" > "$SITED/bin/ascend-$SITE"
chmod +x "$SITED/bin/ascend-$SITE"
if [ ! -f "$SITED/AGENTS.md" ]; then
  cat > "$SITED/AGENTS.md" <<EOF
# ASCEND project on $SITE ($KINDDESC)

- This is a custom ASCEND site. Site facts live in the '$([ "$KIND" = slurm ] && echo hpc-slurm || echo gpu-local)'
  skill: read its references/ (site docs + site-profile.md) before assuming
  partitions, limits, GPUs, or storage rules.
- Use ~/bin/hpcrun for scheduled/heavy work; keep provenance; one heavy job at
  a time until the site's behavior is understood.
- Respect the site's own acceptable-use policy.
EOF
fi
ln -sf "$SITED/bin/ascend-$SITE" "$HOME/.local/bin/ascend-$SITE"
say "launcher installed:  ascend-$SITE"

# ---- 8. register with the router ----------------------------------------------
python3 - "$SITE" "$ALIAS" "$KIND" "$KINDDESC" <<'PY'
import json, os, sys, datetime
site, alias, kind, desc = sys.argv[1:5]
p = os.path.expanduser("~/.ascend/sites.json")
try:
    reg = json.load(open(p))
    assert isinstance(reg, dict)
except Exception:
    reg = {}
reg[site] = {"remote": alias, "kind": kind, "desc": desc,
             "added": datetime.date.today().isoformat()}
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(reg, open(p, "w"), indent=1)
print(f"   registered '{site}' in ~/.ascend/sites.json (the ascend-all router now includes it)")
PY

echo
say "done. Verify from a NEW terminal:   ascend-$SITE --check"
echo "   Launch on it directly:            ascend-$SITE"
echo "   Or let the router pick:           ascend-all \"describe your job\""
case "$KIND" in slurm)
  echo "   First session tip: ask the agent to 'read the site docs and probe the"
  echo "   cluster, then write references/site-profile.md' -- after that it knows"
  echo "   this site's partitions, QOS limits, and storage rules by heart." ;;
esac
