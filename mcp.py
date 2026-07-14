#!/usr/bin/env python3
"""
mcp.py — Roblox Studio MCP helper.

Usage:
    mcp.py luau <code>            execute Lua in Studio (code string)
    mcp.py luau -                 execute Lua read from stdin
    mcp.py luau -f <file.lua>     execute a Lua file
    mcp.py console [filter]       print Studio console output (optionally filtered)
    mcp.py tail [filter]          live-tail Studio console; Ctrl+C to stop
    mcp.py tree [path]            search_game_tree  (default: game)
    mcp.py inspect <path>         inspect_instance
    mcp.py read <path>            script_read — print a deployed script's source
    mcp.py grep <pattern>         script_grep — Luau-pattern search across all scripts
    mcp.py search <keywords>      script_search — fuzzy match on script names
    mcp.py state                  get_studio_state — edit/play mode, place info
    mcp.py capture                screen_capture
    mcp.py studios                list open Studio instances
    mcp.py check <file.lua> ...   compile-check Lua file(s) in Studio (no execution)
    mcp.py drift                  diff local source vs deployed Studio modules
    mcp.py test [pattern] [-v]    run MultiAnimation test suite (pattern filters filenames)
    mcp.py deploy                 push game/MultiAnimPlayer.lua into ServerStorage
    mcp.py playtest [options]     deploy → play mode → watch console → PASS/FAIL
    mcp.py gen model <desc>       AI-generate a procedural model (auto-inserts into workspace)
    mcp.py gen mesh <desc>        AI-generate a textured mesh  [--size x,y,z] [--tris N]
    mcp.py gen material <desc>    AI-generate a material variant [--base Rock] [--pattern Organic]
    mcp.py gen wait <id>          wait for a generation job    [--timeout N]
    mcp.py store <query>          search the Creator Store
    mcp.py store <query> --insert insert the first matching asset [--name X] [--types A,B]
    mcp.py addrig [name]          clone Rig1 in Workspace.FIGURES (next free RigN if no name)
    mcp.py scene list             scenes in Studio vs scenes pulled to disk
    mcp.py scene pull <name>      serialize a scene to MultiAnimation/scenes/<name>/ (git-diffable)
    mcp.py scene push <name> [--as <target>]   rebuild scene in ServerStorage from disk
    mcp.py daemon start|stop|status   persistent proxy — auto-starts on first call
    mcp.py <tool> [json_args]     call any raw tool by name

Daemon mode:
    Without the daemon every call spawns a fresh StudioMCP.exe and re-primes the
    active studio (~5-10 s overhead).  `mcp daemon start` keeps one proxy alive
    behind a Unix socket; all mcp.py commands (and run_tests.py / devsync.py)
    use it automatically when running, and fall back to spawn-per-call if not.

Playtest options:
    --no-deploy        skip the deploy step
    --timeout N        seconds to wait for a result marker (default 45)
    --marker STR       success marker to watch for (default "FINISHED")

Examples:
    mcp.py luau "return workspace.Name"
    mcp.py luau - <<'EOF'
        local t={}
        for _,c in ipairs(workspace:GetChildren()) do table.insert(t,c.Name) end
        return table.concat(t,'|')
    EOF
    mcp.py luau -f tests/test_scrubber.lua
    mcp.py console MultiAnimation
    mcp.py tail MultiAnimation
    mcp.py tree workspace.FIGURES
    mcp.py inspect workspace.FIGURES.Rig1
    mcp.py read ServerStorage.MultiAnimationData.MultiAnimPlayer
    mcp.py grep "RegisterKeyframeSequence"
    mcp.py check MultiAnimation/plugin/core/Exporter.lua
    mcp.py drift
    mcp.py test prop -v
    mcp.py deploy
    mcp.py playtest --timeout 60
    mcp.py gen model "a wooden crate with adjustable size"
    mcp.py gen mesh "medieval sword" --size 1,4,0.3 --tris 5000
    mcp.py gen material "rough mossy stone" --base Rock --pattern Organic
    mcp.py store "low poly tree"
    mcp.py store "low poly tree" --insert --name PineTree
    mcp.py addrig
    mcp.py addrig Villain
"""

import os
import sys
import json
import subprocess
import threading
import queue
import time

# Resolve StudioMCP.exe from the newest installed Roblox version. mcp.bat
# hardcodes a version path that goes stale on every Roblox update (its registry
# fallback is broken cmd syntax), so prefer the exe directly; keep the bat as
# a last resort.
def _find_studio_mcp():
    import glob
    candidates = glob.glob(
        "/mnt/c/Users/kjell/AppData/Local/Roblox/Versions/version-*/StudioMCP.exe")
    return max(candidates, key=os.path.getmtime) if candidates else None

_studio_mcp = _find_studio_mcp()
MCP_CMD = ([_studio_mcp] if _studio_mcp
           else ["cmd.exe", "/c", r"C:\Users\kjell\AppData\Local\Roblox\mcp.bat"])

_INIT = json.dumps({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "mcp-helper", "version": "1"},
    },
}) + "\n"

# ── core MCP call ─────────────────────────────────────────────────────────────

