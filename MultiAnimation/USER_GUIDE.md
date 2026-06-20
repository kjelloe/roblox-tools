# MultiAnimation — User Guide

A Roblox Studio plugin for animating **multiple rigs (R6, R15, or custom), props,
and a cutscene camera** on one shared timeline — entirely in edit mode — and playing
the result back in-game, synchronized across all players.

This guide is for the person *using* the plugin. For developer tooling
(building, testing, hot-reload) see the repo `README.md`; for internals see
`ARCHITECTURE.md`.

---

## 1. Getting Started

**Install:** the plugin lives at
`%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx` (built by `build.py`).
After installing, restart Studio. The plugin appears in the **Plugins toolbar**
(not in "Manage Plugins" — that's marketplace-only).

**Scene setup:** put your rigs in a folder called `FIGURES` in Workspace (or use
tag-based scenes — see Simple Mode below):

```
Workspace
└── FIGURES
    ├── Rig1   (R6: Humanoid + Torso + Motor6Ds, or R15: Humanoid + UpperTorso)
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
| **Mode toggle** | `Simple` / `Advanced` / `Playback` buttons, always visible — switches the whole panel layout without losing session data. See §11 Simple Mode, §12 Playback Tab. |
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

## 7. Keyframe Easing

Every keyframe stores an **easing curve** that shapes the interpolation from that
keyframe toward the next one. The default is Linear (constant speed). Six styles
are available:

| Style | Effect |
|---|---|
| **Linear** | Constant speed — the default |
| **Ease In** | Starts slow, accelerates (cubic in) |
| **Ease Out** | Arrives slow, decelerates (cubic out) |
| **EaseInOut** | Slow start *and* end, faster in the middle |
| **Constant** | Hold the pose until the next keyframe (step / hold) |
| **Bounce** | Overshoots and bounces near the target |

**Advanced mode:** right-click any keyframe dot (rig, prop, camera, or effect lane)
to open a context menu with all six easing options and a Delete option. The menu
appears at cursor position; clicking outside it (or any option) dismisses it.

**Simple mode:** the **`Ease: Linear`** button (to the right of `+ Add Frame`) opens
the same easing picker. The selected easing is stamped onto all rigs, props, and the
camera when you press `+ Add Frame`. Navigating to a frame that already has a keyframe
syncs the button to show its stored easing automatically.

---

## 8. Keyboard Shortcuts


All shortcuts work while the viewport has focus and are ignored while you're
typing in a textbox. The legend at the bottom of the panel lists them too.

| Key | Action |
|-----|--------|
| **`K`** | **Advanced:** Add / update keyframe for all active rigs and props · **Simple:** same as `+ Add Frame` |
| **`J`** | Step timeline **back** by Step frames (default 2) |
| **`L`** | Step timeline **forward** by Step frames (default 2) |
| **`C`** | Capture the viewport camera as a **camera keyframe** at the current frame |

The **Step** box in CONTROLS sets how far `J`/`L` jump.

---

## 9. Mouse Interactions — Complete Reference

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
| Any keyframe dot (Advanced) | **Right-click** | Open context menu: set easing curve (6 styles) or Delete that keyframe |
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
| **Simple mode** `Ease: Linear` | Click | Open easing picker: Linear / Ease In / Ease Out / EaseInOut / Constant / Bounce. Sets the outgoing curve for the next frame capture. Auto-syncs when you navigate to an existing keyframe. |
| **Simple mode** `+ Add Frame` | Click | Capture current frame's pose. At the blank end slot: grow the timeline by 1 and advance cursor. At an existing frame: update its data and advance cursor by 1 (no grow). |
| **Simple mode** `+ Insert` | Click | Insert a blank frame at the current position, shift all subsequent frame data right by 1 |
| **Simple mode** `▶ Play` / `■ Stop` | Click | Play from the current frame to the end, or stop mid-playback |
| **Simple mode** `Del Frame` | Click | Delete the current frame's data, shift all subsequent frames left by 1, shrink the timeline |
| **Simple mode** `Camera View` | Click | ON: create/show the manipulable `SimpleCamera` part and arm camera capture on `+ Add Frame`. OFF: hide the part (kept in FIGURES for next toggle-on). |
| **Simple mode** FOV box | Type + Tab/Enter | Set the `SimpleCamera`'s field of view (clamped 1–120) |
| **Simple mode** `Look Through` | Click | Slave the viewport to the `SimpleCamera`'s view, then fly freely with Studio's normal edit-camera controls; toggle off to restore your original viewport exactly |
| `SimpleCamera` part (viewport) | Move / rotate | Pose the camera like any rig or prop — captured the same way on step-forward; shows a wireframe FOV-frustum outline |
| **Simple mode** `Onion Skin: OFF/ON` | Click | Toggle ghost poses: semi-transparent red = previous keyframe, blue = next keyframe; ghosts refresh on every frame change |
| **Simple mode** FPS box (nav row) | Type + Tab/Enter | Set playback speed (1–999 fps, default 30). Affects `▶ Play` speed; saved with the session. |
| `💾 Save` | Click | Quick-save the session under the current scene name (no dialog) |

**Dot colours:** yellow = rig · teal = prop · orange = camera (move) · red = camera (cut) · purple = effect event.

---

## 10. Sessions: Save, Load, New

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

## 11. Export & In-Game Playback

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

## 12. Simple Mode (Quick Capture)

A lighter, faster workflow for straightforward poses-on-a-timeline work —
no rig selection, no manual prop tracking, no "Add Keyframe" button to
remember.

**Turn it on:** click **Simple** in the mode toggle above RIGS IN SCENE
(switches back to **Advanced** any time — your session data is untouched
either way).

The panel collapses to just: a scrubber + frame counter, a nav row with
**Del Frame**, **+ Insert**, **▶ Play/Stop**, **+ Add Frame**, and an **FPS
box** (default 30), a **Camera View** toggle with FOV box and **Look Through**
toggle, and a scene name + Save/Export row.

**Everything in `Workspace.FIGURES` is tracked automatically** — R6 and R15 rigs
the same way Advanced mode tracks them, and any other part/model gets its
world-space CFrame tracked like an Advanced-mode prop. There's no "Track
Part" or "+ Rig" step; just put things in FIGURES.

**The core workflow:**

- **`+ Add Frame`** — captures the current frame's pose. When the cursor is at
  the blank end slot it grows the timeline by one and moves the cursor there.
  When the cursor is at an *existing* frame it overwrites that frame's data and
  advances the cursor by 1 without growing the timeline (useful for re-posing a
  frame you navigated back to). The typical forward loop is:
  pose → **+ Add Frame** → pose → **+ Add Frame** → …
- **`+ Insert`** — shifts all frames *after* the current one right by 1,
  growing the timeline by 1 without overwriting what's already there. The
  cursor stays on the current frame, which is now blank — ready for a new
  pose. Use this to slip a new key between two existing ones.
- **`Del Frame`** — removes the current frame's data, shifts all subsequent
  frames left by 1 (so frame numbers stay contiguous), and shrinks the
  timeline by 1. The cursor lands on min(current, newEnd).

**Made a mistake?** Press **Del Frame**. The frame is deleted and subsequent
data shifts to close the gap — re-pose at the current cursor position and
press **+ Add Frame** again.

**Auto-save on navigation:** any time you click a different frame icon (or
use the nav buttons), the frame you're leaving is automatically re-captured —
so posing and moving on is safe without remembering to press **+ Add Frame**
each time. The same capture fires at the start of a scrubber drag. Changes
still auto-save to the `_autosave` slot within a second.

**Play / Stop:** press **▶ Play** to play the recorded animation forward from
the current frame to the end of the timeline; the button flips to **■ Stop**
while playing. Press it again (or let it reach the end) to stop — the
viewport settles on whatever frame playback stopped at. The **FPS box** (right
of the nav row, default 30) controls playback speed; type a number and press
Tab or Enter to apply. The setting is saved with the session.

**Camera View:** toggling it on creates (or reuses) a **`SimpleCamera`**
part in `FIGURES` — a real, manipulable object you pose with Studio's normal
move/rotate tools, exactly like a rig or prop. A wireframe outline on the
part shows its field of view and aim direction at a glance (an apex plus a
far rectangle sized from the FOV — not a solid shape, so it won't block
your view of anything behind it). When Camera View is on, pressing **+ Add
Frame** captures the camera part's CFrame and FOV alongside all rig/prop
poses. Set the camera's field of view with the **FOV** box next to the
toggle (1–120); the wireframe redraws to match. Toggling Camera View **off**
hides the `SimpleCamera` part and its FOV outline — the part stays in FIGURES
so it reappears in the same position when you turn Camera View back on.

**Look Through:** with Camera View on, toggle **Look Through** to slave your
edit-mode viewport to the `SimpleCamera` part's current view. Once it's on,
fly around with Studio's normal edit-camera controls (right-drag to look,
WASD/QE to move, scroll to zoom) — the camera part follows your viewport
live, so the gizmo doesn't fight your navigation. Toggle Look Through off to
restore your own viewport exactly where it was *before* you turned it on
(not wherever you flew to). Look Through is rejected (no-op) if Camera View
isn't on yet.

**Onion Skin:** click **Onion Skin: OFF** in the camera row to toggle ghost
rendering. When on, the previous and next keyframed frames are shown as
semi-transparent ghost poses overlaid on the real rigs — **red** for the
frame behind and **blue** for the frame ahead. Ghosts update automatically
each time you change frames. Toggle off to clear them. (Ghosts are never
saved with the place file and vanish on plugin unload.)

**Save / Export** work exactly as in Advanced mode, right there in the
Simple panel — no need to switch modes just to save your work or export
the scene.

---

## 13. Playback Tab — Use Animations In-Game

The **Playback** tab (third mode button) lets you select any saved scene and
generate a Lua snippet ready to paste into a game `LocalScript`. It also
supports animating a **player's actual character** (or a local clone of it)
as one of the rigs.

### How to set up in-game playback

1. **Server side** — add a `Script` to `ServerScriptService`:
   ```lua
   require(game.ServerStorage.MultiAnimationData.MultiAnimDataServer).setup()
   ```
   Deploy `MultiAnimDataServer.lua` to `ServerStorage.MultiAnimationData` (via
   `mcp deploy` or manual paste). This creates the `MultiAnimGetScene`
   RemoteFunction that clients call to fetch scene data.

2. **Client side** — deploy `CutscenePlayer.lua`, `PlayerRigProxy.lua`, and
   `LetterboxGui.lua` to `ReplicatedStorage`.

3. **Paste the snippet** from the Playback tab into a `LocalScript`. Example:
   ```lua
   local CutscenePlayer = require(game.ReplicatedStorage.CutscenePlayer)
   local handle = CutscenePlayer.play(
       "MyScene",
       {
           Rig1 = workspace.FIGURES.Rig1,
           Rig2 = { player = game.Players.LocalPlayer, mode = "clone" },
       },
       { fps = 30, loop = false, movieMode = true }
   )
   -- handle.stop() to cancel early
   ```

### Rig mapping modes

| Mode | What it does |
|------|-------------|
| **Fixed rig** | Uses the workspace rig as-is (default) |
| **LocalPlayer — clone** | Clones the local player's character; strips scripts and Humanoid; hides the original during playback; restores on finish |
| **LocalPlayer — direct** | Animates the player's real character; sets `PlatformStand = true` to suppress physics; restores on finish |
| **UserId — clone** | Same as clone but looks up the player by UserId (must be in the same server) |
| **UserId — direct** | Same as direct but by UserId |

Both R6 and R15 player characters are supported.

### Parameters

| Control | Effect |
|---------|--------|
| **◄ / ►** scene selector | Cycle through saved sessions |
| **FPS box** | Override playback speed (1–999; default uses the scene's recorded fps) |
| **Loop** | Restart automatically when the last frame is reached |
| **Movie Mode** | Shows cinematic black bars (top/bottom 10%) during playback |

### Movie Mode (letterbox)

Toggling **Movie Mode** on adds two black bars that cover the top and bottom
10% of the screen via a `ScreenGui` in `PlayerGui` (DisplayOrder 200). They
are automatically removed when playback finishes or `handle.stop()` is called.

---

## 14. Tips & Troubleshooting

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
