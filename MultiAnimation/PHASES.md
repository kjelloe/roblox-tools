# MultiAnimation — Implementation Phases

## Overview

| Phase | Name | Deliverable |
|-------|------|-------------|
| 1 | Scaffold | Plugin boots, panel opens, rigs listed |
| 2 | Capture | Keyframes recorded, markers appear |
| 3 | Preview | Scrub + play back in viewport |
| 4 | Export | Animation data written to ServerStorage |
| 5 | In-game Playback | Simultaneous playback via MultiAnimPlayer |
| 6 | Polish | UX improvements, session persistence, delete KF |
| 7 | Future | Auto-capture, R15, easing curves, audio sync |

---

## Phase 1 — Scaffold

**Goal:** Plugin installs and opens a docked panel that lists the rigs in the scene.

### Tasks

- [ ] Set up Rojo project (`default.project.json`) targeting `%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxm`
- [ ] `init.server.lua`: create toolbar, toolbar button, DockWidgetPluginGui
- [ ] `RigScanner.lua`: scan `Workspace.FIGURES`, return R6 models (Humanoid + Torso check)
- [ ] `Panel.lua`: root ScreenGui frame with sections (RIGS, TIMELINE, CONTROLS)
- [ ] `RigSelector.lua`: render one toggle button per discovered rig; handle toggle state
- [ ] Wire Refresh button → re-run RigScanner → redraw RigSelector

### Acceptance Criteria

- Plugin button appears in Studio toolbar
- Clicking it opens/closes the docked panel
- Rig1 and Rig2 appear as toggle buttons
- Toggling a button changes its visual state
- Refresh rescans and updates the list

---

## Phase 2 — Capture

**Goal:** Pressing "Add Keyframe" records the current pose of active rigs.

### Tasks

- [ ] `JointCapture.lua`: read `Motor6D.Transform` for all 6 R6 joints from a rig model
- [ ] `ScaleCapture.lua`: read `Part.Size` for all 7 R6 body parts from a rig model
- [ ] `Recorder.lua`: state machine; `addKeyframe(frame)` stores joint + scale data
- [ ] `Timeline.lua`: track `currentFrame`, `frameCount`, `fps`; expose frame navigation helpers
- [ ] `Controls.lua`: render Add Keyframe button, FPS input, FrameCount input, current frame display
- [ ] `TrackLane.lua`: horizontal bar for one rig
- [ ] `KeyframeMarker.lua`: dot on TrackLane at correct proportional position
- [ ] Wire Add Keyframe → Recorder → redraw TrackLanes

### Acceptance Criteria

- Pose Rig1's arm, press Add Keyframe → dot appears on Rig1 lane
- Pose Rig2's leg, press Add Keyframe → dot appears on Rig2 lane at same frame
- With Rig2 toggle off, pressing Add Keyframe only records Rig1 (Rig2 lane unchanged)
- Pressing Add Keyframe twice on same frame overwrites without adding a duplicate dot
- Captured joint CFrames differ from rest pose after moving a part

---

## Phase 3 — Preview

**Goal:** Scrubbing or pressing Play applies poses in the viewport without entering play mode.

### Tasks

- [ ] `PoseApplier.lua`: write `Motor6D.Transform` values back to rig joints; wrap in `ChangeHistoryService`
- [ ] `Timeline.lua`: `getPoseAtFrame(rig, frame)` — linear interpolation between adjacent keyframes
- [ ] Scrubber slider → `Timeline.currentFrame` → `PoseApplier.apply(rigs, frame)`
- [ ] Prev KF / Next KF buttons → jump to nearest keyframe marker
- [ ] Click keyframe dot → jump to that frame
- [ ] Play button → `RunService.Heartbeat` loop stepping frames at configured FPS → `PoseApplier`
- [ ] Stop button → disconnect Heartbeat; reset timeline position

### Acceptance Criteria

- Dragging scrubber moves both rigs to interpolated poses
- Clicking a keyframe dot snaps both rigs to exact captured pose
- Play button animates both rigs in the viewport at ~24fps
- Stop button halts playback; rigs stay at current pose
- Undo in Studio does not revert to a messy intermediate state (ChangeHistoryService)

---

