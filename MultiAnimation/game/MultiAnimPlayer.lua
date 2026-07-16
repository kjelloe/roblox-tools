-- MultiAnimPlayer — in-game playback of exported MultiAnimation scenes.
--
-- Drives animation by setting Motor6D.Transform directly in a Heartbeat loop.
-- No AnimationClipProvider dependency — works server-side and client-side.
--
-- API:
--   player.play(sceneName, rigMap, propMap?, opts?)
--       sceneName  string         — matches the scene name used at export time
--       rigMap     {[name]=Model} — keys match rig names from the plugin session
--       propMap    {[name]=BasePart}? — optional; keys match tracked prop names
--       opts       { resetOnEnd?, skipEffects?, smooth? } — smooth (default
--                  true) uses Catmull-Rom-style interpolation across
--                  keyframes; pass false for legacy linear. skipEffects suppresses
--                  effect-track and spawned-effect firing (used by
--                  CutsceneServer when clients fire them locally instead);
--                  playback duration still includes their tail times
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
local _resetFn    = nil   -- set when resetOnEnd=true; called on stop/finish

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
POSE_EASING_TO_STR[Enum.PoseEasingStyle.Elastic]   = { default = "Elastic" }
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

-- Find the pair of entries that straddle elapsed time (+ index of `before`).
local function surrounding(list, elapsed)
    local bi = 1
    for i = 1, #list do
        if list[i].time <= elapsed then bi = i else break end
    end
    local before = list[bi]
    local after  = list[math.min(bi + 1, #list)]
    return before, after, bi
end

local function lerpCF(a, b, t) return a:Lerp(b, t) end
local function lerpV3(a, b, t) return a:Lerp(b, t) end

-- ── Smooth interpolation (Catmull-Rom-style; same construction as
-- CutscenePlayer — keep the two copies in sync) ───────────────────────────────

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

local function smoothV3(p0, p1, p2, p3, t)
    local t2, t3 = t * t, t * t * t
    return ((p1 * 2) + (p2 - p0) * t
        + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
        + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

local function alpha(before, after, elapsed)
    return math.clamp((elapsed - before.time) / (after.time - before.time), 0, 1)
end

-- ── Prop visual state (transparency/colour lerp, material stepped) ────────────
-- Same construction as Interpolator/CutscenePlayer — keep the copies in sync.

local function lerpState(sa, sb, t)
    return {
        t = sa.t + (sb.t - sa.t) * t,
        c = { sa.c[1] + (sb.c[1] - sa.c[1]) * t,
              sa.c[2] + (sb.c[2] - sa.c[2]) * t,
              sa.c[3] + (sb.c[3] - sa.c[3]) * t },
        m = sa.m,
    }
end

local function applyPartState(part, st)
    if st.t then part.Transparency = st.t end
    if st.c then part.Color = Color3.new(st.c[1], st.c[2], st.c[3]) end
    if st.m then
        -- Material names can change across Roblox versions; ignore unknowns.
        local ok, mat = pcall(function() return Enum.Material[st.m] end)
        if ok and mat then part.Material = mat end
    end
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
    if easing == "Elastic" then
        if t <= 0 then return 0 end
        if t >= 1 then return 1 end
        return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
    end
    return t
end

local function clearActive()
    if _heartbeat then _heartbeat:Disconnect(); _heartbeat = nil end
    _sceneName = nil
    _resetFn   = nil
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
    if _resetFn then pcall(_resetFn) end
    clearActive()
    fireFinished(sn)
end

function MultiAnimPlayer.play(sceneName, rigMap, propMap, opts)
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
    local sfxModule   = sceneFolder:FindFirstChild("SpawnedEffects")
    local sfxData     = sfxModule   and require(sfxModule)   or nil
    local sfxRunner   = script.Parent:FindFirstChild("SpawnedEffectRunner")
    if sfxRunner then sfxRunner = require(sfxRunner) end
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
    if propTracks and propTracks.states and propMap then
        for propName, stKFData in pairs(propTracks.states) do
            local part = propMap[propName]
            if not part then continue end
            local kfs = toSortedKFs(stKFData, fps, function(raw) return raw end,
                propTracks.easings and propTracks.easings[propName])
            for _, kf in ipairs(kfs) do
                totalLength = math.max(totalLength, kf.time)
            end
            if not propStates[propName] then
                propStates[propName] = { part = part, kfs = {} }
            end
            propStates[propName].stateKFs = kfs
            if #kfs > 0 then applyPartState(part, kfs[1].data) end
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

    -- ── SpawnedEffect events ──────────────────────────────────────────────────

    local spawnedFxEvents = {}   -- sorted { {time, fx} }
    if sfxData and sfxRunner then
        for _, fx in ipairs(sfxData.effects or {}) do
            local t = (fx.frame - 1) / fps
            table.insert(spawnedFxEvents, { time = t, fx = fx })
            totalLength = math.max(totalLength, t)
        end
        table.sort(spawnedFxEvents, function(a, b) return a.time < b.time end)
    end

    local function fireSpawnedFx(ev)
        local fx = ev.fx
        sfxRunner.fire(Vector3.new(fx.posX, fx.posY, fx.posZ), fx.effectType, fx)
    end

    if totalLength <= 0 then
        warn("[MultiAnimPlayer] Scene '" .. sceneName .. "' has no keyframes")
        return
    end

    -- When resetOnEnd is requested, build a closure over rigStates/propStates.
    if opts and opts.resetOnEnd then
        _resetFn = function()
            for _, state in pairs(rigStates) do
                if #state.jointKFs > 0 then
                    for jName, motor in pairs(state.joints) do
                        local p = state.jointKFs[1].poses[jName]
                        if p then motor.Transform = p end
                    end
                end
                if #state.scaleKFs > 0 then
                    for pName, sz in pairs(state.scaleKFs[1].data) do
                        local part = state.model:FindFirstChild(pName)
                        if part then part.Size = sz end
                    end
                end
                if #state.rootKFs > 0 then
                    local hrp = state.model:FindFirstChild("HumanoidRootPart")
                    if hrp then hrp.CFrame = state.rootKFs[1].data end
                end
            end
            for _, state in pairs(propStates) do
                if #state.kfs > 0 and state.part and state.part.Parent then
                    state.part.CFrame = state.kfs[1].data
                end
                if state.stateKFs and #state.stateKFs > 0
                    and state.part and state.part.Parent then
                    applyPartState(state.part, state.stateKFs[1].data)
                end
            end
        end
    end

    -- ── Heartbeat loop ────────────────────────────────────────────────────────

    _sceneName = sceneName
    local startTime = tick()
    local done = false
    local nextEffectIdx = 1
    local nextSpawnedFxIdx = 1
    local skipEffects = opts and opts.skipEffects
    local smooth = not (opts and opts.smooth == false)   -- default ON

    _heartbeat = RunService.Heartbeat:Connect(function()
        if done then return end
        local elapsed = tick() - startTime

        -- Fire effect events whose time we have crossed.
        while nextEffectIdx <= #effectEvents
              and effectEvents[nextEffectIdx].time <= elapsed do
            if not skipEffects then fireEffect(effectEvents[nextEffectIdx]) end
            nextEffectIdx += 1
        end

        -- Fire spawned effect events whose time we have crossed.
        while nextSpawnedFxIdx <= #spawnedFxEvents
              and spawnedFxEvents[nextSpawnedFxIdx].time <= elapsed do
            if not skipEffects then fireSpawnedFx(spawnedFxEvents[nextSpawnedFxIdx]) end
            nextSpawnedFxIdx += 1
        end

        for _, state in pairs(rigStates) do
            -- Joint poses via Motor6D.Transform
            if #state.jointKFs > 1 then
                local b, a, bi = surrounding(state.jointKFs, elapsed)
                if b ~= a and a.time > b.time then
                    local t = easedAlpha(alpha(b, a, elapsed), b.easing)
                    local kq0 = state.jointKFs[bi - 1] or b
                    local kq3 = state.jointKFs[bi + 2] or a
                    for jName, motor in pairs(state.joints) do
                        local cfB = b.poses[jName]
                        if cfB then
                            local cfA = a.poses[jName] or cfB
                            if smooth then
                                motor.Transform = smoothCF(kq0.poses[jName] or cfB, cfB, cfA,
                                    kq3.poses[jName] or cfA, t)
                            else
                                motor.Transform = lerpCF(cfB, cfA, t)
                            end
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
                local b, a, bi = surrounding(state.scaleKFs, elapsed)
                if b ~= a and a.time > b.time then
                    local t = easedAlpha(alpha(b, a, elapsed), b.easing)
                    local kq0 = state.scaleKFs[bi - 1] or b
                    local kq3 = state.scaleKFs[bi + 2] or a
                    for pName, sizeB in pairs(b.data) do
                        local part = state.model:FindFirstChild(pName)
                        if part then
                            local sizeA = a.data[pName] or sizeB
                            if smooth then
                                part.Size = smoothV3(kq0.data[pName] or sizeB, sizeB, sizeA,
                                    kq3.data[pName] or sizeA, t)
                            else
                                part.Size = lerpV3(sizeB, sizeA, t)
                            end
                        end
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
                local b, a, bi = surrounding(state.rootKFs, elapsed)
                local cf
                if b ~= a and a.time > b.time then
                    local t = easedAlpha(alpha(b, a, elapsed), b.easing)
                    if smooth then
                        local kq0 = state.rootKFs[bi - 1] or b
                        local kq3 = state.rootKFs[bi + 2] or a
                        cf = smoothCF(kq0.data, b.data, a.data, kq3.data, t)
                    else
                        cf = lerpCF(b.data, a.data, t)
                    end
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
                local b, a, bi = surrounding(state.kfs, elapsed)
                if state.part and state.part.Parent then
                    if b ~= a and a.time > b.time then
                        local t = easedAlpha(alpha(b, a, elapsed), b.easing)
                        if smooth then
                            local kq0 = state.kfs[bi - 1] or b
                            local kq3 = state.kfs[bi + 2] or a
                            state.part.CFrame = smoothCF(kq0.data, b.data, a.data, kq3.data, t)
                        else
                            state.part.CFrame = lerpCF(b.data, a.data, t)
                        end
                    else
                        state.part.CFrame = b.data
                    end
                end
            end
            if state.stateKFs and #state.stateKFs > 0
                and state.part and state.part.Parent then
                local b, a = surrounding(state.stateKFs, elapsed)
                if b ~= a and a.time > b.time then
                    local t = easedAlpha(alpha(b, a, elapsed), b.easing)
                    applyPartState(state.part, lerpState(b.data, a.data, t))
                else
                    applyPartState(state.part, b.data)
                end
            end
        end

        if elapsed >= totalLength then
            done = true
            local sn = _sceneName
            if _resetFn then pcall(_resetFn) end
            if sfxRunner then pcall(sfxRunner.clearFades) end
            clearActive()
            fireFinished(sn)
        end
    end)
end

return MultiAnimPlayer