def _rpc(proc, results: "queue.Queue", msg_id: int, name: str, arguments: dict,
         timeout: float) -> dict | None:
    """Send one tools/call request and wait for its response. None on timeout."""
    proc.stdin.write(json.dumps({
        "jsonrpc": "2.0",
        "id": msg_id,
        "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    }) + "\n")
    proc.stdin.flush()

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            d = results.get(timeout=0.5)
            if d.get("id") == msg_id:
                return d
        except queue.Empty:
            pass
    return None


def _result_texts(d: dict) -> tuple[list[str], bool]:
    """Extract (texts, isError) from a tools/call response.
    Image content blocks are saved to /tmp and replaced with a path marker so
    they survive the text-only daemon protocol (used by `mcp capture`)."""
    result = d.get("result", {})
    content = result.get("content", [])
    texts = []
    for c in content:
        if c.get("type") == "text":
            texts.append(c["text"])
        elif c.get("type") == "image" and c.get("data"):
            import base64
            ext = "png" if "png" in (c.get("mimeType") or "png") else "jpg"
            path = f"/tmp/roblox_capture_{int(time.time() * 1000)}.{ext}"
            try:
                with open(path, "wb") as f:
                    f.write(base64.b64decode(c["data"]))
                texts.append(f"[image saved: {path}]")
            except Exception as e:
                texts.append(f"[image decode failed: {e}]")
    return texts, result.get("isError", False)


# ── daemon (persistent proxy) ─────────────────────────────────────────────────

DAEMON_SOCK = "/tmp/roblox_mcp_daemon.sock"
DAEMON_PID  = "/tmp/roblox_mcp_daemon.pid"
DAEMON_LOG  = "/tmp/roblox_mcp_daemon.log"


def _daemon_call(tool: str, args: dict, timeout: int) -> tuple[list[str], str | None] | None:
    """Try the daemon socket. Returns (texts, err) or None if the daemon is unavailable."""
    import socket
    if not os.path.exists(DAEMON_SOCK):
        return None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(timeout + 40)   # leave room for daemon-side re-priming
        s.connect(DAEMON_SOCK)
        s.sendall((json.dumps({"tool": tool, "args": args, "timeout": timeout}) + "\n").encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        s.close()
        if not buf:
            return None
        d = json.loads(buf.decode())
        return d.get("texts", []), d.get("err")
    except (OSError, json.JSONDecodeError):
        return None


_autostart_attempted = False

def _daemon_autostart() -> bool:
    """Start the daemon in the background (once per process). Returns True if it came up.

    Opt out with MCP_NO_DAEMON=1 in the environment.
    """
    global _autostart_attempted
    if _autostart_attempted or os.environ.get("MCP_NO_DAEMON"):
        return False
    _autostart_attempted = True
    try:
        if os.path.exists(DAEMON_SOCK):
            os.unlink(DAEMON_SOCK)   # stale socket from a dead daemon
        log = open(DAEMON_LOG, "a")
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "daemon", "run"],
            stdout=log, stderr=log, start_new_session=True,
        )
        for _ in range(20):
            time.sleep(0.25)
            if _daemon_send_cmd("ping"):
                return True
    except OSError:
        pass
    return False


def call_mcp(tool: str, args: dict, timeout: int = 15) -> tuple[list[str], str | None]:
    """
    Call a single MCP tool.  Returns (texts, error_or_None).

    Uses the daemon socket (auto-starting the daemon on first use; opt out with
    MCP_NO_DAEMON=1).  Falls back to spawning a fresh StudioMCP.exe — active-studio
    state is per proxy process, so each spawn is primed with list_roblox_studios +
    set_active_studio.
    """
    via_daemon = _daemon_call(tool, args, timeout)
    if via_daemon is None and _daemon_autostart():
        via_daemon = _daemon_call(tool, args, timeout)
    if via_daemon is not None:
        return via_daemon

    try:
        proc = subprocess.Popen(
            MCP_CMD,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except FileNotFoundError:
        return [], "cmd.exe not found — are you on WSL with Windows accessible?"

    results: queue.Queue = queue.Queue()

    def _read():
        for raw in proc.stdout:
            raw = raw.strip()
            if raw:
                try:
                    results.put(json.loads(raw))
                except json.JSONDecodeError:
                    pass

    threading.Thread(target=_read, daemon=True).start()

    try:
        # INIT handshake (server startup can take ~0.5 s)
        proc.stdin.write(_INIT)
        proc.stdin.flush()

        init_deadline = time.time() + 6
        while time.time() < init_deadline:
            try:
                d = results.get(timeout=0.2)
                if d.get("id") == 1:
                    break
            except queue.Empty:
                pass

        msg_id = 2

        # Prime studio selection: a fresh proxy process has no active studio,
        # so direct tool calls fail with "Unable to find an active Studio".
        # Discovery is async after proxy startup — retry the list briefly.
        if tool not in ("list_roblox_studios", "set_active_studio"):
            studios = []
            for attempt in range(5):
                d = _rpc(proc, results, msg_id, "list_roblox_studios", {}, 10)
                msg_id += 1
                if d is not None:
                    texts, _ = _result_texts(d)
                    try:
                        info = json.loads(texts[0]) if texts else {}
                        studios = info.get("studios", [])
                    except (json.JSONDecodeError, IndexError):
                        studios = []
                if studios:
                    break
                time.sleep(1)
            if not studios:
                proc.kill()
                return [], "no Studio instance connected — is Studio open with the MCP plugin on?"
            chosen = next((s for s in studios if s.get("active")), studios[0])
            d = _rpc(proc, results, msg_id, "set_active_studio",
                     {"studio_id": chosen["id"]}, 10)
            msg_id += 1

        # The real tool call
        d = _rpc(proc, results, msg_id, tool, args, timeout)
        proc.stdin.close()

        if d is None:
            proc.kill()
            return [], f"timeout after {timeout}s — Studio might not be open"

        proc.kill()
        if "error" in d:
            return [], d["error"].get("message", "MCP error")
        texts, is_err = _result_texts(d)
        # Return text even on error (it contains the Lua traceback)
        return texts, ("Lua error (see output above)" if is_err else None)
    except BrokenPipeError:
        proc.kill()
        return [], "MCP proxy exited unexpectedly (broken pipe)"


# ── output formatters ─────────────────────────────────────────────────────────

def _fmt_console(texts: list[str], filt: str = "") -> list[str]:
    """Parse Studio console JSON lines into plain messages."""
    out = []
    filt_lower = filt.lower()
    for block in texts:
        for line in block.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
                msg = d.get("message", line)
            except json.JSONDecodeError:
                msg = line
            if not filt_lower or filt_lower in msg.lower():
                out.append(msg)
    return out or ([f"(no matches for '{filt}')" ] if filt else ["(empty console)"])


def _print(texts: list[str], flush: bool = True):
    for t in texts:
        sys.stdout.write(t if t.endswith("\n") else t + "\n")
    if flush:
        sys.stdout.flush()


# ── sub-commands ──────────────────────────────────────────────────────────────

def cmd_luau(argv: list[str]):
    if not argv:
        print("Usage: mcp.py luau <code | - | -f file>", file=sys.stderr)
        sys.exit(1)

    timeout = 15
    # optional trailing --timeout N
    if len(argv) >= 3 and argv[-2] == "--timeout":
        timeout = int(argv[-1])
        argv = argv[:-2]

    # optional trailing --dm Edit|Client|Server (datamodel context; default Edit)
    dm = "Edit"
    if len(argv) >= 3 and argv[-2] == "--dm":
        dm = argv[-1]
        argv = argv[:-2]

    flag = argv[0]
    if flag == "-":
        code = sys.stdin.read()
    elif flag == "-f":
        if len(argv) < 2:
            print("mcp.py luau -f <file>", file=sys.stderr)
            sys.exit(1)
        with open(argv[1], encoding="utf-8") as f:
            code = f.read()
    else:
        code = " ".join(argv)

    texts, err = call_mcp("execute_luau", {"code": code, "datamodel_type": dm}, timeout=timeout)
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n")
        sys.stderr.flush()
        sys.exit(1)


def cmd_console(argv: list[str]):
    filt = argv[0] if argv else ""
    texts, err = call_mcp("get_console_output", {})
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
    _print(_fmt_console(texts, filt))


def cmd_tree(argv: list[str]):
    path = argv[0] if argv else "game"
    texts, err = call_mcp("search_game_tree", {"path": path})
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
    _print(texts)


def cmd_inspect(argv: list[str]):
    if not argv:
        print("Usage: mcp.py inspect <path>", file=sys.stderr)
        sys.exit(1)
    texts, err = call_mcp("inspect_instance", {"path": argv[0]})
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
    _print(texts)


def cmd_capture(_argv):
    # capture_id is required by newer Studio builds; any unique string works.
    texts, err = call_mcp("screen_capture", {"capture_id": f"cap_{int(time.time())}"})
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
    _print(texts)


def cmd_nav(argv):
    """Walk the play-mode character to x y z (or to an instance path).

    Tries the character_navigation MCP tool first (needs datamodel_type since
    the July 2026 Studio update); its client host is broken in some builds
    ("Target is closed"), so falls back to a real Humanoid:MoveTo walk via
    execute_luau — preserving Touched semantics, unlike a teleport."""
    if not argv:
        sys.exit("Usage: mcp nav <x> <y> <z>  |  mcp nav <instance.path>")
    if len(argv) >= 3:
        args = {"x": float(argv[0]), "y": float(argv[1]), "z": float(argv[2]),
                "datamodel_type": "Client"}
        target_lua = f"Vector3.new({float(argv[0])},{float(argv[1])},{float(argv[2])})"
    else:
        args = {"instance_path": argv[0], "datamodel_type": "Client"}
        path = ".".join(f'["{p}"]' if " " in p else p for p in argv[0].split("."))
        target_lua = f"game.{path}.Position"
    texts, err = call_mcp("character_navigation", args, timeout=45)
    if not err:
        _print(texts)
        return
    lua = f"""
local plr = game:GetService("Players").LocalPlayer
local char = plr and plr.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
if not hum then return "no character/Humanoid (is play mode running?)" end
local target = {target_lua}
local done = false
hum.MoveToFinished:Connect(function() done = true end)
hum:MoveTo(target)
local t0 = os.clock()
repeat task.wait(0.1) until done or os.clock() - t0 > 25
local dist = (char:GetPivot().Position - target).Magnitude
return string.format("%s — %.1f studs from target", done and "arrived" or "walk timeout", dist)
"""
    texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Client"},
                          timeout=35)
    if err and not texts:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.exit(1)
    _print(texts)


def cmd_studios(_argv):
    texts, err = call_mcp("list_roblox_studios", {})
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
    _print(texts)


def cmd_tail(argv: list[str]):
    filt = argv[0] if argv else ""
    label = f" (filter: {filt})" if filt else ""
    print(f"Tailing Studio console{label}... (Ctrl+C to stop)\n", flush=True)

    seen_count: int | None = None

    try:
        while True:
            texts, err = call_mcp("get_console_output", {}, timeout=8)
            if not err:
                lines = _fmt_console(texts, filt)
                # Strip the placeholder lines _fmt_console emits when output is empty.
                lines = [l for l in lines if not l.startswith("(")]

                if seen_count is None:
                    # First poll: show last 5 lines as context, then track from here.
                    for line in lines[-5:]:
                        print(f"  {line}", flush=True)
                    seen_count = len(lines)
                else:
                    if len(lines) < seen_count:
                        # Console was cleared or truncated — reset baseline.
                        seen_count = len(lines)
                    for line in lines[seen_count:]:
                        print(f"  {line}", flush=True)
                    seen_count = len(lines)
            time.sleep(1.5)
    except KeyboardInterrupt:
        print("\nStopped.")


def cmd_test(argv: list[str]):
    candidates = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "MultiAnimation", "run_tests.py"),
        "/mnt/c/GIT/Roblox/MultiAnimation/run_tests.py",
    ]
    script = next((p for p in candidates if os.path.exists(p)), None)
    if not script:
        sys.exit("run_tests.py not found — run it directly from MultiAnimation/")
    result = subprocess.run([sys.executable, script] + argv)
    sys.exit(result.returncode)


