# Roblox Studio — Claude Code Project

This directory is the workspace for Roblox game development assisted by Claude Code.
Claude connects to a live Roblox Studio session through the `Roblox_Studio` MCP server.

## MCP Setup

The `Roblox_Studio` server is stored **project-scoped** in `~/.claude.json` (added by Studio's `claude mcp add` prompt):

```
Command: cmd.exe /c %LOCALAPPDATA%\Roblox\mcp.bat
```

`%LOCALAPPDATA%` expands correctly in `cmd.exe` — this survives Roblox version updates without requiring any manual changes. `~/.claude/.mcp.json` is intentionally empty (a previous `roblox-studio` entry there caused two competing `StudioMCP.exe` processes that prevented Studio from connecting).

**Session start ritual — do this every session before using Studio tools:**
1. Open Roblox Studio and load the place (MCP plugin must be active in Studio's Plugins tab)
2. `list_roblox_studios` → `set_active_studio` with the returned ID
3. Quick verify: `execute_luau("return workspace.Name")` → should return `"Workspace"`

The studio ID changes every Studio restart, so steps 2–3 are required each session.

**About `mcp.bat`:** Roblox auto-generates `%LOCALAPPDATA%\Roblox\mcp.bat`. It checks a versioned path first, then falls back to a registry query for `StudioMCP.exe`. Both are handled automatically — never run it manually. Claude Code starts it as a subprocess when the MCP server is activated.

## Quick Reference — MCP Tools

| Tool | What it does |
|------|-------------|
| `search_game_tree` | Browse the Data Model hierarchy |
| `inspect_instance` | Read properties/attributes of an instance |
| `script_read` | Read a script's source |
| `script_grep` | Search scripts by regex pattern |
| `script_search` | Fuzzy match on script names (not contents) |
| `multi_edit` | Batch-edit instance properties |
| `execute_luau` | Run Lua code in Studio |
| `get_console_output` | Read the Studio output window |
| `start_stop_play` | Enter or exit play mode |
| `character_navigation` | Move character (play mode only) |
| `user_keyboard_input` | Send keyboard events |
| `user_mouse_input` | Send mouse events |
| `screen_capture` | Screenshot the Studio viewport |
| `generate_procedural_model` | AI-generate a model from a description |
| `generate_mesh` | AI-generate a mesh |
| `generate_material` | AI-generate a material |
| `search_creator_store` | Search the Roblox Creator Store |
| `insert_from_creator_store` | Insert an asset from the Store |
| `store_image` | Load a local image for use in generation tools |
| `http_get` | Fetch Roblox Engine API docs |
| `list_roblox_studios` | List open Studio instances |
| `set_active_studio` | Switch the active Studio instance |
| `wait_job_finished` | Await an async generation job |

Full usage patterns: see `ROBLOX_MCP_TOOLS.md`.

## Skill

Type `/roblox-studio` in the Claude Code prompt to activate the Roblox Studio skill,
which provides guided workflow patterns for common tasks.

## Instance Path Convention

All instance paths start with `game`, `Workspace`, or `LocalPlayer`:

```
game.Workspace.MyModel.Part
game.ServerScriptService.Handler
Workspace.Folder.Script
```

## Roblox Creator Docs

Navigation guide: `~/GIT/Roblox/roblox-docs/roblox_creator_docs_navigation_guide.md`
Primary source: https://github.com/Roblox/creator-docs

**Always prefer creator-docs over model training knowledge** — APIs, properties, events, enums, and security capabilities change. Model knowledge may be outdated.

Key sections in creator-docs:
| Question type | Path |
|---|---|
| Class / Method / Event / Property | `content/en-us/reference/engine` |
| Luau syntax / coroutines / types | `content/en-us/scripting` |
| Plugin APIs (PluginToolbar, DockWidget, etc.) | `content/en-us/studio/plugins` |
| UI (ScreenGui, Frames, constraints) | `content/en-us/ui` |
| Animation / Physics / Characters | `content/en-us/animation`, `/physics`, `/characters` |

Fetch docs with the `http_get` MCP tool:
```
http_get(url: "https://create.roblox.com/docs/reference/engine/classes/Player.md")
```
Always check: security level, deprecated tags, thread safety, and NotReplicated before using any API.

## Development Notes

- Scripts written here can be pasted into Studio, or use `multi_edit` / `execute_luau` to push changes directly.
- Use `get_console_output` after `execute_luau` to check for errors.
- Generation tools (`generate_*`) are async — always follow with `wait_job_finished`.
- Multiple Studio instances: call `list_roblox_studios` then `set_active_studio` to pick the right one.
- `execute_luau` requires `datamodel_type` ("Edit"/"Client"/"Server").
- **Cloning Player.Character:** requires `character.Archivable = true` first — the default is `false` and `Clone()` silently returns nil otherwise. Always reset to `false` after cloning.

## Dev Tooling

`mcp.py` at the repo root (aliased `mcp`) wraps every workflow: `luau`, `console`/`tail`,
`tree`/`inspect`/`read`/`grep`/`search`/`state`, `check` (compile-check), `drift`,
`test`, `deploy`, `playtest`, `gen`, `store`, `addrig`, `scene` (pull/push), `daemon`.
The daemon auto-starts and makes calls ~100x faster.

MultiAnimation-specific scripts in `MultiAnimation/`: `build.py`, `watch.py`,
`devsync.py` (hot-reload without Studio restart), `run_tests.py`, `hotpatch.py`.

Human guides: `README.md` (tooling), `MultiAnimation/USER_GUIDE.md` (plugin usage
+ all shortcuts). Full tool docs: `MultiAnimation/DEV_TOOLS.md`.
