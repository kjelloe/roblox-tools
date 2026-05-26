# Roblox Studio — Claude Code Project

This directory is the workspace for Roblox game development assisted by Claude Code.
Claude connects to a live Roblox Studio session through the `roblox-studio` MCP server.

## MCP Setup

The MCP server is pre-configured in `~/.claude/.mcp.json`:

```json
{
  "mcpServers": {
    "roblox-studio": {
      "command": "cmd.exe",
      "args": ["/c", "C:\\Users\\kjell\\AppData\\Local\\Roblox\\mcp.bat"]
    }
  }
}
```

**Roblox Studio must be open** for any MCP tool to work. The proxy (`StudioMCP.exe`) connects automatically — no manual server start required. Claude Code loads the server at startup.

## Quick Reference — MCP Tools

| Tool | What it does |
|------|-------------|
| `search_game_tree` | Browse the Data Model hierarchy |
| `inspect_instance` | Read properties/attributes of an instance |
| `script_read` | Read a script's source |
| `script_grep` | Search scripts by regex pattern |
| `script_search` | Semantic search across scripts |
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

## Development Notes

- Scripts written here can be pasted into Studio, or use `multi_edit` / `execute_luau` to push changes directly.
- Use `get_console_output` after `execute_luau` to check for errors.
- Generation tools (`generate_*`) are async — always follow with `wait_job_finished`.
- Multiple Studio instances: call `list_roblox_studios` then `set_active_studio` to pick the right one.
