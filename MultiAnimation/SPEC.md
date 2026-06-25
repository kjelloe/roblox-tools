# MultiAnimation — Functional Specification

## Purpose

A Roblox Studio Plugin that lets an animator pose R6 character rigs in the viewport,
capture those poses as keyframes on a shared timeline, and export the result as
animation data that plays back simultaneously on multiple rigs in a live game.

The initial scope targets two R6 rigs. The design must support N rigs without
architectural changes.

---

## Actors

- **Animator** — the human using Roblox Studio with the plugin installed.
- **Player** — a Roblox player in a live game who experiences the animation playback.

---

## User Stories

### Plugin panel

| ID | Story |
|----|-------|
| P-01 | As an animator, I can open/close the MultiAnimation panel from the Studio toolbar so it does not clutter my workspace when not in use. |
| P-02 | As an animator, the panel docks inside Studio so it does not cover the viewport. |
| P-03 | As an animator, the panel shows all R6 rigs found in `Workspace.FIGURES` so I know what is available. |
| P-04 | As an animator, I can press Refresh to re-scan `Workspace.FIGURES` after adding or removing a rig. |

### Rig selection

| ID | Story |
|----|-------|
| R-01 | As an animator, I can select one rig at a time for recording; clicking a rig button makes it the only active rig (exclusive/radio-button behaviour). |
| R-02 | As an animator, the active rig cannot be deselected without choosing another; exactly one rig is always active. |
| R-03 | As an animator, switching the active rig mid-session does not delete any already-recorded keyframes. |
| R-04 | As an animator, clicking any part of a rig in the Studio viewport automatically selects only that rig in the plugin panel. |

### Keyframe capture

| ID | Story |
|----|-------|
| K-01 | As an animator, I pose a rig by selecting its parts in the viewport and using Studio's Move / Rotate / Scale tools. |
| K-02 | As an animator, I press "Add Keyframe" to capture the current pose of all active rigs at the current frame. |
| K-03 | As an animator, pressing "Add Keyframe" on a frame that already has a keyframe overwrites it for active rigs only; inactive rigs keep their previous data. |
| K-04 | As an animator, joint rotations and positions are captured for all six R6 Motor6D joints per rig. |
| K-05 | As an animator, part scale (Size) is captured for all seven R6 body parts per rig alongside the joint data. |
| K-06 | As an animator, newly added keyframes appear immediately as markers on the track lane. |
| K-07 | As an animator, I can double-click anywhere on a rig's track lane to jump the timeline to that frame and add a keyframe for that rig immediately. |

### Timeline

| ID | Story |
|----|-------|
| T-01 | As an animator, I can scrub the timeline to any frame using a slider. |
| T-02 | As an animator, scrubbing applies the stored pose (interpolated between adjacent keyframes) live in the viewport so I can see the result without playing. |
| T-03 | As an animator, I can click a keyframe marker dot to jump directly to that frame. |
| T-04 | As an animator, I can navigate to the previous or next keyframe with dedicated buttons. |
| T-05 | As an animator, I can set the session FPS (default 24) and total frame count before recording. |
| T-06 | As an animator, I can right-click a keyframe marker dot to delete that keyframe for that rig only. |

### Preview playback (in-editor)

| ID | Story |
|----|-------|
| V-01 | As an animator, I can press Play to step through the timeline at the configured FPS and see both rigs animate in the viewport (edit mode, no play mode required). |
| V-02 | As an animator, I can press Stop at any time to halt preview and stay at the current frame. |
| V-03 | As an animator, preview playback applies interpolated poses to all rigs regardless of which are toggled active for recording. |

### Export

| ID | Story |
|----|-------|
| E-01 | As an animator, I can press Export to write the animation data into `ServerStorage.MultiAnimationData` under a named scene folder. |
| E-02 | As an animator, I can name the scene before exporting; the default name is `Scene_001` incrementing automatically. |
| E-03 | As an animator, the export creates one `KeyframeSequence` per rig (joint data) and one `ModuleScript` (scale data) inside the scene folder. |
| E-04 | As an animator, exporting a scene that already exists prompts for overwrite confirmation. |