def _lua_str(s: str) -> str:
    """Encode s as a double-quoted Lua string literal (safe for any source text)."""
    return (
        '"'
        + s.replace("\\", "\\\\")
           .replace('"',  '\\"')
           .replace("\n", "\\n")
           .replace("\r", "")
           .replace("\0", "")
        + '"'
    )


def cmd_deploy_inner() -> bool:
    """Deploy game/MultiAnimPlayer.lua to ServerStorage. Returns True on success."""
    candidates = [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "MultiAnimation", "game", "MultiAnimPlayer.lua"),
        "/mnt/c/GIT/Roblox/MultiAnimation/game/MultiAnimPlayer.lua",
    ]
    src_path = next((p for p in candidates if os.path.exists(p)), None)
    if not src_path:
        sys.stderr.write("game/MultiAnimPlayer.lua not found\n")
        return False

    with open(src_path, encoding="utf-8") as f:
        source = f.read()

    lua = f"""
local ss  = game:GetService("ServerStorage")
local mad = ss:FindFirstChild("MultiAnimationData")
assert(mad, "ServerStorage.MultiAnimationData not found — export a scene first")
local existing = mad:FindFirstChild("MultiAnimPlayer")
if existing then existing:Destroy() end
local m    = Instance.new("ModuleScript")
m.Name     = "MultiAnimPlayer"
m.Source   = {_lua_str(source)}
m.Parent   = mad
return "deployed MultiAnimPlayer (" .. #m.Source .. " bytes)"
"""
    texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"})
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        return False
    return True


