# MultiAnimation — Dev Tooling Backlog

Already built: `build.py`, `run_tests.py`, `watch.py`, `~/GIT/Roblox/mcp.py`.

The three tools below are designed but not yet implemented.
Each spec is self-contained — no need to read prior conversations to build them.

---

## Tool 3 — `hotpatch.py`

**Purpose:** Push a single Lua module into the running Studio session without a
full plugin rebuild or Studio restart. Cuts the iteration loop from
`edit → build → restart Studio → reload plugin` down to `edit → hotpatch → test`.

**Scope:** Only works for pure-logic modules that hold no widget references —
`core/Interpolator`, `core/Recorder`, `core/Exporter`, `game/MultiAnimPlayer`, etc.
Does **not** work for `init.server.lua` or UI modules that own `InstancedGui` objects,
because those modules run once at plugin load and their state lives in closures.

**Usage:**
```bash
python3 hotpatch.py plugin/core/Interpolator.lua
python3 hotpatch.py game/MultiAnimPlayer.lua
```

**Mechanism:**

For `game/MultiAnimPlayer.lua`, the target is `ServerStorage.MultiAnimationData.MultiAnimPlayer`.
Overwrite its `.Source` property via `execute_luau`:
```lua
local m = game:GetService("ServerStorage")
          :FindFirstChild("MultiAnimationData")
          :FindFirstChild("MultiAnimPlayer")
m.Source = [[ <new source> ]]
```
Any script that subsequently calls `require(MultiAnimPlayer)` gets the new code
(Roblox re-evaluates `require` when `.Source` changes).

For plugin `core/` modules, the running plugin already `require()`'d them at load
time and cached the module table. The only safe hotpatch strategy is to call a
known re-init function if one exists, or to reload the whole plugin.
Hotpatch is therefore most useful for `game/MultiAnimPlayer` during playback testing.

**Implementation sketch:**
```python
# hotpatch.py
import sys, os
sys.path.insert(0, os.path.expanduser("~/GIT/Roblox"))
from mcp import call_mcp

TARGET_MAP = {
    "game/MultiAnimPlayer.lua": (
        "ServerStorage.MultiAnimationData.MultiAnimPlayer",
        "ModuleScript",
    ),
    # extend as needed
}

def hotpatch(rel_path: str):
    key = rel_path.replace("\\", "/")
    if key not in TARGET_MAP:
        sys.exit(f"No hotpatch target configured for '{key}'")
    studio_path, _ = TARGET_MAP[key]
    here = os.path.dirname(os.path.abspath(__file__))
    source = open(os.path.join(here, rel_path), encoding="utf-8").read()
    escaped = source.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    # Use [[ ]] long string to avoid escaping issues
    lua = f"""
        local m = game
        for part in string.gmatch("{studio_path}", "[^.]+") do
            m = m:FindFirstChild(part) or game:GetService(part)
        end
        assert(m, "hotpatch target not found: {studio_path}")
        m.Source = [==[{source}]==]
        return "patched: {studio_path}"
    """
    texts, err = call_mcp("execute_luau", {"code": lua, "timeout": 10})
    if err:
        sys.exit(f"ERROR: {err}")
    print("\n".join(texts))
```

**Caveats:**
- The `[==[…]==]` long-string delimiter must not appear in the source being patched.
  Use a level-3 or level-4 delimiter if necessary (`[====[…]====]`).
- Cached `require()` results mean in-plugin module tables are NOT updated.
  For plugin modules, rebuild + reload is still required.

---

## Tool 4 — `mcp.py` additions: `test` and `deploy` subcommands

**Purpose:** Two new subcommands added to the existing `~/GIT/Roblox/mcp.py`
so common operations are one-liners from anywhere.

### `mcp test [pattern] [-v]`

Wraps `run_tests.py`. Discovers and runs `tests/test_*.lua` files matching an
optional glob pattern.

```bash
mcp test               # all tests
mcp test prop          # tests matching *prop*
mcp test exporter -v   # verbose output
```

**Implementation** — add to `_COMMANDS` in `mcp.py`:
```python
def cmd_test(argv: list[str]):
    """Forward to MultiAnimation/run_tests.py."""
    here = os.path.dirname(os.path.abspath(__file__))
    script = os.path.join(here, "MultiAnimation", "run_tests.py")
    result = subprocess.run([sys.executable, script] + argv)
    sys.exit(result.returncode)
```

