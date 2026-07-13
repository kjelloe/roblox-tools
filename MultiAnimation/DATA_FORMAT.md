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
                -- one entry per BasePart that is a direct child of the rig
                -- Model (all 7 R6 parts, all 16 R15 parts, or whatever a
                -- custom rig has — captured dynamically, no hardcoded list)
                [1] = {
                    Head            = Vector3,
                    Torso           = Vector3,
                    ["Left Arm"]    = Vector3,
                    -- … remaining direct-child parts …
                    HumanoidRootPart = Vector3,
                },
                [12] = { ... },
            },
            easingTrack = {     -- per-keyframe easing (controls segment F → next KF)
                -- absent entries default to "Linear"
                [1]  = "EaseIn",
                [12] = "Bounce",
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
            easingTrack = {     -- per-keyframe easing for this prop
                [1] = "EaseOut",
            },
        },
    },
    camera = {                  -- Phase 8 — one camera track per session
        track = {
            -- key = frame number
            [1]  = { cf = CFrame, fov = 70, mode = "move", easing = "Linear"  },
            [40] = { cf = CFrame, fov = 35, mode = "cut",  easing = "EaseInOut" },
        },
    },
    effects = {                 -- named effect instances with one-shot events
        ["Sparkles"] = {
            kind   = "ParticleEmitter",  -- classified instance type
            action = "emit",             -- default action for new events
            path   = "Workspace.FIGURES.Rig1.Head.Sparkles",
            track  = {
                -- key = frame number
                [10] = { action = "emit", count = 20 },
            },
        },
    },
    spawnedEffects = {          -- array (not frame-keyed); ids are stable
        { id = 1, frame = 12, effectType = "Explosion",  -- or "Smoke"
          posX = 0, posY = 5, posZ = 0,
          size = 3, colorR = 255, colorG = 80, colorB = 0,
          count = 50, duration = 0.6, speed = 20, lifetime = 1.0 },
        { id = 2, frame = 30, effectType = "Sound",
          posX = 0, posY = 5, posZ = 0,
          soundId = "rbxassetid://…", volume = 1, maxDistance = 80 },
    },
    subtitlesEnabled = false,   -- master toggle for the subtitle track
    subtitleStyle    = { … },   -- font/colour/stroke/background/offset fields
    subtitles = {               -- sorted array of stepped text events;
        { frame = 1,  text = "Hello" },   -- text shows from its frame until
        { frame = 40, text = "" },        -- the next event ("" clears)
    },
}
```

`spawnedEffects` and `subtitles` store their frame *inside* each entry rather
than as a table key — frame-shift operations (`Recorder:shiftFrames`,
`deleteFrameAt`) must rewrite `entry.frame` for these two tracks in addition
to re-keying the frame-keyed tracks.

`camera.track` keyframes: `cf` is the world-space viewport-camera CFrame, `fov`
the FieldOfView, `mode` either `"move"` (interpolate from the previous keyframe)
or `"cut"` (the previous shot holds until this frame, then jumps), `easing` is the
interpolation curve for the segment starting at this frame (see Easing Styles below).

**Easing styles:** `"Linear"` (default) · `"EaseIn"` (cubic in) · `"EaseOut"` (cubic out) ·
`"EaseInOut"` (cubic symmetric) · `"Constant"` (hold — α always 0) · `"Bounce"`.
Easing at frame F applies to the segment from F toward the *next* keyframe. Absent entries
or frames with no stored easing default to `"Linear"`.

`easingTrack` is absent in sessions saved before the easing feature; all frames default to Linear.
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
      "joints": { "1": { "RootJoint": [1,0,0, 0,1,0, 0,0,1, 0,0,0], "Neck": [...] } },
      "scales": { "1": { "Head": [2,2,2], "Torso": [2,2,1] } },
      "roots":  { "1": [1,0,0, 0,1,0, 0,0,1, 0,0,0] },
      "easings": { "1": "EaseIn", "12": "Bounce" }
    }
  },
  "props": {
    "Block": {
      "frames":  { "1":  [1,0,0, 0,1,0, 0,0,1,  2, 5, 0] },
      "easings": { "1": "EaseOut" }
    }
  },
  "camera": {
    "1":  { "cf": [...], "fov": 70, "mode": "move", "easing": "Linear"   },
    "40": { "cf": [...], "fov": 35, "mode": "cut",  "easing": "EaseInOut" }
  },
  "effects": {
    "Sparkles": { "kind": "ParticleEmitter", "action": "emit",
                  "path": "Workspace.FIGURES.Rig1.Head.Sparkles",
                  "track": { "10": { "action": "emit", "count": 20 } } }
  },
  "spawnedEffects": [
    { "id": 1, "frame": 12, "effectType": "Explosion", "posX": 0, "posY": 5, "posZ": 0,
      "size": 3, "colorR": 255, "colorG": 80, "colorB": 0,
      "count": 50, "duration": 0.6, "speed": 20, "lifetime": 1.0 }
  ],
  "subtitlesEnabled": true,
  "subtitleStyle": { "size": 28, "yOffset": 0.85 },
  "subtitles": [ { "frame": 1, "text": "Hello" } ]
}
```

