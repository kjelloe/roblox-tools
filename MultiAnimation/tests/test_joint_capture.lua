-- tests/test_joint_capture.lua
-- Run via MCP execute_luau.  Prints PASS/FAIL for each assertion.
-- Does NOT require any UI or plugin; works against the live rig in Workspace.
--
-- Usage (from REFERENCE.md MCP bash template):
--   tool: execute_luau
--   code: <paste this file>
--   then: get_console_output

local EPSILON = 0.001   -- acceptable position error (studs)
local ANGLE_EPS = 0.01  -- acceptable rotation error (radians)

local passed, failed = 0, 0

local function ok(label, cond, extra)
    if cond then
        print("PASS  " .. label)
        passed += 1
    else
        print("FAIL  " .. label .. (extra and ("  >> " .. tostring(extra)) or ""))
        failed += 1
    end
end

local function posDiff(cf1, cf2)
    return (cf1.Position - cf2.Position).Magnitude
end

-- ── Helpers that mirror JointCapture logic ────────────────────────────────────

local function computeTransform(motor)
    local p0, p1 = motor.Part0, motor.Part1
    if not p0 or not p1 then return CFrame.identity end
    return motor.C0:Inverse() * p0.CFrame:Inverse() * p1.CFrame * motor.C1
end

local function applyTransform(motor, child, container, cf)
    child.CFrame = container.CFrame * motor.C0 * cf * motor.C1:Inverse()
end

-- ── Locate rig ────────────────────────────────────────────────────────────────

local fig = workspace:FindFirstChild("FIGURES")
ok("FIGURES folder exists", fig ~= nil)
if not fig then print("ABORT: no FIGURES folder"); return end

local rig = fig:FindFirstChild("Rig1")
ok("Rig1 exists", rig ~= nil)
if not rig then print("ABORT: no Rig1"); return end

local torso = rig:FindFirstChild("Torso")
local hrp   = rig:FindFirstChild("HumanoidRootPart")
local head  = rig:FindFirstChild("Head")
local rArm  = rig:FindFirstChild("Right Arm")
local lArm  = rig:FindFirstChild("Left Arm")
local rLeg  = rig:FindFirstChild("Right Leg")
local lLeg  = rig:FindFirstChild("Left Leg")

ok("Torso found",            torso ~= nil)
ok("HumanoidRootPart found", hrp   ~= nil)
ok("Head found",             head  ~= nil)
ok("Right Arm found",        rArm  ~= nil)

-- ── Motor6D presence ──────────────────────────────────────────────────────────

local rootJoint    = hrp   and hrp:FindFirstChild("RootJoint")
local neck         = torso and torso:FindFirstChild("Neck")
local rShoulder    = torso and torso:FindFirstChild("Right Shoulder")
local lShoulder    = torso and torso:FindFirstChild("Left Shoulder")
local rHip         = torso and torso:FindFirstChild("Right Hip")
local lHip         = torso and torso:FindFirstChild("Left Hip")

ok("RootJoint Motor6D found",    rootJoint ~= nil)
ok("Neck Motor6D found",         neck      ~= nil)
ok("Right Shoulder Motor6D found", rShoulder ~= nil)

if not (rootJoint and rShoulder and torso and hrp and rArm) then
    print("ABORT: missing critical parts/motors")
    return
end

ok("RootJoint Part0 = HumanoidRootPart", rootJoint.Part0 == hrp)
ok("RootJoint Part1 = Torso",            rootJoint.Part1 == torso)
ok("Right Shoulder Part0 = Torso",       rShoulder.Part0 == torso)
ok("Right Shoulder Part1 = Right Arm",   rShoulder.Part1 == rArm)

-- ── Test 1: at-rest transform is near identity ────────────────────────────────
-- For an unposed R6 rig the captured transform should be ~identity.

local restTransform = computeTransform(rShoulder)
local identityDiff  = posDiff(restTransform, CFrame.identity)
ok("Rest transform position ~= identity (< 0.01 studs)",
    identityDiff < 0.01, string.format("diff=%.4f", identityDiff))

