-- PropCapture — reads/writes BasePart world-space CFrame plus the animatable
-- visual state (Transparency, Color, Material) for prop animation.

local PropCapture = {}

function PropCapture.capture(part)
    return part.CFrame
end

function PropCapture.apply(part, cf)
    part.CFrame = cf
end

-- State = { t = Transparency, c = {r,g,b} 0-1 floats, m = Material name }.
-- Plain data so it serializes straight into session JSON and export sources.
function PropCapture.captureState(part)
    local c = part.Color
    return { t = part.Transparency, c = { c.R, c.G, c.B }, m = part.Material.Name }
end

function PropCapture.applyState(part, st)
    if st.t then part.Transparency = st.t end
    if st.c then part.Color = Color3.new(st.c[1], st.c[2], st.c[3]) end
    if st.m then
        -- Material names can change across Roblox versions; ignore unknowns.
        local ok, mat = pcall(function() return Enum.Material[st.m] end)
        if ok and mat then part.Material = mat end
    end
end

return PropCapture
