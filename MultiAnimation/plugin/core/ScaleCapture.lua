-- ScaleCapture — reads Part.Size for all seven R6 body parts.
--
-- Scale data is stored separately from joints because KeyframeSequence
-- does not support part scaling. It is replayed in-game via TweenService.
--
-- Returns { [partName] = Vector3 } for every part found.

local ScaleCapture = {}

local R6_PARTS = {
    "Head",
    "Torso",
    "Left Arm",
    "Right Arm",
    "Left Leg",
    "Right Leg",
    "HumanoidRootPart",
}

function ScaleCapture.capture(rig)
    local result = {}
    for _, name in ipairs(R6_PARTS) do
        local part = rig:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            result[name] = part.Size
        end
    end
    return result
end

-- Apply a scale table back onto a rig's parts (used by PoseApplier / in-game).
function ScaleCapture.apply(rig, scaleData)
    for name, size in pairs(scaleData) do
        local part = rig:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            part.Size = size
        end
    end
end

return ScaleCapture
