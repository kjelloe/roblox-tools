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
| `core/RigScanner` | Core | Detects R6/R15/custom rigs; `scan()` scans Workspace.FIGURES (legacy); `scanByTag(scene)` scans by CollectionService tag; `isR6()`, `isR15()`, `isAnimatableRig()` public predicates; `getWorkspaceFolders()` for tag-UI dropdown |
| `core/Recorder` | Core | Session data storage; addKeyframe captures joints+scale+rootCFrame+props; deleteRigKeyframe/deletePropKeyframe |
| `core/JointCapture` | Core | Dynamic Motor6D discovery (`discoverMotors`) works for R6, R15, and custom rigs; topological apply order; validate() checks joint health; computeWorldCFrames() for onion skin FK |
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
| `game/PlayerRigProxy` | Game | Resolves player entries into R6 or R15 rig models; clone/direct modes (Phase 10) |
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
    ├── RigScanner.lua      scan() — legacy: R6 rigs in Workspace.FIGURES
    │                       scanByTag(scene) — rigs tagged "MAnim:<scene>" anywhere in workspace
    │                       isR6(inst) — public R6 predicate
    │                       getWorkspaceFolders() — sorted first-level Folder/Model names
    │
    ├── Recorder.lua        Owns session data; addKeyframe(frame, rigs, props)
    │                       captureRestPose stores joints+scale baseline for restore
    │
    ├── JointCapture.lua    Dynamic Motor6D discovery; works for R6, R15, custom rigs
    │                       discoverMotors(rig) → motors where both container and Part1
    │                         are direct children of the rig model (excludes accessories)
    │                       buildApplyOrder(motors) → topological sort for FK correctness
    │                       validate(rig) → empty list if joints found, else error string
    │                       computeWorldCFrames(rig, jointData) → { [partName]=CFrame }
    │                         (pure FK; does NOT modify any rig BaseParts — used for onion skin)
    │                       Returns: { [motorName] = CFrame }
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

PlayerRigProxy.lua      ModuleScript — resolves player→rig (R6 or R15) for CutscenePlayer
                        .resolve(entry, anchorCF) → rig, teardownFn
                        .resolveAll(rigMap, anchorCFs) → resolvedMap, teardownFn
                        clone mode: character.Archivable = true before Clone()
                          (Roblox default is false; Clone() silently returns nil otherwise);
                          strip scripts/Humanoid, hide original; teardown destroys clone
                          + restores original; Archivable reset to false after Clone().
                          Sets camera.CameraSubject = clone.HumanoidRootPart at resolve time
                          so the player sees the animation (not the hidden original at the
                          trigger zone). Teardown restores CameraSubject to original char
                          Humanoid BEFORE destroying the clone (prevents a frame where
                          CameraSubject points to a destroyed BasePart) and
                          force-unanchors original HumanoidRootPart.
                        direct mode: PlatformStand=true; teardown restores it
                        Supports R6 and R15 player characters

MultiAnimDataServer.lua ModuleScript — server bridge for client playback
                        .setup() — (1) reconnects any Motor6D.Part0 == nil left by
                          the animation plugin (server-side so replicates to clients);
                          (2) creates "MultiAnimGetScene" RemoteFunction in
                          ReplicatedStorage; OnServerInvoke parses scene folder
                          from ServerStorage.MultiAnimationData into serializable
                          Lua table (joints, scale, root, props, camera, effects,
                          spawnedEffects). spawnedEffects is the raw effects array from
                          the SpawnedEffects ModuleScript — plain numbers/strings, so it
                          serialises cleanly over RemoteFunction.
                          parseKFS handles both flat format (current) and legacy R6
                          hierarchy (Torso child) for backward compat.
                        Call setup() once from a Script in ServerScriptService