def cmd_deploy(_argv):
    if not cmd_deploy_inner():
        sys.exit(1)


def cmd_read(argv: list[str]):
    if not argv:
        print("Usage: mcp.py read <script_path>   (dot notation, e.g. game.ServerScriptService.MyScript)", file=sys.stderr)
        sys.exit(1)
    texts, err = call_mcp("script_read", {"target_file": argv[0]})
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)


def cmd_grep(argv: list[str]):
    if not argv:
        print("Usage: mcp.py grep <pattern>   (string or Luau pattern, max 50 matches)", file=sys.stderr)
        sys.exit(1)
    texts, err = call_mcp("script_grep", {"query": " ".join(argv)})
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)


def cmd_search(argv: list[str]):
    if not argv:
        print("Usage: mcp.py search <keywords>   (comma-separated, fuzzy match on script names)", file=sys.stderr)
        sys.exit(1)
    texts, err = call_mcp("script_search", {"keywords": " ".join(argv)})
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)


def cmd_state(_argv):
    texts, err = call_mcp("get_studio_state", {})
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)


# ── check: compile Lua in Studio without executing ────────────────────────────

def check_file(path: str) -> tuple[bool, str]:
    """
    Compile-check one Lua file via loadstring in Studio.
    Returns (ok, message).  Does not execute the file.
    """
    with open(path, encoding="utf-8") as f:
        source = f.read()

    lua = f"""
local src = {_lua_str(source)}
local fn, err = loadstring(src)
if fn then
    return "OK"
else
    return "COMPILE_ERROR\\n" .. tostring(err)
end
"""
    texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"})
    if err and not texts:
        return False, f"mcp unreachable: {err}"

    full = "\n".join(texts)
    if "Unable to find an active Studio" in full or "no Studio instance" in (err or ""):
        return False, "mcp unreachable: no active Studio instance"
    if full.strip() == "OK":
        return True, "OK"

    # Rewrite loadstring's [string "…"] chunk name to the real filename.
    msg = full.replace("COMPILE_ERROR\n", "").strip()
    import re as _re
    msg = _re.sub(r'\[string "[^"]*"\]', os.path.basename(path), msg)
    return False, msg


def cmd_check(argv: list[str]):
    if not argv:
        print("Usage: mcp.py check <file.lua> [more.lua ...]", file=sys.stderr)
        sys.exit(1)

    failed = 0
    for path in argv:
        if not os.path.exists(path):
            print(f"  {path}: file not found")
            failed += 1
            continue
        ok, msg = check_file(path)
        if ok:
            print(f"  {path}: OK")
        else:
            print(f"  {path}: {msg}")
            failed += 1
    sys.exit(1 if failed else 0)


# ── drift: local source vs deployed Studio modules ────────────────────────────

# (local_path, studio_script_path) pairs to compare.
DRIFT_TARGETS = [
    ("MultiAnimation/game/MultiAnimPlayer.lua",
     "ServerStorage.MultiAnimationData.MultiAnimPlayer"),
]


def _fetch_deployed_source(studio_path: str) -> tuple[str | None, str | None]:
    """Returns (source, error). source is None if not deployed."""
    parts = studio_path.split(".")
    lua_walk = [f'local _m = game:GetService({_lua_str(parts[0])})']
    for part in parts[1:]:
        lua_walk.append(f'_m = _m and _m:FindFirstChild({_lua_str(part)})')
    lua = "\n".join(lua_walk) + """
if not _m then return "__NOT_DEPLOYED__" end
return _m.Source
"""
    texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"})
    if err and not texts:
        return None, err
    full = "\n".join(texts)
    if full.strip() == "__NOT_DEPLOYED__":
        return None, None
    return full, None


def cmd_drift(_argv):
    import difflib

    here = os.path.dirname(os.path.abspath(__file__))
    clean = True

    for local_rel, studio_path in DRIFT_TARGETS:
        local_path = os.path.join(here, local_rel)
        if not os.path.exists(local_path):
            print(f"  {local_rel}: local file missing — skipped")
            continue

        with open(local_path, encoding="utf-8") as f:
            local_src = f.read().replace("\r\n", "\n").rstrip("\n")

        deployed, err = _fetch_deployed_source(studio_path)
        if err:
            sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
            sys.exit(1)
        if deployed is None:
            print(f"  {studio_path}: NOT DEPLOYED")
            clean = False
            continue

        deployed = deployed.replace("\r\n", "\n").rstrip("\n")

        if deployed == local_src:
            print(f"  {studio_path}: in sync")
        else:
            clean = False
            print(f"  {studio_path}: DRIFT DETECTED")
            diff = difflib.unified_diff(
                deployed.splitlines(), local_src.splitlines(),
                fromfile=f"deployed:{studio_path}",
                tofile=f"local:{local_rel}",
                lineterm="",
            )
            for i, line in enumerate(diff):
                if i >= 60:
                    print("    ... (diff truncated; run `mcp deploy` to sync)")
                    break
                print(f"    {line}")

    if not clean:
        print("\n  Fix: `mcp deploy` pushes local MultiAnimPlayer.lua to ServerStorage.")
    sys.exit(0 if clean else 1)


# ── playtest: deploy → play mode → watch console → verdict ───────────────────

def _console_lines() -> list[str]:
    texts, err = call_mcp("get_console_output", {}, timeout=8)
    if err and not texts:
        return []
    lines = _fmt_console(texts)
    return [l for l in lines if not l.startswith("(")]