## Phase 4 — Export

**Goal:** Session data is written as usable assets into ServerStorage.

### Tasks

- [ ] `Exporter.lua`:
  - Build `KeyframeSequence` for each rig from `jointTrack` (Pose tree, correct hierarchy)
  - Serialise `scaleTrack` to a Lua table string → `ModuleScript`
  - Create `ServerStorage.MultiAnimationData` if missing
  - Create named scene subfolder; handle overwrite prompt
- [ ] Scene name input field in panel
- [ ] Export button wired to `Exporter.export(session, sceneName)`
- [ ] Overwrite confirmation dialog (Studio `plugin:CreateYesNoDialog`)

### Acceptance Criteria

- Pressing Export creates `ServerStorage.MultiAnimationData.Scene_001`
- `Rig1_Joints` and `Rig2_Joints` are valid `KeyframeSequence` instances with correct timing
- `ScaleTracks` ModuleScript returns a table matching the spec in `DATA_FORMAT.md`
- Exporting again with same name shows confirmation prompt; cancelling leaves old data intact
- Exported KeyframeSequence can be loaded by `Animator:LoadAnimation()` without error

---

## Phase 5 — In-game Playback

**Goal:** A developer can trigger simultaneous playback of both rigs in a live game.

### Tasks

- [ ] `MultiAnimPlayer.lua` ModuleScript:
  - `play(sceneName, rigMap, options?)` — loads KFS per rig, fires `Animator:Play()` simultaneously
  - Scale tween loop via `RunService.Heartbeat`
  - `stop()` — cancels animations and tweens
  - `onFinished(callback)` — fires on natural end or stop
- [ ] Place `MultiAnimPlayer` in `ServerStorage.MultiAnimationData` (Exporter deposits it)
- [ ] Test script in `ServerScriptService` that calls `player.play("Scene_001", rigMap)`

### Acceptance Criteria

- Running the test script in play mode animates Rig1 and Rig2 simultaneously
- Joint poses match the viewport preview (same CFrames)
- Scale changes tween smoothly between keyframes
- `player.stop()` halts both rigs mid-animation
- `onFinished` fires after the last keyframe

---

## Phase 6 — Polish

**Goal:** Reliable UX, session survives panel close/reopen, keyframes deletable.

### Tasks

- [ ] Session serialisation → `plugin:SetSetting("session", json)` on every change
- [ ] Session deserialisation on panel open (restore markers, frame count, rig list)
- [ ] "New Session" button — clears data after confirmation
- [ ] Delete keyframe: right-click marker → context menu → Delete
- [ ] Auto-detect rig added/removed from FIGURES (instance `ChildAdded`/`ChildRemoved` on FIGURES folder)
- [ ] Rest pose restore: when preview stops, apply stored T-pose to all rigs
- [ ] Validate Motor6Ds exist before capture; surface clear error if rig is broken

### Acceptance Criteria

- Close and reopen panel → all keyframe markers, rig toggles, and frame settings restored
- Deleting a keyframe removes its marker and the stored data
- New Session clears everything after confirmation
- Adding a rig to FIGURES while panel is open → Refresh or auto-detect adds it to selector

---

## Phase 7 — Future (not in v1 scope)

- Auto-capture: detect Motor6D change events and add keyframe automatically
- Per-keyframe easing curve selector (Bezier, Bounce, Elastic)
- R15 rig support (different joint set, different Pose tree)
- Audio track sync (align keyframes to a Sound object)
- Upload animation to Roblox asset catalogue (requires Open Cloud API)
- Onion-skin ghost rendering of adjacent keyframe poses in viewport
- Copy/paste keyframe between rigs (mirror a pose from Rig1 to Rig2)

---

## Development Order Notes

- Phases 1–2 can be built and tested purely in Studio edit mode with no play mode needed.
- Phase 3 requires testing pose application in edit mode; confirm ChangeHistoryService works correctly.
- Phase 4 KeyframeSequence structure must be validated with a real `Animator:LoadAnimation()` call before Phase 5 begins — bad hierarchy causes silent failures.
- Phase 5 is the first phase that requires running the place in play mode.
- Phases 1–5 are the shippable v1. Phase 6 is the hardening pass before wider use.
