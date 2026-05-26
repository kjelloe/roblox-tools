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
├── default.project.json    ← Rojo project file (created in Phase 1)
│
├── plugin/                 ← Plugin source (Rojo syncs this to Studio)
│   ├── init.server.lua     ← entry point
│   ├── ui/
│   │   ├── Panel.lua
│   │   ├── RigSelector.lua
│   │   ├── TrackLane.lua
│   │   ├── KeyframeMarker.lua
│   │   └── Controls.lua
│   └── core/
│       ├── RigScanner.lua
│       ├── Recorder.lua
│       ├── JointCapture.lua
│       ├── ScaleCapture.lua
│       ├── Timeline.lua
│       ├── PoseApplier.lua
│       └── Exporter.lua
│
└── game/
    └── MultiAnimPlayer.lua ← in-game playback ModuleScript (no plugin dep)
```

---

## Roblox Context

- **Place file:** `../MultiAnimation.rbxl` (same directory as this folder, one level up)
- **Target rigs:** `Workspace.FIGURES.Rig1` and `Workspace.FIGURES.Rig2` — both R6
- **R6 joints:** `RootJoint`, `Neck`, `Right Shoulder`, `Left Shoulder`, `Right Hip`, `Left Hip`
- **R6 parts:** `Head`, `Torso`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg`, `HumanoidRootPart`
- **Plugin output path:** `%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxm`

R6 detection: `Humanoid` present AND part named `Torso` present (not `UpperTorso`).

---

## MCP Access

Roblox Studio is reachable via the `roblox-studio` MCP server. Use Bash piped to
`cmd.exe /c "C:\Users\kjell\AppData\Local\Roblox\mcp.bat"` to call tools:

```bash
{ echo '<initialize msg>'; sleep 0.5; echo '<tool call msg>'; sleep 2; } \
  | cmd.exe /c "C:\Users\kjell\AppData\Local\Roblox\mcp.bat" 2>/dev/null | tail -1
```

Useful during development:
- `search_game_tree` — inspect rig structure
- `inspect_instance` — check Motor6D properties
- `execute_luau` — run test snippets in Studio
- `get_console_output` — read Studio output window after execute_luau
- `screen_capture` — see current Studio viewport

Studio must be open with the place loaded for MCP to work.

---

## Tooling

### Rojo

Rojo syncs Lua source files to Studio automatically. Install via:
```
aftman install   (if aftman is set up)
-- or --
rojo serve default.project.json
```

Plugin is installed to `%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxm`.
Studio must be restarted (or Plugin Manager → Manage Plugins → reload) after
initial install; Rojo hot-reload handles subsequent changes.

### Without Rojo

Copy/paste individual Lua files into Studio manually, or use `execute_luau` via
MCP to run test snippets. For early phases this is acceptable.

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

- The plugin runs in **edit mode** only. Never call `game:GetService("Players")` or
  `RunService:IsRunning()` — assume edit context.
- `PoseApplier` must wrap all Motor6D writes in `ChangeHistoryService` waypoints to
  avoid polluting the undo stack. See `ARCHITECTURE.md`.
- `MultiAnimPlayer` (`game/`) must have **zero dependency** on plugin APIs. It only
  uses standard Roblox game APIs (`TweenService`, `RunService`, `Animator`).
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

Prefer MCP `execute_luau` + `get_console_output` for unit-style checks on captured data.

---

## Current Status

See `PHASES.md` for the task checklist. Work phase by phase; do not start Phase N+1
until Phase N acceptance criteria pass.
