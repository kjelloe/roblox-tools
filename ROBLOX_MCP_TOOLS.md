# Roblox Studio MCP Tools — Reference

Complete reference for the `roblox-studio` MCP server tools available in Claude Code.

## Setup

- **MCP config:** `~/.claude/.mcp.json` → key `roblox-studio`
- **Proxy binary:** `C:\Users\kjell\AppData\Local\Roblox\Versions\version-b2a9c018a1e042c6\StudioMCP.exe`
- **Launch script:** `C:\Users\kjell\AppData\Local\Roblox\mcp.bat` (auto-selects latest version)
- **Protocol:** MCP stdio, version `2024-11-05`

---

## Scene Exploration

### `search_game_tree`
Browse the Roblox Data Model as flat JSON.

| Param | Type | Description |
|-------|------|-------------|
| `path` | string | Start path, e.g. `"Workspace"` |
| `instance_type` | string | Filter by class, e.g. `"Script"`, `"Part"` |
| `max_depth` | number | Depth limit (default 3, max 10) |
| `query` | string | Keyword filter on instance names |

Returns array of `{ name, className, fullPath, parentName, childSummary }`.

### `inspect_instance`
Read all properties and attributes of a specific instance.

| Param | Type | Description |
|-------|------|-------------|
| `path` | string | Full instance path, e.g. `"Workspace.Part"` |

---

## Scripts

### `script_read`
Read the source of a script (returned with line numbers, `LINE→CONTENT`).

| Param | Type | Description |
|-------|------|-------------|
| `target_file` | string | Dot-notation path, e.g. `"game.ServerScriptService.MyScript"` |
| `should_read_entire_file` | boolean | Default true |
| `start_line_one_indexed` / `end_line_one_indexed_inclusive` | integer | Range when not reading whole file |

### `script_grep`
Search across all script contents (string or Luau pattern, capped at 50 matches).

| Param | Type | Description |
|-------|------|-------------|
| `query` | string | String or Luau pattern to match |

### `script_search`
Fuzzy match on script **names** (not contents, not semantic). Capped at 10 results.

| Param | Type | Description |
|-------|------|-------------|
| `keywords` | string | Comma-separated keywords, case-insensitive |

### `multi_edit`
Batch-set properties across multiple instances.

---

## Lua Execution

### `execute_luau`
Run Lua code in Studio.

| Param | Type | Description |
|-------|------|-------------|
| `code` | string | Lua source to execute |
| `datamodel_type` | string | **Required.** `"Edit"`, `"Client"`, or `"Server"` — check `get_studio_state` for what's available |

### `get_console_output`
Read the Studio Output window (errors, prints, warns).

---

## Play Mode

### `start_stop_play`
Toggle play/edit mode.

| Param | Type | Description |
|-------|------|-------------|
| `is_start` | boolean | `true` = start play, `false` = stop |

### `character_navigation`
Move the local character. **Requires play mode.**

| Param | Type | Description |
|-------|------|-------------|
| `x`, `y`, `z` | number | World coordinates (use if no instance_path) |
| `instance_path` | string | Navigate to this instance's position |
| `speed_multiplier` | number | Speed factor 0.1–10.0 (default 1.0) |

### `user_keyboard_input`
Send keyboard actions to the game.

Actions array supports: `keyPress`, `keyDown`, `keyUp`, `textInput`, `wait`.

```json
{
  "actions": [
    {"action": "keyPress", "key": "Space"},
    {"action": "textInput", "text_inputs": "hello"},
    {"action": "wait", "wait_time_ms": 500}
  ]
}
```

### `user_mouse_input`
Send mouse events to the game.

---

## Viewport

### `screen_capture`
Capture a screenshot of the current Studio viewport. Returns an image.

---

## AI Generation

All generation tools are **async** — they return a job ID. Call `wait_job_finished` before using the result.

### `generate_procedural_model`
Generate a model from a text description (and optionally an image).

| Param | Type | Description |
|-------|------|-------------|
| `description` | string | Text description of the model |
| `attachedImageUri` | string | Optional `IMAGEID_<id>` from `store_image` |

### `generate_mesh`
Generate a mesh from a description.

### `generate_material`
Generate a surface material from a description.

### `wait_job_finished`
Wait for an async generation job to complete.

| Param | Type | Description |
|-------|------|-------------|
| `jobId` | string | Job ID returned by a generation tool |

---

## Creator Store

### `search_creator_store`
Search the Roblox Creator Store.

| Param | Type | Description |
|-------|------|-------------|
| `query` | string | Search terms |

Returns results including `searchId` and `objectTypes`.

### `insert_from_creator_store`
Insert an asset into the current scene.

| Param | Type | Description |
|-------|------|-------------|
| `searchId` | string | ID from `search_creator_store` result |
| `objectTypes` | string[] | Optional filter by object type |
| `assetName` | string | Optional display name override |

---

## Images

### `store_image`
Load a local image file and get an `IMAGEID_<id>` URI for use with generation tools.

| Param | Type | Description |
|-------|------|-------------|
| `path` | string | Local file path to the image |

---

## Multi-Studio

### `list_roblox_studios`
List all currently open Roblox Studio instances.

### `set_active_studio`
Switch which Studio instance the MCP tools target.

| Param | Type | Description |
|-------|------|-------------|
| `studioId` | string | ID from `list_roblox_studios` |

---

## API Docs

### `http_get`
Fetch Roblox Engine API documentation. Only `create.roblox.com/docs/reference/engine` URLs are allowed.

| Param | Type | Description |
|-------|------|-------------|
| `url` | string | Full doc URL (must end in `.md` or be `llms.txt`) |
| `query` | string | Optional keyword — returns only matching sections |
| `context_lines` | number | Lines of context around each match (default 3) |
| `return_full` | boolean | Return full doc even when query matches |

**Examples:**
```
http_get(url: "https://create.roblox.com/docs/reference/engine/classes/Part.md")
http_get(url: "https://create.roblox.com/docs/reference/engine/classes/BasePart.md", query: "CFrame")
```

---

## Common Recipes

**Find all Parts in Workspace:**
```
search_game_tree(path: "Workspace", instance_type: "Part")
```

**Read a script and check for errors:**
```
script_read(path: "ServerScriptService.MyScript")
execute_luau(code: "<modified source>")
get_console_output()
```

**Generate and insert a model:**
```
generate_procedural_model(description: "a stone well")
wait_job_finished(jobId: "<returned id>")
```

**Play test and navigate:**
```
start_stop_play(is_start: true)
character_navigation(instance_path: "Workspace.StartPart")
user_keyboard_input(actions: [{"action": "keyPress", "key": "Space"}])
start_stop_play(is_start: false)
```
