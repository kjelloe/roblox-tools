#!/usr/bin/env python3
"""
run_tests.py — run MultiAnimation test suite against live Studio.

Usage:
    python3 run_tests.py              # run all tests/test_*.lua
    python3 run_tests.py prop         # run tests matching *prop*
    python3 run_tests.py -v           # verbose: print every PASS/FAIL line
    python3 run_tests.py prop -v      # filter + verbose

Prerequisites:
    - Roblox Studio open with the place loaded (MCP plugin active)
    - Studio session initialised (list_roblox_studios → set_active_studio)

Skipped automatically:
    - test_player.lua  (requires play mode; run manually as a Script in ServerScriptService)

Exit code: 0 if all tests pass, 1 if any fail or Studio is unreachable.
"""

import os
import re
import sys
import time
import glob

# Import call_mcp from the sibling mcp.py helper.
_MCP_DIR = os.path.expanduser("~/GIT/Roblox")
if _MCP_DIR not in sys.path:
    sys.path.insert(0, _MCP_DIR)
try:
    from mcp import call_mcp
except ImportError:
    sys.exit("ERROR: cannot import mcp.py from ~/GIT/Roblox — is it present?")

# ── config ─────────────────────────────────────────────────────────────────────

TESTS_DIR    = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests")
SKIP_FILES   = {
    "test_player.lua",    # requires play mode; use `mcp playtest` instead
    "test_scrubber.lua",  # interactive diagnostic — needs real mouse movement over the panel
}
TIMEOUT_SECS = 25                    # per-test MCP timeout

# ── output parsing ─────────────────────────────────────────────────────────────

_SUMMARY_RE = re.compile(r"===\s*(\d+)\s*passed,\s*(\d+)\s*failed")

def parse_result(texts: list[str]) -> tuple[int, int, bool, list[str]]:
    """
    Returns (passed, failed, all_passed, lines).
    lines = every PASS/FAIL line from the output (for verbose mode).
    A file whose output lacks the `=== N passed, M failed ===` summary line is
    reported as failed — otherwise its cases silently count as 0/0.
    """
    full = "\n".join(texts)
    passed, failed = 0, 0
    detail_lines = []
    saw_summary = False

    for line in full.splitlines():
        m = _SUMMARY_RE.search(line)
        if m:
            saw_summary = True
            passed = int(m.group(1))
            failed = int(m.group(2))
        if line.startswith("PASS  ") or line.startswith("FAIL  "):
            detail_lines.append(line)

    if not saw_summary:
        detail_lines.append("FAIL  missing '=== N passed, M failed ===' summary line")
        return passed, 1, False, detail_lines

    all_passed = "ALL TESTS PASSED" in full
    return passed, failed, all_passed, detail_lines

# ── discovery ──────────────────────────────────────────────────────────────────

def discover(pattern: str = "") -> list[str]:
    """Return sorted list of test file paths matching the optional pattern."""
    all_files = sorted(glob.glob(os.path.join(TESTS_DIR, "test_*.lua")))
    out = []
    for f in all_files:
        name = os.path.basename(f)
        if name in SKIP_FILES:
            continue
        if pattern and pattern not in name:
            continue
        out.append(f)
    return out

# ── runner ─────────────────────────────────────────────────────────────────────

