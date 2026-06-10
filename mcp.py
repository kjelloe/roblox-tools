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
    mcp.py <tool> [json_args]     call any raw tool by name

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
"""

import os
import sys
import json
import subprocess
import threading
import queue
import time

MCP_CMD = ["cmd.exe", "/c", r"C:\Users\kjell\AppData\Local\Roblox\mcp.bat"]

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
    """Extract (texts, isError) from a tools/call response."""
    result = d.get("result", {})
    content = result.get("content", [])
    texts = [c["text"] for c in content if c.get("type") == "text"]
    return texts, result.get("isError", False)


def call_mcp(tool: str, args: dict, timeout: int = 15) -> tuple[list[str], str | None]:
    """
    Call a single MCP tool.  Returns (texts, error_or_None).

    Active-studio state is per proxy process, and this helper spawns a fresh
    StudioMCP.exe per call — so every call is primed with list_roblox_studios +
    set_active_studio before the real tool is sent.
    """
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
    texts, err = call_mcp("screen_capture", {})
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
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
    "studios":  cmd_studios,
    "check":    cmd_check,
    "drift":    cmd_drift,
    "test":     cmd_test,
    "deploy":   cmd_deploy,
    "playtest": cmd_playtest,
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
