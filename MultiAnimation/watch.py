#!/usr/bin/env python3
"""
watch.py — auto-build MultiAnimation plugin when Lua source files change.

Usage:
    python3 watch.py              # watch plugin/ and game/; build on any .lua change
    python3 watch.py --once       # build once and exit (same as running build.py)
    python3 watch.py --no-check   # skip the Studio compile-check before building

Watches:
    plugin/**/*.lua
    game/*.lua

On change: compile-checks the changed files in Studio (loadstring via MCP — catches
syntax errors before they reach a built plugin), then runs `python3 build.py`.
If Studio is unreachable the check is skipped with a warning and the build proceeds.

No external dependencies — uses pure-Python mtime polling.
Press Ctrl+C to stop.
"""

import os
import sys
import time
import subprocess

# Compile-check support comes from mcp.py (same repo root).
_MCP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _MCP_DIR not in sys.path:
    sys.path.insert(0, _MCP_DIR)
try:
    from mcp import check_file
except ImportError:
    check_file = None

# ── config ─────────────────────────────────────────────────────────────────────

HERE         = os.path.dirname(os.path.abspath(__file__))
WATCH_DIRS   = ["plugin", "game"]
POLL_INTERVAL = 0.5    # seconds between filesystem scans
DEBOUNCE      = 0.4    # seconds of quiet before triggering build

# ── helpers ────────────────────────────────────────────────────────────────────

def collect_mtimes() -> dict[str, float]:
    """Return {rel_path: mtime} for every .lua file in the watched dirs."""
    out = {}
    for d in WATCH_DIRS:
        root = os.path.join(HERE, d)
        if not os.path.isdir(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            for fname in filenames:
                if fname.endswith(".lua"):
                    full = os.path.join(dirpath, fname)
                    rel  = os.path.relpath(full, HERE)
                    try:
                        out[rel] = os.path.getmtime(full)
                    except OSError:
                        pass
    return out

def diff(old: dict, new: dict) -> list[str]:
    """Return list of paths that are new or have a newer mtime."""
    changed = []
    for path, mtime in new.items():
        if path not in old or old[path] != mtime:
            changed.append(path)
    return sorted(changed)

def build() -> bool:
    """Run build.py; return True on success."""
    result = subprocess.run(
        [sys.executable, os.path.join(HERE, "build.py")],
        cwd=HERE,
    )
    return result.returncode == 0

# ── compile check ──────────────────────────────────────────────────────────────

_mcp_warned = False

def run_checks(changed_files: list[str]) -> bool:
    """
    Compile-check changed files in Studio via loadstring.
    Returns False only on a confirmed compile error (build should be skipped).
    Unreachable Studio is non-fatal — warns once and lets the build proceed.
    """
    global _mcp_warned
    if check_file is None:
        return True

    for rel in changed_files:
        path = os.path.join(HERE, rel)
        if not os.path.exists(path):
            continue
        ok, msg = check_file(path)
        if ok:
            print(f"  check OK: {rel}")
        elif msg.startswith("mcp unreachable"):
            if not _mcp_warned:
                _mcp_warned = True
                print(f"  check skipped (Studio unreachable) — building anyway")
            return True
        else:
            print(f"  COMPILE ERROR in {rel}:")
            for line in msg.splitlines():
                print(f"    {line}")
            return False
    return True

# ── watch loop ─────────────────────────────────────────────────────────────────

def watch(no_check: bool = False):
    snapshot = collect_mtimes()
    file_count = len(snapshot)
    dirs_str = ", ".join(f"{d}/" for d in WATCH_DIRS if os.path.isdir(os.path.join(HERE, d)))
    check_str = "" if (check_file and not no_check) else " (compile-check off)"
    print(f"Watching {file_count} .lua file(s) in {dirs_str}{check_str}  (Ctrl+C to stop)\n")

    pending_since: float | None = None

    while True:
        time.sleep(POLL_INTERVAL)
        current = collect_mtimes()
        changed = diff(snapshot, current)

        if changed:
            if pending_since is None:
                pending_since = time.time()
                for p in changed:
                    print(f"  changed: {p}")
        else:
            if pending_since is not None and (time.time() - pending_since) >= DEBOUNCE:
                pending_since = None
                changed_files = diff(snapshot, current)
                snapshot = current

                if not no_check and not run_checks(changed_files):
                    print(f"  build skipped — fix the error and save again\n")
                    continue

                print(f"  building...", flush=True)
                ok = build()
                if ok:
                    print(f"  build OK  — reload plugin in Studio: Plugins → Manage Plugins\n")
                else:
                    print(f"  build FAILED\n")

        if pending_since is None and current.keys() != snapshot.keys():
            snapshot = current

# ── entry point ───────────────────────────────────────────────────────────────

def main():
    if "--once" in sys.argv:
        sys.exit(0 if build() else 1)

    try:
        watch(no_check="--no-check" in sys.argv)
    except KeyboardInterrupt:
        print("\nStopped.")

if __name__ == "__main__":
    main()
