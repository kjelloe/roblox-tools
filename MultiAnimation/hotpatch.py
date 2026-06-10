#!/usr/bin/env python3
"""
hotpatch.py — push a single Lua module into the running Studio session
              without a full plugin rebuild or Studio restart.

Usage:
    python3 hotpatch.py game/MultiAnimPlayer.lua
    python3 hotpatch.py plugin/core/Interpolator.lua

Supported targets (PATCH_MAP below):
    game/MultiAnimPlayer.lua  → ServerStorage.MultiAnimationData.MultiAnimPlayer
    plugin/core/Exporter.lua  → requires plugin reload after patch (see note)

Notes:
    - Works immediately for game/ modules: any script that calls require() after
      the patch gets the new source (Roblox re-evaluates require when .Source changes).
    - Plugin core/ and ui/ modules are cached in Lua's require cache at plugin load
      time.  Patching their .Source in Studio has NO effect on the running plugin.
      For those, run build.py + reload the plugin in Studio instead.
    - test subcommand: add --test to also run the matching test file afterwards.

Examples:
    python3 hotpatch.py game/MultiAnimPlayer.lua
    python3 hotpatch.py game/MultiAnimPlayer.lua --test
"""

import os
import sys

_MCP_DIR = os.path.expanduser("~/GIT/Roblox")
if _MCP_DIR not in sys.path:
    sys.path.insert(0, _MCP_DIR)
try:
    from mcp import call_mcp
except ImportError:
    sys.exit("ERROR: cannot import mcp.py from ~/GIT/Roblox — is it present?")

HERE = os.path.dirname(os.path.abspath(__file__))

# ── target map ────────────────────────────────────────────────────────────────
# Maps relative source path → Studio instance path.
# Only game/ targets are effective without a plugin reload.

PATCH_MAP: dict[str, str] = {
    "game/MultiAnimPlayer.lua": "ServerStorage.MultiAnimationData.MultiAnimPlayer",
}

# ── helpers ───────────────────────────────────────────────────────────────────

def _lua_str(s: str) -> str:
    """Encode s as a double-quoted Lua string literal."""
    return (
        '"'
        + s.replace("\\", "\\\\")
           .replace('"',  '\\"')
           .replace("\n", "\\n")
           .replace("\r", "")
           .replace("\0", "")
        + '"'
    )

def _resolve_studio_path(studio_path: str) -> str:
    """
    Build a Lua expression that walks the dotted studio path from game root,
    using GetService() for top-level services.
    """
    parts = studio_path.split(".")
    lines = ["local _m = game"]
    for part in parts:
        # Try GetService first (handles ServerStorage, etc.), fall back to FindFirstChild.
        lines.append(
            f'_m = (pcall(function() return game:GetService({_lua_str(part)}) end) '
            f'and game:GetService({_lua_str(part)})) '
            f'or _m:FindFirstChild({_lua_str(part)})'
        )
    lines.append(f'assert(_m, "hotpatch: instance not found: {studio_path}")')
    return "\n".join(lines)

# ── patch ─────────────────────────────────────────────────────────────────────

def patch(rel_path: str, run_test: bool = False) -> None:
    # Normalise slashes.
    key = rel_path.replace("\\", "/")

    if key not in PATCH_MAP:
        print(f"WARNING: '{key}' is not in PATCH_MAP.")
        if key.startswith("plugin/"):
            print("  Plugin modules are cached at load time — rebuild + reload Studio instead.")
        else:
            print(f"  Add it to PATCH_MAP in hotpatch.py to enable hotpatching.")
        sys.exit(1)

    studio_path = PATCH_MAP[key]
    src_file = os.path.join(HERE, rel_path)
    if not os.path.exists(src_file):
        sys.exit(f"Source file not found: {src_file}")

    with open(src_file, encoding="utf-8") as f:
        source = f.read()

    lua = f"""
{_resolve_studio_path(studio_path)}
_m.Source = {_lua_str(source)}
return string.format("patched %s (%d bytes)", {_lua_str(studio_path)}, #_m.Source)
"""

    print(f"Patching {studio_path} ...", flush=True)
    texts, err = call_mcp("execute_luau", {"code": lua, "datamodel_type": "Edit"})
    for t in texts:
        print(f"  {t}")
    if err:
        sys.stderr.write(f"[mcp error] {err}\n")
        sys.stderr.flush()
        sys.exit(1)

    if run_test:
        _run_matching_test(key)


def _run_matching_test(key: str) -> None:
    """Try to run a test file that corresponds to the patched module."""
    # game/MultiAnimPlayer.lua → tests/test_player.lua (play-mode only, skip)
    # game/MultiAnimPlayer.lua → no edit-mode test; just notify.
    tests_dir = os.path.join(HERE, "tests")
    module_name = os.path.splitext(os.path.basename(key))[0].lower()

    # Find a test whose name contains the module name.
    candidates = [
        f for f in os.listdir(tests_dir)
        if f.startswith("test_") and f.endswith(".lua") and module_name in f
    ]

    if not candidates:
        print(f"\nNo matching test file found for '{module_name}' in tests/")
        return

    run_tests_script = os.path.join(HERE, "run_tests.py")
    if not os.path.exists(run_tests_script):
        print(f"\nrun_tests.py not found — skipping test run")
        return

    import subprocess as sp
    pattern = module_name
    print(f"\nRunning tests matching '{pattern}'...")
    sp.run([sys.executable, run_tests_script, pattern])

# ── entry point ───────────────────────────────────────────────────────────────

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    flags = [a for a in sys.argv[1:] if a.startswith("-")]

    if not args:
        print(__doc__)
        sys.exit(0)

    run_test = "--test" in flags

    for path in args:
        patch(path, run_test=run_test)

if __name__ == "__main__":
    main()
