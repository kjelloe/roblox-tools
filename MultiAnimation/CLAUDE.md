# MultiAnimation — Claude Code Instructions

## What This Is

A Roblox Studio **Plugin** for simultaneously animating multiple R6 rigs.
The animator poses rigs in the viewport, presses "Add Keyframe", and exports
the result as standard Roblox animation assets (`KeyframeSequence`) plus a
custom scale track (`ModuleScript`).

Full context: `SPEC.md`, `ARCHITECTURE.md`, `DATA_FORMAT.md`, `PHASES.md`.

---

## Directory Layout

```
MultiAnimation/
├── CLAUDE.md               ← you are here
├── SPEC.md                 ← functional requirements
├── ARCHITECTURE.md         ← system design and data flow
├── DATA_FORMAT.md          ← exact data structures (session, export, API)
├── PHASES.md               ← implementation roadmap with acceptance criteria
│
├── default.project.json    ← Rojo project file (kept for reference; build uses build.py)
│
├── plugin/                 ← Plugin source (built by build.py)
│   ├── init.server.lua     ← entry point
│   ├── ui/
│   │   ├── Panel.lua
│   │   ├── RigSelector.lua
│   │   ├── PropSelector.lua
│   │   ├── TrackLane.lua
│   │   ├── KeyframeMarker.lua
│   │   └── Scrubber.lua
│   ├── core/
│   │   ├── RigScanner.lua
│   │   ├── Recorder.lua
│   │   ├── JointCapture.lua
│   │   ├── ScaleCapture.lua
│   │   ├── PropCapture.lua
│   │   ├── CameraCapture.lua   ← viewport camera capture/preview (Phase 8)
│   │   ├── Timeline.lua
│   │   ├── Interpolator.lua
│   │   ├── PoseApplier.lua
│   │   ├── TestBridge.lua      ← CoreGui BindableFunction for UI tests
│   │   └── Exporter.lua
│   └── devloader.lua           ← devsync hot-reload stub (NOT in normal build)
│
└── game/                       ← in-game ModuleScripts (no plugin dep)
    ├── MultiAnimPlayer.lua     ← animation playback
    ├── CutsceneServer.lua      ← synchronized cutscene start (server)
    ├── CutsceneCamera.lua      ← client camera driver
    ├── LetterboxGui.lua        ← cinematic black bars (Phase 10)
    ├── PlayerRigProxy.lua      ← player→R6 rig resolver, clone/direct (Phase 10)
    ├── MultiAnimDataServer.lua ← server RemoteFunction: MultiAnimGetScene (Phase 10)
    └── CutscenePlayer.lua      ← client-side playback orchestrator (Phase 10)
```

---

## Roblox Context

