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
    local t = (time - a.time) / (b.time - a.time)
    return lerpCFrame(a.data, b.data, t)
end

local function sampleJointPoses(kfs, time)
    local a, b = findKF(kfs, time)
    if not a then return {} end
    if not b then return a.poses end
    local t   = (time - a.time) / (b.time - a.time)
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
    local t   = (time - a.time) / (b.time - a.time)
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

    -- Build a flat map of workspace rigs we can actually find.
    local workspaceRigs = {}
    for rigName in pairs(sceneData.rigs) do
        -- Use the caller's rigMap entry if provided.
        local entry = rigMap[rigName]
        if entry == nil then
            if rigName == "RigPlayer" then
                -- Implicit convention: RigPlayer → current LocalPlayer clone.
                entry = { player = game:GetService("Players").LocalPlayer, mode = "clone" }
            else
                local fig = workspace:FindFirstChild("FIGURES")
                if fig then entry = fig:FindFirstChild(rigName) end
            end
        end
        if entry then workspaceRigs[rigName] = entry end
    end

    -- Collect all workspace instances tagged for this scene ("MAnim:<sceneName>").
    -- These are the original source rigs regardless of which folder they live in.
    local CS = game:GetService("CollectionService")
    local sceneTag = "MAnim:" .. sceneName
    local taggedSourceRigs = {}
    for _, inst in ipairs(CS:GetTagged(sceneTag)) do
        if inst:IsA("Model") then
            taggedSourceRigs[inst.Name] = inst
        end
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

            -- Camera track
            if #sceneData.camera > 0 then
                local a, b = findKF(sceneData.camera, t)
                if a then
                    if b and not (a.data.cut) then
                        local frac = (t - a.time) / (b.time - a.time)
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
            lastSfxTime = t

            -- Subtitle stepped sampling
            if SubtitleGui and #subtitleEvents > 0 then
                local frame = math.floor(t * fps) + 1
                local activeText = nil
                for _, ev in ipairs(subtitleEvents) do
                    if ev.frame <= frame then activeText = ev.text else break end
                end
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
