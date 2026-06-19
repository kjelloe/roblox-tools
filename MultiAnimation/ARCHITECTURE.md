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
│  │  ├── MultiAnimPlayer (ModuleScript)                 │   │
│  │  └── Scene_001                                      │   │
│  │      ├── Rig1_Joints   (KeyframeSequence)           │   │
│  │      ├── Rig2_Joints   (KeyframeSequence)           │   │
│  │      ├── ScaleTracks   (ModuleScript)               │   │
│  │      ├── RootTracks    (ModuleScript, optional)     │   │
│  │      └── PropTracks    (ModuleScript, optional)     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Live Game (play mode / published)                          │
│                                                             │
│  Script                                                     │
│    └── require(MultiAnimPlayer).play("Scene_001", rigMap)   │
│                    │                                        │
│                    ▼                                        │
│          RunService.Heartbeat loop                          │
│            Motor6D.Transform  (joints)                      │
│            Part.Size          (scale)                       │
│            HRP.CFrame         (root motion)                 │
│            Part.CFrame        (props)                       │
│                    │                                        │
│    ┌───────────────┴───────────────┐                        │
│    │   Rig1    │   Rig2    │ Props │  ← all simultaneous   │
│    └───────────┴───────────┴───────┘                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Module Inventory

| Module | Layer | Purpose |
|--------|-------|---------|
| `init.server.lua` | Entry | Toolbar, widget, event wiring, playback loop, Selection sync, play-mode guard |
| `core/RigScanner` | Core | Detects R6 rigs in Workspace.FIGURES |
| `core/Recorder` | Core | Session data storage; addKeyframe captures joints+scale+rootCFrame+props; deleteRigKeyframe/deletePropKeyframe |
| `core/JointCapture` | Core | Reads/writes Motor6D.Transform; validate() checks joint health; computeWorldCFrames() for onion skin FK |
| `core/ScaleCapture` | Core | Reads/writes Part.Size |
| `core/PropCapture` | Core | Reads/writes BasePart.CFrame (world space) |
| `core/TestBridge` | Core | CoreGui BindableFunction — lets execute_luau drive the live panel (UI tests) |
| `core/CameraCapture` | Core | Reads/writes the Studio viewport camera (capture keyframes, Camera Preview) |
| `core/Timeline` | Core | Frame counter, fps, prev/next KF helpers |
| `core/Interpolator` | Core | Per-keyframe easing lerp between keyframes (joints, scale, root, prop, camera); `easedAlpha` via TweenService |
| `core/PoseApplier` | Core | Applies poses; manages ChangeHistoryService |
| `core/Exporter` | Core | Builds KeyframeSequence (uses `Pose.CFrame`) + ScaleTracks + RootTracks + PropTracks |
| `ui/Panel` | UI | Root layout; owns all sections and events |
| `ui/RigSelector` | UI | Per-rig exclusive-select buttons (radio-button style) |
| `ui/PropSelector` | UI | Per-prop multi-select toggle buttons + Track Part button |
| `ui/TrackLane` | UI | One horizontal keyframe lane per rig or prop (colour-coded) |
| `ui/KeyframeMarker` | UI | Individual dot on a TrackLane; left-click jumps, right-click opens easing/delete context menu |
| `ui/Scrubber` | UI | Horizontal drag slider for frame position |
| `game/MultiAnimPlayer` | Game | In-game simultaneous playback — direct Motor6D.Transform Heartbeat loop |
| `game/CutsceneServer` | Game | Synchronized cutscene start: plays anims, broadcasts camera track + timestamp |
| `game/CutsceneCamera` | Game | Client camera driver: Scriptable camera follows CameraTrack on a shared clock |
| `game/LetterboxGui` | Game | Cinematic black bars (top/bottom 10%) in PlayerGui ScreenGui (Phase 10) |
| `game/PlayerRigProxy` | Game | Resolves player entries into R6 rig models; clone/direct modes; R6-only (Phase 10) |
| `game/MultiAnimDataServer` | Game | Server-side `MultiAnimGetScene` RemoteFunction — parses scene from ServerStorage (Phase 10) |
| `game/CutscenePlayer` | Game | Client LocalScript orchestrator — Heartbeat loop for joints, root, scale, camera (Phase 10) |

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
│   ├── Panel.lua           Root frame layout, all sections, and events
│   ├── RigSelector.lua     Row of exclusive-select buttons, one per discovered rig
│   │                       Fires: onRigToggled(rigName, isActive)
│   ├── PropSelector.lua    "PROPS IN SCENE" section; Track Part + multi-select toggles
│   │                       Fires: onPropToggled, onTrackPart, onRemoveProp
│   ├── TrackLane.lua       Horizontal lane showing keyframe dots for one rig or prop
│   │                       Fires: onKeyframeClicked(frame), onDoubleClicked(frame)
│   ├── KeyframeMarker.lua  Single dot on a TrackLane; left-click jumps, right-click deletes
│   └── Scrubber.lua        Horizontal drag slider; overlay Frame for cross-panel input
│
└── core/
    ├── RigScanner.lua      Scans Workspace.FIGURES for R6 models
    │                       Returns: { [name] = ModelInstance }
    │
    ├── Recorder.lua        Owns session data; addKeyframe(frame, rigs, props)
    │                       captureRestPose stores joints+scale baseline for restore
    │
    ├── JointCapture.lua    Reads Motor6D.Transform for all 6 R6 joints
    │                       validate(rig) → list of broken/missing Motor6Ds
    │                       computeWorldCFrames(rig, jointData) → { [partName]=CFrame }
    │                         (pure FK; does NOT modify any rig BaseParts — used for onion skin)
    │                       Returns: { [jointName] = CFrame }
    │
    ├── ScaleCapture.lua    Reads Part.Size for all 7 R6 body parts
    │                       Returns: { [partName] = Vector3 }
    │
    ├── PropCapture.lua     Reads/writes BasePart.CFrame (world space)
    │
    ├── TestBridge.lua      BindableFunction in CoreGui (JSON protocol) so
    │                       execute_luau can drive the panel — UI integration tests
    │
    ├── CameraCapture.lua   Reads/writes workspace.CurrentCamera (CFrame + FOV)
    │                       capture keyframes; Camera Preview save/apply/restore
    │
    ├── Timeline.lua        Tracks currentFrame, frameCount, fps
    │                       Interpolation helpers (lerp between keyframes)
    │
    ├── Interpolator.lua    Per-keyframe easing lerp (joints, scale, root, prop, camera)
    │                       easedAlpha via TweenService:GetValue
    │                       getPropData, getAllPropFrames, getAllFrames
    │
    ├── PoseApplier.lua     Writes joint CFrames back to Motor6Ds (viewport preview)
    │                       applyPropRecorded / applyPropImmediate for prop CFrames
    │                       Wrapped in ChangeHistoryService waypoints
    │
    └── Exporter.lua        Builds KeyframeSequence instances from session data
                            Builds ScaleTracks + RootTracks + PropTracks ModuleScripts
                            Deploys MultiAnimPlayer into ServerStorage
                            Writes to ServerStorage.MultiAnimationData/<scene>/
