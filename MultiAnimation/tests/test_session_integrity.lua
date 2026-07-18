-- test_session_integrity.lua
-- Structural guards against "a new track type / passive operation silently
-- corrupts session data":
--   1. ROUND-TRIP: a session populated with EVERY feature serializes, loads,
--      and re-serializes byte-equivalently — any field forgotten in
--      serializeSession/restore fails here by path.
--   2. SHIFT IDENTITY: shiftFrames(+1) then shiftFrames(-1) is a no-op across
--      ALL track types — a new track forgotten in shiftFrames desyncs here
--      (the historical spawned-effects/subtitles Insert/Delete bug class).
--   3. INVARIANCE: passive operations (mode round-trips, play+stop, camera
--      view / Look Through / onion toggles, export, navigation sweep) leave
--      the serialized session identical — the generalized capture-hygiene
--      guarantee ("observing the session never changes its bytes").
-- Backs up the live session first and restores it at the end. Live test.

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

local bf = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
local hs = game:GetService("HttpService")
if not bf then
    return "SKIP: __MultiAnimTestBridge not found\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local function call(cmd, args)
    return hs:JSONDecode(bf:Invoke(cmd, args and hs:JSONEncode(args) or nil))
end

-- Serialized-session access: saveSession mirrors JSON into the place file.
local function sessionJSON(slot)
    call("saveSession", { name = slot })
    local folder = game:GetService("ServerStorage"):FindFirstChild("MultiAnimSessions")
    local sv = folder and folder:FindFirstChild(slot)
    return sv and hs:JSONDecode(sv.Value) or nil
end

-- Deep structural compare; returns nil on equality or the path of the first
-- difference. Exact equality — every value has passed through the same
-- JSON-print/parse and float32 CFrame pipeline on both sides.
-- sceneName is excluded: loadNamed deliberately names the scene after the
-- loaded slot, so it changes across a save/load round-trip by design.
local IGNORED_KEYS = { sceneName = true }

local function firstDiff(a, b, path)
    path = path or ""
    if type(a) ~= type(b) then
        return path .. " type " .. type(a) .. " vs " .. type(b)
    end
    if type(a) ~= "table" then
        if a ~= b then return path .. " " .. tostring(a) .. " vs " .. tostring(b) end
        return nil
    end
    for k, v in pairs(a) do
        if not (path == "" and IGNORED_KEYS[k]) then
            if b[k] == nil then return path .. "." .. tostring(k) .. " missing in B" end
            local d = firstDiff(v, b[k], path .. "." .. tostring(k))
            if d then return d end
        end
    end
    for k in pairs(b) do
        if a[k] == nil and not (path == "" and IGNORED_KEYS[k]) then
            return path .. "." .. tostring(k) .. " missing in A"
        end
    end
    return nil
end

-- nil = equal; a string = the first difference (or missing serialization).
local function compare(a, b)
    if not a or not b then return "serialization missing" end
    return firstDiff(a, b)
end

local SLOTS = { "__integ_backup", "__it1", "__it2", "__it3", "__it_op" }

-- ── Backup, then populate every feature ──────────────────────────────────────

call("saveSession", { name = "__integ_backup" })
call("scanFigures")
call("setMode", { mode = "simple" })
task.wait(0.1)

local figures = workspace:FindFirstChild("FIGURES")
if not figures then
    return "SKIP: no FIGURES folder\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end

-- Prop with a ParticleEmitter (prop track + state track + effect lane).
local prop = Instance.new("Part")
prop.Name = "__ITProp"
prop.Anchored = true
prop.CFrame = CFrame.new(10, 4, -20)
prop.Transparency = 0.3
prop.Color = Color3.fromRGB(200, 40, 40)
prop.Material = Enum.Material.Neon
local emitter = Instance.new("ParticleEmitter")
emitter.Name = "__ITSpark"
emitter.Parent = prop
prop.Parent = figures
task.wait(0.2)   -- ChildAdded watcher auto-tracks the prop (deferred)

call("setSimpleFPS", { fps = 24 })
call("setSimpleCamera", { on = true })

-- Three keyframed frames at the end of the timeline via the real Add path.
local fc0 = call("getFrameCount").result or 1
call("simpleNavigate", { frame = fc0 })
call("simpleAddFrame")
local F1, F2, F3 = fc0 + 1, fc0 + 2, fc0 + 3
call("setSimpleCameraCF", { x = 30, y = 10, z = 30, tx = 0, ty = 3, tz = 0 })
call("simpleAddFrame")
call("setSimpleCameraCF", { x = -25, y = 8, z = 20, tx = 0, ty = 3, tz = 0 })
prop.CFrame = CFrame.new(10, 9, -20) * CFrame.Angles(0, math.rad(40), 0)
prop.Transparency = 0.8
call("simpleAddFrame")
prop.Transparency = 0
call("simpleAddFrame")   -- F3

