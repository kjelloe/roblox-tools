-- CutsceneCamera — synchronized cutscene camera playback (client side).
--
-- LocalScript usage (e.g. in StarterPlayerScripts):
--   require(game.ReplicatedStorage:WaitForChild("CutsceneCamera")).start()
--
-- Listens for the MultiAnimCutscene RemoteEvent fired by CutsceneServer.
-- On play: waits for the shared server timestamp, sets the local camera to
-- Scriptable, and drives CFrame + FieldOfView from the CameraTrack data every
-- RenderStepped — perfectly aligned across clients because everyone uses
-- workspace:GetServerTimeNow() against the same start time.
-- Also displays the scene's subtitle track (if any) on the same clock, via
-- the SubtitleGui sibling module in ReplicatedStorage, and fires effect-track
-- and spawned-effect one-shots locally (the server suppresses its own copies).
--
-- Cut semantics match the editor: a keyframe with cut = true is jumped to,
-- not interpolated toward — the previous shot holds until the cut frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local REMOTE_NAME = "MultiAnimCutscene"

local CutsceneCamera = {}

local conn        = nil    -- RenderStepped connection while playing
local savedState  = nil    -- camera state to restore after the cutscene
local subConn     = nil    -- RenderStepped connection for subtitles
local _subtitleGui = nil   -- lazily required ReplicatedStorage sibling

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

local function cameraKeyframes(cameraData)
    -- frames arrives as an array of {frame, cf={12}, fov, cut, easing?} (new
    -- servers reshape it for remote safety) or a legacy frame-keyed dictionary.
    local fps = cameraData.fps or 24
    local list = {}
    for k, kf in pairs(cameraData.frames or {}) do
        local frame = kf.frame or k
        table.insert(list, {
            time   = (frame - 1) / fps,
            cf     = CFrame.new(
                kf.cf[1],  kf.cf[2],  kf.cf[3],
                kf.cf[4],  kf.cf[5],  kf.cf[6],
                kf.cf[7],  kf.cf[8],  kf.cf[9],
                kf.cf[10], kf.cf[11], kf.cf[12]),
            fov    = kf.fov or 70,
            cut    = kf.cut == true,
            easing = kf.easing or "Linear",
        })
    end
    table.sort(list, function(a, b) return a.time < b.time end)
    return list
end

-- ── Smooth interpolation (Catmull-Rom-style; same construction as
-- CutscenePlayer/MultiAnimPlayer — keep the copies in sync) ──────────────────

local SMOOTH_K = 1 / 3

local function cubicCF(q1, b1, b2, q2, t)
    local p01 = q1:Lerp(b1, t)
    local p12 = b1:Lerp(b2, t)
    local p23 = b2:Lerp(q2, t)
    return p01:Lerp(p12, t):Lerp(p12:Lerp(p23, t), t)
end

local function smoothCF(q0, q1, q2, q3, t)
    local b1 = q0:Lerp(q1, 1 + SMOOTH_K):Lerp(q1:Lerp(q2, SMOOTH_K), 0.5)
    local b2 = q3:Lerp(q2, 1 + SMOOTH_K):Lerp(q2:Lerp(q1, SMOOTH_K), 0.5)
    return cubicCF(q1, b1, b2, q2, t)
end

