-- test_effect_core.lua
-- EffectRunner logic: classification, default/cycle actions, live firing on
-- real instances, and the event-crossing pointer used by playback.
-- Inlines the EffectRunner logic; creates temp instances and cleans them up.

local out = {}
local passed, failed = 0, 0

local function ok(label, cond, extra)
    if cond then
        passed += 1
        table.insert(out, "PASS  " .. label)
    else
        failed += 1
        table.insert(out, "FAIL  " .. label .. (extra and ("  >> " .. tostring(extra)) or ""))
    end
end

-- ── Inline EffectRunner (mirrors core/EffectRunner.lua) ───────────────────────

local ENABLED_CLASSES = {
    PointLight = true, SpotLight = true, SurfaceLight = true,
    Beam = true, Trail = true, Highlight = true,
}
local ACTIONS = {
    emitter = { "emit", "on", "off" },
    sound   = { "play", "stop" },
    enabled = { "on", "off" },
}

local function classify(inst)
    if not inst then return nil end
    if inst:IsA("ParticleEmitter") then return "emitter" end
    if inst:IsA("Sound") then return "sound" end
    if ENABLED_CLASSES[inst.ClassName] then return "enabled" end
    return nil
end

local function findEffect(inst)
    if classify(inst) then return inst end
    if inst and (inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Folder")) then
        for _, d in ipairs(inst:GetDescendants()) do
            if classify(d) then return d end
        end
    end
    return nil
end

local function cycleAction(kind, action)
    local list = ACTIONS[kind]
    if not list then return action end
    for i, a in ipairs(list) do
        if a == action then return list[(i % #list) + 1] end
    end
    return list[1]
end

local function fire(inst, event)
    if not (inst and inst.Parent and event) then return end
    local action = event.action
    if action == "emit" and inst:IsA("ParticleEmitter") then
        inst:Emit(event.count or 15)
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

-- ── Temp instances ────────────────────────────────────────────────────────────

local tmp = Instance.new("Part")
tmp.Name = "__FxCoreTestPart"
tmp.Anchored = true
tmp.Transparency = 1
tmp.CanCollide = false
tmp.Position = Vector3.new(0, -80, 0)
tmp.Parent = workspace

local emitter = Instance.new("ParticleEmitter")
emitter.Name = "FxEmitter"
emitter.Enabled = false
emitter.Parent = tmp

local sound = Instance.new("Sound")
sound.Name = "FxSound"
sound.Parent = tmp

local light = Instance.new("PointLight")
light.Name = "FxLight"
light.Enabled = false
light.Parent = tmp

-- ── Classification ────────────────────────────────────────────────────────────

ok("ParticleEmitter → emitter", classify(emitter) == "emitter")
ok("Sound → sound", classify(sound) == "sound")
ok("PointLight → enabled", classify(light) == "enabled")
ok("BasePart itself is not an effect", classify(tmp) == nil)
ok("findEffect on the effect returns it", findEffect(emitter) == emitter)
ok("findEffect on the holder part finds a descendant effect", findEffect(tmp) ~= nil)

local plain = Instance.new("Part")
plain.Parent = nil
ok("findEffect on plain unparented part is nil", findEffect(plain) == nil)

-- ── Action cycling ────────────────────────────────────────────────────────────

ok("emitter cycle: emit → on", cycleAction("emitter", "emit") == "on")
ok("emitter cycle: on → off", cycleAction("emitter", "on") == "off")
ok("emitter cycle wraps: off → emit", cycleAction("emitter", "off") == "emit")
ok("sound cycle: play → stop → play",
    cycleAction("sound", "play") == "stop" and cycleAction("sound", "stop") == "play")
ok("enabled cycle: on → off → on",
    cycleAction("enabled", "on") == "off" and cycleAction("enabled", "off") == "on")
ok("unknown action resets to first", cycleAction("emitter", "bogus") == "emit")

-- ── Live firing ───────────────────────────────────────────────────────────────

local okEmit = pcall(fire, emitter, { action = "emit", count = 5 })
ok("emit fires without error", okEmit)

fire(light, { action = "on" })
ok("'on' enables the instance", light.Enabled == true)
fire(light, { action = "off" })
ok("'off' disables the instance", light.Enabled == false)

fire(emitter, { action = "on" })
ok("'on' works for emitters too (continuous mode)", emitter.Enabled == true)
fire(emitter, { action = "off" })

local okPlay = pcall(fire, sound, { action = "play" })
local okStop = pcall(fire, sound, { action = "stop" })
ok("sound play/stop fire without error", okPlay and okStop)

local destroyed = Instance.new("PointLight")  -- never parented; Enabled defaults to true
destroyed.Enabled = false
local okDead = pcall(fire, destroyed, { action = "on" })
ok("firing an unparented instance is a safe no-op", okDead and destroyed.Enabled == false)

-- ── Event-crossing pointer (playback logic) ───────────────────────────────────
-- Mirrors the MultiAnimPlayer loop: fire all events with time <= elapsed, once.

local fired = {}
local events = {
    { time = 0.0, id = "a" },
    { time = 0.5, id = "b" },
    { time = 0.5, id = "c" },
    { time = 1.2, id = "d" },
}
local idx = 1
local function step(elapsed)
    while idx <= #events and events[idx].time <= elapsed do
        table.insert(fired, events[idx].id)
        idx += 1
    end
end

step(0.0)
ok("time-zero event fires on first tick", table.concat(fired, ",") == "a")
step(0.3)
ok("nothing refires between events", table.concat(fired, ",") == "a")
step(0.6)
ok("co-located events both fire when crossed", table.concat(fired, ",") == "a,b,c")
step(0.7)
ok("crossed events never fire twice", table.concat(fired, ",") == "a,b,c")
step(5.0)
ok("late tick catches remaining events", table.concat(fired, ",") == "a,b,c,d")

-- ── Cleanup ───────────────────────────────────────────────────────────────────

tmp:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