-- Per-track variety: easings, camera cut, effect events, spawned FX, subtitles.
local rigs = call("getRigs").result or {}
if rigs[1] then call("setEasing", { rig = rigs[1], frame = F1, easing = "Bounce" }) end
if rigs[2] then call("setEasing", { rig = rigs[2], frame = F2, easing = "Elastic" }) end
call("setPropEasing",   { prop = "__ITProp", frame = F1, easing = "EaseInOut" })
call("setCameraEasing", { frame = F2, easing = "EaseOut" })
call("setCameraMode",   { frame = F1, mode = "cut" })
call("trackEffect",     { path = "Workspace.FIGURES.__ITProp.__ITSpark" })
call("addEffectEvent",  { name = "__ITSpark", frame = F1, action = "emit", count = 12 })
call("addEffectEvent",  { name = "__ITSpark", frame = F3, action = "on" })
call("addSpawnedEffect", { frame = F1, effectType = "Explosion",
    posX = 5, posY = 6, posZ = 7, size = 3, colorR = 255, colorG = 80, colorB = 0,
    count = 30, duration = 0.4, speed = 15, lifetime = 0.8 })
call("addSpawnedEffect", { frame = F2, effectType = "Sound",
    posX = 1, posY = 2, posZ = 3, soundId = "rbxassetid://12345", volume = 0.7,
    maxDistance = 60 })
call("setSubtitleEnabled", { enabled = true })
call("setSubtitleStyle", { size = 30, yOffset = 0.8 })
call("setSubtitleEvent", { frame = F1, text = "Integrity check" })
call("setSubtitleEvent", { frame = F3, text = "" })

-- ── 1. Serialize → load → serialize round-trip ───────────────────────────────

local s1 = sessionJSON("__it1")
call("loadSession", { name = "__it1" })
task.wait(0.2)
local s2 = sessionJSON("__it2")
local d = compare(s1, s2)
ok("serialize → load → serialize is lossless for every track type", d == nil, d)

-- ── 2. shiftFrames(+1) then shiftFrames(-1) is identity ──────────────────────

call("shiftFrames", { from = 1, delta = 1 })
call("shiftFrames", { from = 2, delta = -1 })
local s3 = sessionJSON("__it3")
d = compare(s2, s3)
ok("shift(+1) then shift(-1) is identity across all track types", d == nil, d)

-- ── 3. Passive operations leave the session byte-identical ───────────────────

local baseline = s3
local function invariant(label, op)
    op()
    local diff = compare(baseline, sessionJSON("__it_op"))
    ok("invariant: " .. label, diff == nil, diff)
end

invariant("mode round-trip simple→advanced→simple", function()
    call("setMode", { mode = "advanced" })
    call("setMode", { mode = "simple" })
    task.wait(0.1)
end)
invariant("mode round-trip simple→playback→simple", function()
    call("setMode", { mode = "playback" })
    call("setMode", { mode = "simple" })
    task.wait(0.1)
end)
invariant("play then stop", function()
    call("simpleTogglePlay")
    task.wait(0.35)
    call("simpleTogglePlay")
    task.wait(0.1)
end)
invariant("Camera View off/on", function()
    call("setSimpleCamera", { on = false })
    call("setSimpleCamera", { on = true })
end)
invariant("Look Through on/off", function()
    call("setSimpleLookThrough", { on = true })
    task.wait(0.2)
    call("setSimpleLookThrough", { on = false })
end)
invariant("Onion Skin on/off", function()
    call("setSimpleOnion", { on = true })
    task.wait(0.1)
    call("setSimpleOnion", { on = false })
end)
invariant("navigation sweep over data frames", function()
    for _, f in ipairs({ F1, F2, F3, F1 }) do
        call("simpleNavigate", { frame = f })
    end
end)
invariant("export", function()
    call("exportScene", { name = "__ITScene" })
end)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

local mad = game:GetService("ServerStorage"):FindFirstChild("MultiAnimationData")
local scene = mad and mad:FindFirstChild("__ITScene")
if scene then scene:Destroy() end
local pads = workspace:FindFirstChild("AnimTriggerPads")
local pad = pads and pads:FindFirstChild("Pad___ITScene")
if pad then pad:Destroy() end
for _, inst in ipairs(workspace:GetDescendants()) do
    if inst.Name:find("__ITScene") then inst:Destroy() end
end
prop:Destroy()
task.wait(0.2)   -- ChildRemoved watcher untracks the prop
call("loadSession", { name = "__integ_backup" })
task.wait(0.2)
for _, slot in ipairs(SLOTS) do
    call("deleteSession", { name = slot })
end
ok("cleanup: backup restored and temp slots removed",
    call("getRigs").result ~= nil)

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