- **Place file:** `../MultiAnimation.rbxl` (same directory as this folder, one level up)
- **Target rigs:** `Workspace.FIGURES.Rig1` and `Workspace.FIGURES.Rig2` — both R6
- **R6 joints:** `RootJoint`, `Neck`, `Right Shoulder`, `Left Shoulder`, `Right Hip`, `Left Hip`
- **R6 parts:** `Head`, `Torso`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg`, `HumanoidRootPart`
- **Plugin output path:** `%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx`

R6 detection: `Humanoid` present AND part named `Torso` present (not `UpperTorso`).
R15 detection: `Humanoid` present AND `UpperTorso` present.
Joint discovery: dynamic (`discoverMotors`) — filter: `motor.Parent.Parent == rig AND motor.Part1.Parent == rig`. Works for R6, R15, and custom rigs without hardcoded joint tables.

---

## MCP Access

The `Roblox_Studio` MCP server is registered project-scoped in `~/.claude.json`. Use the
`mcp__Roblox_Studio__*` tool family directly in Claude Code sessions.

For terminal use, `mcp.py` at `~/GIT/Roblox/mcp.py` is aliased as `mcp` in `~/.bashrc`:

```bash
mcp luau "return workspace.Name"           # inline Lua
mcp luau -f tests/test_exporter.lua        # run a test file
mcp console MultiAnimation                 # filtered console output
mcp tree ServerStorage.MultiAnimationData  # search_game_tree
mcp inspect workspace.FIGURES.Rig1        # inspect_instance
mcp capture                                # screen_capture
```

**Session start ritual every session:**
1. `list_roblox_studios` → `set_active_studio` with the returned ID
2. Quick verify: `execute_luau("return workspace.Name")` → should return `"Workspace"`

Studio must be open with the place loaded for MCP to work.

---

## Tooling

### build.py

`build.py` assembles the plugin from source files and copies it to the Roblox Plugins folder:

```bash
cd MultiAnimation
python3 build.py           # build and install
python3 build.py --dry-run # print XML to stdout only
```

Plugin is installed to `%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx`.
After building, reload the plugin in Studio: Plugins → Manage Plugins → reload MultiAnimation.

### Hot reload (devsync) — preferred dev loop

```bash
python3 devsync.py install     # one-time; restart Studio once after
python3 devsync.py             # watch: every .lua save hot-reloads the plugin (~0.4s)
python3 devsync.py uninstall   # back to build.py + manual reload
```

### Other dev scripts

```bash
python3 run_tests.py [pattern] [-v]   # full suite (~561 cases, 25 files), or `mcp test`
python3 watch.py                      # auto-build on save (when not using devsync)
python3 hotpatch.py game/MultiAnimPlayer.lua   # push one game/ module, or `mcp deploy`
mcp check <file.lua>                  # compile-check in Studio without executing
mcp drift                             # local vs deployed MultiAnimPlayer diff
mcp playtest                          # deploy → F5 → console watch → PASS/FAIL
mcp scene pull|push <name>            # animation data ↔ scenes/ (git-diffable)
```

The MCP daemon auto-starts on first use (~0.07s/call). See `DEV_TOOLS.md` for details.

---

## Coding Conventions

- **Lua 5.1** (Luau) — Roblox's dialect. Use `local` everywhere, no globals.
- **No services at module top level** — get services inside functions or pass as args.
  Exception: `local RunService = game:GetService("RunService")` at top of files that
  use it heavily.
- **Module pattern:**
  ```lua
  local MyModule = {}

  function MyModule.doThing(arg)
      -- ...
  end

  return MyModule
  ```
- **Events:** use `BindableEvent` for intra-plugin communication (UI → core).
- **No pcall wrapping everywhere** — only wrap calls to external/Roblox APIs that are
  known to error (e.g. `KeyframeSequence` validation, `plugin:GetSetting`).
- **Comments:** only where WHY is non-obvious. No docblocks.

---

## Key Constraints

- The plugin runs in **edit mode** only. Never call `game:GetService("Players")` from
  plugin code. `init.server.lua` starts with `if RunService:IsRunning() then return end`
  to guard against re-execution when play mode starts (the `.rbxmx` root Script runs
  again as a server script on F5 — `plugin` global is NOT nil there and cannot be used
  as a guard).
- `PoseApplier` must wrap all Motor6D writes in `ChangeHistoryService` waypoints to
  avoid polluting the undo stack. See `ARCHITECTURE.md`.
- `MultiAnimPlayer` (`game/`) must have **zero dependency** on plugin APIs. It only
  uses standard Roblox game APIs (`RunService`) only — no plugin dependency, no TweenService, no Animator.
- Scale changes use custom interpolation — do not use `AnimationTrack` for scale.
- KeyframeSequence `AuthoredHipHeight` should be set to `0` (let Animator handle it).

---

## Testing Approach

Each phase has acceptance criteria in `PHASES.md`. Test strategy per phase:

| Phase | How to test |
|-------|-------------|
| 1 | Open Studio, click toolbar button, check panel appears |
| 2 | Move a rig arm, press Add Keyframe, verify dot appears + inspect session data via `execute_luau` |
| 3 | Scrub timeline, verify Motor6D values change in viewport |
| 4 | Export, inspect `ServerStorage` via MCP `search_game_tree` + `inspect_instance` |
| 5 | Enter play mode, run test script, observe simultaneous animation |
| 6 | Manual: right-click dot, viewport click sync, Save As / Load overlay |
| 7 | Automated test suite in `tests/` — run via `mcp__Roblox_Studio__execute_luau` |

### Test files (`tests/`)

| File | What it covers |
|------|---------------|
| `test_joint_capture.lua` | Motor6D disconnect/capture/apply round-trip on Rig1; FK chain, computeWorldCFrames (20 cases) |
| `test_r15_joints.lua` | Dynamic motor discovery: mock R6/R15/accessory exclusion, disconnect/reconnect, capture/apply round-trip, live R15 skip (21 cases) |
| `test_interpolator.lua` | Timeline nav, `surrounding()` math, CFrame lerp |
| `test_scrubber.lua` | Scrubber drag math |
| `test_player.lua` | MultiAnimPlayer in-game playback (run in play mode) |
| `test_track_part.lua` | "Track Part" guard logic: BasePart check, name uniqueness, `Selection:Get()` |
| `test_prop_core.lua` | PropCapture round-trip; Recorder prop CRUD (13 cases) |
| `test_prop_interpolator.lua` | `getPropData` clamp/lerp/slerp; `getAllPropFrames` merge (13 cases) |
| `test_prop_exporter.lua` | `buildPropTracksSource` → valid Lua → `require()` structural check (14 cases) |
| `test_prop_serialization.lua` | CFrame `GetComponents()` round-trip; `Lerp` boundary + slerp (17 cases) |
| `test_rig_root_motion.lua` | rootTrack capture/apply/interpolate; whole-model lift on real Rig1 (15 cases) |
| `test_exporter.lua` | `Pose.CFrame` API; KFS structure; RootTracks whole-model positions; flat KFS format + parseKFS round-trip (36 cases) |
| `test_ui_bridge.lua` | UI integration via CoreGui TestBridge — rig selection, frame nav, KF round-trip (18 cases) |
| `test_camera_core.lua` | Camera keyframe CRUD; cut-vs-move interpolation; FOV lerp (17 cases) |
| `test_camera_exporter.lua` | CameraTrack source builder; cut flags; omit-if-empty (16 cases) |
| `test_ui_camera.lua` | Live camera capture, gizmo lifecycle, preview restore via TestBridge (17 cases) |
| `test_mirror_core.lua` | Keyframe mirror reflection math; involution; determinant; name-map round-trips (17 cases) |
| `test_ui_rigtools.lua` | Live add-rig + auto-detect; copy/paste/mirror through TestBridge (20 cases) |
| `test_effect_core.lua` | EffectRunner: classify, cycleAction, live fire, crossing-pointer playback (24 cases) |
| `test_effect_exporter.lua` | EffectTracks source builder; loadstring round-trip; omit-if-empty (13 cases) |
| `test_ui_effects.lua` | Effect track bridge integration: track, cycle, add/delete events, fire, untrack (18 cases) |
| `test_ui_simple.lua` | Simple Mode bridge integration: mode toggle, Add/Insert/Delete Frame management, Camera View capture-on-add, Play/Stop toggle, manipulable camera object (FOV, frustum gizmo, Look Through guard/snap/free-fly-mirrors-to-gizmo/restore, capture-from-gizmo), FIGURES auto-track/untrack, FPS box round-trip, auto-capture-on-navigate, onion skin toggle, frameCount round-trip regression, save/load slot round-trip regression (71 cases) |
| `test_tag_scene.lua` | Tag-based scene organisation: getWorkspaceFolders, tagFolder rigs-only, getSceneTagged, scanByTag via doSimpleScan, clearSceneTags, empty-scene FIGURES fallback, AddTag idempotency; New-button name increment, getTagCounts, confirm overlay flow (20 cases) |
| `test_player_rig_proxy.lua` | PlayerRigProxy: fixed pass-through, R6/R15 detection, clone/direct/teardown round-trips, R15 accepted, resolveAll mix, anchor CFs (48 cases) |
| `test_ui_playback.lua` | Playback tab bridge integration: mode switch, scene list, rig modes (all 5), FPS/Loop/MovieMode clamping + round-trip, snippet generation (scene name, CutscenePlayer, mode strings, params), multi-rig snippet, partial param update, frameCount round-trip regression (52 cases) |
| `test_easing_core.lua` | Recorder easing CRUD (rig/prop/camera), shiftFrames/deleteRigKeyframe/deletePropKeyframe include easingTrack, easedAlpha boundary values (Linear/EaseIn/EaseOut/EaseInOut/Constant/Bounce), toSortedKFs backward compat (20 cases, headless) |
| `test_ui_easing.lua` | Live bridge: rig easing all-6-styles round-trip, camera easing CRUD, simple mode easing state, capture stamps easing, frame navigation syncs display (12 cases) |

Suite total: **~561 cases** across 25 files (2 skipped headless: `test_player` → `mcp playtest`, `test_scrubber` → interactive).

All tests inline their module logic (no `require()` to plugin modules) and return a PASS/FAIL string for `execute_luau`. Run with:

```lua
-- Paste file contents into execute_luau, or use the MCP tool directly.
-- Each file returns a multiline string — check for "ALL TESTS PASSED".
```

**MCP access:** The `Roblox_Studio` MCP server is registered via `claude mcp add`. Use the `mcp__Roblox_Studio__execute_luau` tool directly in Claude Code sessions. The `mcp.py` alias is a secondary fallback for terminal use.

Prefer `execute_luau` + `return` (not `print()`) for unit-style checks.

---

## Current Status

See `PHASES.md` for the task checklist. Work phase by phase; do not start Phase N+1
until Phase N acceptance criteria pass.
