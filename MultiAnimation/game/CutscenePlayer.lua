-- CutscenePlayer — client-side LocalScript module that plays a MultiAnimation
-- scene with optional player-rig substitution.
--
-- Requires:
--   PlayerRigProxy  (sibling in ReplicatedStorage or same require path)
--   LetterboxGui    (sibling)
--   RemoteFunction "MultiAnimGetScene" must be available in ReplicatedStorage
--     (set up by MultiAnimDataServer.setup() on the server).
--
-- Usage:
--   local CutscenePlayer = require(ReplicatedStorage.CutscenePlayer)
--   local handle = CutscenePlayer.play("MyScene", {
--       Rig1 = workspace.FIGURES.Rig1,                             -- fixed rig
--       Rig2 = { player = game.Players.LocalPlayer, mode = "clone" },
--   }, { fps = 30, loop = false, movieMode = true })
--   -- handle.stop()              cancels early
--   -- handle.onComplete(function() ... end)  fires after full teardown
--
-- rigMap values:
--   Instance                              → fixed workspace rig (pass-through)
--   { player = Player,  mode = "clone" }  → clone player's character locally
--   { player = Player,  mode = "direct" } → animate the player's real character
--   { userId = number,  mode = ... }      → look up player by UserId first
--
-- Implicit convention:
--   A rig named "RigPlayer" with no explicit rigMap entry is automatically
--   mapped to { player = LocalPlayer, mode = "clone" }.
--   This lets you call CutscenePlayer.play("MyScene") with no rigMap at all
--   when the only player-dependent rig is named "RigPlayer".

local CutscenePlayer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ──────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ──────────────────────────────────────────────────────────────────────────────

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpCFrame(a, b, t)
    return a:Lerp(b, t)
end

local function lerpV3(a, b, t)
    return a:Lerp(b, t)
end

-- Same curve set as MultiAnimPlayer / CutsceneCamera; keyframe easing governs
-- the segment from that keyframe toward the next one.
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

-- Binary-search for the last keyframe at or before `time`.
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
    return lerpCFrame(a.data, b.data, t)
end

local function sampleJointPoses(kfs, time)
    local a, b = findKF(kfs, time)
    if not a then return {} end
    if not b then return a.poses end
    local t   = easedAlpha((time - a.time) / (b.time - a.time), a.easing)
    local out = {}
    for jointName, cfA in pairs(a.poses) do
        local cfB = b.poses[jointName]
        out[jointName] = cfB and lerpCFrame(cfA, cfB, t) or cfA
    end
    return out
end

local function sampleScaleParts(kfs, time)
    local a, b = findKF(kfs, time)
    if not a then return {} end
    if not b then return a.data end
    local t   = easedAlpha((time - a.time) / (b.time - a.time), a.easing)
    local out = {}
    for pName, v3A in pairs(a.data) do
        local v3B = b.data[pName]
        out[pName] = v3B and lerpV3(v3A, v3B, t) or v3A
    end
    return out
end

-- Build { [motorName] = motor } for all rig-owned Motor6Ds.
-- Works for R6, R15, and custom rigs.
-- Reconnects motors that the plugin left disconnected (Part0 = nil).
local function buildJointMap(rig)
    local map = {}
    for _, inst in ipairs(rig:GetDescendants()) do
        if inst:IsA("Motor6D") then
            local container = inst.Parent   -- always the original Part0 container
            local p1        = inst.Part1
            if container and container.Parent == rig
               and p1 and p1.Parent == rig then
                if inst.Part0 == nil then inst.Part0 = container end
                map[inst.Name] = inst
            end
        end
    end
    return map
end

local function applyJoints(jointMap, poses)
    for motorName, motor in pairs(jointMap) do
        local cf = poses[motorName]
        if cf then motor.Transform = cf end
    end
end

-- Apply part sizes from a scale KF to a rig.
local function applyScale(rig, parts)
    for pName, sz in pairs(parts) do
        local part = rig:FindFirstChild(pName)
        if part and part:IsA("BasePart") then
            part.Size = sz
        end
    end
