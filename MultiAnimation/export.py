#!/usr/bin/env python3
"""
export.py — packages MultiAnimation for distribution.

Produces ./export/:
  MultiAnimation.rbxmx              — Studio plugin (drop into Roblox/Plugins/)
  ServerStorage_MultiAnimationData.rbxm  — server ModuleScripts (insert into ServerStorage)
  ReplicatedStorage.rbxm            — client ModuleScripts (insert into ReplicatedStorage)
  how-to-use.md                     — setup instructions
  USER_GUIDE.html                   — styled HTML render of USER_GUIDE.md

Also regenerates ./USER_GUIDE.html next to USER_GUIDE.md.

Usage:
    python3 export.py
    python3 export.py --selftest     # run the md→html converter self-checks
"""

import html
import os
import re
import shutil
import sys
import time

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


# ── USER_GUIDE.md → USER_GUIDE.html ───────────────────────────────────────────
# Minimal GFM subset covering everything USER_GUIDE.md uses: h1–h3, hr, fenced
# code (also inside list items), tables (incl. escaped \| in cells), blockquotes,
# ordered/unordered lists with continuation lines, bold/italic/inline code/links.

GUIDE_CSS = """\
  :root {
    --bg: #1b1d21; --panel: #24262b; --border: #3a3d44; --text: #d6d8dd;
    --muted: #9a9da6; --accent: #ffc83c; --link: #6fb8ff; --code-bg: #17181c;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text); line-height: 1.55;
         font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
  .wrap { max-width: 960px; margin: 0 auto; padding: 2rem 1.2rem 4rem; }
  h1 { color: var(--accent); border-bottom: 2px solid var(--border); padding-bottom: .4rem; }
  h2 { color: var(--accent); margin-top: 2.2rem; border-bottom: 1px solid var(--border);
       padding-bottom: .25rem; }
  h3 { color: var(--text); margin-top: 1.6rem; }
  a { color: var(--link); }
  hr { border: 0; border-top: 1px solid var(--border); margin: 2rem 0; }
  code { background: var(--code-bg); border: 1px solid var(--border); border-radius: 4px;
         padding: .08rem .35rem; font-size: .9em; }
  pre { background: var(--code-bg); border: 1px solid var(--border); border-radius: 8px;
        padding: .8rem 1rem; overflow-x: auto; }
  pre code { background: none; border: 0; padding: 0; font-size: .85em; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: .92em; }
  th, td { border: 1px solid var(--border); padding: .45rem .6rem; text-align: left;
           vertical-align: top; }
  th { background: var(--panel); color: var(--accent); }
  tr:nth-child(even) td { background: var(--panel); }
  blockquote { border-left: 4px solid var(--accent); background: var(--panel);
               margin: 1rem 0; padding: .6rem 1rem; border-radius: 0 8px 8px 0;
               color: var(--muted); }
  blockquote p { margin: 0; }
  nav.toc { background: var(--panel); border: 1px solid var(--border); border-radius: 8px;
            padding: .8rem 1.2rem; margin: 1.4rem 0; }
  nav.toc ol { margin: .3rem 0; padding-left: 1.4rem; }
  .generated { color: var(--muted); font-size: .8rem; margin-top: 3rem;
               border-top: 1px solid var(--border); padding-top: .6rem; }
"""

def _md_inline(s: str) -> str:
    s = html.escape(s, quote=False)
    spans: list[str] = []
    def stash(m):
        spans.append(m.group(1))
        return f"\x00{len(spans) - 1}\x00"
    s = re.sub(r"`([^`]+)`", stash, s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    s = re.sub(r"\x00(\d+)\x00", lambda m: "<code>" + spans[int(m.group(1))] + "</code>", s)
    return s

def _slug(text: str) -> str:
    t = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE).strip().lower()
    return re.sub(r"\s+", "-", t)

def _split_cells(row: str) -> list[str]:
    row = row.strip().strip("|")
    row = row.replace("\\|", "\x01")
    return [c.strip().replace("\x01", "|") for c in row.split("|")]