Note: `mcp.py` will need `import subprocess` added at the top (it already has it).

---

### `mcp deploy`

Pushes `game/MultiAnimPlayer.lua` into `ServerStorage.MultiAnimationData` without
clicking the Export button in the plugin panel. Useful after rewriting the player
module mid-session without wanting to re-export a full scene.

```bash
mcp deploy
```

**Implementation:**
```python
def cmd_deploy(argv: list[str]):
    """Push game/MultiAnimPlayer.lua into ServerStorage.MultiAnimationData."""
    here = os.path.dirname(os.path.abspath(__file__))
    player_path = os.path.join(here, "MultiAnimation", "game", "MultiAnimPlayer.lua")
    source = open(player_path, encoding="utf-8").read()

    lua = f"""
        local ss = game:GetService("ServerStorage")
        local mad = ss:FindFirstChild("MultiAnimationData")
        assert(mad, "ServerStorage.MultiAnimationData not found — export a scene first")
        local existing = mad:FindFirstChild("MultiAnimPlayer")
        if existing then existing:Destroy() end
        local m = Instance.new("ModuleScript")
        m.Name = "MultiAnimPlayer"
        m.Source = [==[{source}]==]
        m.Parent = mad
        return "deployed MultiAnimPlayer (" .. #m.Source .. " bytes)"
    """
    texts, err = call_mcp("execute_luau", {"code": lua})
    if err:
        sys.stderr.write(f"[mcp error] {err}\n"); sys.stderr.flush()
        sys.exit(1)
    _print(texts)
```

**Caveats:** Same `[==[…]==]` delimiter caveat as `hotpatch.py`. If the source
ever contains `]==]`, switch to `[====[…]====]`.

---

## Tool 5 — `mcp.py` addition: `tail` subcommand

**Purpose:** Continuously poll `get_console_output` and print only new lines,
giving a live tail of the Studio output window. Eliminates the need to run
`mcp console` repeatedly after every `execute_luau` call.

```bash
mcp tail                    # all console output
mcp tail MultiAnimation     # filtered to lines containing "MultiAnimation"
```

**Behaviour:**
- Polls every 1.5 seconds
- Deduplicates lines already seen (tracks a set of seen messages or a line count)
- Prints new lines with a dim timestamp prefix
- Runs until `Ctrl+C`

**Implementation:**
```python
def cmd_tail(argv: list[str]):
    """Poll Studio console and print new lines. Ctrl+C to stop."""
    import time
    filt = argv[0].lower() if argv else ""
    seen: set[str] = set()

    print(f"Tailing Studio console{' (filter: ' + argv[0] + ')' if filt else ''}... (Ctrl+C to stop)\n")
    try:
        while True:
            texts, err = call_mcp("get_console_output", {}, timeout=8)
            if not err:
                for line in _fmt_console(texts, filt):
                    if line not in seen:
                        seen.add(line)
                        ts = time.strftime("%H:%M:%S")
                        print(f"  {ts}  {line}")
            time.sleep(1.5)
    except KeyboardInterrupt:
        print("\nStopped.")
```

**Caveat:** `get_console_output` returns the full console buffer each time,
not a delta. The `seen` set grows unboundedly in long sessions; for very long
sessions it may be worth resetting it or switching to line-number tracking.
A lightweight fix: store `(message, timestamp)` pairs and track the last N
seen rather than the full set.

---

## Summary

| Tool | File | Status |
|------|------|--------|
| `build.py` | `MultiAnimation/build.py` | Built |
| `run_tests.py` | `MultiAnimation/run_tests.py` | Built |
| `watch.py` | `MultiAnimation/watch.py` | Built |
| `mcp` alias | `~/GIT/Roblox/mcp.py` | Built |
| `hotpatch.py` | `MultiAnimation/hotpatch.py` | **Designed** |
| `mcp test` | add to `~/GIT/Roblox/mcp.py` | **Designed** |
| `mcp deploy` | add to `~/GIT/Roblox/mcp.py` | **Designed** |
| `mcp tail` | add to `~/GIT/Roblox/mcp.py` | **Designed** |
