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
| 9 | Quality of Life | ✅ Complete |
| 10 | Playback Tab + Player Rig Substitution | ✅ Complete |

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

## Phase 9 — Quality of Life ✅

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

- [x] **Simple Mode auto-capture on navigation + Playback FPS box.**
  - **Pose changes no longer lost on frame-icon navigation:** `panel.onFrameChanged`
    now calls `doSimpleCaptureFrame(departureFrame)` before jumping when `not simpleScrubbing`
    and the departure frame already has data. Scrubber drag is handled by `panel.onScrubBegan`
    (sets `simpleScrubbing = true`, captures departure frame once) so intermediate drag frames
    are not over-captured.
  - **Playback FPS box in Simple nav row:** a `textBox("30")` next to the total-frames box
    lets the user set playback speed (1–999 fps). `panel.onSimpleFPSChanged` fires on
    `FocusLost`; `init.server.lua` forwards to `timeline:setFps` + `recorder:setFps`. Fresh
    sessions default to 30 fps; existing sessions restore their saved fps via
    `panel:setSimpleFPSDisplay` at the end of `doSimpleScan`.
  - **New TestBridge commands:** `getSimpleFPS`, `setSimpleFPS {fps}`, `simpleNavigate {frame}`
    (simulates icon click with auto-capture logic).
  - **10 new test cases** in `test_ui_simple.lua` (suite: 365 cases across 19 files).

- [x] **Phase 10 — Playback Tab + Player Rig Substitution (complete).**
  - **Third "Playback" tab** in the plugin panel alongside Simple/Advanced, with:
    - Scene selector (◄/► cycle through saved sessions)
    - Per-rig mapping rows: Fixed / LocalPlayer clone / LocalPlayer direct / UserId clone / UserId direct
    - FPS box, Loop toggle, Movie Mode toggle
    - Multi-line Lua snippet `TextBox` (read-only display) that updates live as params change
    - Copy Snippet button (prints to Output) + Preview button
  - **Four new `game/` runtime modules** for in-game playback:
    - `LetterboxGui.lua` — client-side cinematic black bars (top/bottom 10%, DisplayOrder 200)
    - `PlayerRigProxy.lua` — resolves player entries into R6 or R15 rig models; clone mode
      (clones character locally, hides original, strips scripts/Humanoid, teardown destroys
      clone + restores original); direct mode (PlatformStand=true, teardown restores);
      `resolveAll` for batch resolution with combined teardown
    - `MultiAnimDataServer.lua` — server-side `MultiAnimGetScene` RemoteFunction; parses KFS
      instances + ScaleTracks/PropTracks/RootTracks/CameraTrack/EffectTracks ModuleScripts from
      `ServerStorage.MultiAnimationData` into a serializable table; call `setup()` from a
      Script in ServerScriptService
    - `CutscenePlayer.lua` — client-side LocalScript module; `play(sceneName, rigMap, opts)`
      returns a `handle.stop()`; Heartbeat loop drives Motor6D.Transform (joints), HRP.CFrame
      (root track), Part.Size (scale), workspace.CurrentCamera (camera track); supports
      FPS override, loop, movie mode letterbox; teardown restores camera type
  - **Snippet generation:** `buildPlaybackSnippet()` builds a Lua string from current scene +
    rig modes + FPS/loop/movieMode — updated live on any param change
  - **New TestBridge commands:** `setPlaybackMode`, `getPlaybackMode`, `refreshPlaybackScenes`,
    `setPlaybackScene`, `getPlaybackScene`, `setPlaybackRigMode`, `getPlaybackRigModes`,
    `setPlaybackParams`, `getPlaybackParams`, `getPlaybackSnippet`; also `setMode` extended to
    handle `"playback"` case (calls `doPlaybackScan`)
  - **99 new test cases** across 2 new test files:
    - `test_player_rig_proxy.lua` — 48 cases: module loads, fixed pass-through, nil/bad entry,
      R6 detection, savePartStates/restore round-trip, clone mode (name/parent/Humanoid/HRP/hide/
      teardown), direct mode (PlatformStand/teardown), R15 rejection, resolveAll mix, idempotent
      teardown, destroyed-character teardown, anchor CFs, findPlayerByUserId in edit mode
    - `test_ui_playback.lua` — 51 cases: mode switch, scene list, scene selection, rig mode
      cycling (all 5 modes), FPS/Loop/MovieMode round-trips + clamping, getPlaybackParams,
      snippet contains scene name + CutscenePlayer + workspace.FIGURES/LocalPlayer/userId/
      mode strings + loop/movieMode/fps values, multi-rig snippet, partial param update
      preservation, mode persistence
  - **Suite total: 464 cases across 21 files, all passing.**

- [x] **Phase 10 bug-fix pass: frameCount invariant + test regression guards.**
  - **Root cause:** entering Playback mode did not save `advancedFrameCount` (unlike Simple
    mode), so switching back to Advanced left the timeline at the small synthetic frameCount
    from `doSimpleScan` or `doPlaybackScan`. Autosave could also fire while in Simple mode
    and persist that small count, causing `doLoad` to start with e.g. 2 frames on the next
    plugin load. This broke `test_ui_bridge` (setFrame 7 clamped to 2), `test_ui_camera`
    (PARK_A negative → crash at `kfA.result.cf`), and `test_ui_simple` timing tests (animation
    too short for 0.1 s mid-play window).
  - **Fix 1:** All three Playback entry points (`onModeChanged`, `setMode` bridge cmd,
    `setPlaybackMode` bridge cmd) now save `advancedFrameCount = timeline:getFrameCount()`
    when entering, mirroring the existing Simple mode pattern.
  - **Fix 2:** `serializeSession()` uses `advancedFrameCount or session.frameCount`, so
    autosaves in Simple/Playback mode never persist the small synthetic count.
  - **Fix 3:** `doLoad` clamps `frameCount` to `math.max(data.frameCount, 20)` as a safety
    floor against corrupt saves.
  - **Fix 4:** `test_ui_playback` cleanup always restores to "advanced" (not just if
    `origMode ~= "playback"`), preventing stale mode state from leaking into subsequent tests.
  - **2 new regression tests:** `test_ui_simple.lua` (+1, 60 total) and `test_ui_playback.lua`
    (+1, 52 total) each verify that `frameCount` survives a full round-trip through their
    respective non-advanced mode. **Suite total: 466 cases across 21 files, all passing.**

- [x] **Simple Mode UX pass — slot-mapped scrubber, Look Through free-fly fix, onion skin.**
  - **Slot-mapped icon strip:** `Panel:setSimpleSlots(sortedFrames)` replaces the old
    `rebuildSimpleFrameIcons` + `setSimpleIconWidth` pair. Icons are packed consecutively
    (no gaps between sparse frame numbers); scrubber width = keyframe count, not total
    frameCount. `_simpleSlotFrames[i]` and `_simpleFrameToSlot[frame]` lookup tables
    translate slot positions ↔ actual frame numbers throughout `onFrameChanged` and
    `setFrameDisplay`. All call sites updated to `panel:setSimpleSlots(getSimpleKeyframedFrames())`.
  - **Look Through free-fly fix:** removed `workspace.CurrentCamera.CameraType =
    Enum.CameraType.Scriptable` from `setSimpleLookThroughOn`. Setting `Scriptable` in edit
    mode blocks Studio's built-in editor camera controls (right-click drag, WASD, scroll).
    With the line removed, Studio drives the viewport normally; the Heartbeat still copies
    `Camera.CFrame → simpleCameraPart` each tick.
  - **Onion skin toggle:** new "Onion Skin: OFF/ON" button (column 5 of the camera row).
    `setSimpleOnionOn(isOn)` creates/destroys `workspace.__MultiAnimOnionSkin` (Archivable=false)
    containing semi-transparent ghost Parts for the previous keyframe (red, 0.65 opacity)
    and next keyframe (blue, 0.65 opacity). Ghost world CFrames are computed by
    `JointCapture.computeWorldCFrames(rig, jointData)` — pure FK traversal of `APPLY_ORDER`
    that writes to a local table without touching any real rig BaseParts. Panel: new
    `setSimpleOnionState(isOn)` method and `onSimpleOnionToggled` event. Bridge commands:
    `setSimpleOnion {on}`, `getSimpleOnion`.
  - **9 new test cases:** `test_joint_capture.lua` +3 (inline FK chain, no module import),
    `test_ui_simple.lua` +6 (onion skin toggle on/off, folder/ghost lifecycle, frame-change
    refresh, cleanup). **Suite total: 475 cases across 21 files, all passing.**

