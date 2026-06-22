-- Exporter — builds KeyframeSequence instances and a ScaleTracks ModuleScript
-- from the recorded session, then writes them to ServerStorage.
--
-- Output layout:
--   ServerStorage.MultiAnimationData.<sceneName>
--     ├── <RigName>_Joints   (KeyframeSequence)
--     └── ScaleTracks        (ModuleScript)
--
-- If the scene folder already exists it is silently overwritten.

local ServerStorage = game:GetService("ServerStorage")

local Exporter = {}


local POSE_EASING_MAP = {
    Linear    = { Enum.PoseEasingStyle.Linear,   Enum.PoseEasingDirection.Out   },
    EaseIn    = { Enum.PoseEasingStyle.Cubic,    Enum.PoseEasingDirection.In    },
    EaseOut   = { Enum.PoseEasingStyle.Cubic,    Enum.PoseEasingDirection.Out   },
    EaseInOut = { Enum.PoseEasingStyle.Cubic,    Enum.PoseEasingDirection.InOut },
    Constant  = { Enum.PoseEasingStyle.Constant, Enum.PoseEasingDirection.Out   },
    Bounce    = { Enum.PoseEasingStyle.Bounce,   Enum.PoseEasingDirection.Out   },
}

-- ── helpers ───────────────────────────────────────────────────────────────────

local function makePose(name, transform, easing)
    local p           = Instance.new("Pose")
    p.Name            = name
    p.Weight          = 1
    p.CFrame          = transform or CFrame.identity
    local em          = POSE_EASING_MAP[easing or "Linear"] or POSE_EASING_MAP.Linear
    p.EasingStyle     = em[1]
    p.EasingDirection = em[2]
    return p
end

-- ── KeyframeSequence builder ──────────────────────────────────────────────────
-- Flat format: all motor transforms stored as direct children of HumanoidRootPart.
-- Pose name = motor name (e.g. "RootJoint", "Neck", "LeftShoulder").
-- This is rig-agnostic and works for R6, R15, and custom rigs.
-- Legacy R6 format (Torso hierarchy) is handled by the parser on the game side.

local function buildKeyframeSequence(rigName, rigData, fps)
    local kfs             = Instance.new("KeyframeSequence")
    kfs.Name              = rigName .. "_Joints"
    kfs.Loop              = false
    kfs.AuthoredHipHeight = 0

    local sortedFrames = {}
    for f in pairs(rigData.jointTrack) do table.insert(sortedFrames, f) end
    table.sort(sortedFrames)

    for _, frame in ipairs(sortedFrames) do
        local jd     = rigData.jointTrack[frame]
        local easing = rigData.easingTrack and rigData.easingTrack[frame]
        local time   = (frame - 1) / fps

        local kf      = Instance.new("Keyframe")
        kf.Time       = time

        local hrpPose = makePose("HumanoidRootPart", CFrame.identity, easing)

        -- One Pose per motor, named by motor name, sorted for determinism
        local motorNames = {}
        for n in pairs(jd) do table.insert(motorNames, n) end
        table.sort(motorNames)
        for _, motorName in ipairs(motorNames) do
            local pose = makePose(motorName, jd[motorName], easing)
            pose.Parent = hrpPose
        end

        hrpPose.Parent = kf
        kf.Parent      = kfs
    end

    return kfs
end

-- ── ScaleTracks source builder ────────────────────────────────────────────────

