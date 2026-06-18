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
| 9 | Quality of Life | 🔄 In Progress |

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

## Phase 9 — Quality of Life 🔄

### Completed

- [x] **"+ Rig" panel button** — clones Rig1 (or the first tracked rig) into
      FIGURES under the next free `RigN` name, offset +5 studs per existing
      rig, with canonical Motor6D connections restored on the clone (the
      source's are nil'd by the plugin session); FIGURES auto-detect takes it
      from there. Also exposed as the `addRig` TestBridge command.
- [x] **Keyframe clipboard (copy / paste / paste-mirrored)** — CONTROLS row:
      `Copy KF` copies the active rig's keyframe (joints + scales) at the
      current frame; `Paste KF` writes it onto the active rig at the current
      frame; `Paste Mirrored` swaps left↔right joints/parts and reflects each
      transform across the rig's YZ plane
      (`CFrame.new(-x,y,z, r00,-r01,-r02, -r10,r11,r12, -r20,r21,r22)` —
      determinant stays +1). Pose only: the target rig keeps its own world
      position (rootTrack is not copied). A label shows the clipboard source
      (`Rig1 @ 12`). Bridge commands: `copyKeyframe`, `pasteKeyframe`,
      `getClipboard`, `getJointCF`, `setJointCF`.
- [x] Tests — `test_mirror_core.lua` (17: reflection math, involution,
      determinant, name-map round-trips) and `test_ui_rigtools.lua` (20: live
      add-rig + auto-detect, copy/paste/mirror through the bridge, full part-
      CFrame snapshot/restore hygiene). Suite total: **250 cases**.
- [x] **Effect track** — one-shot events (ParticleEmitter emit/on/off, Sound
      play/stop, Light/Beam/Trail/Highlight on/off) placed at any keyframe and
      fired when playback crosses that frame.  Action is cycled per-effect with
      the `Track Effect` button → purple chip (click=cycle, ×=untrack) + purple
      lane in the timeline.  Exported as `EffectTracks` ModuleScript alongside
      the scene; loaded and fired by `MultiAnimPlayer` in the Heartbeat loop via
      a crossing-pointer so events fire exactly once.  Instance path resolved
      from `fx.target` dotted string at runtime (walks from `game`).  New
      modules: `EffectRunner` (classify / fire / cycleAction), extended
      `Recorder` (effect CRUD), extended `Panel` (FX row + purple lanes),
      extended `Exporter` (EffectTracks builder), extended `MultiAnimPlayer`
      (load + fire).  Bridge commands: `trackEffect`, `getEffects`,
      `getEffectInfo`, `cycleEffectAction`, `addEffectEvent`, `getEffectFrames`,
      `getEffectEvent`, `deleteEffectEvent`, `untrackEffect`, `fireEffect`.
- [x] Tests — `test_effect_core.lua` (24: classify, cycleAction, live fire,
      crossing-pointer), `test_effect_exporter.lua` (13: source builder, loadstring
      round-trip, omit-if-empty), `test_ui_effects.lua` (18: full bridge
      integration — track, cycle, add/read/delete events, live fire, untrack).
      Suite total: **306 cases** across 18 files.
- [x] **Simple Mode** — a second panel layout (toggle button above RIGS IN
      SCENE) for quick, no-fuss capture: no rig/prop selection, no manual
      "Add Keyframe". Everything under `Workspace.FIGURES` (rigs and any other
      part/model) is auto-tracked. Workflow is pose → press `►` → the
      departure frame is captured automatically *only if it was still empty*
      (idempotent — stepping across already-keyframed frames never
      overwrites), then the timeline advances and the new frame's pose (if
      any) is applied. **Delete Keyframe** clears the current frame and snaps
      the pose back to the previous frame without moving the cursor — the
      redo loop (re-pose, step again, recaptured fresh). A **Camera View**
      toggle extends the same capture-on-step rule to the viewport camera.
      Switching Simple ↔ Advanced never touches session data. New modules/
      changes: `Panel.lua` (mode toggle, Simple section, `_applyModeVisibility`),
      `init.server.lua` (`doSimpleScan`, `simpleFrameHasData`,
      `doSimpleCaptureFrame`, `doSimpleStepForward`, `doSimpleDeleteKeyframe`,
      FIGURES auto-track/untrack of non-rig children while in Simple mode).
      Bridge commands: `getMode`, `setMode`, `simpleStepForward`,
      `simpleDeleteKeyframe`, `setSimpleCamera`, `simpleFrameHasData`,
      `getSimpleProps`.
