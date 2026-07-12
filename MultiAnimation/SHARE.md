# Sharing the MultiAnimation Plugin

There are two components to share:

| Component | What it is | Who needs it |
|-----------|-----------|--------------|
| **Plugin** (`.rbxmx`) | The Studio editor | Anyone who wants to create animations |
| **Game scripts** (`.rbxm`) | Runtime playback modules | Any game that wants to play back cutscenes |

---

## Option 1 — Share the built file directly

Best for sharing with one or a few people.

### Plugin

1. Build the plugin (from the repo root):
   ```
   cd MultiAnimation
   python3 build.py
   ```
   Output: `%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx`

2. Send that file to your friend (zip, email, Drive, etc.).

3. Your friend drops it in their own Plugins folder:
   ```
   %LOCALAPPDATA%\Roblox\Plugins\
   ```

4. Restart Studio — the plugin appears in the Plugins tab automatically.

### Game scripts

The plugin is for editing only. To play back cutscenes in a live game, the runtime scripts must also be in the game.

1. Build the distribution bundle (from `MultiAnimation/`):
   ```
   python3 export.py
   ```
   Output in `export/`: `MultiAnimation.rbxmx` (plugin),
   `ServerStorage_MultiAnimationData.rbxm` (server modules: MultiAnimDataServer,
   MultiAnimPlayer, CutsceneServer, CutsceneCamera, SpawnedEffectRunner),
   `ReplicatedStorage.rbxm` (client modules: CutscenePlayer, CutsceneCamera,
   LetterboxGui, PlayerRigProxy, SpawnedEffectRunner, SubtitleGui), and
   `how-to-use.md` (setup instructions).

2. Share the contents of `export/`.

3. Your friend follows `how-to-use.md`: insert the two `.rbxm` files into
   `ServerStorage` / `ReplicatedStorage` via Studio → Insert from File.

4. They call `require(game.ServerStorage.MultiAnimationData.MultiAnimDataServer).setup()` server-side before any playback is triggered (see `USER_GUIDE.md` for the full setup snippet).

---

## Option 2 — Publish to the Roblox Creator Store

Best for broader distribution or public release.

### Plugin

1. Open Studio with the plugin loaded and active.
2. Go to **Plugins → Publish as Plugin**.
3. Fill in: name, description, icon image (512×512 PNG recommended).
4. Set visibility to **Public** (or Private if you want invite-only).
5. Click **Publish**.

Anyone can then find and install it from the **Plugin Marketplace** inside Studio (Plugins → Find Plugins).

Updates are pushed by republishing from the same account — installed copies update automatically when users restart Studio.

### Game scripts

Publish the runtime scripts as a free **Model** on the Creator Store:

1. In Studio, select the root folder containing all game scripts.
2. Right-click → **Save to Roblox** (or use the Asset Manager).
3. Set to Public, add a clear description.
4. Share the model URL or Asset ID.

Users insert it into their game via the Toolbox → Creator Store search.

---

## Quick reference

| Task | File / location |
|------|----------------|
| Built plugin | `%LOCALAPPDATA%\Roblox\Plugins\MultiAnimation.rbxmx` |
| Friend's plugin folder | `%LOCALAPPDATA%\Roblox\Plugins\` |
| Rebuild after code changes | `python3 build.py` in `MultiAnimation/` |
| Runtime setup docs | `USER_GUIDE.md` → Playback section |
