-- MultiAnimPlayer — in-game playback of exported MultiAnimation scenes.
--
-- No plugin dependency; uses only standard Roblox game APIs.
-- Place (or require from) ServerStorage.MultiAnimationData.MultiAnimPlayer.
--
-- API:
--   player.play(sceneName, rigMap, propMap?)
--       sceneName  string         — matches the scene name used at export time
--       rigMap     {[name]=Model} — keys match rig names from the plugin session
--       propMap    {[name]=BasePart}? — optional; keys match tracked prop names
--
--   player.stop()
--       Stops all active playback immediately and fires onFinished.
--
--   player.onFinished(callback)
--       callback(sceneName: string) — fired on natural completion or stop().
--       Replaces any previously registered callback.
--
-- Example:
--   local player = require(game.ServerStorage.MultiAnimationData.MultiAnimPlayer)
--   player.onFinished(function(s) print(s .. " finished") end)
--   player.play("Scene_001",
--       { Rig1 = workspace.FIGURES.Rig1, Rig2 = workspace.FIGURES.Rig2 },
--       { Block = workspace.Block }   -- omit if no props
--   )

local RunService            = game:GetService("RunService")
local AnimationClipProvider = game:GetService("AnimationClipProvider")

local MultiAnimPlayer = {}

-- ── module-level playback state ───────────────────────────────────────────────

local _finishedCb  = nil   -- single registered callback
local _heartbeat   = nil   -- RBXScriptConnection
local _tracks      = {}    -- AnimationTrack list for current play
local _sceneName   = nil   -- scene currently playing
local _propState   = {}    -- { [propName] = {part=BasePart, kfs={...}} } for current play

-- ── helpers ───────────────────────────────────────────────────────────────────

local PART_TO_JOINT = {
    Torso         = "RootJoint",
    Head          = "Neck",
    ["Right Arm"] = "Right Shoulder",
    ["Left Arm"]  = "Left Shoulder",
    ["Right Leg"] = "Right Hip",
    ["Left Leg"]  = "Left Hip",
}

-- Build a sorted { {time, poses={[jointName]=CFrame}} } list from a KFS.
local function kfsToKeyframes(kfs)
    local out = {}
    for _, kf in ipairs(kfs:GetKeyframes()) do
        local hrpPose = kf:FindFirstChild("HumanoidRootPart")
        if not hrpPose then continue end
        local torsoPose = hrpPose:FindFirstChild("Torso")
        if not torsoPose then continue end

        local poses = { RootJoint = torsoPose.CFrame }
        for _, child in ipairs(torsoPose:GetChildren()) do
            local jName = PART_TO_JOINT[child.Name]
            if jName then poses[jName] = child.CFrame end
        end
        table.insert(out, { time = kf.Time, poses = poses })
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

-- Gather all Motor6D joints for an R6 rig model.
local function findJoints(rigModel)
    local joints = {}
    local hrp   = rigModel:FindFirstChild("HumanoidRootPart")
    local torso = rigModel:FindFirstChild("Torso")
    if hrp then
        local j = hrp:FindFirstChild("RootJoint")
        if j then joints["RootJoint"] = j end
    end
    if torso then
        for _, name in ipairs({"Neck","Right Shoulder","Left Shoulder","Right Hip","Left Hip"}) do
            local j = torso:FindFirstChild(name)
            if j then joints[name] = j end
        end
    end
    return joints
end

-- Build a sorted { {time, cf=CFrame} } list from a prop's keyframe data.
-- Array layout matches Exporter: {x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22}
local function propToKeyframes(propKFData, fps)
    local out = {}
    for frame, arr in pairs(propKFData) do
        local cf = CFrame.new(
            arr[1], arr[2], arr[3],
            arr[4], arr[5], arr[6],
            arr[7], arr[8], arr[9],
            arr[10], arr[11], arr[12]
        )
        table.insert(out, { time = (frame - 1) / fps, cf = cf })
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

-- Build a sorted { {time, parts={[partName]=Vector3}} } list from the scale table.
local function scaleToKeyframes(rigScaleData, fps)
    local out = {}
    for frame, partData in pairs(rigScaleData) do
        local parts = {}
        for pName, arr in pairs(partData) do
            parts[pName] = Vector3.new(arr[1], arr[2], arr[3])
        end
        table.insert(out, { time = (frame - 1) / fps, parts = parts })
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

