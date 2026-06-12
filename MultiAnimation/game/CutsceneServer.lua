-- CutsceneServer — synchronized multiplayer cutscene playback (server side).
--
-- Plays the rig/prop animation authoritatively on the server (replicates to
-- all clients) and broadcasts the camera track + a shared start timestamp so
-- every client drives its own camera in sync (see CutsceneCamera.lua).
--
-- ServerScript usage:
--   local Cutscene = require(game.ServerStorage.MultiAnimationData.CutsceneServer)
--   Cutscene.play("Scene_001", { Rig1 = workspace.FIGURES.Rig1, ... }, propMap?)
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
local function publishCameraModule()
    if ReplicatedStorage:FindFirstChild("CutsceneCamera") then return end
    local src = script.Parent:FindFirstChild("CutsceneCamera")
    if src then
        src:Clone().Parent = ReplicatedStorage
    end
end

local function loadCameraData(sceneName)
    local mad = game:GetService("ServerStorage"):FindFirstChild("MultiAnimationData")
    local scene = mad and mad:FindFirstChild(sceneName)
    local camModule = scene and scene:FindFirstChild("CameraTrack")
    if not camModule then return nil end
    -- Plain table of numbers/bools — safe to send through a RemoteEvent.
    return require(camModule)
end

function CutsceneServer.play(sceneName, rigMap, propMap)
    local player = require(script.Parent.MultiAnimPlayer)
    publishCameraModule()

    local cameraData = loadCameraData(sceneName)
    local startTime  = workspace:GetServerTimeNow() + START_LEAD

    getRemote():FireAllClients(sceneName, startTime, cameraData)

    -- Start the animation on the same clock the clients use for the camera.
    task.delay(math.max(0, startTime - workspace:GetServerTimeNow()), function()
        player.play(sceneName, rigMap, propMap)
    end)

    return startTime
end

function CutsceneServer.stop()
    local player = require(script.Parent.MultiAnimPlayer)
    player.stop()
    getRemote():FireAllClients("__stop")
end

function CutsceneServer.onFinished(callback)
    local player = require(script.Parent.MultiAnimPlayer)
    player.onFinished(callback)
end

return CutsceneServer