```

### Game (`game/`)

```
MultiAnimPlayer.lua     ModuleScript — no plugin dependency
                        API:
                          .play(sceneName, rigMap, propMap?)
                          .stop()
                          .onFinished(callback)

CutsceneServer.lua      ModuleScript — server side of synchronized cutscenes
                        .play(sceneName, rigMap, propMap?) — plays anims via
                        MultiAnimPlayer + broadcasts camera track & timestamp
                        .stop() / .onFinished(callback)

CutsceneCamera.lua      ModuleScript — client camera driver
                        .start() — listens for the MultiAnimCutscene RemoteEvent
                        and drives a Scriptable camera against the shared clock

-- Phase 10: client-side player-rig playback pipeline --

LetterboxGui.lua        ModuleScript — cinematic black bars
                        .show() / .hide() / .isVisible()
                        Creates ScreenGui in PlayerGui (DisplayOrder 200)

PlayerRigProxy.lua      ModuleScript — resolves player→R6 rig for CutscenePlayer
                        .resolve(entry, anchorCF) → rig, teardownFn
                        .resolveAll(rigMap, anchorCFs) → resolvedMap, teardownFn
                        clone mode: character:Clone(), strip scripts/Humanoid,
                          hide original; teardown destroys clone + restores original
                        direct mode: PlatformStand=true; teardown restores it
                        R6-only: warns + returns nil for R15