-- Find the two surrounding entries in a sorted keyframe list for a given time.
local function surroundingKFs(kfs, elapsed)
    local before = kfs[1]
    local after  = kfs[#kfs]
    for i = 1, #kfs do
        if kfs[i].time <= elapsed then before = kfs[i] end
        if kfs[i].time >= elapsed then after = kfs[i]; break end
    end
    return before, after
end

-- Linear interpolation between two keyframe entries (poses or parts).
local function lerpKFs(before, after, elapsed, lerpFn, key)
    if before == after or after.time <= before.time then
        return before[key]
    end
    local alpha = math.clamp((elapsed - before.time) / (after.time - before.time), 0, 1)
    local result = {}
    for k, a in pairs(before[key]) do
        result[k] = lerpFn(a, after[key][k] or a, alpha)
    end
    return result
end

local function clearActive()
    if _heartbeat then _heartbeat:Disconnect(); _heartbeat = nil end
    for _, t in ipairs(_tracks) do
        if t.IsPlaying then t:Stop(0) end
    end
    _tracks    = {}
    _sceneName = nil
    _propState = {}
end

local function fireFinished(sn)
    if _finishedCb then pcall(_finishedCb, sn) end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function MultiAnimPlayer.onFinished(callback)
    _finishedCb = callback
end

function MultiAnimPlayer.stop()
    if not _sceneName then return end
    local sn = _sceneName
    clearActive()
    fireFinished(sn)
end

function MultiAnimPlayer.play(sceneName, rigMap, propMap)
    if _sceneName then clearActive() end

    local ServerStorage = game:GetService("ServerStorage")
    local mad = ServerStorage:FindFirstChild("MultiAnimationData")
    assert(mad, "ServerStorage.MultiAnimationData not found — export a scene first")
    local sceneFolder = mad:FindFirstChild(sceneName)
    assert(sceneFolder, "Scene '" .. sceneName .. "' not found in MultiAnimationData")

    local scaleModule = sceneFolder:FindFirstChild("ScaleTracks")
    local scaleTracks = scaleModule and require(scaleModule) or nil
    local propModule  = sceneFolder:FindFirstChild("PropTracks")
    local propTracks  = propModule  and require(propModule)  or nil
    local rootModule  = sceneFolder:FindFirstChild("RootTracks")
    local rootTracks  = rootModule  and require(rootModule)  or nil
    local fps = (scaleTracks and scaleTracks.fps)
             or (propTracks  and propTracks.fps)
             or (rootTracks  and rootTracks.fps)
             or 24

    -- ── Joint animation via Animator ──────────────────────────────────────────

    local tracks = {}
    local totalLength = 0

    for rigName, rigModel in pairs(rigMap) do
        local kfs = sceneFolder:FindFirstChild(rigName .. "_Joints")
        if not kfs then
            warn("[MultiAnimPlayer] No KeyframeSequence for '" .. rigName .. "'")
            continue
        end

        -- Compute duration from the KFS itself (don't rely on AnimationTrack.Length)
        for _, kf in ipairs(kfs:GetKeyframes()) do
            totalLength = math.max(totalLength, kf.Time)
        end

        local humanoid = rigModel:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            warn("[MultiAnimPlayer] Rig '" .. rigName .. "' has no Humanoid")
            continue
        end

        local animator = humanoid:FindFirstChildOfClass("Animator")
            or Instance.new("Animator")
        animator.Parent = humanoid

        local ok, animId = pcall(AnimationClipProvider.RegisterKeyframeSequence,
                                  AnimationClipProvider, kfs)
        if not ok then
            warn("[MultiAnimPlayer] RegisterKeyframeSequence failed for '"
                 .. rigName .. "': " .. tostring(animId))
            continue
        end

        local anim = Instance.new("Animation")
        anim.AnimationId = animId
        local track = animator:LoadAnimation(anim)
        track:Play(0)
        table.insert(tracks, track)
    end

    -- ── Scale data ────────────────────────────────────────────────────────────

    local scaleRigs = {}   -- { {model, keyframes, joints(unused)} }

    if scaleTracks and scaleTracks.rigs then
        for rigName, rigScaleData in pairs(scaleTracks.rigs) do
            local rigModel = rigMap[rigName]
            if not rigModel then continue end
            local keyframes = scaleToKeyframes(rigScaleData, fps)
            for _, kf in ipairs(keyframes) do
                totalLength = math.max(totalLength, kf.time)
            end
            scaleRigs[rigName] = { model = rigModel, keyframes = keyframes }

            -- Snap to first keyframe immediately
            if #keyframes > 0 then
                for pName, size in pairs(keyframes[1].parts) do
                    local part = rigModel:FindFirstChild(pName)
                    if part then part.Size = size end
                end
            end
        end
    end

    -- ── Root position data ────────────────────────────────────────────────────
    -- World-space HumanoidRootPart CFrames, interpolated in the Heartbeat loop.

    local rootRigs = {}   -- { [rigName] = { model, keyframes={time,cf} } }

    if rootTracks and rootTracks.rigs then
        for rigName, rigRootData in pairs(rootTracks.rigs) do
            local rigModel = rigMap[rigName]
            if not rigModel then continue end
            local kfs = {}
            for frame, arr in pairs(rigRootData) do
                local cf = CFrame.new(
                    arr[1], arr[2], arr[3],
                    arr[4], arr[5], arr[6],
                    arr[7], arr[8], arr[9],
                    arr[10], arr[11], arr[12]
                )
                table.insert(kfs, { time = (frame - 1) / fps, cf = cf })
            end
            table.sort(kfs, function(a, b) return a.time < b.time end)
            for _, kf in ipairs(kfs) do
                totalLength = math.max(totalLength, kf.time)
            end
            rootRigs[rigName] = { model = rigModel, keyframes = kfs }
            -- Snap to first keyframe immediately
            if #kfs > 0 then
                local hrp = rigModel:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CFrame = kfs[1].cf end
            end
        end
    end

    -- ── Prop data ─────────────────────────────────────────────────────────────

    _propState = {}
    if propTracks and propTracks.props and propMap then
        for propName, propKFData in pairs(propTracks.props) do
            local part = propMap[propName]
            if not part then continue end
            local kfs = propToKeyframes(propKFData, fps)
            for _, kf in ipairs(kfs) do
                totalLength = math.max(totalLength, kf.time)
            end
            _propState[propName] = { part = part, kfs = kfs }
            -- Snap to first keyframe immediately
            if #kfs > 0 then
                part.CFrame = kfs[1].cf
            end
        end
    end

    if totalLength <= 0 then
        warn("[MultiAnimPlayer] Scene '" .. sceneName .. "' has no keyframes")
        return
    end

    -- ── Heartbeat loop (scale + end-of-scene detection) ───────────────────────

    _sceneName = sceneName
    _tracks    = tracks
    local startTime = tick()
    local done      = false

    _heartbeat = RunService.Heartbeat:Connect(function()
        if done then return end
        local elapsed = tick() - startTime

        for _, data in pairs(scaleRigs) do
            local kfs = data.keyframes
            if #kfs == 0 then continue end
            local before, after = surroundingKFs(kfs, elapsed)
            local parts = lerpKFs(before, after, elapsed, function(a, b, t)
                return a:Lerp(b, t)
            end, "parts")
            for pName, size in pairs(parts) do
                local part = data.model:FindFirstChild(pName)
                if part then part.Size = size end
            end
        end

        -- Root position interpolation (whole-model world CFrame)
        for _, data in pairs(rootRigs) do
            local kfs = data.keyframes
            if #kfs == 0 then continue end
            local before, after = surroundingKFs(kfs, elapsed)
            local cf
            if before == after or after.time <= before.time then
                cf = before.cf
            else
                local alpha = math.clamp(
                    (elapsed - before.time) / (after.time - before.time), 0, 1)
                cf = before.cf:Lerp(after.cf, alpha)
            end
            local hrp = data.model:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = cf end
        end

        -- Prop CFrame interpolation
        for _, state in pairs(_propState) do
            local kfs = state.kfs
            if #kfs == 0 then continue end
            local before, after = surroundingKFs(kfs, elapsed)
            local cf
            if before == after or after.time <= before.time then
                cf = before.cf
            else
                local alpha = math.clamp(
                    (elapsed - before.time) / (after.time - before.time), 0, 1)
                cf = before.cf:Lerp(after.cf, alpha)
            end
            if state.part and state.part.Parent then
                state.part.CFrame = cf
            end
        end

        if elapsed >= totalLength then
            done = true
            local sn = _sceneName
            clearActive()
            fireFinished(sn)
        end
    end)
end

return MultiAnimPlayer
