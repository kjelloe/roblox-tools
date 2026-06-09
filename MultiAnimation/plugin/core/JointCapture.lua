-- JointCapture — captures and applies R6 joint poses.
--
-- MOTOR6D BEHAVIOUR IN STUDIO EDIT MODE
--   Motor6D acts like a weld: setting any Part.CFrame moves the entire
--   connected assembly.  Motor6D.Transform writes have no visual effect.
--   FIX: permanently disconnect all Motor6D joints (Part0 = nil) while
--   the plugin session is active.  This lets the user pose individual
--   limbs freely, and lets apply() set CFrames independently.
--
-- CAPTURE: derives Transform from actual part CFrames (motors disconnected).
--   Transform = C0:Inv * P0.CFrame:Inv * P1.CFrame * C1
--
-- APPLY: sets each Part.CFrame using forward kinematics (motors disconnected,
--   so only the target part moves).
--   Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inv
--   Order: RootJoint first (sets Torso), then limbs (use Torso.CFrame).

local JointCapture = {}

-- Motor6D name → Part0 container (the part that holds the Motor6D instance).
local JOINT_PARENT = {
    RootJoint          = "HumanoidRootPart",
    Neck               = "Torso",
    ["Right Shoulder"] = "Torso",
    ["Left Shoulder"]  = "Torso",
    ["Right Hip"]      = "Torso",
    ["Left Hip"]       = "Torso",
}

-- Motor6D name → Part1 name (the part that gets moved).
local JOINT_CHILD = {
    RootJoint          = "Torso",
    Neck               = "Head",
    ["Right Shoulder"] = "Right Arm",
    ["Left Shoulder"]  = "Left Arm",
    ["Right Hip"]      = "Right Leg",
    ["Left Hip"]       = "Left Leg",
}

-- Apply order: parent before children (Torso must be positioned before limbs).
local APPLY_ORDER = {
    "RootJoint",
    "Neck",
    "Right Shoulder",
    "Left Shoulder",
    "Right Hip",
    "Left Hip",
}

-- ── Motor connection management ───────────────────────────────────────────────

-- Disconnect all Motor6D joints so parts can be posed independently.
-- Returns a state table { [jointName] = savedPart0 } for later reconnect.
function JointCapture.disconnectAll(rig)
    local state = {}
    for jointName, parentPartName in pairs(JOINT_PARENT) do
        local container = rig:FindFirstChild(parentPartName)
        if container then
            local motor = container:FindFirstChild(jointName)
            if motor and motor:IsA("Motor6D") then
                state[jointName] = motor.Part0   -- may be nil if already disconnected
                motor.Part0 = nil
            end
        end
    end
    return state
end

-- Restore Motor6D connections from a state table returned by disconnectAll.
function JointCapture.reconnectAll(rig, state)
    for jointName, part0 in pairs(state) do
        local parentPartName = JOINT_PARENT[jointName]
        if parentPartName then
            local container = rig:FindFirstChild(parentPartName)
            if container then
                local motor = container:FindFirstChild(jointName)
                if motor and motor:IsA("Motor6D") then
                    motor.Part0 = part0
                end
            end
        end
    end
end

-- ── Capture ───────────────────────────────────────────────────────────────────

local function computeTransform(motor, container)
    -- container = Part0 (passed separately because motor.Part0 may be nil)
    local child = motor.Parent and motor.Parent.Parent
        and motor.Parent.Parent:FindFirstChild(JOINT_CHILD[motor.Name])
    -- Resolve Part1 from rig via JOINT_CHILD table instead of motor.Part1
    return nil  -- placeholder; see capture() below
end

-- Returns { [jointName] = CFrame } computed from current part positions.
-- Works correctly whether motors are connected or disconnected.
function JointCapture.capture(rig)
    local result = {}
    for jointName, parentPartName in pairs(JOINT_PARENT) do
        local container = rig:FindFirstChild(parentPartName)
        if not container then continue end
        local motor = container:FindFirstChild(jointName)
        if not motor or not motor:IsA("Motor6D") then continue end
        local childPartName = JOINT_CHILD[jointName]
        local child = rig:FindFirstChild(childPartName)
        if not child then continue end
        -- Use container.CFrame as Part0 (works even when motor.Part0 is nil)
        result[jointName] = motor.C0:Inverse() * container.CFrame:Inverse() * child.CFrame * motor.C1
    end
    return result
end

function JointCapture.captureRestPose(rig)
    return JointCapture.capture(rig)
end

-- ── Apply ─────────────────────────────────────────────────────────────────────

-- Apply joint data to the rig.  Assumes Motor6D joints are already disconnected
-- (via disconnectAll) so each CFrame assignment moves only that part.
function JointCapture.apply(rig, jointData)
    for _, jointName in ipairs(APPLY_ORDER) do
        local cf = jointData[jointName]
        if not cf then continue end
        local parentPartName = JOINT_PARENT[jointName]
        local childPartName  = JOINT_CHILD[jointName]
        local container = rig:FindFirstChild(parentPartName)
        local child     = rig:FindFirstChild(childPartName)
        if not (container and child) then continue end
        local motor = container:FindFirstChild(jointName)
        if not motor then continue end
        -- Forward kinematics: Part1 = Part0 * C0 * Transform * C1:Inv
        child.CFrame = container.CFrame * motor.C0 * cf * motor.C1:Inverse()
    end
end

-- Returns a list of missing motor/part names; empty list means rig is healthy.
function JointCapture.validate(rig)
    local missing = {}
    for jointName, parentPartName in pairs(JOINT_PARENT) do
        local container = rig:FindFirstChild(parentPartName)
        if not container then
            table.insert(missing, parentPartName .. " (missing)")
        else
            local motor = container:FindFirstChild(jointName)
            if not motor or not motor:IsA("Motor6D") then
                table.insert(missing, jointName .. " (Motor6D missing)")
            end
        end
    end
    table.sort(missing)
    return missing
end

return JointCapture
