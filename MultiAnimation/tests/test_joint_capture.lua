-- tests/test_joint_capture.lua
-- Run via MCP execute_luau (paste as code argument).
-- Returns a pass/fail string — does NOT use print().
--
-- IMPORTANT: this test manages Motor6D disconnect/reconnect itself.
-- In normal plugin operation, motors are kept disconnected permanently;
-- the test mimics that by disconnecting before testing and reconnecting
-- at the end to leave the rig clean.

local out = {}
local passed, failed = 0, 0

local function ok(label, cond, extra)
    if cond then
        passed = passed + 1
        table.insert(out, "PASS  " .. label)
    else
        failed = failed + 1
        local line = "FAIL  " .. label
        if extra then line = line .. "  >> " .. tostring(extra) end
        table.insert(out, line)
    end
end

local function posDiff(cf1, cf2)
    return (cf1.Position - cf2.Position).Magnitude
end

-- ── Locate rig ────────────────────────────────────────────────────────────────

local fig = workspace:FindFirstChild("FIGURES")
ok("FIGURES folder exists", fig ~= nil)
if not fig then return "ABORT: no FIGURES folder" end

local rig = fig:FindFirstChild("Rig1")
ok("Rig1 exists", rig ~= nil)
if not rig then return "ABORT: no Rig1" end

local torso = rig:FindFirstChild("Torso")
local hrp   = rig:FindFirstChild("HumanoidRootPart")
local rArm  = rig:FindFirstChild("Right Arm")

ok("Torso found",            torso ~= nil)
ok("HumanoidRootPart found", hrp   ~= nil)
ok("Right Arm found",        rArm  ~= nil)

local rShoulder = torso and torso:FindFirstChild("Right Shoulder")
local rootJoint = hrp   and hrp:FindFirstChild("RootJoint")

ok("Right Shoulder Motor6D found", rShoulder ~= nil)
ok("RootJoint Motor6D found",      rootJoint ~= nil)

if not (torso and hrp and rArm and rShoulder and rootJoint) then
    return "ABORT: missing critical parts/motors\n" .. table.concat(out, "\n")
end

ok("Right Shoulder Part0 == Torso",    rShoulder.Part0 == torso)
ok("Right Shoulder Part1 == Right Arm", rShoulder.Part1 == rArm)

-- ── Disconnect all motors (mirrors plugin session behaviour) ──────────────────

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
ok("Motors disconnected (rShoulder.Part0 == nil)", rShoulder.Part0 == nil)

-- ── Capture helpers (inline JointCapture logic) ───────────────────────────────

local function computeTransform(motor, container, child)
    -- container = Part0 (passed explicitly since motor.Part0 may be nil)
    return motor.C0:Inverse() * container.CFrame:Inverse() * child.CFrame * motor.C1
end

local function applyTransform(motor, container, child, cf)
    child.CFrame = container.CFrame * motor.C0 * cf * motor.C1:Inverse()
end

-- ── Test 1: rest transform near identity (motors disconnected) ────────────────

local restTf  = computeTransform(rShoulder, torso, rArm)
local idDiff  = posDiff(restTf, CFrame.identity)
ok("Rest transform position near identity (< 0.01 studs)",
    idDiff < 0.01, string.format("diff=%.5f", idDiff))

-- ── Test 2: capture → apply round-trip ───────────────────────────────────────
-- Save rest transform, move arm (ONLY arm moves now, no weld cascade),
-- capture posed transform, apply rest → verify arm returns to original.

local origCF  = rArm.CFrame
local savedTf = computeTransform(rShoulder, torso, rArm)

-- Confirm torso does NOT move when arm is moved (motors disconnected)
local tY0 = torso.CFrame.Y
rArm.CFrame = rArm.CFrame + Vector3.new(0, 3, 0)
local tY1 = torso.CFrame.Y
ok("Torso does NOT move when arm is moved (motors disconnected)",
    math.abs(tY1 - tY0) < 0.001,
    string.format("torso delta=%.4f", tY1 - tY0))
ok("Arm moved 3 studs",
    math.abs((rArm.CFrame.Position - origCF.Position).Magnitude - 3) < 0.01)

local poseTf = computeTransform(rShoulder, torso, rArm)

-- Pose transform should differ from rest transform
ok("Pose transform differs from rest transform",
    posDiff(poseTf, savedTf) > 0.1,
    string.format("diff=%.4f", posDiff(poseTf, savedTf)))

-- Apply rest transform → arm should return to original position
applyTransform(rShoulder, torso, rArm, savedTf)
local err1 = posDiff(rArm.CFrame, origCF)
ok("Apply savedTf restores arm to original position (< 0.01 studs)",
    err1 < 0.01,
    string.format("err=%.5f  orig=%s  got=%s",
        err1, tostring(origCF.Position), tostring(rArm.CFrame.Position)))

-- Apply pose transform → arm should go back to moved position
applyTransform(rShoulder, torso, rArm, poseTf)
local movedCF = origCF + Vector3.new(0, 3, 0)
local err2 = posDiff(rArm.CFrame, movedCF)
ok("Apply poseTf places arm at captured pose position (< 0.01 studs)",
    err2 < 0.01,
    string.format("err=%.5f", err2))

-- Restore arm
applyTransform(rShoulder, torso, rArm, savedTf)

-- ── Test 3: FK chain — translate whole rig via RootJoint ─────────────────────

local origTorsoCF = torso.CFrame
local origArmCF   = rArm.CFrame
local rootTf      = computeTransform(rootJoint, hrp, torso)

hrp.CFrame   = hrp.CFrame + Vector3.new(5, 0, 0)
torso.CFrame = hrp.CFrame * rootJoint.C0 * rootTf * rootJoint.C1:Inverse()
local armTf  = computeTransform(rShoulder, torso, rArm)
rArm.CFrame  = torso.CFrame * rShoulder.C0 * armTf * rShoulder.C1:Inverse()

local expectedPos = origArmCF.Position + Vector3.new(5, 0, 0)
local err3 = (rArm.CFrame.Position - expectedPos).Magnitude
ok("FK chain: arm follows rig translation (< 0.05 studs)",
    err3 < 0.05,
    string.format("err=%.5f", err3))

-- Restore
hrp.CFrame   = hrp.CFrame   - Vector3.new(5, 0, 0)
torso.CFrame = origTorsoCF
rArm.CFrame  = origArmCF

-- ── Reconnect motors ──────────────────────────────────────────────────────────

for _, j in ipairs(JOINTS) do
    local motor = j.container and j.container:FindFirstChild(j.name)
    if motor and motor:IsA("Motor6D") then
        motor.Part0 = savedPart0[j.name]
    end
end
ok("Motors reconnected", rShoulder.Part0 == torso)

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
if failed == 0 then
    table.insert(out, "ALL TESTS PASSED")
end
return table.concat(out, "\n")
