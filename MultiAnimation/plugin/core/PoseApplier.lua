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

local PoseApplier = {}

local function applyData(rig, jointData, scaleData)
    if jointData then JointCapture.apply(rig, jointData) end
    if scaleData then ScaleCapture.apply(rig, scaleData) end
end

-- Apply and record one undo waypoint.
function PoseApplier.applyRecorded(rig, jointData, scaleData)
    ChangeHistoryService:SetWaypoint("MultiAnim_Before")
    applyData(rig, jointData, scaleData)
    ChangeHistoryService:SetWaypoint("MultiAnim_After")
end

-- Apply with no ChangeHistoryService interaction.
-- Caller is responsible for pausing/resuming history around a batch.
function PoseApplier.applyImmediate(rig, jointData, scaleData)
    applyData(rig, jointData, scaleData)
end

-- Restore a rig to a stored rest pose.
function PoseApplier.restoreRestPose(rig, restJointData, restScaleData)
    ChangeHistoryService:SetWaypoint("MultiAnim_RestoreBefore")
    applyData(rig, restJointData, restScaleData)
    ChangeHistoryService:SetWaypoint("MultiAnim_RestoreAfter")
end

return PoseApplier
