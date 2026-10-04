#!/usr/bin/env python3
"""
ASCEND-Web — a minimal local web chat for the ASCEND agent.

Serves a single-page chat UI on localhost and relays each message to the
Claude Code CLI in headless mode (`claude -p --output-format stream-json`),
running inside the ASCEND project directory for the resource you pick
(NCShare / Hazel / hurricane / local). Conversations continue across
messages via `claude --resume <session_id>`.

Design rules:
  * stdlib only — no pip installs needed; works with macOS system python3.
  * never modifies ASCEND itself — it only runs `claude` in a directory
    that an ASCEND launcher has already seeded (AGENTS.md etc.).
  * localhost only, with a per-run access token in the URL.

Usage:
    python3 ascend-web.py            # starts on http://127.0.0.1:8765
    python3 ascend-web.py --port 9000
    python3 ascend-web.py --config /path/to/config.json
"""

import argparse
import json
import mimetypes
import os
import posixpath
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

HERE = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(HERE, "static")

DEFAULT_CONFIG = {
    "host": "127.0.0.1",
    "port": 8765,
    "claude_bin": "",            # empty = auto-detect (PATH, then ~/.local/bin/claude)
    "permission_mode": "bypassPermissions",
    "allowed_tools": [],          # optional extra --allowedTools entries
    "open_browser": True,
    "resources": [
        {
            "name": "ncshare",
            "label": "NCShare (H200 cluster)",
            "dir": "~/agents/ncshare/projects/web",
            "note": "Runs per-command over the ncshare-agent ssh aliases."
        },
        {
            "name": "hazel",
            "label": "Hazel login node (scheduling/env only)",
            "dir": "~/agents/ncsuhpc/projects-hazel/web",
            "note": "Needs the 'hazel' ssh link warm (run: ssh hazel, once per 8h).",
            "queue_cmd": "ssh hazel 'squeue -u $USER -h -o \"%i|%T|%M|%j\"'"
        },
        {
            "name": "hurricane",
            "label": "hurricane (single GPU, MEAS)",
            "dir": "~/agents/hurricane/projects/web",
            "note": "Direct on campus; via the hazel-vcl jump off campus."
        },
        {
            "name": "local",
            "label": "Local (this computer)",
            "dir": "~/agents/web-projects/local",
            "note": "Plain Claude Code on this machine, no HPC."
        }
    ]
}


def load_config(path):
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))  # deep copy
    if path and os.path.exists(path):
        with open(path) as f:
            user = json.load(f)
        for k, v in user.items():
            cfg[k] = v
    return cfg


def find_claude(cfg):
    cand = cfg.get("claude_bin") or ""
    if cand:
        cand = os.path.expanduser(cand)
        if os.path.exists(cand):
            return cand
    p = shutil.which("claude")
    if p:
        return p
    home_claude = os.path.expanduser("~/.local/bin/claude")
    if os.path.exists(home_claude):
        return home_claude
    return None


class Run:
    """One in-flight claude -p invocation."""
    def __init__(self, proc):
        self.proc = proc
        self.stopped = False


class State:
    def __init__(self):
        self.lock = threading.Lock()
        self.runs = {}        # run_id -> Run
        self.busy_dirs = set()  # one agent at a time per working dir
        self.job_cache = {}   # resource -> {"ts": float, "payload": dict}

    def register(self, run_id, run):
        with self.lock:
            self.runs[run_id] = run

    def unregister(self, run_id):
        with self.lock:
            self.runs.pop(run_id, None)

    def stop(self, run_id):
        with self.lock:
            run = self.runs.get(run_id)
        if run:
            run.stopped = True
            try:
                run.proc.terminate()
            except Exception:
                pass
            return True
        return False


STATE = State()
CFG = None
TOKEN = None
CLAUDE = None


def sse(obj):
    return ("data: " + json.dumps(obj, ensure_ascii=False) + "\n\n").encode("utf-8")


SKIP_DIRS = {".git", ".claude", "node_modules", "__pycache__", ".venv", "venv", ".ascend"}
SKIP_FILES = {"AGENTS.md", "CLAUDE.md"}
MAX_SERVE_BYTES = 100 * 1024 * 1024


