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
}
```

**CFrame values** stored in `jointTrack` are `Motor6D.Transform` — the joint's
current deviation from its rest position. This maps directly to `Pose.Transform`
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
  }
}
```

CFrame array layout: `[r00,r01,r02, r10,r11,r12, r20,r21,r22, x,y,z]`  
Vector3 array layout: `[x, y, z]`

Deserialisation reconstructs via `CFrame.new(x,y,z, r00,r01,r02,r10,r11,r12,r20,r21,r22)`
and `Vector3.new(x, y, z)`.

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

Each `Pose.Transform` = the captured `Motor6D.Transform` CFrame for that joint.
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

## ServerStorage Layout

```
ServerStorage
└── MultiAnimationData
    ├── Scene_001
    │   ├── Rig1_Joints   (KeyframeSequence)
    │   ├── Rig2_Joints   (KeyframeSequence)
    │   └── ScaleTracks   (ModuleScript)
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

-- Play a named scene on a set of rigs
-- rigMap keys must match the rig names used when the scene was exported
player.play("Scene_001", {
    Rig1 = workspace.FIGURES.Rig1,
    Rig2 = workspace.FIGURES.Rig2,
})

-- Stop all active playback immediately
player.stop()

-- Register a callback fired when the scene finishes (or is stopped)
player.onFinished(function(sceneName)
    print(sceneName .. " finished")
end)
```

---

## Interpolation Rules

### Joints (in-game, via Animator)

Handled automatically by Roblox's animation system using the `EasingStyle` set on
each `Pose`. v1 uses `Linear` throughout.

### Scale (in-game, via TweenService)

Between any two adjacent keyframes A (time `tA`) and B (time `tB`):

```
alpha(t) = (t - tA) / (tB - tA)   where t is current playback time in seconds
size(t)  = sizeA:Lerp(sizeB, alpha)
```

A new `Tween` with `TweenInfo.new(tB - tA, Enum.EasingStyle.Linear)` is created
at keyframe A and targets keyframe B's sizes. When it completes the next tween
for B→C is created, and so on.

### Scale (in-editor preview, via PoseApplier)

Applied discretely per frame step — no interpolation during scrub in v1.
Smooth scrub interpolation is a v2 enhancement.

---

## Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| Scene folder | `Scene_NNN` (auto-increment) | `Scene_001` |
| Joint KFS | `<RigName>_Joints` | `Rig1_Joints` |
| Scale module | `ScaleTracks` (shared, one per scene) | `ScaleTracks` |
| Motor6D keys | Exact Roblox name | `"Right Shoulder"` |
| Part scale keys | Exact Roblox name | `"Left Arm"` |
| Frame numbers | 1-based integers | `1`, `12`, `24` |
| Time (KFS) | Seconds, 4 decimal places | `0.4583` |