- [x] **Per-keyframe easing curve selector.**
  - **Easing stored per segment:** easing at frame F controls the interpolation from F to F+1.
    6 styles: Linear (default), EaseIn (cubic in), EaseOut (cubic out), EaseInOut,
    Constant (hold-until-next), Bounce.
  - **Recorder:** `easingTrack[frame]` on each rig and prop; inline `.easing` field on camera
    keyframe records; `getEasing/setEasing`, `getPropEasing/setPropEasing`,
    `getCameraEasing/setCameraEasing`. All shift/delete/clear operations include easingTrack.
  - **Interpolator (plugin):** `easedAlpha(t, easing)` via `TweenService:GetValue`; applied in
    all 5 getters (joints, scale, root, prop, camera).
  - **MultiAnimPlayer + CutsceneCamera (game):** pure-math `easedAlpha` (no TweenService);
    `toSortedKFs` accepts optional parallel `easingsTable` parameter (nil → all Linear for
    backward compat); `parseKFS` reads `Pose.EasingStyle`/`EasingDirection` → easing string.
  - **Exporter:** KFS Pose `EasingStyle`/`EasingDirection` set from per-frame easing;
    scale/root/prop tracks use a parallel `easings` table alongside the existing `rigs`/`props`
    data (omitted entirely when all Linear — backward compat); camera KF records gain an inline
    `easing` field alongside `cf`/`fov`/`cut`.
  - **Panel — Advanced mode:** right-click on any keyframe dot (rig/prop/camera/effect) shows
    a context menu with 6 easing options + Delete. Full-screen transparent overlay intercepts
    outside clicks to dismiss.
  - **Panel — Simple mode:** "Ease: Linear" button (column 5 of action row) opens the same
    easing-only menu. Frame navigation auto-syncs the button to the stored easing of the
    current keyframe. `panel:setSimpleEasingDisplay(easing)` method.
  - **init.server.lua:** `simpleCurrentEasing` variable; stamped onto all tracks at
    `doSimpleCaptureFrame`; `panel.onMarkerEasingChanged` / `panel.onSimpleEasingChanged`
    handlers; serialization + deserialization (backward compat: old saves load as Linear).
  - **Bridge commands:** `setEasing`, `getEasing`, `setPropEasing`, `getPropEasing`,
    `setCameraEasing`, `getCameraEasing`, `setSimpleEasing`, `getSimpleEasing`.
  - **Tests:** `test_easing_core.lua` (20 cases, headless), `test_ui_easing.lua` (23 cases,
    live Studio). **Suite total: ~507 cases across 23 files.**

- ✅ **Bug fix — Simple Mode load drops frame slots:** `panel.onLoadNamedRequested`
  was not calling `doSimpleScan()` after `applySessionData`, so the slot list UI was
  never rebuilt from the loaded keyframe data. Fix: call `doSimpleScan()` when
  `mode == "simple"` in the load handler (and duplicate in the `loadSession` bridge
  command). Bridge cmds added: `saveSession {name}`, `loadSession {name}`,
  `getSimpleSlots`. **5 new regression cases in `test_ui_simple.lua` (71 total).
  Suite: ~512 cases across 23 files.**

- ✅ **Tag-based scene organisation:** Multiple animations can share rigs without
  duplication. Tag format: `MAnim:<sceneName>` via CollectionService. Simple Mode
  gets a "Tag all in" row: folder dropdown (first-level workspace Folders/Models),
  Rigs/Props/Effects checkboxes (Rigs+Props default ON), "Clear scene tags" button.
  Selecting a folder from the dropdown immediately tags qualifying instances and
  rescans. `doSimpleScan` uses `RigScanner.scanByTag(scene)` when scene name is
  non-empty; falls back to legacy FIGURES scan when empty. New `RigScanner` exports:
  `isR6`, `scanByTag`, `getWorkspaceFolders`. Bridge cmds: `setSimpleSceneName`,
  `tagFolder {folder, types}`, `clearSceneTags`, `getSceneTagged`, `getWorkspaceFolders`.
  **New test file `test_tag_scene.lua` (15 cases). Suite: ~527 cases, 24 files.**

- ✅ **Bug fix — Motor6D disconnected in play mode, animation invisible:** The plugin
  sets `motor.Part0 = nil` for all R6 joints in edit mode (free-pose mode). When the
  user enters play mode (F5), Roblox copies this state into the simulation — joints
  remain disconnected, so `Motor6D.Transform` writes by `MultiAnimPlayer` and
  `CutscenePlayer` have no visual effect. Fix: `MultiAnimPlayer.findJoints` and
  `CutscenePlayer.buildJointMap` reconnect motors via `motor.Part0 = motor.Parent`
  on discovery.

- ✅ **R15 / dynamic rig support:** All joint operations now use dynamic Motor6D
  discovery instead of hardcoded R6 tables. `JointCapture.discoverMotors(rig)` filters
  by: `motor.Parent.Parent == rig AND motor.Part1.Parent == rig` — captures all
  canonical rig joints for R6 (6), R15 (15), and custom rigs while excluding
  accessory welds (Handle is inside an Accessory model, not a direct child).
  `buildApplyOrder` gives topological FK ordering for both rig types.
  `MultiAnimPlayer.findJoints`, `CutscenePlayer.buildJointMap` (pre-built at setup),
  and `JointCapture` all use the same discovery path. `PlayerRigProxy` now accepts
  R15 characters. `RigScanner` adds `isR15()` and `isAnimatableRig()` predicates;
  `scan()` / `scanByTag()` include R15 rigs. KFS export changed to flat format
  (motor-name Poses under HumanoidRootPart); `parseKFS` handles legacy R6 hierarchy
  for backward compat. **New test file `test_r15_joints.lua` (21 cases). Suite:
  ~548 cases, 25 files.**

- ✅ **Tag UX improvements + bugfixes:**
  - **Tag row repositioned** to the top of Simple Mode (LayoutOrder 1) for immediate
    access on panel open.
  - **Toggle button fix:** Rigs/Props/Effects toggles rebuilt as standalone
    TextButtons — the original `btn()`-wrapper caused a double MouseLeave handler that
    overwrote the active colour. Now visually correct on load (Rigs ON, Props ON,
    Effects OFF by default) and toggle cleanly on click.
  - **`doSimpleScan` forward declaration:** `doTagAllIn` and `doClearSceneTags` called
    `doSimpleScan()` before its `local function` definition — fixed with `local
    doSimpleScan` forward ref + `doSimpleScan = function()` assignment.
  - **"New" button** (next to Load): auto-increments scene name, shows confirm overlay
    with tagged instance + keyframe counts, then clears tags + full session + rescans.
  - **"Clear scene tags" confirm overlay:** shows counts before removing tags.
  - **"Manual tag" hint:** live-updating label `Manual tag: MAnim:Scene_001` to the
    right of "Clear scene tags".
  - **`panel:showTagConfirm(header, msg, onOkay)`:** generic confirm overlay reused by
    both actions. Counts via `getTagCounts()` + `getKeyframeCount()` helpers in
    init.server.lua.
  - **Lua 200-register fix:** `Panel.new` exceeded Lua 5.1's 200-local-register limit.
    Fixed by wrapping Simple Mode, Overlays, and Playback Tab in `do...end` blocks —
    compiler reuses registers freed by each closed block.
  - **`test_exporter.lua`** extended with 13 new flat-KFS-format cases (total 36).
    **Suite: ~561 cases, 25 files.**

- ✅ **Post-Phase-10 bug fixes and polish:**
  - **`parseKFS` flat format support in `MultiAnimDataServer`:** handles both flat format
    (motor names as direct children of HumanoidRootPart) and legacy R6 hierarchy (Torso
    child present). Auto-detected; no caller change needed.
  - **Server-side Motor6D reconnect:** `MultiAnimDataServer.setup()` now walks all
    `workspace` descendants on the server at game start and reconnects any `Motor6D`
    where `Part0 == nil` (left nil by the plugin). Server replicates connected motors to
    clients — more reliable than the previous Heartbeat-based attempt.
  - **Source rig hiding via CollectionService tags:** `CutscenePlayer.play()` uses
    `CollectionService:GetTagged("MAnim:" .. sceneName)` instead of `workspace.FIGURES`
    to find source rigs. Rigs whose slot is played by a clone/player rig are hidden
    (Transparency=1) for the duration and restored on teardown.
  - **`PlayerRigProxy` clone nil fix:** `character.Archivable = true` before
    `character:Clone()` — Roblox's default is `false` and `Clone()` silently returns nil
    without this. Reset to `false` after cloning.
  - **Session save/load of sceneName + tagFolder:** `serializeSession()` persists both
    fields; `applySessionData()` restores them. `loadNamed()` falls back to the slot
    name as scene name for old saves that predate the `sceneName` field.
  - **"Refresh tags" button:** left of "Clear scene tags". Additively tags new qualifying
    instances in the selected folder (idempotent). Also detects orphaned rig/prop tracks
    (recorded but missing from the folder) and shows an inform-only overlay.
  - **Snippet fps omitted from opts:** `buildPlaybackSnippet()` no longer includes `fps`
    in the generated opts table (comment instead). `CutscenePlayer` already reads fps
    from `sceneData.fps`; only `loop = true` / `movieMode = true` appear when set.
  - **hotpatch.py full coverage:** `PATCH_MAP` now covers all 7 `game/` modules:
    `MultiAnimPlayer`, `PlayerRigProxy`, `CutscenePlayer`, `MultiAnimDataServer`,
    `LetterboxGui`, `CutsceneServer`, `CutsceneCamera`.

