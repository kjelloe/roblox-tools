-- MultiAnimPlayer — in-game playback of exported MultiAnimation scenes.
--
-- Drives animation by setting Motor6D.Transform directly in a Heartbeat loop.
-- No AnimationClipProvider dependency — works server-side and client-side.
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

local RunService = game:GetService("RunService")

local MultiAnimPlayer = {}

-- ── module-level state ────────────────────────────────────────────────────────

local _finishedCb = nil
local _heartbeat  = nil
local _sceneName  = nil

-- ── helpers ───────────────────────────────────────────────────────────────────

-- Discover all rig-owned Motor6Ds and return { [motorName] = motor }.
-- Works for R6, R15, and custom rigs.
-- Reconnects motors that the plugin left disconnected (Part0 = nil).
local function findJoints(rig)
    local joints = {}
    for _, inst in ipairs(rig:GetDescendants()) do
        if inst:IsA("Motor6D") then
            local container = inst.Parent   -- always the original Part0 container
            local p1        = inst.Part1
            if container and container.Parent == rig
               and p1 and p1.Parent == rig then
                if inst.Part0 == nil then inst.Part0 = container end
                joints[inst.Name] = inst
            end
        end
    end
    return joints
end

-- Legacy R6 KFS pose-name → motor name mapping (for backward-compat parsing).
local LEGACY_POSE_TO_JOINT = {
    Torso         = "RootJoint",
    Head          = "Neck",
    ["Right Arm"] = "Right Shoulder",
    ["Left Arm"]  = "Left Shoulder",
    ["Right Leg"] = "Right Hip",
    ["Left Leg"]  = "Left Hip",
}

local POSE_EASING_TO_STR = {}
POSE_EASING_TO_STR[Enum.PoseEasingStyle.Linear]   = { default = "Linear" }
POSE_EASING_TO_STR[Enum.PoseEasingStyle.Constant]  = { default = "Constant" }
POSE_EASING_TO_STR[Enum.PoseEasingStyle.Bounce]    = { default = "Bounce" }
POSE_EASING_TO_STR[Enum.PoseEasingStyle.Cubic]     = {
    [Enum.PoseEasingDirection.In]    = "EaseIn",
    [Enum.PoseEasingDirection.Out]   = "EaseOut",
    [Enum.PoseEasingDirection.InOut] = "EaseInOut",
    default = "EaseOut",
}

local function poseEasingToStr(style, dir)
    local m = POSE_EASING_TO_STR[style]
    if not m then return "Linear" end
    return m[dir] or m.default or "Linear"
end

-- Parse a KeyframeSequence into sorted { {time, easing, poses={[motorName]=CFrame}} }.
-- Handles two formats:
--   Legacy R6: HumanoidRootPart → Torso → (Head, Right Arm, ...)
--   Flat (new): HumanoidRootPart → [motorName, ...]
local function parseKFS(kfs)
    local out = {}
    for _, kf in ipairs(kfs:GetKeyframes()) do
        local hrpPose = kf:FindFirstChild("HumanoidRootPart")
        if not hrpPose then continue end
        local poses  = {}
        local easing = "Linear"
        local torsoPose = hrpPose:FindFirstChild("Torso")
        if torsoPose then
            -- Legacy R6 hierarchy format
            poses["RootJoint"] = torsoPose.CFrame
            easing = poseEasingToStr(torsoPose.EasingStyle, torsoPose.EasingDirection)
            for _, child in ipairs(torsoPose:GetChildren()) do
                local jName = LEGACY_POSE_TO_JOINT[child.Name]
                if jName then poses[jName] = child.CFrame end
            end
        else
            -- Flat format: each child is a motor name directly
            for _, child in ipairs(hrpPose:GetChildren()) do
                poses[child.Name] = child.CFrame
            end
            local first = hrpPose:GetChildren()[1]
            if first then
                easing = poseEasingToStr(first.EasingStyle, first.EasingDirection)
            end
        end
        table.insert(out, { time = kf.Time, poses = poses, easing = easing })
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

-- Convert a {[frame]=data} table to sorted { {time, easing, data} } using fps.
-- easingsTable is an optional parallel {[frame]=easingString} table.
local function toSortedKFs(frameTable, fps, buildFn, easingsTable)
    local out = {}
    for frame, raw in pairs(frameTable) do
        local easing = (easingsTable and easingsTable[frame]) or "Linear"
        table.insert(out, { time = (frame - 1) / fps, data = buildFn(raw), easing = easing })
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

