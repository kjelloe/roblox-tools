-- ScaleCapture — reads Part.Size for every BasePart that is a direct child
-- of the rig Model (mirrors the dynamic Motor6D discovery filter, so it works
-- for R6, R15, and custom rigs without a hardcoded part list).
--
-- Scale data is stored separately from joints because KeyframeSequence
-- does not support part scaling. It is replayed in-game by MultiAnimPlayer's
-- Heartbeat loop.
--
-- Returns { [partName] = Vector3 } for every part found.

local ScaleCapture = {}

function ScaleCapture.capture(rig)
    local result = {}
    for _, child in ipairs(rig:GetChildren()) do
        if child:IsA("BasePart") then
            result[child.Name] = child.Size
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