### Session file transfer

| ID | Story |
|----|-------|
| X-01 | As an animator, I can click **Export File** to serialise the current session as JSON into a `StringValue` (`ServerStorage.MultiAnimSessions.<sceneName>`), which I can then save as a `.rbxm` from Explorer. |
| X-02 | As an animator, I can insert a session `.rbxm` into any Studio project, select the `StringValue` in Explorer, and click **Import File** to restore the full session. |
| X-03 | On import, rigs/props/effects are re-linked by name; data for instances not found is preserved in the recorder for export but has no live viewport link. |
| X-04 | On import in Simple mode with a scene name and tag folder set, the plugin re-applies `MAnim:<name>` tags and rescans rigs automatically. |

### Prop tracking

| ID | Story |
|----|-------|
| O-01 | As an animator, I can select any `BasePart` in the Studio viewport and click "Track Part" to add it to the animation session. |
| O-02 | As an animator, the plugin rejects tracking a part whose name is not unique among already-tracked props and rigs, and tells me why. |
| O-03 | As an animator, tracked props appear in a "PROPS IN SCENE" section with independent multi-select toggle buttons (not exclusive — I can have Rig1 active and Block active simultaneously). |
| O-04 | As an animator, I can click × on a prop button to remove it from the active prop list; its recorded keyframe data is kept until the session is cleared. |
| O-05 | As an animator, each tracked prop has its own track lane with teal keyframe dots so I can immediately distinguish prop lanes from rig lanes. |
| O-06 | As an animator, "Add Keyframe" captures the current `CFrame` of all active props at the current frame, alongside active rig poses. |
| O-07 | As an animator, I can double-click anywhere on a prop's track lane to jump to that frame and add a keyframe for that prop. |
| O-08 | As an animator, I can right-click a teal keyframe dot to delete that prop's keyframe at that frame. |
| O-09 | As an animator, scrubbing the timeline applies interpolated `CFrame` positions to all tracked props in the viewport. |
| O-10 | As an animator, Preview playback moves props in the viewport at the configured FPS, interpolated between keyframes. |
| O-11 | As an animator, prop tracks are included in Save As / Load so my prop keyframes persist across sessions. |

### Camera track & cutscenes

| ID | Story |
|----|-------|
| C-01 | As an animator, I can press `C` (or the 📷 button) to capture the current Studio viewport camera (position, rotation, FOV) as a camera keyframe at the current frame. |
| C-02 | As an animator, camera keyframes appear as orange dots on a dedicated Camera track lane; cut keyframes are red. |
| C-03 | As an animator, each camera keyframe is either "move" (smooth interpolation from the previous shot) or "cut" (the previous shot holds, then jumps); I can toggle the mode of the keyframe at the current frame with one button. |
| C-04 | As an animator, every camera keyframe renders a gizmo part in the scene showing the shot's position and direction; gizmos are never saved with the place. |
| C-05 | As an animator, clicking a camera gizmo in the viewport jumps the timeline to its frame; dragging a gizmo with Studio tools re-aims that keyframe. |
| C-06 | As an animator, I can toggle "Cam Preview" so the Studio viewport follows the interpolated camera track while I scrub or preview — and get my exact previous view back when I toggle it off. |
| C-07 | As an animator, FOV is captured per keyframe and interpolated on moves (enabling zoom shots), jumping on cuts. |
| C-08 | As an animator, exporting a scene writes a `CameraTrack` ModuleScript alongside the animation data (omitted when no camera keyframes exist). |
| C-09 | As a developer, calling `CutsceneServer.play(scene, rigMap)` plays the animation and synchronizes every connected player's camera to the camera track via a shared server timestamp. |
| C-10 | As a player, my camera is restored to normal when the cutscene ends or is stopped. |

### In-game playback