CutscenePlayer.lua      ModuleScript — client LocalScript orchestrator
                        .play(sceneName, rigMap, opts) → handle
                          opts: { fps (optional; sceneData.fps used when omitted),
                                  loop, movieMode, resetOnEnd }
                          handle.stop() — cancel early
                          handle.onComplete = function() end  — fires after full teardown
                            (natural end OR stop()); set after play() returns
                        Flow: MultiAnimGetScene:InvokeServer → PlayerRigProxy.resolveAll
                          → prop instance resolution (CollectionService tags + workspace
                          search fallback) → LetterboxGui.show (if movieMode)
                          → RunService.Heartbeat loop → doTeardown on finish/stop/error
                        Heartbeat drives: Motor6D.Transform (joints),
                          HumanoidRootPart.CFrame (root track),
                          Part.Size (scale track), Part.CFrame (prop tracks),
                          CurrentCamera (camera track),
                          SpawnedEffectRunner.fire() (spawned effects crossing-pointer)
                        doTeardown (shared): applyAtT0 (if resetOnEnd), teardownRigs,
                          LetterboxGui.hide, camera.CFrame snap to player HRP,
                          camera.CameraType = Custom, handle.onComplete callback.
                          Entire Heartbeat body wrapped in pcall — any error triggers
                          doTeardown so state is always restored.
                        Prop resolution: for each propName in sceneData.props, prefers a
                          CollectionService-tagged BasePart with that name; falls back to
                          workspace:FindFirstChild(propName, true). Prop CFrames are then
                          driven each Heartbeat from the exported PropTracks.
                        NOTE: Touched-event triggers fire once per body part; always use
                          a debounce variable and reset it in handle.onComplete.
                        Requires SpawnedEffectRunner from ReplicatedStorage siblings
                          (deployed there by Exporter.clientMods)
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
        │               Pose tree: flat — HumanoidRootPart → motor-name Poses
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

### Motor6D Disconnect Survives Into Play Mode

When the user presses F5, Roblox copies the current edit-mode workspace into the
play simulation. If motors are disconnected (`Part0 = nil`) at that moment — which
they always are while the plugin is active — the simulation starts with disconnected
joints. `MultiAnimPlayer.findJoints` / `CutscenePlayer.applyJoints` would set
`Motor6D.Transform` on these dead joints with no visual effect.

**Fix — client side:** `MultiAnimPlayer.findJoints` and `CutscenePlayer.buildJointMap`
reconnect any motor with `Part0 == nil` by setting `motor.Part0 = motor.Parent` on
discovery. Both use dynamic motor discovery for R6, R15, and custom rigs.

**Fix — server side (authoritative):** `MultiAnimDataServer.setup()` walks all
`workspace` descendants on the server at game start and reconnects nil Motor6D joints
before creating the `MultiAnimGetScene` RemoteFunction. Server-side reconnection
replicates to all clients, so rigs are never broken regardless of client join order.

### Source Rig Hiding During Cutscene Playback

When `CutscenePlayer.play()` animates a player-character clone (or direct-mode rig) in
a slot that has a tagged source rig, the original rig is hidden for the duration —
otherwise the source and the animated copy are both visible.

**Discovery:** `CollectionService:GetTagged("MAnim:" .. sceneName)` finds all Models
tagged for the scene regardless of which workspace folder they live in (the previous
FIGURES-only approach missed rigs stored elsewhere).

**Hiding:** For each tagged source rig whose slot is played by a different instance
(`resolvedRigs[rigName] ~= src`), all `BasePart` descendants have `Transparency = 1`.
Original values are saved in a `hiddenSourceParts` table.

**Restore:** `teardownRigs` is wrapped to call `restoreSourceRigs()` first (restoring
saved Transparency values), then runs the original teardown (clone destroy, PlatformStand
restore). Fires on both natural end and early `handle.stop()`.

**Teardown robustness:** The entire Heartbeat body is wrapped in `pcall`. Any unhandled
error (malformed keyframe data, destroyed instance, etc.) prints a warning and calls
`doTeardown()` — preventing permanent stuck states (anchored character, hidden source
rigs, Scriptable camera) that previously occurred when the Heartbeat threw.

### Dynamic Rig Support (R6, R15, Custom)

All joint operations now use dynamic Motor6D discovery instead of hardcoded R6 tables.