MultiAnimDataServer.lua ModuleScript — server bridge for client playback
                        .setup() — creates "MultiAnimGetScene" RemoteFunction in
                          ReplicatedStorage; OnServerInvoke parses scene folder
                          from ServerStorage.MultiAnimationData into serializable
                          Lua table (joints, scale, root, props, camera, effects)
                        Call setup() once from a Script in ServerScriptService

CutscenePlayer.lua      ModuleScript — client LocalScript orchestrator
                        .play(sceneName, rigMap, opts) → handle
                          opts: { fps, loop, movieMode }
                          handle.stop() — cancel early
                        Flow: MultiAnimGetScene:InvokeServer → PlayerRigProxy.resolveAll
                          → LetterboxGui.show (if movieMode) → RunService.Heartbeat loop
                          → teardown on finish
                        Heartbeat drives: Motor6D.Transform (joints),
                          HumanoidRootPart.CFrame (root track),
                          Part.Size (scale track), CurrentCamera (camera track)
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
User presses "Add Keyframe" (or K shortcut, or double-click track lane)
        │
        ▼
init.server.lua: doAddKeyframe()
        │
        ├── JointCapture.validate(rig) — abort if Motor6Ds broken
        │
        ▼
Recorder.addKeyframe(frame, activeRigs, activeProps)
        │
        ├── for each activeRig:
        │       JointCapture.capture(rig)    → jointData
        │       ScaleCapture.capture(rig)    → scaleData
        │       RootCapture (HRP.CFrame)     → rootCFrame
        │       session.rigs[rigName].jointTrack[frame] = jointData
        │       session.rigs[rigName].scaleTrack[frame] = scaleData
        │       session.rigs[rigName].rootTrack[frame]  = rootCFrame
        │
        ├── for each activeProp:
        │       PropCapture.capture(part)    → propCFrame
        │       session.props[propName].propTrack[frame] = propCFrame
        │
        └── UI event → TrackLane.addMarker(name, frame) for each rig + prop
```

## Data Flow: Export

```
User presses "Export"
        │
        ▼
Exporter.export(session, sceneName)
        │
        ├── for each rig in session:
        │       build KeyframeSequence  (Rig1_Joints, Rig2_Joints, …)
        │           for each frame in jointTrack:
        │               Keyframe at time = frame/fps
        │               Pose tree: HumanoidRootPart → Torso → limbs/head
        │               each Pose.CFrame = captured Motor6D.Transform CFrame
        │       insert KeyframeSequence into scene folder
        │
        ├── build ScaleTracks — { fps, rigs={...}, easings={...} }
        │       per-frame easing in parallel easings table (omitted if all Linear)
        │       serialise to ModuleScript source; insert into scene folder
        │
        ├── build RootTracks — { fps, rigs={...}, easings={...} }
        │       omitted if no rig has whole-model movement keyframes
        │
        ├── build PropTracks — { fps, props={...}, easings={...} }
        │       omitted if no props were tracked
        │
        ├── deploy MultiAnimPlayer ModuleScript into MultiAnimationData root
        │
        └── create/overwrite ServerStorage.MultiAnimationData[sceneName]
```

## Data Flow: In-game Playback

```
require(MultiAnimPlayer).play("Scene_001", rigMap, propMap?)
        │
        ▼
Load from ServerStorage.MultiAnimationData.Scene_001
        │
        ├── parseKFS(Rig_Joints KeyframeSequence)   → sorted { {time, poses, easing} }
        ├── toSortedKFs(ScaleTracks.rigs[name], fps, buildFn, easingsTable)
        │     → sorted { {time, data=parts, easing} }
        ├── toSortedKFs(RootTracks.rigs[name], fps, buildFn, easingsTable)
        │     → sorted { {time, data=CFrame, easing} }
        ├── toSortedKFs(PropTracks.props[name], fps, buildFn, easingsTable)
        │     → sorted { {time, data=CFrame, easing} }
        │
        └── RunService.Heartbeat loop (startTime = tick()):
                elapsed = tick() - startTime
                for each rig:
                    surrounding(jointKFs, elapsed) → before, after
                    t = easedAlpha(alpha, before.easing)
                    motor.Transform = lerpCF(before.poses[j], after.poses[j], t)
                    part.Size       = lerpV3(before.data[p],  after.data[p],  t)
                    hrp.CFrame      = lerpCF(before.data,     after.data,     t)
                for each prop:
                    t = easedAlpha(alpha, before.easing)
                    part.CFrame     = lerpCF(before.data,     after.data,     t)
                if elapsed >= totalLength → fireFinished(sceneName)
