# MultiAnimation — Dev Tooling

Already built: `build.py`, `export.py`, `run_tests.py`, `watch.py`, `hotpatch.py`,
and `~/GIT/Roblox/mcp.py` with subcommands:
`luau / console / tail / tree / inspect / read / grep / search / state /
capture / studios / check / drift / test / deploy / playtest`.

`mcp nav <x> <y> <z>` (or `mcp nav <instance.path>`) walks the play-mode
character to a target: it tries the `character_navigation` MCP tool (which
requires `datamodel_type: "Client"` since the July 2026 Studio update and whose
client host is flaky — "Target is closed" in stale sessions) and falls back to
a real `Humanoid:MoveTo` walk via `execute_luau`, preserving Touched semantics.

`mcp capture` saves the viewport screenshot to `/tmp/roblox_capture_<ms>.jpg`
and prints the path (newer Studio builds return an image block and require a
`capture_id`, both handled by mcp.py). Note: in edit mode, scripted viewport
camera moves only stick if `CameraType = Scriptable` is set before writing
`CFrame` (restore `Fixed` after).

Tools 3–5 below were implemented from these specs (kept for reference).
Tools 6–8 describe the second wave (also implemented).

---

## Tool 6 — `mcp check` + watch.py integration

Compile-checks Lua files in Studio via `loadstring(src)` — compiles without executing,
so syntax errors surface instantly instead of after build → reload → console error.

```bash
mcp check MultiAnimation/plugin/core/Exporter.lua    # one or more files
```

`watch.py` runs this automatically on every changed file before building.
If Studio is unreachable the check is skipped with a warning (build proceeds);
a confirmed compile error skips the build until the next save.
Disable with `python3 watch.py --no-check`.

The `[string "…"]` chunk name in loadstring errors is rewritten to the real filename.

## Tool 7 — `mcp drift`

Diffs local source against what is actually deployed in Studio. Catches the
"rewrote the module but the old version is still deployed" bug class.

```bash
mcp drift     # exit 0 = in sync, 1 = drift or not deployed
```

Targets are listed in `DRIFT_TARGETS` in `mcp.py`
(currently `game/MultiAnimPlayer.lua` ↔ `ServerStorage.MultiAnimationData.MultiAnimPlayer`).
Prints a unified diff (truncated at 60 lines) and suggests `mcp deploy` to fix.

## Tool 8 — `mcp playtest`

Automates the manual F5 loop: deploy → enter play mode → watch console → verdict.

```bash
mcp playtest                       # full cycle, 45s timeout
mcp playtest --no-deploy           # skip the deploy step
mcp playtest --timeout 60          # longer scenes
mcp playtest --marker "Done."      # custom success marker
```

PASS when the success marker (default `FINISHED`) appears in new console output;
FAIL on `ERROR` / `FAIL` / `Stack Begin`; TIMEOUT otherwise. Play mode is always
exited afterwards, even on Ctrl+C. Requires a test script in ServerScriptService
that prints the marker (e.g. `tests/test_player.lua`).

---

The original specs for tools 3–5 follow.
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

