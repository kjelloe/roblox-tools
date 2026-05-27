#!/usr/bin/env python3
"""
build.py — builds MultiAnimation.rbxmx from Lua source files
           and copies it to the Roblox Plugins folder.

Usage:
    python3 build.py           # build and install
    python3 build.py --dry-run # print XML to stdout only

Structure expected:
    plugin/
        init.server.lua        → root Script
        core/
            *.lua              → ModuleScripts in a "core" Folder
        ui/
            *.lua              → ModuleScripts in a "ui" Folder
    game/
        *.lua                  → not included in plugin build (in-game only)
"""

import os
import sys

PLUGINS_DIR_WSL = "/mnt/c/Users/kjell/AppData/Local/Roblox/Plugins"
OUTPUT_NAME     = "MultiAnimation.rbxmx"

# ── XML helpers ───────────────────────────────────────────────────────────────

def xe(s: str) -> str:
    """Escape XML attribute / text content (not needed for CDATA)."""
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def lua_cdata(source: str) -> str:
    """Wrap Lua source in a CDATA block, escaping any embedded ]]>."""
    return "<![CDATA[" + source.replace("]]>", "]]]]><![CDATA[>") + "]]>"

def module_xml(name: str, source: str, indent: int) -> str:
    pad = "  " * indent
    return (
        f'{pad}<Item class="ModuleScript">\n'
        f'{pad}  <Properties>\n'
        f'{pad}    <string name="Name">{xe(name)}</string>\n'
        f'{pad}    <ProtectedString name="Source">{lua_cdata(source)}</ProtectedString>\n'
        f'{pad}  </Properties>\n'
        f'{pad}</Item>'
    )

def folder_xml(name: str, children_xml: str, indent: int) -> str:
    pad = "  " * indent
    return (
        f'{pad}<Item class="Folder">\n'
        f'{pad}  <Properties>\n'
        f'{pad}    <string name="Name">{xe(name)}</string>\n'
        f'{pad}  </Properties>\n'
        f'{children_xml}\n'
        f'{pad}</Item>'
    )

def script_xml(name: str, source: str, children_xml: str) -> str:
    return (
        f'  <Item class="Script">\n'
        f'    <Properties>\n'
        f'      <string name="Name">{xe(name)}</string>\n'
        f'      <ProtectedString name="Source">{lua_cdata(source)}</ProtectedString>\n'
        f'      <bool name="Disabled">false</bool>\n'
        f'    </Properties>\n'
        f'{children_xml}\n'
        f'  </Item>'
    )

ROBLOX_HEADER = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<roblox '
    'xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" '
    'version="4">\n'
)
ROBLOX_FOOTER = '</roblox>\n'

# ── file readers ──────────────────────────────────────────────────────────────

def read(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()

def modules_from_dir(dir_path: str, indent: int) -> str:
    """Build module XML for every .lua file in dir_path, alphabetically."""
    parts = []
    for fname in sorted(os.listdir(dir_path)):
        if not fname.endswith(".lua"):
            continue
        mod_name = fname[:-4]  # strip .lua
        source   = read(os.path.join(dir_path, fname))
        parts.append(module_xml(mod_name, source, indent))
    return "\n".join(parts)

# ── build ─────────────────────────────────────────────────────────────────────

def build(dry_run: bool = False) -> None:
    here       = os.path.dirname(os.path.abspath(__file__))
    plugin_dir = os.path.join(here, "plugin")

    # core Folder
    core_children = modules_from_dir(os.path.join(plugin_dir, "core"), indent=4)
    core_xml = folder_xml("core", core_children, indent=3)

    # ui Folder
    ui_children = modules_from_dir(os.path.join(plugin_dir, "ui"), indent=4)
    ui_xml = folder_xml("ui", ui_children, indent=3)

    children_xml = core_xml + "\n" + ui_xml

    # game Folder — included so MultiAnimPlayer can be required in-game
    game_dir = os.path.join(here, "game")
    game_lua_files = [f for f in os.listdir(game_dir) if f.endswith(".lua")]
    if game_lua_files:
        game_children = modules_from_dir(game_dir, indent=4)
        game_xml = folder_xml("game", game_children, indent=3)
        children_xml += "\n" + game_xml

    # Root Script
    init_source = read(os.path.join(plugin_dir, "init.server.lua"))
    root_xml = script_xml("MultiAnimation", init_source, children_xml)

    output = ROBLOX_HEADER + root_xml + "\n" + ROBLOX_FOOTER

    if dry_run:
        print(output)
        return

    out_path = os.path.join(PLUGINS_DIR_WSL, OUTPUT_NAME)
    os.makedirs(PLUGINS_DIR_WSL, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(output)
    print(f"[build] Written → {out_path}")
    print("[build] Reload the plugin in Studio: Plugins → Manage Plugins → reload MultiAnimation")

# ── entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    build(dry_run=dry)
