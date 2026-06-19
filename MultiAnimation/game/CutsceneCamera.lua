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
--
-- Cut semantics match the editor: a keyframe with cut = true is jumped to,
-- not interpolated toward — the previous shot holds until the cut frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local REMOTE_NAME = "MultiAnimCutscene"

local CutsceneCamera = {}

local conn        = nil    -- RenderStepped connection while playing
local savedState  = nil    -- camera state to restore after the cutscene

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
    -- {fps, frames = {[n] = {cf={12}, fov, cut, easing?}}} → sorted {time, cf, fov, cut, easing}
    local fps = cameraData.fps or 24
    local list = {}
    for frame, kf in pairs(cameraData.frames or {}) do
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

-- Camera pose at `elapsed` seconds: (cf, fov).  Clamps outside the range.
local function sample(kfs, elapsed)
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

local function playCamera(cameraData, startTime)
    stopPlayback()
    local kfs = cameraKeyframes(cameraData)
    if #kfs == 0 then return end

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
        cam.CFrame, cam.FieldOfView = sample(kfs, elapsed)
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
    remote.OnClientEvent:Connect(function(sceneName, startTime, cameraData)
        if sceneName == "__stop" then
            stopPlayback()
        elseif cameraData then
            playCamera(cameraData, startTime)
        end
    end)
end

function CutsceneCamera.stop()
    stopPlayback()
end

return CutsceneCamera
