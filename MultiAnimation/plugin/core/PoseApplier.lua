-- PoseApplier — writes joint and scale data back to rig instances.
--
-- Two modes:
--   applyRecorded  — wraps in ChangeHistoryService (scrub, marker jump, step).
--                    One undo step per call. Use sparingly (not in tight loops).
--   applyImmediate — no history recording. Use during playback while history
--                    is already paused via ChangeHistoryService:SetEnabled(false).

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local JointCapture = require(script.Parent.JointCapture)
local ScaleCapture = require(script.Parent.ScaleCapture)
local PropCapture  = require(script.Parent.PropCapture)

local PoseApplier = {}

-- rootCFrame (optional): world-space HumanoidRootPart CFrame.
-- Applied BEFORE joint transforms so limbs position correctly relative to the new root.
local function applyData(rig, jointData, scaleData, rootCFrame)
    if rootCFrame then
        local hrp = rig:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = rootCFrame end
    end
    if jointData then JointCapture.apply(rig, jointData) end
    if scaleData then ScaleCapture.apply(rig, scaleData) end
end

-- Apply and record one undo waypoint.
function PoseApplier.applyRecorded(rig, jointData, scaleData, rootCFrame)
    ChangeHistoryService:SetWaypoint("MultiAnim_Before")
    applyData(rig, jointData, scaleData, rootCFrame)
    ChangeHistoryService:SetWaypoint("MultiAnim_After")
end

-- Apply with no ChangeHistoryService interaction.
-- Caller is responsible for pausing/resuming history around a batch.
function PoseApplier.applyImmediate(rig, jointData, scaleData, rootCFrame)
    applyData(rig, jointData, scaleData, rootCFrame)
end

-- Restore a rig to a stored rest pose.
function PoseApplier.restoreRestPose(rig, restJointData, restScaleData)
    ChangeHistoryService:SetWaypoint("MultiAnim_RestoreBefore")
    applyData(rig, restJointData, restScaleData, nil)
    ChangeHistoryService:SetWaypoint("MultiAnim_RestoreAfter")
end

-- Apply world-space CFrames and visual states to prop BaseParts.
-- propInstances: { [propName] = BasePart }
-- propCFrames:   { [propName] = CFrame }
-- propStates:    optional { [propName] = {t, c, m} } (PropCapture state shape)

local function applyPropData(propInstances, propCFrames, propStates)
    for propName, cf in pairs(propCFrames) do
        local part = propInstances[propName]
        if part and part.Parent then
            part.CFrame = cf
        end
    end
    for propName, st in pairs(propStates or {}) do
        local part = propInstances[propName]
        if part and part.Parent then
            PropCapture.applyState(part, st)
        end
    end
end

function PoseApplier.applyPropRecorded(propInstances, propCFrames, propStates)
    ChangeHistoryService:SetWaypoint("MultiAnim_Before")
    applyPropData(propInstances, propCFrames, propStates)
    ChangeHistoryService:SetWaypoint("MultiAnim_After")
end

function PoseApplier.applyPropImmediate(propInstances, propCFrames, propStates)
    applyPropData(propInstances, propCFrames, propStates)
end

return PoseApplier