**Test output contract:** every test file must end its returned string with a
`=== N passed, M failed ===` line (plus `ALL TESTS PASSED` or
`FAILURES DETECTED`). `run_tests.py` regex-parses that summary for the counts —
a file that returns any other format still shows PASS/FAIL status but reports
**0/0 cases**, silently vanishing from the suite total (this hid
`test_easing_core`'s 20 cases for a long time).

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
| `hotpatch.py` | `MultiAnimation/hotpatch.py` | Built |
| `mcp test` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp deploy` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp tail` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp check` (+ watch.py hook) | `~/GIT/Roblox/mcp.py` | Built |
| `mcp drift` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp playtest` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp read/grep/search/state` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp gen model/mesh/material/wait` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp store [--insert]` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp addrig [name]` | `~/GIT/Roblox/mcp.py` | Built |
| `mcp daemon start/stop/status` | `~/GIT/Roblox/mcp.py` | Built |
| `devsync.py` + dev loader | `MultiAnimation/devsync.py`, `plugin/devloader.lua` | Built |

## Tool 9 — `mcp gen` (AI generation)

```bash
mcp gen model "a wooden crate with adjustable size"   # ProceduralModel, auto-inserts
mcp gen model "a crate" --wait                        # block until job completes
mcp gen mesh "medieval sword" --size 1,4,0.3 --tris 5000
mcp gen material "rough mossy stone" --base Rock --pattern Organic
mcp gen wait <generationId> [--timeout N]             # await a submitted job
```

Notes: `gen model` is async — returns a generation ID immediately; `--wait` polls via
`wait_job_finished` and reports the inserted model path (e.g. `Workspace.WoodenCrate`).
`gen material` is synchronous — returns `{BaseMaterial, Name}`; set those on a BasePart's
`Material` and `MaterialVariant` properties to use it. `--base` must be a valid
Roblox material enum name (Rock, Wood, Metal, …); `--pattern` is Regular or Organic.

## Tool 10 — `mcp store` (Creator Store)

```bash
mcp store "low poly tree"                       # search → searchId + objectTypes
mcp store "low poly tree" --insert              # search + insert first match
mcp store "low poly tree" --insert --name Pine --types tree,plant
```

## Tool 11 — `mcp addrig`

```bash
mcp addrig            # clone Rig1 → next free RigN, offset +5 studs X per existing rig
mcp addrig Villain    # explicit name
```

Restores canonical R6 Motor6D connections on the clone (Rig1's may be nil'd by an
active plugin session), then parents it to FIGURES — the plugin's ChildAdded
auto-detect picks it up, captures rest pose, and manages its motors from there.
Verified live: `[MultiAnimation] Auto-detected rig: Rig3`.

## Tool 12 — `mcp daemon` (persistent proxy)

Without the daemon every `mcp` call spawns a fresh `StudioMCP.exe` and re-primes the
active studio (~5–10 s of overhead per call). The daemon keeps one proxy alive behind
a Unix socket; all `mcp.py` commands and any script importing `call_mcp`
(`run_tests.py`, `hotpatch.py`, `devsync.py`) use it automatically and fall back to
spawn-per-call when it isn't running.

```bash
mcp daemon start     # background; socket /tmp/roblox_mcp_daemon.sock
mcp daemon status
mcp daemon stop
```

Measured: single call 0.07 s (was ~7 s); full 146-case test suite 0.6 s (was ~13 s).
The daemon self-heals — if Studio restarts (stale studio ID) or the proxy dies, it
re-spawns/re-primes and retries once. Log: `/tmp/roblox_mcp_daemon.log`.

## Tool 13 — `devsync` (hot-reload, no Studio restart)

Eliminates the build → restart-Studio cycle for plugin development.

```bash
python3 devsync.py install     # one-time; restart Studio once after
python3 devsync.py             # watch mode: every .lua save hot-reloads the plugin
python3 devsync.py push        # one-shot push
python3 devsync.py uninstall   # back to the normal build.py workflow
```

**Mechanism:** pushes the source tree as fresh ModuleScripts into
`CoreGui.__MultiAnimDevSrc` (never saved with the place; fresh instances bust the
require cache) and bumps a `Version` attribute. The `MultiAnimationDevLoader` stub
plugin (built from `plugin/devloader.lua`) watches the attribute and re-runs
`init.server.lua` via `loadstring` + `setfenv` with `script` → dev tree and
`plugin` → loader handle. `init.server.lua` registers `_G.__MultiAnimTeardown`
(stop playback, reconnect motors, disconnect DataModel-level connections, destroy
widget + toolbar) which the next boot invokes first.

`install` renames `MultiAnimation.rbxmx` → `.disabled` so the two plugin instances
don't fight; `uninstall` restores it. Push takes ~0.4 s with the daemon running.
`build.py` cooperates: when the DevLoader is installed it writes the build to
`.disabled` directly (a plain build used to re-enable the static plugin, which
then shadowed the dev tree with stale code after the next Studio restart).

**Hotpatch is overwritten by the next Export:** `Exporter.export` (the ⬆ button
or the `exportScene` bridge cmd) re-deploys game modules from the *plugin's*
embedded copies. If you hotpatch a `game/` fix, `devsync.py push` before the
next export — otherwise the export silently rolls the deployed module back to
the dev tree's older copy.

**After every Studio restart:** the dev source tree lives in CoreGui and is not
saved with the place, so the loader idles ("waiting for first devsync push")
until you run `devsync.py push`. A reload also resets the recorder session —
save to a named slot before pushing mid-authoring and load it back after.

The teardown changes in `init.server.lua` are inert for the normally installed
plugin (`_G` is per plugin VM, empty on every normal load).

## Tool 14 — `mcp scene` (animation version control)

The exported animation data (KeyframeSequences + track ModuleScripts) lives only
inside the binary `.rbxl` — `mcp scene` makes it text, diffable, and committable.

```bash
mcp scene list                       # scenes in Studio vs scenes on disk
mcp scene pull Scene_001             # → MultiAnimation/scenes/Scene_001/
mcp scene push Scene_001             # rebuild in ServerStorage from disk
mcp scene push Scene_001 --as Copy   # push under a different name
```

On-disk format per scene: `<Rig>_Joints.json` (keyframes sorted by time, pose
tree nested, CFrames as 12-number arrays rounded to 6 decimals), track
ModuleScripts as verbatim `.lua`, plus `manifest.json`. Round-trip verified
byte-identical (pull → push --as → pull → diff).

## Tool 15 — TestBridge (UI integration tests)

`plugin/core/TestBridge.lua` exposes a `BindableFunction` in CoreGui
(`__MultiAnimTestBridge`) that lets `execute_luau` — a different Lua VM — drive
the live panel: `ping`, `getRigs`, `getActiveRigs`, `setActiveRig`, `setFrame`,
`stepFrame`, `addKeyframe`, `getFrames`, `deleteKeyframe`, `getCurrentFrame`,
`getFrameCount`, plus command groups for Simple Mode, camera, easing, effects,
spawned effects (`addSpawnedEffect`/`getSpawnedEffects`/`deleteSpawnedEffect` —
same path as the overlay's Add to Frame, including gizmo and preview fire),
prop attachments (`attachProp`/`detachProp`/`getPropAttachments`),
subtitles, sessions, playback tab, and `exportScene` (same path as the Export
button). Payloads cross the VM boundary as JSON strings. The full command list
is the `cmds` table in `init.server.lua`.

`tests/test_ui_bridge.lua` (18 cases) covers exclusive rig selection, frame
clamping, and a keyframe add/delete round-trip at a parking frame — restoring
the user's active rig and timeline position afterwards. The bridge is destroyed
on devsync teardown and on plugin unload.

## Backlog

Empty — all planned dev tools are built. (Daemon now auto-starts on first
`call_mcp` use; opt out with `MCP_NO_DAEMON=1`.)
