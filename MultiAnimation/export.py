#!/usr/bin/env python3
"""
export.py — packages MultiAnimation for distribution.

Produces ./export/:
  MultiAnimation.rbxmx              — Studio plugin (drop into Roblox/Plugins/)
  ServerStorage_MultiAnimationData.rbxm  — server ModuleScripts (insert into ServerStorage)
  ReplicatedStorage.rbxm            — client ModuleScripts (insert into ReplicatedStorage)
  how-to-use.md                     — setup instructions

Usage:
    python3 export.py
"""

import os
import shutil
import sys

HERE         = os.path.dirname(os.path.abspath(__file__))
GAME_DIR     = os.path.join(HERE, "game")
EXPORT_DIR   = os.path.join(HERE, "export")

# Where build.py writes the compiled plugin on WSL / Windows.
PLUGINS_DIR  = "/mnt/c/Users/kjell/AppData/Local/Roblox/Plugins"
PLUGIN_FILE  = "MultiAnimation.rbxmx"

# ── XML helpers (same conventions as build.py) ────────────────────────────────

def xe(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def lua_cdata(source: str) -> str:
    return "<![CDATA[" + source.replace("]]>", "]]]]><![CDATA[>") + "]]>"

ROBLOX_HEADER = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<roblox '
    'xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
    'version="4">\n'
)
ROBLOX_FOOTER = '</roblox>\n'

def module_item(name: str, source: str, indent: int = 1) -> str:
    pad = "  " * indent
    return (
        f'{pad}<Item class="ModuleScript">\n'
        f'{pad}  <Properties>\n'
        f'{pad}    <string name="Name">{xe(name)}</string>\n'
        f'{pad}    <ProtectedString name="Source">{lua_cdata(source)}</ProtectedString>\n'
        f'{pad}  </Properties>\n'
        f'{pad}</Item>'
    )

def folder_item(name: str, children: str, indent: int = 1) -> str:
    pad = "  " * indent
    return (
        f'{pad}<Item class="Folder">\n'
        f'{pad}  <Properties>\n'
        f'{pad}    <string name="Name">{xe(name)}</string>\n'
        f'{pad}  </Properties>\n'
        f'{children}\n'
        f'{pad}</Item>'
    )

def rbxm(items_xml: str) -> str:
    return ROBLOX_HEADER + items_xml + "\n" + ROBLOX_FOOTER

def read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()

def game(fname: str) -> str:
    return read(os.path.join(GAME_DIR, fname))

# ── build ─────────────────────────────────────────────────────────────────────