end

-- Derive anchor CFrames from the first rootKF of each rig (where the rig
-- starts in world space at t=0). Falls back to the rig's current HRP CFrame.
local function buildAnchorCFs(sceneData, resolvedRigs)
    local anchors = {}
    for rigName, rigData in pairs(sceneData.rigs) do
        if rigData.rootKFs and #rigData.rootKFs > 0 then
            anchors[rigName] = rigData.rootKFs[1].data
        elseif resolvedRigs[rigName] then
            local hrp = resolvedRigs[rigName]:FindFirstChild("HumanoidRootPart")
            anchors[rigName] = hrp and hrp.CFrame or CFrame.identity
        end
    end
    return anchors
end

-- ──────────────────────────────────────────────────────────────────────────────
-- play()
-- ──────────────────────────────────────────────────────────────────────────────

function CutscenePlayer.play(sceneName, rigMap, options)
    options  = options  or {}
    rigMap   = rigMap   or {}
    local fps        = math.max(1, math.floor(options.fps  or 30))
    local loop       = options.loop        or false
    local movieMode  = options.movieMode   or false
    local resetOnEnd = options.resetOnEnd  or false

    -- Grab modules; they live next to CutscenePlayer in ReplicatedStorage.
    local selfModule  = script  -- the ModuleScript itself (for sibling access)
    local PlayerRigProxy = require(selfModule.Parent:FindFirstChild("PlayerRigProxy")
                                or selfModule.Parent.Parent:FindFirstChild("PlayerRigProxy"))
    local LetterboxGui   = require(selfModule.Parent:FindFirstChild("LetterboxGui")
                                or selfModule.Parent.Parent:FindFirstChild("LetterboxGui"))
    local SpawnedEffectRunner = require(selfModule.Parent:FindFirstChild("SpawnedEffectRunner")
                                    or selfModule.Parent.Parent:FindFirstChild("SpawnedEffectRunner"))
    local subtitleGuiMod = selfModule.Parent:FindFirstChild("SubtitleGui")
                        or selfModule.Parent.Parent:FindFirstChild("SubtitleGui")
    local SubtitleGui = subtitleGuiMod and require(subtitleGuiMod) or nil

    -- Fetch scene data from the server.
    local remote = ReplicatedStorage:WaitForChild("MultiAnimGetScene", 10)
    if not remote then
        warn("[CutscenePlayer] RemoteFunction 'MultiAnimGetScene' not found. "
          .. "Did you call MultiAnimDataServer.setup() on the server?")
        return { stop = function() end }
    end
    local sceneData = remote:InvokeServer(sceneName)
    if not sceneData then
        warn("[CutscenePlayer] Scene '" .. sceneName .. "' returned no data.")
        return { stop = function() end }
    end

    -- Override fps from sceneData if caller didn't specify.
    if not options.fps then fps = sceneData.fps or fps end

    -- Collect all workspace instances tagged for this scene ("MAnim:<sceneName>").
    -- Done first so they can serve as the auto-fallback for unmapped rigs.
    local CS = game:GetService("CollectionService")
    local sceneTag = "MAnim:" .. sceneName
    local taggedSourceRigs = {}
    for _, inst in ipairs(CS:GetTagged(sceneTag)) do
        if inst:IsA("Model") then
            taggedSourceRigs[inst.Name] = inst
        end
    end

    -- Build a flat map of workspace rigs we can actually find.
    -- Fallback priority (when no explicit rigMap entry):
    --   1. "RigPlayer" → LocalPlayer clone (implicit convention)
    --   2. Tagged scene instance by name (works for any folder)
    --   3. workspace.FIGURES child by name (legacy fallback)
    local workspaceRigs = {}
    local Players = game:GetService("Players")
    for rigName in pairs(sceneData.rigs) do
        local entry = rigMap[rigName]
        if entry == nil then
            if rigName == "RigPlayer" then
                entry = { player = Players.LocalPlayer, mode = "clone" }
            else
                entry = taggedSourceRigs[rigName]
                if not entry then
                    local fig = workspace:FindFirstChild("FIGURES")
                    if fig then entry = fig:FindFirstChild(rigName) end
                end
            end
        end
        if entry then workspaceRigs[rigName] = entry end
    end

    -- Resolve player entries → actual rig models (may clone/hide player character).
    -- We need anchors first; do a pre-pass with whatever rootKFs give us.
    local preAnchors = {}
    for rigName, rigData in pairs(sceneData.rigs) do
        if rigData.rootKFs and #rigData.rootKFs > 0 then
            preAnchors[rigName] = rigData.rootKFs[1].data
        end
    end
    local resolvedRigs, teardownRigs = PlayerRigProxy.resolveAll(workspaceRigs, preAnchors)

    -- Hide any tagged source rigs whose slot is being played by a clone/player rig.
    -- Fixed rigs (resolvedRigs[n] IS the tagged rig itself) stay visible.
    local hiddenSourceParts = {}
    for rigName, src in pairs(taggedSourceRigs) do
        if resolvedRigs[rigName] ~= src then
            for _, part in ipairs(src:GetDescendants()) do
                if part:IsA("BasePart") then
                    hiddenSourceParts[part] = part.Transparency
                    part.Transparency = 1
                end
            end
        end
    end
    local function restoreSourceRigs()
        for part, t in pairs(hiddenSourceParts) do
            if part and part.Parent then part.Transparency = t end
        end
        hiddenSourceParts = {}
    end
    local _origTeardown = teardownRigs
    teardownRigs = function()
        restoreSourceRigs()
        _origTeardown()
    end

    -- Recompute anchors now that we have the actual resolved models.
    local anchorCFs = buildAnchorCFs(sceneData, resolvedRigs)

    -- Resolve prop instances from the scene's prop tracks.
    -- Prefers CollectionService-tagged BaseParts, falls back to workspace search by name.
    local propInstances = {}
    for propName in pairs(sceneData.props or {}) do
        local found
        for _, inst in ipairs(CS:GetTagged(sceneTag)) do
            if inst.Name == propName and inst:IsA("BasePart") then
                found = inst; break
            end
        end
        if not found then
            local candidate = workspace:FindFirstChild(propName, true)
            if candidate and candidate:IsA("BasePart") then found = candidate end
        end
        if found then propInstances[propName] = found end
    end

    -- Spawned effects: convert frame → time, sort
    local spawnedFxEvents = {}
    for _, sfx in ipairs(sceneData.spawnedEffects or {}) do
        local t = (sfx.frame - 1) / fps
        table.insert(spawnedFxEvents, { time = t, sfx = sfx })
    end
    table.sort(spawnedFxEvents, function(a, b) return a.time < b.time end)

    -- Effect track events (one-shots on existing instances): resolve each
    -- target from its exported full path, flatten to a sorted event list.
    local effectEvents = {}
    for fxName, fx in pairs(sceneData.effects or {}) do
        local inst = game
        for seg in string.gmatch(fx.target or "", "[^.]+") do
            if inst == game and seg == "game" then continue end
            inst = inst and inst:FindFirstChild(seg)
        end
        if inst and inst ~= game then
            for _, ev in ipairs(fx.kfs or {}) do
                table.insert(effectEvents, {
                    time   = ev.time,
                    inst   = inst,
                    action = ev.data.action,
                    count  = ev.data.count,
                })
            end
        else
            warn("[CutscenePlayer] Effect target not found: " .. tostring(fx.target)
                .. " ('" .. fxName .. "')")
        end
    end
    table.sort(effectEvents, function(a, b) return a.time < b.time end)

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

    -- Subtitle track: sorted events + style (nil when scene has no SubtitleTrack)
    local subtitleEvents = sceneData.subtitles or {}
    local subtitleStyle  = sceneData.subtitleStyle or {}
    local _lastSubText   = nil  -- tracks currently displayed subtitle to avoid redundant show() calls

    -- Letterbox
    if movieMode then LetterboxGui.show() end

    -- Pre-build joint maps (rig:GetDescendants once, not per frame)
    local jointMaps = {}
    for rigName, rig in pairs(resolvedRigs) do
        jointMaps[rigName] = buildJointMap(rig)
    end

    -- Duration
    local function lastKFTime(kfs)
        return kfs and #kfs > 0 and kfs[#kfs].time or 0
    end
    local duration = 0
    for _, rigData in pairs(sceneData.rigs) do
        duration = math.max(duration,
            lastKFTime(rigData.jointKFs),
            lastKFTime(rigData.scaleKFs),
            lastKFTime(rigData.rootKFs))
    end
    for _, kfs in pairs(sceneData.props or {}) do
        duration = math.max(duration, lastKFTime(kfs))
    end
    if #sceneData.camera > 0 then
        duration = math.max(duration, sceneData.camera[#sceneData.camera].time)
    end
    if #spawnedFxEvents > 0 then
        duration = math.max(duration, spawnedFxEvents[#spawnedFxEvents].time)
    end
    if #effectEvents > 0 then
        duration = math.max(duration, effectEvents[#effectEvents].time)
    end
    for _, ev in ipairs(subtitleEvents) do
        duration = math.max(duration, (ev.frame - 1) / fps)
    end
    if duration == 0 then duration = 1 end

    -- Snap all resolved rigs and props back to their frame-1 pose.
    local function applyAtT0()
        for rigName, rig in pairs(resolvedRigs) do
            local rd = sceneData.rigs[rigName]
            if not rd then continue end
            if rd.rootKFs and #rd.rootKFs > 0 then
                local hrp = rig:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CFrame = rd.rootKFs[1].data end
            end
            if rd.jointKFs and #rd.jointKFs > 0 then
                applyJoints(jointMaps[rigName] or {}, rd.jointKFs[1].poses)
            end
            if rd.scaleKFs and #rd.scaleKFs > 0 then
                applyScale(rig, rd.scaleKFs[1].data)
            end
        end
        for propName, part in pairs(propInstances) do
            local kfs = sceneData.props[propName]
            if kfs and #kfs > 0 then
                part.CFrame = kfs[1].data
            end
        end
    end

    local camera  = workspace.CurrentCamera
    local stopped = false
    local elapsed     = 0
    local lastSfxTime = -1

    -- handle is declared here so doTeardown can close over _onComplete.
    local handle = {}
    local _onComplete = nil

    -- handle.onComplete(fn) — register a callback to fire after full teardown.
    function handle.onComplete(fn)
        _onComplete = fn
    end

    -- Shared teardown: runs once on natural completion OR handle.stop() OR Heartbeat error.
    local function doTeardown()
        if resetOnEnd then pcall(applyAtT0) end
        teardownRigs()
        if movieMode then LetterboxGui.hide() end
        if SubtitleGui then pcall(SubtitleGui.hide) end
        -- A scene that ends faded-out must not leave the view black.
        pcall(SpawnedEffectRunner.clearFades)
        -- Snap camera back to the live player character before restoring CameraType so
        -- Roblox's CameraModule resumes from the character position, not the cinematic
        -- endpoint (which would look like the camera is stuck far from the player).
        local Players = game:GetService("Players")
        local lp      = Players.LocalPlayer
        local char    = lp and lp.Character
        local hrp     = char and char:FindFirstChild("HumanoidRootPart")
        if camera and hrp then
            camera.CFrame = hrp.CFrame * CFrame.new(0, 2, 12)
        end
        if camera then
            camera.CameraType = Enum.CameraType.Custom
        end
        -- Fire onComplete callback last, after full state restore.
        if _onComplete then
            local cb = _onComplete
            _onComplete = nil
            pcall(cb)
        end
    end

    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        if stopped then conn:Disconnect(); return end

        local ok, err = pcall(function()
            elapsed = elapsed + dt
            local t = elapsed

            if t > duration then
                if loop then
                    elapsed     = elapsed - duration
                    t           = elapsed
                    lastSfxTime = -1
                else
                    t = duration
                    stopped = true
                end
            end

            -- Per-rig animation
            for rigName, rig in pairs(resolvedRigs) do
                local rd = sceneData.rigs[rigName]
                if not rd then continue end

                if rd.rootKFs and #rd.rootKFs > 0 then
                    local cf  = sampleCFrame(rd.rootKFs, t)
                    local hrp = rig:FindFirstChild("HumanoidRootPart")
                    if hrp then hrp.CFrame = cf end
                end

                if rd.jointKFs and #rd.jointKFs > 0 then
                    local poses = sampleJointPoses(rd.jointKFs, t)
                    if poses then applyJoints(jointMaps[rigName] or {}, poses) end
                end

                if rd.scaleKFs and #rd.scaleKFs > 0 then
                    local parts = sampleScaleParts(rd.scaleKFs, t)
                    if parts then applyScale(rig, parts) end
                end
            end

            -- Prop animation
            for propName, part in pairs(propInstances) do
                local kfs = sceneData.props[propName]
                if kfs and #kfs > 0 and part and part.Parent then
                    part.CFrame = sampleCFrame(kfs, t)
                end
            end

            -- Camera track. A keyframe with cut = true is jumped to, not
            -- interpolated toward — the previous shot holds until the cut lands
            -- (same semantics as the editor preview and CutsceneCamera).
            if #sceneData.camera > 0 then
                local a, b = findKF(sceneData.camera, t)
                if a then
                    if b and not b.data.cut then
                        local frac = easedAlpha((t - a.time) / (b.time - a.time), a.data.easing)
                        camera.CFrame      = lerpCFrame(a.data.cf, b.data.cf, frac)
                        camera.FieldOfView = lerp(a.data.fov or 70, b.data.fov or 70, frac)
                    else
                        camera.CFrame      = a.data.cf
                        camera.FieldOfView = a.data.fov or 70
                    end
                    camera.CameraType = Enum.CameraType.Scriptable
                end
            end

            -- Spawned effects crossing-pointer
            for _, ev in ipairs(spawnedFxEvents) do
                if ev.time > lastSfxTime and ev.time <= t then
                    SpawnedEffectRunner.fire(
                        Vector3.new(ev.sfx.posX, ev.sfx.posY, ev.sfx.posZ),
                        ev.sfx.effectType,
                        ev.sfx
                    )
                end
            end
            -- Effect track events (same crossing window)
            for _, ev in ipairs(effectEvents) do
                if ev.time > lastSfxTime and ev.time <= t then
                    fireEffect(ev)
                end
            end
            lastSfxTime = t

            -- Subtitle stepped sampling
            if SubtitleGui and #subtitleEvents > 0 then
                local frame = math.floor(t * fps) + 1
                local activeText = nil
                for _, ev in ipairs(subtitleEvents) do
                    if ev.frame <= frame then activeText = ev.text else break end
                end
                -- Empty-text events are "clear" markers, not empty bars.
                if activeText == "" then activeText = nil end
                if activeText ~= _lastSubText then
                    _lastSubText = activeText
                    if activeText then
                        pcall(SubtitleGui.show, activeText, subtitleStyle)
                    else
                        pcall(SubtitleGui.hide)
                    end
                end
            end

            if stopped then
                conn:Disconnect()
                doTeardown()
            end
        end)

        if not ok then
            warn("[CutscenePlayer] Error during playback (cleaning up): " .. tostring(err))
            stopped = true
            conn:Disconnect()
            pcall(doTeardown)
        end
    end)

    function handle.stop()
        if not stopped then
            stopped = true
            conn:Disconnect()
            pcall(doTeardown)
        end
    end
    return handle
end

return CutscenePlayer
