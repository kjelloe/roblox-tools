# MultiAnimation — Data Format Specification

## Session Data (in-memory, plugin)

Held in `Recorder.lua` during an active session. Serialised to JSON for
`plugin:SetSetting()` persistence.

```lua
session = {
    fps         = 24,           -- frames per second
    frameCount  = 120,          -- total timeline length in frames
    rigs = {
        ["Rig1"] = {
            jointTrack = {
                -- key = frame number (integer, 1-based)
                [1] = {
                    RootJoint       = CFrame,
                    Neck            = CFrame,
                    ["Right Shoulder"] = CFrame,
                    ["Left Shoulder"]  = CFrame,
                    ["Right Hip"]      = CFrame,
                    ["Left Hip"]       = CFrame,
                },
                [12] = { ... },
                [24] = { ... },
            },
            scaleTrack = {
                [1] = {
                    Head            = Vector3,
                    Torso           = Vector3,
                    ["Left Arm"]    = Vector3,
                    ["Right Arm"]   = Vector3,
                    ["Left Leg"]    = Vector3,
                    ["Right Leg"]   = Vector3,
                    HumanoidRootPart = Vector3,
                },
                [12] = { ... },
            },
        },
        ["Rig2"] = { ... },
    },
    props = {                   -- Phase 7 — prop CFrame tracks
        ["Block"] = {
            propTrack = {
                -- key = frame number; value = CFrame stored as table of 12 numbers
                [1]  = CFrame,   -- world-space CFrame of the BasePart
                [10] = CFrame,
                [50] = CFrame,
            },
        },
    },
}
```

`props` is absent in sessions saved before Phase 7; consumers treat absence as `{}`.

**CFrame values** in `propTrack` are world-space `Part.CFrame` (absolute position + rotation), not relative to any parent or joint.

**CFrame values** stored in `jointTrack` are `Motor6D.Transform` — the joint's
current deviation from its rest position. This maps directly to `Pose.CFrame`
in a `KeyframeSequence` with no additional conversion.

**Vector3 values** stored in `scaleTrack` are absolute `Part.Size`, not deltas.

---

## JSON Serialisation (plugin persistence)

CFrames and Vector3s are not JSON-native. They are serialised as arrays:

```json
{
  "fps": 24,
  "frameCount": 120,
  "rigs": {
    "Rig1": {
      "jointTrack": {
        "1": {
          "RootJoint": [1,0,0, 0,1,0, 0,0,1, 0,0,0],
          "Neck":      [1,0,0, 0,1,0, 0,0,1, 0,1.5,0]
        }
      },
      "scaleTrack": {
        "1": {
          "Head":  [2, 2, 2],
          "Torso": [2, 2, 1]
        }
      }
    }
  },
  "props": {
    "Block": {
      "propTrack": {
        "1":  [1,0,0, 0,1,0, 0,0,1,  2, 5, 0],
        "10": [1,0,0, 0,1,0, 0,0,1,  5, 7, -3],
        "50": [1,0,0, 0,1,0, 0,0,1, -2, 5,  0]
      }
    }
  }
}
```

CFrame array layout: `[x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22]`  
(position first — matches the order `CFrame:GetComponents()` returns)  
Vector3 array layout: `[x, y, z]`

Deserialisation:
- CFrame: `CFrame.new(arr[1],arr[2],arr[3], arr[4]…arr[12])`
- Vector3: `Vector3.new(x, y, z)`
- Prop CFrame: same layout — position first, then rotation matrix rows

`props` key is omitted in sessions from before Phase 7; treat absence as `{}`.

---

## Exported: KeyframeSequence (per rig)

Standard Roblox `KeyframeSequence` instance written into `ServerStorage`.

```
KeyframeSequence  (Name = "Rig1_Joints", Loop = false, AuthoredHipHeight = 0)
├── Keyframe      (Time = 0.000)          ← frame 1 / fps
│   └── Pose      (Name = "HumanoidRootPart", Weight = 1)
│       └── Pose  (Name = "Torso",            Weight = 1)
│           ├── Pose (Name = "Head",           Weight = 1)
│           ├── Pose (Name = "Left Arm",       Weight = 1)
│           ├── Pose (Name = "Right Arm",      Weight = 1)
│           ├── Pose (Name = "Left Leg",       Weight = 1)
│           └── Pose (Name = "Right Leg",      Weight = 1)
│
├── Keyframe      (Time = 0.458)          ← frame 12 / fps
│   └── ...
│
└── Keyframe      (Time = 0.917)          ← frame 24 / fps (last)
    └── ...
```

Each `Pose.CFrame` = the captured `Motor6D.Transform` CFrame for that joint.
(`Pose.Transform` was renamed to `Pose.CFrame` in a Roblox Studio update.)
`Pose.EasingStyle` = `Enum.PoseEasingStyle.Linear` (v1).
`Pose.EasingDirection` = `Enum.PoseEasingDirection.Out`.

The Pose tree mirrors the R6 skeleton hierarchy so Roblox's `Animator` can resolve it.

---

## Exported: ScaleTracks ModuleScript

```lua
-- ScaleTracks (ModuleScript source)
return {
    fps = 24,
    rigs = {
        Rig1 = {
            -- [frameNumber] = { partName = {x, y, z} }
            [1]  = { Head={2,2,2}, Torso={2,2,1}, ["Left Arm"]={1,2,1}, ... },
            [12] = { Head={2,2,2}, Torso={2,2,1}, ... },
            [24] = { Head={2,2,2}, Torso={2,2,1}, ... },
        },
        Rig2 = {
            [1]  = { ... },
        },
    },
}
```

`MultiAnimPlayer` reconstructs `Vector3` values from the `{x,y,z}` arrays at runtime.

