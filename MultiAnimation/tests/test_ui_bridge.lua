-- test_ui_bridge.lua
-- UI integration tests — drives the LIVE plugin panel through the TestBridge
-- (CoreGui.__MultiAnimTestBridge, see plugin/core/TestBridge.lua).
--
-- Requires the plugin to be running (normal install or devsync). Mutates the
-- session only at a parking frame which is deleted again before exiting, and
-- restores the previously active rig and timeline frame.

local HttpService = game:GetService("HttpService")

local out = {}
local passed, failed = 0, 0

local function ok(label, cond, extra)
    if cond then
        passed += 1
        table.insert(out, "PASS  " .. label)
    else
        failed += 1
        table.insert(out, "FAIL  " .. label .. (extra and ("  >> " .. tostring(extra)) or ""))
    end
end

local function finish()
    table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
    table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
    return table.concat(out, "\n")
end

-- ── Bridge presence ───────────────────────────────────────────────────────────

local bridge = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
ok("TestBridge present (is the plugin running?)", bridge ~= nil)
if not bridge then return finish() end

local function call(cmd, args)
    local resJson = bridge:Invoke(cmd, args and HttpService:JSONEncode(args) or nil)
    return HttpService:JSONDecode(resJson)
end

-- ── Basic protocol ────────────────────────────────────────────────────────────

local r = call("ping")
ok("ping → pong", r.ok and r.result == "pong", r.err)

r = call("definitely_not_a_command")
ok("unknown command rejected cleanly", not r.ok and r.err ~= nil)

-- ── Rig discovery & selection ─────────────────────────────────────────────────

r = call("getRigs")
ok("getRigs returns at least 2 rigs", r.ok and type(r.result) == "table" and #r.result >= 2, r.err)
if not (r.ok and #r.result >= 1) then return finish() end
local rigs = r.result
local rigA = rigs[1]
local rigB = rigs[2] or rigs[1]

-- Remember user state to restore at the end.
local prevActive = call("getActiveRigs")
local prevFrame  = call("getCurrentFrame")

r = call("setActiveRig", { name = rigA })
ok("setActiveRig " .. rigA, r.ok, r.err)
r = call("getActiveRigs")
ok("exactly one active rig after select", r.ok and #r.result == 1 and r.result[1] == rigA,
    r.ok and table.concat(r.result, ",") or r.err)

r = call("setActiveRig", { name = rigB })
r = call("getActiveRigs")
ok("exclusive selection: switching deactivates previous",
    r.ok and #r.result == 1 and r.result[1] == rigB,
    r.ok and table.concat(r.result, ",") or r.err)

r = call("setActiveRig", { name = "NoSuchRig__" })
ok("selecting unknown rig errors", not r.ok)

-- ── Timeline navigation ───────────────────────────────────────────────────────

r = call("getFrameCount")
ok("getFrameCount > 0", r.ok and r.result > 0, r.err)
local frameCount = r.ok and r.result or 120

r = call("setFrame", { frame = 7 })
ok("setFrame 7", r.ok and r.result == 7, r.err)
r = call("getCurrentFrame")
ok("getCurrentFrame reflects setFrame", r.ok and r.result == 7)

r = call("setFrame", { frame = frameCount + 50 })
ok("setFrame clamps to frameCount", r.ok and r.result == frameCount, r.ok and r.result or r.err)

r = call("setFrame", { frame = 0 })
ok("setFrame clamps to 1", r.ok and r.result == 1)

-- ── Keyframe add/delete round-trip (parking frame, cleaned up) ────────────────

local PARK = frameCount - 7   -- unlikely to hold real keyframes

call("setActiveRig", { name = rigA })
r = call("getFrames", { rig = rigA })
local before = (r.ok and r.result) or {}
local parkOccupied = false
for _, f in ipairs(before) do
    if f == PARK then parkOccupied = true end
end

if parkOccupied then
    table.insert(out, "SKIP  keyframe round-trip (frame " .. PARK .. " already has user data)")
else
    call("setFrame", { frame = PARK })
    r = call("addKeyframe")
    ok("addKeyframe at parking frame " .. PARK, r.ok, r.err)

    r = call("getFrames", { rig = rigA })
    local found = false
    for _, f in ipairs((r.ok and r.result) or {}) do
        if f == PARK then found = true end
    end
    ok("keyframe recorded for active rig", found)

    -- Only the ACTIVE rig records — rigB must be untouched at PARK.
    if rigB ~= rigA then
        r = call("getFrames", { rig = rigB })
        local leaked = false
        for _, f in ipairs((r.ok and r.result) or {}) do
            if f == PARK then leaked = true end
        end
        ok("inactive rig did NOT record", not leaked)
    end

    r = call("deleteKeyframe", { rig = rigA, frame = PARK })
    ok("deleteKeyframe", r.ok, r.err)

    r = call("getFrames", { rig = rigA })
    ok("frame list restored after delete",
        r.ok and #r.result == #before,
        r.ok and ("#" .. #r.result .. " vs #" .. #before) or r.err)
end

-- ── Restore user state ────────────────────────────────────────────────────────

if prevFrame.ok then call("setFrame", { frame = prevFrame.result }) end
if prevActive.ok and prevActive.result[1] then
    call("setActiveRig", { name = prevActive.result[1] })
end

return finish()
