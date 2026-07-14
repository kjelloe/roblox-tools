-- CutsceneServer — synchronized multiplayer cutscene playback (server side).
--
-- Plays the rig/prop animation authoritatively on the server (replicates to
-- all clients) and broadcasts the camera track, subtitle track, and a shared
-- start timestamp so every client drives its own camera and subtitles in sync
-- (see CutsceneCamera.lua).
--
-- ServerScript usage:
--   local Cutscene = require(game.ServerStorage.MultiAnimationData.CutsceneServer)
--   Cutscene.play("Scene_001", { Rig1 = workspace.FIGURES.Rig1, ... }, propMap?, opts?)
--     opts.smooth (default true) — Catmull-Rom-style interpolation; false = linear
--   Cutscene.stop()
--   Cutscene.onFinished(function(sceneName) ... end)
--
-- Clients must require CutsceneCamera from a LocalScript and call .start()
-- (a copy is placed in ReplicatedStorage.MultiAnimCutscene on first play).
--
-- Known caveat: rig motion reaches clients via replication (~50–100 ms behind
-- the locally-computed camera). Acceptable for v1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_NAME = "MultiAnimCutscene"
local START_LEAD  = 0.35   -- seconds between broadcast and start, so every
                           -- client receives the event before the clock hits 0

local CutsceneServer = {}

local function getRemote()
    local remote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = REMOTE_NAME
        remote.Parent = ReplicatedStorage
    end
    return remote
end

-- Make CutsceneCamera requireable by clients (ServerStorage is not replicated).
-- Replaces a stale copy when the source differs (e.g. after a plugin update).
-- Reading Script.Source requires plugin capability — available to edit-mode
-- tooling, but not to a live game server, where the pcall fails and the
-- deployed copy is kept (the Exporter owns freshness in that flow).
local function publishCameraModule()
    local src = script.Parent:FindFirstChild("CutsceneCamera")
    if not src then return end
    local existing = ReplicatedStorage:FindFirstChild("CutsceneCamera")
    if existing then
        local ok, same = pcall(function()
            return existing.Source == src.Source
        end)
        if not ok or same then return end
        existing:Destroy()
    end
    src:Clone().Parent = ReplicatedStorage
end

local function loadCameraData(sceneName)
    local mad = game:GetService("ServerStorage"):FindFirstChild("MultiAnimationData")
    local scene = mad and mad:FindFirstChild(sceneName)
    local camModule = scene and scene:FindFirstChild("CameraTrack")
    if not camModule then return nil end
    local cam = require(camModule)
    -- Reshape the frame-keyed dictionary to an array: sparse numeric keys are
    -- silently dropped by RemoteEvent serialization (dense Simple-Mode captures
    -- only survived because 1..N dictionaries happen to be arrays).
    local frames = {}
    for frame, kf in pairs(cam.frames or {}) do
        table.insert(frames, {
            frame = frame, cf = kf.cf, fov = kf.fov, cut = kf.cut, easing = kf.easing,
        })
    end
    return { fps = cam.fps, frames = frames }
end

local function findScene(sceneName)
    local mad = game:GetService("ServerStorage"):FindFirstChild("MultiAnimationData")
    return mad and mad:FindFirstChild(sceneName)
end

local function sceneFps(scene)
    for _, modName in ipairs({ "ScaleTracks", "PropTracks", "RootTracks", "CameraTrack", "EffectTracks" }) do
        local m = scene:FindFirstChild(modName)
        if m then
            local t = require(m)
            if t.fps then return t.fps end
        end
    end
    return 24
end

-- Subtitle track + the scene's fps (subtitles are frame-timed; the client
-- needs fps to convert). Nil when the scene has no SubtitleTrack.
local function loadSubtitleData(sceneName)
    local scene = findScene(sceneName)
    local subModule = scene and scene:FindFirstChild("SubtitleTrack")
    if not subModule then return nil end
    local sub = require(subModule)
    return { fps = sceneFps(scene), style = sub.style, events = sub.events }
end

-- Effect tracks + spawned effects, reshaped for the RemoteEvent (frame-keyed
-- dictionaries would be dropped by remote serialization — arrays only).
-- Nil when the scene has neither, so clients skip the scheduler entirely.
local function loadEffectData(sceneName)
    local scene = findScene(sceneName)
    if not scene then return nil end
    local out = { fps = sceneFps(scene), effects = {}, spawnedEffects = {} }
    local fxModule = scene:FindFirstChild("EffectTracks")
    if fxModule then
        for name, fx in pairs(require(fxModule).effects or {}) do
            local events = {}
            for frame, ev in pairs(fx.events or {}) do
                table.insert(events, { frame = frame, action = ev.action, count = ev.count })
            end
            table.insert(out.effects, { name = name, target = fx.target, events = events })
        end
    end
    local sfxModule = scene:FindFirstChild("SpawnedEffects")
    if sfxModule then
        out.spawnedEffects = require(sfxModule).effects or {}
    end
    if #out.effects == 0 and #out.spawnedEffects == 0 then return nil end
    return out
end

local _userFinished = nil

function CutsceneServer.play(sceneName, rigMap, propMap, opts)
    local player = require(script.Parent.MultiAnimPlayer)
    publishCameraModule()

    local smooth = not (opts and opts.smooth == false)   -- default ON
    local cameraData   = loadCameraData(sceneName)
    if cameraData then cameraData.smooth = smooth end
    local subtitleData = loadSubtitleData(sceneName)
    local effectData   = loadEffectData(sceneName)
    local startTime    = workspace:GetServerTimeNow() + START_LEAD

    -- Signal clients on natural completion so camera/subtitles stop in sync.
    -- Register via CutsceneServer.onFinished, not player.onFinished directly —
    -- this wrapper replaces the player-level callback.
    player.onFinished(function(sn)
        getRemote():FireAllClients("__stop")
        if _userFinished then _userFinished(sn) end
    end)

    getRemote():FireAllClients(sceneName, startTime, cameraData, subtitleData, effectData)

    -- Start the animation on the same clock the clients use for the camera.
    -- When clients received effectData they fire effects locally (server-side
    -- ParticleEmitter:Emit does not replicate) — suppress the server copies.
    task.delay(math.max(0, startTime - workspace:GetServerTimeNow()), function()
        player.play(sceneName, rigMap, propMap,
            { skipEffects = effectData ~= nil, smooth = smooth })
    end)

    return startTime
end

function CutsceneServer.stop()
    local player = require(script.Parent.MultiAnimPlayer)
    player.stop()
    getRemote():FireAllClients("__stop")
end

function CutsceneServer.onFinished(callback)
    _userFinished = callback
end

return CutsceneServer
