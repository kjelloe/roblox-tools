-- test_rig_root_motion.lua
-- Tests that whole-model movement (moving HumanoidRootPart in the scene)
-- is captured in rootTrack and correctly applied during scrub/playback.
-- Inlines the relevant logic; runs against real Rig1 in the scene.
-- Motors are disconnected then reconnected so the test leaves the rig clean.

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

local function approx(a, b, eps)  return math.abs(a - b) < (eps or 0.05) end
local function approxV3(a, b, eps) return (a - b).Magnitude < (eps or 0.05) end
local function approxCF(a, b, eps)
    eps = eps or 0.05
    return (a.Position - b.Position).Magnitude < eps
       and (a.XVector  - b.XVector).Magnitude  < eps
end

-- ── Locate Rig1 ──────────────────────────────────────────────────────────────

local fig = workspace:FindFirstChild("FIGURES")
ok("FIGURES folder exists", fig ~= nil)
if not fig then return "ABORT: no FIGURES\n" .. table.concat(out, "\n") end

local rig = fig:FindFirstChild("Rig1")
ok("Rig1 exists", rig ~= nil)
if not rig then return "ABORT: no Rig1\n" .. table.concat(out, "\n") end

local hrp   = rig:FindFirstChild("HumanoidRootPart")
local torso = rig:FindFirstChild("Torso")
ok("HumanoidRootPart found", hrp   ~= nil)
ok("Torso found",            torso ~= nil)
if not (hrp and torso) then return "ABORT: missing parts\n" .. table.concat(out, "\n") end

-- ── Inline: disconnect motors ─────────────────────────────────────────────────

local JOINTS = {
    { name = "RootJoint",      container = hrp   },
    { name = "Neck",           container = torso },
    { name = "Right Shoulder", container = torso },
    { name = "Left Shoulder",  container = torso },
    { name = "Right Hip",      container = torso },
    { name = "Left Hip",       container = torso },
}
local savedPart0 = {}
for _, j in ipairs(JOINTS) do
    local motor = j.container and j.container:FindFirstChild(j.name)
    if motor and motor:IsA("Motor6D") then
        savedPart0[j.name] = motor.Part0
        motor.Part0 = nil
    end
end
ok("Motors disconnected", hrp:FindFirstChild("RootJoint") and hrp:FindFirstChild("RootJoint").Part0 == nil)

-- ── Inline: rootTrack capture / apply ────────────────────────────────────────

local function captureRoot(model)
    local h = model:FindFirstChild("HumanoidRootPart")
    return h and h.CFrame or nil
end

