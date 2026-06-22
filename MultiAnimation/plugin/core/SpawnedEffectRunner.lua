-- SpawnedEffectRunner — preset definitions, property config, and fire() for edit-mode previews.
-- The game-side copy (game/SpawnedEffectRunner.lua) shares the same fire() logic.

local SpawnedEffectRunner = {}

SpawnedEffectRunner.PRESETS = {
    Explosion = {
        size = 3, colorR = 255, colorG = 80, colorB = 0,
        count = 50, duration = 0.6, speed = 20, lifetime = 1.0,
    },
    Smoke = {
        size = 5, colorR = 160, colorG = 160, colorB = 160,
        count = 25, duration = 4.0, speed = 4, lifetime = 5.0,
    },
    Sound = {
        soundId = "", volume = 1, maxDistance = 80,
    },
}

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

-- Create a temporary Part+ParticleEmitter (or Sound) at pos, fire it, then Destroy.
-- Returns a cancel function that destroys it early.
function SpawnedEffectRunner.fire(pos, effectType, params)
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
        snd.Parent            = part
        snd:Play()
        local function cleanup()
            if part and part.Parent then part:Destroy() end
        end
        snd.Ended:Connect(cleanup)
        task.delay(30, cleanup)  -- fallback if Ended never fires
        return cleanup
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
    else  -- Explosion
        pe.SpreadAngle    = Vector2.new(180, 180)
        pe.LightEmission  = 0.8
        pe.LightInfluence = 0.2
    end

    pe.Parent = part
    pe:Emit(params.count or 50)

    local destroyAfter = (params.duration or 0.6) + (params.lifetime or 1.0)
    task.delay(destroyAfter, function()
        if part and part.Parent then part:Destroy() end
    end)

    return function()
        if part and part.Parent then part:Destroy() end
    end
end

return SpawnedEffectRunner
