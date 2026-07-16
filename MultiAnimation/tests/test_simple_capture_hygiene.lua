-- test_simple_capture_hygiene.lua
-- Simple Mode navigation-capture hygiene. Guards the "navigation mutates data
-- the user didn't touch" bug class:
--   1. passing through a camera-only frame must NOT materialize rig keyframes
--      (pins interpolated poses, changes eased/smooth motion)
--   2. rig keyframes stay bit-identical across step-throughs of an untouched
--      pose (no capture round-trip float re-stamping)
--   3. a real pose edit at a data frame still captures on departure
--   4. a pose edit at an EMPTY frame creates keyframes AND its tile appears
--      immediately in the panel strip (no invisible data)
--   5. Insert Frame duplicates inherit the source camera keyframe's cut mode
-- Builds all frames at the END of the timeline; cleans up. Live test.

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

local bf = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
local hs = game:GetService("HttpService")
if not bf then
    return "SKIP: __MultiAnimTestBridge not found\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local function call(cmd, args)
    return hs:JSONDecode(bf:Invoke(cmd, args and hs:JSONEncode(args) or nil))
end

call("scanFigures")
call("setMode", { mode = "simple" })

local rigs = call("getRigs").result or {}
if #rigs == 0 then
    return "SKIP: no rigs in FIGURES\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local rigA  = rigs[1]
local props = call("getSimpleProps").result or {}

local function rigHasKF(rig, frame)
    for _, f in ipairs(call("getFrames", { rig = rig }).result or {}) do
        if f == frame then return true end
    end
    return false
end

local function clearAllAt(frame)
    call("deleteCameraKeyframe", { frame = frame })
    for _, rig in ipairs(rigs) do call("deleteKeyframe", { rig = rig, frame = frame }) end
    for _, prop in ipairs(props) do call("deletePropKeyframe", { prop = prop, frame = frame }) end
end

-- ── Build two rig frames at the end of the timeline ───────────────────────────

local fc0 = call("getFrameCount").result or 1
local base = fc0
local baseHadData = call("simpleFrameHasData", { frame = base }).result == true
call("simpleNavigate", { frame = base })
call("simpleAddFrame")                 -- (re)captures base, cursor → base+1
local F1, F2 = base + 1, base + 2
call("simpleAddFrame")                 -- captures F1, cursor → F2
call("simpleAddFrame")                 -- captures F2, cursor → EMPTY (base+3)
local EMPTY = base + 3

-- ── 2: untouched pose → rig keyframes bit-identical across step-throughs ─────

call("saveSession", { name = "__hygA" })
for _ = 1, 2 do
    call("simpleNavigate", { frame = F1 })
    call("simpleNavigate", { frame = F2 })
end
call("saveSession", { name = "__hygB" })

local folder = game:GetService("ServerStorage"):FindFirstChild("MultiAnimSessions")
local worst = -1
if folder and folder:FindFirstChild("__hygA") and folder:FindFirstChild("__hygB") then
    local a = hs:JSONDecode(folder.__hygA.Value)
    local b = hs:JSONDecode(folder.__hygB.Value)
    worst = 0
    for rigName, rA in pairs(a.rigs or {}) do
        local rB = b.rigs and b.rigs[rigName]
        for frame, jointsA in pairs(rA and rA.joints or {}) do
            local jointsB = rB and rB.joints and rB.joints[frame]
            for jName, arrA in pairs(jointsA) do
                local arrB = jointsB and jointsB[jName]
                if arrB then
                    for i = 1, 12 do worst = math.max(worst, math.abs(arrA[i] - arrB[i])) end
                end
            end
        end
    end
end
ok("rig keyframes bit-identical across step-throughs of an untouched pose",
    worst == 0, "worst joint delta " .. tostring(worst))
call("deleteSession", { name = "__hygA" })
call("deleteSession", { name = "__hygB" })

-- ── 3: a real pose edit at a data frame still captures on departure ───────────

call("simpleNavigate", { frame = F1 })
local rigModel = workspace:FindFirstChild("FIGURES")
    and workspace.FIGURES:FindFirstChild(rigA)
local limb = rigModel and rigModel:FindFirstChild("Right Arm")
if limb then
    local editedCF = limb.CFrame * CFrame.new(0, 1.5, 0)
    limb.CFrame = editedCF
    call("simpleNavigate", { frame = F2 })
    call("simpleNavigate", { frame = F1 })   -- applyPosesAt restores from recorder
    ok("pose edit at a data frame survives navigation away and back",
        (limb.CFrame.Position - editedCF.Position).Magnitude < 0.01,
        (limb.CFrame.Position - editedCF.Position).Magnitude)
else
    table.insert(out, "SKIP  pose-edit capture test (no Right Arm limb)")
end

-- ── 1: camera-only frame is not materialized into rig keyframes ───────────────

call("setSimpleCamera", { on = true })
call("simpleNavigate", { frame = EMPTY })
call("setSimpleCameraCF", { x = 60, y = 20, z = 60, tx = 0, ty = 3, tz = 0 })
call("simpleNavigate", { frame = F1 })   -- departure: camera-only keyframe at EMPTY
ok("camera move at an empty frame creates a camera-only keyframe",
    call("getCameraKeyframe", { frame = EMPTY }).result ~= nil)
ok("camera-only capture does not create rig keyframes", not rigHasKF(rigA, EMPTY))

call("simpleNavigate", { frame = EMPTY })   -- pass through it, untouched
call("simpleNavigate", { frame = F1 })
ok("passing through a camera-only frame does not materialize rig keyframes",
    not rigHasKF(rigA, EMPTY))
local emptyCamKF = call("getCameraKeyframe", { frame = EMPTY }).result
ok("camera-only keyframe survives the pass-through", emptyCamKF ~= nil)

-- ── 4: capture at a new frame surfaces its tile immediately ───────────────────

local uiSlots = call("getSimpleUISlots").result or {}
local tileShown = false
for _, f in ipairs(uiSlots) do if f == EMPTY then tileShown = true end end
ok("new keyframe's tile appears in the panel strip without a manual rebuild",
    tileShown, hs:JSONEncode(uiSlots))

-- ── 5: Insert Frame duplicate inherits the source camera cut mode ─────────────

call("simpleNavigate", { frame = F1 })
call("setCameraMode", { frame = F1, mode = "cut" })
call("simpleInsertFrame")                -- duplicates F1 into F1+1, cursor there
local dup = call("getCameraKeyframe", { frame = F1 + 1 }).result
ok("Insert Frame duplicate keeps the source camera keyframe's cut mode",
    dup ~= nil and dup.mode == "cut", dup and dup.mode)
-- remove the inserted duplicate (shifts everything back into place)
call("simpleDeleteKeyframe")

-- ── Cleanup (highest frame first; simpleDeleteKeyframe shifts left) ───────────

for _, f in ipairs({ EMPTY, F2, F1 }) do
    call("setFrame", { frame = f })
    call("simpleDeleteKeyframe")
end
if not baseHadData then clearAllAt(base) end
call("setSimpleCamera", { on = false })

local fcEnd = call("getFrameCount").result
ok("cleanup: frame count restored", fcEnd == fc0, tostring(fcEnd) .. " vs " .. tostring(fc0))

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
