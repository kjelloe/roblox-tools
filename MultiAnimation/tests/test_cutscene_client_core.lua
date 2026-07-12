-- test_cutscene_client_core.lua
-- CutscenePlayer client-side sampling logic: eased keyframe interpolation,
-- camera cut-hold semantics, effect-track event flattening, duration coverage.
-- Inlines the CutscenePlayer helpers so no require() into game modules is needed.

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

local function approx(a, b, eps) return math.abs(a - b) < (eps or 0.001) end
local function approxCF(a, b, eps)
    eps = eps or 0.001
    return (a.Position - b.Position).Magnitude < eps
end

-- ── Inline CutscenePlayer helpers ─────────────────────────────────────────────

local function easedAlpha(t, easing)
    if easing == "Constant" then return 0 end
    if easing == "EaseIn"   then return t * t * t end
    if easing == "EaseOut"  then local u = 1 - t; return 1 - u * u * u end
    if easing == "EaseInOut" then
        if t < 0.5 then return 4 * t * t * t end
        local u = -2 * t + 2; return 1 - u * u * u / 2
    end
    if easing == "Bounce" then
        local n1, d1 = 7.5625, 2.75
        if t < 1/d1 then
            return n1 * t * t
        elseif t < 2/d1 then
            t = t - 1.5/d1; return n1 * t * t + 0.75
        elseif t < 2.5/d1 then
            t = t - 2.25/d1; return n1 * t * t + 0.9375
        else
            t = t - 2.625/d1; return n1 * t * t + 0.984375
        end
    end
    return t
end