`easings` objects are omitted when all frames are Linear. Old saves without `easings`
are backward-compatible — all frames default to Linear on load.

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

Standard Roblox `KeyframeSequence` instance written into `ServerStorage`. Uses a flat
format where each motor's transform is a `Pose` named by motor name, directly under
`HumanoidRootPart`. Works for R6, R15, and custom rigs.

```
KeyframeSequence  (Name = "Rig1_Joints", Loop = false, AuthoredHipHeight = 0)
├── Keyframe      (Time = 0.000)                   ← frame 1 / fps
│   └── Pose      (Name = "HumanoidRootPart", Weight = 1, CFrame = identity)
│       ├── Pose  (Name = "RootJoint",    Weight = 1, CFrame = <transform>)
│       ├── Pose  (Name = "Neck",         Weight = 1, CFrame = <transform>)
│       ├── Pose  (Name = "Right Shoulder", ...)
│       └── ...   (one Pose per Motor6D, sorted alphabetically)
│
└── Keyframe      (Time = 0.458)
    └── ...
```

Backward compat: the old R6 hierarchy format (Torso → limbs) is still parsed by
`MultiAnimPlayer.parseKFS` for scenes exported before this format change.

Each `Pose.CFrame` = the captured `Motor6D.Transform` CFrame for that joint.
(`Pose.Transform` was renamed to `Pose.CFrame` in a Roblox Studio update.)
`Pose.EasingStyle` and `Pose.EasingDirection` are set from the per-keyframe easing:

