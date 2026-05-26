# MultiAnimation — Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Roblox Studio (edit mode)                                  │
│                                                             │
│  ┌──────────────┐    Selection / Motor6D    ┌───────────┐  │
│  │  Viewport    │ ◄────────────────────────► │  Plugin   │  │
│  │  (rigs live  │    PoseApplier writes       │  (Lua)    │  │
│  │   here)      │    back to Motor6Ds         │           │  │
│  └──────────────┘                            └─────┬─────┘  │
│                                                    │        │
│                                          Export    │        │
│                                                    ▼        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ServerStorage.MultiAnimationData                   │   │
│  │  └── Scene_001                                      │   │
│  │      ├── Rig1_Joints   (KeyframeSequence)           │   │
│  │      ├── Rig2_Joints   (KeyframeSequence)           │   │
│  │      └── ScaleTracks   (ModuleScript)               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Live Game (play mode / published)                          │
│                                                             │
│  Script                                                     │
│    └── require(MultiAnimPlayer).play("Scene_001", rigMap)   │
│                    │                                        │
│          ┌─────────┴──────────┐                            │
│          ▼                    ▼                            │
│    Animator:Play()      TweenService                        │
│    (joint poses)        (scale changes)                     │
│          │                    │                            │
│    ┌─────┴─────┐        ┌─────┴─────┐                     │
│    │   Rig1    │        │   Rig2    │  ← simultaneous      │
│    └───────────┘        └───────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Map

### Plugin (`plugin/`)

```
init.server.lua
│
│  Creates toolbar button → DockWidgetPluginGui
│  Wires all modules together
│  Owns plugin lifetime
│
├── ui/
│   ├── Panel.lua           Root frame layout and section dividers
│   ├── RigSelector.lua     Row of toggle buttons, one per discovered rig
│   │                       Fires: onRigToggled(rigName, isActive)
│   ├── TrackLane.lua       Horizontal lane showing keyframe dots for one rig
│   │                       Fires: onKeyframeClicked(frame)
│   ├── KeyframeMarker.lua  Single dot on a TrackLane; clickable
│   └── Controls.lua        Add Keyframe / Prev KF / Scrubber / Next KF /
│                           Play / Stop / Export / FPS + FrameCount inputs
│
└── core/
    ├── RigScanner.lua      Scans Workspace.FIGURES for R6 models
    │                       Returns: { [name] = ModelInstance }
    │
    ├── Recorder.lua        State machine (IDLE → RECORDING → IDLE)
    │                       Owns session data table
    │                       Calls JointCapture + ScaleCapture on AddKeyframe
    │
    ├── JointCapture.lua    Reads Motor6D.Transform for all 6 R6 joints
    │                       Returns: { [jointName] = CFrame }
    │
    ├── ScaleCapture.lua    Reads Part.Size for all 7 R6 body parts
    │                       Returns: { [partName] = Vector3 }
    │
    ├── Timeline.lua        Tracks currentFrame, frameCount, fps
    │                       Interpolation helpers (lerp between keyframes)
    │
    ├── PoseApplier.lua     Writes joint CFrames back to Motor6Ds (viewport preview)
    │                       Wrapped in ChangeHistoryService.SetWaypoint so it is
    │                       undoable and does not pollute the undo stack permanently
    │
    └── Exporter.lua        Builds KeyframeSequence instances from session data
                            Builds ScaleTracks ModuleScript
                            Writes to ServerStorage.MultiAnimationData/<scene>/
```

### Game (`game/`)

```
MultiAnimPlayer.lua     ModuleScript — no plugin dependency
                        API:
                          .play(sceneName, rigMap, options?)
                          .stop()
                          .onFinished(callback)
```

---

## State Machine (`Recorder.lua`)

```
          ┌─────────────────────────────────┐
          │             IDLE                │
          └────────────┬────────────────────┘
                       │ startRecording()
                       ▼
          ┌─────────────────────────────────┐
          │           RECORDING             │
          │                                 │
          │  addKeyframe() →                │
          │    JointCapture(activeRigs)      │
          │    ScaleCapture(activeRigs)      │
          │    store in session[frame]       │
          │    redraw TrackLanes            │
          └────────────┬────────────────────┘
                       │ stopRecording()
                       ▼
          ┌─────────────────────────────────┐
          │             IDLE                │
          └─────────────────────────────────┘

  From IDLE or RECORDING:
  previewPlay() → steps frames via RunService.Heartbeat,
                  calls PoseApplier each frame
  previewStop() → disconnects Heartbeat
```

