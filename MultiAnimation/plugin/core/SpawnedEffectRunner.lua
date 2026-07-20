-- SpawnedEffectRunner — preset definitions, property config, and fire() for edit-mode previews.
-- The game-side copy (game/SpawnedEffectRunner.lua) shares the same fire() logic.

local SpawnedEffectRunner = {}

SpawnedEffectRunner.PRESETS = {
    Explosion = {
        size = 3, colorR = 255, colorG = 80, colorB = 0,
        count = 50, duration = 0.6, speed = 20, lifetime = 1.0,
    },
    Flame = {
        size = 4, colorR = 255, colorG = 140, colorB = 30,
        count = 40, duration = 3.0, speed = 6, lifetime = 1.2,
    },
    Electric = {
        size = 2, colorR = 140, colorG = 210, colorB = 255,
        count = 60, duration = 2.0, speed = 10, lifetime = 0.3,
    },
    Sparkles = {
        size = 1.5, colorR = 255, colorG = 230, colorB = 120,
        count = 30, duration = 2.0, speed = 5, lifetime = 1.5,
    },
    Smoke = {
        size = 5, colorR = 160, colorG = 160, colorB = 160,
        count = 25, duration = 4.0, speed = 4, lifetime = 5.0,
    },
    Sound = {
        soundId = "", volume = 1, maxDistance = 80,
        playbackSpeed = 1, looped = false, stopAtFrame = 0, timePosition = 0,
    },
    Fade = {
        colorR = 0, colorG = 0, colorB = 0,
        imageId = "", duration = 1.0, direction = "out",
    },
}

-- Continuous emitters: `count` is particles/second over `duration`, then the
-- emitter shuts off and lingering particles live out `lifetime`. Burst types
-- (Explosion, Smoke) emit `count` once.
SpawnedEffectRunner.CONTINUOUS = { Flame = true, Electric = true, Sparkles = true }

-- Ordered list of editable properties shown in the Effects overlay.
SpawnedEffectRunner.PROPS = {
    { key = "size",     label = "Size"     },
    { key = "colorR",   label = "Color R"  },
    { key = "colorG",   label = "Color G"  },
    { key = "colorB",   label = "Color B"  },
    { key = "count",    label = "Count"    },
    { key = "duration", label = "Duration" },
    { key = "speed",    label = "Speed"    },
    { key = "lifetime", label = "Lifetime" },
}

function SpawnedEffectRunner.buildParams(effectType, overrides)
    local base = SpawnedEffectRunner.PRESETS[effectType]
    if not base then return nil end
    local p = {}
    for k, v in pairs(base) do p[k] = v end
    if overrides then
        for k, v in pairs(overrides) do p[k] = v end
    end
    return p
end

-- Full-screen fade overlay (colour Frame + optional ImageLabel), animated over
-- params.duration. direction "out" fades TO the colour/image, "in" reveals the
-- scene again (and removes the overlay when done). A FadeToken attribute lets a
-- newer fade take over from a still-running one.
local function runFade(gui, params)
    local dur   = math.max(tonumber(params.duration) or 1, 0.05)
    local out   = (params.direction or "out") == "out"
    local frame = gui:FindFirstChild("Color")
    local img   = gui:FindFirstChild("Image")
    frame.BackgroundColor3 = Color3.fromRGB(
        math.clamp(math.floor(params.colorR or 0), 0, 255),
        math.clamp(math.floor(params.colorG or 0), 0, 255),
        math.clamp(math.floor(params.colorB or 0), 0, 255))
    local hasImg = params.imageId ~= nil and params.imageId ~= ""
    img.Image   = hasImg and params.imageId or ""
    img.Visible = hasImg
    local token = (gui:GetAttribute("FadeToken") or 0) + 1
    gui:SetAttribute("FadeToken", token)
    local t0 = os.clock()
    local conn
    conn = game:GetService("RunService").Heartbeat:Connect(function()
        if not gui.Parent or gui:GetAttribute("FadeToken") ~= token then
            conn:Disconnect()
            return
        end
        local a  = math.min((os.clock() - t0) / dur, 1)
        local tr = out and (1 - a) or a
        frame.BackgroundTransparency = tr
        if hasImg then img.ImageTransparency = tr end
        if a >= 1 then
            conn:Disconnect()
            if not out then gui:Destroy() end
        end
    end)
    return function()
        conn:Disconnect()
        if gui and gui.Parent then gui:Destroy() end
    end
