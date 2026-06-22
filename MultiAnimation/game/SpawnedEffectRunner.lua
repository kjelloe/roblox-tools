-- SpawnedEffectRunner (game-side) — fires spawned effects during MultiAnimPlayer playback.
-- Kept intentionally free of plugin dependencies; only standard Roblox game APIs used.

local SpawnedEffectRunner = {}

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
        task.delay(30, cleanup)
        return
    end

    local part            = Instance.new("Part")
    part.Name             = "__MAnim_SpawnedFX"
    part.Anchored         = true
    part.CanCollide       = false
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

    task.delay((params.duration or 0.6) + (params.lifetime or 1.0), function()
        if part and part.Parent then part:Destroy() end
    end)
end

return SpawnedEffectRunner
