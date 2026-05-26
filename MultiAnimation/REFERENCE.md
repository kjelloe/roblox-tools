# MultiAnimation — Quick Reference

## R6 Joint Map

| Motor6D | Part0 (parent) | Part1 (child) |
|---------|---------------|---------------|
| RootJoint | HumanoidRootPart | Torso |
| Neck | Torso | Head |
| Right Shoulder | Torso | Right Arm |
| Left Shoulder | Torso | Left Arm |
| Right Hip | Torso | Right Leg |
| Left Hip | Torso | Left Leg |

## R6 Body Parts (scale track)

`Head` · `Torso` · `Left Arm` · `Right Arm` · `Left Leg` · `Right Leg` · `HumanoidRootPart`

## Pose Tree (KeyframeSequence)

```
HumanoidRootPart  (RootJoint.Transform)
└── Torso
    ├── Head
    ├── Left Arm
    ├── Right Arm
    ├── Left Leg
    └── Right Leg
```

## Rigs in Scene

| Name | Path |
|------|------|
| Rig1 | `Workspace.FIGURES.Rig1` |
| Rig2 | `Workspace.FIGURES.Rig2` |

## ServerStorage Layout

```
ServerStorage.MultiAnimationData
└── Scene_001
    ├── Rig1_Joints   KeyframeSequence
    ├── Rig2_Joints   KeyframeSequence
    └── ScaleTracks   ModuleScript
```

## MultiAnimPlayer API

```lua
local p = require(game.ServerStorage.MultiAnimationData.MultiAnimPlayer)
p.play("Scene_001", { Rig1 = workspace.FIGURES.Rig1, Rig2 = workspace.FIGURES.Rig2 })
p.stop()
p.onFinished(function(name) end)
```

## MCP Bash Template

```bash
{
  echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude","version":"0.1"}}}'
  sleep 0.5
  echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"TOOL_NAME","arguments":ARGS_JSON}}'
  sleep 2
} | cmd.exe /c "C:\Users\kjell\AppData\Local\Roblox\mcp.bat" 2>/dev/null | tail -1
```

## Common MCP Calls

**Inspect a Motor6D:**
```bash
# tool: inspect_instance, path: "Workspace.FIGURES.Rig1.Torso.Neck"
```

**Run Lua and read output:**
```bash
# tool: execute_luau, then tool: get_console_output
```

**Check ServerStorage after export:**
```bash
# tool: search_game_tree, path: "ServerStorage.MultiAnimationData"
```

## Rojo Commands

```bash
rojo serve default.project.json    # sync plugin source to Studio
rojo build default.project.json -o MultiAnimation.rbxm   # build plugin file
```

## Plugin File Location

`C:\Users\kjell\AppData\Local\Roblox\Plugins\MultiAnimation.rbxm`

## Phase Status → see PHASES.md