```

---

## Key Technical Decisions

### Motor6D Weld Behaviour in Studio Edit Mode

**Critical finding (confirmed via live `execute_luau` tests):**

In Studio edit mode, Motor6D joints act as rigid welds:
- Setting `Part.CFrame` via script moves the **entire connected assembly**, not just that part.
- Writing `Motor6D.Transform` has **no visual effect** — the property is inert until
  the physics engine runs (play mode).
- Reconnecting a motor (`Part0` nil → valid) immediately snaps `Part1` to the
  rest-pose position, regardless of any `Transform` value written beforehand.

**Consequence for capture:**  
Studio's viewport tools move the whole rig together, so `Motor6D.Transform` is never
updated and relative joint positions never change — making pose data unrecordable
while motors are connected.

**Fix — permanent motor disconnect:**  
`JointCapture.disconnectAll(rig)` sets `motor.Part0 = nil` for all 6 joints at
session start.  While disconnected:
- Individual parts can be freely moved/rotated in the viewport (no weld cascade).
- `capture()` computes `Transform = C0:Inv * Part0.CFrame:Inv * Part1.CFrame * C1`
  from actual positions — correct and non-identity for posed limbs.
- `apply()` sets each `Part.CFrame` via forward kinematics with no interference.

`reconnectAll()` restores `Part0` on plugin unload, leaving the rig in a clean state.

### Motor6D Transform vs. C0/C1

Roblox animations store the joint deviation in `Pose.CFrame` (renamed from `Pose.Transform` in a Studio update) — the joint's deviation from its rest `C0 * C1:Inverse()` offset. We derive this value from actual part CFrames:
`Transform = C0:Inv * Part0.CFrame:Inv * Part1.CFrame * C1`
This formula gives the value already in the correct space for `KeyframeSequence` and `Motor6D.Transform`.

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
Applied each `Heartbeat` tick in-game via direct `Part.Size` assignment in the same
loop as joint, root, and prop interpolation.

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

### DockWidget Input Model

`UserInputService` mouse events (`InputChanged`, `GetMouseLocation`, `IsMouseButtonPressed`) do **not** fire inside a `DockWidgetPluginGui`. Only `GuiObject` events work.

**Scrubber drag:** A transparent overlay `Frame` is parented to the `DockWidgetPluginGui` (not any `UIListLayout` container) so `InputChanged` fires across the full panel width without disrupting layout. The source element's `InputEnded` owns the mouse-button release signal.

### Prop Track System (Phase 7)

Props are `BasePart` instances tracked by the animator on demand. They are architecturally parallel to rigs but simpler — no Motor6D, no joint hierarchy, just world-space `CFrame`.

**Discovery:** `Selection:Get()` when the animator clicks "Track Part". The selected instance must be a `BasePart` with a name unique across all tracked props and rigs. Sub-parts (MeshPart, ParticleEmitter) follow the parent automatically; their own properties are not captured.

**Track data:** `session.props[propName].propTrack[frame] = CFrame` (world space). Stored parallel to `session.rigs` in `Recorder`.

**UI:** "PROPS IN SCENE" section with multi-select toggle buttons (independent of the exclusive rig selector). Prop track lanes use teal `#00CFCF` keyframe dots to distinguish from rig lanes (yellow). × button removes the prop from the active list; data is retained in the session.

**Interpolation:** `CFrame:Lerp(alpha)` — spherically interpolates rotation (slerp). Applied in `PoseApplier.applyPropPoses` during scrub and in `MultiAnimPlayer`'s Heartbeat loop during in-game playback.

**Export:** `PropTracks` ModuleScript written alongside `ScaleTracks` in the scene folder. Absent if no props were tracked. `MultiAnimPlayer.play(scene, rigMap, propMap?)` — `propMap` is optional for backward compatibility.

### Viewport Selection Sync

