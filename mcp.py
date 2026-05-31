#!/usr/bin/env python3
"""
mcp.py — Roblox Studio MCP helper.

Usage:
    mcp.py luau <code>            execute Lua in Studio (code string)
    mcp.py luau -                 execute Lua read from stdin
    mcp.py luau -f <file.lua>     execute a Lua file
    mcp.py console [filter]       print Studio console output (optionally filtered)
    mcp.py tree [path]            search_game_tree  (default: game)
    mcp.py inspect <path>         inspect_instance
    mcp.py capture                screen_capture
    mcp.py studios                list open Studio instances
    mcp.py <tool> [json_args]     call any raw tool by name

Examples:
    mcp.py luau "return workspace.Name"
    mcp.py luau - <<'EOF'
        local t={}
        for _,c in ipairs(workspace:GetChildren()) do table.insert(t,c.Name) end
        return table.concat(t,'|')
    EOF
    mcp.py luau -f tests/test_scrubber.lua
    mcp.py console MultiAnimation
    mcp.py tree workspace.FIGURES
    mcp.py inspect workspace.FIGURES.Rig1
"""

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

def call_mcp(tool: str, args: dict, timeout: int = 15) -> tuple[list[str], str | None]:
    """
    Call a single MCP tool.  Returns (texts, error_or_None).
    """
    tool_msg = json.dumps({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {"name": tool, "arguments": args},
    }) + "\n"

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

    # Send INIT and wait for its response (server startup can take ~0.5 s)
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

    # Send tool call
    proc.stdin.write(tool_msg)
    proc.stdin.flush()
    proc.stdin.close()

    # Wait for tool response
    tool_deadline = time.time() + timeout
    while time.time() < tool_deadline:
        try:
            d = results.get(timeout=0.5)
            if d.get("id") == 2:
                proc.kill()
                if "error" in d:
                    return [], d["error"].get("message", "MCP error")
                result = d.get("result", {})
                is_err = result.get("isError", False)
                content = result.get("content", [])
                texts = [c["text"] for c in content if c.get("type") == "text"]
                # Return text even on error (it contains the Lua traceback)
                return texts, ("Lua error (see output above)" if is_err else None)
        except queue.Empty:
            pass

    proc.kill()
    return [], f"timeout after {timeout}s — Studio might not be open"


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

    texts, err = call_mcp("execute_luau", {"code": code, "timeout": timeout - 3})
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
    "luau":    cmd_luau,
    "console": cmd_console,
    "tree":    cmd_tree,
    "inspect": cmd_inspect,
    "capture": cmd_capture,
    "studios": cmd_studios,
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