---

## Data Flow: Add Keyframe

```
User presses "Add Keyframe"
        │
        ▼
Controls.lua fires addKeyframe event
        │
        ▼
Recorder.addKeyframe(currentFrame)
        │
        ├── for each activeRig:
        │       JointCapture.capture(rig)  → jointData
        │       ScaleCapture.capture(rig)  → scaleData
        │
        ├── session.rigs[rigName].jointTrack[frame] = jointData
        ├── session.rigs[rigName].scaleTrack[frame] = scaleData
        │
        └── UI event → TrackLane.addMarker(rigName, frame)
```

## Data Flow: Export

```
User presses "Export"
        │
        ▼
Exporter.export(session, sceneName)
        │
        ├── for each rig in session:
        │       build KeyframeSequence
        │           for each frame in jointTrack:
        │               Keyframe at time = frame/fps
        │               Pose tree: HumanoidRootPart → Torso → limbs/head
        │               each Pose.Transform = captured CFrame
        │       insert KeyframeSequence into scene folder
        │
        ├── build ScaleTracks table
        │       { Rig1 = { [frame] = { Head=V3, Torso=V3, ... } }, Rig2 = {...} }
        │       serialise to ModuleScript source string
        │       insert ModuleScript into scene folder
        │
        └── create/overwrite ServerStorage.MultiAnimationData[sceneName]
```

## Data Flow: In-game Playback

```
require(MultiAnimPlayer).play("Scene_001", {
    Rig1 = workspace.FIGURES.Rig1,
    Rig2 = workspace.FIGURES.Rig2,
})
        │
        ▼
Load from ServerStorage.MultiAnimationData.Scene_001
        │
        ├── for each rig:
        │       anim = Animator:LoadAnimation(Rig_Joints KeyframeSequence)
        │       store anim + scale track
        │
        ├── sync point — wait one frame
        │
        ├── for each rig simultaneously:
        │       anim:Play()
        │
        └── scale tween loop:
                RunService.Heartbeat
                for each rig, each part:
                    find surrounding keyframes for current time
                    TweenService:Create(part, tweenInfo, {Size = lerped Vector3}):Play()
```

---

## Key Technical Decisions

### Motor6D Transform vs. C0/C1

Roblox animations store `Pose.Transform` — the deviation of the joint from its rest
`C0 * C1:Inverse()` offset. We capture `Motor6D.Transform` directly (Roblox updates
this property when you move parts in the viewport), which gives the value already in
the correct space for `KeyframeSequence`.

### Rest Pose Baseline

On session start, `RigScanner` records the default `Motor6D.Transform` for all joints
(the T-pose). `PoseApplier` resets to these values when playback stops, ensuring rigs
return to their original pose.

### ChangeHistoryService

`PoseApplier` wraps each pose application in:
```lua
ChangeHistoryService:SetWaypoint("MultiAnim Preview")
-- apply Motor6D.Transform changes
ChangeHistoryService:SetWaypoint("MultiAnim Preview End")
```
This keeps preview non-destructive and keeps the Studio undo stack clean.

### Scale Track Interpolation

Between keyframes A and B, part scale is linearly interpolated:
```
alpha = (currentTime - timeA) / (timeB - timeA)
size  = sizeA:Lerp(sizeB, alpha)
```
Applied each `Heartbeat` tick in-game via direct `Part.Size` assignment inside a
`TweenService` call (TweenInfo duration = 1/fps per frame step).

### Pose Tree (KeyframeSequence hierarchy)

```
Keyframe
└── Pose "HumanoidRootPart"   (root, Transform = RootJoint.Transform)
    └── Pose "Torso"
        ├── Pose "Head"
        ├── Pose "Left Arm"
        ├── Pose "Right Arm"
        ├── Pose "Left Leg"
        └── Pose "Right Leg"
```

### Plugin Persistence

Session data is stored in `plugin:GetSetting("session")` as a JSON string so it
survives panel close/reopen within the same Studio session. It is cleared on explicit
"New Session" or when the place file is closed.

---

## Tooling

| Tool | Role |
|------|------|
| Rojo | Syncs `/plugin/` source files → Studio as installed plugin |
| MCP (`execute_luau`) | Quick iteration: run snippets against live Studio without full sync |
| MCP (`inspect_instance`, `search_game_tree`) | Inspect rig state during development |
| Claude Code | All source authoring |

Plugin output path (Rojo target):
`%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxm`
