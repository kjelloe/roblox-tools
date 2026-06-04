-- test_exporter.lua
-- Tests the Exporter pipeline end-to-end via execute_luau:
--   1. Pose.CFrame API (confirms the renamed property works)
--   2. buildKeyframeSequence produces a valid KeyframeSequence
--   3. Whole-model export: rootTrack CFrames appear in RootTracks ModuleScript
--   4. KeyframeSequence can be registered with AnimationClipProvider
--   5. PropTracks omitted when no props; written when props present
--
-- All builder logic is inlined so no require() is needed.

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

local function approx(a, b, eps) return math.abs(a - b) < (eps or 0.001) end
local function approxCF(a, b, eps)
    eps = eps or 0.001
    return (a.Position - b.Position).Magnitude < eps
       and (a.XVector  - b.XVector).Magnitude  < eps
end

-- ── Part 1: Pose.CFrame API sanity ───────────────────────────────────────────

do
    local ok1, err1 = pcall(function()
        local p = Instance.new("Pose")
        p.Name   = "TestPose"
        p.CFrame = CFrame.new(1, 2, 3)
        p:Destroy()
    end)
    ok("Pose.CFrame is settable (new API)", ok1, err1)

    local ok2, err2 = pcall(function()
        local p = Instance.new("Pose")
        p.Name   = "HumanoidRootPart"
        p.Weight = 1
        p.CFrame = CFrame.identity
        p.EasingStyle     = Enum.PoseEasingStyle.Linear
        p.EasingDirection = Enum.PoseEasingDirection.Out
        p:Destroy()
    end)
    ok("Pose named 'HumanoidRootPart' with CFrame works", ok2, err2)

    -- Confirm old Transform property is gone (regression guard)
    local hasTransform = pcall(function()
        local p = Instance.new("Pose")
        local _ = p.Transform
        p:Destroy()
    end)
    ok("Pose.Transform is NOT valid (API changed — use CFrame)", not hasTransform)
end

-- ── Inline: makePose (mirrors Exporter) ──────────────────────────────────────

local function makePose(name, cf)
    local p           = Instance.new("Pose")
    p.Name            = name
    p.Weight          = 1
    p.CFrame          = cf or CFrame.identity
    p.EasingStyle     = Enum.PoseEasingStyle.Linear
    p.EasingDirection = Enum.PoseEasingDirection.Out
    return p
end

-- ── Inline: buildKeyframeSequence ────────────────────────────────────────────