| ID | Story |
|----|-------|
| G-01 | As a developer, I can require `MultiAnimPlayer` and call `player.play(sceneName, rigMap)` to start playback. |
| G-02 | As a player, both rigs begin their animations in the same frame, with no perceptible offset. |
| G-03 | As a developer, scale changes are interpolated between keyframes in a `RunService.Heartbeat` loop, matching the session FPS. |
| G-04 | As a developer, I can call `player.stop()` to halt playback on all rigs and props at any time. |
| G-05 | As a developer, I can pass an optional `propMap` to `player.play()` mapping prop names to their in-game Part instances; omitting it plays rigs only (backward compatible). |
| G-06 | As a developer, prop `CFrame` is interpolated between keyframes in the same Heartbeat loop as scale tracks. |

---

## Rig Detection Rules

**R6:** Model with `Humanoid` + `Part` named `Torso` (no `UpperTorso`) + at least one `Motor6D` in the Torso.

**R15:** Model with `Humanoid` + `Part` named `UpperTorso` + at least one qualifying `Motor6D`.

**Animatable rig (general):** R6 or R15 — used by `RigScanner.isAnimatableRig()`.

---

## Motor6D Joint Discovery (Dynamic)

The plugin dynamically discovers all Motor6Ds belonging to a rig using a filter:
- `motor.Parent.Parent == rig` — the Motor6D's container part is a direct child of the rig Model
- `motor.Part1.Parent == rig` — the target part is also a direct child of the rig Model

This naturally captures all canonical rig joints for both R6 (6 joints) and R15 (15 joints)
while excluding accessory welds (whose Handle is nested inside an Accessory model).

Apply order is determined by topological sort: parent joints are applied before child joints,
ensuring correct FK chain regardless of rig type.

**R6 joints (for reference):**

| Motor6D Name | Part0 | Part1 |
|---|---|---|
| RootJoint | HumanoidRootPart | Torso |
| Neck | Torso | Head |
| Right Shoulder | Torso | Right Arm |
| Left Shoulder | Torso | Left Arm |
| Right Hip | Torso | Right Leg |
| Left Hip | Torso | Left Leg |

---

## Body Parts Scaled

`Head`, `Torso`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg`, `HumanoidRootPart`

---

## Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NF-01 | The plugin must not error or hang if no rigs are present in `Workspace.FIGURES`. |
| NF-02 | Preview playback must not enter Roblox play mode; it operates entirely in edit mode. |
| NF-03 | Closing the plugin panel must not discard recorded session data; reopening resumes the session. |
| NF-04 | The plugin must not interfere with Roblox's undo/redo stack during preview (pose applies are non-destructive or wrapped in ChangeHistoryService). |
| NF-05 | In-game playback (`MultiAnimPlayer`) must have no dependency on the plugin being installed. |

---

## Prop Constraints (Phase 7)

- Props must be `BasePart` instances (Part, MeshPart, etc.). Models with multiple parts are not supported; pick the root part.
- Props must have a unique name across all tracked props and rigs in the session.
- Props should be `Anchored = true`; the plugin warns but does not block if unanchored. Unanchored props will drift under physics during playback.
- Sub-parts (`MeshPart`, `SpecialMesh`, `ParticleEmitter`) follow the parent part's CFrame automatically — their own properties are not animated.
- Props are identified by `Name` for session persistence. If a prop is not found by name on session load, that prop's tracks are skipped with a warning.

## Camera Constraints (Phase 8)

- One camera track per session (multiple named cameras + switcher = Phase 9).
- Camera gizmos live in `workspace.__MultiAnimCameraGizmos` with `Archivable = false` — they never persist into the saved place and are removed on plugin unload.
- Synchronized playback: the server broadcasts the camera track data in the RemoteEvent payload (clients cannot read ServerStorage) plus a `GetServerTimeNow()` start timestamp with a 0.35 s lead.
- Known caveat: rig motion reaches clients via replication ~50–100 ms behind the locally-computed camera; acceptable for v1 (full client-side playback is the v2 fix).

## Out of Scope (v1)

- Auto-capture on transform change (future Phase 6)
- R15 rig support
- Easing curve editor per keyframe (all interpolation is linear in v1)
- Audio sync
- Uploading animations to Roblox asset catalogue
- Rig FK/IK controls
- Multiple named cameras with a switcher track (Phase 9)