`Selection.SelectionChanged` fires when the user clicks in the Studio viewport. The handler walks each selected instance's ancestor chain to find a matching rig in `allRigs`. If any rig is found, `panel:setActiveRigs(rigNames)` sets the selector buttons. Ignored during playback.

### Exclusive Rig Selection

Rig buttons behave as radio buttons: clicking a button sets only that rig active and clears all others in a single loop over `self._active`. If the clicked rig is already the active one, the handler returns early. On initial load, rig names are sorted alphabetically and the first is activated — giving a deterministic default regardless of table iteration order.

`setActiveRigs(rigNames)` (used by viewport sync) also enforces this: it sets `_active[name] = rigNames[name] == true` for all rigs, so passing `{ Rig2 = true }` correctly deactivates Rig1 and activates Rig2.

### Double-Click Track Lane → Add Keyframe

`track.InputBegan` (GuiObject event, works in DockWidgets) tracks the time of the last `MouseButton1` press. If a second press arrives within 0.35 s, it fires `onDoubleClicked(frame)`. The frame is derived from the click's X position relative to the track area:

```
frame = clamp( round((relX / trackWidth) * (frameCount - 1)) + 1, 1, frameCount )
```

Propagation: `TrackLane.onDoubleClicked → Panel.onTimelineDoubleClicked(rigName, frame) → init.server.lua` which calls `timeline:setCurrent`, `applyPosesAt`, and `recorder:addKeyframe` for that rig only. Clicking on an existing marker (TextButton) sinks the input and does not trigger the track's double-click handler.

### Keyframe Deletion

Right-clicking a `KeyframeMarker` fires `onDeleteRequested(frame)` via `MouseButton2Click`. This propagates up through `TrackLane.onMarkerDeleteRequested → Panel.onMarkerDeleteRequested(rigName, frame)` and is handled in `init.server.lua` by calling `recorder:deleteRigKeyframe(rigName, frame)` followed by `panel:removeKeyframeMarker(rigName, frame)`. Only the clicked rig's data is removed; other rigs' keyframes at the same frame are unaffected.

### Plugin Persistence

Session data is stored in `plugin:GetSetting("session")` as a JSON string so it
survives panel close/reopen within the same Studio session. It is cleared on explicit
"New Session" or when the place file is closed.

**frameCount persistence invariant:** `serializeSession()` saves `advancedFrameCount or session.frameCount`. This prevents the small synthetic frameCount that Simple/Playback mode writes into the recorder (`maxKF+1` or 1 for empty session) from being persisted to disk — autosave may fire while in those modes, but the saved value is always the real advanced-mode length. `doLoad` additionally clamps the loaded frameCount to `math.max(data.frameCount, 20)` as a safety floor against corrupt saves. All three entry points to Playback mode (UI button `onModeChanged`, `setMode` bridge command, `setPlaybackMode` bridge command) must save `advancedFrameCount = timeline:getFrameCount()` when entering, so the restoration on return to Advanced mode works correctly — same invariant as Simple mode entry.

### Whole-Model Movement (Root Track)

`session.rigs[rigName].rootTrack[frame] = HumanoidRootPart.CFrame` — world-space CFrame captured alongside joint/scale data in every `addKeyframe` call.

**In-editor:** `PoseApplier.applyRecorded/applyImmediate` accepts an optional `rootCFrame`. When present, it sets `HumanoidRootPart.CFrame` **before** applying joint transforms, so all limbs reposition correctly relative to the new root (forward kinematics from HRP down).

**Export:** `RootTracks` ModuleScript written alongside `ScaleTracks` (omitted if no rig had whole-model movement). Same 12-number array format as PropTracks.

**In-game:** `MultiAnimPlayer` loads `RootTracks`, interpolates HRP world CFrames in the Heartbeat loop (`CFrame:Lerp()`) in the same pass as scale and prop tracks.

### Scrubber Alignment

The scrubber track is inset by 56 px (`TrackLane.LABEL_W 52 + UIListLayout gap 4`) so the thumb and fill bar align vertically with the keyframe dots in the track lanes. The `leftOffset` parameter to `Scrubber.new` controls this. `frameFromInputX` uses `track.AbsolutePosition.X` so the maths are unaffected.

### Auto-Update Keyframe on Scrub Departure

