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

## MCP Helper (`mcp` alias)

`/home/kjelloe/GIT/Roblox/mcp.py` — aliased as `mcp` in `~/.bashrc`.

```bash
mcp luau "return workspace.Name"           # inline Lua
mcp luau - <<'EOF'                         # multi-line stdin
  local t={}
  for _,c in ipairs(workspace:GetChildren()) do
    table.insert(t,c.Name)
  end
  return table.concat(t,'|')
EOF
mcp luau -f tests/test_scrubber.lua        # run a file
mcp console MultiAnimation                 # filtered console output
mcp tree workspace.FIGURES                 # search_game_tree
mcp inspect workspace.FIGURES.Rig1        # inspect_instance
mcp capture                                # screen_capture
mcp studios                                # list open Studio instances
```

## Common MCP Calls

**Inspect a Motor6D:**
```bash
mcp inspect workspace.FIGURES.Rig1.Torso.Neck
```

**Run Lua and read output:**
```bash
mcp luau "return workspace.FIGURES.Rig1.Torso.Neck.Transform"
mcp console MultiAnimation
```

**Check ServerStorage after export:**
```bash
mcp tree ServerStorage.MultiAnimationData
```

## Rojo Commands

```bash
rojo serve default.project.json    # sync plugin source to Studio
rojo build default.project.json -o MultiAnimation.rbxm   # build plugin file
```

## Plugin File Location

`C:\Users\kjell\AppData\Local\Roblox\Plugins\MultiAnimation.rbxm`

## Phase Status

| Phase | Status |
|-------|--------|
| 1 Scaffold | ✅ |
| 2 Capture | ✅ |
| 3 Preview | ✅ |
| 4 Export | ✅ |
| 5 In-game Playback | ✅ |
| 6 Polish | 🔄 In Progress |

See `PHASES.md` for full task lists.

## UX Interactions

| Interaction | Action |
|---|---|
| Click rig button in panel | Exclusive select — deactivates all others |
| Click rig part in viewport | Exclusive select that rig in panel |
| Double-click track lane | Jump to that frame + add keyframe for that rig |
| Left-click keyframe dot | Jump timeline to that frame |
| Right-click keyframe dot | Delete that rig's keyframe at that frame |
| Drag scrubber | Scrub timeline (overlay pattern — see ARCHITECTURE.md) |