def md_to_html_body(md: str) -> tuple[list[str], list[tuple[str, str]]]:
    lines = md.splitlines()
    out: list[str] = []
    toc: list[tuple[str, str]] = []
    para: list[str] = []
    i, n = 0, len(lines)

    def flush_para():
        if para:
            out.append("<p>" + _md_inline(" ".join(para)) + "</p>")
            para.clear()

    while i < n:
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            flush_para()
            i += 1
            code = []
            while i < n and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            i += 1
            indents = [len(c) - len(c.lstrip()) for c in code if c.strip()]
            d = min(indents) if indents else 0
            code = [c[d:] if len(c) >= d else c for c in code]
            out.append("<pre><code>" + html.escape("\n".join(code)) + "</code></pre>")
            continue

        if stripped in ("---", "***") and not para:
            out.append("<hr>")
            i += 1
            continue

        m = re.match(r"(#{1,3}) (.*)", line)
        if m:
            flush_para()
            level, text = len(m.group(1)), m.group(2)
            sid = _slug(text)
            if level == 2:
                toc.append((sid, text))
            out.append(f'<h{level} id="{sid}">{_md_inline(text)}</h{level}>')
            i += 1
            continue

        if stripped.startswith(">"):
            flush_para()
            quote = []
            while i < n and lines[i].strip().startswith(">"):
                quote.append(lines[i].strip()[1:].lstrip())
                i += 1
            out.append("<blockquote><p>"
                       + _md_inline(" ".join(q for q in quote if q))
                       + "</p></blockquote>")
            continue

        if (stripped.startswith("|") and i + 1 < n
                and re.match(r"^\|[\s:|-]+\|?$", lines[i + 1].strip())):
            flush_para()
            header = _split_cells(stripped)
            i += 2
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append(_split_cells(lines[i]))
                i += 1
            t = ["<table><thead><tr>"]
            t += [f"<th>{_md_inline(h)}</th>" for h in header]
            t.append("</tr></thead><tbody>")
            for r in rows:
                t.append("<tr>" + "".join(f"<td>{_md_inline(c)}</td>" for c in r) + "</tr>")
            t.append("</tbody></table>")
            out.append("".join(t))
            continue

        m = re.match(r"\s*([-*]|\d+\.) (.*)", line)
        if m and stripped:
            flush_para()
            ordered = m.group(1)[0].isdigit()
            start = int(m.group(1)[:-1]) if ordered else 1
            items: list[str] = []
            cur = None
            while i < n:
                lm = re.match(r"\s*([-*]|\d+\.) (.*)", lines[i])
                if lm and lines[i].strip():
                    if cur is not None:
                        items.append(cur)
                    cur = lm.group(2)
                    i += 1
                elif (lines[i].strip() and lines[i][:1] in (" ", "\t")
                        and not lines[i].strip().startswith("```")):
                    cur += " " + lines[i].strip()
                    i += 1
                else:
                    break
            if cur is not None:
                items.append(cur)
            tag = "ol" if ordered else "ul"
            attr = f' start="{start}"' if ordered and start != 1 else ""
            out.append(f"<{tag}{attr}>"
                       + "".join(f"<li>{_md_inline(it)}</li>" for it in items)
                       + f"</{tag}>")
            continue

        if not stripped:
            flush_para()
            i += 1
            continue

        para.append(stripped)
        i += 1

    flush_para()
    return out, toc

def render_user_guide(md: str) -> str:
    blocks, toc = md_to_html_body(md)
    nav = ""
    if toc:
        nav = ("<nav class=\"toc\"><strong>Contents</strong><ol>"
               + "".join(f'<li><a href="#{sid}">{html.escape(text)}</a></li>'
                         for sid, text in toc)
               + "</ol></nav>")
        # Insert the TOC after the intro (before the first h2).
        for idx, b in enumerate(blocks):
            if b.startswith("<h2"):
                blocks.insert(idx, nav)
                break
    stamp = time.strftime("%Y-%m-%d %H:%M")
    return (
        "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<title>MultiAnimation — User Guide</title>\n"
        "<!-- GENERATED from USER_GUIDE.md by export.py — do not edit by hand. -->\n"
        f"<style>\n{GUIDE_CSS}</style>\n</head>\n<body>\n<div class=\"wrap\">\n"
        + "\n".join(blocks)
        + f"\n<p class=\"generated\">Generated from USER_GUIDE.md by export.py — {stamp}. "
          "Do not edit by hand.</p>\n"
        "</div>\n</body>\n</html>\n"
    )

def build_user_guide_html() -> None:
    src = os.path.join(HERE, "USER_GUIDE.md")
    with open(src, encoding="utf-8") as f:
        page = render_user_guide(f.read())
    for dst in (os.path.join(HERE, "USER_GUIDE.html"),
                os.path.join(EXPORT_DIR, "USER_GUIDE.html")):
        with open(dst, "w", encoding="utf-8") as f:
            f.write(page)
        print(f"[export] User guide  → {dst}")

def selftest() -> None:
    sample = "\n".join([
        "# Title",
        "",
        "Intro with **bold**, *italic*, `a < b`, and a [link](https://x.y).",
        "",
        "---",
        "",
        "## Section One",
        "",
        "| Key | Action |",
        "|-----|--------|",
        "| `\\|◄` / `►\\|` | Jump to first / last |",
        "",
        "1. first",
        "2. second",
        "   continued",
        "",
        "```lua",
        "if a < b then print(\"hi\") end",
        "```",
        "",
        "3. third",
        "",
        "> **Tip:** stay calm.",
    ])
    blocks, toc = md_to_html_body(sample)
    joined = "\n".join(blocks)
    checks = [
        ('<h2 id="section-one">' in joined,               "h2 with slug id"),
        (toc == [("section-one", "Section One")],         "toc collected"),
        ("<strong>bold</strong>" in joined,               "bold"),
        ("<em>italic</em>" in joined,                     "italic"),
        ("<code>a &lt; b</code>" in joined,               "inline code escaped"),
        ('<a href="https://x.y">link</a>' in joined,      "link"),
        ("<td><code>|◄</code> / <code>►|</code></td>" in joined, "escaped pipes in table cell"),
        ("second continued" in joined,                    "list continuation line"),
        ('<ol start="3">' in joined,                      "ordered list resumes numbering"),
        ("print(&quot;hi&quot;)" in joined,               "fenced code escaped"),
        ("<blockquote><p><strong>Tip:</strong> stay calm.</p></blockquote>" in joined, "blockquote"),
    ]
    failed = [label for ok, label in checks if not ok]
    if failed:
        sys.exit("[selftest] FAILED: " + ", ".join(failed))
    print(f"[selftest] {len(checks)} checks passed")

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
    build_user_guide_html()
    print("[export] Done — share the contents of ./export/")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        main()