- ✅ **UI refinements (post-Phase-10 polish round 2):**
  - **Selected frame highlight:** current frame icon turns light blue (`iconSel` colour)
    instead of the accent blue used for hover; preserved across marker rebuilds.
  - **Scene rename propagates tags:** `onSceneRenamed` fires on `FocusLost` of the scene
    name box; `init.server.lua` renames all `MAnim:<oldName>` CollectionService tags to
    `MAnim:<newName>` and rescans.
  - **Brighter overlay and hint text:** `muted` raised to RGB(170,170,170), overlay body
    text uses a new `ovText` constant RGB(205,205,205) — visible on the dark gray panel.
  - **Camera spawns near rigs:** `ensureSimpleCameraPart()` computes the average
    HumanoidRootPart position of all tracked rigs and places the camera there +
    Vector3(0,2,8); falls back to `CurrentCamera.CFrame.Position` if no rigs are tracked.
  - **Duplicate frame:** `+ Insert` renamed `Duplicate`. Captures the current frame,
    shifts subsequent frames right by 1, copies the current frame's data into the new
    frame+1, and navigates there. Old bridge name `simpleInsertFrame` preserved.
  - **Snippet uses actual exported rig names:** `refreshCurrentPlaybackScene()` reads
    `ServerStorage.MultiAnimationData.<scene>` for children with a `_Joints`
    `KeyframeSequence` and seeds `playbackRigModes` with their names; rig rows reflect
    the real animation cast instead of a blank list.
  - **Copy snippet below snippet box; Preview modal:** "📋 Copy Snippet" moved to its
    own row (LO 8) below the snippet `TextBox`. The `Preview` button now opens an
    in-panel modal overlay (`pbPreviewOv`) with the full snippet text and a `✕` close
    button — no more console print.
  - **Export warning:** yellow `TextLabel` below the scene selector; shown when the
    selected scene has no export in `ServerStorage.MultiAnimationData`; cleared when
    the export exists. Fires on scene change and on `refreshPlaybackScenes`.
  - **FPS removed from Playback tab:** `pbFPSBox` and "FPS:" label removed; params row
    has only Loop and Movie Mode toggles. `setPlaybackFPSDisplay` is a no-op. Bridge
    `setPlaybackParams` still accepts `fps` for test compatibility.

- ✅ **SpawnedEffects (Simple Mode particle bursts + Sound):**
  - **Effects button** added to Simple Mode action row (position 6).
  - **Effects overlay** — card at ZIndex 55, `AutomaticSize = Enum.AutomaticSize.Y`
    (separate `do...end` block to respect the 200-register limit): type cycle
    (Explosion / Smoke / Sound), `fxApplyTypeVisibility()` toggles particle rows vs
    Sound rows (UIListLayout skips `Visible=false` children). Particle inputs: Size,
    Color R/G/B, Count, Duration, Speed, Lifetime. Sound inputs: SoundId TextBox
    (`ClearTextOnFocus = false`), Volume, Max Distance. "Select Position" picker +
    coordinate label. Add / Cancel / Delete buttons. Delete hidden in create mode.
  - **`plugin/core/SpawnedEffectRunner.lua`** (new): `PRESETS` (Explosion: orange
    burst; Smoke: gray column; Sound: soundId/volume/maxDistance), `PROPS` ordered
    list (particle only), `buildParams`, `fire()` — Sound branch creates `Part` +
    `Sound`, calls `:Play()`, destroys on `Ended` or 30s fallback; particle branch
    creates `Part` + `ParticleEmitter`, `:Emit(count)`, `task.delay`-destroys.
  - **`game/SpawnedEffectRunner.lua`** (new): identical `fire()` including Sound
    branch; zero plugin dependencies; deployed via `Exporter.serverMods` and
    `clientMods`.
  - **Recorder CRUD:** `session.spawnedEffects` array + `_nextSpawnedEffectId`;
    `addSpawnedEffect`, `updateSpawnedEffect`, `deleteSpawnedEffect`, `getSpawnedEffects`,
    `getSpawnedEffectById`; `clearSession()` resets both.
  - **Position picking:** `plugin:Activate(true)` + `plugin:GetMouse().Button1Down`;
    calls `panel:setSpawnedFxPosition(pos)` on click.
  - **Gizmo spheres:** `workspace.__MultiAnimEffectGizmos` folder; Ball Part per effect
    (orange = Explosion, gray = Smoke, blue = Sound); `Selection.SelectionChanged` opens
    overlay in edit mode on gizmo click.
  - **Edit-mode preview:** fires immediately on "Add to Frame" / "Update".
  - **Session persistence:** `serializeSession` branches on effectType (Sound stores
    soundId/volume/maxDistance; particles store scalar set); `applySessionData`
    round-trips; gizmos recreated on restore.
  - **Export:** `buildSpawnedEffectsSource()` branches on effectType → `SpawnedEffects`
    ModuleScript in scene folder (omitted if empty). `SpawnedEffectRunner` added to
    `serverMods` and `clientMods`.
  - **In-game playback:** `MultiAnimPlayer.play()` and `CutscenePlayer.play()` both fire
    spawned effects via crossing-pointer pattern; Sound fires a Part+Sound at world pos.
  - **Tests:** `test_spawned_effects_core.lua` (64 cases — PRESETS incl. Sound,
    buildParams, Recorder CRUD incl. Sound type), `test_spawned_effects_exporter.lua`
    (62 cases — particle + Sound round-trip, mixed entries, inline builder updated).
    **Suite: 621 cases, 27 files.**

- ✅ **Test infrastructure — UI test isolation:** Added `scanFigures` TestBridge command that
  rescans `Workspace.FIGURES`, normalises `frameCount ≥ 120`, and sets `mode = "advanced"`.
  Called at the start of `test_ui_bridge`, `test_ui_camera`, `test_ui_easing`, and
  `test_ui_rigtools`. Prevents `frameCount = 1` bleed-through from Simple Mode (which resets
  the counter for empty sessions), which caused parking-frame arithmetic to go negative and
  all test frame operations to clamp to frame 1. Also rewrote `test_ui_easing.lua` from the
  old bridge protocol (`MultiAnimTestBridge`, plain-Lua returns) to the current JSON protocol
  (`__MultiAnimTestBridge`, `{ok,result}`); case count grew from 12 → 23.

- ✅ **Simple Mode refinements (post-SpawnedEffects):**
  - **"Add effect" button rename:** `simpleActionRow` button renamed from "Effects" → "Add effect".
  - **Delete scene dialog:** Red **Delete** button added at position 8 in `simpleSceneRow`
    (next to New). Opens a full-panel **Delete overlay** (mirrors Load overlay) listing all
    saved sessions. Clicking a session name shows a confirmation card: "Are you sure you want
    to delete `"<name>"`?" with red **Yes** and grey **No** buttons. Yes fires
    `onDeleteNamedRequested` → `deleteNamed()` removes the session from plugin settings +
    refreshes the Playback scene list. **Cancel** button added to the footer of both the
    Delete overlay and the Load overlay.
  - **Spawned effects fire during Simple Mode playback:** The `startPlayback` Heartbeat
    previously fired `EffectRunner` events (Effect Track system) but skipped spawned effects.
    Fixed: inner loop now also iterates `recorder:getSpawnedEffects()` and fires
    `SpawnedEffectRunner.fire()` for any effect whose `frame` falls in the crossing window
    `(lastEventFrame, intFrame]` — same crossing-pointer pattern used by the game-side player.
  - **`deleteSession` + `listSessions` TestBridge commands:** allow test isolation without
    polluting the saved-session index; `listSessions` returns a name array.
  - **`export.py`** — packages the plugin + game-side runtime scripts for distribution as
    ready-to-import `.rbxm` files (no Rojo, no git required for recipients).
    Outputs `export/MultiAnimation.rbxmx`, `export/ServerStorage_MultiAnimationData.rbxm`,
    `export/ReplicatedStorage.rbxm`, and `export/how-to-use.md`.
  - **`SHARE.md`** — documents distribution options (direct file share vs Creator Store).
  - **5 new test cases** in `test_ui_bridge.lua` (save / listSessions / deleteSession /
    verify-absent round-trip). **Suite: 626 cases, 27 files.**