def run_all(files: list[str], verbose: bool) -> bool:
    if not files:
        print("No test files found.")
        return True

    print(f"Running {len(files)} test file(s) against Studio...\n")

    col = max(len(os.path.basename(f)[:-4]) for f in files) + 2
    total_passed = total_failed = 0
    any_error = False
    wall_start = time.time()

    for path in files:
        name = os.path.basename(path)[:-4]  # strip .lua
        label = name.ljust(col)

        with open(path, encoding="utf-8") as fh:
            code = fh.read()

        # Live UI tests flake roughly once per full run (timing against the
        # Studio event loop). A failed/errored file gets exactly one retry;
        # the retry's result counts, and the status is marked so flakes stay
        # visible instead of silently vanishing.
        t0 = time.time()
        retried = False
        texts, err = call_mcp("execute_luau", {"code": code, "datamodel_type": "Edit"},
                              timeout=TIMEOUT_SECS)
        if (err and not texts) or not parse_result(texts)[2]:
            retried = True
            time.sleep(0.5)
            texts, err = call_mcp("execute_luau", {"code": code, "datamodel_type": "Edit"},
                                  timeout=TIMEOUT_SECS)
        elapsed = time.time() - t0

        if err and not texts:
            print(f"  {label}  ERROR  {err}")
            any_error = True
            continue

        passed, failed, ok, detail = parse_result(texts)
        total_passed += passed
        total_failed += failed

        status = "PASS" if ok else "FAIL"
        if retried and ok:
            status = "PASS*"   # * = passed on retry (flaked once)
        count  = f"{passed}/{passed + failed}"
        print(f"  {label}  {count:>7}  {status}  ({elapsed:.1f}s)")

        if verbose or not ok:
            for line in detail:
                print(f"      {line}")
            if not ok:
                # Print full raw output so the failure is diagnosable.
                print("    --- raw output ---")
                for t in texts:
                    for l in t.splitlines():
                        print(f"    {l}")

    wall = time.time() - wall_start
    total = total_passed + total_failed
    bar = "-" * (col + 25)
    print(f"\n  {bar}")
    overall = "PASS" if (total_failed == 0 and not any_error) else "FAIL"
    print(f"  {'Total:'.ljust(col)}  {total_passed}/{total:>3}  {overall}  ({wall:.1f}s)")

    skipped = set(os.path.basename(f) for f in
                  glob.glob(os.path.join(TESTS_DIR, "test_*.lua"))) & SKIP_FILES
    if skipped:
        print(f"\n  Skipped (play-mode only): {', '.join(sorted(skipped))}")

    return total_failed == 0 and not any_error

# ── copy-sync pre-flight (pure local, no Studio) ──────────────────────────────
# Several functions are deliberately duplicated across game modules ("keep in
# sync" comments) because game/ modules cannot require each other at runtime.
# Nothing enforced the sync until now: a fix applied to one copy silently
# missed the others. Fails the run before any Studio call if copies drift.

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))

# Each entry: canonical name → list of (relative path, header regex). The first
# file is the reference. Test inline copies are included: headless tests
# exercise their own copies of module logic, so an un-mirrored fix would pass
# tests while the real module (or the test) lies.
_SYNCED_BLOCKS = {
    "easedAlpha": [
        ("game/MultiAnimPlayer.lua",          r"^local function easedAlpha\("),
        ("game/CutscenePlayer.lua",           r"^local function easedAlpha\("),
        ("game/CutsceneCamera.lua",           r"^local function easedAlpha\("),
        ("tests/test_easing_core.lua",        r"^local function easedAlpha\("),
    ],
    "cubicCF": [
        ("game/MultiAnimPlayer.lua",          r"^local function cubicCF\("),
        ("game/CutscenePlayer.lua",           r"^local function cubicCF\("),
        ("game/CutsceneCamera.lua",           r"^local function cubicCF\("),
        ("tests/test_smooth_interp.lua",      r"^local function cubicCF\("),
    ],
    "smoothCF": [
        ("game/MultiAnimPlayer.lua",          r"^local function smoothCF\("),
        ("game/CutscenePlayer.lua",           r"^local function smoothCF\("),
        ("game/CutsceneCamera.lua",           r"^local function smoothCF\("),
        ("tests/test_smooth_interp.lua",      r"^local function smoothCF\("),
    ],
    "smoothV3": [
        ("game/MultiAnimPlayer.lua",          r"^local function smoothV3\("),
        ("game/CutscenePlayer.lua",           r"^local function smoothV3\("),
        ("tests/test_smooth_interp.lua",      r"^local function smoothV3\("),
    ],
    "LEGACY_POSE_TO_JOINT": [
        ("game/MultiAnimPlayer.lua",          r"^local LEGACY_POSE_TO_JOINT = {"),
        ("game/MultiAnimDataServer.lua",      r"^local LEGACY_POSE_TO_JOINT = {"),
    ],
    "SpawnedEffect PRESETS": [
        ("plugin/core/SpawnedEffectRunner.lua", r"^SpawnedEffectRunner\.PRESETS = {"),
        ("tests/test_spawned_effects_core.lua", r"^local PRESETS = {"),
    ],
}

