-- test_spawned_effects_exporter.lua
-- SpawnedEffects ModuleScript source builder: structure, field serialization,
-- loadstring round-trip, omit-if-empty behaviour.
-- Inlines buildSpawnedEffectsSource from core/Exporter.lua.

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

-- ── Inline builder (mirrors Exporter.buildSpawnedEffectsSource) ───────────────

local function buildSpawnedEffectsSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add("    effects = {")
    for _, fx in ipairs(session.spawnedEffects or {}) do
        if fx.effectType == "Sound" then
            add(string.format(
                "        {id=%d, frame=%d, effectType=%q, posX=%.4f, posY=%.4f, posZ=%.4f," ..
                " soundId=%q, volume=%.2f, maxDistance=%.1f},",
                fx.id, fx.frame, fx.effectType, fx.posX or 0, fx.posY or 0, fx.posZ or 0,
                fx.soundId or "", fx.volume or 1, fx.maxDistance or 80
            ))
        elseif fx.effectType == "Fade" then
            add(string.format(
                "        {id=%d, frame=%d, effectType=%q, posX=%.4f, posY=%.4f, posZ=%.4f," ..
                " colorR=%d, colorG=%d, colorB=%d, imageId=%q, duration=%.2f, direction=%q},",
                fx.id, fx.frame, fx.effectType, fx.posX or 0, fx.posY or 0, fx.posZ or 0,
                fx.colorR or 0, fx.colorG or 0, fx.colorB or 0,
                fx.imageId or "", fx.duration or 1, fx.direction or "out"
            ))
        else
            add(string.format(
                "        {id=%d, frame=%d, effectType=%q, posX=%.4f, posY=%.4f, posZ=%.4f," ..
                " size=%.2f, colorR=%d, colorG=%d, colorB=%d, count=%d, duration=%.2f, speed=%.2f, lifetime=%.2f},",
                fx.id, fx.frame, fx.effectType, fx.posX or 0, fx.posY or 0, fx.posZ or 0,
                fx.size or 3, fx.colorR or 255, fx.colorG or 80, fx.colorB or 0,
                fx.count or 50, fx.duration or 0.6, fx.speed or 20, fx.lifetime or 1.0
            ))
        end
    end
    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── 1. Empty session ─────────────────────────────────────────────────────────