**Discovery filter** (`discoverMotors` in JointCapture): a Motor6D belongs to the rig if:
- `motor.Parent.Parent == rig` — the container part is a direct child of the rig model
- `motor.Part1.Parent == rig` — Part1 is also a direct child of the rig model

This includes all canonical rig joints for R6 and R15 while excluding accessory welds
(Handle is inside an Accessory model, not a direct child of the character).

**Note:** `motor.Parent` is always the original Part0 container even when `motor.Part0 == nil`
(Roblox convention). This is how discovery works correctly on disconnected motors.

**Apply order** is topologically sorted: `buildApplyOrder` starts from HumanoidRootPart
and processes motors whose container has already been positioned before moving to children.
This gives correct FK order without hardcoding the skeleton structure.

**Export format**: `Exporter.buildKeyframeSequence` now uses a flat format — each motor's
transform is a Pose named by motor name, directly under HumanoidRootPart. `MultiAnimPlayer.parseKFS`
detects the old R6 hierarchy format (Torso child present) for backward compat with existing
exported scenes, and reads the new flat format otherwise.

**RigScanner**: `isR15(inst)` added. `scan()` and `scanByTag()` use `isAnimatableRig()`
(R6 or R15) instead of R6-only. `doTagAllIn` in init.server.lua uses `isAnimatableRig`
for rig detection.

### Tag-Based Scene Organisation

Games with many animations need a way to share rigs across scenes (e.g., a MobBoss
rig reused in five cutscenes without duplication) and to scope rig discovery to the
rigs that participate in a specific animation.

**Tag format:** `MAnim:<sceneName>` — e.g. `MAnim:intro_cutscene`. Applied to any
workspace instance (Model for rigs, BasePart/Model for props, ParticleEmitter etc.
for effects) via `CollectionService:AddTag`.

**Scan behaviour (`doSimpleScan`):**
- Scene name non-empty → `RigScanner.scanByTag(sceneName)` for rigs; prop instances
  scanned from `CollectionService:GetTagged(tag)` filtered to non-rig BaseParts.
- Scene name empty → legacy `RigScanner.scan()` (Workspace.FIGURES) — fully backward
  compatible with existing setups that don't use named scenes.

**"Tag all in" row (top of Simple Mode section):**
```
Tag: [FIGURES ▼]  [Rigs ✓]  [Props ✓]  [Effects □]  [Clear scene tags]  Manual tag: MAnim:Scene_001
```
- Row appears at the very top of Simple Mode (LayoutOrder 1) for immediate access.
- Folder dropdown (`onTagFolderListRequested` event → `RigScanner.getWorkspaceFolders()`
  → `panel:openTagFolderDropdown(names)`) lists first-level workspace Folders/Models.
  Selecting a folder immediately tags qualifying instances and rescans.
- Rigs / Props / Effects are standalone toggle buttons (default Rigs ON, Props ON,
  Effects OFF). They are reset to defaults when "New" is pressed.
- "Refresh tags" (left of "Clear scene tags") adds `MAnim:<scene>` to any new qualifying
  instances in the selected folder (additive — already-tagged instances are skipped).
  Also detects orphaned rig/prop tracks (recorded but no matching instance in the folder)
  and shows an inform-only overlay listing their names.
- "Clear scene tags" shows a confirm overlay with the count of tagged rigs/props/effects
  before removing `MAnim:<scene>` from all tagged instances and rescanning.
- The muted "Manual tag: MAnim:Scene_001" hint updates live as the scene name box
  changes, letting the user apply tags manually via Studio's Tag Editor.
- Tagging is additive (`CollectionService:AddTag` is idempotent); `doClearSceneTags`
  is the explicit reset.

**Scene rename — propagating tags:**
Renaming the scene name box (FocusLost) fires `panel.onSceneRenamed(oldName, newName)`.
The handler in `init.server.lua` uses `CollectionService:GetTagged("MAnim:" .. oldName)`
to collect all tagged instances, removes the old tag, and applies `"MAnim:" .. newName` to
each. `doSimpleScan` is then called to resync the rig/prop lists. The rename is atomic for
all currently tagged instances and survives a plugin reload.