end

local function fadeOverlayIn(parent)
    local gui = parent:FindFirstChild("__MAnimFadeGui")
    if gui then return gui end
    gui = Instance.new("ScreenGui")
    gui.Name          = "__MAnimFadeGui"
    gui.DisplayOrder  = 300
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn  = false
    local frame = Instance.new("Frame")
    frame.Name = "Color"
    frame.Size = UDim2.fromScale(1, 1)
    frame.BorderSizePixel = 0
    frame.BackgroundTransparency = 1
    frame.Parent = gui
    local img = Instance.new("ImageLabel")
    img.Name = "Image"
    img.Size = UDim2.fromScale(1, 1)
    img.BackgroundTransparency = 1
    img.ImageTransparency = 1
    img.ScaleType = Enum.ScaleType.Crop
    img.Visible = false
    img.Parent = gui
    gui.Parent = parent
    return gui
end

-- Remove any fade overlay so the view returns to normal (called when preview
-- playback stops — a scene that ends faded-out must not leave the editor black).
function SpawnedEffectRunner.clearFades()
    local gui = game:GetService("CoreGui"):FindFirstChild("__MAnimFadeGui")
    if gui then gui:Destroy() end
end

-- Live cancel functions for long-running effects (looped sounds, continuous
-- emitters). Every playback teardown path calls stopAll() so nothing outlives
-- its scene; already-finished effects cancel harmlessly (guards inside).
local activeCancels = {}

local function register(cancel)
    activeCancels[cancel] = true
    return cancel
end

function SpawnedEffectRunner.stopAll()
    for cancel in pairs(activeCancels) do
        pcall(cancel)
    end
    table.clear(activeCancels)
end

