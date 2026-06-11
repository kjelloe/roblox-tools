#!/usr/bin/env python3
"""
devsync.py — hot-reload the MultiAnimation plugin without restarting Studio.

Usage:
    python3 devsync.py install     install the dev-loader plugin (one Studio restart needed)
    python3 devsync.py uninstall   remove the dev loader, restore the normal plugin
    python3 devsync.py push        push the source tree to Studio once (hot reload)
    python3 devsync.py             watch mode: push on every .lua save (Ctrl+C to stop)

Workflow:
    1. python3 devsync.py install      (renames MultiAnimation.rbxmx → .disabled so the
                                        two plugins don't fight; installs the dev loader)
    2. Restart Studio once             (loads MultiAnimationDevLoader)
    3. python3 devsync.py              (first push boots the plugin; every save reloads it)
    4. python3 devsync.py uninstall    (back to the normal build.py / reload workflow)

How it works:
    Pushes plugin source as fresh ModuleScripts into CoreGui.__MultiAnimDevSrc
    (CoreGui is never saved with the place) and bumps a Version attribute.
    The dev-loader plugin re-runs init.server.lua on each bump; the teardown
    closure in init.server.lua (_G.__MultiAnimTeardown) dismantles the previous
    instance first.  Fresh ModuleScript instances bust Luau's require cache.

Tip: run `mcp daemon start` first — pushes drop from ~30 s to under a second.
"""

import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
for p in (REPO, HERE):
    if p not in sys.path:
        sys.path.insert(0, p)

try:
    from mcp import call_mcp, _lua_str
except ImportError:
    sys.exit("ERROR: cannot import mcp.py from the repo root")

from build import script_xml, ROBLOX_HEADER, ROBLOX_FOOTER, PLUGINS_DIR_WSL

SRC_NAME     = "__MultiAnimDevSrc"
LOADER_NAME  = "MultiAnimationDevLoader.rbxmx"
PLUGIN_NAME  = "MultiAnimation.rbxmx"
PUSH_DIRS    = ["core", "ui"]      # plugin/<dir>/*.lua
POLL_INTERVAL = 0.5
DEBOUNCE      = 0.4

# ── install / uninstall ───────────────────────────────────────────────────────

def install():
    loader_src = open(os.path.join(HERE, "plugin", "devloader.lua"), encoding="utf-8").read()
    xml = ROBLOX_HEADER + script_xml("MultiAnimationDevLoader", loader_src, "") + "\n" + ROBLOX_FOOTER

    os.makedirs(PLUGINS_DIR_WSL, exist_ok=True)
    out = os.path.join(PLUGINS_DIR_WSL, LOADER_NAME)
    with open(out, "w", encoding="utf-8") as f:
        f.write(xml)
    print(f"[install] Dev loader written → {out}")

    normal = os.path.join(PLUGINS_DIR_WSL, PLUGIN_NAME)
    if os.path.exists(normal):
        os.rename(normal, normal + ".disabled")
        print(f"[install] {PLUGIN_NAME} → {PLUGIN_NAME}.disabled (so the two don't fight)")

    print("[install] Restart Studio once, then run: python3 devsync.py")


def uninstall():
    loader = os.path.join(PLUGINS_DIR_WSL, LOADER_NAME)
    if os.path.exists(loader):
        os.remove(loader)
        print(f"[uninstall] Removed {LOADER_NAME}")

    disabled = os.path.join(PLUGINS_DIR_WSL, PLUGIN_NAME + ".disabled")
    if os.path.exists(disabled):
        os.rename(disabled, os.path.join(PLUGINS_DIR_WSL, PLUGIN_NAME))
        print(f"[uninstall] Restored {PLUGIN_NAME}")

    print("[uninstall] Restart Studio to load the normal plugin again.")

# ── push ──────────────────────────────────────────────────────────────────────

def _lua_root():
    return f"""
local cg = game:GetService("CoreGui")
local root = cg:FindFirstChild({_lua_str(SRC_NAME)})
if not root then
    root = Instance.new("Folder")
    root.Name = {_lua_str(SRC_NAME)}
    root.Parent = cg
end
"""