- [x] **💾 Save button** — quick-save to the current scene name with no
      dialog or overwrite confirmation, in both Advanced and Simple panels;
      complements `_autosave` and the existing named `Save As`/`Load` flow.
- [x] **Simple Mode refinement — Play/Stop + manipulable camera object.**
      A **▶ Play / ■ Stop** toggle plays the recorded animation forward from
      the current frame to the end (reuses the Advanced-mode playback engine
      and `ePreview`/`eStop` events — no new engine). Camera View no longer
      captures the ambient, unmoving viewport camera; toggling it on creates
      a persistent `SimpleCamera` part in `FIGURES` that's posed with
      Studio's normal move/rotate tools just like a rig or prop, with its own
      FOV box. A separate **Look Through** toggle slaves the edit viewport to
      the camera part live (`RunService.Heartbeat` mirror via
      `CameraCapture.apply`) and restores the original viewport exactly on
      toggle-off (`CameraCapture.saveState`/`restoreState`). The camera
      object is excluded from generic prop auto-tracking and captured via
      `PoseApplier.applyPropImmediate`/`applyPropRecorded` like a one-entry
      prop table; the exported `CameraTrack` data shape is unchanged, so
      export and in-game cutscene playback need no changes. New:
      `ensureSimpleCameraPart`, `setSimpleCameraOn`, `setSimpleLookThroughOn`
      in `init.server.lua`; FOV box + Look Through button in `Panel.lua`.
      Bridge commands: `isPlaying`, `simpleTogglePlay`, `setSimpleLookThrough`,
      `getSimpleLookThrough`, `setSimpleCameraFOV`, `getSimpleCameraInfo`.
- [x] **Simple Mode refinement #2 — layout + FOV-frustum gizmo + free-fly
      Look Through.** ▶/■ Play moved into the Delete Keyframe row (was its
      own row, now also 2.5× wider via `widenButton`) so the two most-used
      Simple buttons sit together and Play is easy to hit. The SimpleCamera
      part's visual marker (a Hinge-surface stud) is replaced with a
      `FOVFrustum` Folder of 8 thin Neon Parts (apex-to-corner edges + far
      rectangle, sized from the live FOV, `drawSimpleCameraFrustum`/
      `addFrustumEdge`, redrawn on FOV change/keyframe apply), each rigidly
      welded to the camera part via `WeldConstraint` — so aim direction and
      field of view are visible at a glance and the outline reliably follows
      the part through Studio's drag tool *and* scripted CFrame writes
      (scrubbing/playback/Look Through), via the same assembly mechanics
      already relied on for Motor6D rigid welds elsewhere in this file.
      (First attempt used a `WireframeHandleAdornment`, which `screen_capture`
      can't render at all — confirmed with isolated test parts — and whose
      `Adornee` did not visually track the part in live Studio either; the
      Part+weld approach renders unconditionally and was visually confirmed
      via `screen_capture` to follow the camera through an arbitrary
      move+rotate.) Look Through now allows free navigation while active: a
      one-time snap (gizmo → viewport) on toggle-on, then a reversed one-way
      Heartbeat mirror (viewport → gizmo) for as long as it stays on, so
      Studio's native edit-camera controls (right-drag look, WASD/QE fly,
      scroll zoom) drive the viewport as normal and re-aim the gizmo to
      match — previously the gizmo's CFrame was forced onto the viewport
      every tick, which fought any attempt to navigate while looking
      through. FOV still flows gizmo/FOV-box → viewport one-way. Toggle-off
      still restores the original pre-toggle viewport exactly
      (`CameraCapture.saveState`/`restoreState`, unchanged). New bridge
      command: `getSimpleCameraFrustumInfo` (edge count + per-edge
      `WeldConstraint` check, since there's no line-count-style getter for
      Part geometry either).