- ✅ **In-game spawned effects via CutscenePlayer + PlayerRigProxy clone camera fix:**
  - **`MultiAnimDataServer.getSceneData()`** previously returned only `{fps, rigs, props,
    camera, effects}` — the `SpawnedEffects` ModuleScript was never read. Added `ok6/sfxData`
    pcall; `out.spawnedEffects = sfxData.effects or {}` now included in every response.
    Plain-table structure serialises cleanly over `RemoteFunction:InvokeServer()`.
  - **`CutscenePlayer.play()`** had no spawned effects handling. Added: require
    `SpawnedEffectRunner` from `selfModule.Parent` (ReplicatedStorage siblings); build sorted
    `spawnedFxEvents` list (time = `(frame-1)/fps`); crossing-pointer loop in Heartbeat using
    `lastSfxTime` upvalue; `lastSfxTime = -1` reset on loop.
  - **`Exporter.clientMods`** — added `"SpawnedEffectRunner"` so Export deploys it to
    ReplicatedStorage alongside CutscenePlayer (previously only in serverMods).
  - **`PlayerRigProxy` clone camera bug:** in clone mode the original character is hidden and
    anchored at the trigger zone, but `camera.CameraSubject` still pointed to the original's
    Humanoid — player saw empty space above the trigger zone, not the animation. Fix: at
    resolve time, set `camera.CameraSubject = clone.HumanoidRootPart`; teardown restores to
    `character.Humanoid` and force-unanchors `HumanoidRootPart`. After teardown, player sees
    their character correctly and physics resumes.
  - **7 new test cases** in `test_player_rig_proxy.lua` (camera subject set/restored, HRP
    force-unanchored, teardown-with-destroyed-character, sequential-clone correctness).
    **Suite: 669 cases, 27 files.**

- ✅ **Sound spawned effect type:**
  - `FX_TYPES` extended to `{ "Explosion", "Smoke", "Sound" }` in Panel.lua.
  - Overlay `AutomaticSize = Enum.AutomaticSize.Y`; `fxApplyTypeVisibility()` shows
    Sound rows (SoundId, Volume, MaxDistance) and hides particle rows when Sound is
    selected, and vice-versa.
  - `SpawnedEffectRunner.PRESETS.Sound`, `fire()` Sound branch: creates a transparent
    `Part` at world-pos, parents a `Sound`, sets `SoundId`/`Volume`/`RollOffMaxDistance`,
    calls `:Play()`. On `Ended` (or 30s fallback) destroys the Part.
  - `Exporter.buildSpawnedEffectsSource` and `init.server.lua serializeSession` both
    branch on `effectType == "Sound"` to emit/store only Sound fields (not size/color/etc).
  - Blue `(80,160,255)` gizmo sphere for Sound effects.
  - `test_spawned_effects_core.lua` +20 cases (Sound PRESETS, buildParams, Recorder CRUD).
  - `test_spawned_effects_exporter.lua` +15 cases (Sound round-trip, mixed entries).
  - **Suite: 669 cases, 27 files.**

- ✅ **CutscenePlayer robustness + prop animation + onComplete callback:**
  - **Prop animation missing:** `CutscenePlayer` only animated rigs; prop BaseParts
    (e.g. a tracked Ball) stayed at whatever pose the plugin scrubber was parked at
    when F5 was pressed — invisible if scrubbed to an underground frame. Fix: resolve
    prop instances via CollectionService tags (MAnim:<scene> tagged BaseParts) with
    workspace search fallback; animate each prop's CFrame in the Heartbeat from
    `sceneData.props`; include prop track end-time in duration calculation; reset
    props to frame-1 in `applyAtT0` when `resetOnEnd = true`.
  - **Camera stuck after cutscene:** `CameraType` was restored to a captured
    `prevCameraType` which could be `Scriptable` if multiple animations fired
    simultaneously (Touched fires per body part — no debounce). Additionally,
    Roblox's CameraModule re-initialised from the last cinematic CFrame (far from
    player), placing the camera at a large orbit distance. Fix: always restore to
    `Enum.CameraType.Custom`; snap `camera.CFrame` to `hrp.CFrame * CFrame.new(0,2,12)`
    before handing back to CameraModule so it starts from the correct position.
  - **Teardown on error:** any unhandled throw in the Heartbeat previously left clones
    alive, characters anchored, source rigs transparent, and camera in Scriptable mode.
    Fix: entire Heartbeat body wrapped in `pcall`; errors call `doTeardown()` and warn.
  - **PlayerRigProxy camera ordering:** CameraSubject was restored to character Humanoid
    AFTER `clone:Destroy()`, leaving a frame where CameraSubject pointed to a destroyed
    BasePart. Fix: restore CameraSubject BEFORE destroying the clone.
  - **`handle.onComplete` callback:** `CutscenePlayer.play()` handle now exposes
    `handle.onComplete(fn)`. Call after `play()` returns; fires once after full
    `doTeardown()` completes (natural end, stop(), or error). Intended use:
    debounce reset, follow-up actions. Example:
    ```lua
    local debounce = false
    part.Touched:Connect(function(hit)
        if debounce or hit.Parent ~= character then return end
        debounce = true
        local h = CutscenePlayer.play("scene1", rigMap, opts)
        h.onComplete(function() debounce = false end)
    end)
    ```
  - **Suite: 673 cases, 27 files.**

---

## Session File Transfer ✅

Transfers the editable session between PCs/projects without requiring dev tooling on the target machine.

### Implementation

- `init.server.lua`:
  - `panel.onFileExportRequested`: calls `serializeSession()`, `HttpService:JSONEncode`s it, writes to a `StringValue` in `ServerStorage.MultiAnimSessions`, selects it in Explorer.
  - `panel.onFileImportRequested`: reads the `StringValue` currently selected in Explorer via `SelectionService:Get()`, `JSONDecode`s it, calls `applySessionData(data)`, then runs `doRefreshTags()` or `doSimpleScan()` as appropriate for the current mode.
- `Panel.lua`: two new buttons **Export File** and **Import File** in a row below Save As / Load / New in the RIGS section.
- Session format is the same structure as `plugin:SetSetting` saves — no separate serialisation code needed.

### Acceptance criteria

- Clicking Export File creates `ServerStorage.MultiAnimSessions.<sceneName>` (StringValue) and selects it.
- Saving the StringValue as `.rbxm`, inserting in another project, selecting it, and clicking Import File restores all keyframe data, FPS, frameCount, scene name, and tag folder.
- Re-linking: rigs/props/effects matched by name; missing instances produce a warning, data preserved for export.
- Simple mode with scene+tag folder: Import triggers `doRefreshTags` so rigs are immediately available.

## Tag Folder & Playback Refinements ✅

Quality-of-life improvements to the tag-folder workflow and CutscenePlayer implicit rig resolution.

### Implementation

**Searchable folder picker (`Panel.lua` — `openTagFolderDropdown`):**
- Replaced the flat ctxMenu dropdown with a dedicated overlay: filter TextBox + ScrollingFrame.
- Typing filters the list in real time (case-insensitive substring). Up to 8 rows visible; scrollable beyond that.
- Click-outside (`fpOverlay` fullscreen dismiss button) closes the picker.

**Nested model scanning (`init.server.lua` — `doRefreshTags`):**
- Replaced `folder:GetChildren()` with `walkFolder(container)` recursive walk.
- Descends into `Model`/`Folder` containers that are not themselves rigs/props/effects.
- Stops recursion at the first rig/prop/effect found at each level, so rig sub-parts are never tagged separately.

**New objects confirm (`doRefreshTags` + `panel:showTagConfirm`):**
- New objects are collected without tagging; shown in a confirm overlay before applying.
- OK tags them and proceeds to scan + remap/orphan dialogs. Cancel skips tagging but still rescans.
- `showTagConfirm` gained an optional 4th `onCancel` callback to support this.

**Name remap dialog (`Panel.lua` — `showNameRemapDialog`, `Recorder.lua` — `renameRig`/`renameProp`):**
- When orphaned recorder tracks have at least one same-type candidate in the folder, shows a **Renamed Objects** overlay.
- Each row: old name label + cycling button stepping through same-type candidates + `(skip)`.
- Apply calls `recorder:renameRig` / `recorder:renameProp` (moves track data + rest poses in-place), then rescans and auto-saves.

**CutscenePlayer implicit rig resolution (`game/CutscenePlayer.lua`):**
- Tagged source rigs (`CollectionService:GetTagged("MAnim:<scene>")`) collected before the workspace rig loop so they serve as the auto-fallback.
- Fallback order for unmapped rigs: (1) `"RigPlayer"` → `LocalPlayer` clone, (2) tagged scene instance by name, (3) `workspace.FIGURES` child.
- `CutscenePlayer.play("MyScene")` with no rigMap animates a full multi-rig scene without any explicit mapping.

### Acceptance criteria

- Folder picker filter box narrows list as user types; selecting a row fires tag-all.
- Rigs/props nested inside sub-models of the animation folder are detected and tagged by Refresh Tags.
- Refresh Tags with new untagged objects shows confirm dialog; OK tags them; Cancel skips without data loss.
- Refresh Tags with renamed objects shows remap dialog; Apply moves recorder track data to new names; tracks survive the rename.
- `CutscenePlayer.play("Scene")` (no rigMap) works when scene contains `RigPlayer` + any other tagged rig.
- Explicit rigMap entries override implicit resolution.

### Backlog

- Multiple named cameras + switcher track (authoring sugar over Phase 8 cuts)
- Audio track sync
- Upload to Roblox asset catalogue
- Prop property animation (emitter rate, transparency, colour)
- SpawnedEffects list panel (browse/select all scene effects without clicking gizmos)

