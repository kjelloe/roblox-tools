-- JointCapture — captures and applies joint poses for any rig type.
-- Works with R6, R15, and custom rigs via dynamic Motor6D discovery.
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
--
-- DISCOVERY FILTER: a Motor6D belongs to the rig if:
--   motor.Parent.Parent == rig   (container is a direct child of the rig model)
--   AND motor.Part1.Parent == rig (Part1 is also a direct child)
-- This excludes accessory welds and nested sub-model motors.
-- motor.Parent is always the original Part0 container, even when Part0 == nil.

local JointCapture = {}

-- ── Discovery ─────────────────────────────────────────────────────────────────

local function discoverMotors(rig)
    local motors = {}
    for _, inst in ipairs(rig:GetDescendants()) do
        if inst:IsA("Motor6D") then
            local container = inst.Parent   -- always the original Part0 container
            local p1        = inst.Part1
            if container and container.Parent == rig
               and p1 and p1.Parent == rig then
                table.insert(motors, inst)
            end
        end
    end
    return motors
end

-- Topological sort: apply parent joints before child joints so FK is correct.
-- HumanoidRootPart is the implicit root (no inbound joint).
local function buildApplyOrder(motors)
    local positioned = { HumanoidRootPart = true }
    local ordered    = {}
    local remaining  = { table.unpack(motors) }
    local maxIter    = (#motors + 1) * (#motors + 1)
    local iter       = 0
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
    -- Append any unresolvable motors (cycle or disconnected sub-graph)
    for _, m in ipairs(remaining) do table.insert(ordered, m) end
    return ordered
end

-- ── Motor connection management ───────────────────────────────────────────────

-- Disconnect all rig joints so parts can be posed independently.
-- Returns an opaque state table for reconnectAll.
function JointCapture.disconnectAll(rig)
    local state = {}
    for _, motor in ipairs(discoverMotors(rig)) do
        table.insert(state, { motor = motor, part0 = motor.Part0 })
        motor.Part0 = nil
    end
    return state
end

-- Restore Motor6D connections from the state returned by disconnectAll.
function JointCapture.reconnectAll(rig, state)
    for _, entry in ipairs(state) do
        if entry.motor and entry.motor.Parent then
            entry.motor.Part0 = entry.part0
        end
    end
end

-- ── Capture ───────────────────────────────────────────────────────────────────

-- Returns { [motorName] = CFrame } computed from current part CFrames.
-- Works whether motors are connected or disconnected.
function JointCapture.capture(rig)
    local result = {}
    for _, motor in ipairs(discoverMotors(rig)) do
        local container = motor.Parent   -- always the Part0 container
        local child     = motor.Part1
        result[motor.Name] = motor.C0:Inverse()
                           * container.CFrame:Inverse()
                           * child.CFrame
                           * motor.C1
    end
    return result
end

function JointCapture.captureRestPose(rig)
    return JointCapture.capture(rig)
end

-- ── Apply ─────────────────────────────────────────────────────────────────────

-- Apply joint data to the rig. Assumes motors are disconnected (via disconnectAll)
-- so each CFrame assignment moves only that part.
function JointCapture.apply(rig, jointData)
    local motors  = discoverMotors(rig)
    local ordered = buildApplyOrder(motors)
    for _, motor in ipairs(ordered) do
        local cf = jointData[motor.Name]
        if not cf then continue end
        local container = motor.Parent
        local child     = motor.Part1
        child.CFrame = container.CFrame * motor.C0 * cf * motor.C1:Inverse()
    end
end

-- Compute world-space CFrames for each rig part without modifying instances.
-- Used by the onion-skin renderer.
-- rootCF: optional world CFrame for HumanoidRootPart.
function JointCapture.computeWorldCFrames(rig, jointData, rootCF)
    local hrp = rig:FindFirstChild("HumanoidRootPart")
    local computed = {}
    computed["HumanoidRootPart"] = rootCF or (hrp and hrp.CFrame) or CFrame.new()
    local motors  = discoverMotors(rig)
    local ordered = buildApplyOrder(motors)
    for _, motor in ipairs(ordered) do
        local cf = jointData and jointData[motor.Name]
        if not cf then continue end
        local containerName = motor.Parent.Name
        local childName     = motor.Part1.Name
        local parentCF = computed[containerName] or motor.Parent.CFrame
        computed[childName] = parentCF * motor.C0 * cf * motor.C1:Inverse()
    end
    return computed
end

-- Returns a list of issues; empty list means rig has discoverable Motor6D joints.
function JointCapture.validate(rig)
    local motors = discoverMotors(rig)
    if #motors == 0 then
        return { "no Motor6D joints found matching rig-joint filter" }
    end
    return {}
end

return JointCapture
