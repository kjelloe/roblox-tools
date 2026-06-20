-- test_r15_joints.lua
-- Tests dynamic Motor6D discovery in JointCapture (discoverMotors filter).
-- Creates mock rigs entirely in code — no dependency on workspace FIGURES.
-- Also runs a live R15 test if an R15 rig is found tagged "MAnim:TestScene15".

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

-- ── Inline discoverMotors (mirrors JointCapture) ──────────────────────────────

local function discoverMotors(rig)
    local motors = {}
    for _, inst in ipairs(rig:GetDescendants()) do
        if inst:IsA("Motor6D") then
            local container = inst.Parent
            local p1 = inst.Part1
            if container and container.Parent == rig
               and p1 and p1.Parent == rig then
                table.insert(motors, inst)
            end
        end
    end
    return motors
end

local function buildApplyOrder(motors)
    local positioned = { HumanoidRootPart = true }
    local ordered = {}
    local remaining = { table.unpack(motors) }
    local maxIter = (#motors + 1) * (#motors + 1)
    local iter = 0
    while #remaining > 0 and iter < maxIter do
        iter += 1
        local next = {}
        local progressed = false
        for _, m in ipairs(remaining) do
            if positioned[m.Parent.Name] then
                table.insert(ordered, m)
                positioned[m.Part1.Name] = true
                progressed = true
            else
                table.insert(next, m)
            end
        end
        remaining = next
        if not progressed then break end
    end
    for _, m in ipairs(remaining) do table.insert(ordered, m) end
    return ordered
end

local function captureRig(rig)
    local result = {}
    for _, motor in ipairs(discoverMotors(rig)) do
        local container = motor.Parent
        local child = motor.Part1
        result[motor.Name] = motor.C0:Inverse() * container.CFrame:Inverse()
                           * child.CFrame * motor.C1
    end
    return result
end

local function applyRig(rig, jointData)
    local ordered = buildApplyOrder(discoverMotors(rig))
    for _, motor in ipairs(ordered) do
        local cf = jointData[motor.Name]
        if not cf then continue end
        motor.Part1.CFrame = motor.Parent.CFrame * motor.C0 * cf * motor.C1:Inverse()
    end
end

-- ── Helper: build mock Motor6D ────────────────────────────────────────────────

local function makeMotor(name, parent, part0, part1)
    local m = Instance.new("Motor6D")
    m.Name  = name
    m.Part0 = part0
    m.Part1 = part1
    m.Parent = parent
    return m
end

local function makePart(name, parent)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.CFrame = CFrame.new(0, 0, 0)
    p.Parent = parent
    return p
end

-- ── Test 1: mock R6 rig — discovery finds exactly 6 joints ───────────────────

do
    local rig = Instance.new("Model"); rig.Parent = workspace
    local hrp   = makePart("HumanoidRootPart", rig)
    local torso  = makePart("Torso",  rig)
    local head   = makePart("Head",   rig)
    local rArm   = makePart("Right Arm", rig)
    local lArm   = makePart("Left Arm",  rig)
    local rLeg   = makePart("Right Leg", rig)
    local lLeg   = makePart("Left Leg",  rig)

    makeMotor("RootJoint",      hrp,   hrp,   torso)
    makeMotor("Neck",           torso, torso, head)
    makeMotor("Right Shoulder", torso, torso, rArm)
    makeMotor("Left Shoulder",  torso, torso, lArm)
    makeMotor("Right Hip",      torso, torso, rLeg)
    makeMotor("Left Hip",       torso, torso, lLeg)

    local motors = discoverMotors(rig)
    ok("mock R6: discovers exactly 6 joints", #motors == 6, tostring(#motors))

    local names = {}
    for _, m in ipairs(motors) do names[m.Name] = true end
    ok("mock R6: RootJoint found",      names["RootJoint"])
    ok("mock R6: Neck found",           names["Neck"])
    ok("mock R6: Right Shoulder found", names["Right Shoulder"])
    ok("mock R6: Left Shoulder found",  names["Left Shoulder"])
    ok("mock R6: Right Hip found",      names["Right Hip"])
    ok("mock R6: Left Hip found",       names["Left Hip"])

    rig:Destroy()
end

-- ── Test 2: mock R15 rig — discovery finds all 15 joints ─────────────────────

do
    local rig = Instance.new("Model"); rig.Parent = workspace
    local hrp  = makePart("HumanoidRootPart", rig)
    local ltor  = makePart("LowerTorso",   rig)
    local utor  = makePart("UpperTorso",   rig)
    local head  = makePart("Head",         rig)
    local lula  = makePart("LeftUpperArm", rig)
    local llla  = makePart("LeftLowerArm", rig)
    local lhand = makePart("LeftHand",     rig)
    local rula  = makePart("RightUpperArm",rig)
    local rlla  = makePart("RightLowerArm",rig)
    local rhand = makePart("RightHand",    rig)
    local lul   = makePart("LeftUpperLeg", rig)
    local lll   = makePart("LeftLowerLeg", rig)
    local lfoot = makePart("LeftFoot",     rig)
    local rul   = makePart("RightUpperLeg",rig)
    local rll   = makePart("RightLowerLeg",rig)
    local rfoot = makePart("RightFoot",    rig)

    makeMotor("Root",          hrp,   hrp,   ltor)
    makeMotor("Waist",         ltor,  ltor,  utor)
    makeMotor("Neck",          utor,  utor,  head)
    makeMotor("LeftShoulder",  utor,  utor,  lula)
    makeMotor("LeftElbow",     lula,  lula,  llla)
    makeMotor("LeftWrist",     llla,  llla,  lhand)
    makeMotor("RightShoulder", utor,  utor,  rula)
    makeMotor("RightElbow",    rula,  rula,  rlla)
    makeMotor("RightWrist",    rlla,  rlla,  rhand)
    makeMotor("LeftHip",       ltor,  ltor,  lul)
    makeMotor("LeftKnee",      lul,   lul,   lll)
    makeMotor("LeftAnkle",     lll,   lll,   lfoot)
    makeMotor("RightHip",      ltor,  ltor,  rul)
    makeMotor("RightKnee",     rul,   rul,   rll)
    makeMotor("RightAnkle",    rll,   rll,   rfoot)

    local motors = discoverMotors(rig)
    ok("mock R15: discovers exactly 15 joints", #motors == 15, tostring(#motors))

    -- Check apply order puts Root before Waist before Neck/Shoulder
    local ordered = buildApplyOrder(motors)
    ok("mock R15: apply order has 15 entries", #ordered == 15, tostring(#ordered))
    local rootIdx, waistIdx, neckIdx = 0, 0, 0
    for i, m in ipairs(ordered) do
        if m.Name == "Root"  then rootIdx  = i end
        if m.Name == "Waist" then waistIdx = i end
        if m.Name == "Neck"  then neckIdx  = i end
    end
    ok("mock R15: Root comes before Waist",  rootIdx > 0 and waistIdx > rootIdx,
        string.format("Root=%d Waist=%d", rootIdx, waistIdx))
    ok("mock R15: Waist comes before Neck",  waistIdx > 0 and neckIdx > waistIdx,
        string.format("Waist=%d Neck=%d", waistIdx, neckIdx))

    rig:Destroy()
end

-- ── Test 3: accessory Motor6D excluded ───────────────────────────────────────

do
    local rig = Instance.new("Model"); rig.Parent = workspace
    local hrp   = makePart("HumanoidRootPart", rig)
    local torso = makePart("Torso",  rig)
    makeMotor("RootJoint", hrp, hrp, torso)

    -- Accessory-style: Handle inside a sub-model (not direct child of rig)
    local acc = Instance.new("Accessory"); acc.Parent = rig
    local handle = makePart("Handle", acc)
    handle.Parent = acc
    local accMotor = Instance.new("Motor6D")
    accMotor.Name   = "AccessoryWeld"
    accMotor.Part0  = torso
    accMotor.Part1  = handle
    accMotor.Parent = handle  -- handle.Parent == acc, not rig → excluded

    local motors = discoverMotors(rig)
    ok("accessory Motor6D excluded from discovery", #motors == 1, tostring(#motors))
    ok("only RootJoint discovered", motors[1] and motors[1].Name == "RootJoint")

    acc:Destroy()
    rig:Destroy()
end

-- ── Test 4: disconnect/reconnect round-trip (motor.Parent stays correct) ──────

do
    local rig = Instance.new("Model"); rig.Parent = workspace
    local hrp   = makePart("HumanoidRootPart", rig)
    local torso = makePart("Torso", rig)
    local motor = makeMotor("RootJoint", hrp, hrp, torso)

    local origPart0 = motor.Part0
    ok("motor.Part0 == hrp before disconnect", motor.Part0 == hrp)

    -- Disconnect
    motor.Part0 = nil
    ok("motor.Part0 == nil after disconnect", motor.Part0 == nil)
    ok("motor.Parent == hrp after disconnect", motor.Parent == hrp)

    -- discoverMotors still finds it (uses motor.Parent, not motor.Part0)
    local motors = discoverMotors(rig)
    ok("discoverMotors finds motor while disconnected", #motors == 1, tostring(#motors))

    -- Reconnect
    motor.Part0 = origPart0
    ok("motor.Part0 restored", motor.Part0 == hrp)

    rig:Destroy()
end

-- ── Test 5: capture → apply round-trip on mock R6 ────────────────────────────

do
    local rig = Instance.new("Model"); rig.Parent = workspace
    local hrp   = makePart("HumanoidRootPart", rig)
    local torso = makePart("Torso", rig)
    local rArm  = makePart("Right Arm", rig)

    hrp.CFrame   = CFrame.new(0, 0, 0)
    torso.CFrame = CFrame.new(0, 3, 0)
    rArm.CFrame  = CFrame.new(3, 3, 0)

    local root = makeMotor("RootJoint",      hrp,   hrp,   torso)
    local rs   = makeMotor("Right Shoulder", torso, torso, rArm)

    -- Disconnect so capture works with current CFrames
    root.Part0 = nil
    rs.Part0   = nil

    local captured = captureRig(rig)
    ok("capture returns RootJoint",      captured["RootJoint"] ~= nil)
    ok("capture returns Right Shoulder", captured["Right Shoulder"] ~= nil)

    -- Move arm to a new position
    local origArmCF = rArm.CFrame
    rArm.CFrame = CFrame.new(5, 3, 0)

    -- Apply saved transform to restore
    applyRig(rig, captured)
    local err = (rArm.CFrame.Position - origArmCF.Position).Magnitude
    ok("apply restores arm to original position (< 0.01 studs)", err < 0.01,
        string.format("err=%.5f", err))

    rig:Destroy()
end

-- ── Test 6: live R15 rig (skipped if none found) ─────────────────────────────

do
    local CollectionService = game:GetService("CollectionService")
    local tagged = CollectionService:GetTagged("MAnim:TestScene15")
    local r15Rig = nil
    for _, inst in ipairs(tagged) do
        if inst:IsA("Model") and inst:FindFirstChild("UpperTorso") then
            r15Rig = inst; break
        end
    end

    if not r15Rig then
        table.insert(out, "SKIP  live R15 rig test (no Model tagged MAnim:TestScene15 with UpperTorso)")
    else
        local motors = discoverMotors(r15Rig)
        ok("live R15: at least 10 joints discovered", #motors >= 10, tostring(#motors))

        local captured = captureRig(r15Rig)
        local count = 0
        for _ in pairs(captured) do count += 1 end
        ok("live R15: capture returns same count as discovered", count == #motors,
            string.format("discovered=%d captured=%d", #motors, count))
    end
end

return finish()