def cmd_playtest(argv: list[str]):
    timeout = 45
    marker = "FINISHED"
    do_deploy = True

    i = 0
    while i < len(argv):
        if argv[i] == "--timeout" and i + 1 < len(argv):
            timeout = int(argv[i + 1]); i += 2
        elif argv[i] == "--marker" and i + 1 < len(argv):
            marker = argv[i + 1]; i += 2
        elif argv[i] == "--no-deploy":
            do_deploy = False; i += 1
        else:
            print(f"Unknown playtest option: {argv[i]}", file=sys.stderr)
            sys.exit(1)

    fail_markers = ("ERROR", "FAIL", "Stack Begin")

    if do_deploy:
        print("[playtest] Deploying MultiAnimPlayer...", flush=True)
        cmd_deploy_inner()

    baseline = len(_console_lines())

    print("[playtest] Entering play mode...", flush=True)
    texts, err = call_mcp("start_stop_play", {"is_start": True}, timeout=20)
    if err and not texts:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)

    verdict = None
    deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            time.sleep(2)
            lines = _console_lines()
            if len(lines) < baseline:
                baseline = 0   # console reset on play start
            new = lines[baseline:]
            baseline = len(lines)
            for line in new:
                print(f"  {line}", flush=True)
                if marker in line:
                    verdict = "PASS"
                elif any(fm in line for fm in fail_markers):
                    verdict = verdict or "FAIL"
            if verdict:
                break
    finally:
        print("[playtest] Exiting play mode...", flush=True)
        call_mcp("start_stop_play", {"is_start": False}, timeout=20)

    if verdict is None:
        verdict = f"TIMEOUT (no '{marker}' within {timeout}s)"

    print(f"\n[playtest] {verdict}")
    sys.exit(0 if verdict == "PASS" else 1)


# ── gen: AI generation pipeline ───────────────────────────────────────────────

def _split_flags(argv: list[str], value_flags: tuple, bool_flags: tuple = ()) -> tuple[dict, list[str]]:
    """Separate --flag value / --flag pairs from positional args."""
    flags, pos = {}, []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in value_flags and i + 1 < len(argv):
            flags[a] = argv[i + 1]; i += 2
        elif a in bool_flags:
            flags[a] = True; i += 1
        else:
            pos.append(a); i += 1
    return flags, pos


def _find_generation_id(text: str) -> str | None:
    import re as _re
    m = _re.search(r'"?generationId"?\s*[:=]\s*"?([\w-]+)', text)
    if m:
        return m.group(1)
    m = _re.search(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b', text)
    return m.group(1) if m and m.lastindex else (m.group(0) if m else None)


def cmd_gen(argv: list[str]):
    if not argv or argv[0] not in ("model", "mesh", "material", "wait"):
        print("Usage: mcp.py gen model|mesh|material <description> | gen wait <generationId>", file=sys.stderr)
        sys.exit(1)

    kind = argv[0]
    flags, pos = _split_flags(argv[1:],
                              value_flags=("--size", "--tris", "--timeout", "--base", "--pattern"),
                              bool_flags=("--wait",))
    desc = " ".join(pos)

    if kind == "wait":
        if not pos:
            print("Usage: mcp.py gen wait <generationId> [--timeout N]", file=sys.stderr)
            sys.exit(1)
        wait_timeout = int(flags.get("--timeout", 600))
        texts, err = call_mcp("wait_job_finished",
                              {"generationId": pos[0], "timeout": wait_timeout},
                              timeout=wait_timeout + 30)
        _print(texts)
        if err:
            sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
            sys.exit(1)
        return

    if not desc:
        print(f"Usage: mcp.py gen {kind} <description>", file=sys.stderr)
        sys.exit(1)

    if kind == "model":
        tool, args = "generate_procedural_model", {"prompt": desc}
    elif kind == "mesh":
        tool, args = "generate_mesh", {"textPrompt": desc}
        if "--tris" in flags:
            args["maxTriangles"] = int(flags["--tris"])
        if "--size" in flags:
            try:
                x, y, z = (float(v) for v in flags["--size"].split(","))
                args["size"] = {"x": x, "y": y, "z": z}
            except ValueError:
                print("--size must be x,y,z numbers, e.g. --size 4,6,2", file=sys.stderr)
                sys.exit(1)
    else:  # material
        import uuid
        tool, args = "generate_material", {
            "materialDescription": desc,
            "baseMaterial":   flags.get("--base", "Plastic"),
            "materialPattern": flags.get("--pattern", "Regular"),
            "materialId":     str(uuid.uuid4()),
        }

    submit_timeout = int(flags.get("--timeout", 300))
    print(f"[gen] Submitting {kind} generation...", flush=True)
    texts, err = call_mcp(tool, args, timeout=submit_timeout)
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)

    if flags.get("--wait"):
        gen_id = _find_generation_id("\n".join(texts))
        if not gen_id:
            print("[gen] No generationId found in response — nothing to wait for.")
            return
        print(f"[gen] Waiting for job {gen_id}...", flush=True)
        texts, err = call_mcp("wait_job_finished", {"generationId": gen_id}, timeout=630)
        _print(texts)
        if err:
            sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
            sys.exit(1)


# ── store: Creator Store search + insert ──────────────────────────────────────

def cmd_store(argv: list[str]):
    flags, pos = _split_flags(argv, value_flags=("--name", "--types"), bool_flags=("--insert",))
    query = " ".join(pos)
    if not query:
        print("Usage: mcp.py store <query> [--insert] [--name X] [--types A,B]", file=sys.stderr)
        sys.exit(1)

    texts, err = call_mcp("search_creator_store", {"query": query}, timeout=60)
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)

    if not flags.get("--insert"):
        return

    # Pull the searchId out of the search response (JSON or labelled text).
    full = "\n".join(texts)
    search_id = None
    try:
        search_id = json.loads(full).get("searchId")
    except (json.JSONDecodeError, AttributeError):
        import re as _re
        m = _re.search(r'"?searchId"?\s*[:=]\s*"?([\w-]+)', full)
        search_id = m.group(1) if m else None
    if not search_id:
        sys.stderr.write("[mcp error] could not find searchId in search response\n")
        sys.exit(1)

    args = {"searchId": search_id}
    if "--types" in flags:
        args["objectTypes"] = [t.strip() for t in flags["--types"].split(",") if t.strip()]
    if "--name" in flags:
        args["assetName"] = flags["--name"]

    print(f"\n[store] Inserting from searchId {search_id}...", flush=True)
    texts, err = call_mcp("insert_from_creator_store", args, timeout=120)
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)


# ── addrig: clone Rig1 in Workspace.FIGURES ───────────────────────────────────

