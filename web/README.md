# ASCEND-Web

A minimal local web chat for the ASCEND agent. It serves a single page on
`http://127.0.0.1:8765` and relays each message to Claude Code in headless
mode (`claude -p --output-format stream-json`), running inside the ASCEND
project directory for the resource you pick (NCShare / Hazel / hurricane /
local). The conversation continues across messages via `claude --resume`.

It is a **separate add-on**: it does not modify the ASCEND harness,
launchers, or skills in any way. It only runs the same `claude` CLI the
launchers run, in directories those launchers have seeded.

- Pure Python standard library — no `pip install` of anything.
- Localhost-only, with a random access token in the URL (regenerated each
  start). It refuses to bind to anything but 127.0.0.1.
- Streams agent text and tool calls (ssh commands, sbatch, file edits) live
  into the browser, with a Stop button.

## Quick start

From the ASCEND clone root:

```bash
./install.sh web      # one-time: links ascend-web into ~/.local/bin
ascend-web
```

(or run it directly: `python3 web/ascend-web.py`). It prints a URL like
`http://127.0.0.1:8765/?t=...` and opens your browser. Pick a resource in
the dropdown, type a message, Enter to send.

Note: the web backend drives **Claude Code** in headless mode. The
per-launch Claude-Code-or-Codex choice of the terminal launchers does not
apply here (Codex is not wired into the web backend yet).

## One-time setup per resource — seed the project directory

ASCEND's per-resource rules (what's allowed on the Hazel login node, how to
route commands to NCShare, hurricane's house rules) live in the `AGENTS.md`
that each launcher seeds into a project directory. ASCEND-Web does not seed;
it reuses. So, once per resource, run the normal launcher pointed at the
directory ASCEND-Web will use, let it start, then exit:

```bash
ascend-ncshare  -d ~/agents/ncshare/projects/web          # then /exit
ascend-hazel    -d ~/agents/ncsuhpc/projects-hazel/web    # then /exit
ascend-hurricane -d ~/agents/hurricane/projects/web       # then /exit
```

(The `local` resource needs no seeding.) The directories are set in
`config.json` — change them if you prefer other project dirs, including
ones you already use from the CLI. The shipped entries match the ASCEND
defaults (NCShare / Hazel / hurricane); **edit the list to your own
resources** — a custom `ascend-<site>` install, your own cluster, your
workstation — and the dropdown shows exactly what you configure, nothing
else.

