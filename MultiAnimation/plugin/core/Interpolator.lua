-- Interpolator — eased interpolation between captured keyframes.
--
-- Works against a Recorder instance; does not own data.
-- Returns interpolated joint CFrames and scale Vector3s for any
-- fractional frame position between recorded keyframes.

local TweenService = game:GetService("TweenService")

local EASING_MAP = {
    EaseIn    = { Enum.EasingStyle.Cubic,  Enum.EasingDirection.In    },
    EaseOut   = { Enum.EasingStyle.Cubic,  Enum.EasingDirection.Out   },
    EaseInOut = { Enum.EasingStyle.Cubic,  Enum.EasingDirection.InOut },
    Bounce    = { Enum.EasingStyle.Bounce, Enum.EasingDirection.Out   },
}

local function easedAlpha(t, easing)
    if easing == "Constant" then return 0 end
    if not easing or easing == "Linear" then return t end
    local info = EASING_MAP[easing]
    return info and TweenService:GetValue(t, info[1], info[2]) or t
end

local Interpolator = {}

-- Find the two keyframes surrounding queryFrame in a sorted list.
-- Returns (frameA, frameB, alpha) where alpha is 0..1.
-- If queryFrame is outside the recorded range, clamps to the edge.
local function surrounding(sortedFrames, queryFrame)
    if #sortedFrames == 0 then return nil, nil, 0 end
    if #sortedFrames == 1 then
        return sortedFrames[1], sortedFrames[1], 0
    end
    if queryFrame <= sortedFrames[1] then
        return sortedFrames[1], sortedFrames[1], 0
    end
    if queryFrame >= sortedFrames[#sortedFrames] then
        local last = sortedFrames[#sortedFrames]
        return last, last, 0
    end
    for i = 1, #sortedFrames - 1 do
        local a, b = sortedFrames[i], sortedFrames[i + 1]
        if queryFrame >= a and queryFrame <= b then
            return a, b, (queryFrame - a) / (b - a)
        end
    end
    return nil, nil, 0
end

-- Returns interpolated { [jointName] = CFrame } for rigName at queryFrame,
-- or nil if no keyframes have been recorded for this rig.
function Interpolator.getJointData(recorder, rigName, queryFrame)
    local sorted = recorder:getSortedFrames(rigName)
    if #sorted == 0 then return nil end

    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end

    local dataA = recorder:getJointData(rigName, fA)
    if fA == fB or alpha == 0 then return dataA end

    local dataB = recorder:getJointData(rigName, fB)
    if not dataB then return dataA end

    local t = easedAlpha(alpha, recorder:getEasing(rigName, fA))
    if t == 0 then return dataA end

    local result = {}
    for joint, cfA in pairs(dataA) do
        local cfB = dataB[joint]
        result[joint] = cfB and cfA:Lerp(cfB, t) or cfA
    end
    return result
end

-- Returns interpolated { [partName] = Vector3 } for rigName at queryFrame,
-- or nil if no scale keyframes have been recorded.
function Interpolator.getScaleData(recorder, rigName, queryFrame)
    local sorted = recorder:getSortedFrames(rigName)
    if #sorted == 0 then return nil end

    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end

    local dataA = recorder:getScaleData(rigName, fA)
    if fA == fB or alpha == 0 then return dataA end

    local dataB = recorder:getScaleData(rigName, fB)
    if not dataB then return dataA end

    local t = easedAlpha(alpha, recorder:getEasing(rigName, fA))
    if t == 0 then return dataA end

    local result = {}
    for part, sA in pairs(dataA) do
        local sB = dataB[part]
        result[part] = sB and sA:Lerp(sB, t) or sA
    end
    return result
end

-- Merge all rigs' sorted frame lists into one deduped sorted list.
-- Useful for Prev KF / Next KF navigation across all rigs.
function Interpolator.getAllFrames(recorder, rigNames)
    local seen = {}
    for _, name in ipairs(rigNames) do
        for _, f in ipairs(recorder:getSortedFrames(name)) do
            seen[f] = true
        end
    end
    local result = {}
    for f in pairs(seen) do table.insert(result, f) end
    table.sort(result)
    return result
end

-- Returns interpolated world-space CFrame for the rig's HumanoidRootPart at queryFrame,
-- or nil if no root keyframes exist (whole-model movement not recorded).
function Interpolator.getRootData(recorder, rigName, queryFrame)
    local sorted = recorder:getSortedRootFrames(rigName)
    if #sorted == 0 then return nil end

    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end

    local cfA = recorder:getRootData(rigName, fA)
    if fA == fB or alpha == 0 then return cfA end

    local cfB = recorder:getRootData(rigName, fB)
    if not cfB then return cfA end

    return cfA:Lerp(cfB, easedAlpha(alpha, recorder:getEasing(rigName, fA)))
end

-- Returns interpolated CFrame for propName at queryFrame, or nil if no data.
function Interpolator.getPropData(recorder, propName, queryFrame)
    local sorted = recorder:getSortedPropFrames(propName)
    if #sorted == 0 then return nil end

    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end

    local cfA = recorder:getPropData(propName, fA)
    if fA == fB or alpha == 0 then return cfA end

    local cfB = recorder:getPropData(propName, fB)
    if not cfB then return cfA end

    return cfA:Lerp(cfB, easedAlpha(alpha, recorder:getPropEasing(propName, fA)))
end

-- Returns interpolated camera {cf, fov} at queryFrame, or nil if no camera
-- keyframes exist.  A keyframe with mode == "cut" is not interpolated toward:
-- the previous shot holds until the cut frame itself, then jumps.
function Interpolator.getCameraData(recorder, queryFrame)
    local sorted = recorder:getSortedCameraFrames()
    if #sorted == 0 then return nil end

    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end

    local dataA = recorder:getCameraData(fA)
    if fA == fB or alpha == 0 then
        return { cf = dataA.cf, fov = dataA.fov }
    end

    local dataB = recorder:getCameraData(fB)
    if not dataB then
        return { cf = dataA.cf, fov = dataA.fov }
    end

    if dataB.mode == "cut" then
        if alpha >= 1 then
            return { cf = dataB.cf, fov = dataB.fov }
        end
        return { cf = dataA.cf, fov = dataA.fov }
    end

    local t = easedAlpha(alpha, recorder:getCameraEasing(fA))
    return {
        cf  = dataA.cf:Lerp(dataB.cf, t),
        fov = dataA.fov + (dataB.fov - dataA.fov) * t,
    }
end

-- Merge all props' sorted frame lists into one deduped sorted list.
function Interpolator.getAllPropFrames(recorder, propNames)
    local seen = {}
    for _, name in ipairs(propNames) do
        for _, f in ipairs(recorder:getSortedPropFrames(name)) do
            seen[f] = true
        end
    end
    local result = {}
    for f in pairs(seen) do table.insert(result, f) end
    table.sort(result)
    return result
end

return Interpolator