def cmd_addrig(argv: list[str]):
    name_expr = _lua_str(argv[0]) if argv else "nil"

    lua = f"""
local fig = workspace:FindFirstChild("FIGURES")
assert(fig, "Workspace.FIGURES not found")
local src = fig:FindFirstChild("Rig1")
assert(src, "Rig1 not found in FIGURES — nothing to clone")

local name = {name_expr}
if not name then
    local n = 2
    while fig:FindFirstChild("Rig" .. n) do n += 1 end
    name = "Rig" .. n
end
assert(not fig:FindFirstChild(name), "'" .. name .. "' already exists in FIGURES")

local rigCount = 0
for _, c in ipairs(fig:GetChildren()) do
    if c:FindFirstChildOfClass("Humanoid") then rigCount += 1 end
end

local clone = src:Clone()
clone.Name = name

-- Rig1's motors may be disconnected (active plugin session nils Part0).
-- Restore canonical R6 connections on the clone so it arrives healthy;
-- the plugin's FIGURES auto-detect will manage its session state itself.
local JOINT_PARENT = {{
    RootJoint = "HumanoidRootPart", Neck = "Torso",
    ["Right Shoulder"] = "Torso", ["Left Shoulder"] = "Torso",
    ["Right Hip"] = "Torso", ["Left Hip"] = "Torso",
}}
for jName, pName in pairs(JOINT_PARENT) do
    local container = clone:FindFirstChild(pName)
    local motor = container and container:FindFirstChild(jName)
    if motor and motor:IsA("Motor6D") then
        motor.Part0 = container
    end
end

clone.Parent = fig
clone:PivotTo(src:GetPivot() * CFrame.new(5 * rigCount, 0, 0))
return string.format("Added rig '%s' (offset +%d studs X); plugin auto-detect will pick it up", name, 5 * rigCount)
"""
    texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"}, timeout=30)
    _print(texts)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)


# ── scene: pull/push animation scenes to disk (version control) ──────────────

SCENES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "MultiAnimation", "scenes")

_SCENE_PULL_LUA = """
local HttpService = game:GetService("HttpService")
local mad = game:GetService("ServerStorage"):FindFirstChild("MultiAnimationData")
assert(mad, "ServerStorage.MultiAnimationData not found")
local scene = mad:FindFirstChild(%s)
assert(scene, "scene not found: " .. %s)

local function r6(v) return math.floor(v * 1e6 + 0.5) / 1e6 end
local function cfTo(cf)
    local c = { cf:GetComponents() }
    for i = 1, 12 do c[i] = r6(c[i]) end
    return c
end
local function poseTo(p)
    local kids = {}
    for _, ch in ipairs(p:GetChildren()) do
        if ch:IsA("Pose") then table.insert(kids, poseTo(ch)) end
    end
    table.sort(kids, function(a, b) return a.name < b.name end)
    return { name = p.Name, cframe = cfTo(p.CFrame), weight = r6(p.Weight), children = kids }
end

local out = { scene = scene.Name, kfs = {}, modules = {} }
for _, child in ipairs(scene:GetChildren()) do
    if child:IsA("KeyframeSequence") then
        local frames = {}
        for _, kf in ipairs(child:GetChildren()) do
            if kf:IsA("Keyframe") then
                local poses = {}
                for _, p in ipairs(kf:GetChildren()) do
                    if p:IsA("Pose") then table.insert(poses, poseTo(p)) end
                end
                table.insert(frames, { time = r6(kf.Time), poses = poses })
            end
        end
        table.sort(frames, function(a, b) return a.time < b.time end)
        table.insert(out.kfs, {
            name = child.Name, loop = child.Loop,
            authoredHipHeight = child.AuthoredHipHeight, keyframes = frames,
        })
    elseif child:IsA("ModuleScript") then
        table.insert(out.modules, { name = child.Name, source = child.Source })
    end
end
table.sort(out.kfs, function(a, b) return a.name < b.name end)
table.sort(out.modules, function(a, b) return a.name < b.name end)
-- Tool responses truncate at ~100k chars; return one slice per call and let
-- the Python side reassemble ("<total>|<slice>").
local json = HttpService:JSONEncode(out)
local off = %d
return #json .. "|" .. string.sub(json, off, off + 89999)
"""

_SCENE_PUSH_LUA = """
local HttpService = game:GetService("HttpService")
local data = HttpService:JSONDecode(%s)
local targetName = %s

local ss = game:GetService("ServerStorage")
local mad = ss:FindFirstChild("MultiAnimationData")
if not mad then
    mad = Instance.new("Folder")
    mad.Name = "MultiAnimationData"
    mad.Parent = ss
end
local old = mad:FindFirstChild(targetName)
if old then old:Destroy() end
local sceneF = Instance.new("Folder")
sceneF.Name = targetName

local function buildPose(d, parent)
    local p = Instance.new("Pose")
    p.Name = d.name
    p.CFrame = CFrame.new(unpack(d.cframe))
    p.Weight = d.weight or 1
    p.EasingStyle = Enum.PoseEasingStyle.Linear
    p.EasingDirection = Enum.PoseEasingDirection.Out
    p.Parent = parent
    for _, c in ipairs(d.children or {}) do buildPose(c, p) end
end

local nk = 0
for _, k in ipairs(data.kfs or {}) do
    local kfs = Instance.new("KeyframeSequence")
    kfs.Name = k.name
    kfs.Loop = k.loop and true or false
    kfs.AuthoredHipHeight = k.authoredHipHeight or 0
    for _, fr in ipairs(k.keyframes or {}) do
        local kf = Instance.new("Keyframe")
        kf.Time = fr.time
        for _, p in ipairs(fr.poses or {}) do buildPose(p, kf) end
        kf.Parent = kfs
        nk += 1
    end
    kfs.Parent = sceneF
end
for _, m in ipairs(data.modules or {}) do
    local ms = Instance.new("ModuleScript")
    ms.Name = m.name
    ms.Source = m.source
    ms.Parent = sceneF
end
sceneF.Parent = mad
return string.format("pushed '%%s' — %%d KFS, %%d keyframes, %%d module(s)",
    targetName, #(data.kfs or {}), nk, #(data.modules or {}))
"""


