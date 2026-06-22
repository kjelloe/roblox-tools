-- test_spawned_effects_core.lua
-- SpawnedEffectRunner preset/buildParams and Recorder spawnedEffects CRUD.
-- Headless — no live instances needed.

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

-- ── Inline SpawnedEffectRunner (mirrors plugin/core/SpawnedEffectRunner.lua) ──

local PRESETS = {
    Explosion = { size=3, colorR=255, colorG=80,  colorB=0,   count=50, duration=0.6, speed=20, lifetime=1.0 },
    Smoke     = { size=5, colorR=160, colorG=160, colorB=160, count=25, duration=4.0, speed=4,  lifetime=5.0 },
    Sound     = { soundId="", volume=1, maxDistance=80 },
}

local PROPS = {
    { key="size",     label="Size"     },
    { key="colorR",   label="Color R"  },
    { key="colorG",   label="Color G"  },
    { key="count",    label="Count"    },
    { key="duration", label="Duration" },
    { key="speed",    label="Speed"    },
    { key="lifetime", label="Lifetime" },
}

local function buildParams(effectType, overrides)
    local base = PRESETS[effectType]
    if not base then return nil end
    local p = {}
    for k, v in pairs(base) do p[k] = v end
    if overrides then for k, v in pairs(overrides) do p[k] = v end end
    return p
end

-- ── Inline Recorder spawnedEffects (mirrors plugin/core/Recorder.lua) ─────────

local function newRecorder()
    local r = {
        _session = { spawnedEffects = {} },
        _nextId  = 1,
    }
    function r:addSpawnedEffect(data)
        local fx = {}
        for k, v in pairs(data) do fx[k] = v end
        if not fx.id then
            fx.id = self._nextId
            self._nextId = self._nextId + 1
        elseif fx.id >= self._nextId then
            self._nextId = fx.id + 1
        end
        table.insert(self._session.spawnedEffects, fx)
        return fx
    end
    function r:updateSpawnedEffect(id, newData)
        for i, fx in ipairs(self._session.spawnedEffects) do
            if fx.id == id then
                for k, v in pairs(newData) do fx[k] = v end
                fx.id = id
                self._session.spawnedEffects[i] = fx
                return fx
            end
        end
    end
    function r:deleteSpawnedEffect(id)
        for i, fx in ipairs(self._session.spawnedEffects) do
            if fx.id == id then table.remove(self._session.spawnedEffects, i); return end
        end
    end
    function r:getSpawnedEffects()
        return self._session.spawnedEffects
    end
    function r:getSpawnedEffectById(id)
        for _, fx in ipairs(self._session.spawnedEffects) do
            if fx.id == id then return fx end
        end
    end
    function r:clearSession()
        self._session.spawnedEffects = {}
        self._nextId = 1
    end
    return r
end

-- ── 1. PRESETS ────────────────────────────────────────────────────────────────

ok("PRESETS has Explosion", PRESETS.Explosion ~= nil)
ok("PRESETS has Smoke",     PRESETS.Smoke ~= nil)
ok("Explosion colorR=255",  PRESETS.Explosion.colorR == 255)
ok("Explosion colorG=80",   PRESETS.Explosion.colorG == 80)
ok("Explosion colorB=0",    PRESETS.Explosion.colorB == 0)
ok("Smoke colorR=160",      PRESETS.Smoke.colorR == 160)
ok("Smoke duration=4.0",    PRESETS.Smoke.duration == 4.0)
ok("Smoke lifetime=5.0",    PRESETS.Smoke.lifetime == 5.0)

-- ── 2. PROPS ─────────────────────────────────────────────────────────────────

