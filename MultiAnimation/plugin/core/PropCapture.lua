-- PropCapture — reads/writes BasePart world-space CFrame for prop animation.

local PropCapture = {}

function PropCapture.capture(part)
    return part.CFrame
end

function PropCapture.apply(part, cf)
    part.CFrame = cf
end

return PropCapture
