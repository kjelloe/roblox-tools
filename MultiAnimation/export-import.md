# MultiAnimation — Session File Export / Import

Transfers a complete animation session (all keyframes, props, camera, effects, subtitles, spawned effects) between Roblox Studio projects or between machines that both have the MultiAnimation plugin installed.

---

## Export (PC / project 1)

1. Finish or checkpoint your animation in MultiAnimation (any mode).
2. In the **RIGS IN SCENE** section of the plugin panel, click **Export File**.
   - The plugin serialises the session to JSON and stores it as a `StringValue` named after your current scene (e.g. `Scene_001`) inside `ServerStorage.MultiAnimSessions`.
   - The StringValue is automatically selected in Explorer so the next step is one click.
3. In Studio's **Explorer**, right-click the highlighted StringValue → **Save to File…** → save as a `.rbxm` file.
4. Transfer the `.rbxm` to the other PC (USB drive, cloud storage, etc.).

---

## Import (PC / project 2)

Requirements on the target project:
- MultiAnimation plugin installed and active.
- Same rig/prop/effect object names exist in the scene (same structure the original session referenced). Rigs must be in `Workspace.FIGURES` or tagged with the scene's `MAnim:<name>` tags.

Steps:
1. In Studio's **Explorer**, right-click the root → **Insert from File…** → select the `.rbxm`.
   - The `StringValue` is inserted somewhere in the tree (often under the selected node or directly in the place).
2. Select the imported `StringValue` by clicking it in Explorer.
3. In the MultiAnimation panel, click **Import File**.
   - The plugin reads the selected StringValue, restores all session data, and re-links rigs/props/effects by name.
   - If you are in **Simple** mode with a scene name and tag folder set, tags are re-applied automatically before scanning.

---

## What is transferred

| Data | Included |
|---|---|
| Joint keyframes (all rigs) | ✅ |
| Scale keyframes | ✅ |
| Root / whole-model movement | ✅ |
| Easing per keyframe | ✅ |
| Prop CFrame keyframes | ✅ |
| Camera keyframes (CFrame, FOV, cut/move) | ✅ |
| Effect track events | ✅ |
| Spawned effects (Explosion, Smoke, Sound) | ✅ |
| Subtitle track | ✅ |
| FPS and frame count | ✅ |
| Scene name and tag folder name | ✅ |
| Named saved sessions (plugin:SetSetting) | ❌ (not portable) |
| Exported KeyframeSequences in ServerStorage | ❌ (use `.rbxm` of the scene folder instead) |

---

## Notes

- **Session data vs exported data**: this feature transfers the *editable session* so you can continue animating on PC 2. It is not a replacement for the normal **⬆ Export** workflow, which writes `KeyframeSequences` and playback modules into `ServerStorage.MultiAnimationData`.
- **Large sessions**: `StringValue` in Roblox can hold strings up to ~200 KB. Very long animations with many rigs, props, and hundreds of keyframes may approach this limit. If the export silently produces an empty or truncated value, use `mcp scene pull/push` (developer tooling) instead.
- **Autosave is local**: the `_autosave` slot and all named saves in **Load** are stored in `plugin:SetSetting`, which is local to the machine. They are not included in the `.rbxm`.
- **Re-linking**: props and effect instances are matched by name via `workspace:FindFirstChild(name, true)`. If a name does not exist in the target scene, that track's data is preserved in the recorder (and will appear in the export) but has no live viewport link.
- **Developer alternative**: `mcp scene pull <name>` / `mcp scene push <name>` does the same transfer via JSON files on disk, suitable for version control or CI pipelines.