`onScrubBegan` fires when the user clicks the scrubber thumb or track. At that moment the current frame is the "departure frame". If that frame has keyframes for any active rig or prop, `recorder:addKeyframe` re-captures the current pose. This lets the user pose a rig while parked at a keyframe and move the scrubber away — the change is saved without an explicit "Add Keyframe" click. Idempotent if nothing was changed.

### Keyboard Shortcuts

Wired via `UserInputService.InputBegan` with `gameProcessed` guard (TextBox focus suppresses all shortcuts):

| Key | Action |
|-----|--------|
| `K` | `doAddKeyframe()` — same as "+ Add Keyframe" button |
| `L` | `doStepFrame(+1)` — advance by Step frames, auto-update if at a KF |
| `J` | `doStepFrame(-1)` — step back by Step frames, auto-update if at a KF |

`doStepFrame` reuses the same departure-frame auto-update logic as `onScrubBegan`.

### Pose.CFrame API (Roblox rename)

Roblox renamed `Pose.Transform` → `Pose.CFrame` in a Studio update. The Exporter uses `p.CFrame = cf` (not `p.Transform`). A regression-guard test in `test_exporter.lua` confirms `Pose.Transform` is gone and `Pose.CFrame` works.

### In-game Playback — Direct Motor6D.Transform (no AnimationClipProvider)

`AnimationClipProvider:RegisterKeyframeSequence` was removed from Roblox's server-side API. `MultiAnimPlayer` now drives animation by setting `Motor6D.Transform` directly in a `RunService.Heartbeat` loop — which is exactly what the Animator service does internally. This approach:
- Works on both server and client without any deprecated API
- Reads pose data from the exported `KeyframeSequence` instances (parsing the Pose hierarchy)
- Interpolates joint transforms with `CFrame:Lerp()` between keyframes
- Applies scale (via `Part.Size`) and root motion (via `HumanoidRootPart.CFrame`) in the same loop

### Camera Track & Cutscenes (Phase 8)

One camera track per session. Keyframes (`{cf, fov, mode}`) are captured from
`workspace.CurrentCamera` (the `C` shortcut or the 📷 button); each keyframe is
either `"move"` (interpolated from the previous shot — CFrame:Lerp + linear FOV)
or `"cut"` (the previous shot holds until the cut frame, then jumps).

**Edit-mode preview:** plugins may drive `workspace.CurrentCamera` in edit mode.
The "Cam Preview" toggle saves the viewport camera state, then `applyPosesAt`
slaves the viewport to the interpolated track during scrub/preview; toggling
off restores the saved state exactly.

**Gizmos:** every camera keyframe renders an orange (move) or red (cut) part in
`workspace.__MultiAnimCameraGizmos`, `Archivable = false` so they never save
with the place. The Hinge stud on the front face marks the look direction.
Clicking a gizmo jumps the timeline to its frame (Selection handler); dragging
it with Studio tools rewrites that keyframe's CFrame (guarded against the
programmatic-update feedback loop with a `gizmoSyncing` flag).

**Synchronized playback:** `CutsceneServer.play` fires a RemoteEvent carrying
the scene name, a `GetServerTimeNow()+0.35s` start timestamp, and the
CameraTrack data (clients cannot read ServerStorage). The server starts the rig
animation on the same clock; each client's `CutsceneCamera` drives a
`Scriptable` camera per RenderStepped against the shared timestamp and restores
the player camera afterwards. Rig motion replicates ~50–100 ms behind the
locally-computed camera — accepted v1 trade-off.

### Simple Mode — Slot-Mapped Icon Strip

The Simple Mode frame icon strip maps *slot indices* (1, 2, 3…) to *actual frame numbers* (which may be sparse, e.g. 1, 4, 9…). This keeps the icon strip and scrubber width equal to the number of keyframed frames rather than the total frameCount.

Two lookup tables are built by `Panel:setSimpleSlots(sortedFrames)` and kept in sync with every Add/Insert/Delete Frame operation:
- `_simpleSlotFrames[slotIdx] = actualFrame`
- `_simpleFrameToSlot[actualFrame] = slotIdx`

The scrubber fires slot indices; the `onFrameChanged` callback translates to actual frame numbers via `_simpleSlotFrames`. `setFrameDisplay` translates back to slot indices via `_simpleFrameToSlot` so the scrubber thumb tracks the correct slot. All call sites use `panel:setSimpleSlots(getSimpleKeyframedFrames())` rather than the old `rebuildSimpleFrameIcons` + `setSimpleIconWidth` pair.