-- Camera pose at `elapsed` seconds: (cf, fov).  Clamps outside the range.
local function sample(kfs, elapsed, smooth)
    if elapsed <= kfs[1].time then
        return kfs[1].cf, kfs[1].fov
    end
    local last = kfs[#kfs]
    if elapsed >= last.time then
        return last.cf, last.fov
    end
    for i = 1, #kfs - 1 do
        local a, b = kfs[i], kfs[i + 1]
        if elapsed >= a.time and elapsed < b.time then
            if b.cut then
                return a.cf, a.fov   -- hold the shot until the cut lands
            end
            local t = easedAlpha((elapsed - a.time) / (b.time - a.time), a.easing)
            if smooth then
                -- never build tangents across a cut boundary
                local q0 = kfs[i - 1]
                if not q0 or a.cut then q0 = a end
                local q3 = kfs[i + 2]
                if not q3 or q3.cut then q3 = b end
                return smoothCF(q0.cf, a.cf, b.cf, q3.cf, t),
                       a.fov + (b.fov - a.fov) * t
            end
            return a.cf:Lerp(b.cf, t), a.fov + (b.fov - a.fov) * t
        end
    end
    return last.cf, last.fov
end

local function stopPlayback()
    if conn then
        conn:Disconnect()
        conn = nil
    end
    if savedState then
        local cam = workspace.CurrentCamera
        cam.CameraType  = savedState.camType
        cam.CFrame      = savedState.cf
        cam.FieldOfView = savedState.fov
        savedState = nil
    end
end

local function stopSubtitles()
    if subConn then
        subConn:Disconnect()
        subConn = nil
    end
    if _subtitleGui then pcall(_subtitleGui.hide) end
end

local fxConn = nil
local _spawnedRunner = nil

local function stopEffects()
    if fxConn then
        fxConn:Disconnect()
        fxConn = nil
    end
    -- Runs on "__stop" (fired on stop AND natural completion): a scene that
    -- ends faded-out must not leave the view black.
    if not _spawnedRunner then
        local mod = script.Parent:FindFirstChild("SpawnedEffectRunner")
        _spawnedRunner = mod and require(mod) or nil
    end
    if _spawnedRunner then pcall(_spawnedRunner.clearFades) end
end

local function fireTargetEffect(ev)
    local inst = ev.inst
    if not (inst and inst.Parent) then return end
    if ev.action == "emit" and inst:IsA("ParticleEmitter") then
        inst:Emit(ev.count or 15)
    elseif ev.action == "play" and inst:IsA("Sound") then
        inst:Play()
    elseif ev.action == "stop" and inst:IsA("Sound") then
        inst:Stop()
    elseif ev.action == "on" then
        inst.Enabled = true
    elseif ev.action == "off" then
        inst.Enabled = false
    end
end

-- Client-side one-shot effects on the shared clock. The server suppresses its
-- own copies (MultiAnimPlayer skipEffects) so nothing fires twice; server-side
-- ParticleEmitter:Emit would not replicate to clients anyway.
local function playEffects(effectData, startTime)
    stopEffects()
    local fps = effectData.fps or 24
    local events = {}

    for _, fx in ipairs(effectData.effects or {}) do
        local inst = game
        for seg in string.gmatch(fx.target or "", "[^.]+") do
            if inst == game and seg == "game" then continue end
            inst = inst and inst:FindFirstChild(seg)
        end
        if inst and inst ~= game then
            for _, ev in ipairs(fx.events or {}) do
                table.insert(events, {
                    time   = (ev.frame - 1) / fps,
                    inst   = inst,
                    action = ev.action,
                    count  = ev.count,
                })
            end
        else
            warn("[CutsceneCamera] Effect target not found: " .. tostring(fx.target)
                .. " ('" .. tostring(fx.name) .. "')")
        end
    end

    local spawned = effectData.spawnedEffects or {}
    if #spawned > 0 then
        if not _spawnedRunner then
            local mod = script.Parent:FindFirstChild("SpawnedEffectRunner")
            _spawnedRunner = mod and require(mod) or nil
        end
        if _spawnedRunner then
            for _, sfx in ipairs(spawned) do
                table.insert(events, { time = (sfx.frame - 1) / fps, spawned = sfx })
            end
        else
            warn("[CutsceneCamera] SpawnedEffectRunner not found in ReplicatedStorage")
        end
    end

    if #events == 0 then return end
    table.sort(events, function(a, b) return a.time < b.time end)

    local nextIdx = 1
    fxConn = RunService.RenderStepped:Connect(function()
        local elapsed = workspace:GetServerTimeNow() - startTime
        if elapsed < 0 then return end
        while nextIdx <= #events and events[nextIdx].time <= elapsed do
            local ev = events[nextIdx]
            if ev.spawned then
                pcall(_spawnedRunner.fire,
                    Vector3.new(ev.spawned.posX, ev.spawned.posY, ev.spawned.posZ),
                    ev.spawned.effectType, ev.spawned)
            else
                pcall(fireTargetEffect, ev)
            end
            nextIdx += 1
        end
        if nextIdx > #events then stopEffects() end
    end)
end

-- Stepped subtitle display on the shared clock; text stays up until the next
-- event or the server's "__stop" signal (fired on stop() and natural end).
local function playSubtitles(subData, startTime)
    stopSubtitles()
    if not _subtitleGui then
        local mod = script.Parent:FindFirstChild("SubtitleGui")
        _subtitleGui = mod and require(mod) or nil
    end
    local gui = _subtitleGui
    if not gui then return end
    local events = subData.events or {}
    if #events == 0 then return end
    local fps      = subData.fps or 24
    local style    = subData.style or {}
    local lastText = nil

    subConn = RunService.RenderStepped:Connect(function()
        local elapsed = workspace:GetServerTimeNow() - startTime
        if elapsed < 0 then return end
        local frame  = math.floor(elapsed * fps) + 1
        local active = nil
        for _, ev in ipairs(events) do
            if ev.frame <= frame then active = ev.text else break end
        end
        -- Empty-text events are "clear" markers, not empty bars.
        if active == "" then active = nil end
        if active ~= lastText then
            lastText = active
            if active then pcall(gui.show, active, style) else pcall(gui.hide) end
        end
    end)
end

local function playCamera(cameraData, startTime)
    stopPlayback()
    local kfs = cameraKeyframes(cameraData)
    if #kfs == 0 then return end
    local smooth = cameraData.smooth ~= false   -- default ON

    local cam = workspace.CurrentCamera
    savedState = { camType = cam.CameraType, cf = cam.CFrame, fov = cam.FieldOfView }
    cam.CameraType = Enum.CameraType.Scriptable

    local endTime = kfs[#kfs].time

    conn = RunService.RenderStepped:Connect(function()
        local elapsed = workspace:GetServerTimeNow() - startTime
        if elapsed < 0 then
            -- Start lead: hold the first shot until the shared clock hits zero.
            cam.CFrame, cam.FieldOfView = kfs[1].cf, kfs[1].fov
            return
        end
        cam.CFrame, cam.FieldOfView = sample(kfs, elapsed, smooth)
        if elapsed > endTime then
            stopPlayback()
        end
    end)
end

function CutsceneCamera.start()
    local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME, 30)
    if not remote then
        warn("[CutsceneCamera] RemoteEvent not found — is CutsceneServer in use?")
        return
    end
    remote.OnClientEvent:Connect(function(sceneName, startTime, cameraData, subtitleData, effectData)
        if sceneName == "__stop" then
            stopPlayback()
            stopSubtitles()
            stopEffects()
        else
            if cameraData   then playCamera(cameraData, startTime) end
            if subtitleData then playSubtitles(subtitleData, startTime) end
            if effectData   then playEffects(effectData, startTime) end
        end
    end)
end

function CutsceneCamera.stop()
    stopPlayback()
    stopSubtitles()
    stopEffects()
end

return CutsceneCamera