def _normalise(block: str) -> str:
    """Comment- and whitespace-insensitive body (headers legitimately differ,
    e.g. `SpawnedEffectRunner.PRESETS = {` vs the test's `local PRESETS = {`)."""
    lines = block.splitlines()[1:]   # drop the header line
    lines = [re.sub(r"--.*$", "", line) for line in lines]
    body = re.sub(r"\s+", "", "\n".join(lines))
    return re.sub(r",}", "}", body)   # trailing commas are cosmetic

def _extract_block(source: str, header_re: str) -> str | None:
    """Grab a top-level block from its header line to the first column-0 `end`/`}`."""
    m = re.search(header_re, source, re.M)
    if not m:
        return None
    lines = source[m.start():].splitlines()
    block = []
    for line in lines:
        block.append(line)
        if line.rstrip() in ("end", "}"):
            break
    return "\n".join(block)

def check_copy_sync() -> bool:
    ok = True
    for name, entries in _SYNCED_BLOCKS.items():
        blocks = {}
        for rel, header_re in entries:
            with open(os.path.join(ROOT_DIR, rel), encoding="utf-8") as f:
                raw = _extract_block(f.read(), header_re)
            blocks[rel] = _normalise(raw) if raw is not None else None
            if blocks[rel] is None:
                print(f"  *** COPY SYNC: {name} not found in {rel} ***")
                ok = False
        ref = entries[0][0]
        for rel, _ in entries[1:]:
            if blocks[rel] is not None and blocks[ref] is not None and blocks[rel] != blocks[ref]:
                print(f"  *** COPY DRIFT: {name} differs between {ref} and {rel} ***")
                ok = False
    if not ok:
        print("  *** keep-in-sync copies have drifted — fix before trusting the suite ***\n")
    return ok

# ── build version pre-flight ───────────────────────────────────────────────────

_VERSION_CHECK_CODE = """
local ok, res = pcall(function()
    local bf = game:GetService("CoreGui"):WaitForChild("__MultiAnimTestBridge", 3)
    local hs = game:GetService("HttpService")
    local raw = bf:Invoke("getPluginBuildHash", nil)
    local r = hs:JSONDecode(raw)
    return r.ok and tostring(r.result) or "error"
end)
return ok and res or "unreachable"
"""

def check_plugin_version() -> None:
    hash_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".build_hash")
    if not os.path.exists(hash_file):
        return
    with open(hash_file) as f:
        expected = f.read().strip()
    texts, err = call_mcp("execute_luau",
                          {"code": _VERSION_CHECK_CODE, "datamodel_type": "Edit"},
                          timeout=8)
    if err or not texts:
        return
    running = texts[0].strip() if texts else ""
    if running != expected:
        print(f"  *** WARNING: plugin not reloaded after last build ***")
        print(f"  *** Built: {expected}  Running: {running} ***")
        print(f"  *** Plugins → Manage Plugins → reload MultiAnimation ***\n")


# ── entry point ───────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    verbose = "-v" in args
    args = [a for a in args if a != "-v"]
    pattern = args[0] if args else ""

    files = discover(pattern)
    if not files:
        print(f"No test files match pattern '{pattern}' in {TESTS_DIR}")
        sys.exit(1)

    sync_ok = check_copy_sync()
    check_plugin_version()
    ok = run_all(files, verbose)
    sys.exit(0 if (ok and sync_ok) else 1)

if __name__ == "__main__":
    main()
