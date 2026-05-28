# MultiAnimation — Implementation Phases

## Overview

| Phase | Name | Status |
|-------|------|--------|
| 1 | Scaffold | ✅ Complete |
| 2 | Capture | ✅ Complete |
| 3 | Preview | ✅ Complete |
| 4 | Export | ⬜ Next |
| 5 | In-game Playback | ⬜ Pending |
| 6 | Polish | ⬜ Pending |
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

- `JointCapture` — reads `Motor6D.Transform` for all 6 R6 joints
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
  so `ChangeHistoryService` is paused during drag
- `|◄` / `►|` buttons — jump to prev/next keyframe across all rigs
- `▶ Preview` — `RunService.Heartbeat` loop; `ChangeHistoryService:SetEnabled(false)`
  during playback
- `■ Stop` — disconnects loop, re-enables history, sets waypoint

---

## Phase 4 — Export ⬜ Next

Write animation data to `ServerStorage` as usable Roblox assets.

### Tasks

- [ ] `Exporter.lua`:
  - Build `KeyframeSequence` per rig from `jointTrack` (correct R6 Pose hierarchy)
  - Serialise `scaleTrack` to a Lua table string → `ModuleScript`
  - Create `ServerStorage.MultiAnimationData` folder if missing
  - Create named scene subfolder; prompt overwrite if exists
- [ ] Scene name `TextBox` in CONTROLS (default `Scene_001`, auto-increment)
- [ ] Wire `⬆ Export` button → `Exporter.export(session, sceneName)`
- [ ] Overwrite confirmation via `plugin:CreateYesNoDialog`
- [ ] Copy `MultiAnimPlayer.lua` into the scene folder on export

### Acceptance Criteria

- Pressing Export creates `ServerStorage.MultiAnimationData.Scene_001`
- `Rig1_Joints` / `Rig2_Joints` are valid `KeyframeSequence` instances
- `ScaleTracks` ModuleScript returns a table matching `DATA_FORMAT.md`
- Exporting twice with same name shows confirmation prompt
- Exported `KeyframeSequence` loads via `Animator:LoadAnimation()` without error

---

## Phase 5 — In-game Playback ⬜

Simultaneous playback of both rigs in a live game.

### Tasks

- [ ] `MultiAnimPlayer.lua` ModuleScript:
  - `play(sceneName, rigMap, options?)` — simultaneous `Animator:Play()` on both rigs
  - Scale tween loop via `RunService.Heartbeat`
  - `stop()` — cancels animations and tweens
  - `onFinished(callback)` — fires on natural end or stop
- [ ] Test script in `ServerScriptService`

### Acceptance Criteria

- Both rigs animate simultaneously in play mode
- Joint poses match the viewport preview
- Scale changes tween smoothly between keyframes
- `stop()` and `onFinished` work correctly

---

## Phase 6 — Polish ⬜

Session persistence, delete keyframe, auto-detect rigs.

### Tasks

- [ ] Session serialisation → `plugin:SetSetting("session", json)` on every change
- [ ] Session deserialisation on panel open (restore markers, frame count)
- [ ] "New Session" button with confirmation
- [ ] Delete keyframe: right-click marker → remove
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
