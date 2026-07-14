-- EffectRunner — classify effect instances and fire one-shot effect events.
--
-- An "effect" is a ParticleEmitter, Sound, Light (Point/Spot/Surface), Beam,
-- Trail, Highlight, or a Lighting post-effect (ColorCorrection/Bloom/Blur).
-- Effect events live on the timeline as non-interpolated one-shots: when
-- playback crosses the event's frame, the action fires.
--
-- Kinds and their actions (first action = default):
--   emitter  : emit (Emit(count)), on, off       — ParticleEmitter
--   sound    : play, stop                        — Sound
--   enabled  : on, off                           — Lights / Beam / Trail / Highlight
--                                                  / Lighting post-effects

local EffectRunner = {}

local ENABLED_CLASSES = {
    PointLight = true, SpotLight = true, SurfaceLight = true,
    Beam = true, Trail = true, Highlight = true,
    ColorCorrectionEffect = true, BloomEffect = true, BlurEffect = true,
}

local ACTIONS = {
    emitter = { "emit", "on", "off" },
    sound   = { "play", "stop" },
    enabled = { "on", "off" },
}

EffectRunner.DEFAULT_EMIT_COUNT = 15

-- Returns "emitter" | "sound" | "enabled" | nil for an instance.
function EffectRunner.classify(inst)
    if not inst then return nil end
    if inst:IsA("ParticleEmitter") then return "emitter" end
    if inst:IsA("Sound") then return "sound" end
    if ENABLED_CLASSES[inst.ClassName] then return "enabled" end
    return nil
end

-- Walk a selected instance: if it's an effect, return it; otherwise return
-- the first effect found among its descendants (lets the user select the
-- part/model that holds the emitter).
function EffectRunner.findEffect(inst)
    if EffectRunner.classify(inst) then return inst end
    if inst and (inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Folder")) then
        for _, d in ipairs(inst:GetDescendants()) do
            if EffectRunner.classify(d) then return d end
        end
    end
    return nil
end

function EffectRunner.defaultAction(kind)
    local list = ACTIONS[kind]
    return list and list[1] or nil
end

-- Next action in the kind's cycle (wraps around).
function EffectRunner.cycleAction(kind, action)
    local list = ACTIONS[kind]
    if not list then return action end
    for i, a in ipairs(list) do
        if a == action then
            return list[(i % #list) + 1]
        end
    end
    return list[1]
end

-- Fire one event on a live instance. Safe to call in edit mode.
function EffectRunner.fire(inst, event)
    if not (inst and inst.Parent and event) then return end
    local action = event.action

    if action == "emit" and inst:IsA("ParticleEmitter") then
        inst:Emit(event.count or EffectRunner.DEFAULT_EMIT_COUNT)
    elseif action == "play" and inst:IsA("Sound") then
        inst:Play()
    elseif action == "stop" and inst:IsA("Sound") then
        inst:Stop()
    elseif action == "on" then
        inst.Enabled = true
    elseif action == "off" then
        inst.Enabled = false
    end
end

return EffectRunner