| Plugin easing string | Pose.EasingStyle | Pose.EasingDirection |
|---|---|---|
| `"Linear"` | `PoseEasingStyle.Linear` | `PoseEasingDirection.Out` |
| `"EaseIn"` | `PoseEasingStyle.Cubic` | `PoseEasingDirection.In` |
| `"EaseOut"` | `PoseEasingStyle.Cubic` | `PoseEasingDirection.Out` |
| `"EaseInOut"` | `PoseEasingStyle.Cubic` | `PoseEasingDirection.InOut` |
| `"Constant"` | `PoseEasingStyle.Constant` | `PoseEasingDirection.Out` |
| `"Bounce"` | `PoseEasingStyle.Bounce` | `PoseEasingDirection.Out` |

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
        },
    },
    -- easings omitted entirely when all frames are Linear (backward compat)
    easings = {
        Rig1 = {
            [1] = "EaseIn",     -- only non-Linear frames appear
        },
    },
}
```

`MultiAnimPlayer` reconstructs `Vector3` values from the `{x,y,z}` arrays at runtime.
`easings[rigName][frame]` is the easing for the segment from that frame to the next.
Old ScaleTracks without an `easings` table treat all frames as Linear.

---

## Exported: PropTracks ModuleScript (Phase 7)

Written alongside `ScaleTracks` when any props are tracked.

```lua
-- PropTracks (ModuleScript source)
return {
    fps = 24,
    props = {
        Block = {
            -- [frameNumber] = { x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22 }
            [1]  = { 2, 5,  0,  1,0,0, 0,1,0, 0,0,1 },
            [10] = { 5, 7, -3,  1,0,0, 0,1,0, 0,0,1 },
            [50] = {-2, 5,  0,  1,0,0, 0,1,0, 0,0,1 },
        },
    },
    -- easings omitted entirely when all frames are Linear (backward compat)
    easings = {
        Block = {
            [1] = "EaseOut",
        },
    },
}
```

`MultiAnimPlayer` reconstructs `CFrame` values from the 12-number arrays at runtime using
`CFrame.new(arr[1]…arr[12])` (position first — matches `CFrame:GetComponents()` order).
`easings[propName][frame]` is the easing for that segment. Old PropTracks without `easings`
treat all frames as Linear.

---

## Exported: CameraTrack ModuleScript (Phase 8)

Written when any camera keyframes were recorded; omitted otherwise.

```lua
-- CameraTrack (ModuleScript source)
return {
    fps = 24,
    frames = {
        -- [frameNumber] = { cf={x,y,z, r00..r22}, fov, cut, easing }
        [1]  = {cf = {3,12,-7, 1,0,0, 0,1,0, 0,0,1}, fov = 70, cut = false, easing = "Linear" },
        [40] = {cf = {0,8,20,  1,0,0, 0,1,0, 0,0,1}, fov = 35, cut = true,  easing = "EaseInOut"},
    },
}
```

`cut = true` means the previous shot holds until this frame, then jumps
(no interpolation toward a cut keyframe). `easing` controls the camera
path for move keyframes; absent in old exports (defaults to `"Linear"`).
Keyframe time = `(frame - 1) / fps`.

---

## ServerStorage Layout

```
ServerStorage
└── MultiAnimationData
    ├── Scene_001
    │   ├── Rig1_Joints   (KeyframeSequence)
    │   ├── Rig2_Joints   (KeyframeSequence)
    │   ├── ScaleTracks   (ModuleScript)
    │   ├── RootTracks    (ModuleScript — absent if no whole-model movement)
    │   ├── PropTracks    (ModuleScript — absent if no props in scene)
    │   ├── CameraTrack   (ModuleScript — absent if no camera keyframes)
    │   ├── EffectTracks  (ModuleScript — absent if no effect events)
    │   ├── SpawnedEffects (ModuleScript — absent if no spawned effects)
    │   └── SubtitleTrack (ModuleScript — absent unless subtitles enabled + events exist)
    ├── Scene_002
    │   └── ...
    ├── MultiAnimPlayer   (ModuleScript — game playback API)
    ├── CutsceneServer    (ModuleScript — synchronized cutscene start, server)
    └── CutsceneCamera    (ModuleScript — client camera driver; a copy is
                           published to ReplicatedStorage on first play)
```

`MultiAnimPlayer` is placed here so any `Script` or `LocalScript` in the game
can `require` it without a plugin dependency.

## Client Scene Payload (`MultiAnimGetScene`)

`MultiAnimDataServer.getSceneData()` converts the ServerStorage scene into a plain
table that survives the RemoteFunction boundary, consumed by `CutscenePlayer`:

```lua
{
    fps  = 24,
    rigs = {
        [rigName] = {
            jointKFs = { {time, poses = {[motorName]=CFrame}, easing = "EaseOut"}, ... },
            scaleKFs = { {time, data = {[partName]=Vector3}, easing}, ... },
            rootKFs  = { {time, data = CFrame, easing}, ... },
        },
    },
    props  = { [propName] = { {time, data = CFrame, easing}, ... } },
    camera = { {time, data = {cf = CFrame, fov, cut, easing}}, ... },
    effects = {
        [effectName] = {
            target = "game.Workspace.FX.Emitter",   -- full path, resolved client-side
            kfs    = { {time, data = {action = "emit", count = 15}}, ... },
        },
    },
    spawnedEffects = { {id, frame, effectType, posX, posY, posZ, ...}, ... },
    subtitles      = { {frame, text}, ... },        -- only when SubtitleTrack exists
    subtitleStyle  = { fontAsset, size, ... },      -- only when SubtitleTrack exists
}
```

Every keyframe entry carries the `easing` string governing the segment toward the
next entry (joint easing recovered from Pose `EasingStyle`/`EasingDirection`; the
others from the exported `easings` tables). Entries lacking `easing` (pre-easing
exports) are treated as `"Linear"` by the client.

## Cutscene API (Phase 8)

```lua
-- Server Script:
local Cutscene = require(game.ServerStorage.MultiAnimationData.CutsceneServer)
Cutscene.play("Scene_001", { Rig1 = workspace.FIGURES.Rig1 }, propMap)  -- broadcasts start
Cutscene.stop()
Cutscene.onFinished(function(sceneName) end)

