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
    p.Transform       = transform or CFrame.identity
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

-- ── Public API ────────────────────────────────────────────────────────────────

-- Exports session data to ServerStorage.MultiAnimationData/<sceneName>/.
-- Returns (true, sceneName) on success or (false, errorMsg) on failure.
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

    print(string.format(
        "[Exporter] Scene '%s' exported — %d rig(s) — ServerStorage.MultiAnimationData",
        sceneName, kfsCount
    ))
    return true, sceneName
end

return Exporter
