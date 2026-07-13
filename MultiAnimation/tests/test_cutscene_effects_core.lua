-- test_cutscene_effects_core.lua
-- CutsceneServer→CutsceneCamera client-fired effects: remote-safe reshaping of
-- EffectTracks/SpawnedEffects (arrays only — frame-keyed dictionaries are
-- dropped by remote serialization), client event-list building, crossing-window
-- single-fire, and MultiAnimPlayer's skipEffects gate.
-- Inlines the module logic so no require() into game modules is needed.

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

-- ── Inline CutsceneServer.loadEffectData reshaping ────────────────────────────

local function reshapeEffectData(fps, fxTracks, sfxData)
    local o = { fps = fps, effects = {}, spawnedEffects = {} }
    if fxTracks then
        for name, fx in pairs(fxTracks.effects or {}) do
            local events = {}
            for frame, ev in pairs(fx.events or {}) do
                table.insert(events, { frame = frame, action = ev.action, count = ev.count })
            end
            table.insert(o.effects, { name = name, target = fx.target, events = events })
        end
    end
    if sfxData then
        o.spawnedEffects = sfxData.effects or {}
    end
    if #o.effects == 0 and #o.spawnedEffects == 0 then return nil end
    return o
end

-- ── Inline CutsceneCamera.playEffects event-list build ────────────────────────

local function buildEvents(effectData, resolve)
    local fps = effectData.fps or 24
    local events = {}
    for _, fx in ipairs(effectData.effects or {}) do
        local inst = resolve(fx.target)
        if inst then
            for _, ev in ipairs(fx.events or {}) do
                table.insert(events, { time = (ev.frame - 1) / fps, inst = inst,
                                       action = ev.action, count = ev.count })
            end
        end
    end
    for _, sfx in ipairs(effectData.spawnedEffects or {}) do
        table.insert(events, { time = (sfx.frame - 1) / fps, spawned = sfx })
    end
    table.sort(events, function(a, b) return a.time < b.time end)
    return events
end

-- ── Reshaping ─────────────────────────────────────────────────────────────────

local fxTracks = {
    fps = 10,
    effects = {
        Sparks = { target = "game.Workspace.FX.Emitter",
                   events = { [13] = { action = "emit", count = 25 }, [40] = { action = "off" } } },
    },
}
local sfxData = { effects = { { id = 1, frame = 9, effectType = "Smoke", posX = 1, posY = 2, posZ = 3 } } }

local data = reshapeEffectData(10, fxTracks, sfxData)
ok("reshape produces array of effects", #data.effects == 1 and data.effects[1].name == "Sparks")
ok("frame-keyed events become an array", #data.effects[1].events == 2)
ok("event fields preserved", (function()
    for _, ev in ipairs(data.effects[1].events) do
        if ev.frame == 13 and ev.action == "emit" and ev.count == 25 then return true end
    end
    return false
end)())
ok("no numeric-keyed dictionaries remain (remote-safe)", (function()
    for _, fx in ipairs(data.effects) do
        for k in pairs(fx.events) do
            if type(k) ~= "number" or k > #fx.events then return false end
        end
    end
    return true
end)())
ok("spawned effects passed through", #data.spawnedEffects == 1 and data.spawnedEffects[1].frame == 9)
ok("nil when scene has no effects", reshapeEffectData(10, nil, nil) == nil)
ok("nil when tracks exist but are empty",
    reshapeEffectData(10, { effects = {} }, { effects = {} }) == nil)

-- ── Client event-list build ───────────────────────────────────────────────────

local fakeInst = { Name = "Emitter" }
local events = buildEvents(data, function(target)
    return target == "game.Workspace.FX.Emitter" and fakeInst or nil
end)
ok("all events flattened and merged", #events == 3, #events)
ok("sorted by time (spawned at 0.8s first)",
    events[1].spawned ~= nil and math.abs(events[1].time - 0.8) < 0.001,
    events[1].time)
ok("effect event times use fps", math.abs(events[2].time - 1.2) < 0.001, events[2].time)

local dropped = buildEvents(data, function() return nil end)
ok("unresolvable targets drop their events (spawned kept)", #dropped == 1)

-- ── Crossing-window: each event fires exactly once, none before start ─────────

local fired = {}
local nextIdx = 1
for _, elapsed in ipairs({ -0.5, 0.0, 0.9, 0.9, 2.0, 5.0 }) do
    if elapsed >= 0 then
        while nextIdx <= #events and events[nextIdx].time <= elapsed do
            table.insert(fired, events[nextIdx].time)
            nextIdx += 1
        end
    end
end
ok("crossing window fires each event exactly once", #fired == 3, #fired)
ok("nothing fires before the shared clock hits zero", fired[1] > 0)

-- ── MultiAnimPlayer skipEffects gate ──────────────────────────────────────────

local function runPlayerLoop(skipEffects, elapsed)
    local firedCount, idx = 0, 1
    while idx <= #events and events[idx].time <= elapsed do
        if not skipEffects then firedCount += 1 end
        idx += 1
    end
    return firedCount, idx
end

local n1, i1 = runPlayerLoop(false, 10)
local n2, i2 = runPlayerLoop(true, 10)
ok("player fires all events without skipEffects", n1 == 3)
ok("skipEffects suppresses firing but advances pointers", n2 == 0 and i2 == i1)

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
