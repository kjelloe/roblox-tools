# MultiAnimation — Implementation Phases

## Overview

| Phase | Name | Status |
|-------|------|--------|
| 1 | Scaffold | ✅ Complete |
| 2 | Capture | ✅ Complete |
| 3 | Preview | ✅ Complete |
| 4 | Export | ✅ Complete |
| 5 | In-game Playback | ✅ Complete |
| 6 | Polish | ✅ Complete |
| 7 | Prop Animation | ✅ Complete |
| 8 | Camera Track & Cutscenes | ✅ Complete |
| 9 | Future | ⬜ Backlog |

---

## Phase 1 — Scaffold ✅

Plugin boots, docked panel opens, rigs listed with toggle buttons.

- Rojo project + `build.py` (generates `.rbxmx`, no Rojo install needed)
- Toolbar button toggles dock widget
- `RigScanner` finds R6 models in `Workspace.FIGURES`
- `RigSelector` renders toggle buttons; prevents deselecting last rig
- Refresh button rescans

**Note:** Plugin appears under the Plugins menu/toolbar, not in "Manage Plugins"
(which is marketplace-only). This is expected Studio behaviour.

---

## Phase 2 — Capture ✅

Keyframes recorded, dots appear on track lanes.

- `JointCapture` — derives joint transforms from actual part CFrames (not
  `Motor6D.Transform`, which is never updated by Studio's edit tools)
- `ScaleCapture` — reads `Part.Size` for all 7 R6 body parts
- `Recorder` — stores session data; `addKeyframe(frame, activeRigs)`
- `Timeline` — frame counter, fps, navigation helpers
- `TrackLane` + `KeyframeMarker` — visual dots per rig
- CONTROLS: frame box, step `◄`/`►`, total/fps inputs, + Add Keyframe button

---

## Phase 3 — Preview ✅

Scrub and play back poses live in the viewport (edit mode, no play mode needed).

- `PoseApplier` — `applyRecorded` (with ChangeHistoryService) and
  `applyImmediate` (for playback loop)
- `Interpolator` — linear lerp between keyframes for joints (CFrame) and
  scale (Vector3); `getAllFrames` for cross-rig KF navigation
- `Scrubber` — horizontal drag slider; fires `onDragBegan`/`onDragEnded`
  so `ChangeHistoryService` is paused during drag; drag uses a transparent
  overlay Frame parented to the DockWidgetPluginGui (not the UIListLayout root)
  so `InputChanged` fires across the full panel without disrupting layout;
  source-element `InputEnded` owns the mouse-button release signal
- `|◄` / `►|` — rewind to frame 1 / fast-forward to last frame
- `◄` / `►` — step one frame back / forward
- `▶ Preview` — `RunService.Heartbeat` loop; `ChangeHistoryService:SetEnabled(false)`
  during playback
- `■ Stop` — disconnects loop, re-enables history, sets waypoint
- `Save` / `Load` buttons — persist session via `plugin:SetSetting`
  (CFrames serialised as 12-number arrays, Vector3s as 3-number arrays)

**Key technical finding — Motor6D weld behaviour in edit mode:**
In Studio edit mode Motor6D acts as a rigid weld: setting any `Part.CFrame`
moves the entire connected assembly, and writing `Motor6D.Transform` has no
visual effect.  Fix: `disconnectAll()` sets `motor.Part0 = nil` for all 6
joints at session start; this lets the user pose individual limbs freely and
lets `apply()` set CFrames correctly.  Motors are reconnected on plugin unload.
Confirmed and root-caused via live `execute_luau` headless tests.

---

## Phase 4 — Export ✅

Write animation data to `ServerStorage` as usable Roblox assets.

### Tasks

- [x] `Exporter.lua`:
  - Build `KeyframeSequence` per rig from `jointTrack` (correct R6 Pose hierarchy)
  - Serialise `scaleTrack` to a Lua table string → `ModuleScript`
  - Create `ServerStorage.MultiAnimationData` folder if missing
  - Create named scene subfolder; overwrite silently if exists (dialog deferred to Phase 6)
- [x] Scene name `TextBox` in CONTROLS (default `Scene_001`)
- [x] Wire `⬆ Export` button → `Exporter.export(session, sceneName)`

### Acceptance Criteria

- Pressing Export creates `ServerStorage.MultiAnimationData.Scene_001`
- `Rig1_Joints` / `Rig2_Joints` are valid `KeyframeSequence` instances
- `ScaleTracks` ModuleScript returns a table matching `DATA_FORMAT.md`
- Exporting twice with same name overwrites silently (confirmation dialog → Phase 6)

### Notes

- Pose hierarchy: `HumanoidRootPart` (identity) → `Torso` (RootJoint.Transform) → limbs
- Each limb `Pose.CFrame` = the captured CFrame for that joint (Neck→Head, shoulders→arms, hips→legs)
- `AuthoredHipHeight = 0`, `Loop = false`, `EasingStyle = Linear` per spec

---

## Phase 5 — In-game Playback ✅

Simultaneous playback of both rigs in a live game.

### Tasks

- [x] `MultiAnimPlayer.lua` ModuleScript (`game/`):
  - `play(sceneName, rigMap, propMap?)` — drives animation by setting `Motor6D.Transform` directly in a `RunService.Heartbeat` loop; scale + root CFrame + prop CFrames interpolated in the same loop
  - `stop()` — disconnects Heartbeat, fires `onFinished`
  - `onFinished(callback)` — single registered callback, fires on completion or stop
- [x] Auto-deployed to `ServerStorage.MultiAnimationData` by `Exporter.export()`
- [x] Test script: `tests/test_player.lua` (place in ServerScriptService, run in Play mode)

### Acceptance Criteria

- Both rigs animate simultaneously in play mode
- Joint poses match the viewport preview
- Scale changes lerp smoothly between keyframes
- `stop()` and `onFinished` work correctly

### Notes

- `AnimationClipProvider:RegisterKeyframeSequence` was removed from Roblox's server-side API; `MultiAnimPlayer` drives animation via direct `Motor6D.Transform` writes in a Heartbeat loop — the same mechanism `Animator` uses internally
- Joint poses, scale (`Part.Size`), root position (`HumanoidRootPart.CFrame`), and prop CFrames all interpolate in the same loop with `CFrame:Lerp` / `Vector3:Lerp`
- `onFinished` is single-callback (last registered wins); call before `play()` to avoid race
- Exporter clones `MultiAnimPlayer` from the plugin's `game` folder into `ServerStorage.MultiAnimationData` on every export so the game-side module is always up to date

---

## Phase 6 — Polish ✅

Session persistence, keyframe editing, rig workflow improvements.

### Tasks

- [x] Delete keyframe: right-click marker → removes that rig's keyframe at that frame only (`MouseButton2Click` → `Recorder:deleteRigKeyframe`)
- [x] Viewport selection sync: clicking any part of a rig in the Studio viewport selects only that rig in the plugin panel (`Selection.SelectionChanged` + ancestor walk)
- [x] Session save/load: `Save` and `Load` buttons persist session via `plugin:SetSetting` (CFrames as 12-number arrays, Vector3 as 3-number arrays)
- [x] Exclusive rig selection: rig buttons behave as radio buttons — clicking one deactivates all others; first rig alphabetically starts active on load
- [x] Double-click track lane: double-click anywhere on a rig's track area jumps the timeline to that frame position and records a keyframe for that rig (`track.InputBegan` double-click timer → `onTimelineDoubleClicked(rigName, frame)`)
- [x] Scrubber alignment: scrubber track inset by 56px (TrackLane label 52px + gap 4px) so thumb aligns vertically with keyframe dots
- [x] Auto-update keyframe on scrub departure: when drag starts at a frame that has keyframes, re-captures current pose for active rigs/props automatically (idempotent if nothing changed)
- [x] Whole-model movement (rootTrack): `HumanoidRootPart.CFrame` captured per frame in `rootTrack`; applied before joint transforms during scrub/preview so the whole rig moves; exported to `RootTracks` ModuleScript; interpolated in MultiAnimPlayer Heartbeat loop
- [x] Keyboard shortcuts (viewport-focused, ignored when TextBox active):
  - `K` — add/update keyframe for active rigs & props at current frame
  - `L` — step timeline forward by Step frames
  - `J` — step timeline back by Step frames
- [x] Step size textbox in CONTROLS (default 2): controls how many frames `J`/`L` advance the timeline
- [x] Shortcut legend label pinned to bottom of panel (`K  add/update KF   J  step ←   L  step →`)
- [x] `Pose.CFrame` API fix: Roblox renamed `Pose.Transform` → `Pose.CFrame`; fix applied in Exporter and MultiAnimPlayer
- [x] Session auto-save on every keyframe change — debounced 1s, saves to `_autosave` slot
- [x] "New Session" button with confirmation dialog (clears all keyframes, re-scans rigs)
- [x] Auto-detect rigs added/removed from FIGURES (`ChildAdded`/`ChildRemoved`)
- [x] Rest pose restore when preview stops — viewport syncs to current timeline frame on stop
- [x] Validate Motor6Ds before capture; surface clear error if rig is broken (`JointCapture.validate`)

---

## Phase 7 — Prop Animation ✅

Animate arbitrary `BasePart` objects (blocks, projectiles, props) on the same timeline as rigs. A prop's world-space `CFrame` is keyframed and interpolated, giving animators full control over position and rotation of any scene object.

**Design decisions:**
- Discovery: "Track Part" button — adds the currently viewport-selected `BasePart`
- Selection: multi-select toggles (independent of the exclusive rig selector)
- Naming: part must have a unique name; duplicates against rigs or other props rejected with warning
- Sub-parts: `MeshPart`, `SpecialMesh`, `ParticleEmitter` children follow parent CFrame automatically
- Dot colour: teal `#00CFCF` (`Color3.fromRGB(0, 207, 207)`) to distinguish prop lanes from rig lanes (yellow)
- Remove: × button removes from active list; recorded data kept in session until cleared
- Session persistence: props re-linked on load by recursive `workspace:FindFirstChild(name, true)`; if not found, data remains in recorder (for export) but no live link

### Tasks

- [x] `core/PropCapture` — `capture(part)` → `part.CFrame`; `apply(part, cf)` → `part.CFrame = cf`
- [x] `core/Recorder` — `session.props` table; `addKeyframe(frame, activeRigs, activeProps)` captures props via PropCapture; `getSortedPropFrames`, `getPropData`, `setPropData`, `deletePropKeyframe`
- [x] `core/Interpolator` — `getPropData(recorder, propName, frame)` → interpolated CFrame via `CFrame:Lerp()`; `getAllPropFrames(recorder, propNames)` for KF navigation
- [x] `core/PoseApplier` — `applyPropRecorded(propInstances, propCFrames)` (with ChangeHistoryService waypoints); `applyPropImmediate(propInstances, propCFrames)`
- [x] `core/Exporter` — `buildPropTracksSource(session)` writes `PropTracks` ModuleScript alongside `ScaleTracks` (omitted if no props)
- [x] `game/MultiAnimPlayer` — `propToKeyframes(propKFData, fps)`; `play(scene, rigMap, propMap?)` (propMap optional, backward compatible); prop CFrame:Lerp in existing Heartbeat loop
- [x] `ui/PropSelector` — "PROPS IN SCENE" section with "Track Part" button; per-prop toggle (teal when active) + × button; multi-select independent of rig radio buttons
- [x] Part validation on "Track Part": selection must be BasePart; name unique across allRigs + allProps
- [x] Prop track lanes — teal `TrackLane.new(parent, name, fc, order, PROP_COLOUR)`; double-click adds KF for prop; right-click deletes; left-click jumps timeline
- [x] "Add Keyframe" — `panel:getActiveProps()` returns `{[name]=BasePart}`; `recorder:addKeyframe(frame, activeRigs, activeProps)` captures both in one call
- [x] Session persistence — `serializeSession` includes `props` dict (CFrames as `{GetComponents()}` arrays); `applySessionData` restores prop data and re-links parts from workspace
- [x] `init.server.lua` — `allProps = {}`; `applyPosesAt` applies prop poses; `allKeyframesSorted` merges rig + prop frames; four new panel event handlers wired

### Acceptance Criteria

- ✅ "Track Part" button adds the selected part; its teal track lane appears in TIMELINE
- ✅ Name conflict (prop vs prop, or prop vs rig name) is rejected with a clear warning
- ✅ Double-click on prop lane and "Add Keyframe" both record the prop's current CFrame
- ✅ Scrubbing and Preview move the prop in the viewport
- ✅ Right-click teal dot deletes that prop's keyframe; × removes the prop lane (data retained)
- ✅ Export creates `PropTracks` ModuleScript in the scene folder (omitted if no props)
- ✅ In-game: `player.play("Scene_001", rigMap, { Block = workspace.Block })` animates the prop simultaneously with rigs
- ✅ `propMap` argument is optional; omitting it plays rigs only (backward compatible)

### Tests (`tests/`)

All 57 cases pass against live Studio via `mcp__Roblox_Studio__execute_luau`:

| File | Cases | Covers |
|------|-------|--------|
| `test_track_part.lua` | 8 | `Selection:Get()` accessible; BasePart check; name collision guards |
| `test_prop_core.lua` | 13 | PropCapture capture/apply/round-trip; Recorder prop CRUD; cross-prop isolation |
| `test_prop_interpolator.lua` | 13 | `getPropData` clamp low/high, exact, midpoint lerp, slerp rotation; `getAllPropFrames` merge |
| `test_prop_exporter.lua` | 14 | `buildPropTracksSource` → valid Lua → `require()` → fps/props/arrays correct; empty props omitted |
| `test_prop_serialization.lua` | 17 | `GetComponents()` round-trip; position/rotation/combined; `Lerp` α=0/0.5/1; slerp; serialize→lerp matches direct |
| `test_rig_root_motion.lua` | 15 | rootTrack capture/apply/interpolate; whole-model lift verified; Torso follows HRP; boundary clamp |
| `test_exporter.lua` | 23 | `Pose.CFrame` API (Roblox renamed from Transform); KFS structure & CFrames; RootTracks whole-model positions; empty rootTrack omitted |

### Notes

- `CFrame:GetComponents()` returns `(x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22)` — stored as-is in both JSON persistence and PropTracks ModuleScript; reconstructed with `CFrame.new(arr[1]…arr[12])`
- `CFrame:Lerp()` spherically interpolates rotation — correct for tumbling/spinning props
- Props live anywhere in the workspace; the plugin stores the part's `Name` only (not full path)
- Emitter rate, mesh scale, colour, transparency — out of scope; Phase 8 candidate

---

## Phase 8 — Camera Track & Cutscenes ✅

One camera track on the shared timeline; keyframes captured from the Studio
viewport camera; hard cuts and smooth moves; synchronized multiplayer playback.

**Design decisions (agreed 2026-06-11):**
- **Authoring — both methods:** primary flow is viewport capture (`C` shortcut
  records `workspace.CurrentCamera` CFrame + FOV at the current frame); a cone
  gizmo is also rendered per camera keyframe so shots are visible and grabbable
  in the scene (dragging a gizmo updates its keyframe).
- **Cut model:** single camera track. Each keyframe has `mode = "move" | "cut"`
  — move interpolates CFrame+FOV from the previous keyframe, cut jumps both.
- **FOV:** stored per keyframe, lerped on move, jumped on cut.
- **Playback:** all players synchronized. Server plays rig/prop animation
  (authoritative, replicates) and fires a RemoteEvent with the scene name and a
  `workspace:GetServerTimeNow()` start timestamp; each client drives its own
  `Scriptable` camera from the CameraTrack aligned to that timestamp.
  (Known caveat: rig motion reaches clients via replication ~50–100 ms behind
  the locally-computed camera — acceptable for v1.)
- **Edit-mode preview:** "Camera Preview" toggle slaves the Studio viewport
  camera (`workspace.CurrentCamera`) to the interpolated track during scrub and
  preview playback — author and review entire cutscenes without play mode.
  Viewport camera state is saved on toggle-on and restored on toggle-off.

### Tasks

- [x] `core/CameraCapture.lua` — `capture()` → `{cf, fov}` from viewport camera;
      `apply(cf, fov)` → write viewport camera (preview); save/restore camera state
- [x] `core/Recorder` — `session.camera.track[frame] = {cf, fov, mode}`;
      add/delete/get sorted frames; included in save/load serialization
- [x] `core/Interpolator` — `getCameraData(recorder, frame)` → `{cf, fov}` honouring
      cut (no interpolation across a cut keyframe) vs move (CFrame:Lerp + fov lerp)
- [x] `ui/Panel` — CAMERA section: "Camera Preview" toggle, "📷 Capture" button,
      per-keyframe cut/move toggle; camera track lane (orange dots)
- [x] `C` keyboard shortcut — capture camera keyframe at current frame
- [x] Gizmos — cone part per camera keyframe in `workspace.__MultiAnimCameraGizmos`
      (`Archivable = false` so they never save with the place; removed on unload);
      click gizmo → jump timeline to its frame; drag gizmo → update keyframe
- [x] `core/Exporter` — `CameraTrack` ModuleScript
      `{fps, frames = {[n] = {cf = {12 numbers}, fov = 70, cut = false}}}`;
      omitted when no camera keyframes
- [x] `game/CutsceneServer.lua` — `playCutscene(sceneName, rigMap, propMap?)`:
      plays anims via MultiAnimPlayer, fires `MultiAnimCutscene` RemoteEvent
      with `(sceneName, startServerTime)`
- [x] `game/CutsceneCamera.lua` — client module: on RemoteEvent, waits for the
      server timestamp, sets `CameraType.Scriptable`, drives CFrame+FOV per
      Heartbeat from CameraTrack, restores the player camera on finish/stop
- [x] TestBridge — camera commands (`captureCamera`, `getCameraFrames`,
      `setCameraMode`, `deleteCameraKeyframe`, `setCameraPreview`)
- [x] Tests — `test_camera_core.lua` (capture/apply/interpolate, cut vs move,
      FOV lerp), `test_camera_exporter.lua` (CameraTrack structure, omit-if-empty),
      `test_ui_camera.lua` (bridge-driven UI round-trip)
- [x] `mcp scene` — CameraTrack rides along automatically (it's a ModuleScript)

### Acceptance Criteria

- `C` captures the current viewport as a camera keyframe; orange dot + gizmo appear
- Scrubbing with Camera Preview ON flies the viewport through the track;
  cut keyframes jump, move keyframes glide; FOV animates
- Toggling Camera Preview OFF restores the exact pre-toggle viewport camera
- Dragging a gizmo updates that keyframe; right-click dot deletes it (gizmo too)
- Export writes `CameraTrack` (omitted when empty); `mcp scene pull` captures it
- In play mode, every connected client's camera plays the track in sync and is
  restored when the cutscene ends
- Gizmos never persist into the saved place and vanish on plugin unload

---

## Phase 9 — Future Backlog

- Multiple named cameras + switcher track (authoring sugar over Phase 8 cuts)
- Effect track — trigger ParticleEmitters / sounds at keyframes ("Add effect" TODO)
- "+ Add Rig" panel button (logic already proven by `mcp addrig`)
- Auto-capture on transform change
- Per-keyframe easing curve selector
- R15 rig support
- Audio track sync
- Upload to Roblox asset catalogue
- Onion-skin ghost rendering
- Copy/paste keyframe between rigs (mirror pose)
- Prop property animation (emitter rate, transparency, colour)