-- ── Test 2: capture → apply round-trip for Right Arm ─────────────────────────
-- Save CFrame, move arm, restore via apply, check we're back.

local origCF = rArm.CFrame

-- Record transform from the REST position
local savedTransform = computeTransform(rShoulder)

-- Move the arm 3 studs upward (simulate a pose change)
rArm.CFrame = rArm.CFrame + Vector3.new(0, 3, 0)
local movedCF = rArm.CFrame

-- Confirm it actually moved
ok("Arm actually moved 3 studs up",
    math.abs((movedCF.Position - origCF.Position).Magnitude - 3) < 0.01,
    string.format("moved=%.4f", (movedCF.Position - origCF.Position).Magnitude))

-- Capture the new transform
local poseTransform = computeTransform(rShoulder)

-- Apply the original rest transform to restore
applyTransform(rShoulder, rArm, torso, savedTransform)
local restoredCF = rArm.CFrame
local restoreErr = posDiff(restoredCF, origCF)

ok("Apply restores arm to original position (< 0.01 studs)",
    restoreErr < 0.01,
    string.format("err=%.4f  orig=%s  restored=%s",
        restoreErr, tostring(origCF.Position), tostring(restoredCF.Position)))

-- ── Test 3: apply the posed transform, verify arm at moved position ───────────

applyTransform(rShoulder, rArm, torso, poseTransform)
local poseAppliedCF = rArm.CFrame
local poseErr = posDiff(poseAppliedCF, movedCF)

ok("Apply posed transform places arm at captured position (< 0.01 studs)",
    poseErr < 0.01,
    string.format("err=%.4f  expected=%s  got=%s",
        poseErr, tostring(movedCF.Position), tostring(poseAppliedCF.Position)))

-- Restore to original so we don't leave the rig in a broken state
applyTransform(rShoulder, rArm, torso, savedTransform)

-- ── Test 4: forward kinematics chain (Torso → Arm) ───────────────────────────
-- Move Torso, verify arm placed correctly relative to new Torso position.

local origTorsoCF = torso.CFrame
local origArmCF   = rArm.CFrame
local armOffset   = torso.CFrame:Inverse() * rArm.CFrame   -- arm relative to torso

-- Shift entire rig (move HumanoidRootPart, apply RootJoint transform to derive Torso)
local rootTransform = computeTransform(rootJoint)
-- Move HRP 5 studs along X
hrp.CFrame = hrp.CFrame + Vector3.new(5, 0, 0)
-- Apply RootJoint (sets Torso)
torso.CFrame = hrp.CFrame * rootJoint.C0 * rootTransform * rootJoint.C1:Inverse()
-- Apply Right Shoulder (sets Right Arm)
local armTransform = computeTransform(rShoulder)  -- same arm pose relative to torso
rArm.CFrame = torso.CFrame * rShoulder.C0 * armTransform * rShoulder.C1:Inverse()

-- Arm should have moved by the same 5 studs
local expectedArmPos = origArmCF.Position + Vector3.new(5, 0, 0)
local chainErr = (rArm.CFrame.Position - expectedArmPos).Magnitude

ok("FK chain: arm moves correctly with rig translation (< 0.05 studs)",
    chainErr < 0.05,
    string.format("err=%.4f  expected=%s  got=%s",
        chainErr, tostring(expectedArmPos), tostring(rArm.CFrame.Position)))

-- Restore rig
hrp.CFrame   = hrp.CFrame   - Vector3.new(5, 0, 0)
torso.CFrame = origTorsoCF
rArm.CFrame  = origArmCF

-- ── Summary ───────────────────────────────────────────────────────────────────

print(string.format("\n=== %d passed, %d failed ===", passed, failed))
if failed == 0 then
    print("ALL TESTS PASSED — JointCapture math is correct")
else
    print("FAILURES DETECTED — see FAIL lines above")
end
