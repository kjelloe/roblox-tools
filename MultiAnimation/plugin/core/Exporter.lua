-- Exporter — builds KeyframeSequence instances and a ScaleTracks ModuleScript
-- from the recorded session, then writes them to ServerStorage.
--
-- Output layout:
--   ServerStorage.MultiAnimationData.<sceneName>
--     ├── <RigName>_Joints   (KeyframeSequence)
--     └── ScaleTracks        (ModuleScript)
--
-- If the scene folder already exists it is silently overwritten.

local ServerStorage = game:GetService("ServerStorage")

local Exporter = {}

-- R6: Motor6D joint name → the Part1 it drives
local JOINT_TO_PART = {
    RootJoint          = "Torso",
    Neck               = "Head",
    ["Right Shoulder"] = "Right Arm",
    ["Left Shoulder"]  = "Left Arm",
    ["Right Hip"]      = "Right Leg",
    ["Left Hip"]       = "Left Leg",
}

-- Limb parts that live under the Torso Pose (ordered for determinism)
local TORSO_LIMBS = { "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }

-- Which joint drives each limb (inverse of JOINT_TO_PART for Torso's children)
local LIMB_JOINT = {
    Head          = "Neck",
    ["Right Arm"] = "Right Shoulder",
    ["Left Arm"]  = "Left Shoulder",
    ["Right Leg"] = "Right Hip",
    ["Left Leg"]  = "Left Hip",
}

-- ── helpers ───────────────────────────────────────────────────────────────────

local function makePose(name, transform)
    local p           = Instance.new("Pose")
    p.Name            = name
    p.Weight          = 1
    p.CFrame          = transform or CFrame.identity   -- Roblox renamed Pose.Transform → Pose.CFrame
    p.EasingStyle     = Enum.PoseEasingStyle.Linear
    p.EasingDirection = Enum.PoseEasingDirection.Out
    return p
end

-- ── KeyframeSequence builder ──────────────────────────────────────────────────

local function buildKeyframeSequence(rigName, rigData, fps)
    local kfs             = Instance.new("KeyframeSequence")
    kfs.Name              = rigName .. "_Joints"
    kfs.Loop              = false
    kfs.AuthoredHipHeight = 0

    local sortedFrames = {}
    for f in pairs(rigData.jointTrack) do table.insert(sortedFrames, f) end
    table.sort(sortedFrames)

    for _, frame in ipairs(sortedFrames) do
        local jd   = rigData.jointTrack[frame]
        local time = (frame - 1) / fps

        local kf  = Instance.new("Keyframe")
        kf.Time   = time

        -- Pose tree root — HumanoidRootPart has no inbound Motor6D; identity anchor
        local hrpPose   = makePose("HumanoidRootPart", CFrame.identity)

        -- Torso is driven by RootJoint
        local torsoPose = makePose("Torso", jd["RootJoint"])
        torsoPose.Parent = hrpPose

        -- Limbs are children of Torso in the skeleton hierarchy
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

-- ── ScaleTracks source builder ────────────────────────────────────────────────

local function buildScaleTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    rigs = {")

    for rigName, rigData in pairs(session.rigs) do
        if not next(rigData.scaleTrack) then continue end

        add(string.format("        [%q] = {", rigName))

        local sortedFrames = {}
        for f in pairs(rigData.scaleTrack) do table.insert(sortedFrames, f) end
        table.sort(sortedFrames)

        for _, frame in ipairs(sortedFrames) do
            local sd = rigData.scaleTrack[frame]
            add(string.format("            [%d] = {", frame))
            for partName, v3 in pairs(sd) do
                add(string.format(
                    "                [%q] = {%g, %g, %g},",
                    partName, v3.X, v3.Y, v3.Z
                ))
            end
            add("            },")
        end

        add("        },")
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── RootTracks source builder ─────────────────────────────────────────────────
-- World-space HumanoidRootPart CFrames per rig per frame.
-- Absent if no rig had root movement recorded.

local function buildRootTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    rigs = {")

    for rigName, rigData in pairs(session.rigs) do
        if not rigData.rootTrack or not next(rigData.rootTrack) then continue end

        add(string.format("        [%q] = {", rigName))

        local sortedFrames = {}
        for f in pairs(rigData.rootTrack) do table.insert(sortedFrames, f) end
        table.sort(sortedFrames)

        for _, frame in ipairs(sortedFrames) do
            local cf = rigData.rootTrack[frame]
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            add(string.format(
                "            [%d] = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g},",
                frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22
            ))
        end

        add("        },")
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── PropTracks source builder ─────────────────────────────────────────────────

local function buildPropTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    props = {")

    for propName, propData in pairs(session.props or {}) do
        if not next(propData.propTrack) then continue end

        add(string.format("        [%q] = {", propName))

        local sortedFrames = {}
        for f in pairs(propData.propTrack) do table.insert(sortedFrames, f) end
        table.sort(sortedFrames)

        for _, frame in ipairs(sortedFrames) do
            local cf = propData.propTrack[frame]
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            add(string.format(
                "            [%d] = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g},",
                frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22
            ))
        end

        add("        },")
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Exports session data to ServerStorage.MultiAnimationData/<sceneName>/.
-- Returns (true, sceneName) on success or (false, errorMsg) on failure.
-- ── CameraTrack source builder ────────────────────────────────────────────────
-- One camera track per scene: {fps, frames = {[n] = {cf={12 numbers}, fov, cut}}}.
-- cut = true means the camera jumps to this keyframe instead of interpolating.

local function buildCameraTrackSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    frames = {")

    local track = (session.camera and session.camera.track) or {}
    local sortedFrames = {}
    for f in pairs(track) do table.insert(sortedFrames, f) end
    table.sort(sortedFrames)

    for _, frame in ipairs(sortedFrames) do
        local kf = track[frame]
        local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = kf.cf:GetComponents()
        add(string.format(
            "        [%d] = {cf = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g}, fov = %g, cut = %s},",
            frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22,
            kf.fov or 70, tostring(kf.mode == "cut")
        ))
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

function Exporter.export(session, sceneName)
    if not session or not session.rigs or not next(session.rigs) then
        warn("[Exporter] Nothing to export — record some keyframes first")
        return false, "no session data"
    end
    if not sceneName or sceneName:match("^%s*$") then
        warn("[Exporter] Scene name is empty")
        return false, "empty scene name"
    end

    local fps = session.fps or 24

    local mad = ServerStorage:FindFirstChild("MultiAnimationData")
    if not mad then
        mad        = Instance.new("Folder")
        mad.Name   = "MultiAnimationData"
        mad.Parent = ServerStorage
    end

    local existing = mad:FindFirstChild(sceneName)
    if existing then
        existing:Destroy()
        print(string.format("[Exporter] Overwriting existing scene '%s'", sceneName))
    end

    local sceneFolder   = Instance.new("Folder")
    sceneFolder.Name    = sceneName
    sceneFolder.Parent  = mad

    local kfsCount = 0
    for rigName, rigData in pairs(session.rigs) do
        if not next(rigData.jointTrack) then continue end
        local kfs  = buildKeyframeSequence(rigName, rigData, fps)
        kfs.Parent = sceneFolder
        kfsCount  += 1
    end

    local scaleModule        = Instance.new("ModuleScript")
    scaleModule.Name         = "ScaleTracks"
    scaleModule.Source       = buildScaleTracksSource(session)
    scaleModule.Parent       = sceneFolder

    -- RootTracks — only written when any rig had whole-model movement recorded
    local hasRootData = false
    for _, rd in pairs(session.rigs) do
        if rd.rootTrack and next(rd.rootTrack) then hasRootData = true; break end
    end
    if hasRootData then
        local rootModule        = Instance.new("ModuleScript")
        rootModule.Name         = "RootTracks"
        rootModule.Source       = buildRootTracksSource(session)
        rootModule.Parent       = sceneFolder
    end

    -- PropTracks — only written when props were tracked
    local hasPropData = false
    for _, pd in pairs(session.props or {}) do
        if next(pd.propTrack) then hasPropData = true; break end
    end
    if hasPropData then
        local propModule        = Instance.new("ModuleScript")
        propModule.Name         = "PropTracks"
        propModule.Source       = buildPropTracksSource(session)
        propModule.Parent       = sceneFolder
    end

    -- CameraTrack — only written when camera keyframes were recorded
    if session.camera and session.camera.track and next(session.camera.track) then
        local camModule        = Instance.new("ModuleScript")
        camModule.Name         = "CameraTrack"
        camModule.Source       = buildCameraTrackSource(session)
        camModule.Parent       = sceneFolder
    end

    -- Deploy game-side modules alongside the scene data so game scripts can
    -- require them (MultiAnimPlayer + the cutscene pair).
    local gameFolder = script.Parent.Parent:FindFirstChild("game")
    if gameFolder then
        for _, modName in ipairs({ "MultiAnimPlayer", "CutsceneServer", "CutsceneCamera" }) do
            local src = gameFolder:FindFirstChild(modName)
            if src then
                local prev = mad:FindFirstChild(modName)
                if prev then prev:Destroy() end
                src:Clone().Parent = mad
            end
        end
    end

    print(string.format(
        "[Exporter] Scene '%s' exported — %d rig(s) — ServerStorage.MultiAnimationData",
        sceneName, kfsCount
    ))
    return true, sceneName
end

return Exporter
