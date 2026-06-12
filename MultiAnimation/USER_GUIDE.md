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
| **RIGS IN SCENE** | One button per detected rig (exclusive select — exactly one active), plus `↺ Refresh`, `Save As`, `Load`, `New` |
| **PROPS IN SCENE** | `Track Part` button + one toggle per tracked prop (multi-select), each with a `×` to untrack |
| **TIMELINE** | One keyframe lane per rig (yellow dots), the Camera lane (orange/red dots), and one lane per prop (teal dots) |
| **CONTROLS** | Frame navigation, step size, the scrubber, scene name, action buttons, and the camera row |

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

## 6. Keyboard Shortcuts

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

## 7. Mouse Interactions — Complete Reference

| Where | Action | Result |
|---|---|---|
| Rig button (panel) | Click | Exclusive-select that rig |
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
| Scrubber | Drag | Scrub; auto-updates an existing keyframe at the departure frame |
| `\|◄` / `►\|` | Click | Jump to first / last frame |
| `◄` / `►` | Click | Step one frame back / forward |

**Dot colours:** yellow = rig · teal = prop · orange = camera (move) · red = camera (cut).

---

## 8. Sessions: Save, Load, New

- Everything auto-saves to an `_autosave` slot one second after any change.
- **Save As** stores a named snapshot (up to 30, newest first); **Load** brings
  one back — including props (re-linked by name) and the camera track.
- **New** clears the whole session after a confirmation. Rigs are re-scanned;
  rest poses re-captured.
- Sessions survive closing/reopening the panel within a Studio session.

---

## 9. Export & In-Game Playback

Type a scene name (default `Scene_001`) and press **⬆ Export**. This writes to
`ServerStorage.MultiAnimationData.<SceneName>`:

| Item | Content |
|---|---|
| `<Rig>_Joints` | Standard Roblox `KeyframeSequence` per rig |
| `ScaleTracks` | Part sizes per keyframe |
| `RootTracks` | Whole-rig world positions (if the rig moved) |
| `PropTracks` | Prop CFrames (if props were tracked) |
| `CameraTrack` | Camera CFrames + FOV + cut flags (if camera keyframes exist) |

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

## 10. Tips & Troubleshooting

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
