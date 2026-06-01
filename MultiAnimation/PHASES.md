# MultiAnimation — Implementation Phases

## Overview

| Phase | Name | Status |
|-------|------|--------|
| 1 | Scaffold | ✅ Complete |
| 2 | Capture | ✅ Complete |
| 3 | Preview | ✅ Complete |
| 4 | Export | ✅ Complete |
| 5 | In-game Playback | ✅ Complete |
| 6 | Polish | 🔄 In Progress |
| 7 | Future | ⬜ Backlog |

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
- Each limb Pose.Transform = the captured CFrame for that joint (Neck→Head, shoulders→arms, hips→legs)
- `AuthoredHipHeight = 0`, `Loop = false`, `EasingStyle = Linear` per spec

---

## Phase 5 — In-game Playback ✅

Simultaneous playback of both rigs in a live game.

### Tasks

- [x] `MultiAnimPlayer.lua` ModuleScript (`game/`):
  - `play(sceneName, rigMap, options?)` — loads KFS via `AnimationClipProvider:RegisterKeyframeSequence`, calls `Animator:Play()`; scale interpolated via `RunService.Heartbeat`
  - `stop()` — stops all AnimationTracks and Heartbeat loop, fires `onFinished`
  - `onFinished(callback)` — single registered callback, fires on completion or stop
- [x] Auto-deployed to `ServerStorage.MultiAnimationData` by `Exporter.export()`
- [x] Test script: `tests/test_player.lua` (place in ServerScriptService, run in Play mode)

### Acceptance Criteria

- Both rigs animate simultaneously in play mode
- Joint poses match the viewport preview
- Scale changes lerp smoothly between keyframes
- `stop()` and `onFinished` work correctly

### Notes

- `AnimationClipProvider:RegisterKeyframeSequence` registers the in-memory KFS and returns a `rbxtemp://` content ID usable as `Animation.AnimationId`
- Scale interpolation runs on `RunService.Heartbeat`; `CFrame:Lerp` / `Vector3:Lerp` for linear blending
- `onFinished` is single-callback (last registered wins); call before `play()` to avoid race
- Exporter clones `MultiAnimPlayer` from the plugin's `game` folder into `ServerStorage.MultiAnimationData` on every export so the game-side module is always up to date

---

## Phase 6 — Polish 🔄

Session persistence, keyframe editing, rig workflow improvements.

### Tasks

- [x] Delete keyframe: right-click marker → removes that rig's keyframe at that frame only (`MouseButton2Click` → `Recorder:deleteRigKeyframe`)
- [x] Viewport selection sync: clicking any part of a rig in the Studio viewport selects only that rig in the plugin panel (`Selection.SelectionChanged` + ancestor walk)
- [x] Session save/load: `Save` and `Load` buttons persist session via `plugin:SetSetting` (CFrames as 12-number arrays, Vector3 as 3-number arrays)
- [ ] Session auto-save on every keyframe change (currently manual Save button only)
- [ ] "New Session" button with confirmation dialog
- [ ] Auto-detect rigs added/removed from FIGURES (`ChildAdded`/`ChildRemoved`)
- [ ] Rest pose restore when preview stops
- [ ] Validate Motor6Ds before capture; surface clear error if rig is broken

---

## Phase 7 — Future Backlog

- Auto-capture on transform change
- Per-keyframe easing curve selector
- R15 rig support
- Audio track sync
- Upload to Roblox asset catalogue
- Onion-skin ghost rendering
- Copy/paste keyframe between rigs (mirror pose)
