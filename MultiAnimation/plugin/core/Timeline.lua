-- Timeline — owns the current frame position, fps, and total frame count.
-- Pure data module; no UI or Roblox instance dependencies.

local Timeline = {}
Timeline.__index = Timeline

function Timeline.new(fps, frameCount)
    return setmetatable({
        _fps        = fps        or 24,
        _frameCount = frameCount or 120,
        _current    = 1,
    }, Timeline)
end

function Timeline:getFps()         return self._fps        end
function Timeline:getFrameCount()  return self._frameCount end
function Timeline:getCurrent()     return self._current    end

function Timeline:setFps(v)
    self._fps = math.max(1, math.floor(v))
end

function Timeline:setFrameCount(v)
    self._frameCount = math.max(1, math.floor(v))
    self._current = math.min(self._current, self._frameCount)
end

function Timeline:setCurrent(frame)
    self._current = math.clamp(math.floor(frame), 1, self._frameCount)
    return self._current
end

function Timeline:step(delta)
    return self:setCurrent(self._current + (delta or 1))
end

-- Given a sorted list of keyframe numbers, find the nearest prev/next.
function Timeline:prevKeyframe(sortedFrames)
    local result = nil
    for _, f in ipairs(sortedFrames) do
        if f < self._current then result = f
        else break end
    end
    return result
end

function Timeline:nextKeyframe(sortedFrames)
    for _, f in ipairs(sortedFrames) do
        if f > self._current then return f end
    end
    return nil
end

-- Linear interpolation alpha between two keyframe times.
-- Returns alpha (0–1) and the two surrounding frame numbers,
-- or nil if sortedFrames is empty / only one frame.
function Timeline:interpolationAlpha(sortedFrames, queryFrame)
    if #sortedFrames == 0 then return nil end
    if #sortedFrames == 1 then return 0, sortedFrames[1], sortedFrames[1] end

    queryFrame = queryFrame or self._current

    -- Clamp to range
    if queryFrame <= sortedFrames[1] then
        return 0, sortedFrames[1], sortedFrames[1]
    end
    if queryFrame >= sortedFrames[#sortedFrames] then
        return 1, sortedFrames[#sortedFrames], sortedFrames[#sortedFrames]
    end

    for i = 1, #sortedFrames - 1 do
        local a, b = sortedFrames[i], sortedFrames[i + 1]
        if queryFrame >= a and queryFrame <= b then
            local alpha = (queryFrame - a) / (b - a)
            return alpha, a, b
        end
    end
    return nil
end

return Timeline