local function buildScaleTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    rigs = {")

    for rigName, rigData in pairs(session.rigs) do
        if not next(rigData.scaleTrack) then continue end

        add(string.format("        [%q] = {", rigName))

        local sortedFrames = {}
        for f in pairs(rigData.scaleTrack) do table.insert(sortedFrames, f) end
        table.sort(sortedFrames)

        for _, frame in ipairs(sortedFrames) do
            local sd = rigData.scaleTrack[frame]
            add(string.format("            [%d] = {", frame))
            for partName, v3 in pairs(sd) do
                add(string.format(
                    "                [%q] = {%g, %g, %g},",
                    partName, v3.X, v3.Y, v3.Z
                ))
            end
            add("            },")
        end

        add("        },")
    end

    add("    },")

    -- Per-rig per-frame easing (parallel to rigs table; absent when all Linear)
    local hasEasing = false
    for _, rigData in pairs(session.rigs) do
        if rigData.easingTrack and next(rigData.easingTrack) then
            hasEasing = true; break
        end
    end
    if hasEasing then
        add("    easings = {")
        for rigName, rigData in pairs(session.rigs) do
            if not next(rigData.scaleTrack) then continue end
            if not (rigData.easingTrack and next(rigData.easingTrack)) then continue end
            add(string.format("        [%q] = {", rigName))
            local ef = {}
            for f in pairs(rigData.scaleTrack) do table.insert(ef, f) end
            table.sort(ef)
            for _, frame in ipairs(ef) do
                local e = rigData.easingTrack[frame]
                if e and e ~= "Linear" then
                    add(string.format("            [%d] = %q,", frame, e))
                end
            end
            add("        },")
        end
        add("    },")
    end

    add("}")
    return table.concat(lines, "\n")
end

-- ── RootTracks source builder ─────────────────────────────────────────────────
-- World-space HumanoidRootPart CFrames per rig per frame.
-- Absent if no rig had root movement recorded.

local function buildRootTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    rigs = {")

    for rigName, rigData in pairs(session.rigs) do
        if not rigData.rootTrack or not next(rigData.rootTrack) then continue end

        add(string.format("        [%q] = {", rigName))

        local sortedFrames = {}
        for f in pairs(rigData.rootTrack) do table.insert(sortedFrames, f) end
        table.sort(sortedFrames)

        for _, frame in ipairs(sortedFrames) do
            local cf = rigData.rootTrack[frame]
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            add(string.format(
                "            [%d] = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g},",
                frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22
            ))
        end

        add("        },")
    end

    add("    },")

    local hasEasing = false
    for _, rigData in pairs(session.rigs) do
        if rigData.easingTrack and next(rigData.easingTrack) then
            hasEasing = true; break
        end
    end
    if hasEasing then
        add("    easings = {")
        for rigName, rigData in pairs(session.rigs) do
            if not (rigData.rootTrack and next(rigData.rootTrack)) then continue end
            if not (rigData.easingTrack and next(rigData.easingTrack)) then continue end
            add(string.format("        [%q] = {", rigName))
            local ef = {}
            for f in pairs(rigData.rootTrack) do table.insert(ef, f) end
            table.sort(ef)
            for _, frame in ipairs(ef) do
                local e = rigData.easingTrack[frame]
                if e and e ~= "Linear" then
                    add(string.format("            [%d] = %q,", frame, e))
                end
            end
            add("        },")
        end
        add("    },")
    end

    add("}")
    return table.concat(lines, "\n")
end

-- ── PropTracks source builder ─────────────────────────────────────────────────

local function buildPropTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    props = {")

    for propName, propData in pairs(session.props or {}) do
        if not next(propData.propTrack) then continue end

        add(string.format("        [%q] = {", propName))

        local sortedFrames = {}
        for f in pairs(propData.propTrack) do table.insert(sortedFrames, f) end
        table.sort(sortedFrames)

        for _, frame in ipairs(sortedFrames) do
            local cf = propData.propTrack[frame]
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            add(string.format(
                "            [%d] = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g},",
                frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22
            ))
        end

        add("        },")
    end

    add("    },")

    local hasPropEasing = false
    for _, propData in pairs(session.props or {}) do
        if propData.easingTrack and next(propData.easingTrack) then
            hasPropEasing = true; break
        end
    end
    if hasPropEasing then
        add("    easings = {")
        for propName, propData in pairs(session.props or {}) do
            if not next(propData.propTrack) then continue end
            if not (propData.easingTrack and next(propData.easingTrack)) then continue end
            add(string.format("        [%q] = {", propName))
            local ef = {}
            for f in pairs(propData.propTrack) do table.insert(ef, f) end
            table.sort(ef)
            for _, frame in ipairs(ef) do
                local e = propData.easingTrack[frame]
                if e and e ~= "Linear" then
                    add(string.format("            [%d] = %q,", frame, e))
                end
            end
            add("        },")
        end
        add("    },")
    end

    add("}")
    return table.concat(lines, "\n")
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Exports session data to ServerStorage.MultiAnimationData/<sceneName>/.
-- Returns (true, sceneName) on success or (false, errorMsg) on failure.
-- ── CameraTrack source builder ────────────────────────────────────────────────
-- One camera track per scene: {fps, frames = {[n] = {cf={12 numbers}, fov, cut}}}.
-- cut = true means the camera jumps to this keyframe instead of interpolating.

local function buildCameraTrackSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    frames = {")

    local track = (session.camera and session.camera.track) or {}
    local sortedFrames = {}
    for f in pairs(track) do table.insert(sortedFrames, f) end
    table.sort(sortedFrames)

    for _, frame in ipairs(sortedFrames) do
        local kf = track[frame]
        local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = kf.cf:GetComponents()
        add(string.format(
            "        [%d] = {cf = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g}, fov = %g, cut = %s, easing = %q},",
            frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22,
            kf.fov or 70, tostring(kf.mode == "cut"), kf.easing or "Linear"
        ))
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── EffectTracks source builder ───────────────────────────────────────────────
-- One-shot events: {fps, effects = {name = {target = "full.path", events =
-- {[frame] = {action = "emit", count = 15}}}}}. Fired when playback crosses
-- the frame; never interpolated.

local function buildEffectTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    effects = {")

    local names = {}
    for name in pairs(session.effects or {}) do table.insert(names, name) end
    table.sort(names)

    for _, name in ipairs(names) do
        local fx = session.effects[name]
        if next(fx.track) then
            add(string.format("        [%q] = {", name))
            add(string.format("            target = %q,", fx.path or ""))
            add("            events = {")
            local sortedFrames = {}
            for f in pairs(fx.track) do table.insert(sortedFrames, f) end
            table.sort(sortedFrames)
            for _, frame in ipairs(sortedFrames) do
                local ev = fx.track[frame]
                if ev.count then
                    add(string.format("                [%d] = {action = %q, count = %d},",
                        frame, ev.action, ev.count))
                else
                    add(string.format("                [%d] = {action = %q},", frame, ev.action))
                end
            end
            add("            },")
            add("        },")
        end
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── SpawnedEffects source builder ─────────────────────────────────────────────

local function buildSpawnedEffectsSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add("    effects = {")
    for _, fx in ipairs(session.spawnedEffects or {}) do
        add(string.format(
            "        {id=%d, frame=%d, effectType=%q, posX=%.4f, posY=%.4f, posZ=%.4f," ..
            " size=%.2f, colorR=%d, colorG=%d, colorB=%d, count=%d, duration=%.2f, speed=%.2f, lifetime=%.2f},",
            fx.id, fx.frame, fx.effectType, fx.posX or 0, fx.posY or 0, fx.posZ or 0,
            fx.size or 3, fx.colorR or 255, fx.colorG or 80, fx.colorB or 0,
            fx.count or 50, fx.duration or 0.6, fx.speed or 20, fx.lifetime or 1.0
        ))
    end
    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

function Exporter.export(session, sceneName)
    if not session or not session.rigs or not next(session.rigs) then
        warn("[Exporter] Nothing to export — record some keyframes first")
        return false, "no session data"
    end
    if not sceneName or sceneName:match("^%s*$") then
        warn("[Exporter] Scene name is empty")
        return false, "empty scene name"
    end

    local fps = session.fps or 24

    local mad = ServerStorage:FindFirstChild("MultiAnimationData")
    if not mad then
        mad        = Instance.new("Folder")
        mad.Name   = "MultiAnimationData"
        mad.Parent = ServerStorage
    end

    local existing = mad:FindFirstChild(sceneName)
    if existing then
        existing:Destroy()
        print(string.format("[Exporter] Overwriting existing scene '%s'", sceneName))
    end

    local sceneFolder   = Instance.new("Folder")
    sceneFolder.Name    = sceneName
    sceneFolder.Parent  = mad

    local kfsCount = 0
    for rigName, rigData in pairs(session.rigs) do
        if not next(rigData.jointTrack) then continue end
        local kfs  = buildKeyframeSequence(rigName, rigData, fps)
        kfs.Parent = sceneFolder
        kfsCount  += 1
    end

    local scaleModule        = Instance.new("ModuleScript")
    scaleModule.Name         = "ScaleTracks"
    scaleModule.Source       = buildScaleTracksSource(session)
    scaleModule.Parent       = sceneFolder

    -- RootTracks — only written when any rig had whole-model movement recorded
    local hasRootData = false
    for _, rd in pairs(session.rigs) do
        if rd.rootTrack and next(rd.rootTrack) then hasRootData = true; break end
    end
    if hasRootData then
        local rootModule        = Instance.new("ModuleScript")
        rootModule.Name         = "RootTracks"
        rootModule.Source       = buildRootTracksSource(session)
        rootModule.Parent       = sceneFolder
    end

    -- PropTracks — only written when props were tracked
    local hasPropData = false
    for _, pd in pairs(session.props or {}) do
        if next(pd.propTrack) then hasPropData = true; break end
    end
    if hasPropData then
        local propModule        = Instance.new("ModuleScript")
        propModule.Name         = "PropTracks"
        propModule.Source       = buildPropTracksSource(session)
        propModule.Parent       = sceneFolder
    end

    -- CameraTrack — only written when camera keyframes were recorded
    if session.camera and session.camera.track and next(session.camera.track) then
        local camModule        = Instance.new("ModuleScript")
        camModule.Name         = "CameraTrack"
        camModule.Source       = buildCameraTrackSource(session)
        camModule.Parent       = sceneFolder
    end

    -- EffectTracks — only written when any effect has events
    local hasEffectData = false
    for _, fx in pairs(session.effects or {}) do
        if next(fx.track) then hasEffectData = true; break end
    end
    if hasEffectData then
        local fxModule        = Instance.new("ModuleScript")
        fxModule.Name         = "EffectTracks"
        fxModule.Source       = buildEffectTracksSource(session)
        fxModule.Parent       = sceneFolder
    end

    -- SpawnedEffects — only written when any spawned effects are configured
    if session.spawnedEffects and next(session.spawnedEffects) then
        local sfxModule        = Instance.new("ModuleScript")
        sfxModule.Name         = "SpawnedEffects"
        sfxModule.Source       = buildSpawnedEffectsSource(session)
        sfxModule.Parent       = sceneFolder
    end

    -- Deploy game-side modules.
    -- Server-side (ServerStorage.MultiAnimationData): MultiAnimPlayer, CutsceneServer,
    --   CutsceneCamera, MultiAnimDataServer, SpawnedEffectRunner.
    -- Client-side (ReplicatedStorage): CutscenePlayer, CutsceneCamera, PlayerRigProxy,
    --   LetterboxGui — siblings so CutscenePlayer's require() finds them.
    local gameFolder = script.Parent.Parent:FindFirstChild("game")
    if gameFolder then
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local serverMods = { "MultiAnimPlayer", "CutsceneServer", "CutsceneCamera", "MultiAnimDataServer", "SpawnedEffectRunner" }
        local clientMods = { "CutscenePlayer", "CutsceneCamera", "PlayerRigProxy", "LetterboxGui", "SpawnedEffectRunner" }
        for _, modName in ipairs(serverMods) do
            local src = gameFolder:FindFirstChild(modName)
            if src then
                local prev = mad:FindFirstChild(modName)
                if prev then prev:Destroy() end
                src:Clone().Parent = mad
            end
        end
        for _, modName in ipairs(clientMods) do
            local src = gameFolder:FindFirstChild(modName)
            if src then
                local prev = ReplicatedStorage:FindFirstChild(modName)
                if prev then prev:Destroy() end
                src:Clone().Parent = ReplicatedStorage
            end
        end
    end

    print(string.format(
        "[Exporter] Scene '%s' exported — %d rig(s)\n" ..
        "  Server: ServerStorage.MultiAnimationData (MultiAnimPlayer, CutsceneServer, CutsceneCamera, MultiAnimDataServer, SpawnedEffectRunner)\n" ..
        "  Client: ReplicatedStorage (CutscenePlayer, CutsceneCamera, PlayerRigProxy, LetterboxGui, SpawnedEffectRunner)\n" ..
        "  Server prerequisite: require(game.ServerStorage.MultiAnimationData.MultiAnimDataServer).setup()",
        sceneName, kfsCount
    ))
    return true, sceneName
end

return Exporter