-- Mirrors PoseApplier: apply root CFrame first so limbs position relative to it.
local JOINT_PARENT = {
    RootJoint          = "HumanoidRootPart",
    Neck               = "Torso",
    ["Right Shoulder"] = "Torso",
    ["Left Shoulder"]  = "Torso",
    ["Right Hip"]      = "Torso",
    ["Left Hip"]       = "Left Leg",  -- wrong for real apply but only testing HRP + Torso
}
local JOINT_CHILD = {
    RootJoint          = "Torso",
    Neck               = "Head",
    ["Right Shoulder"] = "Right Arm",
    ["Left Shoulder"]  = "Left Arm",
    ["Right Hip"]      = "Right Leg",
    ["Left Hip"]       = "Left Leg",
}
local APPLY_ORDER = { "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }

local function captureJoints(model)
    local result = {}
    for _, jointName in ipairs(APPLY_ORDER) do
        local parentName = JOINT_PARENT[jointName]
        local childName  = JOINT_CHILD[jointName]
        local container  = model:FindFirstChild(parentName)
        local child      = model:FindFirstChild(childName)
        if not (container and child) then continue end
        local motor = container:FindFirstChild(jointName)
        if not motor or not motor:IsA("Motor6D") then continue end
        result[jointName] = motor.C0:Inverse() * container.CFrame:Inverse() * child.CFrame * motor.C1
    end
    return result
end

local function applyJoints(model, jointData, rootCFrame)
    -- Set HRP position first (mirrors PoseApplier behaviour)
    if rootCFrame then
        local h = model:FindFirstChild("HumanoidRootPart")
        if h then h.CFrame = rootCFrame end
    end
    for _, jointName in ipairs(APPLY_ORDER) do
        local cf = jointData[jointName]
        if not cf then continue end
        local parentName = JOINT_PARENT[jointName]
        local childName  = JOINT_CHILD[jointName]
        local container  = model:FindFirstChild(parentName)
        local child      = model:FindFirstChild(childName)
        if not (container and child) then continue end
        local motor = container:FindFirstChild(jointName)
        if not motor then continue end
        child.CFrame = container.CFrame * motor.C0 * cf * motor.C1:Inverse()
    end
end

-- ── Inline: rootTrack interpolation ──────────────────────────────────────────

local function surrounding(sf, q)
    if #sf == 0 then return nil, nil, 0 end
    if #sf == 1 then return sf[1], sf[1], 0 end
    if q <= sf[1] then return sf[1], sf[1], 0 end
    if q >= sf[#sf] then local l = sf[#sf]; return l, l, 0 end
    for i = 1, #sf - 1 do
        local a, b = sf[i], sf[i+1]
        if q >= a and q <= b then return a, b, (q-a)/(b-a) end
    end
    return nil, nil, 0
end

local function getRootDataInterp(rootTrack, queryFrame)
    local sorted = {}
    for f in pairs(rootTrack) do table.insert(sorted, f) end
    table.sort(sorted)
    if #sorted == 0 then return nil end
    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end
    local cfA = rootTrack[fA]
    if fA == fB or alpha == 0 then return cfA end
    local cfB = rootTrack[fB]
    return cfB and cfA:Lerp(cfB, alpha) or cfA
end

-- ── Tests ─────────────────────────────────────────────────────────────────────

local origHRPCF  = hrp.CFrame
local origTorsoCF = torso.CFrame

-- 1. captureRoot returns current HRP CFrame
local captured0 = captureRoot(rig)
ok("captureRoot returns HRP CFrame", captured0 ~= nil and approxCF(captured0, hrp.CFrame))

-- 2. Capture joint transforms at rest
local jointsRest = captureJoints(rig)
ok("captureJoints captures RootJoint", jointsRest["RootJoint"] ~= nil)

-- 3. Move whole rig up by 5 units (simulates moving Model in viewport)
local LIFT = 5
local allParts = { hrp, torso,
    rig:FindFirstChild("Head"),
    rig:FindFirstChild("Left Arm"), rig:FindFirstChild("Right Arm"),
    rig:FindFirstChild("Left Leg"), rig:FindFirstChild("Right Leg") }
for _, p in ipairs(allParts) do
    if p then p.CFrame = p.CFrame + Vector3.new(0, LIFT, 0) end
end

local capturedLift = captureRoot(rig)
ok("captureRoot after lift: Y ≈ original + 5",
    capturedLift ~= nil and approx(capturedLift.Position.Y, origHRPCF.Position.Y + LIFT),
    string.format("got Y=%.3f expected≈%.3f", capturedLift and capturedLift.Position.Y or -1,
        origHRPCF.Position.Y + LIFT))

local jointsLifted = captureJoints(rig)

-- 4. Reset rig to original position
for _, p in ipairs(allParts) do
    if p then p.CFrame = p.CFrame - Vector3.new(0, LIFT, 0) end
end
ok("rig reset to original position", approxV3(hrp.Position, origHRPCF.Position))

-- 5. Apply rest joints WITHOUT rootCFrame → HRP stays at original position
applyJoints(rig, jointsRest, nil)
ok("apply without rootCFrame: HRP stays at origin",
    approxV3(hrp.Position, origHRPCF.Position))

-- 6. Apply lifted state WITH rootCFrame → HRP moves to lifted position
applyJoints(rig, jointsLifted, capturedLift)
ok("apply WITH rootCFrame: HRP moves to lifted Y",
    approx(hrp.Position.Y, origHRPCF.Position.Y + LIFT),
    string.format("got Y=%.3f", hrp.Position.Y))

-- 7. Torso moved relative to HRP (not left behind at original position)
local expectedTorsoY = origTorsoCF.Position.Y + LIFT
ok("Torso follows HRP after apply",
    approx(torso.Position.Y, expectedTorsoY, 0.1),
    string.format("got Y=%.3f expected≈%.3f", torso.Position.Y, expectedTorsoY))

-- 8. Reset back to original
applyJoints(rig, jointsRest, origHRPCF)
ok("reset via apply: HRP back at original", approxV3(hrp.Position, origHRPCF.Position))

-- 9. rootTrack interpolation: midpoint between two Y positions gives correct lerp
local rootTrack = {
    [1]  = CFrame.new(0, 0, 0),
    [11] = CFrame.new(0, 10, 0),
}
local mid = getRootDataInterp(rootTrack, 6)   -- alpha = 0.5
ok("rootTrack midpoint interpolation Y=5",
    mid ~= nil and approx(mid.Position.Y, 5),
    string.format("got Y=%.4f", mid and mid.Position.Y or -1))

-- 10. rootTrack clamps before first frame
local before = getRootDataInterp(rootTrack, 0)
ok("rootTrack clamps before first frame",
    before ~= nil and approx(before.Position.Y, 0))

-- 11. rootTrack clamps after last frame
local after = getRootDataInterp(rootTrack, 99)
ok("rootTrack clamps after last frame",
    after ~= nil and approx(after.Position.Y, 10))

-- 12. rootTrack: nil when empty
ok("empty rootTrack returns nil", getRootDataInterp({}, 5) == nil)

-- ── Reconnect motors ──────────────────────────────────────────────────────────

for _, j in ipairs(JOINTS) do
    local motor = j.container and j.container:FindFirstChild(j.name)
    if motor and motor:IsA("Motor6D") then
        motor.Part0 = savedPart0[j.name]
    end
end
-- Check motors restored to pre-test state (may still be nil if plugin already disconnected them)
local rootJoint = hrp:FindFirstChild("RootJoint")
ok("Motors restored to pre-test state",
    rootJoint ~= nil and rootJoint.Part0 == savedPart0["RootJoint"])

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
