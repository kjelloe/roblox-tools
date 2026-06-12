-- test_mirror_core.lua
-- Keyframe mirror math: reflection of joint transforms across the rig's
-- left-right (YZ) plane, plus the joint/part name swap maps.
-- Inlines mirrorCF and the maps from init.server.lua.

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

local function approx(a, b, eps) return math.abs(a - b) < (eps or 0.0001) end
local function approxCF(a, b, eps)
    eps = eps or 0.0001
    local ca, cb = { a:GetComponents() }, { b:GetComponents() }
    for i = 1, 12 do
        if math.abs(ca[i] - cb[i]) > eps then return false end
    end
    return true
end

-- ── Inline mirror logic (mirrors init.server.lua) ─────────────────────────────

local MIRROR_JOINT = {
    ["Right Shoulder"] = "Left Shoulder", ["Left Shoulder"] = "Right Shoulder",
    ["Right Hip"] = "Left Hip", ["Left Hip"] = "Right Hip",
    RootJoint = "RootJoint", Neck = "Neck",
}
local MIRROR_PART = {
    ["Right Arm"] = "Left Arm", ["Left Arm"] = "Right Arm",
    ["Right Leg"] = "Left Leg", ["Left Leg"] = "Right Leg",
    Head = "Head", Torso = "Torso", HumanoidRootPart = "HumanoidRootPart",
}

local function mirrorCF(cf)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

-- ── Validity: mirrored matrices stay proper rotations ─────────────────────────

local function det3(cf)
    local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    return r00 * (r11 * r22 - r12 * r21)
         - r01 * (r10 * r22 - r12 * r20)
         + r02 * (r10 * r21 - r11 * r20)
end

local samples = {
    CFrame.identity,
    CFrame.new(1, 2, 3),
    CFrame.Angles(0.3, 0, 0),
    CFrame.Angles(0, 0.7, 0),
    CFrame.Angles(0, 0, 1.1),
    CFrame.new(2, -1, 0.5) * CFrame.Angles(0.4, -0.9, 1.3),
}
local allDet, allInvol = true, true
for _, cf in ipairs(samples) do
    local m = mirrorCF(cf)
    if not approx(det3(m), 1, 0.0001) then allDet = false end
    if not approxCF(mirrorCF(m), cf) then allInvol = false end
end
ok("mirrored matrices have determinant +1 (valid rotations)", allDet)
ok("mirror is an involution: mirror(mirror(cf)) == cf", allInvol)

-- ── Specific behaviours ───────────────────────────────────────────────────────

ok("identity mirrors to identity", approxCF(mirrorCF(CFrame.identity), CFrame.identity))

local m = mirrorCF(CFrame.new(1, 2, 3))
ok("translation: X negates, Y/Z preserved",
    approx(m.X, -1) and approx(m.Y, 2) and approx(m.Z, 3))

-- Rotation about X (nodding around the left-right axis) is symmetric → unchanged
ok("rotation about X unchanged",
    approxCF(mirrorCF(CFrame.Angles(0.6, 0, 0)), CFrame.Angles(0.6, 0, 0)))

-- Rotation about Y (turning) flips direction
ok("rotation about Y negates",
    approxCF(mirrorCF(CFrame.Angles(0, 0.6, 0)), CFrame.Angles(0, -0.6, 0)))

-- Rotation about Z (tilting sideways) flips direction
ok("rotation about Z negates",
    approxCF(mirrorCF(CFrame.Angles(0, 0, 0.6)), CFrame.Angles(0, 0, -0.6)))

-- Combined: an arm raised forward-and-out mirrors to the opposite side
local raise = CFrame.new(0.5, 0.2, -0.1) * CFrame.Angles(0.8, 0.3, -0.4)
local mr = mirrorCF(raise)
ok("combined transform: position X mirrored", approx(mr.X, -raise.X))
ok("combined transform: look direction Z preserved, X flipped",
    approx(mr.LookVector.X, -raise.LookVector.X)
    and approx(mr.LookVector.Y, raise.LookVector.Y)
    and approx(mr.LookVector.Z, raise.LookVector.Z))

-- ── Name swap maps ────────────────────────────────────────────────────────────

ok("shoulder names swap both ways",
    MIRROR_JOINT["Right Shoulder"] == "Left Shoulder"
    and MIRROR_JOINT["Left Shoulder"] == "Right Shoulder")
ok("hip names swap both ways",
    MIRROR_JOINT["Right Hip"] == "Left Hip"
    and MIRROR_JOINT["Left Hip"] == "Right Hip")
ok("centre joints map to themselves",
    MIRROR_JOINT.RootJoint == "RootJoint" and MIRROR_JOINT.Neck == "Neck")

local allJointsCovered = true
for _, j in ipairs({ "RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip" }) do
    if MIRROR_JOINT[j] == nil then allJointsCovered = false end
end
ok("all 6 R6 joints covered by the swap map", allJointsCovered)

local allPartsCovered = true
for _, p in ipairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "HumanoidRootPart" }) do
    if MIRROR_PART[p] == nil then allPartsCovered = false end
end
ok("all 7 R6 parts covered by the swap map", allPartsCovered)

-- Swap map round-trips: applying it twice restores every name
local roundTrips = true
for from, to in pairs(MIRROR_JOINT) do
    if MIRROR_JOINT[to] ~= from then roundTrips = false end
end
for from, to in pairs(MIRROR_PART) do
    if MIRROR_PART[to] ~= from then roundTrips = false end
end
ok("swap maps are involutions", roundTrips)

-- ── Full keyframe mirror round-trip ───────────────────────────────────────────
-- Mirroring a whole joint table twice must reproduce the original exactly.

local original = {
    RootJoint          = CFrame.Angles(0, 0.2, 0),
    Neck               = CFrame.Angles(0.3, 0.1, 0),
    ["Right Shoulder"] = CFrame.new(0.2, 0, 0) * CFrame.Angles(0.9, 0.4, -0.2),
    ["Left Shoulder"]  = CFrame.Angles(-0.1, 0, 0.5),
    ["Right Hip"]      = CFrame.Angles(0.6, 0, 0),
    ["Left Hip"]       = CFrame.identity,
}

local function mirrorJoints(joints)
    local result = {}
    for jName, cf in pairs(joints) do
        result[MIRROR_JOINT[jName] or jName] = mirrorCF(cf)
    end
    return result
end

local once  = mirrorJoints(original)
local twice = mirrorJoints(once)

ok("mirrored table moves right-shoulder data to left shoulder",
    approxCF(once["Left Shoulder"], mirrorCF(original["Right Shoulder"])))
local fullRT = true
for jName, cf in pairs(original) do
    if not (twice[jName] and approxCF(twice[jName], cf)) then fullRT = false end
end
ok("double mirror reproduces the original keyframe exactly", fullRT)

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