-- Find the pair of entries that straddle elapsed time.
local function surrounding(list, elapsed)
    local before = list[1]
    local after  = list[#list]
    for i = 1, #list do
        if list[i].time <= elapsed then before = list[i] end
        if list[i].time >= elapsed then after = list[i]; break end
    end
    return before, after
end

local function lerpCF(a, b, t) return a:Lerp(b, t) end
local function lerpV3(a, b, t) return a:Lerp(b, t) end

local function alpha(before, after, elapsed)
    return math.clamp((elapsed - before.time) / (after.time - before.time), 0, 1)
end

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

local function clearActive()
    if _heartbeat then _heartbeat:Disconnect(); _heartbeat = nil end
    _sceneName = nil
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
    local fxModule    = sceneFolder:FindFirstChild("EffectTracks")
    local fxTracks    = fxModule    and require(fxModule)    or nil
    local fps = (scaleTracks and scaleTracks.fps)
             or (propTracks  and propTracks.fps)
             or (rootTracks  and rootTracks.fps)
             or (fxTracks    and fxTracks.fps)
             or 24

    -- ── Per-rig data ──────────────────────────────────────────────────────────

    local rigStates  = {}
    local totalLength = 0

    for rigName, rigModel in pairs(rigMap) do
        local state = {
            model     = rigModel,
            joints    = findJoints(rigModel),
            jointKFs  = {},
            scaleKFs  = {},
            rootKFs   = {},
        }

        local kfs = sceneFolder:FindFirstChild(rigName .. "_Joints")
        if kfs then
            state.jointKFs = parseKFS(kfs)
            for _, kf in ipairs(state.jointKFs) do
                totalLength = math.max(totalLength, kf.time)
            end
        else
            warn("[MultiAnimPlayer] No KeyframeSequence for '" .. rigName .. "'")
        end

        if scaleTracks and scaleTracks.rigs and scaleTracks.rigs[rigName] then
            state.scaleKFs = toSortedKFs(scaleTracks.rigs[rigName], fps, function(raw)
                local parts = {}
                for pName, arr in pairs(raw) do
                    parts[pName] = Vector3.new(arr[1], arr[2], arr[3])
                end
                return parts
            end, scaleTracks.easings and scaleTracks.easings[rigName])
            for _, kf in ipairs(state.scaleKFs) do
                totalLength = math.max(totalLength, kf.time)
            end
        end

        if rootTracks and rootTracks.rigs and rootTracks.rigs[rigName] then
            state.rootKFs = toSortedKFs(rootTracks.rigs[rigName], fps, function(arr)
                return CFrame.new(arr[1],arr[2],arr[3],
                                  arr[4],arr[5],arr[6],
                                  arr[7],arr[8],arr[9],
                                  arr[10],arr[11],arr[12])
            end, rootTracks.easings and rootTracks.easings[rigName])
            for _, kf in ipairs(state.rootKFs) do
                totalLength = math.max(totalLength, kf.time)
            end
        end

        -- Snap all tracks to frame 1
        if #state.jointKFs > 0 then
            for jName, motor in pairs(state.joints) do
                local p = state.jointKFs[1].poses[jName]
                if p then motor.Transform = p end
            end
        end
        if #state.scaleKFs > 0 then
            for pName, size in pairs(state.scaleKFs[1].data) do
                local part = rigModel:FindFirstChild(pName)
                if part then part.Size = size end
            end
        end
        if #state.rootKFs > 0 then
            local hrp = rigModel:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = state.rootKFs[1].data end
        end

        rigStates[rigName] = state
    end

    -- ── Prop data ─────────────────────────────────────────────────────────────

    local propStates = {}
    if propTracks and propTracks.props and propMap then
        for propName, propKFData in pairs(propTracks.props) do
            local part = propMap[propName]
            if not part then continue end
            local kfs = toSortedKFs(propKFData, fps, function(arr)
                return CFrame.new(arr[1],arr[2],arr[3],
                                  arr[4],arr[5],arr[6],
                                  arr[7],arr[8],arr[9],
                                  arr[10],arr[11],arr[12])
            end, propTracks.easings and propTracks.easings[propName])
            for _, kf in ipairs(kfs) do
                totalLength = math.max(totalLength, kf.time)
            end
            propStates[propName] = { part = part, kfs = kfs }
            if #kfs > 0 then part.CFrame = kfs[1].data end
        end
    end

    -- ── Effect events (one-shots, fired when playback crosses their time) ────

    local effectEvents = {}   -- sorted { {time, inst, action, count} }
    if fxTracks and fxTracks.effects then
        for fxName, fx in pairs(fxTracks.effects) do
            -- Resolve the live instance from its exported full path.
            local inst = game
            for seg in string.gmatch(fx.target or "", "[^.]+") do
                if inst == game and seg == "game" then continue end
                inst = inst and inst:FindFirstChild(seg)
            end
            if inst and inst ~= game then
                for frame, ev in pairs(fx.events or {}) do
                    table.insert(effectEvents, {
                        time   = (frame - 1) / fps,
                        inst   = inst,
                        action = ev.action,
                        count  = ev.count,
                    })
                    totalLength = math.max(totalLength, (frame - 1) / fps)
                end
            else
                warn("[MultiAnimPlayer] Effect target not found: " .. tostring(fx.target)
                    .. " ('" .. fxName .. "')")
            end
        end
        table.sort(effectEvents, function(a, b) return a.time < b.time end)
    end

    local function fireEffect(ev)
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

    if totalLength <= 0 then
        warn("[MultiAnimPlayer] Scene '" .. sceneName .. "' has no keyframes")
        return
    end

    -- ── Heartbeat loop ────────────────────────────────────────────────────────

    _sceneName = sceneName
    local startTime = tick()
    local done = false
    local nextEffectIdx = 1

    _heartbeat = RunService.Heartbeat:Connect(function()
        if done then return end
        local elapsed = tick() - startTime

        -- Fire effect events whose time we have crossed.
        while nextEffectIdx <= #effectEvents
              and effectEvents[nextEffectIdx].time <= elapsed do
            fireEffect(effectEvents[nextEffectIdx])
            nextEffectIdx += 1
        end

        for _, state in pairs(rigStates) do
            -- Joint poses via Motor6D.Transform
            if #state.jointKFs > 1 then
                local b, a = surrounding(state.jointKFs, elapsed)
                if b ~= a and a.time > b.time then
                    local t = easedAlpha(alpha(b, a, elapsed), b.easing)
                    for jName, motor in pairs(state.joints) do
                        local cfB = b.poses[jName]
                        if cfB then
                            motor.Transform = lerpCF(cfB, a.poses[jName] or cfB, t)
                        end
                    end
                else
                    for jName, motor in pairs(state.joints) do
                        local p = b.poses[jName]
                        if p then motor.Transform = p end
                    end
                end
            elseif #state.jointKFs == 1 then
                for jName, motor in pairs(state.joints) do
                    local p = state.jointKFs[1].poses[jName]
                    if p then motor.Transform = p end
                end
            end

            -- Scale
            if #state.scaleKFs > 0 then
                local b, a = surrounding(state.scaleKFs, elapsed)
                if b ~= a and a.time > b.time then
                    local t = easedAlpha(alpha(b, a, elapsed), b.easing)
                    for pName, sizeB in pairs(b.data) do
                        local part = state.model:FindFirstChild(pName)
                        if part then part.Size = lerpV3(sizeB, a.data[pName] or sizeB, t) end
                    end
                else
                    for pName, sizeB in pairs(b.data) do
                        local part = state.model:FindFirstChild(pName)
                        if part then part.Size = sizeB end
                    end
                end
            end

            -- Root position
            if #state.rootKFs > 0 then
                local b, a = surrounding(state.rootKFs, elapsed)
                local cf
                if b ~= a and a.time > b.time then
                    cf = lerpCF(b.data, a.data, easedAlpha(alpha(b, a, elapsed), b.easing))
                else
                    cf = b.data
                end
                local hrp = state.model:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CFrame = cf end
            end
        end

        -- Props
        for _, state in pairs(propStates) do
            if #state.kfs > 0 then
                local b, a = surrounding(state.kfs, elapsed)
                if state.part and state.part.Parent then
                    if b ~= a and a.time > b.time then
                        state.part.CFrame = lerpCF(b.data, a.data, easedAlpha(alpha(b, a, elapsed), b.easing))
                    else
                        state.part.CFrame = b.data
                    end
                end
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