def cmd_scene(argv: list[str]):
    sub = argv[0] if argv else "list"
    rest = argv[1:]

    if sub == "list":
        texts, err = call_mcp("execute_luau", {"code": """
local mad = game:GetService("ServerStorage"):FindFirstChild("MultiAnimationData")
if not mad then return "(no MultiAnimationData in ServerStorage)" end
local t = {}
for _, c in ipairs(mad:GetChildren()) do
    if c:IsA("Folder") then table.insert(t, c.Name) end
end
table.sort(t)
return #t > 0 and table.concat(t, "\\n") or "(no scenes)"
""", "datamodel_type": "Edit"})
        print("In Studio:")
        for t in texts:
            for line in t.splitlines():
                print(f"  {line}")
        if err:
            sys.stderr.write(f"[mcp error] {err}\n")
        print("On disk:")
        if os.path.isdir(SCENES_DIR):
            names = sorted(d for d in os.listdir(SCENES_DIR)
                           if os.path.isdir(os.path.join(SCENES_DIR, d)))
            for n in names:
                print(f"  {n}")
            if not names:
                print("  (none)")
        else:
            print("  (none)")
        return

    if sub == "pull":
        if not rest:
            sys.exit("Usage: mcp.py scene pull <SceneName>")
        name = rest[0]
        parts, off, total = [], 1, None
        while total is None or off <= total:
            lua = _SCENE_PULL_LUA % (_lua_str(name), _lua_str(name), off)
            texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"},
                                  timeout=30)
            if err:
                _print(texts)
                sys.stderr.write(f"[mcp error] {err}\n")
                sys.exit(1)
            payload = "\n".join(texts)
            head, slice_ = payload.split("|", 1)
            total = int(head)
            parts.append(slice_)
            off += 90000
        data = json.loads("".join(parts))

        out_dir = os.path.join(SCENES_DIR, name)
        os.makedirs(out_dir, exist_ok=True)
        written = []
        for kfs in data.get("kfs", []):
            path = os.path.join(out_dir, kfs["name"] + ".json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(kfs, f, indent=2, sort_keys=True)
                f.write("\n")
            written.append(os.path.basename(path))
        for mod in data.get("modules", []):
            path = os.path.join(out_dir, mod["name"] + ".lua")
            with open(path, "w", encoding="utf-8") as f:
                f.write(mod["source"])
            written.append(os.path.basename(path))
        manifest = {
            "scene": name,
            "kfs": sorted(k["name"] for k in data.get("kfs", [])),
            "modules": sorted(m["name"] for m in data.get("modules", [])),
        }
        with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"Pulled '{name}' → {os.path.relpath(out_dir)} ({', '.join(written)})")
        return

    if sub == "push":
        if not rest:
            sys.exit("Usage: mcp.py scene push <SceneName> [--as <TargetName>]")
        name = rest[0]
        target = name
        if len(rest) >= 3 and rest[1] == "--as":
            target = rest[2]

        src_dir = os.path.join(SCENES_DIR, name)
        manifest_path = os.path.join(src_dir, "manifest.json")
        if not os.path.exists(manifest_path):
            sys.exit(f"No pulled scene at {src_dir} — run `mcp scene pull {name}` first")
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)

        data = {"scene": target, "kfs": [], "modules": []}
        for kname in manifest.get("kfs", []):
            with open(os.path.join(src_dir, kname + ".json"), encoding="utf-8") as f:
                data["kfs"].append(json.load(f))
        for mname in manifest.get("modules", []):
            with open(os.path.join(src_dir, mname + ".lua"), encoding="utf-8") as f:
                data["modules"].append({"name": mname, "source": f.read()})

        lua = _SCENE_PUSH_LUA % (_lua_str(json.dumps(data)), _lua_str(target))
        texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"}, timeout=30)
        _print(texts)
        if err:
            sys.stderr.write(f"[mcp error] {err}\n")
            sys.exit(1)
        return

    print("Usage: mcp.py scene list | pull <name> | push <name> [--as <target>]", file=sys.stderr)
    sys.exit(1)


# ── daemon server ─────────────────────────────────────────────────────────────

class _ProxySession:
    """One long-lived StudioMCP.exe with priming and auto-recovery."""

    def __init__(self):
        self.proc = None
        self.results: queue.Queue = queue.Queue()
        self.msg_id = 1
        self.primed = False

    def _alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def _spawn(self) -> str | None:
        self.results = queue.Queue()
        self.msg_id = 1
        self.primed = False
        try:
            self.proc = subprocess.Popen(
                MCP_CMD, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, text=True,
            )
        except FileNotFoundError:
            return "cmd.exe not found"

        def _read(p=self.proc, q=self.results):
            for raw in p.stdout:
                raw = raw.strip()
                if raw:
                    try:
                        q.put(json.loads(raw))
                    except json.JSONDecodeError:
                        pass
        threading.Thread(target=_read, daemon=True).start()

        self.proc.stdin.write(_INIT)
        self.proc.stdin.flush()
        deadline = time.time() + 6
        while time.time() < deadline:
            try:
                if self.results.get(timeout=0.2).get("id") == 1:
                    return None
            except queue.Empty:
                pass
        return "proxy init handshake timed out"

    def _next_id(self) -> int:
        self.msg_id += 1
        return self.msg_id

    def _prime(self) -> str | None:
        studios = []
        for _ in range(5):
            d = _rpc(self.proc, self.results, self._next_id(), "list_roblox_studios", {}, 10)
            if d is not None:
                texts, _ = _result_texts(d)
                try:
                    studios = (json.loads(texts[0]) if texts else {}).get("studios", [])
                except (json.JSONDecodeError, IndexError):
                    studios = []
            if studios:
                break
            time.sleep(1)
        if not studios:
            return "no Studio instance connected"
        chosen = next((s for s in studios if s.get("active")), studios[0])
        _rpc(self.proc, self.results, self._next_id(), "set_active_studio",
             {"studio_id": chosen["id"]}, 10)
        self.primed = True
        return None

    def call(self, tool: str, args: dict, timeout: int) -> tuple[list[str], str | None]:
        for attempt in (1, 2):
            if not self._alive():
                err = self._spawn()
                if err:
                    return [], err
            if not self.primed and tool not in ("list_roblox_studios", "set_active_studio"):
                err = self._prime()
                if err:
                    return [], err
            try:
                d = _rpc(self.proc, self.results, self._next_id(), tool, args, timeout)
            except BrokenPipeError:
                d = None
                self.proc = None   # force respawn on retry
            if d is None:
                if attempt == 1:
                    self.proc = None
                    continue
                return [], f"timeout after {timeout}s — Studio might not be open"
            if "error" in d:
                return [], d["error"].get("message", "MCP error")
            texts, is_err = _result_texts(d)
            full = "\n".join(texts)
            # Studio restarted → stale active-studio. Re-prime and retry once.
            stale = (
                "Unable to find an active Studio" in full
                or "previously active Studio has disconnected" in full
                or "doesn't have a place opened" in full
            )
            if stale and attempt == 1:
                self.primed = False
                continue
            return texts, ("Lua error (see output above)" if is_err else None)
        return [], "daemon: unreachable"