local emptySrc = buildSpawnedEffectsSource({ spawnedEffects = {} })
ok("empty source is a string",       type(emptySrc) == "string")
ok("empty source contains effects",  emptySrc:find("effects") ~= nil)
local emptyFn, emptyErr = loadstring(emptySrc)
ok("empty source loadstring OK",     emptyFn ~= nil, emptyErr)
if emptyFn then
    local result = emptyFn()
    ok("empty result is table",          type(result) == "table")
    ok("empty effects is table",         type(result.effects) == "table")
    ok("empty effects has 0 entries",    #result.effects == 0)
end

-- ── 2. Single Explosion entry ────────────────────────────────────────────────

local session1 = {
    spawnedEffects = {
        { id=1, frame=5, effectType="Explosion", posX=10.5, posY=3.0, posZ=-2.25,
          size=3, colorR=255, colorG=80, colorB=0, count=50, duration=0.6, speed=20, lifetime=1.0 },
    },
}
local src1 = buildSpawnedEffectsSource(session1)
ok("Explosion source is string",     type(src1) == "string")
ok("source contains effectType",     src1:find('"Explosion"') ~= nil)
ok("source contains frame=5",        src1:find("frame=5") ~= nil)
ok("source contains posX",           src1:find("posX=10.5") ~= nil or src1:find("posX=10.50") ~= nil)

local fn1, err1 = loadstring(src1)
ok("Explosion source loadstring OK", fn1 ~= nil, err1)
if fn1 then
    local r = fn1()
    ok("result has effects table",   type(r.effects) == "table")
    ok("effects has 1 entry",        #r.effects == 1)
    local e = r.effects[1]
    ok("id round-trips",             e.id == 1)
    ok("frame round-trips",          e.frame == 5)
    ok("effectType round-trips",     e.effectType == "Explosion")
    ok("posX round-trips (approx)",  math.abs(e.posX - 10.5) < 0.001)
    ok("posY round-trips",           math.abs(e.posY - 3.0) < 0.001)
    ok("posZ round-trips (negative)",math.abs(e.posZ - (-2.25)) < 0.001)
    ok("size round-trips",           e.size == 3)
    ok("colorR round-trips",         e.colorR == 255)
    ok("colorG round-trips",         e.colorG == 80)
    ok("colorB round-trips",         e.colorB == 0)
    ok("count round-trips",          e.count == 50)
    ok("duration round-trips",       math.abs(e.duration - 0.6) < 0.01)
    ok("speed round-trips",          e.speed == 20)
    ok("lifetime round-trips",       math.abs(e.lifetime - 1.0) < 0.001)
end

-- ── 3. Smoke entry ───────────────────────────────────────────────────────────

local session2 = {
    spawnedEffects = {
        { id=2, frame=12, effectType="Smoke", posX=0, posY=5, posZ=0,
          size=5, colorR=160, colorG=160, colorB=160, count=25, duration=4.0, speed=4, lifetime=5.0 },
    },
}
local fn2, err2 = loadstring(buildSpawnedEffectsSource(session2))
ok("Smoke source loadstring OK",     fn2 ~= nil, err2)
if fn2 then
    local e = fn2().effects[1]
    ok("Smoke effectType",           e.effectType == "Smoke")
    ok("Smoke size=5",               e.size == 5)
    ok("Smoke duration=4.0",         math.abs(e.duration - 4.0) < 0.01)
    ok("Smoke lifetime=5.0",         math.abs(e.lifetime - 5.0) < 0.001)
end

-- ── 4. Multiple entries ───────────────────────────────────────────────────────

local session3 = {
    spawnedEffects = {
        { id=1, frame=3,  effectType="Explosion", posX=1, posY=0, posZ=0, size=3, colorR=255, colorG=80, colorB=0, count=50, duration=0.6, speed=20, lifetime=1.0 },
        { id=2, frame=10, effectType="Smoke",     posX=5, posY=0, posZ=5, size=5, colorR=160, colorG=160, colorB=160, count=25, duration=4.0, speed=4, lifetime=5.0 },
        { id=3, frame=20, effectType="Explosion", posX=0, posY=0, posZ=-10, size=2, colorR=200, colorG=100, colorB=0, count=30, duration=0.4, speed=15, lifetime=0.8 },
    },
}
local fn3, err3 = loadstring(buildSpawnedEffectsSource(session3))
ok("multi-entry loadstring OK",      fn3 ~= nil, err3)
if fn3 then
    local r = fn3()
    ok("multi-entry count=3",        #r.effects == 3)
    ok("entry 1 id=1",               r.effects[1].id == 1)
    ok("entry 2 id=2",               r.effects[2].id == 2)
    ok("entry 3 id=3",               r.effects[3].id == 3)
    ok("entry 3 effectType",         r.effects[3].effectType == "Explosion")
    ok("entry 3 posZ=-10 (approx)",  math.abs(r.effects[3].posZ - (-10)) < 0.001)
end

-- ── 5. Default field fallbacks ────────────────────────────────────────────────

local session4 = {
    spawnedEffects = {
        { id=1, frame=1, effectType="Explosion", posX=0, posY=0, posZ=0 },
    },
}
local fn4, err4 = loadstring(buildSpawnedEffectsSource(session4))
ok("defaults loadstring OK",         fn4 ~= nil, err4)
if fn4 then
    local e = fn4().effects[1]
    ok("default size=3",             e.size == 3)
    ok("default colorR=255",         e.colorR == 255)
    ok("default count=50",           e.count == 50)
    ok("default duration≈0.6",       math.abs(e.duration - 0.6) < 0.01)
    ok("default speed=20",           e.speed == 20)
    ok("default lifetime=1.0",       math.abs(e.lifetime - 1.0) < 0.001)
end

-- ── 6. Sound entry ───────────────────────────────────────────────────────────

local sessionS = {
    spawnedEffects = {
        { id=7, frame=15, effectType="Sound", posX=5, posY=0, posZ=-3,
          soundId="rbxassetid://12345678", volume=0.75, maxDistance=120 },
    },
}
local srcS, errS = pcall(buildSpawnedEffectsSource, sessionS)
local fnS, errSL = loadstring(buildSpawnedEffectsSource(sessionS))
ok("Sound source loadstring OK",     fnS ~= nil, errSL)
if fnS then
    local eS = fnS().effects[1]
    ok("Sound effectType",           eS.effectType == "Sound")
    ok("Sound id round-trips",       eS.id == 7)
    ok("Sound frame round-trips",    eS.frame == 15)
    ok("Sound soundId round-trips",  eS.soundId == "rbxassetid://12345678")
    ok("Sound volume round-trips",   math.abs(eS.volume - 0.75) < 0.01)
    ok("Sound maxDistance rt",       math.abs(eS.maxDistance - 120) < 0.1)
    ok("Sound has no size field",    eS.size == nil)
    ok("Sound has no colorR field",  eS.colorR == nil)
end

-- ── 6b. Fade entry ────────────────────────────────────────────────────────────

local sessionF = {
    spawnedEffects = {
        { id=9, frame=27, effectType="Fade", posX=0, posY=0, posZ=0,
          colorR=10, colorG=20, colorB=30, imageId="rbxassetid://424242",
          duration=1.5, direction="in" },
    },
}
local fnF, errFL = loadstring(buildSpawnedEffectsSource(sessionF))
ok("Fade source loadstring OK",      fnF ~= nil, errFL)
if fnF then
    local eF = fnF().effects[1]
    ok("Fade effectType",            eF.effectType == "Fade")
    ok("Fade colours round-trip",    eF.colorR == 10 and eF.colorG == 20 and eF.colorB == 30)
    ok("Fade imageId round-trips",   eF.imageId == "rbxassetid://424242")
    ok("Fade duration round-trips",  math.abs(eF.duration - 1.5) < 0.01)
    ok("Fade direction round-trips", eF.direction == "in")
    ok("Fade has no count field",    eF.count == nil)
end

local sessionFD = { spawnedEffects = { { id=1, frame=1, effectType="Fade" } } }
local fnFD = loadstring(buildSpawnedEffectsSource(sessionFD))
ok("Fade defaults loadstring OK",    fnFD ~= nil)
if fnFD then
    local eD = fnFD().effects[1]
    ok("Fade defaults: black, 1s, out",
        eD.colorR == 0 and eD.colorB == 0 and math.abs(eD.duration - 1) < 0.01
        and eD.direction == "out" and eD.imageId == "")
end

-- ── 7. Mixed Explosion + Sound ────────────────────────────────────────────────

local sessionM = {
    spawnedEffects = {
        { id=1, frame=5,  effectType="Explosion", posX=0, posY=0, posZ=0,
          size=3, colorR=255, colorG=80, colorB=0, count=50, duration=0.6, speed=20, lifetime=1.0 },
        { id=2, frame=20, effectType="Sound", posX=1, posY=2, posZ=3,
          soundId="rbxassetid://99", volume=1, maxDistance=80 },
    },
}
local fnM, errM = loadstring(buildSpawnedEffectsSource(sessionM))
ok("mixed loadstring OK",            fnM ~= nil, errM)
if fnM then
    local rM = fnM()
    ok("mixed count=2",              #rM.effects == 2)
    ok("mixed[1] is Explosion",      rM.effects[1].effectType == "Explosion")
    ok("mixed[2] is Sound",          rM.effects[2].effectType == "Sound")
    ok("mixed[1] has size",          rM.effects[1].size == 3)
    ok("mixed[2] soundId",           rM.effects[2].soundId == "rbxassetid://99")
end

-- ── Result ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
if failed == 0 then
    table.insert(out, "ALL TESTS PASSED")
else
    table.insert(out, "FAILURES DETECTED")
end
return table.concat(out, "\n")
