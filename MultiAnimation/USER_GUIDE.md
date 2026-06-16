# MultiAnimation — User Guide

A Roblox Studio plugin for animating **multiple R6 rigs, props, and a cutscene
camera** on one shared timeline — entirely in edit mode — and playing the
result back in-game, synchronized across all players.

This guide is for the person *using* the plugin. For developer tooling
(building, testing, hot-reload) see the repo `README.md`; for internals see
`ARCHITECTURE.md`.

---

## 1. Getting Started

**Install:** the plugin lives at
`%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx` (built by `build.py`).
After installing, restart Studio. The plugin appears in the **Plugins toolbar**
(not in "Manage Plugins" — that's marketplace-only).

**Scene setup:** put your R6 rigs in a folder called `FIGURES` in Workspace:

```
Workspace
└── FIGURES
    ├── Rig1   (R6: Humanoid + Torso + Motor6Ds)
    └── Rig2
```

**Open the panel:** click the MultiAnimation toolbar button. The panel docks at
the bottom. Rigs are detected automatically — including rigs you add or remove
while the panel is open.

> **Note:** while the panel is open, the plugin disconnects the rigs' Motor6D
> joints so you can pose limbs individually (in edit mode they otherwise act as
> rigid welds). Joints are reconnected automatically when the plugin unloads.

---

## 2. The Panel, Top to Bottom

| Section | What's in it |
|---|---|
| **Mode toggle** | `Simple` / `Advanced` buttons, always visible above RIGS IN SCENE — switches the whole panel layout without losing session data. See §11, Simple Mode. |
| **RIGS IN SCENE** | One button per detected rig (exclusive select — exactly one active), plus `↺ Refresh`, `+ Rig`, `Save As`, `Load`, `New` |
| **PROPS IN SCENE** | `Track Part` button + one toggle per tracked prop (multi-select), each with a `×` to untrack |
| **TIMELINE** | One keyframe lane per rig (yellow dots), the Camera lane (orange/red dots), and one lane per prop (teal dots) |
| **CONTROLS** | Frame navigation, step size, the scrubber, scene name, action buttons (including `💾 Save`), and the camera row |

These five are the **Advanced mode** sections. **Simple mode** (toggle above)
replaces RIGS IN SCENE / PROPS IN SCENE / TIMELINE / CONTROLS with one compact
section — see §11, Simple Mode.

---

## 3. Animating Rigs

1. **Select a rig** — click its button in the panel, *or* just click any part
   of it in the viewport. Selection is exclusive (radio-button style).
2. **Pose it** — move/rotate limbs with Studio's normal tools. You can also
   resize parts (scale is animated too) and move the whole rig.
3. **Add a keyframe** — press **`K`** or click **+ Add Keyframe**. A yellow dot
   appears on that rig's lane at the current frame.
4. **Move to the next frame** — press **`L`** (forward) / **`J`** (back), drag
   the scrubber, or type a frame number. Pose again, keyframe again.
5. **Watch it** — **▶ Preview** plays the timeline live in the viewport;
   **■ Stop** halts and leaves you at the current frame.

**Adding rigs:** click **`+ Rig`** to clone Rig1 into FIGURES as the next free
`RigN`, placed beside the existing rigs. It's detected and ready to animate
immediately. (Dropping any R6 model into FIGURES by hand works too.)

**Copying poses between rigs and frames:** the **Copy KF / Paste KF / Paste
Mirrored** row at the bottom of CONTROLS is a keyframe clipboard:

1. Select the source rig, go to the keyframe you want, click **Copy KF**
   (the label shows what's held, e.g. `Rig1 @ 12`).
2. Select the target rig and/or move to another frame, then click
   **Paste KF** — the pose (joints + sizes) is written there. The target rig
   keeps its own position in the world; only the pose transfers.
3. **Paste Mirrored** flips the pose left↔right — a right-arm wave becomes a
   left-arm wave. Perfect for symmetric walk cycles and mirrored reaction
   shots between two characters.

**Useful behaviours:**
- Scrubbing **interpolates** between keyframes live, so you can inspect any
  in-between pose.
- Parking on a keyframe, adjusting the pose, then scrubbing away
  **auto-updates** that keyframe — no need to press `K` again.
- **Double-click anywhere on a rig's lane** to jump there *and* keyframe that
  rig in one motion.
- Each rig records independently: only the **active** rig captures when you
  press `K`. Other rigs' keyframes are never touched.

---

## 4. Animating Props

Any single `BasePart` (block, boulder, projectile…) can be animated:

1. Select the part in the viewport and click **Track Part**. It gets a toggle
   button and a teal lane. (Names must be unique; keep props `Anchored`.)
2. Prop toggles are **multi-select** and independent of the rig selection —
   you can keyframe Rig1 and two props in the same `K` press.
3. Move/rotate the prop, keyframe, repeat. Position *and* rotation interpolate
   smoothly (rotation slerps, so tumbling looks right).
4. The `×` on a prop button untracks it from the panel but keeps its recorded
   data in the session (and in the export).

---

## 5. The Camera Track (Cutscenes)

Direct your scene like a film, without ever entering play mode:

1. **Frame a shot:** fly the Studio viewport to where you want the camera.
2. **Press `C`** (or click **📷 Cam KF**). The current view — position,
   rotation, *and* field of view — becomes a camera keyframe at the current
   frame. An **orange dot** appears on the Camera lane and a small **gizmo
   part** appears in the scene showing the shot (the stud marks the look
   direction).
3. **Move vs Cut:** keyframes default to **move** — the camera glides smoothly
   from the previous shot. Click **Cam KF: move** to flip it to **cut** — the
   previous shot holds, then the camera jumps hard at that frame (the dot and
   gizmo turn **red**). Classic multi-angle editing is just a row of cuts.
4. **Review:** toggle **Cam Preview: ON** and scrub or press Preview — your
   viewport *is* the cutscene camera. Toggle OFF and your previous view is
   restored exactly.
5. **Adjust shots:** click a gizmo to jump the timeline to its keyframe; drag
   a gizmo with Studio's move/rotate tools to re-aim that shot. Right-click
   the dot on the Camera lane to delete it (the gizmo disappears too).

FOV is captured per keyframe and interpolates on moves — capture two keyframes
with different zoom levels for dolly-zoom style shots.

Gizmos are never saved into your place file and vanish when the plugin unloads.

> **Tip:** capture a camera keyframe *before* turning Cam Preview on — while
> preview is on, the viewport shows the track, so capturing would just re-record
> the existing shot (the plugin warns and skips if you try).

---

## 6. The Effect Track (Particle / Sound / Light Events)

Trigger one-shot effects — particle bursts, sound cues, light flashes — exactly on the frame you choose, without any manual scripting at runtime.

**Supported effect types**

| Type | Detected class | Actions |
|------|---------------|---------|
| Particle | `ParticleEmitter` | `emit` (burst) · `on` (enable continuous) · `off` |
| Sound | `Sound` | `play` · `stop` |
| Toggle | `PointLight`, `SpotLight`, `SurfaceLight`, `Beam`, `Trail`, `Highlight` | `on` · `off` |

**Workflow**

1. In the **PROPS** section click **Track Effect**.
2. Click the part (or the effect instance itself) in the viewport. The plugin
   walks the part's descendants to find the first compatible effect and adds a
   **purple chip** with the effect's name and current action (`emit`, `on`, etc.).
   A **purple lane** appears in the timeline.
3. **Change the default action:** click the chip to cycle through that type's
   actions (`emit → on → off → emit …`). The action shown is the default for
   *new* events you place.
4. **Place an event:** navigate to a frame, then **double-click** the purple lane.
   An event is recorded at that frame using the current default action.
   - `emit` events also store the burst count (default 15).
5. **Right-click an event dot** to delete it.
6. **Untrack:** click `×` on the purple chip. The live link is removed but all
   events are preserved in the session (re-tracking the same effect restores them).
7. **Export** works as normal — if any effect has events, an `EffectTracks`
   `ModuleScript` is written alongside the scene.  `MultiAnimPlayer` loads it and
   fires events in its Heartbeat loop using a crossing-pointer so each event fires
   exactly once per playback.

> **Tip:** effects are always one-shot — there is no interpolation between event
> dots. To toggle a light on at frame 10 and off at frame 30, place an `on` event
> at frame 10 and an `off` event at frame 30.

---

## 7. Keyboard Shortcuts

All shortcuts work while the viewport has focus and are ignored while you're
typing in a textbox. The legend at the bottom of the panel lists them too.

| Key | Action |
|-----|--------|
| **`K`** | Add / update keyframe for all **active rigs and props** at the current frame |
| **`J`** | Step timeline **back** by Step frames (default 2) |
| **`L`** | Step timeline **forward** by Step frames (default 2) |
| **`C`** | Capture the viewport camera as a **camera keyframe** at the current frame |

The **Step** box in CONTROLS sets how far `J`/`L` jump.

---

## 8. Mouse Interactions — Complete Reference

| Where | Action | Result |
|---|---|---|
| `Simple` / `Advanced` | Click | Switch panel mode (session data untouched) |
| Rig button (panel) | Click | Exclusive-select that rig |
| `+ Rig` | Click | Clone Rig1 → next free RigN, auto-detected and ready |
| `Copy KF` | Click | Copy the active rig's keyframe at the current frame |
| `Paste KF` | Click | Paste the copied pose onto the active rig at the current frame |
| `Paste Mirrored` | Click | Paste with left↔right swapped and reflected |
| Rig part (viewport) | Click | Exclusive-select that rig in the panel |
| Prop button (panel) | Click | Toggle that prop active/inactive (multi-select) |
| Prop button `×` | Click | Untrack prop (data kept) |
| `Track Part` | Click | Track the viewport-selected BasePart as a prop |
| Any keyframe dot | Left-click | Jump timeline to that frame |
| Any keyframe dot | **Right-click** | **Delete** that keyframe (that lane only) |
| Rig / prop lane | Double-click | Jump there + add keyframe for that rig/prop |
| Camera lane | Double-click | Jump there + capture a camera keyframe |
| Camera gizmo (viewport) | Click | Jump timeline to that camera keyframe |
| Camera gizmo (viewport) | Drag / rotate | Re-aim that camera keyframe |
| `Track Effect` | Click | Track the selected part/effect as an effect lane |
| Effect chip | Click | Cycle default action (emit → on → off → …) |
| Effect chip `×` | Click | Untrack effect (events kept) |
| Effect lane | Double-click | Add an event at the current frame using the current default action |
| Effect event dot | **Right-click** | **Delete** that event |
| Scrubber | Drag | Scrub; auto-updates an existing keyframe at the departure frame |
| `\|◄` / `►\|` | Click | Jump to first / last frame |
| `◄` / `►` | Click | Step one frame back / forward |
| **Simple mode** `►` | Click | Step forward; captures the departure frame first if it's still empty |
| **Simple mode** `▶ Play` / `■ Stop` | Click | Play from the current frame to the end, or stop mid-playback |
| **Simple mode** `Delete Keyframe` | Click | Clear current frame's data, snap pose to the previous frame (cursor stays put) |
| **Simple mode** `Camera View` | Click | Create/arm the manipulable `SimpleCamera` part; toggle camera capture-on-step alongside rig/prop poses |
| **Simple mode** FOV box | Type + Tab/Enter | Set the `SimpleCamera`'s field of view (clamped 1–120) |
| **Simple mode** `Look Through` | Click | Slave the edit viewport to the `SimpleCamera` part live; toggle off to restore your viewport exactly |
| `SimpleCamera` part (viewport) | Move / rotate | Pose the camera like any rig or prop — captured the same way on step-forward |
| `💾 Save` | Click | Quick-save the session under the current scene name (no dialog) |

**Dot colours:** yellow = rig · teal = prop · orange = camera (move) · red = camera (cut) · purple = effect event.

---

## 9. Sessions: Save, Load, New

- Everything auto-saves to an `_autosave` slot one second after any change.
- **💾 Save** writes a quick-save to whatever name is in the scene box right
  now — no dialog, no overwrite confirmation. Use it for "save my progress"
  without committing to a new named snapshot.
- **Save As** stores a named snapshot (up to 30, newest first); **Load** brings
  one back — including props (re-linked by name), the camera track, and all effect events.
- **New** clears the whole session after a confirmation. Rigs are re-scanned;
  rest poses re-captured.
- Sessions survive closing/reopening the panel within a Studio session.

---

## 10. Export & In-Game Playback

Type a scene name (default `Scene_001`) and press **⬆ Export**. This writes to
`ServerStorage.MultiAnimationData.<SceneName>`:

| Item | Content |
|---|---|
| `<Rig>_Joints` | Standard Roblox `KeyframeSequence` per rig |
| `ScaleTracks` | Part sizes per keyframe |
| `RootTracks` | Whole-rig world positions (if the rig moved) |
| `PropTracks` | Prop CFrames (if props were tracked) |
| `CameraTrack` | Camera CFrames + FOV + cut flags (if camera keyframes exist) |
| `EffectTracks` | One-shot effect events: instance path + action + frame (if effects have events) |

The playback modules (`MultiAnimPlayer`, `CutsceneServer`, `CutsceneCamera`)
are deployed alongside automatically.

**Animation only** (server Script):

```lua
local player = require(game.ServerStorage.MultiAnimationData.MultiAnimPlayer)
player.play("Scene_001", { Rig1 = workspace.FIGURES.Rig1, Rig2 = workspace.FIGURES.Rig2 })
player.onFinished(function(name) print(name .. " done") end)
```

**Full cutscene with synchronized cameras** (all players see the same thing):

```lua
-- Server Script:
local Cutscene = require(game.ServerStorage.MultiAnimationData.CutsceneServer)
Cutscene.play("Scene_001", { Rig1 = workspace.FIGURES.Rig1, Rig2 = workspace.FIGURES.Rig2 })

-- LocalScript in StarterPlayerScripts:
require(game.ReplicatedStorage:WaitForChild("CutsceneCamera")).start()
```

Every client's camera follows the camera track on a shared clock and is
restored when the cutscene ends.

**Version-control your animations:** from a terminal, `mcp scene pull Scene_001`
saves the exported scene as diffable text under `MultiAnimation/scenes/` —
commit it with your code. `mcp scene push` restores it into Studio.

---

## 11. Simple Mode (Quick Capture)

A lighter, faster workflow for straightforward poses-on-a-timeline work —
no rig selection, no manual prop tracking, no "Add Keyframe" button to
remember.

**Turn it on:** click **Simple** in the mode toggle above RIGS IN SCENE
(switches back to **Advanced** any time — your session data is untouched
either way).

The panel collapses to just: a scrubber + frame counter, **▶ Play/Stop**,
**Delete Keyframe**, a **Camera View** toggle with FOV box and **Look
Through** toggle, and a scene name + Save/Export row.

**Everything in `Workspace.FIGURES` is tracked automatically** — R6 rigs the
same way Advanced mode tracks them, and any other part/model gets its
world-space CFrame tracked like an Advanced-mode prop. There's no "Track
Part" or "+ Rig" step; just put things in FIGURES.

**The core workflow — pose, then step:**

1. Pose everything in the viewport at the current frame.
2. Press **►** (step forward). If the frame you're *leaving* has no recorded
   data yet, your pose is captured there automatically — then the timeline
   advances and whatever's recorded at the new frame (if anything) is applied.
3. Repeat: pose, step, pose, step.

Because capture only happens on a frame that's still empty, scrubbing back
and forth across already-keyframed frames never overwrites them — only the
act of stepping *away from a fresh, unkeyframed frame* records it.

**Made a mistake?** Press **Delete Keyframe**. It clears the current frame's
data and snaps the viewport back to the previous frame's pose — but leaves
the timeline cursor right where it was. Re-pose, press ► again, and that
frame is captured fresh. This is the redo loop for Simple Mode.

**Play / Stop:** press **▶ Play** to play the recorded animation forward from
the current frame to the end of the timeline; the button flips to **■ Stop**
while playing. Press it again (or let it reach the end) to stop — the
viewport settles on whatever frame playback stopped at.

**Camera View:** toggling it on creates (or reuses) a **`SimpleCamera`**
part in `FIGURES` — a real, manipulable object you pose with Studio's normal
move/rotate tools, exactly like a rig or prop. The same step-forward rule
applies to it: leaving an empty frame with Camera View on captures the
camera part's CFrame and FOV alongside the poses. Set its field of view with
the **FOV** box next to the toggle (1–120).

**Look Through:** with Camera View on, toggle **Look Through** to slave your
edit-mode viewport to the `SimpleCamera` part live — move or rotate the part
and the viewport follows in real time, so you can frame a shot before
capturing it. Toggle it off to restore your own viewport exactly where you
left it. Look Through is rejected (no-op) if Camera View isn't on yet.

**Save / Export** work exactly as in Advanced mode, right there in the
Simple panel — no need to switch modes just to save your work or export
the scene.

---

## 12. Tips & Troubleshooting

| Symptom | Explanation / fix |
|---|---|
| Moving one limb drags the whole rig | The plugin panel isn't open (motors reconnected). Open it. |
| Rig looks broken / "cannot capture" warning | A Motor6D is missing — the warning names it. Fix the rig, then Refresh. |
| Keyframe didn't record for a rig | That rig wasn't the **active** one. Select it first. |
| Viewport stuck following the camera | Cam Preview is ON — toggle it off to restore your view. |
| Camera keyframe captured the wrong shot | You captured with Cam Preview ON (plugin warns and skips) — toggle off, frame the shot, press `C`. |
| Orange/red boxes left in the scene | Camera gizmos — they never save with the place and vanish on unload. Delete a camera keyframe to remove its gizmo. |
| Exported playback ignores my latest edits | Re-export, or run `mcp drift` / `mcp deploy` from a terminal. |
| In-game cutscene camera slightly ahead of rig motion | Known v1 caveat (~50–100 ms replication lag). |
| Undo behaves oddly during preview | Preview suspends the undo history while playing; it resumes on Stop. |