def _daemon_serve():
    """Foreground daemon loop: serve call_mcp requests over a Unix socket."""
    import socket
    if os.path.exists(DAEMON_SOCK):
        os.unlink(DAEMON_SOCK)

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(DAEMON_SOCK)
    srv.listen(4)
    with open(DAEMON_PID, "w") as f:
        f.write(str(os.getpid()))

    session = _ProxySession()
    print(f"[daemon] listening on {DAEMON_SOCK} (pid {os.getpid()})", flush=True)

    try:
        while True:
            conn, _ = srv.accept()
            try:
                buf = b""
                conn.settimeout(10)
                while not buf.endswith(b"\n"):
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    buf += chunk
                if not buf:
                    conn.close(); continue
                req = json.loads(buf.decode())

                if req.get("cmd") == "stop":
                    conn.sendall(b'{"texts": ["daemon stopping"], "err": null}\n')
                    conn.close()
                    break
                if req.get("cmd") == "ping":
                    alive = session._alive()
                    conn.sendall((json.dumps({
                        "texts": [f"daemon up (pid {os.getpid()}, proxy {'alive' if alive else 'idle'})"],
                        "err": None}) + "\n").encode())
                    conn.close(); continue

                tool = req.get("tool", "")
                args = req.get("args", {})
                timeout = int(req.get("timeout", 15))
                conn.settimeout(timeout + 60)
                texts, err = session.call(tool, args, timeout)
                conn.sendall((json.dumps({"texts": texts, "err": err}) + "\n").encode())
            except (OSError, json.JSONDecodeError) as e:
                try:
                    conn.sendall((json.dumps({"texts": [], "err": f"daemon: {e}"}) + "\n").encode())
                except OSError:
                    pass
            finally:
                conn.close()
    finally:
        srv.close()
        for p in (DAEMON_SOCK, DAEMON_PID):
            if os.path.exists(p):
                os.unlink(p)
        if session.proc is not None:
            session.proc.kill()
        print("[daemon] stopped", flush=True)


def _daemon_send_cmd(cmd: str) -> tuple[list[str], str | None] | None:
    import socket
    if not os.path.exists(DAEMON_SOCK):
        return None
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect(DAEMON_SOCK)
        s.sendall((json.dumps({"cmd": cmd}) + "\n").encode())
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        s.close()
        if not buf:
            return None
        d = json.loads(buf.decode())
        return d.get("texts", []), d.get("err")
    except (OSError, json.JSONDecodeError):
        return None


def cmd_daemon(argv: list[str]):
    sub = argv[0] if argv else "status"

    if sub == "run":
        _daemon_serve()
        return

    if sub == "start":
        if _daemon_send_cmd("ping"):
            print("daemon already running")
            return
        if os.path.exists(DAEMON_SOCK):
            os.unlink(DAEMON_SOCK)   # stale socket
        log = open(DAEMON_LOG, "a")
        subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "daemon", "run"],
            stdout=log, stderr=log, start_new_session=True,
        )
        # Wait for the socket to appear.
        for _ in range(20):
            time.sleep(0.25)
            r = _daemon_send_cmd("ping")
            if r:
                print(r[0][0])
                return
        sys.exit(f"daemon failed to start — see {DAEMON_LOG}")

    if sub == "stop":
        r = _daemon_send_cmd("stop")
        if r:
            print(r[0][0])
        else:
            # Socket gone or unresponsive — try the pidfile.
            if os.path.exists(DAEMON_PID):
                try:
                    with open(DAEMON_PID) as f:
                        os.kill(int(f.read().strip()), 15)
                    print("daemon killed via pidfile")
                except (OSError, ValueError):
                    print("daemon not running")
                for p in (DAEMON_SOCK, DAEMON_PID):
                    if os.path.exists(p):
                        os.unlink(p)
            else:
                print("daemon not running")
        return

    if sub == "status":
        r = _daemon_send_cmd("ping")
        print(r[0][0] if r else "daemon not running")
        return

    print("Usage: mcp.py daemon start|stop|status", file=sys.stderr)
    sys.exit(1)


def cmd_raw(tool: str, argv: list[str]):
    args = {}
    if argv:
        try:
            args = json.loads(argv[0])
        except json.JSONDecodeError:
            args = {"input": argv[0]}
    texts, err = call_mcp(tool, args)
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
    _print(texts)


# ── entry point ───────────────────────────────────────────────────────────────

_COMMANDS = {
    "luau":     cmd_luau,
    "console":  cmd_console,
    "tail":     cmd_tail,
    "tree":     cmd_tree,
    "inspect":  cmd_inspect,
    "read":     cmd_read,
    "grep":     cmd_grep,
    "search":   cmd_search,
    "state":    cmd_state,
    "capture":  cmd_capture,
    "nav":      cmd_nav,
    "studios":  cmd_studios,
    "check":    cmd_check,
    "drift":    cmd_drift,
    "test":     cmd_test,
    "deploy":   cmd_deploy,
    "playtest": cmd_playtest,
    "gen":      cmd_gen,
    "store":    cmd_store,
    "addrig":   cmd_addrig,
    "daemon":   cmd_daemon,
    "scene":    cmd_scene,
}

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    sub = sys.argv[1]
    rest = sys.argv[2:]

    handler = _COMMANDS.get(sub)
    if handler:
        handler(rest)
    else:
        cmd_raw(sub, rest)


if __name__ == "__main__":
    main()