- [x] **Simple Mode frame management redesign — Add / Insert / Delete Frame.**
      Replaced the idempotent "step-forward" and "delete-keyframe" semantics
      with three explicit operations: **Add Frame** always captures the current
      pose, grows `frameCount` by 1, and moves the cursor to the new end frame
      (returns `oldCount + 1`); **Insert Frame** shifts all data at frames ≥
      current+1 right by 1, grows `frameCount` by 1, cursor stays on the now-
      blank current frame; **Delete Frame** removes data at the current frame,
      shifts all subsequent data left by 1, shrinks `frameCount` by 1 (minimum
      1), cursor = min(current, newCount). The panel row is now
      `Del Frame | + Insert | ▶ Play (wide) | + Add Frame`. Old bridge names
      `simpleStepForward` / `simpleDeleteKeyframe` are kept as legacy aliases
      pointing at the new functions so existing saves/scripts aren't broken.
      `init.server.lua` now saves the Advanced-mode `frameCount` in
      `advancedFrameCount` before entering Simple Mode (restored on exit) so a
      `doSimpleScan` that finds no keyframes and resets `frameCount=1` doesn't
      contaminate subsequent Advanced-mode test runs. Bridge commands:
      `simpleAddFrame`, `simpleInsertFrame`, `simpleDeleteFrame` (plus legacy
      aliases above).
- [x] Tests — `test_ui_simple.lua` (49: mode toggle, Add/Insert/Delete Frame
      management, Camera View capture-on-add, Play/Stop toggle, manipulable
      camera object — creation, FOV round-trip, frustum gizmo edge count/weld
      check, Look Through guard/snap/free-fly-mirrors-to-gizmo/exact
      restore, capture-from-gizmo — FIGURES auto-track/untrack). Suite total:
      **355 cases** across 19 files.
- [x] **Simple Mode bug-fix pass.**
  - **Look Through toggle stuck on:** `panel.onSimpleLookThroughToggled` now always calls
    `panel:setSimpleLookThroughState(result)` — previously only called when result differed
    from the requested state, so `self._simpleLookOn` was never set to `true` and every
    button click fired `eSimpleLook:Fire(true)` rather than toggling off.
  - **Frame count inherits Advanced session size:** `doSimpleScan` now derives `frameCount`
    from the highest keyframed frame (`maxKF + 1`) instead of the stored session frame count,
    preventing a large Advanced-mode session from inflating the Simple Mode scrubber on entry.
  - **Camera View ON/OFF is now visually effective:** `setSimpleCameraOn` sets the Part's
    `Transparency = 0/1` and destroys/recreates the `FOVFrustum` folder on toggle. `doSimpleScan`
    hides an existing Part on load when Camera View is OFF. `applyPosesAt` and `onSimpleFOVChanged`
    now guard frustum redraws behind `simpleCameraOn`.
  - **`doSimpleAddFrame` only grows the timeline when at the blank end frame:** if the cursor
    is at an existing frame, data is overwritten and the cursor advances by 1 without growing
    `frameCount` — previously navigating back and pressing Add Frame created a phantom gap in the
    icon strip.
  - **"Part Edge not parented" log warning fixed:** `drawSimpleCameraFrustum` now parents the
    `FOVFrustum` Folder to the camera Part *before* adding edge Parts, so WeldConstraint
    geometry resolution happens in Workspace context from the start.

### Backlog

- Multiple named cameras + switcher track (authoring sugar over Phase 8 cuts)
- Auto-capture on transform change
- Per-keyframe easing curve selector
- R15 rig support
- Audio track sync
- Upload to Roblox asset catalogue
- Onion-skin ghost rendering
- Prop property animation (emitter rate, transparency, colour)