-- LocalScript (e.g. StarterPlayerScripts):
require(game.ReplicatedStorage:WaitForChild("CutsceneCamera")).start()
```

`CutsceneServer.play` fires a RemoteEvent with the scene name, a shared
`workspace:GetServerTimeNow()` start timestamp (+0.35 s lead), the CameraTrack
data, and the SubtitleTrack data `{fps, style, events}` (clients cannot read
ServerStorage). Each client sets its camera to `Scriptable` and drives CFrame +
FOV per RenderStepped against the shared clock; subtitles are displayed stepped
on the same clock via the `SubtitleGui` module in ReplicatedStorage. The player
camera is restored when the track ends or on stop; subtitles hide on the
server's `"__stop"` signal, fired both by `Cutscene.stop()` and on natural
completion. Register completion callbacks via `Cutscene.onFinished` — it wraps
`MultiAnimPlayer.onFinished` internally, so do not set the player-level
callback directly when using CutsceneServer.

Known caveats: rig motion replicates ~50–100 ms behind the locally-driven
camera. Effect tracks and spawned effects fire server-side via MultiAnimPlayer
in this path — fine in Studio play-solo, but method calls like
`ParticleEmitter:Emit()` do not replicate, so particle bursts may not be
visible to clients in a live multiplayer server (sounds and property toggles
replicate normally). For client-visible effects use the `CutscenePlayer` path.

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

### Easing

All track types support per-keyframe easing. Between keyframes A and B, the raw
linear `alpha` is transformed by the easing stored at keyframe A:

```
alpha(t)       = (t - tA) / (tB - tA)
easedAlpha(t)  = applyEasing(alpha, A.easing)
```

| Easing string | Curve |
|---|---|
| `"Linear"` | `t` |
| `"EaseIn"` | `t³` |
| `"EaseOut"` | `1 − (1−t)³` |
| `"EaseInOut"` | cubic symmetric (fast start/end, slower middle) |
| `"Constant"` | always `0` — holds A's value until the next keyframe |
| `"Bounce"` | overshoot bounce near the target |

Plugin: uses `TweenService:GetValue`. Game modules: pure-math (no TweenService).

### Joints (in-game, via Motor6D.Transform)

`MultiAnimPlayer` drives `Motor6D.Transform` directly in a `RunService.Heartbeat`
loop — the same mechanism `Animator` uses internally. `AnimationClipProvider:RegisterKeyframeSequence` was removed from Roblox's server-side API and is no longer used.

Between any two adjacent keyframes A (time `tA`) and B (time `tB`):

```
t             = easedAlpha((elapsed - tA) / (tB - tA), A.easing)
motor.Transform = cfA:Lerp(cfB, t)
```

### Scale (in-game, via Heartbeat loop)

```
t        = easedAlpha((elapsed - tA) / (tB - tA), A.easing)
part.Size = sizeA:Lerp(sizeB, t)
```

### Props (in-game, via Heartbeat loop)

```
t           = easedAlpha((elapsed - tA) / (tB - tA), A.easing)
part.CFrame = cfA:Lerp(cfB, t)
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