def _push_folder(folder_name: str, dir_path: str) -> tuple[bool, str]:
    """Replace one source folder (fresh ModuleScripts bust the require cache)."""
    parts = [_lua_root(), f"""
local old = root:FindFirstChild({_lua_str(folder_name)})
if old then old:Destroy() end
local fold = Instance.new("Folder")
fold.Name = {_lua_str(folder_name)}
fold.Parent = root
"""]
    n = 0
    for fname in sorted(os.listdir(dir_path)):
        if not fname.endswith(".lua"):
            continue
        src = open(os.path.join(dir_path, fname), encoding="utf-8").read()
        parts.append(f"""
do
    local m = Instance.new("ModuleScript")
    m.Name = {_lua_str(fname[:-4])}
    m.Source = {_lua_str(src)}
    m.Parent = fold
end
""")
        n += 1
    parts.append(f'return "{folder_name}: {n} module(s)"')
    texts, err = call_mcp("execute_luau", {"code": "".join(parts), "datamodel_type": "Edit"}, timeout=30)
    return err is None, "\n".join(texts) or (err or "")


def _push_init_and_bump() -> tuple[bool, str]:
    init_src = open(os.path.join(HERE, "plugin", "init.server.lua"), encoding="utf-8").read()
    lua = _lua_root() + f"""
local old = root:FindFirstChild("init")
if old then old:Destroy() end
local sv = Instance.new("StringValue")
sv.Name = "init"
sv.Value = {_lua_str(init_src)}
sv.Parent = root
root:SetAttribute("Version", (root:GetAttribute("Version") or 0) + 1)
return "version " .. root:GetAttribute("Version")
"""
    texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"}, timeout=30)
    return err is None, "\n".join(texts) or (err or "")


def push() -> bool:
    t0 = time.time()
    for d in PUSH_DIRS:
        ok, msg = _push_folder(d, os.path.join(HERE, "plugin", d))
        if not ok:
            print(f"[push] FAILED on {d}/: {msg}")
            return False
        print(f"[push] {msg}")
    ok, msg = _push_folder("game", os.path.join(HERE, "game"))
    if not ok:
        print(f"[push] FAILED on game/: {msg}")
        return False
    print(f"[push] {msg}")

    # init last — the Version bump is what triggers the loader to boot,
    # so all modules must already be in place when it fires.
    ok, msg = _push_init_and_bump()
    if not ok:
        print(f"[push] FAILED on init: {msg}")
        return False
    print(f"[push] {msg} — hot-reloaded in {time.time() - t0:.1f}s")
    return True

# ── watch mode ────────────────────────────────────────────────────────────────

def _collect_mtimes() -> dict:
    out = {}
    dirs = [os.path.join(HERE, "plugin"), os.path.join(HERE, "game")]
    for root_dir in dirs:
        for dirpath, _, files in os.walk(root_dir):
            for f in files:
                if f.endswith(".lua") and f != "devloader.lua":
                    full = os.path.join(dirpath, f)
                    try:
                        out[full] = os.path.getmtime(full)
                    except OSError:
                        pass
    return out


def watch():
    try:
        from mcp import check_file
    except ImportError:
        check_file = None

    print("devsync watch — pushing current state first...\n")
    push()
    snapshot = _collect_mtimes()
    print(f"\nWatching {len(snapshot)} file(s); every save hot-reloads the plugin. (Ctrl+C to stop)\n")

    pending = None
    while True:
        time.sleep(POLL_INTERVAL)
        current = _collect_mtimes()
        changed = [p for p, m in current.items() if snapshot.get(p) != m]

        if changed:
            if pending is None:
                pending = time.time()
                for p in changed:
                    print(f"  changed: {os.path.relpath(p, HERE)}")
        elif pending is not None and time.time() - pending >= DEBOUNCE:
            pending = None
            changed_files = [p for p, m in current.items() if snapshot.get(p) != m]
            snapshot = current

            bad = False
            if check_file:
                for p in changed_files:
                    ok, msg = check_file(p)
                    if not ok and not msg.startswith("mcp unreachable"):
                        print(f"  COMPILE ERROR in {os.path.relpath(p, HERE)}:\n    {msg}")
                        bad = True
            if bad:
                print("  push skipped — fix the error and save again\n")
                continue

            push()
            print()

        if pending is None and current.keys() != snapshot.keys():
            snapshot = current

# ── entry point ───────────────────────────────────────────────────────────────

def main():
    sub = sys.argv[1] if len(sys.argv) > 1 else "watch"
    if sub == "install":
        install()
    elif sub == "uninstall":
        uninstall()
    elif sub == "push":
        sys.exit(0 if push() else 1)
    elif sub == "watch":
        try:
            watch()
        except KeyboardInterrupt:
            print("\nStopped.")
    else:
        print(__doc__)
        sys.exit(1)

if __name__ == "__main__":
    main()