### Simple Mode — Onion Skin

When "Onion Skin" is ON, `updateOnionSkin()` creates a transient folder `workspace.__MultiAnimOnionSkin` (`Archivable = false`) containing ghost Parts for the previous and next keyframed frames relative to the current cursor position.

Ghost CFrames are computed by `JointCapture.computeWorldCFrames(rig, jointData)`:
- Walks `APPLY_ORDER` (same joint order as `apply()`)
- Computes each part's world CFrame via `parentCF * motor.C0 * transform * motor.C1:Inverse()`
- Writes results into a local table — **never modifies any real rig BasePart**

Ghost Parts use `Color3.fromRGB(255,80,80)` (red = previous frame) and `Color3.fromRGB(80,80,255)` (blue = next frame), `Transparency = 0.65`, `CanCollide = false`, `Anchored = true`, `CastShadow = false`. The folder is destroyed and rebuilt on every frame change when onion skin is active, and on toggle-off or mode exit.

`CameraType = Scriptable` is intentionally **not** set when Look Through is active, so Studio's built-in editor controls (right-click drag, WASD, scroll) remain functional. The Heartbeat copies `Camera.CFrame → simpleCameraPart` one-way so the gizmo follows the viewport.

### Per-Keyframe Easing Curves

Easing is stored **per frame per track** — the value at frame F controls the
interpolation from F toward the next keyframe (the "outgoing" segment).

**Storage:**
- Rigs/props: `easingTrack[frame]` inside each rig/prop record in `Recorder`
- Camera: inline `.easing` field on each keyframe record
- Absent entries default to `"Linear"`

**Plugin interpolation (`Interpolator.lua`):** uses `TweenService:GetValue(t, style, dir)`.

**Game interpolation (`MultiAnimPlayer.lua`, `CutsceneCamera.lua`):** pure-math
implementation (no TweenService — CLAUDE.md constraint). Identical outputs for the
6 supported styles.

**Export format:** KFS `Pose.EasingStyle`/`EasingDirection` set per frame. Scale/root/prop
tracks use a parallel `easings = { [rigName] = { [frame] = "..." } }` table alongside
the existing `rigs`/`props` data; omitted entirely when all frames are Linear (backward
compat). Camera track gains an inline `easing` field on each frame record.

**Context menu:** `KeyframeMarker` fires `onDeleteRequested(frame, absPos)` on right-click.
`Panel._showContextMenu` builds a 6-easing + Delete menu positioned over a full-screen
transparent overlay (ZIndex 40). Outside click dismisses via overlay `MouseButton1Click`.

**Simple mode:** the "Ease: Linear" button (action row, col 5) opens the same menu with
easing-only options. `simpleCurrentEasing` is stamped onto all tracks at capture time.
Frame navigation syncs the button to the stored easing of the arrived-at keyframe.

### Plugin Play-Mode Guard

`init.server.lua` begins with `if game:GetService("RunService"):IsRunning() then return end`. The root element of the plugin `.rbxmx` is a `Script` class, which Roblox also executes as a server script when play mode starts. This guard prevents the plugin from disconnecting Motor6D joints or interfering with runtime animation.

---

## Tooling

| Tool | Role |
|------|------|
| `build.py` | Assembles `.rbxmx` from source files and copies to Plugins folder |
| `watch.py` | Auto-build on save, with Studio compile-check first |
| `devsync.py` + `plugin/devloader.lua` | Hot-reload the plugin on save — no Studio restart |
| `run_tests.py` | Runs the full `tests/` suite (~507 cases, 23 files) against live Studio |
| `hotpatch.py` | Push a single `game/` module without reload |
| `mcp.py` (`mcp` alias) | CLI for everything: luau, console/tail, tree/inspect/read/grep, check, drift, test, deploy, playtest, gen, store, addrig, scene, daemon |
| MCP daemon | Persistent StudioMCP proxy (auto-starts) — 0.07s/call vs ~7s |
| Claude Code | All source authoring, MCP tool calls |

Full tool documentation: `DEV_TOOLS.md`. Human guide: repo-root `README.md`.

Plugin output path:
`%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx`
