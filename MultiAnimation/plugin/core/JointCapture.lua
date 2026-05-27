-- JointCapture — reads the current Motor6D.Transform for all six R6 joints.
--
-- Motor6D.Transform is the value Roblox's Animator writes to drive poses,
-- and exactly what Pose.Transform stores in a KeyframeSequence — so no
-- conversion is needed between capture and export.
--
-- Returns { [jointName] = CFrame } for every joint found.
-- Missing joints are silently skipped (broken rig guard).

local JointCapture = {}

-- RootJoint lives inside HumanoidRootPart; the rest live inside Torso.
local JOINT_PARENTS = {
    RootJoint        = "HumanoidRootPart",
    Neck             = "Torso",
    ["Right Shoulder"] = "Torso",
    ["Left Shoulder"]  = "Torso",
    ["Right Hip"]      = "Torso",
    ["Left Hip"]       = "Torso",
}

function JointCapture.capture(rig)
    local result = {}

    for jointName, parentName in pairs(JOINT_PARENTS) do
        local parent = rig:FindFirstChild(parentName)
        if parent then
            local motor = parent:FindFirstChild(jointName)
            if motor and motor:IsA("Motor6D") then
                result[jointName] = motor.Transform
            end
        end
    end

    return result
end

-- Capture the rest (T-pose) transforms. Call once at session start
-- so PoseApplier can restore rigs after preview stops.
function JointCapture.captureRestPose(rig)
    return JointCapture.capture(rig)
end

-- Apply a joint table back onto a rig's Motor6Ds (used by PoseApplier).
function JointCapture.apply(rig, jointData)
    for jointName, parentName in pairs(JOINT_PARENTS) do
        local cf = jointData[jointName]
        if cf then
            local parent = rig:FindFirstChild(parentName)
            if parent then
                local motor = parent:FindFirstChild(jointName)
                if motor and motor:IsA("Motor6D") then
                    motor.Transform = cf
                end
            end
        end
    end
end

return JointCapture