---

## Simple Mode Camera & Scene Name Refinements ✅

Bug-fixes and UX additions for the Simple Mode camera workflow, no-folder safety, and scene name handling.

### Implementation

**Camera erratic fix (`init.server.lua`):**
- Three auto-capture-on-navigation sites (`onFrameChanged`, `onScrubBegan`, `simpleNavigate` bridge)
  now guarded with `not simpleLookThroughOn`. While Look Through is active the viewport drives
  the `SimpleCamera` part — those movements are intentional flying, not poses — so skipping the
  capture prevents random viewport positions becoming camera keyframes.

**`Del Cam >=Here` button (`Panel.lua` + `init.server.lua`):**
- New `Del Cam >=Here` button added to the Simple Mode camera row (after Onion Skin).
- Fires `onSimpleCamDeleteFrom`. Handler collects all camera keyframes ≥ current frame, shows
  a confirm overlay (count + frame number), then calls `recorder:deleteCameraKeyframe(f)` +
  `panel:removeCameraKeyframeMarker(f)` for each.
- Implements C-11: a fixed frame-1 camera pose can persist without later keyframes overriding it.

**No-folder warning + Camera View state revert (`Panel.lua` + `init.server.lua`):**
- New `panel:showWarning(header, message)` method reuses the existing `tagConfOv` overlay with
  Cancel button hidden and no callback — pure notification.
- `ensureSimpleCameraPart()` calls `showWarning("No Animation Folder", ...)` and returns `nil`
  when `getActiveSimpleFolder()` returns nil. `setSimpleCameraOn(true)` reverts
  `simpleCameraOn = false` and calls `panel:setSimpleCameraState(false)` when `simpleCameraPart`
  is still nil after the call, so the toggle never shows "Camera View: ON" without a working part.
- Same pattern applied in `doAddRig`: shows a warning if no folder is configured in Simple Mode.
- `showTagConfirm` and the OK-button handler now explicitly restore `tagConfCancel.Visible = true`
  so Cancel always reappears after a warning (which hides it).

**No FIGURES fallback — production default (`init.server.lua` + `RigScanner.lua`):**
- `legacyFiguresName` module variable declared as `nil` (no default folder name assumed).
- `RigScanner.scan(nil)` scans `workspace:GetChildren()` directly (workspace top-level), no folder
  required.
- `getActiveSimpleFolder()` helper returns the configured tag-folder instance or `nil` — never falls
  back to FIGURES.
- `doAddRig`, `doSimpleScan`, and the `ChildAdded` watcher all guard with `legacyFiguresName and ...`
  before calling `workspace:FindFirstChild`.
- Test bridge `scanFigures` still sets `legacyFiguresName = "FIGURES"` (all existing tests unaffected);
  `setFiguresFolder` bridge updated to write `legacyFiguresName` instead of a local variable.

**Scene name sanitization (`Panel.lua`):**
- New `sanitizeSceneName(name)`: `name:gsub("[^%w_]", "_")` — replaces any non-alphanumeric /
  non-underscore character (spaces included) with `_`.
- Applied at three entry points: `simpleSceneBox.FocusLost`, Save As `_doSave`, and
  `self:setSimpleSceneName(name)`. Call sites in `init.server.lua` need no changes; the stored
  value is always sanitized.
- Scene name textbox width doubled from 80 px to 160 px for longer names.

- ✅ **SimpleCamera spawn & Look-Through bug fixes:**

