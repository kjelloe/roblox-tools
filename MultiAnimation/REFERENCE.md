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
├── MultiAnimPlayer   ModuleScript (deployed by Exporter)
└── Scene_001
    ├── Rig1_Joints   KeyframeSequence
    ├── Rig2_Joints   KeyframeSequence
    ├── ScaleTracks   ModuleScript
    ├── RootTracks    ModuleScript  (absent if no whole-model movement)
    └── PropTracks    ModuleScript  (absent if no props tracked)
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
mcp console MultiAnimation                 # filtered console output (one-shot)
mcp tail MultiAnimation                    # live-tail console; Ctrl+C to stop
mcp tree workspace.FIGURES                 # search_game_tree
mcp inspect workspace.FIGURES.Rig1        # inspect_instance
mcp read ServerStorage.MultiAnimationData.MultiAnimPlayer   # deployed source
mcp grep "RegisterKeyframeSequence"        # regex search across all scripts
mcp search "play animation"                # semantic search across scripts
mcp state                                  # edit/play mode, place info
mcp capture                                # screen_capture
mcp studios                                # list open Studio instances
mcp check plugin/core/Exporter.lua         # compile-check (loadstring, no run)
mcp drift                                  # local vs deployed diff
mcp test [pattern] [-v]                    # run test suite
mcp deploy                                 # push MultiAnimPlayer → ServerStorage
mcp playtest [--timeout N] [--no-deploy]   # deploy → F5 → watch console → verdict
mcp gen model "desc" [--wait]              # AI-generate model (auto-inserts)
mcp gen mesh "desc" [--size x,y,z] [--tris N]   # AI-generate textured mesh
mcp gen material "desc" [--base Rock]      # AI-generate material variant
mcp store "query" [--insert] [--name X]    # Creator Store search / insert
mcp addrig [name]                          # clone Rig1 → next free RigN
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

## Build Commands

```bash
cd MultiAnimation
python3 build.py           # build and install to Plugins folder
python3 build.py --dry-run # print assembled XML to stdout
python3 watch.py           # auto-rebuild on any .lua save (Ctrl+C to stop)
```

## Plugin File Location

`C:\Users\kjell\AppData\Local\Roblox\Plugins\MultiAnimation.rbxmx`

## Phase Status

| Phase | Status |
|-------|--------|
| 1 Scaffold | ✅ |
| 2 Capture | ✅ |
| 3 Preview | ✅ |
| 4 Export | ✅ |
| 5 In-game Playback | ✅ |
| 6 Polish | ✅ |
| 7 Prop Animation | ✅ |
| 8 Future | ⬜ Backlog |

See `PHASES.md` for full task lists.

## UX Interactions

| Interaction | Action |
|---|---|
| Click rig button in panel | Exclusive select — deactivates all others |
| Click rig part in viewport | Exclusive select that rig in panel |
| Click prop button in panel | Multi-select toggle (independent of rig selection) |
| Click "Track Part" button | Adds currently viewport-selected BasePart as a tracked prop |
| Click × on prop button | Removes prop from panel; data kept in session |
| Double-click rig/prop track lane | Jump to that frame + add keyframe for that object |
| Left-click keyframe dot | Jump timeline to that frame |
| Right-click keyframe dot | Delete that object's keyframe at that frame |
| Drag scrubber | Scrub timeline; auto-updates existing KF at departure frame |

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `K` | Add / update keyframe for all active rigs & props at current frame |
| `L` | Step timeline forward by Step frames (default 2) |
| `J` | Step timeline back by Step frames (default 2) |

All shortcuts are ignored when a TextBox has keyboard focus.  
Shortcut legend is shown at the bottom of the plugin panel.

## Track Lane Colours

| Colour | Type |
|---|---|
| Yellow `Color3.fromRGB(255, 200, 60)` | Rig keyframe |
| Teal `Color3.fromRGB(0, 207, 207)` | Prop keyframe |