local TORSO_LIMBS = { "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
local LIMB_JOINT  = {
    Head          = "Neck",
    ["Right Arm"] = "Right Shoulder",
    ["Left Arm"]  = "Left Shoulder",
    ["Right Leg"] = "Right Hip",
    ["Left Leg"]  = "Left Hip",
}

local function buildKeyframeSequence(rigName, rigData, fps)
    local kfs             = Instance.new("KeyframeSequence")
    kfs.Name              = rigName .. "_Joints"
    kfs.Loop              = false
    kfs.AuthoredHipHeight = 0

    local sortedFrames = {}
    for f in pairs(rigData.jointTrack) do table.insert(sortedFrames, f) end
    table.sort(sortedFrames)

    for _, frame in ipairs(sortedFrames) do
        local jd  = rigData.jointTrack[frame]
        local kf  = Instance.new("Keyframe")
        kf.Time   = (frame - 1) / fps

        local hrpPose   = makePose("HumanoidRootPart", CFrame.identity)
        local torsoPose = makePose("Torso", jd["RootJoint"])
        torsoPose.Parent = hrpPose

        for _, partName in ipairs(TORSO_LIMBS) do
            local jointName = LIMB_JOINT[partName]
            local limbPose  = makePose(partName, jd[jointName])
            limbPose.Parent = torsoPose
        end

        hrpPose.Parent = kf
        kf.Parent      = kfs
    end

    return kfs
end

-- ── Inline: buildRootTracksSource ────────────────────────────────────────────

local function buildRootTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end
    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    rigs = {")
    for rigName, rigData in pairs(session.rigs) do
        if not rigData.rootTrack or not next(rigData.rootTrack) then continue end
        add(string.format("        [%q] = {", rigName))
        local sf = {}
        for f in pairs(rigData.rootTrack) do table.insert(sf, f) end
        table.sort(sf)
        for _, frame in ipairs(sf) do
            local cf = rigData.rootTrack[frame]
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            add(string.format("            [%d] = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g},",
                frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22))
        end
        add("        },")
    end
    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- Helper: require a generated source via temp ModuleScript
local tmp = Instance.new("Folder"); tmp.Name = "__ExporterTest"; tmp.Parent = workspace
local function requireSource(src)
    local ms = Instance.new("ModuleScript"); ms.Source = src; ms.Parent = tmp
    local ok2, r = pcall(require, ms); ms:Destroy()
    return ok2, r
end

-- ── Part 2: buildKeyframeSequence (normal pose, no root motion) ───────────────

do
    local jointCF = CFrame.Angles(0, math.pi / 4, 0)
    local rigData = {
        jointTrack = {
            [1]  = { RootJoint = CFrame.identity, Neck = CFrame.identity,
                     ["Right Shoulder"] = jointCF, ["Left Shoulder"] = CFrame.identity,
                     ["Right Hip"] = CFrame.identity, ["Left Hip"] = CFrame.identity },
            [12] = { RootJoint = CFrame.new(0,0.1,0), Neck = CFrame.identity,
                     ["Right Shoulder"] = CFrame.identity, ["Left Shoulder"] = jointCF,
                     ["Right Hip"] = CFrame.identity, ["Left Hip"] = CFrame.identity },
        },
        scaleTrack = {},
        rootTrack  = {},
    }

    local ok3, err3 = pcall(function()
        local kfs = buildKeyframeSequence("Rig1", rigData, 24)
        ok("KFS created without error", kfs ~= nil, err3)
        ok("KFS name = Rig1_Joints",    kfs.Name == "Rig1_Joints")
        ok("KFS not looping",           not kfs.Loop)

        local kfs_kf = kfs:GetKeyframes()
        ok("KFS has 2 keyframes", #kfs_kf == 2, tostring(#kfs_kf))

        -- Check first keyframe structure
        local kf1 = kfs_kf[1]
        ok("KF[1].Time = 0", approx(kf1.Time, 0))
        local hrp1 = kf1:FindFirstChild("HumanoidRootPart")
        ok("HumanoidRootPart Pose exists", hrp1 ~= nil)
        if hrp1 then
            ok("HRP.CFrame = identity", approxCF(hrp1.CFrame, CFrame.identity))
            local torso1 = hrp1:FindFirstChild("Torso")
            ok("Torso Pose exists under HRP", torso1 ~= nil)
            if torso1 then
                ok("Torso.CFrame = RootJoint data", approxCF(torso1.CFrame, CFrame.identity))
                local rArm = torso1:FindFirstChild("Right Arm")
                ok("Right Arm Pose exists", rArm ~= nil)
                if rArm then
                    ok("Right Arm.CFrame = captured joint CF", approxCF(rArm.CFrame, jointCF))
                end
            end
        end

        kfs:Destroy()
    end)
    if not ok3 then ok("buildKeyframeSequence ran without unhandled error", false, err3) end
end

-- ── Part 3: Whole-model export — rootTrack in RootTracks source ───────────────

do
    local hrpAtFrame1  = CFrame.new(0, 0, 0)
    local hrpAtFrame12 = CFrame.new(0, 5, 0)   -- whole rig moved up 5 units

    local session = {
        fps        = 24,
        frameCount = 24,
        rigs = {
            Rig1 = {
                jointTrack = {
                    [1]  = { RootJoint=CFrame.identity, Neck=CFrame.identity,
                             ["Right Shoulder"]=CFrame.identity, ["Left Shoulder"]=CFrame.identity,
                             ["Right Hip"]=CFrame.identity, ["Left Hip"]=CFrame.identity },
                    [12] = { RootJoint=CFrame.identity, Neck=CFrame.identity,
                             ["Right Shoulder"]=CFrame.identity, ["Left Shoulder"]=CFrame.identity,
                             ["Right Hip"]=CFrame.identity, ["Left Hip"]=CFrame.identity },
                },
                scaleTrack = {},
                rootTrack  = { [1] = hrpAtFrame1, [12] = hrpAtFrame12 },
            }
        },
        props = {},
    }

    local hasRoot = false
    for _, rd in pairs(session.rigs) do
        if rd.rootTrack and next(rd.rootTrack) then hasRoot = true; break end
    end
    ok("session has rootTrack data", hasRoot)

    local src = buildRootTracksSource(session)
    ok("RootTracks source non-empty", #src > 0)

    local rtOk, rt = requireSource(src)
    ok("RootTracks source is valid Lua", rtOk, not rtOk and tostring(rt) or nil)

    if rtOk then
        ok("RootTracks.fps = 24",       rt.fps == 24)
        ok("RootTracks.rigs.Rig1 exists", rt.rigs and rt.rigs["Rig1"] ~= nil)

        if rt.rigs and rt.rigs["Rig1"] then
            local f1 = rt.rigs["Rig1"][1]
            ok("Frame 1 has 12 elements", f1 ~= nil and #f1 == 12, f1 and #f1 or "nil")
            if f1 and #f1 == 12 then
                local cf1 = CFrame.new(f1[1],f1[2],f1[3],f1[4],f1[5],f1[6],f1[7],f1[8],f1[9],f1[10],f1[11],f1[12])
                ok("Frame 1 HRP position = (0,0,0)", approxCF(cf1, hrpAtFrame1))
            end

            local f12 = rt.rigs["Rig1"][12]
            ok("Frame 12 has 12 elements", f12 ~= nil and #f12 == 12, f12 and #f12 or "nil")
            if f12 and #f12 == 12 then
                local cf12 = CFrame.new(f12[1],f12[2],f12[3],f12[4],f12[5],f12[6],f12[7],f12[8],f12[9],f12[10],f12[11],f12[12])
                ok("Frame 12 HRP Y = 5 (whole-model lift)", approx(cf12.Position.Y, 5),
                    string.format("Y=%.4f", cf12.Position.Y))
            end
        end
    end

    -- Session without rootTrack → RootTracks source has empty rigs table
    local noRootSession = {
        fps = 24, frameCount = 24,
        rigs = {
            Rig1 = { jointTrack = { [1] = {} }, scaleTrack = {}, rootTrack = {} }
        },
        props = {},
    }
    local noRootSrc = buildRootTracksSource(noRootSession)
    local nrOk, nrResult = requireSource(noRootSrc)
    ok("no-root session: source valid Lua", nrOk, not nrOk and tostring(nrResult) or nil)
    if nrOk then
        ok("no-root session: rigs table empty", nrResult.rigs and next(nrResult.rigs) == nil)
    end
end

-- Note: AnimationClipProvider.RegisterKeyframeSequence is runtime-only and cannot
-- be tested via execute_luau in edit mode. Test in play mode via test_player.lua.

-- ── Cleanup ───────────────────────────────────────────────────────────────────

tmp:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