**Camera spawns facing rigs from viewer's angle (`init.server.lua` — `ensureSimpleCameraPart`):**
- Old: `spawnPos = avgPos + Vector3.new(0, 2, 8)` (world +Z offset regardless of rig orientation),
  looked at `spawnPos - Vector3.new(0, 0, 8)` (wrong look direction when rigs aren't at Z=0);
  fallback used `CurrentCamera.CFrame.Position` (placed camera ON the viewer, not in scene).
- New: computes `dir` = vector from `avgPos` toward `viewCF.Position`, flattened to XZ plane;
  `spawnPos = avgPos + dir * 8 + Vector3.new(0, 2, 0)`; orientation via `CFrame.lookAt(spawnPos,
  avgPos + Vector3.new(0, 1, 0))` — gizmo faces rig chest height on creation. Fallback: no rigs →
  spawn 8 studs in front of the Studio viewport camera (not on top of it), using
  `viewCF.Position + viewCF.LookVector * 8` and `CFrame.lookAt(spawnPos, spawnPos + viewCF.LookVector)`.

**Look-Through 180° flip fix (`init.server.lua` — `setSimpleLookThroughOn`):**
- Root cause: `CameraCapture.restoreState` (called when Look Through turns OFF) restores
  `cam.Focus` to the original pre-Look-Through focus point. On the second Look Through activation,
  `CameraCapture.apply(simpleCameraPart.CFrame, fov)` sets `cam.CFrame` correctly but leaves
  `cam.Focus` at the old restored point. If that focus was behind the new camera position, Studio's
  camera controller re-derived camera angles from CFrame + Focus and flipped the view 180°.
- Fix: after `CameraCapture.apply`, also set
  `workspace.CurrentCamera.Focus = CFrame.new(partCF.Position + partCF.LookVector * 10)` —
  places Focus 10 studs in front of the gizmo's look direction, so Studio's angle computation
  always produces the same orientation as the Part's CFrame.

- ✅ **Recording-integrity review fixes (2026-07-03):**

**Frame shift desync (`Recorder.lua` — `shiftFrames` / `deleteFrameAt`):**
- Both skipped the `spawnedEffects` and `subtitles` tracks (which store their frame
  inside each entry, not as a table key), so Simple Mode Insert/Delete Frame silently
  desynced explosions/sounds/subtitles from the rig/prop/camera data.
- `shiftFrames` now rewrites `entry.frame` for both; `deleteFrameAt` removes spawned
  effects and the subtitle event at the deleted frame. `doSimpleDeleteFrame` destroys
  gizmos of spawned effects it removes.

**Prop pose loss on Simple Mode navigation (`init.server.lua`):**
- `snapshotRigParts`/`simpleIsDirty` compared only rig part CFrames; moving only a
  tracked prop at an empty frame was silently discarded on navigate. The arrival
  snapshot now includes prop CFrames.

**Guard visibility (`init.server.lua` — `simpleFrameHasAnyData`):**
- New wider predicate used by the Insert/Delete Frame guards so spawned-effect-only and
  subtitle-only frames count as data. The narrow `simpleFrameHasData` is retained for
  the auto-capture-on-navigate paths, which must NOT stamp rig keyframes onto such
  frames. Exposed on the TestBridge as `simpleFrameHasAnyData`.

**Undo re-weld protection (`init.server.lua`):**
- Studio Ctrl+Z could revert the `Motor6D.Part0 = nil` disconnection (it rides along
  with the next recorded waypoint), re-welding rigs mid-session. `OnUndo`/`OnRedo`
  listeners now re-assert the disconnection for all tracked rigs; pose changes stay
  undone/redone as the user intended.

**Dynamic scale capture (`ScaleCapture.lua`):**
- Replaced the hardcoded 7-part R6 list with all direct-child BaseParts of the rig
  Model (mirrors the Motor6D discovery filter) — R15 and custom rigs now get full
  scale tracks.

**Cleanup:** removed dead `Recorder:deleteKeyframe` (unused; missed rootTrack/easingTrack).
`test_easing_core.lua` now emits the standard `=== N passed, M failed ===` summary so
`run_tests.py` counts its 20 cases (previously reported 0/0).

---

## In-game playback pipeline review fixes (2026-07-12)

End-to-end review of author → export (Studio + file bundle) → in-game playback.

**File-export bundle was incomplete (`export.py`):**
- `ReplicatedStorage.rbxm` omitted `SpawnedEffectRunner` and `SubtitleGui` —
  `CutscenePlayer.play()` errored immediately (`require(nil)`) on any game
  installed from the bundle. `ServerStorage_MultiAnimationData.rbxm` omitted
  `CutsceneCamera`, silently breaking `CutsceneServer`'s camera publish.
  Both lists now match `Exporter`'s deploy lists exactly; `how-to-use.md`
  regenerated (six client modules, updated folder tree).

**CutscenePlayer never fired EffectTracks events (`game/CutscenePlayer.lua`):**
- `MultiAnimDataServer` sent `sceneData.effects` but the client ignored it —
  tracked particle/sound/light one-shots played in the editor and via server-side
  `MultiAnimPlayer` but not in the primary client path. Now resolved from the
  exported target path and fired via the crossing-window pattern.

**Easing dropped in the client path:**
- `MultiAnimDataServer` did not serialize easing (joints, scale, root, props,
  camera) and `CutscenePlayer` lerped linearly, so all authored easing played
  back linear in-game. Every keyframe entry now carries an `easing` string and
  `CutscenePlayer` applies the shared `easedAlpha` curve set. Old exports
  without easing fields fall back to linear.

**Camera cut semantics inverted (`game/CutscenePlayer.lua`):**
- The cut flag was checked on the *previous* keyframe, so the segment toward a
  cut interpolated (should hold) and the segment after a cut held (should
  interpolate). Now checks the next keyframe, matching `CutsceneCamera` and the
  editor preview.

**Playback duration truncated event-only tails (`game/CutscenePlayer.lua`):**
- `duration` ignored spawned effects, effect events, and subtitles, so anything
  scheduled after the last rig/prop/camera keyframe was cut off. All event
  tracks now extend the duration.

**New test:** `tests/test_cutscene_client_core.lua` (20 cases) — eased sampling,
Constant/missing-easing fallbacks, camera cut-hold/jump/resume, effect-event
flattening + crossing-window single-fire, duration tail coverage.

---

## Follow-up hardening (2026-07-12, same session)

**CutsceneServer path subtitles (`game/CutsceneServer.lua`, `game/CutsceneCamera.lua`):**
- The synchronized-multiplayer path broadcast only the camera track; scenes with
  subtitles showed none. `CutsceneServer.play` now also broadcasts
  `{fps, style, events}` from SubtitleTrack, and `CutsceneCamera` displays them
  stepped on the shared clock via ReplicatedStorage `SubtitleGui`. Natural
  completion now fires the `"__stop"` signal to clients (wrapper around
  `MultiAnimPlayer.onFinished`; register callbacks via `Cutscene.onFinished`).
  `publishCameraModule` replaces a stale ReplicatedStorage copy when the source
  differs (previously returned early, so updates never propagated).
- Documented caveat: effect tracks/spawned effects fire server-side in this
  path; `ParticleEmitter:Emit()` does not replicate, so bursts may be invisible
  to clients in live multiplayer — use the CutscenePlayer path for effects.

**run_tests.py output contract enforced:** a test file whose output lacks the
`=== N passed, M failed ===` summary line now reports FAIL instead of silently
counting 0/0.

**test_tag_scene flake fix:** the "FIGURES fallback scan" assertion retries the
mode-cycle up to 3× with 0.3 s waits — tag removal propagates asynchronously and
the first rescan occasionally saw stale state in full-suite runs.

---

## Part Handoff E2E manipulation test (2026-07-13)

Full authoring-to-playback test driven through the plugin's real code paths:
two cloned R6 rigs pass a crate prop (16 frames @ 10 fps, Simple Mode), with
spawned smoke, tracked-emitter sparkle, subtitle, camera cut + FOV change —
exported and verified in-game via CutscenePlayer. Fixes that came out of it:

**Static plugin shadowing devsync (`build.py`, `export.py`):**
- `build.py` rewrote `MultiAnimation.rbxmx` into the Plugins folder, silently
  re-enabling the static plugin that `devsync.py install` had disabled — Studio
  then ran stale code while devsync pushes went nowhere. `build.py` now writes
  `MultiAnimation.rbxmx.disabled` when the DevLoader is installed; `export.py`
  falls back to the `.disabled` file when packaging.

**`tagFolder` bridge half-configured the session (`init.server.lua`):**
- It tagged and scanned but never set `panel._tagFolderName` (the UI dropdown
  sets both), so Camera View / + Rig failed after bridge-driven setup. The
  bridge now calls `panel:setTagFolder` first.

**Empty-text subtitle events rendered an empty bar:**
- The only way to end a subtitle is an empty-text event, but `""` is truthy in
  Lua — editor preview, `CutscenePlayer`, and `CutsceneCamera` all showed a
  blank background bar instead of hiding. All three now treat `""` as a clear
  marker; `Recorder:getActiveSubtitleAt` returns nil for it.
  `test_subtitle_core` +2 cases (41).

**New TestBridge commands (`init.server.lua`):**
- `addSpawnedEffect` / `getSpawnedEffects` / `deleteSpawnedEffect` (mirror the
  overlay's Add-to-Frame path including gizmo + edit-mode preview fire) and
  `exportScene` (mirrors the Export button) — spawned effects and export are
  now reachable from bridge-driven tests.

**mcp.py tooling (Studio update fallout):**
- `screen_capture` now requires a `capture_id`; image content blocks are saved
  to `/tmp/roblox_capture_*.jpg` and returned as a path marker (`mcp capture`).
- `StudioMCP.exe` resolved directly from the newest Versions folder (mcp.bat
  hardcodes a stale path after every Roblox update; its registry fallback is
  broken cmd syntax).

**Prop attachment feature (follow-up, same day):** the test's top finding —
manually keyframing a carried prop against a moving hand — became a feature.
Simple Mode **Attach** button: select tracked prop + target part → the prop
follows the part via a plugin Heartbeat loop (grip offset frozen at attach
time; skips while play mode runs); select only the prop → detach. Ephemeral
authoring aid: no session/export data, state dies with the plugin, stale
entries self-clean when either part disappears. Chosen over a WeldConstraint
mechanism because welds left in the workspace would freeze rigs in play mode
and double-move parts during preview. Bridge cmds `attachProp` / `detachProp` /
`getPropAttachments`; `tests/test_prop_attach.lua` (11 cases, live — follow
translation/rotation with frozen offset, detach, guards). Suite: ~822 / 33 files.

**FIGURES fixtures repaired:** Rig1/Rig2/Rig3 had collapsed (disconnected
motors + unanchored parts + edit-mode physics). Motors reconnected, rest pose
re-applied, HumanoidRootParts now anchored so it cannot recur.

---

## Gizmo scaling + multiplayer client-fired effects (2026-07-14)

**Gizmo distance scaling (`init.server.lua`):** camera and spawned-effect
gizmos keep a roughly constant apparent size — `clamp(dist × 0.05, 0.5, 3.0)` ×
base size in a plugin Heartbeat (natural size at ~20 studs). Size written only
on >5 % change; the selected gizmo is skipped so scaling never fights the
dragger; Size writes don't trip the CFrame re-aim handler. From E2E finding #8.
`tests/test_gizmo_scale.lua` (8 cases, live).

**CutsceneServer path client-fired effects (`CutsceneServer.lua`,
`MultiAnimPlayer.lua`, `CutsceneCamera.lua`):** retires the multiplayer caveat.
`CutsceneServer.play` now loads EffectTracks + SpawnedEffects, reshapes them to
**arrays** (frame-keyed dictionaries are silently dropped by RemoteEvent
serialization) and broadcasts them as a fifth argument; it passes
`{skipEffects = true}` to `MultiAnimPlayer.play` so the server copies never
double-fire (server `ParticleEmitter:Emit()` wouldn't replicate anyway).
`CutsceneCamera` gained an effect scheduler: sorted events fired crossing-window
on the shared clock via its own RenderStepped connection (works in scenes with
no camera track), targets resolved client-side, spawned effects through the
ReplicatedStorage `SpawnedEffectRunner`; `"__stop"` cancels pending events.
`MultiAnimPlayer` duration still counts skipped-effect tails so the natural-end
`"__stop"` doesn't cut client effects short. Deploy server + client modules
together (⬆ Export does both). `tests/test_cutscene_effects_core.lua`
(15 cases, headless).

**Multi-client test finding:** `Script.Source` is readable only with plugin
capability — `publishCameraModule`'s stale-copy source-compare crashed a live
server (`lacking capability PluginOrOpenCloud`). Now pcall-guarded: edit-mode
tooling still refreshes stale copies; a live server keeps the deployed copy
(the Exporter owns freshness in that flow).

**DevLoader hardening (2026-07-14):** removed the 10-minute give-up (a place
open longer than that before the first push permanently killed hot-reload for
the session), then replaced the timeout-less `WaitForChild` with a
`CoreGui.ChildAdded:Wait()` loop — idle sessions in unrelated projects no
longer log "Infinite yield possible" warnings.

**Multi-client verification (2026-07-14):** two-player Clients-and-Servers run
confirmed both clients show the identical cutscene — camera cuts, client-fired
smoke/sparkle, and subtitles in sync on the shared clock. Also caught two more
bugs: `loadSession` returned true for a missing slot (now returns false — an
empty session then silently exported over a good scene), and saved session
slots can vanish when the DevLoader .rbxmx is rebuilt (plugin-settings
identity) — exported scenes are now kept on disk via `mcp scene pull`
(`scenes/Handoff_001/`).

**Latent camera bug fixed en route:** the CameraTrack broadcast sent `frames`
as a frame-keyed dictionary — sparse Advanced-mode camera keyframes (e.g.
frames 1 and 25 only) would be silently dropped by remote serialization; dense
Simple-Mode captures (1..N) only survived because they happen to be arrays.
`loadCameraData` now reshapes to an array of `{frame, cf, fov, cut, easing}`;
`cameraKeyframes` on the client accepts both the new array and the legacy
dictionary shape.

**Notable behavior observations (no code change):** prop tracking is tag-based
and parent-agnostic (a tagged prop keeps tracking inside a rig Model); edit-mode
WeldConstraints co-move welded parts on script CFrame writes even when anchored
(offset frozen at weld creation) — a possible basis for a future "prop follows
hand" attach feature; edit-mode viewport camera requires
`CameraType = Scriptable` before CFrame writes stick; the DevLoader needs a
`devsync.py push` after every Studio restart and a reload resets the session
(save/load slots recover it).

---

## Backflip test scene + Lighting post-effect toggles (2026-07-15)

**Effect lane extension:** `ColorCorrectionEffect`, `BloomEffect`, and
`BlurEffect` added to the Toggle classes — Lighting post-effects can now be
switched on/off from the Effect lane. Enables plugin-native **fade to black**:
three ColorCorrections at Brightness −0.34 toggled on across consecutive
frames (stepped fade, works in editor preview and in-game), and instant
full-body colour via a `Highlight` toggle. (+1 `test_effect_core` case.)

**Backflip_001 scene** (`Workspace.BackflipTest`, session slot, and
`scenes/Backflip_001[_Slow]/` on disk): single-rig stress test authored via
bridge — face close-up (FOV 30) → zoom-out dolly → 8-keyframe 360° head orbit →
5-frame backflip (root track through a full −360° pitch with height arc and
tuck poses) → red Highlight flash on landing → 4-frame fall onto the back →
3-step fade to black; `off` events at frame 1 reset the effects for replays.
Exported twice from one session: `Backflip_001` (12 fps, ~2.4 s, automated
playtest PASS) and `Backflip_001_Slow` (1 fps, ~29 s, human viewing via the
Disabled `__BackflipViewer` LocalScript — enable + F5). Verifies three
previously untested paths: camera FOV animation + orbit interpolation, root
rotations >180° across keyframes, and Lighting-effect toggles in-game.

---

## Fade effect type + animation trigger pads (2026-07-15)

**Fade spawned-effect type:** fourth type in the Add Effect overlay — fields
Color R/G/B, optional Image ID (`rbxassetid://` decal shown over the colour),
Duration (default 1.0 s), Direction (`out` = to colour/image, `in` = reveal).
Rendered as a full-screen ScreenGui overlay animated per Heartbeat with a
FadeToken so a newer fade takes over a running one: edit-mode preview in
CoreGui (plugin runner), in-game in PlayerGui (client paths; the server-only
MultiAnimPlayer path creates it in every player's PlayerGui, which replicates).
No world position — the violet gizmo sits at the authoring camera position as
an edit handle. Exporter/session/remote pipes reuse the spawnedEffects track
unchanged. Also fixed en route: **Color B was missing from the overlay's
property rows** — blue was never editable or saved for Explosion/Smoke.
Verified live: mid-fade transparency 0.50 at half duration, opaque at end.
(+5 `test_spawned_effects_core`, +9 `test_spawned_effects_exporter`.)

**Animation trigger pads** (`Workspace.AnimTriggerPads` +
`StarterPlayerScripts.__AnimPadListener`): labelled neon pads near spawn —
step on one in Play mode and the client plays the scene named in the pad's
`SceneName` attribute via CutscenePlayer (movieMode, debounced, pad flashes
amber while playing, resets on completion). Pads: `Backflip_001_Slow` (rig
also tagged `MAnim:Backflip_001_Slow` for auto-resolution) and `Handoff_001`.
Verified in play mode: pad touch → full cutscene with letterbox/effects/
subtitle. New pads = duplicate a pad, set its `SceneName` attribute and label.

**Feedback round (same day):** RedFlash highlight switched to Roblox
"Really red"; the Backflip scene's three ColorCorrection step events replaced
by a single smooth Fade event (dogfooding the new type — EffectTracks now
carries only RedFlash); `SpawnedEffectRunner.clearFades()` added to both runner
copies and wired into every teardown (CutscenePlayer doTeardown, CutsceneCamera
stopEffects — fired by `"__stop"` on stop and natural end — MultiAnimPlayer
finish, and the plugin's editor-preview stopPlayback) so a scene that ends
faded-out always returns the view to normal. Verified in play mode: overlay
gone after onComplete. Also: `character_navigation` now requires
`datamodel_type` and its client host can go stale ("Target is closed") — new
`mcp nav` command tries the tool then falls back to a Humanoid:MoveTo walk.

---

## Auto-pads on export + backflip direction fix (2026-07-15)

**Auto-pads:** Playback-tab toggle "Pads: ON" (persisted plugin setting,
default ON). Every successful export (button or `exportScene` bridge cmd)
creates or updates `Workspace.AnimTriggerPads.Pad_<scene>` — labelled neon pad,
`SceneName` attribute, palette colour, auto-placed in a grid near spawn — and
deploys `game/AnimPadListener.lua` as a LocalScript in StarterPlayerScripts
(replaces the hand-built `__AnimPadListener`; refreshed by source-compare,
which is legal in plugin context). Existing pads keep user-adjusted
position/colour; only label + attribute refresh. Step on a pad in Play mode →
CutscenePlayer plays that scene (debounced, amber flash).
Bridge: `setAutoPads`/`getAutoPads`/`ensureTriggerPad`.
`tests/test_trigger_pads.lua` (12 cases, live). Suite ~873.

**Backflip direction fix:** the flip rotated forward (pitch sign inverted) —
frames 14–29 re-posed with positive pitch: proper backflip, lands on feet,
falls backward onto his back. Both variants re-exported and re-pulled.

**Smoothing round (same day):** the 90°-per-keyframe flip read as jagged —
piecewise-linear CFrame lerp makes large rotation steps visible. Re-authored
with 8 keyframes at 45°/step (three `simpleInsertFrame` duplications opened the
gap; the frame-shift machinery auto-migrated the RedFlash event to the new
landing frame and the Fade event to F28 — first in-anger validation of
spawned/effect-event shift sync). Height arc made parabolic; fps doubled
(fast 12→24, slow 1→2). Authoring heuristic: keep per-keyframe rotation steps
at ≤45° for full rotations; ≥90° steps look mechanical at viewing speeds.

---

## Smooth interpolation mode (2026-07-15)

45° steps still read jagged at 2 fps — root cause is linear per-segment lerp
(velocity kink at every keyframe). All playback paths (CutscenePlayer,
MultiAnimPlayer, CutsceneCamera) now interpolate smoothly **by default**:
cubic De Casteljau over `CFrame:Lerp` with tangent controls extrapolated from
neighbour segments (unclamped Lerp extrapolates) — one construction covering
positions and rotations; Vector3/scale uses standard Catmull-Rom. Properties:
keyframes hit exactly, C1-ish velocity continuity, `Constant` easing holds
exactly, camera tangents never cross a `cut`, uniform linear data stays
linear. Opt out with `smooth = false` in play opts (CutscenePlayer /
MultiAnimPlayer / CutsceneServer). Editor Preview remains linear — noted as a
follow-up (Interpolator parity). `tests/test_smooth_interp.lua` (11 cases,
headless: endpoints, line invariance, boundary velocity continuity vs the
linear kink, rotation midpoints, 45°-ladder monotonicity, Constant hold).
Suite ~884.

---

## Pose→End button + fixes (2026-07-15)

**Pose→End (Simple Mode action row):** selection-scoped pose hold — a selected
rig part propagates just that limb's joint, a rig Model/HumanoidRootPart the
whole rig (joints + root), a tracked prop its CFrame. Takes the LIVE viewport
pose (no capture needed first) and overwrites every following keyframe;
earlier frames untouched, no new frames created. Bridge `simplePoseToEnd`;
`tests/test_pose_to_end.lua` (7 cases, live). The button additions hit the
Panel.new 200-register ceiling (crashed plugin boot: "Out of local registers…
subNumRow") — wrapped in a do…end block per the documented convention.

**Remap-dialog crash fixed:** `showNameRemapDialog` used `C.text` — a colour
key that never existed (`C.btnText`) — crashing the first time a user opened
the rename-remap flow.

**Cross-scene tag contamination (user-flow finding):** selecting a folder in
the Tag row tags it with the CURRENT scene name — picking HandoffTest while
the scene box said Backflip_001 pulled the Handoff rigs into the Backflip
session (captured on every navigation, exported as extra KFS, and the scene's
Crate track would have animated the Handoff crate). Stray tags removed, scene
rebuilt clean. Workflow rule: set the scene name FIRST, then pick the folder.

**`mcp scene pull` chunking:** tool responses truncate at ~100 k chars — dense
scenes (45+ keyframes) broke the pull. Now transfers the JSON in 90 k slices.

---

## Simple default + Elastic easing + session mirror + dense backflip (2026-07-15)

**Simple Mode is now the boot default** (`panel:setMode("simple")` after the
initial scan) — Advanced is an explicit choice.

**Elastic easing** (7th style): native `PoseEasingStyle.Elastic` end-to-end —
Panel dropdown, Interpolator (TweenService map), Exporter pose map, all three
game-side `easedAlpha` copies (spring-out formula), MultiAnimDataServer enum
parse. (+2 test_easing_core, +1 test_ui_easing style round-trip.)

**Place-file session backup:** every save — autosave included — mirrors the
session JSON into a `ServerStorage.MultiAnimSessions` StringValue (>190 k
sessions skip the mirror with a warning); `deleteSession` removes the mirror;
**loadNamed falls back to the mirror** when the plugin-settings slot is
missing. Closes the slot-loss failure from 2026-07-14. (+3 test_ui_bridge.)

**Backflip, manual-density edition:** per user feedback ("many frames with
small adjustments"), re-authored at 32 flip steps of 11.25° + 16 fall steps
(69 frames; fast 24 fps, slow 12 fps).

**Test-hygiene findings:** (1) UI test runs park keyframes in the live
session — authoring afterwards without a devsync reset exports the leftovers
(FIGURES rigs leaked into the Backflip scene a second way). Rule: reset the
session (push) between test runs and authoring. (2) `test_ui_easing` assumed
the panel's simple-easing state was Linear — it now normalises it at start and
restores it at the end, making the file retry-safe.

---

## Test-coverage hardening (2026-07-16)

Coverage review outcome — two structural guards added:

**Copy-sync pre-flight (`run_tests.py`):** the deliberately duplicated
functions (`easedAlpha`, `cubicCF`, `smoothCF`, `smoothV3` across the three
game players; `LEGACY_POSE_TO_JOINT` across player + data-server) were only
guarded by "keep in sync" comments — a fix applied to one copy could silently
miss the others. The suite now extracts and diffs the copies locally (no
Studio) and fails the run on drift.

**`test_platform_canary.lua` (15 cases):** named assertions for every Roblox
API behaviour the plugin depends on — Pose.CFrame (already renamed once),
easing enums incl. Elastic, CFrame:Lerp extrapolation (smooth-mode tangents),
TweenService:GetValue, the Motor6D contract, ChangeHistoryService undo
signals, CollectionService tagging, ScreenGui/StringValue/JSON primitives,
effect-lane classes, WeldConstraint. After a Studio update, this file fails
first and by name instead of leaving mysterious downstream breakage. Its very
first run caught a semantics detail: GetTagged only returns DataModel members
— the probable mechanism of the old test_tag_scene flake.

**Cross-file state leak found and fixed:** `test_ui_easing` ended with the
panel's simple-easing at EaseOut (its last assertion navigates to an EaseOut
frame); the next full-suite run's `test_pose_to_end` (alphabetically earlier)
then stamped EaseOut onto Rig1's captures, failing ui_easing's default-Linear
assertion — a two-run, two-file interaction that explains much of the
recurring once-per-run flake. The file now restores Linear in its cleanup.
Convention reinforced: UI test files must restore any panel state they change
— captures stamp the current easing.

**Gap closure (same day):** (1) `mcp playtest --client [--scene NAME]` — the
first automated play-mode client test: a temporary LocalScript runs the scene
through CutscenePlayer end-to-end (remote fetch, rig resolution, smooth
playback, teardown) and reports PASS/FAIL; server test script muted+restored;
nothing persists. (2) Copy-sync checker now also covers the test inline
copies (comment/whitespace/trailing-comma-insensitive body compare) and the
spawned-effect PRESETS plugin↔test pair — headless tests can no longer
silently diverge from the code they claim to test. (3) New live tests:
`test_cutscene_server_loaders.lua` (9 — exercises the REAL deployed module's
loaders via loadstring shim) and `test_fade_runtime.lua` (7 — fade overlay
timing, fade-in removal, image mode). Suite ~928.

---

## Didge round: mode-desync, prop state, camera drift, capture hygiene (done, 2026-07-16/17)

**Simple-default mode desync (both "Didge bugs" in one root cause):**
`panel:setMode("simple")` at startup only flips UI visibility — it deliberately
does not fire `onModeChanged` — so core `mode` stayed `"advanced"` and every
`mode == "simple"` gate was dead until the user manually toggled modes: tile
auto-capture (pose changes lost), camera capture on navigation, and the Look
Through per-frame viewport drive. The four scattered copies of the mode-switch
logic (button handler, two bridge commands, startup) are now one
`applyModeChange()`; startup goes through it. `getPanelMode` bridge command +
panel/core agreement assertion guard the desync.

**Prop visual-state tracks:** every prop keyframe now also captures
Transparency, Color, and Material (`stateTrack`, parallel to easingTrack).
Transparency/colour lerp with the frame's easing; material is stepped. Flows
end-to-end: editor scrub/preview, session JSON + place-file mirror, PropTracks
`states` block (omitted when empty — backward compatible), MultiAnimDataServer
`propStates` remote reshape, MultiAnimPlayer + CutscenePlayer sampling,
Pose→End propagation, dirty-detection. Two deliberate copies (`lerpState`,
`applyPartState`) registered in the copy-sync pre-flight.
`test_prop_state.lua` (13, headless); client playtest verified the remote path.

**Camera keyframe drift on navigation (Didge report: "camera frames save
wrongly / change on every iteration"):** two compounding causes. (1) Every
navigation departure unconditionally rewrote the frame's camera keyframe from
the live viewport — stepping through frames re-stamped every keyframe, reset
cut→move, and overwrote easing. Now a keyframe is only rewritten when the
camera actually moved at that frame (epsilon compare vs the saved keyframe /
arrival snapshot); overwrites preserve mode + easing. (2) `CameraCapture.apply`
never updated `Camera.Focus`; Studio's editor camera re-derives orientation
from CFrame+Focus and snapped/flipped the view with a stale Focus, which Look
Through mirrored into the gizmo and captures wrote into the track. Focus now
follows 10 studs ahead on every apply. `test_camera_capture.lua` (16, live —
appends frames at the timeline END so it runs regardless of session content);
platform canary +4 edit-camera write→read contract cases.

**Simple-mode capture-hygiene review (5 fixes):** (1) departure capture is
dirty-gated — rigs/props only re-captured when the pose actually changed
(conservative capture when no arrival snapshot, so edits are never lost);
camera-only frames are no longer materialized into rig keyframes (was pinning
interpolated poses and changing eased/smooth motion — confirmed live on Didge),
and untouched poses are no longer re-stamped with capture round-trip float
noise (measured 1.3e-5/2 passes before). (2) Arrival snapshot re-baselined
after scrub end / playback stop / Add-Insert-Delete frame. (3) Tile strip
refreshes immediately when navigation capture creates data at a new frame
(was invisible until the next rebuild). (4) Insert Frame duplicates inherit
the source camera keyframe's cut mode + easing. (5) Session-load prop re-link
prefers the session's tagged scene instances over a workspace-wide name search
(multi-scene places: every scene can have a "Wall"/"SimpleCamera" — verified
with a decoy). `test_simple_capture_hygiene.lua` (9, live, end-appended);
bridge: `setSimpleCameraCF`, `deletePropKeyframe`, `getSimpleUISlots`.

**Suite: ~1006 cases, 42 runnable files** (fewer reported when the live
session holds user data — several test_ui_simple blocks skip; the two new
end-appended files always run).

---

## Structural self-tests round (done, 2026-07-17)

**Three new guards against "code change with unattended side consequences",
plus the navigation consolidation** (`simpleNavigate` bridge = the panel's
`navigateToFrame` — no more hand-mirrored copies, the mode-desync divergence
pattern):

1. **`test_session_integrity.lua` (11, live):** fully-populated session (all
   track types) must survive serialize→load→serialize losslessly (deep diff by
   path); `shiftFrames(+1)/(−1)` must be identity; eight passive operations
   (mode round-trips, play+stop, Camera View / Look Through / Onion toggles,
   navigation sweep, export) must leave the serialization byte-identical.
   Backs up + restores the live session. New bridge cmd: `shiftFrames`.
2. **Deploy-sync pre-flight in `run_tests.py`:** every deployed game module's
   Source vs `game/*.lua` (normalized) — live tests can no longer silently
   validate stale deployed code.
3. Consolidation as above.

**The integrity test caught two shipped bugs on its first run:**
- `applyModeChange` overwrote `advancedFrameCount` on every Simple entry, so
  simple→playback→simple degraded the saved frameCount (120 → collapsed
  count). Now captured only when actually coming from Advanced (also closes
  the documented simple→simple re-entry trap).
- **Camera easing wiped on every session load and every switch to Advanced:**
  the camera-gizmo `GetPropertyChangedSignal("CFrame")` handler re-captured
  keyframes with a 4-arg `addCameraKeyframe` (drops easing), and the
  `gizmoSyncing` boolean guard is DEFEATED BY DEFERRED SIGNAL DELIVERY — the
  callback fires after the flag is reset, so `rebuildCameraUI`'s programmatic
  sync echoed into a re-capture. Fixed: skip when the gizmo CFrame equals the
  stored keyframe, pass easing through (also in the advanced C-key capture).
  Lesson recorded in CLAUDE.md Key Constraints: guard programmatic writes by
  VALUE, never by a same-frame boolean flag.

Also fixed: `test_pose_to_end` was not self-contained (never reset the live
arm pose or deleted its frames) — one failing run poisoned every subsequent
run via capture inheritance. Now rest-pose baseline + full cleanup.

**Suite: ~1017 cases, 43 runnable files.**