---

## Exported: PropTracks ModuleScript (Phase 7)

Written alongside `ScaleTracks` when any props are tracked.

```lua
-- PropTracks (ModuleScript source)
return {
    fps = 24,
    props = {
        Block = {
            -- [frameNumber] = { r00,r01,r02, r10,r11,r12, r20,r21,r22, x,y,z }
            [1]  = { 1,0,0, 0,1,0, 0,0,1,  2, 5,  0 },
            [10] = { 1,0,0, 0,1,0, 0,0,1,  5, 7, -3 },
            [50] = { 1,0,0, 0,1,0, 0,0,1, -2, 5,  0 },
        },
    },
}
```

`MultiAnimPlayer` reconstructs `CFrame` values from the 12-number arrays at runtime using
`CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)`.

---

## ServerStorage Layout

```
ServerStorage
└── MultiAnimationData
    ├── Scene_001
    │   ├── Rig1_Joints   (KeyframeSequence)
    │   ├── Rig2_Joints   (KeyframeSequence)
    │   ├── ScaleTracks   (ModuleScript)
    │   └── PropTracks    (ModuleScript — absent if no props in scene)
    ├── Scene_002
    │   └── ...
    └── MultiAnimPlayer   (ModuleScript — game playback API)
```

`MultiAnimPlayer` is placed here so any `Script` or `LocalScript` in the game
can `require` it without a plugin dependency.

---

## MultiAnimPlayer API

```lua
local player = require(game.ServerStorage.MultiAnimationData.MultiAnimPlayer)

-- Play a named scene on a set of rigs (propMap is optional — Phase 7)
player.play("Scene_001",
    { Rig1 = workspace.FIGURES.Rig1, Rig2 = workspace.FIGURES.Rig2 },
    { Block = workspace.Block }   -- omit to play rigs only (backward compatible)
)

-- Stop all active playback immediately (rigs + props)
player.stop()

-- Register a callback fired when the scene finishes (or is stopped)
player.onFinished(function(sceneName)
    print(sceneName .. " finished")
end)
```

---

## Interpolation Rules

### Joints (in-game, via Motor6D.Transform)

`MultiAnimPlayer` drives `Motor6D.Transform` directly in a `RunService.Heartbeat`
loop — the same mechanism `Animator` uses internally. `AnimationClipProvider:RegisterKeyframeSequence` was removed from Roblox's server-side API and is no longer used.

Between any two adjacent keyframes A (time `tA`) and B (time `tB`):

```
alpha(t) = (t - tA) / (tB - tA)   where t is current playback time in seconds
motor.Transform = cfA:Lerp(cfB, alpha)
```

### Scale (in-game, via Heartbeat loop)

Same Heartbeat loop as joints. Between adjacent keyframes A and B:

```
alpha(t) = (t - tA) / (tB - tA)
size(t)  = sizeA:Lerp(sizeB, alpha)
part.Size = size(t)
```

### Props (in-game, via Heartbeat loop)

Same loop as scale interpolation. For each pair of adjacent prop keyframes A and B:

```
alpha(t) = (t - tA) / (tB - tA)
cf(t)    = cfA:Lerp(cfB, alpha)
part.CFrame = cf(t)
```

`CFrame:Lerp()` spherically interpolates rotation (slerp), giving smooth tumbling/spinning.

### Props (in-editor preview, via PoseApplier)

Discrete assignment per frame step — `part.CFrame = interpolatedCFrame`.
Wrapped in `ChangeHistoryService` waypoints to keep the undo stack clean.

### Scale (in-editor preview, via PoseApplier)

Applied discretely per frame step — no interpolation during scrub in v1.
Smooth scrub interpolation is a v2 enhancement.

---

## On-Disk Scene Format (`mcp scene pull/push`)

`mcp scene pull <name>` serializes a ServerStorage scene to `MultiAnimation/scenes/<name>/`
so animation data is git-diffable instead of trapped in the binary `.rbxl`:

```
scenes/Scene_001/
├── manifest.json        { scene, kfs: [names], modules: [names] }
├── Rig1_Joints.json     KeyframeSequence as JSON (see below)
├── Rig2_Joints.json
├── ScaleTracks.lua      ModuleScript Source, verbatim
└── RootTracks.lua       (PropTracks.lua when props were tracked)
```

KeyframeSequence JSON (keys sorted, floats rounded to 6 decimals for stable diffs):

```json
{
  "name": "Rig1_Joints",
  "loop": false,
  "authoredHipHeight": 0,
  "keyframes": [
    {
      "time": 0.125,
      "poses": [
        { "name": "HumanoidRootPart",
          "cframe": [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22],
          "weight": 1,
          "children": [ { "name": "Torso", "...": "nested same shape" } ] }
      ]
    }
  ]
}
```

`cframe` arrays use `CFrame:GetComponents()` order (position first), matching the
`CFrame.new(...)` constructor. Keyframes are sorted by time and pose children by
name, so a pull → push → pull round-trip is byte-identical.

---

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Scene folder | `Scene_NNN` (auto-increment) | `Scene_001` |
| Joint KFS | `<RigName>_Joints` | `Rig1_Joints` |
| Scale module | `ScaleTracks` (shared, one per scene) | `ScaleTracks` |
| Motor6D keys | Exact Roblox name | `"Right Shoulder"` |
| Part scale keys | Exact Roblox name | `"Left Arm"` |
| Prop name keys | Exact `BasePart.Name` | `"Block"` |
| Prop module | `PropTracks` (shared, one per scene) | `PropTracks` |
| Frame numbers | 1-based integers | `1`, `12`, `24` |
| Time (KFS) | Seconds, 4 decimal places | `0.4583` |
