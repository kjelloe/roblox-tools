#!/usr/bin/env python3
"""
watch.py — auto-build MultiAnimation plugin when Lua source files change.

Usage:
    python3 watch.py              # watch plugin/ and game/; build on any .lua change
    python3 watch.py --once       # build once and exit (same as running build.py)

Watches:
    plugin/**/*.lua
    game/*.lua

On change: runs `python3 build.py` from this directory.

No external dependencies — uses pure-Python mtime polling.
Press Ctrl+C to stop.
"""

import os
import sys
import time
import subprocess

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

# ── watch loop ─────────────────────────────────────────────────────────────────

def watch():
    snapshot = collect_mtimes()
    file_count = len(snapshot)
    dirs_str = ", ".join(f"{d}/" for d in WATCH_DIRS if os.path.isdir(os.path.join(HERE, d)))
    print(f"Watching {file_count} .lua file(s) in {dirs_str}  (Ctrl+C to stop)\n")

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
                snapshot = current
                print(f"  building...", flush=True)
                ok = build()
                if ok:
                    print(f"  build OK  — reload plugin in Studio: Plugins → Manage Plugins\n")
                else:
                    print(f"  build FAILED\n")

        if current.keys() != snapshot.keys():
            snapshot = current

# ── entry point ───────────────────────────────────────────────────────────────

def main():
    if "--once" in sys.argv:
        sys.exit(0 if build() else 1)

    try:
        watch()
    except KeyboardInterrupt:
        print("\nStopped.")

if __name__ == "__main__":
    main()