-- Create a temporary Part+ParticleEmitter (or Sound) at pos, fire it, then Destroy.
-- Returns a cancel function that destroys it early.
function SpawnedEffectRunner.fire(pos, effectType, params)
    if effectType == "Fade" then
        -- Edit-mode preview: overlay in CoreGui (plugin context).
        return runFade(fadeOverlayIn(game:GetService("CoreGui")), params)
    end
    if effectType == "Sound" then
        local part        = Instance.new("Part")
        part.Name         = "__MAnim_SpawnedFX"
        part.Anchored     = true; part.CanCollide = false; part.CastShadow = false
        part.Transparency = 1; part.Size = Vector3.new(0.1, 0.1, 0.1)
        part.CFrame       = CFrame.new(pos); part.Parent = workspace
        local snd             = Instance.new("Sound")
        snd.SoundId           = params.soundId or ""
        snd.Volume            = math.clamp(params.volume or 1, 0, 10)
        snd.RollOffMaxDistance = params.maxDistance or 80
        snd.PlaybackSpeed     = math.clamp(params.playbackSpeed or 1, 0.05, 20)
        snd.Looped            = params.looped == true
        snd.Parent            = part
        snd:Play()
        -- Play() resets TimePosition, so the start offset must be set after it.
        if (params.timePosition or 0) > 0 then
            snd.TimePosition = params.timePosition
        end
        local function cleanup()
            activeCancels[cleanup] = nil
            if part and part.Parent then part:Destroy() end
        end
        if snd.Looped then
            -- Loops end at stopAfterSeconds (callers convert stopAtFrame → s)
            -- or at scene teardown via stopAll().
            if (params.stopAfterSeconds or 0) > 0 then
                task.delay(params.stopAfterSeconds, cleanup)
            end
        else
            snd.Ended:Connect(cleanup)
            task.delay(30, cleanup)  -- fallback if Ended never fires
        end
        return register(cleanup)
    end

    local part            = Instance.new("Part")
    part.Name             = "__MAnim_SpawnedFX"
    part.Anchored         = true
    part.CanCollide       = false
    part.CanQuery         = false
    part.CastShadow       = false
    part.Transparency     = 1
    part.Size             = Vector3.new(0.1, 0.1, 0.1)
    part.CFrame           = CFrame.new(pos)
    part.Parent           = workspace

    local pe              = Instance.new("ParticleEmitter")
    pe.Enabled            = false
    pe.Size               = NumberSequence.new(params.size or 3)
    pe.Color              = ColorSequence.new(Color3.fromRGB(
        math.clamp(math.floor(params.colorR or 255), 0, 255),
        math.clamp(math.floor(params.colorG or 80),  0, 255),
        math.clamp(math.floor(params.colorB or 0),   0, 255)
    ))
    pe.Lifetime           = NumberRange.new(
        (params.lifetime or 1.0) * 0.6,
         params.lifetime or 1.0
    )
    pe.Speed              = NumberRange.new(
        (params.speed or 20) * 0.7,
         params.speed or 20
    )
    pe.RotSpeed           = NumberRange.new(-60, 60)
    pe.Rotation           = NumberRange.new(0, 360)

    if effectType == "Smoke" then
        pe.SpreadAngle    = Vector2.new(25, 25)
        pe.LightEmission  = 0
        pe.LightInfluence = 1
    elseif effectType == "Flame" then
        -- Rising fire licks: taper to nothing, glow, drift upward.
        pe.Texture        = "rbxasset://textures/particles/fire_main.dds"
        pe.SpreadAngle    = Vector2.new(12, 12)
        pe.Acceleration   = Vector3.new(0, 6, 0)
        pe.LightEmission  = 1
        pe.LightInfluence = 0
        pe.Size           = NumberSequence.new({
            NumberSequenceKeypoint.new(0, params.size or 4),
            NumberSequenceKeypoint.new(1, 0),
        })
        pe.Transparency   = NumberSequence.new({
            NumberSequenceKeypoint.new(0,   0.1),
            NumberSequenceKeypoint.new(0.7, 0.4),
            NumberSequenceKeypoint.new(1,   1),
        })
    elseif effectType == "Electric" then
        -- Sizzling static surrounding the point: short-lived sparks in every
        -- direction, spinning fast, full glow.
        pe.Texture        = "rbxasset://textures/particles/sparkles_main.dds"
        pe.SpreadAngle    = Vector2.new(180, 180)
        pe.LightEmission  = 1
        pe.LightInfluence = 0
        pe.RotSpeed       = NumberRange.new(-400, 400)
    elseif effectType == "Sparkles" then
        pe.Texture        = "rbxasset://textures/particles/sparkles_main.dds"
        pe.SpreadAngle    = Vector2.new(180, 180)
        pe.Acceleration   = Vector3.new(0, 1, 0)
        pe.LightEmission  = 1
        pe.LightInfluence = 0
    else  -- Explosion
        pe.SpreadAngle    = Vector2.new(180, 180)
        pe.LightEmission  = 0.8
        pe.LightInfluence = 0.2
    end

    pe.Parent = part

    local function cleanup()
        if part and part.Parent then part:Destroy() end
    end

    if SpawnedEffectRunner.CONTINUOUS[effectType] then
        -- Continuous: emit `count`/second for `duration`, then let lingering
        -- particles live out `lifetime` before the part goes away.
        pe.Rate    = params.count or 30
        pe.Enabled = true
        local dur = math.max(params.duration or 2, 0.05)
        local function cancelNow()
            activeCancels[cancelNow] = nil
            cleanup()
        end
        task.delay(dur, function()
            if pe and pe.Parent then pe.Enabled = false end
        end)
        task.delay(dur + (params.lifetime or 1.0), cancelNow)
        return register(cancelNow)
    end

    pe:Emit(params.count or 50)
    local destroyAfter = (params.duration or 0.6) + (params.lifetime or 1.0)
    task.delay(destroyAfter, cleanup)
    return cleanup
end

return SpawnedEffectRunner