ok("PROPS is a table",          type(PROPS) == "table")
ok("PROPS has >=6 entries",     #PROPS >= 6)
local propKeys = {}
for _, p in ipairs(PROPS) do propKeys[p.key] = true end
ok("PROPS includes size",       propKeys["size"])
ok("PROPS includes count",      propKeys["count"])
ok("PROPS includes duration",   propKeys["duration"])
ok("PROPS includes lifetime",   propKeys["lifetime"])

-- ── 3. buildParams ───────────────────────────────────────────────────────────

local p1 = buildParams("Explosion")
ok("buildParams Explosion non-nil",     p1 ~= nil)
ok("buildParams Explosion size=3",      p1 and p1.size == 3)
ok("buildParams Explosion count=50",    p1 and p1.count == 50)

local p2 = buildParams("Smoke")
ok("buildParams Smoke non-nil",         p2 ~= nil)
ok("buildParams Smoke size=5",          p2 and p2.size == 5)

local p3 = buildParams("Explosion", { size = 10, count = 99 })
ok("buildParams override size",         p3 and p3.size == 10)
ok("buildParams override count",        p3 and p3.count == 99)
ok("buildParams non-overridden kept",   p3 and p3.colorR == 255)

ok("buildParams unknown type = nil",    buildParams("Laser") == nil)

-- ── 4. Recorder CRUD ─────────────────────────────────────────────────────────

local rec = newRecorder()

local fx1 = rec:addSpawnedEffect({ frame=5, effectType="Explosion", posX=0, posY=0, posZ=0, size=3 })
ok("addSpawnedEffect returns table",    type(fx1) == "table")
ok("addSpawnedEffect assigns id",       fx1.id ~= nil)
ok("addSpawnedEffect id=1",             fx1.id == 1)
ok("addSpawnedEffect preserves frame",  fx1.frame == 5)
ok("addSpawnedEffect preserves type",   fx1.effectType == "Explosion")

local fx2 = rec:addSpawnedEffect({ frame=10, effectType="Smoke", posX=1, posY=2, posZ=3, size=5 })
ok("second effect id=2",                fx2.id == 2)
ok("getSpawnedEffects count=2",         #rec:getSpawnedEffects() == 2)

local found = rec:getSpawnedEffectById(1)
ok("getSpawnedEffectById(1) found",     found ~= nil)
ok("getSpawnedEffectById type correct", found and found.effectType == "Explosion")

local notFound = rec:getSpawnedEffectById(999)
ok("getSpawnedEffectById missing=nil",  notFound == nil)

rec:updateSpawnedEffect(1, { size = 7, posX = 10 })
local updated = rec:getSpawnedEffectById(1)
ok("updateSpawnedEffect size updated",  updated and updated.size == 7)
ok("updateSpawnedEffect posX updated",  updated and updated.posX == 10)
ok("updateSpawnedEffect id preserved",  updated and updated.id == 1)
ok("updateSpawnedEffect type preserved",updated and updated.effectType == "Explosion")

rec:deleteSpawnedEffect(1)
ok("deleteSpawnedEffect removes entry", #rec:getSpawnedEffects() == 1)
ok("deleted id no longer findable",     rec:getSpawnedEffectById(1) == nil)
ok("remaining entry is fx2",            rec:getSpawnedEffectById(2) ~= nil)

-- ── 5. clearSession resets ───────────────────────────────────────────────────

rec:clearSession()
ok("clearSession empties list",         #rec:getSpawnedEffects() == 0)
local fx3 = rec:addSpawnedEffect({ frame=1, effectType="Explosion", posX=0, posY=0, posZ=0 })
ok("after clearSession id restarts at 1", fx3.id == 1)

-- ── 6. id preservation on restore ───────────────────────────────────────────

local rec2 = newRecorder()
rec2:addSpawnedEffect({ id=5, frame=3, effectType="Smoke", posX=0, posY=0, posZ=0 })
ok("restore with explicit id=5",        rec2:getSpawnedEffectById(5) ~= nil)
local next_fx = rec2:addSpawnedEffect({ frame=4, effectType="Explosion", posX=0, posY=0, posZ=0 })
ok("nextId advanced past restored id",  next_fx.id == 6)

-- ── 7. Sound preset and buildParams ─────────────────────────────────────────

ok("Sound preset exists",           PRESETS.Sound ~= nil)
ok("Sound preset soundId",          PRESETS.Sound.soundId == "")
ok("Sound preset volume=1",         PRESETS.Sound.volume == 1)
ok("Sound preset maxDistance=80",   PRESETS.Sound.maxDistance == 80)
ok("Sound preset no size field",    PRESETS.Sound.size == nil)

local pSound = buildParams("Sound")
ok("buildParams Sound not nil",     pSound ~= nil)
ok("buildParams Sound volume=1",    pSound ~= nil and pSound.volume == 1)
ok("buildParams Sound maxDist=80",  pSound ~= nil and pSound.maxDistance == 80)

local pSoundOv = buildParams("Sound", { soundId="rbxassetid://1", volume=0.5 })
ok("buildParams Sound override",    pSoundOv ~= nil and pSoundOv.soundId == "rbxassetid://1")
ok("buildParams Sound vol override",pSoundOv ~= nil and math.abs(pSoundOv.volume - 0.5) < 0.001)
ok("buildParams Sound maxDist kept",pSoundOv ~= nil and pSoundOv.maxDistance == 80)

-- ── 8. Recorder CRUD with Sound type ────────────────────────────────────────

local recS = newRecorder()
local fxS = recS:addSpawnedEffect({
    frame=3, effectType="Sound", posX=1, posY=0, posZ=0,
    soundId="rbxassetid://99", volume=0.8, maxDistance=120,
})
ok("Sound add returns table",       type(fxS) == "table")
ok("Sound add effectType",          fxS.effectType == "Sound")
ok("Sound add soundId",             fxS.soundId == "rbxassetid://99")
ok("Sound add volume",              fxS.volume == 0.8)
ok("Sound add maxDistance",         fxS.maxDistance == 120)

recS:updateSpawnedEffect(fxS.id, { soundId="rbxassetid://77", volume=0.5 })
local updS = recS:getSpawnedEffectById(fxS.id)
ok("Sound update soundId",          updS and updS.soundId == "rbxassetid://77")
ok("Sound update volume",           updS and math.abs(updS.volume - 0.5) < 0.001)
ok("Sound update effectType kept",  updS and updS.effectType == "Sound")

-- ── Result ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
if failed == 0 then
    table.insert(out, "ALL TESTS PASSED")
else
    table.insert(out, "FAILURES DETECTED")
end
return table.concat(out, "\n")