As with the CLI launchers: the Hazel resource needs the `hazel` ssh link
warm (`ssh hazel`, once per 8 h — the web agent will tell you if it's cold),
and hurricane/NCShare work the same as from the terminal because the exact
same ssh aliases are used.

## Permissions — read this once

Headless mode cannot pop up the usual "allow this command?" prompt, so by
default ASCEND-Web runs with `permission_mode: "bypassPermissions"` — the
agent's tool calls (ssh, sbatch, file edits in the project dir) run without
per-call approval, like pressing "yes" automatically. That is the same
trust you extend when you let a CLI session run with auto-approval.

This is why the server is localhost-only + token-protected. If you want a
tighter setup, edit `config.json`:

```json
"permission_mode": "default",
"allowed_tools": ["Bash(ssh hazel *)", "Bash(ssh ncshare-agent *)", "Read", "Glob", "Grep"]
```

With `default`, anything not in `allowed_tools` is simply refused in
headless mode (the agent will say it couldn't run it) — safe, but the agent
can do less.

## Choosing the model

A dropdown next to **Send** picks which Claude model handles your next
message (Default / Sonnet / Opus / Haiku, editable via `models` in
`config.json`). The choice is passed straight to `claude --model`, applies
per message — you can switch mid-conversation — and is remembered by the
browser. "Default model" uses whatever your Claude Code CLI is configured
to use; hover the dropdown after a reply to see the exact model that ran.

## Config reference (`config.json`)

| key | meaning |
|---|---|
| `port` | default 8765; or `--port` on the command line |
| `claude_bin` | path to the `claude` CLI; empty = auto-detect (PATH, then `~/.local/bin/claude`) |
| `permission_mode` | passed to `claude --permission-mode` (default `bypassPermissions`) |
| `allowed_tools` | optional `--allowedTools` list |
| `models` | the model dropdown next to Send: `{"id","label"}` entries; the id is passed as `claude --model` (ships with Default / Sonnet / Opus / Haiku; `""` = the CLI's default) |
| `open_browser` | auto-open the URL on start |
| `resources` | the dropdown: `name`, `label`, `dir` (working dir for the agent), `note` |

## Result files show up in the chat

After each run, ASCEND-Web lists any files the agent created or updated in
that resource's project folder as chips under the reply. Click a chip to
view it inline — HTML reports and PDFs open in an embedded frame (scripts
like Plotly work), images display directly, and text/code/CSV shows as a
scrollable block; the ↗ opens it in its own browser tab. Click the chip
again to collapse the preview.

Only files in the **local project folder** are detected — results that live
on a cluster aren't. So for cluster runs, just ask the agent: *"copy the
report back to the project folder"* (scp/rsync over the same ssh aliases)
and it will appear as a chip.

## Job monitoring

Between messages the agent is idle — nothing runs. But for resources with a
`queue_cmd` in `config.json` (Hazel ships with one: `ssh hazel 'squeue -u
$USER …'`), the page shows a live job strip in the header: job id, state
(RUNNING / PENDING), elapsed time, name. The browser refreshes it about
every two minutes through the server, which runs the one squeue over your
multiplexed ssh link and caches it for 60 s — no agent, no tokens, just one
cheap command. Close the page and the polling stops.

Next to the strip is a **Watch** toggle. With it on, when the queue goes
from having jobs to empty, the page automatically sends the agent one
message — "a watched job left the queue: check whether it completed, look
at the output, report" — which appears in the chat like any other turn (so
one agent run, only when something actually finished, not on a timer). If
the agent is mid-run at that moment, the check fires right after.

To add a strip for another resource, set its `queue_cmd`. For NCShare,
note the `ncshare-agent` alias provisions a compute job on every
connection, so do NOT point queue_cmd at it; use a plain login alias if
you have one.

## Built-in ssh terminal

The **Terminal** button opens a real terminal in a right-side panel, connected
to the selected resource over the same ssh aliases the agent uses (`term_cmd`
in `config.json`: Hazel ships `ssh hazel`, hurricane `ssh hurricane`, local
your login shell). It is a full PTY — run `squeue`, `sinfo`, `htop`, edit
files, anything you'd do in a normal terminal — served only on localhost with
the same access token, using a bundled copy of xterm.js (no CDN needed).

This is also the answer to a **cold link**: when the multiplexed ssh link has
expired, the terminal is where you type your password and Duo — warming the
link for the agent too (same ControlMaster socket). The job strip's error
line links straight to it ("open Terminal to log in"). One terminal per
resource; it keeps running when you hide the panel, follows the resource
dropdown, and "restart" kills and reconnects it. The agent and the terminal
are independent — the agent never reads what you type there.

## How it works

```
browser ──POST /api/chat──► ascend-web.py ──spawn──► claude -p --output-format stream-json
   ▲                              │                        (cwd = resource project dir,
   └──── SSE stream of text ◄─────┘                         --resume <session> after msg 1)
         and tool-call events                     agent uses the seeded AGENTS.md + skills
                                                  → ssh aliases → NCShare / Hazel / hurricane
```

One run at a time per resource directory (a second message while the agent
is working gets "run already in progress"). Different resources can run in
parallel. "New chat" drops the session id, so the next message starts fresh.

## Notes / limits

- Chat history lives in the page; reloading the browser clears the display,
  but the *session* transcript is Claude Code's own (`claude --resume` from
  the CLI in the same directory can pick up a web conversation, and vice
  versa).
- This is deliberately single-user. Do not port-forward or expose it; the
  agent runs under your account with your ssh keys.
- Requires a reasonably recent Claude Code CLI (stream-json output).