def files_changed_since(workdir, since, limit=20):
    """Files under workdir modified at/after `since` (newest first)."""
    out = []
    for root, dirs, files in os.walk(workdir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for f in files:
            if f.startswith(".") or f in SKIP_FILES:
                continue
            p = os.path.join(root, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime >= since - 1:
                out.append({"path": os.path.relpath(p, workdir).replace(os.sep, "/"),
                            "size": st.st_size, "mtime": st.st_mtime})
    out.sort(key=lambda x: -x["mtime"])
    return out[:limit]


def summarize_tool(name, tool_input):
    """One-line human summary of a tool call for the UI."""
    try:
        if name == "Bash":
            return tool_input.get("command", "")[:400]
        if name in ("Read", "Write", "Edit"):
            return tool_input.get("file_path", "")[:400]
        if name in ("Glob", "Grep"):
            return tool_input.get("pattern", "")[:200]
        if name == "WebFetch":
            return tool_input.get("url", "")[:300]
        if name == "WebSearch":
            return tool_input.get("query", "")[:300]
        s = json.dumps(tool_input, ensure_ascii=False)
        return s[:300]
    except Exception:
        return ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "ascend-web"

    # ---------- helpers ----------

    def log_message(self, fmt, *args):
        sys.stderr.write("[ascend-web] %s\n" % (fmt % args))

    def _check_host(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        return host in ("127.0.0.1", "localhost", "[::1]", "::1")

    def _check_token(self, query=None, body=None):
        t = None
        if query:
            t = (query.get("t") or [None])[0]
        if t is None and body is not None:
            t = body.get("t")
        if t is None:
            t = self.headers.get("X-Ascend-Token")
        if t is None:
            # cookie (set by the page JS) — lets HTML previews load their
            # relative assets (images, css) without a token in every URL
            for part in (self.headers.get("Cookie") or "").split(";"):
                k, _, v = part.strip().partition("=")
                if k == "ascend_token":
                    t = v
                    break
        return t == TOKEN

    def _send_json(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _deny(self, why="forbidden"):
        self._send_json({"error": why}, 403)

    def _read_body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if n <= 0 or n > 10_000_000:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    # ---------- GET ----------

    def do_GET(self):
        if not self._check_host():
            return self._deny("bad host")
        url = urlparse(self.path)
        q = parse_qs(url.query)

        if url.path in ("/", "/index.html"):
            try:
                with open(os.path.join(STATIC_DIR, "index.html"), "rb") as f:
                    data = f.read()
            except OSError:
                return self._send_json({"error": "static/index.html missing"}, 500)
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
            return

        if url.path == "/api/config":
            if not self._check_token(query=q):
                return self._deny("bad token")
            resources = []
            for r in CFG["resources"]:
                d = os.path.expanduser(r["dir"])
                resources.append({
                    "name": r["name"],
                    "label": r.get("label", r["name"]),
                    "dir": d,
                    "exists": os.path.isdir(d),
                    "note": r.get("note", ""),
                })
            return self._send_json({
                "resources": resources,
                "claude": CLAUDE or "",
                "permission_mode": CFG["permission_mode"],
            })

        if url.path == "/api/jobs":
            if not self._check_token(query=q):
                return self._deny("bad token")
            return self._jobs((q.get("resource") or [""])[0],
                              bool((q.get("force") or [""])[0]))

        if url.path.startswith("/files/"):
            if not self._check_token(query=q):
                return self._deny("bad token")
            return self._serve_file(url.path)

        self._send_json({"error": "not found"}, 404)

    def _jobs(self, resource, force=False):
        """Slurm queue snapshot for the resource's configured queue_cmd.
        Cheap (no agent): one ssh/squeue, cached 60 s so browser polling
        never hammers the login node."""
        res = next((r for r in CFG["resources"] if r["name"] == resource), None)
        if res is None:
            return self._send_json({"error": "unknown resource"}, 404)
        cmd = res.get("queue_cmd") or ""
        if not cmd:
            return self._send_json({"supported": False})
        now = time.time()
        with STATE.lock:
            cached = STATE.job_cache.get(resource)
            if cached and now - cached["ts"] < (5 if force else 60):
                return self._send_json(cached["payload"])
        env = dict(os.environ)
        extra = os.pathsep.join(os.path.expanduser(p) for p in ("~/.local/bin", "~/bin"))
        env["PATH"] = extra + os.pathsep + env.get("PATH", "")
        payload = {"supported": True, "fetched_at": now, "jobs": []}
        try:
            out = subprocess.run(cmd, shell=True, env=env, capture_output=True,
                                 text=True, timeout=30)
            if out.returncode != 0:
                payload["error"] = (out.stderr or "queue command failed").strip()[-300:]
            else:
                for line in out.stdout.splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    parts = (line.split("|") + ["", "", "", ""])[:4]
                    payload["jobs"].append({"id": parts[0], "state": parts[1],
                                            "elapsed": parts[2], "name": parts[3]})
        except subprocess.TimeoutExpired:
            payload["error"] = "queue command timed out (link cold?)"
        except OSError as e:
            payload["error"] = str(e)
        with STATE.lock:
            STATE.job_cache[resource] = {"ts": now, "payload": payload}
        return self._send_json(payload)

    def _serve_file(self, path):
        rest = unquote(path[len("/files/"):])
        if "/" not in rest:
            return self._send_json({"error": "bad path"}, 400)
        resource, rel = rest.split("/", 1)
        res = next((r for r in CFG["resources"] if r["name"] == resource), None)
        if res is None:
            return self._send_json({"error": "unknown resource"}, 404)
        workdir = os.path.realpath(os.path.expanduser(res["dir"]))
        rel = posixpath.normpath(rel)
        if rel.startswith("..") or rel.startswith("/"):
            return self._send_json({"error": "bad path"}, 400)
        full = os.path.realpath(os.path.join(workdir, rel))
        if full != workdir and not full.startswith(workdir + os.sep):
            return self._send_json({"error": "bad path"}, 400)
        if not os.path.isfile(full):
            return self._send_json({"error": "not found"}, 404)
        size = os.path.getsize(full)
        if size > MAX_SERVE_BYTES:
            return self._send_json({"error": "file too large to preview (%d MB)" % (size // 1048576)}, 413)
        ctype, _ = mimetypes.guess_type(full)
        if not ctype:
            ctype = "text/plain" if size < 2_000_000 else "application/octet-stream"
        if ctype.startswith("text/") or ctype in ("application/json", "image/svg+xml"):
            ctype += "; charset=utf-8"
        try:
            with open(full, "rb") as f:
                data = f.read()
        except OSError as e:
            return self._send_json({"error": str(e)}, 500)
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    # ---------- POST ----------

    def do_POST(self):
        if not self._check_host():
            return self._deny("bad host")
        url = urlparse(self.path)
        body = self._read_body()
        if not self._check_token(body=body):
            return self._deny("bad token")

        if url.path == "/api/stop":
            ok = STATE.stop(str(body.get("run_id", "")))
            return self._send_json({"stopped": ok})

        if url.path == "/api/chat":
            return self._chat(body)

        self._send_json({"error": "not found"}, 404)

    # ---------- the agent call ----------

    def _chat(self, body):
        message = (body.get("message") or "").strip()
        resource = body.get("resource") or ""
        session_id = body.get("session_id") or None
        run_id = str(body.get("run_id") or secrets.token_hex(8))

        res = next((r for r in CFG["resources"] if r["name"] == resource), None)
        if not message or res is None:
            return self._send_json({"error": "need message and a valid resource"}, 400)
        if CLAUDE is None:
            return self._send_json({"error": "claude CLI not found — set claude_bin in config.json"}, 500)

        workdir = os.path.expanduser(res["dir"])
        os.makedirs(workdir, exist_ok=True)

        with STATE.lock:
            if workdir in STATE.busy_dirs:
                return self._send_json(
                    {"error": "an agent run is already in progress for this resource — wait or stop it"}, 409)
            STATE.busy_dirs.add(workdir)

        # SSE response
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()

        cmd = [CLAUDE, "-p", "--output-format", "stream-json", "--verbose"]
        pm = CFG.get("permission_mode") or ""
        if pm:
            cmd += ["--permission-mode", pm]
        allowed = CFG.get("allowed_tools") or []
        if allowed:
            cmd += ["--allowedTools", ",".join(allowed)]
        if session_id:
            cmd += ["--resume", session_id]

        env = dict(os.environ)
        # make sure ~/.local/bin and ~/bin are reachable for ascend helper tools
        extra = os.pathsep.join(os.path.expanduser(p) for p in ("~/.local/bin", "~/bin"))
        env["PATH"] = extra + os.pathsep + env.get("PATH", "")

        try:
            proc = subprocess.Popen(
                cmd, cwd=workdir, env=env,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, bufsize=1,
            )
        except OSError as e:
            with STATE.lock:
                STATE.busy_dirs.discard(workdir)
            self.wfile.write(sse({"type": "error", "error": "failed to start claude: %s" % e}))
            self.wfile.write(sse({"type": "done"}))
            return

        run = Run(proc)
        STATE.register(run_id, run)
        start_ts = time.time()
        self.wfile.write(sse({"type": "start", "run_id": run_id, "cmd": " ".join(shlex.quote(c) for c in cmd),
                              "workdir": workdir}))
        self.wfile.flush()

        # feed the prompt on stdin, close it
        def feed():
            try:
                proc.stdin.write(message)
                proc.stdin.close()
            except Exception:
                pass
        threading.Thread(target=feed, daemon=True).start()

        got_result = False
        try:
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                out = self._translate(ev)
                for o in out:
                    if o.get("type") == "result":
                        got_result = True
                    self.wfile.write(sse(o))
                self.wfile.flush()
            proc.wait(timeout=10)
        except (BrokenPipeError, ConnectionResetError):
            # browser went away — stop the agent run
            try:
                proc.terminate()
            except Exception:
                pass
        except Exception as e:
            try:
                self.wfile.write(sse({"type": "error", "error": str(e)}))
            except Exception:
                pass
        finally:
            STATE.unregister(run_id)
            with STATE.lock:
                STATE.busy_dirs.discard(workdir)

        try:
            if run.stopped:
                self.wfile.write(sse({"type": "error", "error": "stopped by user"}))
            elif not got_result:
                # the run ended without a result event — never leave the user
                # with a silent "(no output)": surface stderr and a hint
                err = ""
                try:
                    err = (proc.stderr.read() or "").strip()[-2000:]
                except Exception:
                    pass
                msg = "the agent run ended without producing a reply (exit code %s)" % proc.returncode
                if session_id:
                    msg += " — if this repeats, try 'New chat' (the resumed session may be locked or missing)"
                self.wfile.write(sse({"type": "error", "error": msg, "stderr": err}))
            try:
                changed = files_changed_since(workdir, start_ts)
            except Exception:
                changed = []
            if changed:
                self.wfile.write(sse({"type": "files", "resource": resource, "files": changed}))
            self.wfile.write(sse({"type": "done"}))
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    @staticmethod
    def _translate(ev):
        """stream-json event -> list of UI events."""
        t = ev.get("type")
        out = []
        if t == "system" and ev.get("subtype") == "init":
            out.append({"type": "session", "session_id": ev.get("session_id"),
                        "model": ev.get("model", "")})
        elif t == "assistant":
            msg = ev.get("message") or {}
            for block in msg.get("content") or []:
                bt = block.get("type")
                if bt == "text" and block.get("text"):
                    out.append({"type": "text", "text": block["text"]})
                elif bt == "tool_use":
                    out.append({"type": "tool",
                                "name": block.get("name", "?"),
                                "summary": summarize_tool(block.get("name", ""), block.get("input") or {})})
        elif t == "result":
            out.append({"type": "result",
                        "is_error": bool(ev.get("is_error")),
                        "result": ev.get("result", ""),
                        "duration_ms": ev.get("duration_ms"),
                        "cost_usd": ev.get("total_cost_usd"),
                        "session_id": ev.get("session_id")})
        return out


def main():
    global CFG, TOKEN, CLAUDE
    ap = argparse.ArgumentParser(description="ASCEND-Web local chat server")
    ap.add_argument("--config", default=os.path.join(HERE, "config.json"))
    ap.add_argument("--port", type=int, default=None)
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()

    CFG = load_config(args.config)
    if args.port:
        CFG["port"] = args.port
    TOKEN = secrets.token_urlsafe(16)
    CLAUDE = find_claude(CFG)

    host, port = CFG["host"], int(CFG["port"])
    if host not in ("127.0.0.1", "localhost", "::1"):
        print("Refusing to bind to %r — ASCEND-Web is localhost-only by design." % host)
        sys.exit(1)

    httpd = ThreadingHTTPServer((host, port), Handler)
    url = "http://%s:%d/?t=%s" % (host, port, TOKEN)

    print()
    print("  ASCEND-Web is up.")
    print("  Open:  %s" % url)
    if CLAUDE:
        print("  Agent: %s  (permission mode: %s)" % (CLAUDE, CFG["permission_mode"]))
    else:
        print("  WARNING: 'claude' CLI not found — set claude_bin in config.json")
    print("  Ctrl-C to stop.")
    print()

    if CFG.get("open_browser", True) and not args.no_browser:
        threading.Thread(target=lambda: webbrowser.open(url), daemon=True).start()

    def shutdown(signum, frame):
        print("\nshutting down…")
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