**"New" button (scene row, next to Load):**
- Auto-increments the scene name (`Scene_001` → `Scene_002`, `Foo` → `Foo_001`,
  preserving zero-pad width).
- Shows a confirm overlay listing tagged instance counts + keyframe count.
- On confirm: clears current scene tags (`doClearSceneTags`), resets the full session
  (props, camera, effects, recorder), rescans rigs, resets tag toggles to defaults,
  updates the scene name box.

**Generic tag-action confirm overlay (`panel:showTagConfirm(header, msg, onOkay)`):**
- Reused by both "New" and "Clear scene tags".
- Counts computed in init.server.lua via `getTagCounts(sceneName)` (CollectionService
  query + `isAnimatableRig`/`EffectRunner.classify` categorisation) and
  `getKeyframeCount()` (union of all rig/prop frame sets from the recorder session).

**Lua 200-register limit — `do...end` blocks in Panel.new:**
Panel.lua's `Panel.new` function was hitting Lua 5.1's 200-local-register limit.
Fixed by wrapping the three largest sub-sections in `do...end` blocks (Simple Mode,
Overlays, Playback Tab). Lua's compiler reuses freed registers after each block ends,
so the peak concurrent register count stays under 200. Closures defined inside the
blocks capture their upvalues on the heap (Lua's upvalue mechanism) — no data is lost.

**Design consequence:** rigs can live anywhere in the workspace hierarchy (their actual
game position) rather than being forced into a staging FIGURES folder. A rig gets
tagged for each scene it participates in — one MobBoss rig, many scene tags.

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

Current export uses a flat format — each motor's transform is a Pose named by motor
name, directly under HumanoidRootPart. R6 example:

```
Keyframe
└── Pose "HumanoidRootPart"
    ├── Pose "RootJoint"
    ├── Pose "Neck"
    ├── Pose "Right Shoulder"
    ├── Pose "Left Shoulder"
    ├── Pose "Right Hip"
    └── Pose "Left Hip"
```

`parseKFS` in both `MultiAnimDataServer` and `MultiAnimPlayer` auto-detects legacy R6
hierarchy format (Torso child present under HumanoidRootPart) for backward compatibility
with scenes exported before the flat format was introduced.

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

`serializeSession()` also persists `sceneName` and `tagFolder`. `applySessionData()`
restores both on load. `loadNamed()` falls back to the slot name as scene name for old
saves that predate the `sceneName` field (unless the slot is `_autosave`).

**Test isolation — `scanFigures` bridge command:** UI tests that need specific rigs call `scanFigures` at their start. This calls `scanAndSetup()` (rescans `Workspace.FIGURES`, captures rest poses, disconnects joints, updates the panel) and then normalises `frameCount` to `max(current, 120)` and sets `mode = "advanced"`. Without this, a prior test that left the plugin in Simple Mode (where `frameCount` is reset to 1 for an empty session) would corrupt parking-frame arithmetic (`PARK = frameCount - N` going negative → `setFrame` clamps to 1 → keyframe lands on frame 1, not PARK). Call `scanFigures` at the start of any UI test file that needs deterministic rig availability or adequate timeline length.

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

### Playback Tab

The third mode in the panel (alongside Simple and Advanced). Layout order:

1. Scene selector row: ◄ [scene name] ► — cycles through saved sessions
2. Export warning label (yellow) — visible when the selected scene has no export in
   `ServerStorage.MultiAnimationData`; cleared automatically when the export exists
3. Rig mapping header
4. Rig rows container (dynamic, one row per exported rig): name + mode cycle btn + UserId box
5. Params row: Loop toggle + Movie Mode toggle (FPS removed — read from `sceneData.fps`)
6. Snippet header
7. Snippet TextBox (read-only display, green-tinted code font)
8. Copy row: 📋 Copy Snippet + Preview btn
   - Copy prints snippet to Output (Studio has no clipboard API in plugin context)
   - Preview opens `pbPreviewOv` — an in-panel modal overlay with the full snippet text
     and a ✕ close button (ZIndex 55); no console print

**Rig name discovery:** `refreshCurrentPlaybackScene()` queries
`ServerStorage.MultiAnimationData.<scene>` for child instances that have a
`_Joints KeyframeSequence`. These are the exported rig names — they seed
`playbackRigModes` (preserving existing mode choices) and populate the rig rows.
If no export exists, an empty row set is shown and the export warning fires.

**Snippet generation:** `buildPlaybackSnippet()` builds a Lua string from
`playbackScene`, `playbackRigModes`, `playbackLoop`, and `playbackMovieMode`.
`fps` is never injected into the opts table (CutscenePlayer reads it from the
scene export; the snippet includes a comment to add `fps=N` if needed).

### Plugin Play-Mode Guard

`init.server.lua` begins with `if game:GetService("RunService"):IsRunning() then return end`. The root element of the plugin `.rbxmx` is a `Script` class, which Roblox also executes as a server script when play mode starts. This guard prevents the plugin from disconnecting Motor6D joints or interfering with runtime animation.

---

## SpawnedEffects System (Simple Mode)

Spawned effects are single-frame world-position events (Explosion, Smoke particle
bursts, or Sound playback) defined at an absolute world position, separate from the
existing Effect Track system (which targets live instances in the scene). They are
designed for Simple Mode use: no manual Effect Track setup needed.

### Data model

Each effect entry is a plain table stored in `session.spawnedEffects` (array):

```lua
-- Particle types (Explosion / Smoke):
{
    id         = 1,           -- unique integer, managed by Recorder
    frame      = 5,           -- timeline frame to fire on
    effectType = "Explosion", -- "Explosion" or "Smoke"
    posX, posY, posZ          -- world-space position
    size, colorR, colorG, colorB, count, duration, speed, lifetime  -- scalar params
}

-- Sound type:
{
    id         = 2,
    frame      = 10,
    effectType = "Sound",
    posX, posY, posZ          -- world-space position (3-D rolloff origin)
    soundId    = "rbxassetid://12345678",
    volume     = 1,           -- 0–10
    maxDistance = 80,         -- RollOffMaxDistance
}
```

### Plugin side (`plugin/core/SpawnedEffectRunner.lua`)

- `PRESETS` table: `Explosion` (orange, spread-180°, LightEmission 0.8), `Smoke`
  (gray, spread-25°, no light), `Sound` (soundId="", volume=1, maxDistance=80).
- `PROPS`: ordered list of particle-specific editable properties (not used for Sound).
- `buildParams(effectType, overrides)`: merges preset defaults with user values.
- `fire(pos, effectType, params)`:
  - **Sound:** creates a transparent `Part` at `pos`, parents a `Sound` to it, sets
    `SoundId`/`Volume`/`RollOffMaxDistance`, calls `:Play()`. Destroys on `Ended` or
    after a 30-second `task.delay` fallback. Returns a cancel function.
  - **Particle (Explosion/Smoke):** creates a transparent `Part` + `ParticleEmitter`,
    calls `pe:Emit(params.count)`, `task.delay`-destroys after `duration + lifetime`.
    Returns a cancel function. Used for edit-mode preview immediately after "Add/Update".

### Game side (`game/SpawnedEffectRunner.lua`)

Identical `fire()` function (including Sound branch); zero plugin dependencies. Deployed
to `ServerStorage.MultiAnimationData` via `Exporter.serverMods`. `MultiAnimPlayer`
requires it from `script.Parent` and calls `sfxRunner.fire(pos, effectType, fx)`.

### Recorder CRUD (`plugin/core/Recorder.lua`)

`session.spawnedEffects` is an array (not a dict) — order is preserved for export.
`_nextSpawnedEffectId` increments monotonically. `addSpawnedEffect(data)` respects an
explicit `data.id` for session restore and advances `_nextSpawnedEffectId` past it.
`clearSession()` resets both array and counter. Sound-type entries carry `soundId`,
`volume`, and `maxDistance` instead of particle scalar params.

### Panel overlay (`plugin/ui/Panel.lua`)

- **"Add effect" button** in `simpleActionRow` at layout order 6.
- `do -- SPAWNED FX OVERLAY` block (ZIndex 55, `AutomaticSize = Enum.AutomaticSize.Y`):
  header with frame number; type cycle button (Explosion → Smoke → Sound → Explosion);
  `fxApplyTypeVisibility(effectType)` shows/hides particle rows vs Sound rows —
  `UIListLayout` skips `Visible = false` children so the frame resizes automatically.
  - **Particle rows** (LayoutOrders 3–9): one textbox per PROPS key (Size, Color R/G/B,
    Count, Duration, Speed, Lifetime). Visible when type ≠ Sound.
  - **Sound rows** (LayoutOrders 3–5, `Visible = false` by default):
    `fxSoundIdRow` (SoundId textbox, `ClearTextOnFocus = false`, default "rbxassetid://"),
    `fxSoundVolRow` (Volume), `fxSoundDistRow` (Max Distance). Visible only when Sound.
  - "Select Position" button + coordinate label, Add/Cancel/Delete buttons.
- `showSpawnedFxOverlay(frame, data?)`: calls `fxApplyTypeVisibility`, populates Sound
  fields or particle fields depending on `effectType`.
- `setSpawnedFxPosition(pos)`: called by `init.server.lua` after position pick completes.
- Events: `onSpawnedFxAdded`, `onSpawnedFxUpdated`, `onSpawnedFxDeleted`,
  `onSpawnedFxPickPosRequested`.

### Position picking (`plugin/init.server.lua`)

`panel.onSpawnedFxPickPosRequested` handler:
1. Sets `pickingEffectPos = true`.
2. Calls `plugin:Activate(true)` (exclusive mouse mode).
3. Connects `mouse.Button1Down`; on click, reads `mouse.Hit.Position`, calls
   `plugin:Deactivate()`, fires `panel:setSpawnedFxPosition(pos)`.

### Gizmo spheres

- Folder: `workspace.__MultiAnimEffectGizmos` (`Archivable = false`).
- Each effect gets a `Part` (Ball shape, 0.7 studs, 30% transparent), named
  `SpawnedFX_<id>`. Color: orange `(255,120,0)` for Explosion, gray `(150,150,150)`
  for Smoke, blue `(80,160,255)` for Sound.
- `Selection.SelectionChanged` handler: when the selected Part matches a gizmo, opens
  `panel:showSpawnedFxOverlay(fx.frame, fx)` in edit mode, then clears the selection.
- `destroyAllEffectGizmos()` is forward-declared so `applySessionData` (defined earlier)
  can call it when loading a session.

### Export (`plugin/core/Exporter.lua`)

`buildSpawnedEffectsSource(session)` emits a `return { effects = {...} }` ModuleScript.
Written only when `session.spawnedEffects` is non-empty (file name: `SpawnedEffects`).
Branches on `effectType`: Sound entries emit `soundId`/`volume`/`maxDistance` fields;
particle entries emit the full scalar set. `serializeSession()` applies the same branch
so only the relevant fields are stored per entry.
`SpawnedEffectRunner` is added to both `serverMods` (ServerStorage.MultiAnimationData,
used by MultiAnimPlayer) and `clientMods` (ReplicatedStorage, used by CutscenePlayer).

### Edit-mode playback (`plugin/init.server.lua — startPlayback`)

The `startPlayback` Heartbeat fires spawned effects during **Simple Mode play** using the
same crossing-pointer pattern as `EffectRunner` events:

```lua
for _, sfx in ipairs(recorder:getSpawnedEffects()) do
    if sfx.frame > lastEventFrame and sfx.frame <= intFrame then
        SpawnedEffectRunner.fire(Vector3.new(sfx.posX, sfx.posY, sfx.posZ), sfx.effectType, sfx)
    end
end
```

This runs every Heartbeat alongside the regular `allEffects` loop; `lastEventFrame` is
shared so each frame fires at most once.

### In-game playback via MultiAnimPlayer (`game/MultiAnimPlayer.lua`)

`MultiAnimPlayer.play()` loads `SpawnedEffects` and `SpawnedEffectRunner` from
`script.Parent` (= `ServerStorage.MultiAnimationData`). Builds a sorted
`spawnedFxEvents` list (time = `(frame - 1) / fps`). Fires in the Heartbeat loop via
the same crossing-pointer pattern as `effectEvents`:

```lua
while nextSpawnedFxIdx <= #spawnedFxEvents
      and spawnedFxEvents[nextSpawnedFxIdx].time <= elapsed do
    fireSpawnedFx(spawnedFxEvents[nextSpawnedFxIdx])
    nextSpawnedFxIdx += 1
end
```

`fireSpawnedFx` calls `sfxRunner.fire(Vector3.new(fx.posX, fx.posY, fx.posZ), fx.effectType, fx)`.

### In-game playback via CutscenePlayer (`game/CutscenePlayer.lua`)

`CutscenePlayer.play()` receives `sceneData.spawnedEffects` (raw array) from
`MultiAnimDataServer.getSceneData()` via `MultiAnimGetScene:InvokeServer()`. Builds the
same `spawnedFxEvents` list (time = `(sfx.frame - 1) / fps`). Fires in the Heartbeat
crossing-pointer pattern using `lastSfxTime`:

```lua
for _, ev in ipairs(spawnedFxEvents) do
    if ev.time > lastSfxTime and ev.time <= t then
        SpawnedEffectRunner.fire(
            Vector3.new(ev.sfx.posX, ev.sfx.posY, ev.sfx.posZ),
            ev.sfx.effectType, ev.sfx)
    end
end
lastSfxTime = t
```

`lastSfxTime` resets to `-1` on loop so effects re-fire. `SpawnedEffectRunner` is
required from `selfModule.Parent` (ReplicatedStorage siblings, deployed by Exporter).

### Session persistence

`serializeSession()` serializes `session.spawnedEffects` as a plain array (field-by-field
copy). `applySessionData()` restores them via `recorder:addSpawnedEffect(fxData)` and
recreates gizmos. Both sides call `destroyAllEffectGizmos()` first to avoid duplicates.

---

## Delete scene dialog

A **Delete** button (red, position 8 in `simpleSceneRow`) opens a full-panel **Delete
overlay** that mirrors the Load overlay structure:

- Header "DELETE SESSION" + ✕ close button.
- `ScrollingFrame` listing all saved sessions (same row format as Load: name left, timestamp right).
- **Cancel** button in a footer bar (also added to Load overlay).
- Clicking a session row shows a **confirmation card** (ZIndex 60, parented to the overlay):
  "Are you sure you want to delete `"<name>"`?" with a red **Yes** and a grey **No** button.
  No hides the card; Yes fires `eDeleteNamed` → `onDeleteNamedRequested` → `deleteNamed(name)`.

`deleteNamed(name)` removes the entry from the index array and calls
`plugin:SetSetting(DATA_PREFIX .. name, nil)` + re-saves the index.
After deletion, `doPlaybackScan()` is called to remove the scene from the Playback tab list.

TestBridge commands: `deleteSession {name}`, `listSessions` (returns name array).

---

## Tooling

| Tool | Role |
|------|------|
| `build.py` | Assembles `.rbxmx` from source files and copies to Plugins folder |
| `export.py` | Packages plugin + game-side runtime scripts as distributable `.rbxm` files into `export/` |
| `watch.py` | Auto-build on save, with Studio compile-check first |
| `devsync.py` + `plugin/devloader.lua` | Hot-reload the plugin on save — no Studio restart |
| `run_tests.py` | Runs the full `tests/` suite (626 cases, 27 files) against live Studio |
| `hotpatch.py` | Push a single `game/` module without reload (all 7 game/ modules in PATCH_MAP) |
| `mcp.py` (`mcp` alias) | CLI for everything: luau, console/tail, tree/inspect/read/grep, check, drift, test, deploy, playtest, gen, store, addrig, scene, daemon |
| MCP daemon | Persistent StudioMCP proxy (auto-starts) — 0.07s/call vs ~7s |
| Claude Code | All source authoring, MCP tool calls |

Full tool documentation: `DEV_TOOLS.md`. Human guide: repo-root `README.md`.

Plugin output path:
`%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx`
