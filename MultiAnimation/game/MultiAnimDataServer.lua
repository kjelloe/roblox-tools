-- MultiAnimDataServer — server-side bridge for client-side playback.
-- Creates a "MultiAnimGetScene" RemoteFunction in ReplicatedStorage that clients
-- can invoke to receive fully-parsed, serializable scene data.
--
-- Usage (Script in ServerScriptService):
--   require(game.ServerStorage.MultiAnimationData.MultiAnimDataServer).setup()

local MultiAnimDataServer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

-- Legacy R6 pose-name → motor-name map (old hierarchy export format).
local LEGACY_POSE_TO_JOINT = {
    Torso         = "RootJoint",
    Head          = "Neck",
    ["Right Arm"] = "Right Shoulder",
    ["Left Arm"]  = "Left Shoulder",
    ["Right Leg"] = "Right Hip",
    ["Left Leg"]  = "Left Hip",
}

-- Parse a KeyframeSequence into a serializable list.
-- Handles both the legacy R6 hierarchy format (Torso child under HumanoidRootPart)
-- and the current flat format (motor names as direct children of HumanoidRootPart).
local function parseKFS(kfs)
    local out = {}
    for _, kf in ipairs(kfs:GetKeyframes()) do
        local hrpPose = kf:FindFirstChild("HumanoidRootPart")
        if not hrpPose then continue end
        local poses = {}
        local torsoPose = hrpPose:FindFirstChild("Torso")
        if torsoPose then
            -- Legacy R6 hierarchy format
            poses["RootJoint"] = torsoPose.CFrame
            for _, child in ipairs(torsoPose:GetChildren()) do
                local jName = LEGACY_POSE_TO_JOINT[child.Name]
                if jName then poses[jName] = child.CFrame end
            end
        else
            -- Flat format: each child Pose is named by motor name directly
            for _, child in ipairs(hrpPose:GetChildren()) do
                poses[child.Name] = child.CFrame
            end
        end
        if next(poses) then
            table.insert(out, { time = kf.Time, poses = poses })
        end
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

-- Convert a {[frame]=rawData} table to a sorted time-keyed list.
local function toSortedKFs(frameTable, fps, buildFn)
    local out = {}
    for frame, raw in pairs(frameTable) do
        local t = (tonumber(frame) - 1) / fps
        table.insert(out, { time = t, data = buildFn(raw) })
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

local function cfFromArr(arr)
    return CFrame.new(arr[1],arr[2],arr[3],
                      arr[4],arr[5],arr[6],
                      arr[7],arr[8],arr[9],
                      arr[10],arr[11],arr[12])
end

local function getSceneData(sceneName)
    if type(sceneName) ~= "string" then return nil end
    local mad = ServerStorage:FindFirstChild("MultiAnimationData")
    if not mad then
        warn("[MultiAnimDataServer] ServerStorage.MultiAnimationData not found — export a scene first")
        return nil
    end
    local sceneFolder = mad:FindFirstChild(sceneName)
    if not sceneFolder then
        warn("[MultiAnimDataServer] Scene '" .. sceneName .. "' not found in MultiAnimationData")
        return nil
    end

    local ok, scaleTracks = pcall(function()
        local m = sceneFolder:FindFirstChild("ScaleTracks"); return m and require(m) or nil
    end)
    if not ok then scaleTracks = nil end
    local ok2, propTracks = pcall(function()
        local m = sceneFolder:FindFirstChild("PropTracks");  return m and require(m) or nil
    end)
    if not ok2 then propTracks = nil end
    local ok3, rootTracks = pcall(function()
        local m = sceneFolder:FindFirstChild("RootTracks");  return m and require(m) or nil
    end)
    if not ok3 then rootTracks = nil end
    local ok4, fxTracks = pcall(function()
        local m = sceneFolder:FindFirstChild("EffectTracks"); return m and require(m) or nil
    end)
    if not ok4 then fxTracks = nil end
    local ok5, camTrack = pcall(function()
        local m = sceneFolder:FindFirstChild("CameraTrack"); return m and require(m) or nil
    end)
    if not ok5 then camTrack = nil end

    local fps = (scaleTracks and scaleTracks.fps)
             or (propTracks  and propTracks.fps)
             or (rootTracks  and rootTracks.fps)
             or (fxTracks    and fxTracks.fps)
             or (camTrack    and camTrack.fps)
             or 24

    local out = { fps = fps, rigs = {}, props = {}, camera = {}, effects = {} }

    -- Joint tracks (KeyframeSequence per rig)
    for _, child in ipairs(sceneFolder:GetChildren()) do
        if child:IsA("KeyframeSequence") then
            local rigName = child.Name:match("^(.+)_Joints$")
            if rigName then
                if not out.rigs[rigName] then out.rigs[rigName] = {} end
                out.rigs[rigName].jointKFs = parseKFS(child)
            end
        end
    end

    -- Scale tracks
    if scaleTracks and scaleTracks.rigs then
        for rigName, data in pairs(scaleTracks.rigs) do
            if not out.rigs[rigName] then out.rigs[rigName] = {} end
            out.rigs[rigName].scaleKFs = toSortedKFs(data, fps, function(raw)
                local parts = {}
                for pName, arr in pairs(raw) do
                    parts[pName] = Vector3.new(arr[1], arr[2], arr[3])
                end
                return parts
            end)
        end
    end

    -- Root (whole-rig CFrame) tracks
    if rootTracks and rootTracks.rigs then
        for rigName, data in pairs(rootTracks.rigs) do
            if not out.rigs[rigName] then out.rigs[rigName] = {} end
            out.rigs[rigName].rootKFs = toSortedKFs(data, fps, function(arr)
                return cfFromArr(arr)
            end)
        end
    end

    -- Prop tracks
    if propTracks and propTracks.props then
        for propName, data in pairs(propTracks.props) do
            out.props[propName] = toSortedKFs(data, fps, function(arr)
                return cfFromArr(arr)
            end)
        end
    end

    -- Camera track
    if camTrack and camTrack.frames then
        out.camera = toSortedKFs(camTrack.frames, fps, function(raw)
            return {
                cf  = cfFromArr(raw.cf),
                fov = raw.fov,
                cut = raw.cut or false,
            }
        end)
    end

    -- Effect tracks (pass event times + actions; instance resolution happens on the client)
    if fxTracks and fxTracks.effects then
        for fxName, fx in pairs(fxTracks.effects) do
            local events = fx.events or fx.track or {}
            out.effects[fxName] = {
                target = fx.target,
                kfs    = toSortedKFs(events, fps, function(raw)
                    return { action = raw.action, count = raw.count }
                end),
            }
        end
    end

    return out
end

-- Call this once from a server-side Script (e.g. ServerScriptService).
function MultiAnimDataServer.setup()
    local existing = ReplicatedStorage:FindFirstChild("MultiAnimGetScene")
    if existing then existing:Destroy() end   -- replace stale one on hot-reload

    local remote       = Instance.new("RemoteFunction")
    remote.Name        = "MultiAnimGetScene"
    remote.Parent      = ReplicatedStorage

    remote.OnServerInvoke = function(_player, sceneName)
        return getSceneData(sceneName)
    end
end

return MultiAnimDataServer