local function findKF(kfs, time)
    if #kfs == 0 then return nil, nil end
    local lo, hi = 1, #kfs
    if time <= kfs[1].time then return kfs[1], nil end
    if time >= kfs[#kfs].time then return kfs[#kfs], nil end
    while lo + 1 < hi do
        local mid = math.floor((lo + hi) / 2)
        if kfs[mid].time <= time then lo = mid else hi = mid end
    end
    return kfs[lo], kfs[hi]
end

local function sampleCFrame(kfs, time)
    local a, b = findKF(kfs, time)
    if not a then return CFrame.identity end
    if not b then return a.data end
    local t = easedAlpha((time - a.time) / (b.time - a.time), a.easing)
    return a.data:Lerp(b.data, t)
end

-- Camera sample mirroring CutscenePlayer's Heartbeat camera block.
local function sampleCamera(cameraKFs, t)
    local a, b = findKF(cameraKFs, t)
    if not a then return nil end
    if b and not b.data.cut then
        local frac = easedAlpha((t - a.time) / (b.time - a.time), a.data.easing)
        return a.data.cf:Lerp(b.data.cf, frac),
               (a.data.fov or 70) + ((b.data.fov or 70) - (a.data.fov or 70)) * frac
    end
    return a.data.cf, a.data.fov or 70
end

-- Effect-track flattening mirroring CutscenePlayer.play (target resolution stubbed).
local function flattenEffectEvents(effects, resolve)
    local events = {}
    for _, fx in pairs(effects or {}) do
        local inst = resolve(fx.target)
        if inst then
            for _, ev in ipairs(fx.kfs or {}) do
                table.insert(events, {
                    time   = ev.time,
                    inst   = inst,
                    action = ev.data.action,
                    count  = ev.data.count,
                })
            end
        end
    end
    table.sort(events, function(a, b) return a.time < b.time end)
    return events
end

-- ── Eased sampling ────────────────────────────────────────────────────────────

local cfA = CFrame.new(0, 0, 0)
local cfB = CFrame.new(10, 0, 0)
local kfs = {
    { time = 0, data = cfA, easing = "EaseIn" },
    { time = 1, data = cfB, easing = "Linear" },
}

ok("eased sample: EaseIn midpoint below linear",
    approxCF(sampleCFrame(kfs, 0.5), CFrame.new(10 * 0.125, 0, 0)))
ok("eased sample: t=0 at start", approxCF(sampleCFrame(kfs, 0), cfA))
ok("eased sample: t=1 at end",   approxCF(sampleCFrame(kfs, 1), cfB))
ok("eased sample: clamps past end", approxCF(sampleCFrame(kfs, 2), cfB))

kfs[1].easing = "Constant"
ok("Constant easing holds first keyframe",
    approxCF(sampleCFrame(kfs, 0.9), cfA))

kfs[1].easing = nil
ok("missing easing falls back to linear",
    approxCF(sampleCFrame(kfs, 0.5), CFrame.new(5, 0, 0)))

ok("easedAlpha EaseOut(0.5)", approx(easedAlpha(0.5, "EaseOut"), 0.875))
ok("easedAlpha EaseInOut(0.5)", approx(easedAlpha(0.5, "EaseInOut"), 0.5))
ok("easedAlpha unknown string is linear", approx(easedAlpha(0.3, "Nope"), 0.3))

-- ── Camera cut semantics ──────────────────────────────────────────────────────

local shot1 = CFrame.new(0, 5, 0)
local shot2 = CFrame.new(100, 5, 0)
local camKFs = {
    { time = 0, data = { cf = shot1, fov = 70, cut = false, easing = "Linear" } },
    { time = 2, data = { cf = shot2, fov = 40, cut = true,  easing = "Linear" } },
    { time = 4, data = { cf = shot1, fov = 70, cut = false, easing = "Linear" } },
}

local cf, fov = sampleCamera(camKFs, 1)
ok("segment toward a cut holds the previous shot", approxCF(cf, shot1))
ok("fov also held before cut", approx(fov, 70))

cf, fov = sampleCamera(camKFs, 2)
ok("cut keyframe is jumped to at its time", approxCF(cf, shot2))
ok("fov jumps with the cut", approx(fov, 40))

cf = sampleCamera(camKFs, 3)
ok("segment after a cut interpolates normally",
    approxCF(cf, shot2:Lerp(shot1, 0.5)))

-- ── Effect-track event flattening ─────────────────────────────────────────────

local fakeInst = { Name = "Emitter" }
local effects = {
    Sparks = {
        target = "game.Workspace.FX.Emitter",
        kfs = {
            { time = 0.5, data = { action = "emit", count = 25 } },
            { time = 0.1, data = { action = "on" } },
        },
    },
    Missing = {
        target = "game.Workspace.Nope",
        kfs = { { time = 0.2, data = { action = "emit" } } },
    },
}
local events = flattenEffectEvents(effects, function(target)
    return target == "game.Workspace.FX.Emitter" and fakeInst or nil
end)

ok("unresolvable targets dropped", #events == 2, #events)
ok("events sorted by time", events[1].time == 0.1 and events[2].time == 0.5)
ok("action and count preserved",
    events[2].action == "emit" and events[2].count == 25)
ok("resolved instance attached", events[1].inst == fakeInst)

-- Crossing-window firing: events in (lastT, t] fire exactly once.
local fired = {}
local lastT = -1
for _, t in ipairs({ 0.0, 0.3, 0.3, 1.0 }) do
    for _, ev in ipairs(events) do
        if ev.time > lastT and ev.time <= t then
            table.insert(fired, ev.action)
        end
    end
    lastT = t
end
ok("crossing window fires each event exactly once",
    #fired == 2 and fired[1] == "on" and fired[2] == "emit",
    table.concat(fired, ","))

-- ── Duration includes event-only tails ────────────────────────────────────────

local fps = 24
local duration = 0
for _, kf in ipairs(kfs) do duration = math.max(duration, kf.time) end
for _, ev in ipairs(events) do duration = math.max(duration, ev.time) end
local subtitleEvents = { { frame = 97, text = "The End" } }
for _, ev in ipairs(subtitleEvents) do
    duration = math.max(duration, (ev.frame - 1) / fps)
end
ok("duration extends to last subtitle event", approx(duration, 4))

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