def build_plugin() -> None:
    """Run build.py to regenerate the plugin, then copy to export/."""
    import subprocess
    print("[export] Building plugin...")
    result = subprocess.run(
        [sys.executable, os.path.join(HERE, "build.py")],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        sys.exit(f"[export] build.py failed — aborting")
    # build.py writes MultiAnimation.rbxmx.disabled when devsync is installed.
    src = os.path.join(PLUGINS_DIR, PLUGIN_FILE)
    if not os.path.exists(src):
        src = src + ".disabled"
    dst = os.path.join(EXPORT_DIR, PLUGIN_FILE)
    shutil.copy2(src, dst)
    print(f"[export] Plugin → {dst}")


def build_server_rbxm() -> None:
    """ServerStorage/MultiAnimationData — server-side ModuleScripts."""
    scripts = [
        ("MultiAnimDataServer",  "MultiAnimDataServer.lua"),
        ("MultiAnimPlayer",      "MultiAnimPlayer.lua"),
        ("CutsceneServer",       "CutsceneServer.lua"),
        ("CutsceneCamera",       "CutsceneCamera.lua"),
        ("SpawnedEffectRunner",  "SpawnedEffectRunner.lua"),
    ]
    children = "\n".join(
        module_item(name, game(fname), indent=2)
        for name, fname in scripts
    )
    folder = folder_item("MultiAnimationData", children, indent=1)
    path = os.path.join(EXPORT_DIR, "ServerStorage_MultiAnimationData.rbxm")
    with open(path, "w", encoding="utf-8") as f:
        f.write(rbxm(folder))
    print(f"[export] Server scripts → {path}")


def build_client_rbxm() -> None:
    """ReplicatedStorage — client-side ModuleScripts."""
    scripts = [
        ("CutscenePlayer",       "CutscenePlayer.lua"),
        ("CutsceneCamera",       "CutsceneCamera.lua"),
        ("LetterboxGui",         "LetterboxGui.lua"),
        ("PlayerRigProxy",       "PlayerRigProxy.lua"),
        ("SpawnedEffectRunner",  "SpawnedEffectRunner.lua"),
        ("SubtitleGui",          "SubtitleGui.lua"),
    ]
    items = "\n".join(
        module_item(name, game(fname), indent=1)
        for name, fname in scripts
    )
    path = os.path.join(EXPORT_DIR, "ReplicatedStorage.rbxm")
    with open(path, "w", encoding="utf-8") as f:
        f.write(rbxm(items))
    print(f"[export] Client scripts → {path}")


HOW_TO_USE = """\
# MultiAnimation — Setup Guide

You received three files:

| File | What it is |
|------|-----------|
| `MultiAnimation.rbxmx` | Studio plugin for creating animations |
| `ServerStorage_MultiAnimationData.rbxm` | Server-side runtime scripts |
| `ReplicatedStorage.rbxm` | Client-side runtime scripts |

---

## 1. Install the Studio plugin

1. Close Roblox Studio if it is open.
2. Copy `MultiAnimation.rbxmx` to your Plugins folder:
   ```
   %LOCALAPPDATA%\\Roblox\\Plugins\\
   ```
   (Paste that path into Windows Explorer's address bar.)
3. Open Studio — **MultiAnimation** appears in the Plugins tab.

---

## 2. Add the runtime scripts to your game

These steps let your game actually play back cutscenes created with the plugin.

**Insert into ServerStorage:**

1. In Studio, open your place.
2. In the menu: **Model → Insert from File** (or right-click `ServerStorage` → Insert from File).
3. Select `ServerStorage_MultiAnimationData.rbxm`.
4. A folder named `MultiAnimationData` appears inside `ServerStorage`.

**Insert into ReplicatedStorage:**

1. Right-click `ReplicatedStorage` → Insert from File.
2. Select `ReplicatedStorage.rbxm`.
3. Six ModuleScripts appear: `CutscenePlayer`, `CutsceneCamera`, `LetterboxGui`,
   `PlayerRigProxy`, `SpawnedEffectRunner`, `SubtitleGui`.

---

## 3. Add the server bootstrap Script

Add a **Script** to `ServerScriptService` with this content:

```lua
require(game.ServerStorage.MultiAnimationData.MultiAnimDataServer).setup()
```

This must run before any client calls `CutscenePlayer.play()`.

---

## 4. Add a LocalScript to start the cutscene

In `StarterPlayerScripts` (or `StarterCharacterScripts`), add a **LocalScript**:

```lua
local CutscenePlayer = require(game.ReplicatedStorage.CutscenePlayer)

local handle = CutscenePlayer.play(
    "MyScene",           -- name you gave the scene in the plugin
    {
        Rig1 = workspace.FIGURES.Rig1,   -- map rig names to workspace models
    },
    { movieMode = true }
)
-- handle.stop()  -- call to cancel early
```

The plugin's **Playback** tab generates this snippet for you with the correct
scene name, rig names, and options pre-filled.

---

## 5. Export a scene from the plugin

1. Open Studio with the plugin active.
2. Create or load a scene in the **Simple** tab.
3. Click **Export** — scene data is written to `ServerStorage.MultiAnimationData.<SceneName>`.
4. Press F5 to play-test; the LocalScript above will play the cutscene.

---

## Folder structure when complete

```
ServerStorage/
  MultiAnimationData/
    MultiAnimDataServer   ← runtime bridge (from rbxm)
    MultiAnimPlayer       ← animation engine (from rbxm)
    CutsceneServer        ← server sync (from rbxm)
    CutsceneCamera        ← camera track source for CutsceneServer (from rbxm)
    SpawnedEffectRunner   ← particle effects (from rbxm)
    <SceneName>/          ← exported by the plugin (one folder per scene)

ReplicatedStorage/
  CutscenePlayer          ← main playback API (from rbxm)
  CutsceneCamera          ← client camera driver (from rbxm)
  LetterboxGui            ← cinematic black bars (from rbxm)
  PlayerRigProxy          ← player character resolver (from rbxm)
  SpawnedEffectRunner     ← spawned effect firing (from rbxm)
  SubtitleGui             ← subtitle display (from rbxm)

ServerScriptService/
  SetupScript             ← your Script calling .setup()

StarterPlayerScripts/
  YourLocalScript         ← your LocalScript calling CutscenePlayer.play()
```
"""


def build_how_to() -> None:
    path = os.path.join(EXPORT_DIR, "how-to-use.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write(HOW_TO_USE)
    print(f"[export] Instructions → {path}")


def main() -> None:
    os.makedirs(EXPORT_DIR, exist_ok=True)
    build_plugin()
    build_server_rbxm()
    build_client_rbxm()
    build_how_to()
    print("[export] Done — share the contents of ./export/")


if __name__ == "__main__":
    main()
