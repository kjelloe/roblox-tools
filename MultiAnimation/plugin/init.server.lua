-- MultiAnimation Plugin — entry point
-- Wires all core and UI modules together. Owns the playback loop.
--
-- MOTOR6D SESSION MANAGEMENT
--   Motor6D joints act as welds in Studio edit mode: setting any Part.CFrame
--   moves the entire connected assembly.  We keep ALL Motor6D joints in all
--   rigs DISCONNECTED (Part0 = nil) for the entire plugin session.  This lets
--   the user pose individual limbs freely and lets apply() work correctly.
--   Motors are reconnected only when the plugin unloads (leaving a clean rig).

-- Bail out immediately when running as a game server script during play mode.
-- RunService:IsRunning() is true in any game context; false in the Studio
-- editor / plugin context where this code actually belongs.
if game:GetService("RunService"):IsRunning() then return end

-- devsync hot-reload: tear down the previous instance before booting this one.
-- _G is per plugin VM, so this is a no-op for a normally installed plugin and
-- only fires when the dev loader re-runs this source in the same VM.
if _G.__MultiAnimTeardown then
    pcall(_G.__MultiAnimTeardown)
    _G.__MultiAnimTeardown = nil
end

-- Boot counter for this plugin VM — used to derive fallback IDs when a
-- toolbar/button/widget ID is still registered from an earlier hot-reload.
_G.__MultiAnimBootCount = (_G.__MultiAnimBootCount or 0) + 1
local BOOT_N = _G.__MultiAnimBootCount

local RunService           = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService          = game:GetService("HttpService")
local Selection            = game:GetService("Selection")

local RigScanner    = require(script.core.RigScanner)
local JointCapture  = require(script.core.JointCapture)
local Recorder      = require(script.core.Recorder)
local Timeline      = require(script.core.Timeline)
local Interpolator  = require(script.core.Interpolator)
local PoseApplier   = require(script.core.PoseApplier)
local Exporter      = require(script.core.Exporter)
local CameraCapture = require(script.core.CameraCapture)
local EffectRunner  = require(script.core.EffectRunner)
local Panel         = require(script.ui.Panel)
-- PropCapture required for its apply path (called via PoseApplier); Recorder requires it directly.

-- DataModel-level connections (everything not parented under the widget) must
-- be disconnected on devsync hot-reload or they accumulate across boots.
local devConns = {}
local function track(conn)
    table.insert(devConns, conn)
    return conn
end

-- ── Toolbar & widget ──────────────────────────────────────────────────────────

-- Toolbar and button IDs stay registered in the plugin VM even after
-- toolbar:Destroy(), so re-creating them on a devsync hot-reload errors
-- ("Cannot create more than one button with id ..."). Cache and reuse them
-- across boots; if the cache is empty but the ID is burned (e.g. an older
-- plugin version booted first in this VM), fall back to a suffixed ID.
local toolbar = _G.__MultiAnimToolbar
if not toolbar then
    local ok, tb = pcall(function() return plugin:CreateToolbar("MultiAnimation") end)
    toolbar = ok and tb or plugin:CreateToolbar("MultiAnimation " .. BOOT_N)
    _G.__MultiAnimToolbar = toolbar
end

local toggleButton = _G.__MultiAnimToggleButton
if not toggleButton then
    local ok, btn = pcall(function()
        return toolbar:CreateButton("MultiAnimation", "Open / close the MultiAnimation panel", "")
    end)
    toggleButton = ok and btn or toolbar:CreateButton(
        "MultiAnimation " .. BOOT_N, "Open / close the MultiAnimation panel", "")
    _G.__MultiAnimToggleButton = toggleButton
end

local widgetInfo = DockWidgetPluginGuiInfo.new(
    Enum.InitialDockState.Bottom,
    false, false, 300, 200, 220, 140
)
-- The widget ID may still be registered from a previous hot-reload boot in the
-- same plugin VM; fall back to a suffixed ID so re-creation never hard-fails.
local widget
do
    local ok, w = pcall(function()
        return plugin:CreateDockWidgetPluginGui("MultiAnimation", widgetInfo)
    end)
    if ok then
        widget = w
    else
        widget = plugin:CreateDockWidgetPluginGui("MultiAnimation_dev" .. BOOT_N, widgetInfo)
    end
end
widget.Title = "MultiAnimation"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
    toggleButton:SetActive(widget.Enabled)
end)
-- toggleButton persists across hot-reloads — its Click connection must be
-- tracked or each boot would stack another handler on the same button.
track(toggleButton.Click:Connect(function()
    widget.Enabled = not widget.Enabled
end))

-- ── Core state ────────────────────────────────────────────────────────────────

local timeline = Timeline.new(24, 120)
local recorder = Recorder.new()
local panel    = Panel.new(widget)

local allRigs      = {}   -- { [rigName] = Model }
local allProps     = {}   -- { [propName] = BasePart }
local allEffects   = {}   -- { [effectName] = effect Instance (emitter/sound/light…) }
local motorStates  = {}   -- { [rigName] = disconnectAll() state } for cleanup
local isPlaying    = false
local playConn     = nil

-- Camera track state (Phase 8). Vars live up here so applyPosesAt (defined
-- early) sees them as upvalues; the helper functions are defined further down.
local CAM_GIZMO_FOLDER = "__MultiAnimCameraGizmos"
local camPreviewOn   = false
local savedCamState  = nil    -- viewport camera snapshot while preview is on
local camGizmos      = {}     -- { [frame] = Part }
local gizmoSyncing   = false  -- guards the gizmo CFrame-changed feedback loop

-- Simple Mode state (mode toggle + camera-view-while-posing flag)
local mode = "advanced"   -- "advanced" | "simple" | "playback"
local simpleCameraOn = false
local advancedFrameCount = nil   -- saved frameCount to restore when leaving Simple Mode

-- Simple Mode camera object: a manipulable Part in FIGURES standing in for
-- the camera, posed with Studio's normal tools instead of capturing the
-- ambient viewport. Look Through mirrors it onto workspace.CurrentCamera.
local SIMPLE_CAMERA_NAME    = "SimpleCamera"
local simpleCameraPart      = nil
local simpleCameraFOV       = 70
local simpleLookThroughOn   = false
local simpleOnionOn         = false
local savedSimpleCamState   = nil
local simpleLookThroughConn = nil
local setSimpleLookThroughOn -- forward declared; defined in the SIMPLE MODE section, used by setSimpleCameraOn below

-- Playback tab state
local playbackScene    = nil    -- string: selected scene name
local playbackScenes   = {}     -- sorted list of saved scene names
local playbackSceneIdx = 0      -- index into playbackScenes (1-based)
local playbackRigModes = {}     -- { [rigName] = modeKey }
local playbackFPS      = 30
local playbackLoop     = false
local playbackMovieMode= false

-- FOV-frustum outline drawn on the SimpleCamera part — an apex (the part's
-- origin) plus a far rectangle sized from the FOV, so aim and field of view
-- are both visible at a glance. Aspect is a fixed estimate (the gizmo
-- doesn't know the runtime viewport's actual aspect ratio).
--
-- Built from thin welded Parts rather than a WireframeHandleAdornment:
-- screen_capture cannot render WireframeHandleAdornment content at all
-- (confirmed via isolated test instances), and in live Studio its Adornee
-- did not track the part's position either. Real Parts always render, and
-- WeldConstraint to simpleCameraPart (Anchored) rigidly carries them along
-- through Roblox's assembly mechanics on ANY CFrame change to the camera
-- part — scripted (scrubbing/playback/Look Through) or Studio's own drag
-- tool — exactly like the Motor6D rigid-weld behavior already relied on
-- elsewhere in this file for rigs.
local SIMPLE_CAM_FRUSTUM_DEPTH     = 4
local SIMPLE_CAM_FRUSTUM_ASPECT    = 16 / 9
local SIMPLE_CAM_FRUSTUM_THICKNESS = 0.06

local function addFrustumEdge(folder, part, fromLocal, toLocal)
    local mid    = fromLocal:Lerp(toLocal, 0.5)
    local length = (toLocal - fromLocal).Magnitude
    local localCF = CFrame.new(mid, mid + (toLocal - fromLocal))

    local edge = Instance.new("Part")
    edge.Name        = "Edge"
    edge.Size        = Vector3.new(SIMPLE_CAM_FRUSTUM_THICKNESS, SIMPLE_CAM_FRUSTUM_THICKNESS, length)
    edge.Anchored    = false
    edge.CanCollide  = false
    edge.CanQuery    = false
    edge.CastShadow  = false
    edge.Massless    = true
    edge.Locked      = true
    edge.Material    = Enum.Material.Neon
    edge.Color       = Color3.fromRGB(255, 200, 40)
    edge.Archivable  = false
    edge.CFrame      = part.CFrame * localCF
    edge.Parent      = folder

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = part
    weld.Part1 = edge
    weld.Parent = edge
end

local function drawSimpleCameraFrustum(part, fov)
    local old = part:FindFirstChild("FOVFrustum")
    if old then old:Destroy() end

    local folder = Instance.new("Folder")
    folder.Name       = "FOVFrustum"
    folder.Archivable = false
    folder.Parent     = part   -- parent first so edge Parts are in Workspace from creation

    local depth = SIMPLE_CAM_FRUSTUM_DEPTH
    local vHalf = math.rad(fov) / 2
    local hHalf = math.atan(math.tan(vHalf) * SIMPLE_CAM_FRUSTUM_ASPECT)
    local y = depth * math.tan(vHalf)
    local x = depth * math.tan(hHalf)

    -- Front face (-Z) is the look direction, matching the existing camera-
    -- gizmo convention used elsewhere in this file.
    local apex = Vector3.new(0, 0, 0)
    local corners = {
        Vector3.new(-x,  y, -depth),
        Vector3.new( x,  y, -depth),
        Vector3.new( x, -y, -depth),
        Vector3.new(-x, -y, -depth),
    }
    for _, c in ipairs(corners) do
        addFrustumEdge(folder, part, apex, c)
    end
    for i, c in ipairs(corners) do
        local next_ = corners[(i % #corners) + 1]
        addFrustumEdge(folder, part, c, next_)
    end
end

-- ── Motor management ──────────────────────────────────────────────────────────

local function disconnectRig(rigName, model)
    if not motorStates[rigName] then
        motorStates[rigName] = JointCapture.disconnectAll(model)
        print(string.format("[MultiAnimation] Motors disconnected for %s (free-pose mode)", rigName))
    end
end

local function disconnectAllRigs()
    for rigName, model in pairs(allRigs) do
        disconnectRig(rigName, model)
    end
end

local function reconnectAllRigs()
    for rigName, model in pairs(allRigs) do
        local state = motorStates[rigName]
        if state then
            JointCapture.reconnectAll(model, state)
            motorStates[rigName] = nil
        end
    end
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function applyPosesAt(queryFrame, immediate)
    for rigName, model in pairs(allRigs) do
        local jd = Interpolator.getJointData(recorder, rigName, queryFrame)
        local sd = Interpolator.getScaleData(recorder, rigName, queryFrame)
        local rd = Interpolator.getRootData(recorder, rigName, queryFrame)
        if jd then
            if immediate then
                PoseApplier.applyImmediate(model, jd, sd, rd)
            else
                PoseApplier.applyRecorded(model, jd, sd, rd)
            end
        end
    end
    -- Apply prop poses
    local propCFrames = {}
    for propName in pairs(allProps) do
        local cf = Interpolator.getPropData(recorder, propName, queryFrame)
        if cf then propCFrames[propName] = cf end
    end
    if next(propCFrames) then
        if immediate then
            PoseApplier.applyPropImmediate(allProps, propCFrames)
        else
            PoseApplier.applyPropRecorded(allProps, propCFrames)
        end
    end

    -- Camera Preview: slave the Studio viewport to the interpolated camera track.
    if camPreviewOn then
        local camData = Interpolator.getCameraData(recorder, queryFrame)
        if camData then
            CameraCapture.apply(camData.cf, camData.fov)
        end
    end

    -- Simple Mode: pose the manipulable camera gizmo itself (not the
    -- viewport — that's Look Through's job, mirrored independently via its
    -- own Heartbeat connection below). Apply whenever the part exists,
    -- regardless of the Camera View toggle state, so scrub/playback always
    -- reflects recorded camera poses.
    if mode == "simple" and simpleCameraPart and simpleCameraPart.Parent then
        local camData = Interpolator.getCameraData(recorder, queryFrame)
        if camData then
            local camCFrames = { [SIMPLE_CAMERA_NAME] = camData.cf }
            local camParts    = { [SIMPLE_CAMERA_NAME] = simpleCameraPart }
            if immediate then
                PoseApplier.applyPropImmediate(camParts, camCFrames)
            else
                PoseApplier.applyPropRecorded(camParts, camCFrames)
            end
            simpleCameraFOV = camData.fov
            simpleCameraPart:SetAttribute("FOV", camData.fov)
            if simpleCameraOn then
                drawSimpleCameraFrustum(simpleCameraPart, camData.fov)
            end
            panel:setSimpleFOVDisplay(camData.fov)
        end
    end
    -- Keep the "Cam KF: move/cut/—" button reflecting the current frame.
    local camKF = recorder:getCameraData(math.floor(queryFrame + 0.5))
    panel:setCameraModeDisplay(camKF and camKF.mode or nil)
end

-- Non-rig FIGURES child → its world-CFrame-trackable BasePart (Simple Mode).
local function getPropPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function allKeyframesSorted()
    local rigNames = {}
    for n in pairs(allRigs) do table.insert(rigNames, n) end
    local propNames = {}
    for n in pairs(allProps) do table.insert(propNames, n) end

    local seen = {}
    for _, f in ipairs(Interpolator.getAllFrames(recorder, rigNames)) do seen[f] = true end
    for _, f in ipairs(Interpolator.getAllPropFrames(recorder, propNames)) do seen[f] = true end
    local result = {}
    for f in pairs(seen) do table.insert(result, f) end
    table.sort(result)
    return result
end

-- ── Session persistence ───────────────────────────────────────────────────────

local INDEX_KEY   = "MultiAnim_Index_v2"
local DATA_PREFIX = "MultiAnim_Data_v2_"
local MAX_SAVES   = 30

-- Forward declarations — defined in the CAMERA TRACK section below.
-- applySessionData needs them but is defined first.
local updateCameraGizmo, clearCameraGizmos, rebuildCameraUI

local function serializeSession()
    local session = recorder:getSession()
    -- When in simple/playback mode the timeline has a small synthetic frame count;
    -- serialize the real advanced count so plugin reloads don't start with 1–2 frames.
    local savedFC = advancedFrameCount or session.frameCount
    local out = { fps = session.fps, frameCount = savedFC, rigs = {}, props = {} }
    for rigName, rigData in pairs(session.rigs) do
        local jOut, sOut = {}, {}
        for frame, jointData in pairs(rigData.jointTrack) do
            local jd = {}
            for jName, cf in pairs(jointData) do
                local c = { cf:GetComponents() }
                jd[jName] = c
            end
            jOut[tostring(frame)] = jd
        end
        for frame, scaleData in pairs(rigData.scaleTrack) do
            local sd = {}
            for pName, v3 in pairs(scaleData) do
                sd[pName] = { v3.X, v3.Y, v3.Z }
            end
            sOut[tostring(frame)] = sd
        end
        local rOut = {}
        for frame, cf in pairs(rigData.rootTrack or {}) do
            rOut[tostring(frame)] = { cf:GetComponents() }
        end
        out.rigs[rigName] = { joints = jOut, scales = sOut, roots = rOut }
    end
    for propName, propData in pairs(session.props or {}) do
        local pOut = {}
        for frame, cf in pairs(propData.propTrack) do
            pOut[tostring(frame)] = { cf:GetComponents() }
        end
        out.props[propName] = pOut
    end
    out.camera = {}
    for frame, kf in pairs((session.camera and session.camera.track) or {}) do
        out.camera[tostring(frame)] = {
            cf   = { kf.cf:GetComponents() },
            fov  = kf.fov,
            mode = kf.mode,
        }
    end
    out.effects = {}
    for name, fx in pairs(session.effects or {}) do
        local tOut = {}
        for frame, ev in pairs(fx.track) do
            tOut[tostring(frame)] = { action = ev.action, count = ev.count }
        end
        out.effects[name] = { kind = fx.kind, action = fx.action, path = fx.path, track = tOut }
    end
    return out
end

local function getIndex()
    local ok, idx = pcall(function() return plugin:GetSetting(INDEX_KEY) end)
    return (ok and type(idx) == "table") and idx or {}
end

local function saveNamed(name)
    local ok, err = pcall(function()
        plugin:SetSetting(DATA_PREFIX .. name, serializeSession())
    end)
    if not ok then
        warn("[MultiAnimation] Save failed: " .. tostring(err))
        return
    end
    local idx = getIndex()
    for i = #idx, 1, -1 do
        if idx[i].name == name then table.remove(idx, i) end
    end
    table.insert(idx, 1, { name = name, savedAt = os.time() })
    while #idx > MAX_SAVES do
        local dropped = table.remove(idx)
        pcall(function() plugin:SetSetting(DATA_PREFIX .. dropped.name, nil) end)
    end
    pcall(function() plugin:SetSetting(INDEX_KEY, idx) end)
    print("[MultiAnimation] Saved as '" .. name .. "'")
end

local function applySessionData(data)
    -- Clear existing prop UI before clearing recorder
    for propName in pairs(allProps) do
        panel:removeProp(propName)
    end
    allProps = {}

    -- Clear camera UI (markers + gizmos) before the recorder data goes away.
    for _, f in ipairs(recorder:getSortedCameraFrames()) do
        panel:removeCameraKeyframeMarker(f)
    end
    if clearCameraGizmos then clearCameraGizmos() end

    -- Clear effect UI (chips + lanes).
    for name in pairs(recorder:getSession().effects or {}) do
        panel:removeEffect(name)
    end
    allEffects = {}

    recorder:clearSession()
    local fps        = data.fps        or 24
    -- Minimum of 20: guards against a corrupt autosave (e.g. from a tiny Simple
    -- Mode session) producing a frameCount too small for the advanced timeline.
    -- Simple mode overwrites this with its own keyframe-derived count anyway.
    local frameCount = math.max(data.frameCount or 120, 20)
    recorder:setFps(fps)
    recorder:setFrameCount(frameCount)
    timeline:setFps(fps)
    timeline:setFrameCount(frameCount)
    for rigName, rigData in pairs(data.rigs) do
        for frameStr, jd in pairs(rigData.joints or {}) do
            local frame = tonumber(frameStr)
            if frame then
                local jointData = {}
                for jName, arr in pairs(jd) do
                    jointData[jName] = CFrame.new(
                        arr[1],  arr[2],  arr[3],
                        arr[4],  arr[5],  arr[6],
                        arr[7],  arr[8],  arr[9],
                        arr[10], arr[11], arr[12]
                    )
                end
                recorder:setJointData(rigName, frame, jointData)
            end
        end
        for frameStr, sd in pairs(rigData.scales or {}) do
            local frame = tonumber(frameStr)
            if frame then
                local scaleData = {}
                for pName, arr in pairs(sd) do
                    scaleData[pName] = Vector3.new(arr[1], arr[2], arr[3])
                end
                recorder:setScaleData(rigName, frame, scaleData)
            end
        end
        for frameStr, arr in pairs(rigData.roots or {}) do
            local frame = tonumber(frameStr)
            if frame then
                recorder:setRootData(rigName, frame, CFrame.new(
                    arr[1], arr[2], arr[3], arr[4], arr[5], arr[6],
                    arr[7], arr[8], arr[9], arr[10], arr[11], arr[12]
                ))
            end
        end
    end
    -- Restore prop data; attempt to re-link parts by name from Workspace
    for propName, propFrames in pairs(data.props or {}) do
        for frameStr, arr in pairs(propFrames) do
            local frame = tonumber(frameStr)
            if frame then
                recorder:setPropData(propName, frame, CFrame.new(
                    arr[1], arr[2], arr[3], arr[4], arr[5], arr[6],
                    arr[7], arr[8], arr[9], arr[10], arr[11], arr[12]
                ))
            end
        end
        -- Try to find the part in Workspace so it can be re-linked
        local part = workspace:FindFirstChild(propName, true)
        if part and part:IsA("BasePart") and not allRigs[propName] then
            allProps[propName] = part
            panel:addProp(propName, part)
        else
            -- Data is preserved in recorder for export but no live link
            panel:addProp(propName, nil)
        end
        for _, frame in ipairs(recorder:getSortedPropFrames(propName)) do
            panel:addPropKeyframeMarker(propName, frame)
        end
    end
    -- Restore camera track keyframes.
    for frameStr, kf in pairs(data.camera or {}) do
        local frame = tonumber(frameStr)
        if frame and kf.cf then
            recorder:addCameraKeyframe(frame, CFrame.new(
                kf.cf[1],  kf.cf[2],  kf.cf[3],
                kf.cf[4],  kf.cf[5],  kf.cf[6],
                kf.cf[7],  kf.cf[8],  kf.cf[9],
                kf.cf[10], kf.cf[11], kf.cf[12]
            ), kf.fov, kf.mode)
        end
    end

    -- Restore effect tracks; re-link live instances by name.
    for name, fxData in pairs(data.effects or {}) do
        local fx = recorder:registerEffect(name, fxData.kind, fxData.action, fxData.path)
        for frameStr, ev in pairs(fxData.track or {}) do
            local frame = tonumber(frameStr)
            if frame then
                fx.track[frame] = { action = ev.action, count = ev.count }
            end
        end
        local inst = workspace:FindFirstChild(name, true)
        if inst and EffectRunner.classify(inst) then
            allEffects[name] = inst
        end
        panel:addEffect(name, fx.action)
        for _, f in ipairs(recorder:getSortedEffectFrames(name)) do
            panel:addEffectMarker(name, f)
        end
    end

    panel:setRigs(allRigs)
    for rigName in pairs(allRigs) do
        for _, frame in ipairs(recorder:getSortedFrames(rigName)) do
            panel:addKeyframeMarker(rigName, frame)
        end
    end
    if rebuildCameraUI then rebuildCameraUI() end
    panel:setFrameCount(frameCount)
    panel:setFrameDisplay(timeline:getCurrent(), frameCount)
end

local function loadNamed(name)
    local ok, data = pcall(function() return plugin:GetSetting(DATA_PREFIX .. name) end)
    if not ok or not data or not data.rigs then
        warn("[MultiAnimation] Save '" .. name .. "' not found")
        return
    end
    applySessionData(data)
    print("[MultiAnimation] Loaded '" .. name .. "'")
end

-- ── Auto-save ─────────────────────────────────────────────────────────────────
-- Debounced: batches rapid keyframe additions into one save per second.

local _autoSavePending = false
local function scheduleAutoSave()
    if _autoSavePending then return end
    _autoSavePending = true
    task.delay(1, function()
        _autoSavePending = false
        saveNamed("_autosave")
    end)
end

-- ── CAMERA TRACK (Phase 8) ────────────────────────────────────────────────────
-- One camera track on the shared timeline. Keyframes are captured from the
-- Studio viewport camera; gizmo parts visualize each shot in the scene.
-- Gizmos are Archivable = false so they never save into the place file.

local CAM_GIZMO_MOVE_COLOUR = Color3.fromRGB(255, 150, 40)
local CAM_GIZMO_CUT_COLOUR  = Color3.fromRGB(255, 80, 80)

local function getGizmoFolder()
    local folder = workspace:FindFirstChild(CAM_GIZMO_FOLDER)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = CAM_GIZMO_FOLDER
        folder.Archivable = false
        folder.Parent = workspace
    end
    return folder
end

-- Create/refresh (or remove, if the keyframe is gone) the gizmo for one frame.
function updateCameraGizmo(frame)
    local kf = recorder:getCameraData(frame)
    if not kf then
        if camGizmos[frame] then
            camGizmos[frame]:Destroy()
            camGizmos[frame] = nil
        end
        return
    end

    local gizmo = camGizmos[frame]
    if not gizmo then
        gizmo = Instance.new("Part")
        gizmo.Name        = "CamKF_" .. frame
        gizmo.Size        = Vector3.new(0.7, 0.7, 1.4)
        gizmo.Anchored    = true
        gizmo.CanCollide  = false
        gizmo.CastShadow  = false
        gizmo.Transparency = 0.25
        gizmo.Archivable  = false
        -- Hinge stud on the front face marks the look direction (-Z).
        gizmo.FrontSurface  = Enum.SurfaceType.Hinge
        gizmo.TopSurface    = Enum.SurfaceType.Smooth
        gizmo.BottomSurface = Enum.SurfaceType.Smooth
        gizmo.Parent = getGizmoFolder()

        -- Dragging the gizmo with Studio tools re-aims that keyframe.
        gizmo:GetPropertyChangedSignal("CFrame"):Connect(function()
            if gizmoSyncing then return end
            local current = recorder:getCameraData(frame)
            if current then
                recorder:addCameraKeyframe(frame, gizmo.CFrame, current.fov, current.mode)
                scheduleAutoSave()
            end
        end)
        camGizmos[frame] = gizmo
    end

    gizmoSyncing = true
    gizmo.CFrame = kf.cf
    gizmo.Color  = kf.mode == "cut" and CAM_GIZMO_CUT_COLOUR or CAM_GIZMO_MOVE_COLOUR
    gizmoSyncing = false
end

function clearCameraGizmos()
    for _, gizmo in pairs(camGizmos) do
        gizmo:Destroy()
    end
    camGizmos = {}
    local folder = workspace:FindFirstChild(CAM_GIZMO_FOLDER)
    if folder then folder:Destroy() end
end

-- Rebuild markers + gizmos from recorder state (after load / new session).
function rebuildCameraUI()
    for _, frame in ipairs(recorder:getSortedCameraFrames()) do
        local kf = recorder:getCameraData(frame)
        panel:addCameraKeyframeMarker(frame, kf.mode)
        updateCameraGizmo(frame)
    end
end

-- ── ADD RIG (Phase 9) ─────────────────────────────────────────────────────────
-- Clones Rig1 (or the first tracked rig) into FIGURES under the next free
-- RigN name, offset sideways so it doesn't overlap. The clone gets canonical
-- Motor6D connections (the source's are nil'd by this plugin session); the
-- FIGURES auto-detect then picks it up and manages it like any other rig.

local ADDRIG_JOINT_PARENT = {
    RootJoint = "HumanoidRootPart", Neck = "Torso",
    ["Right Shoulder"] = "Torso", ["Left Shoulder"] = "Torso",
    ["Right Hip"] = "Torso", ["Left Hip"] = "Torso",
}

local function doAddRig()
    local fig = workspace:FindFirstChild("FIGURES")
    if not fig then
        warn("[MultiAnimation] No Workspace.FIGURES folder — nothing to clone into")
        return nil
    end

    local src = fig:FindFirstChild("Rig1")
    if not src then
        local names = {}
        for n in pairs(allRigs) do table.insert(names, n) end
        table.sort(names)
        src = names[1] and fig:FindFirstChild(names[1])
    end
    if not src then
        warn("[MultiAnimation] No source rig found to clone")
        return nil
    end

    local n = 2
    while fig:FindFirstChild("Rig" .. n) do n += 1 end
    local name = "Rig" .. n

    local rigCount = 0
    for _, c in ipairs(fig:GetChildren()) do
        if c:FindFirstChildOfClass("Humanoid") then rigCount += 1 end
    end

    local clone = src:Clone()
    clone.Name = name
    for jName, pName in pairs(ADDRIG_JOINT_PARENT) do
        local container = clone:FindFirstChild(pName)
        local motor = container and container:FindFirstChild(jName)
        if motor and motor:IsA("Motor6D") then
            motor.Part0 = container
        end
    end
    clone.Parent = fig
    clone:PivotTo(src:GetPivot() * CFrame.new(5 * rigCount, 0, 0))
    print(string.format("[MultiAnimation] Added rig '%s' (offset +%d studs)", name, 5 * rigCount))
    return name
end

-- ── KEYFRAME CLIPBOARD (Phase 9) ──────────────────────────────────────────────
-- Copy the active rig's keyframe at the current frame; paste it onto the
-- active rig at the current frame — optionally mirrored left↔right.
-- Pose only (joints + scales); the target rig keeps its own world position.

local MIRROR_JOINT = {
    ["Right Shoulder"] = "Left Shoulder", ["Left Shoulder"] = "Right Shoulder",
    ["Right Hip"] = "Left Hip", ["Left Hip"] = "Right Hip",
    RootJoint = "RootJoint", Neck = "Neck",
}
local MIRROR_PART = {
    ["Right Arm"] = "Left Arm", ["Left Arm"] = "Right Arm",
    ["Right Leg"] = "Left Leg", ["Left Leg"] = "Right Leg",
    Head = "Head", Torso = "Torso", HumanoidRootPart = "HumanoidRootPart",
}

-- Mirror a joint transform across the rig's left-right (YZ) plane:
-- conjugation by diag(-1,1,1) — negate x and the xy/xz/yx/zx rotation terms.
-- Determinant stays +1, so the result is a valid rotation.
local function mirrorCF(cf)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
    return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

local kfClipboard = nil   -- { rig, frame, joints = {name=CFrame}, scales = {name=Vector3} }

local function activeRigName()
    for n in pairs(panel:getActiveRigs()) do return n end
    return nil
end

local function doCopyKeyframe()
    local rigName = activeRigName()
    if not rigName then
        warn("[MultiAnimation] No active rig to copy from")
        return false
    end
    local frame = timeline:getCurrent()
    local jd = recorder:getJointData(rigName, frame)
    if not jd then
        warn(string.format("[MultiAnimation] %s has no keyframe at frame %d", rigName, frame))
        return false
    end
    local joints, scales = {}, {}
    for k, v in pairs(jd) do joints[k] = v end
    for k, v in pairs(recorder:getScaleData(rigName, frame) or {}) do scales[k] = v end
    kfClipboard = { rig = rigName, frame = frame, joints = joints, scales = scales }
    panel:setClipboardDisplay(string.format("%s @ %d", rigName, frame))
    print(string.format("[MultiAnimation] Copied %s keyframe @ %d", rigName, frame))
    return true
end

local function doPasteKeyframe(mirrored)
    if not kfClipboard then
        warn("[MultiAnimation] Clipboard empty — Copy KF first")
        return false
    end
    local rigName = activeRigName()
    if not rigName then
        warn("[MultiAnimation] No active rig to paste onto")
        return false
    end
    local frame = timeline:getCurrent()

    local joints, scales = {}, {}
    if mirrored then
        for jName, cf in pairs(kfClipboard.joints) do
            joints[MIRROR_JOINT[jName] or jName] = mirrorCF(cf)
        end
        for pName, size in pairs(kfClipboard.scales) do
            scales[MIRROR_PART[pName] or pName] = size
        end
    else
        for k, v in pairs(kfClipboard.joints) do joints[k] = v end
        for k, v in pairs(kfClipboard.scales) do scales[k] = v end
    end

    recorder:setJointData(rigName, frame, joints)
    if next(scales) then
        recorder:setScaleData(rigName, frame, scales)
    end
    panel:addKeyframeMarker(rigName, frame)
    applyPosesAt(frame, false)
    scheduleAutoSave()
    print(string.format("[MultiAnimation] Pasted %s%s @ %d onto %s",
        kfClipboard.rig, mirrored and " (mirrored)" or "", frame, rigName))
    return true
end

local function doCameraCapture()
    if camPreviewOn then
        warn("[MultiAnimation] Turn Cam Preview OFF before capturing — the viewport is showing the track, not a new shot")
        return
    end
    local frame = timeline:getCurrent()
    local snap  = CameraCapture.capture()
    local existing = recorder:getCameraData(frame)
    local mode = existing and existing.mode or "move"

    recorder:addCameraKeyframe(frame, snap.cf, snap.fov, mode)
    panel:addCameraKeyframeMarker(frame, mode)
    updateCameraGizmo(frame)
    panel:setCameraModeDisplay(mode)
    scheduleAutoSave()
    print(string.format("[MultiAnimation] Camera keyframe at frame %d (fov %.0f, %s)",
        frame, snap.fov, mode))
end

-- ── Playback ──────────────────────────────────────────────────────────────────

local function stopPlayback()
    if playConn then
        playConn:Disconnect()
        playConn = nil
    end
    isPlaying = false
    ChangeHistoryService:SetEnabled(true)
    ChangeHistoryService:SetWaypoint("MultiAnim_PreviewEnd")
    panel:setPlaybackState(false)
    -- Sync viewport to current timeline position after playback ends.
    applyPosesAt(timeline:getCurrent(), false)
end

local function startPlayback()
    if isPlaying then return end
    if next(allRigs) == nil then
        warn("[MultiAnimation] No rigs to preview")
        return
    end

    local frames = allKeyframesSorted()
    if #frames == 0 then
        warn("[MultiAnimation] No keyframes recorded yet")
        return
    end

    -- If already at the last frame, rewind to 1 so playback doesn't stop immediately.
    if timeline:getCurrent() >= timeline:getFrameCount() then
        local f = timeline:setCurrent(1)
        panel:setFrameDisplay(f, timeline:getFrameCount())
    end

    isPlaying = true
    panel:setPlaybackState(true)
    ChangeHistoryService:SetEnabled(false)

    local startTick  = tick()
    local startFrame = timeline:getCurrent()
    local fps        = timeline:getFps()
    local lastFrame  = timeline:getFrameCount()

    -- Effect events fire once when playback crosses their frame.
    local lastEventFrame = startFrame - 1

    playConn = RunService.Heartbeat:Connect(function()
        local elapsed  = tick() - startTick
        local rawFrame = startFrame + elapsed * fps
        local intFrame = math.min(math.floor(rawFrame), lastFrame)

        applyPosesAt(rawFrame, true)

        if intFrame > lastEventFrame then
            for name, inst in pairs(allEffects) do
                for _, f in ipairs(recorder:getSortedEffectFrames(name)) do
                    if f > lastEventFrame and f <= intFrame then
                        EffectRunner.fire(inst, recorder:getEffectEvent(name, f))
                    end
                end
            end
            lastEventFrame = intFrame
        end

        local clamped = timeline:setCurrent(intFrame)
        panel:setFrameDisplay(clamped, lastFrame)

        if intFrame >= lastFrame then
            stopPlayback()
        end
    end)
end

-- ── Scan helper ───────────────────────────────────────────────────────────────

local function scanAndSetup()
    allRigs = RigScanner.scan()
    for name, model in pairs(allRigs) do
        recorder:captureRestPose(name, model)
        disconnectRig(name, model)   -- disconnect AFTER capturing rest pose
    end
    panel:setRigs(allRigs)
    for rigName in pairs(allRigs) do
        for _, frame in ipairs(recorder:getSortedFrames(rigName)) do
            panel:addKeyframeMarker(rigName, frame)
        end
    end
    panel:setFrameDisplay(timeline:getCurrent(), timeline:getFrameCount())
end

-- ── SIMPLE MODE ───────────────────────────────────────────────────────────────
-- Auto-tracks everything directly under Workspace.FIGURES: R6 rigs use the
-- same joint/scale/root capture as Advanced; everything else is tracked by
-- world CFrame like an Advanced prop. Stepping forward captures the
-- departure frame only if it has no recorded data yet (idempotent — replays
-- existing keyframes instead of overwriting them); "Delete Keyframe" clears
-- the current frame and snaps back to the previous frame's pose so the user
-- can re-pose and step forward again to re-capture it.
--
-- The Camera View camera is a real, manipulable Part (SIMPLE_CAMERA_NAME) in
-- FIGURES — posed with Studio's move/rotate tools like any rig or prop —
-- rather than a capture of the ambient Studio viewport. It is excluded from
-- the generic prop auto-tracking below and instead driven through the same
-- recorder:addCameraKeyframe/Interpolator.getCameraData path Advanced mode's
-- camera track already uses, so the export pipeline is unaffected.

local function ensureSimpleCameraPart()
    local fig = workspace:FindFirstChild("FIGURES")
    if not fig then
        fig = Instance.new("Folder")
        fig.Name = "FIGURES"
        fig.Parent = workspace
    end

    local part = fig:FindFirstChild(SIMPLE_CAMERA_NAME)
    if not part then
        part = Instance.new("Part")
        part.Name        = SIMPLE_CAMERA_NAME
        part.Size         = Vector3.new(0.7, 0.7, 1.4)
        part.Anchored     = true
        part.CanCollide   = false
        part.CastShadow   = false
        part.Material     = Enum.Material.Neon
        part.Color        = Color3.fromRGB(80, 200, 255)
        part.CFrame       = workspace.CurrentCamera.CFrame
        part:SetAttribute("FOV", simpleCameraFOV)
        part.Parent = fig
        print("[MultiAnimation] Simple: created manipulable camera object 'SimpleCamera' in FIGURES")
    end
    simpleCameraPart = part
    drawSimpleCameraFrustum(part, simpleCameraFOV)
    return part
end

-- Collect all frame numbers that have any keyframe data in Simple Mode.
local function getSimpleKeyframedFrames()
    local set = {}
    for rigName in pairs(allRigs) do
        for _, f in ipairs(recorder:getSortedFrames(rigName)) do set[f] = true end
    end
    for propName in pairs(allProps) do
        for _, f in ipairs(recorder:getSortedPropFrames(propName)) do set[f] = true end
    end
    for _, f in ipairs(recorder:getSortedCameraFrames()) do set[f] = true end
    local sorted = {}
    for f in pairs(set) do table.insert(sorted, f) end
    table.sort(sorted)
    return sorted
end

local function doSimpleScan()
    reconnectAllRigs()
    allRigs = RigScanner.scan()
    for name, model in pairs(allRigs) do
        recorder:captureRestPose(name, model)
        disconnectRig(name, model)
    end

    for propName in pairs(allProps) do
        panel:removeProp(propName)
    end
    allProps = {}

    local fig = workspace:FindFirstChild("FIGURES")
    if fig then
        for _, child in ipairs(fig:GetChildren()) do
            if not allRigs[child.Name] and child.Name ~= SIMPLE_CAMERA_NAME then
                local part = getPropPart(child)
                if part then allProps[child.Name] = part end
            end
        end
        simpleCameraPart = fig:FindFirstChild(SIMPLE_CAMERA_NAME)
        if simpleCameraPart and not simpleCameraOn then
            simpleCameraPart.Transparency = 1
            local frustum = simpleCameraPart:FindFirstChild("FOVFrustum")
            if frustum then frustum:Destroy() end
        end
    else
        simpleCameraPart = nil
    end

    panel:setRigs(allRigs)
    for rigName in pairs(allRigs) do
        for _, f in ipairs(recorder:getSortedFrames(rigName)) do
            panel:addKeyframeMarker(rigName, f)
        end
    end
    for propName, part in pairs(allProps) do
        panel:addProp(propName, part)
        for _, f in ipairs(recorder:getSortedPropFrames(propName)) do
            panel:addPropKeyframeMarker(propName, f)
        end
    end
    -- If this is a fresh session (no existing keyframes anywhere), start the
    -- Simple Mode timeline at 1 frame so the user builds it up via Add Frame.
    local hasAnyData = false
    for rigName in pairs(allRigs) do
        if #recorder:getSortedFrames(rigName) > 0 then hasAnyData = true; break end
    end
    if not hasAnyData then
        for propName in pairs(allProps) do
            if #recorder:getSortedPropFrames(propName) > 0 then hasAnyData = true; break end
        end
    end
    if not hasAnyData and #recorder:getSortedCameraFrames() > 0 then hasAnyData = true end
    if not hasAnyData then
        timeline:setFrameCount(1)
        recorder:setFrameCount(1)
        panel:setFrameCount(1)
        timeline:setFps(30)
        recorder:setFps(30)
    else
        -- Derive frame count from actual keyframe span so a large Advanced-Mode
        -- session frameCount doesn't carry into Simple Mode's sequential model.
        local maxKF = 0
        for rigName in pairs(allRigs) do
            for _, f in ipairs(recorder:getSortedFrames(rigName)) do
                if f > maxKF then maxKF = f end
            end
        end
        for propName in pairs(allProps) do
            for _, f in ipairs(recorder:getSortedPropFrames(propName)) do
                if f > maxKF then maxKF = f end
            end
        end
        for _, f in ipairs(recorder:getSortedCameraFrames()) do
            if f > maxKF then maxKF = f end
        end
        local needed = maxKF + 1
        timeline:setFrameCount(needed)
        recorder:setFrameCount(needed)
        panel:setFrameCount(needed)
    end
    panel:setFrameDisplay(timeline:getCurrent(), timeline:getFrameCount())

    local rigCount, propCount = 0, 0
    for _ in pairs(allRigs) do rigCount += 1 end
    for _ in pairs(allProps) do propCount += 1 end
    print(string.format("[MultiAnimation] Simple mode scan: %d rig(s), %d prop(s)", rigCount, propCount))
    panel:setSimpleSlots(getSimpleKeyframedFrames())
    panel:setSimpleFPSDisplay(timeline:getFps())
end

local function simpleFrameHasData(frame)
    for rigName in pairs(allRigs) do
        if recorder:hasKeyframe(rigName, frame) then return true end
    end
    for propName in pairs(allProps) do
        if recorder:getPropData(propName, frame) ~= nil then return true end
    end
    if recorder:getCameraData(frame) ~= nil then return true end
    return false
end

local function doSimpleCaptureFrame(frame)
    if next(allRigs) ~= nil or next(allProps) ~= nil then
        recorder:addKeyframe(frame, allRigs, allProps)
        for rigName in pairs(allRigs) do panel:addKeyframeMarker(rigName, frame) end
        for propName in pairs(allProps) do panel:addPropKeyframeMarker(propName, frame) end
    end
    -- Camera is captured whenever the part exists, not gated by Camera View
    -- toggle, so the pose is always recorded along with rigs/props.
    if simpleCameraPart and simpleCameraPart.Parent then
        recorder:addCameraKeyframe(frame, simpleCameraPart.CFrame, simpleCameraFOV, "move")
        panel:addCameraKeyframeMarker(frame, "move")
        -- No updateCameraGizmo here: the SimpleCamera Part in FIGURES is the
        -- visual for Simple Mode. Advanced-mode orange markers would pile up at
        -- every past keyframe position and clutter the viewport.
    end
    scheduleAutoSave()
end

-- Rebuild all timeline markers from recorder state (used after insert/delete
-- frame operations that shift data across multiple frame numbers at once).
local function rebuildAllSimpleMarkers()
    panel:setRigs(allRigs)
    for rigName in pairs(allRigs) do
        for _, f in ipairs(recorder:getSortedFrames(rigName)) do
            panel:addKeyframeMarker(rigName, f)
        end
    end
    for propName in pairs(allProps) do
        for _, f in ipairs(recorder:getSortedPropFrames(propName)) do
            panel:addPropKeyframeMarker(propName, f)
        end
    end
    -- Camera gizmos are Advanced Mode only; skip rebuild in Simple Mode.
    panel:setSimpleSlots(getSimpleKeyframedFrames())
end

-- Capture current frame (always, overwriting any existing data), extend the
-- timeline by one frame, and advance the cursor to that new last frame.
local function doSimpleAddFrame()
    if isPlaying then return end
    local frame = timeline:getCurrent()
    local frameCount = timeline:getFrameCount()
    doSimpleCaptureFrame(frame)
    if frame >= frameCount then
        -- Cursor is at the blank end slot — grow timeline and advance.
        local newCount = frameCount + 1
        timeline:setFrameCount(newCount)
        recorder:setFrameCount(newCount)
        panel:setFrameCount(newCount)
        panel:setSimpleSlots(getSimpleKeyframedFrames())
        local f = timeline:setCurrent(newCount)
        panel:setFrameDisplay(f, newCount)
        applyPosesAt(f, false)
    else
        -- Cursor is at an existing frame — update its data, advance one step.
        panel:setSimpleSlots(getSimpleKeyframedFrames())
        local f = timeline:setCurrent(frame + 1)
        panel:setFrameDisplay(f, frameCount)
        applyPosesAt(f, false)
    end
end

-- Insert a blank frame at the current position: shift all data at frames
-- >= current+1 right by 1, grow the timeline by 1, stay at current frame
-- (now empty, ready to pose).
local function doSimpleInsertFrame()
    if isPlaying then return end
    local frame = timeline:setCurrent(timeline:getCurrent())  -- clamp
    recorder:shiftFrames(frame + 1, 1)
    local newCount = timeline:getFrameCount() + 1
    timeline:setFrameCount(newCount)
    recorder:setFrameCount(newCount)
    panel:setFrameCount(newCount)
    rebuildAllSimpleMarkers()
    panel:setFrameDisplay(frame, newCount)
    applyPosesAt(frame, false)
end

-- Delete the current frame: remove its data, shift all data at frames after
-- it left by 1, shrink the timeline by 1.
local function doSimpleDeleteFrame()
    if isPlaying then return end
    local frame = timeline:getCurrent()
    local oldCount = timeline:getFrameCount()
    if oldCount <= 1 then return end   -- keep at least one frame
    recorder:deleteFrameAt(frame)
    recorder:shiftFrames(frame + 1, -1)
    local newCount = oldCount - 1
    timeline:setFrameCount(newCount)
    recorder:setFrameCount(newCount)
    panel:setFrameCount(newCount)
    local f = timeline:setCurrent(math.min(frame, newCount))
    rebuildAllSimpleMarkers()
    panel:setFrameDisplay(f, newCount)
    applyPosesAt(f, false)
    scheduleAutoSave()
end

-- Shared by the panel toggle and the TestBridge command so both paths get
-- identical gizmo-creation / Look-Through-teardown behaviour.
local function setSimpleCameraOn(isOn)
    simpleCameraOn = isOn
    if isOn then
        ensureSimpleCameraPart()
        if simpleCameraPart then
            simpleCameraPart.Transparency = 0
        end
    else
        if simpleLookThroughOn then
            setSimpleLookThroughOn(false)
            panel:setSimpleLookThroughState(false)
        end
        if simpleCameraPart then
            simpleCameraPart.Transparency = 1
            local frustum = simpleCameraPart:FindFirstChild("FOVFrustum")
            if frustum then frustum:Destroy() end
        end
    end
end

-- Snaps the viewport into the gizmo's lens once, then mirrors the OTHER way
-- for as long as Look Through stays on: Studio's native edit-camera controls
-- (right-drag look, WASD/QE fly, scroll zoom) keep driving
-- workspace.CurrentCamera as normal, and every Heartbeat that live CFrame is
-- copied back onto simpleCameraPart — so flying around re-aims the gizmo
-- instead of fighting it. FOV still flows gizmo → viewport one-way, since
-- the FOV box is its single source of truth. Restores the original viewport
-- exactly on toggle-off, like Advanced mode's Cam Preview (CameraCapture.lua).
function setSimpleLookThroughOn(isOn)
    if isOn then
        if not simpleCameraOn or not (simpleCameraPart and simpleCameraPart.Parent) then
            warn("[MultiAnimation] Turn Camera View ON first — nothing to look through")
            return false
        end
        if simpleLookThroughOn then return true end
        simpleLookThroughOn = true
        savedSimpleCamState = CameraCapture.saveState()
        -- Snap viewport camera to the SimpleCamera Part's position.
        -- We intentionally do NOT set CameraType = Scriptable so Studio's
        -- built-in editor controls (right-click-drag, WASD) remain active.
        -- The Heartbeat copies Camera → Part, so wherever the user flies
        -- the camera, the part tracks it.
        CameraCapture.apply(simpleCameraPart.CFrame, simpleCameraFOV)
        simpleLookThroughConn = RunService.Heartbeat:Connect(function()
            if simpleCameraPart and simpleCameraPart.Parent then
                simpleCameraPart.CFrame = workspace.CurrentCamera.CFrame
                workspace.CurrentCamera.FieldOfView = simpleCameraFOV
                simpleCameraPart:SetAttribute("FOV", simpleCameraFOV)
            end
        end)
    else
        if not simpleLookThroughOn then return false end
        simpleLookThroughOn = false
        if simpleLookThroughConn then
            simpleLookThroughConn:Disconnect()
            simpleLookThroughConn = nil
        end
        if savedSimpleCamState then
            CameraCapture.restoreState(savedSimpleCamState)
            savedSimpleCamState = nil
        end
    end
    return simpleLookThroughOn
end

-- ── Onion-skin ghost rendering ────────────────────────────────────────────────

local ONION_FOLDER = "__MultiAnimOnionSkin"
-- Two ghost colours: previous frame = warm red, next frame = cool blue.
local ONION_PREV_COLOR = Color3.fromRGB(255, 80, 80)
local ONION_NEXT_COLOR = Color3.fromRGB(80, 80, 255)
local ONION_TRANSPARENCY = 0.65

local function clearOnionSkin()
    local folder = workspace:FindFirstChild(ONION_FOLDER)
    if folder then folder:Destroy() end
end

local function updateOnionSkin()
    clearOnionSkin()
    if not simpleOnionOn then return end

    local frame = timeline:getCurrent()
    -- Find the nearest keyframed frame before and after current.
    local kfFrames = getSimpleKeyframedFrames()
    local prevFrame, nextFrame
    for _, f in ipairs(kfFrames) do
        if f < frame then prevFrame = f end
        if f > frame and not nextFrame then nextFrame = f; break end
    end
    if not prevFrame and not nextFrame then return end

    local folder = Instance.new("Folder")
    folder.Name        = ONION_FOLDER
    folder.Archivable  = false
    folder.Parent      = workspace

    for _, spec in ipairs({
        { prevFrame, ONION_PREV_COLOR },
        { nextFrame, ONION_NEXT_COLOR },
    }) do
        local adjFrame, color = spec[1], spec[2]
        if not adjFrame then continue end
        for rigName, rigModel in pairs(allRigs) do
            local jd = recorder:getJointData(rigName, adjFrame)
            if not jd then continue end
            local worldCFs = JointCapture.computeWorldCFrames(rigModel, jd)
            for partName, cf in pairs(worldCFs) do
                local orig = rigModel:FindFirstChild(partName)
                if not orig or not orig:IsA("BasePart") then continue end
                local ghost = Instance.new("Part")
                ghost.Name             = rigName .. "_" .. partName
                ghost.Size             = orig.Size
                ghost.CFrame           = cf
                ghost.Color            = color
                ghost.Transparency     = ONION_TRANSPARENCY
                ghost.CanCollide       = false
                ghost.Anchored         = true
                ghost.CastShadow       = false
                ghost.Archivable       = false
                ghost.Parent           = folder
            end
        end
    end
end

local function setSimpleOnionOn(isOn)
    simpleOnionOn = isOn
    panel:setSimpleOnionState(isOn)
    if isOn then updateOnionSkin() else clearOnionSkin() end
end

-- ── Panel event wiring ────────────────────────────────────────────────────────

panel.onRefreshRequested:Connect(function()
    -- Reconnect before re-scan so captureRestPose reads clean rest positions,
    -- then disconnect again for free-pose mode.
    reconnectAllRigs()
    scanAndSetup()
end)

-- Shared add-keyframe logic used by both the button and the K shortcut.
local function doAddKeyframe()
    if isPlaying then return end
    local frame       = timeline:getCurrent()
    local activeRigs  = panel:getActiveRigs()
    local activeProps = panel:getActiveProps()
    if next(activeRigs) == nil and next(activeProps) == nil then
        warn("[MultiAnimation] No active rigs or props selected")
        return
    end
    -- Validate Motor6Ds for each active rig before capturing.
    for rigName, model in pairs(activeRigs) do
        local missing = JointCapture.validate(model)
        if #missing > 0 then
            warn(string.format("[MultiAnimation] Rig '%s' has broken joints — cannot capture: %s",
                rigName, table.concat(missing, ", ")))
            return
        end
    end
    recorder:addKeyframe(frame, activeRigs, activeProps)
    local names = {}
    for rigName in pairs(activeRigs) do
        panel:addKeyframeMarker(rigName, frame)
        table.insert(names, rigName)
    end
    for propName in pairs(activeProps) do
        panel:addPropKeyframeMarker(propName, frame)
        table.insert(names, propName)
    end
    table.sort(names)
    print(string.format("[MultiAnimation] Keyframe at frame %d for: %s",
        frame, table.concat(names, ", ")))
    scheduleAutoSave()
end

panel.onAddKeyframeRequested:Connect(doAddKeyframe)

-- Step-frame: mirrors the onScrubBegan auto-update so moving the timeline via
-- shortcut also saves any pose changes made while parked at a keyframe.
local function doStepFrame(direction)
    if isPlaying then return end

    -- Auto-update existing keyframe at the departure frame (same logic as onScrubBegan)
    local departureFrame = timeline:getCurrent()
    local activeRigs  = panel:getActiveRigs()
    local activeProps = panel:getActiveProps()
    local shouldUpdate = false
    for rigName in pairs(activeRigs) do
        if recorder:hasKeyframe(rigName, departureFrame) then shouldUpdate = true; break end
    end
    if not shouldUpdate then
        for propName in pairs(activeProps) do
            if recorder:getPropData(propName, departureFrame) ~= nil then shouldUpdate = true; break end
        end
    end
    if shouldUpdate then
        recorder:addKeyframe(departureFrame, activeRigs, activeProps)
        scheduleAutoSave()
    end

    -- Step to new frame
    local step     = panel:getStepSize()
    local newFrame = math.clamp(departureFrame + direction * step, 1, timeline:getFrameCount())
    local f = timeline:setCurrent(newFrame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
end

-- Keyboard shortcuts (fire when viewport is focused; ignored when a TextBox has focus).
track(game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if      input.KeyCode == Enum.KeyCode.K  then doAddKeyframe()
    elseif  input.KeyCode == Enum.KeyCode.L  then doStepFrame( 1)   -- L = step forward
    elseif  input.KeyCode == Enum.KeyCode.J  then doStepFrame(-1)   -- J = step back
    elseif  input.KeyCode == Enum.KeyCode.C  then doCameraCapture() -- C = camera keyframe
    end
end))

-- ── Add Rig / keyframe clipboard handlers ─────────────────────────────────────

panel.onAddRigRequested:Connect(function()
    doAddRig()
end)

-- ── Simple Mode handlers ──────────────────────────────────────────────────────

-- ── Playback tab helpers ──────────────────────────────────────────────────────

local buildPlaybackSnippet  -- forward declaration; defined just after doPlaybackScan

-- Refresh the playbackScenes list from saved sessions and push to panel.
local function doPlaybackScan()
    local idx = getIndex()
    playbackScenes = {}
    for _, entry in ipairs(idx) do
        table.insert(playbackScenes, entry.name)
    end
    table.sort(playbackScenes)
    -- Select first scene if current selection no longer exists or none yet
    if #playbackScenes == 0 then
        playbackScene    = nil
        playbackSceneIdx = 0
        panel:setPlaybackSceneDisplay("—")
        panel:rebuildPlaybackRigRows({}, {})
        panel:setPlaybackSnippet("-- no saved scenes --")
        return
    end
    if not playbackScene then
        playbackSceneIdx = 1
        playbackScene    = playbackScenes[1]
    else
        playbackSceneIdx = 1
        for i, n in ipairs(playbackScenes) do
            if n == playbackScene then playbackSceneIdx = i; break end
        end
    end
    panel:setPlaybackSceneDisplay(playbackScene)
    -- Rebuild rig rows: use the exported scene's rig names if we can find them
    -- from the session index (names not available without loading the scene,
    -- so start with an empty row set — rows get rebuilt when scene is loaded).
    panel:rebuildPlaybackRigRows({}, playbackRigModes)
    buildPlaybackSnippet()
end

-- Build the Lua snippet string and push to the panel's TextBox.
buildPlaybackSnippet = function()
    if not playbackScene then
        panel:setPlaybackSnippet("-- no scene selected --")
        return
    end
    local rigLines = {}
    for rigName, modeKey in pairs(playbackRigModes) do
        local line
        if modeKey == "fixed" then
            line = string.format('        %s = workspace.FIGURES.%s,', rigName, rigName)
        elseif modeKey == "localClone" then
            line = string.format('        %s = { player = game.Players.LocalPlayer, mode = "clone" },', rigName)
        elseif modeKey == "localDirect" then
            line = string.format('        %s = { player = game.Players.LocalPlayer, mode = "direct" },', rigName)
        elseif modeKey == "userIdClone" then
            line = string.format('        -- Replace 0 with the target player\'s UserId\n        %s = { userId = 0, mode = "clone" },', rigName)
        elseif modeKey == "userIdDirect" then
            line = string.format('        -- Replace 0 with the target player\'s UserId\n        %s = { userId = 0, mode = "direct" },', rigName)
        else
            line = string.format('        %s = workspace.FIGURES.%s,', rigName, rigName)
        end
        table.insert(rigLines, line)
    end
    local rigBlock = #rigLines > 0
        and table.concat(rigLines, "\n")
        or '        -- no rigs — add rig slots here'
    local snippet = string.format(
        'local CutscenePlayer = require(game.ReplicatedStorage.CutscenePlayer)\n' ..
        'local handle = CutscenePlayer.play(\n' ..
        '    "%s",\n' ..
        '    {\n' ..
        '%s\n' ..
        '    },\n' ..
        '    { fps = %d, loop = %s, movieMode = %s }\n' ..
        ')',
        playbackScene,
        rigBlock,
        playbackFPS,
        tostring(playbackLoop),
        tostring(playbackMovieMode)
    )
    panel:setPlaybackSnippet(snippet)
end

panel.onModeChanged:Connect(function(newMode)
    if newMode == "simple" then
        advancedFrameCount = timeline:getFrameCount()
        mode = newMode
        clearCameraGizmos()
        doSimpleScan()
    elseif newMode == "playback" then
        if not advancedFrameCount then
            advancedFrameCount = timeline:getFrameCount()
        end
        mode = newMode
        doPlaybackScan()
    else
        mode = newMode
        if advancedFrameCount then
            timeline:setFrameCount(advancedFrameCount)
            recorder:setFrameCount(advancedFrameCount)
            panel:setFrameCount(advancedFrameCount)
            advancedFrameCount = nil
        end
        -- Leaving simple mode: shut down onion skin.
        if simpleOnionOn then setSimpleOnionOn(false) end
        clearOnionSkin()
        rebuildCameraUI()
    end
end)

panel.onSimpleAddFrame:Connect(doSimpleAddFrame)
panel.onSimpleInsertFrame:Connect(doSimpleInsertFrame)
panel.onSimpleDeleteFrame:Connect(doSimpleDeleteFrame)
panel.onSimpleCameraToggled:Connect(setSimpleCameraOn)
panel.onSimpleLookThroughToggled:Connect(function(isOn)
    local result = setSimpleLookThroughOn(isOn)
    panel:setSimpleLookThroughState(result)
end)
panel.onSimpleOnionToggled:Connect(setSimpleOnionOn)
panel.onSimpleFOVChanged:Connect(function(fov)
    simpleCameraFOV = fov
    if simpleCameraPart then
        simpleCameraPart:SetAttribute("FOV", fov)
        if simpleCameraOn then
            drawSimpleCameraFrustum(simpleCameraPart, fov)
        end
    end
end)
panel.onSimpleFPSChanged:Connect(function(fps)
    timeline:setFps(fps)
    recorder:setFps(fps)
end)

-- ── Playback tab event handlers ───────────────────────────────────────────────

panel.onPlaybackSceneChanged:Connect(function(name)
    if name == "__prev__" then
        if #playbackScenes == 0 then return end
        playbackSceneIdx = ((playbackSceneIdx - 2) % #playbackScenes) + 1
        playbackScene    = playbackScenes[playbackSceneIdx]
        panel:setPlaybackSceneDisplay(playbackScene)
        panel:rebuildPlaybackRigRows({}, playbackRigModes)
        buildPlaybackSnippet()
    elseif name == "__next__" then
        if #playbackScenes == 0 then return end
        playbackSceneIdx = (playbackSceneIdx % #playbackScenes) + 1
        playbackScene    = playbackScenes[playbackSceneIdx]
        panel:setPlaybackSceneDisplay(playbackScene)
        panel:rebuildPlaybackRigRows({}, playbackRigModes)
        buildPlaybackSnippet()
    else
        playbackScene = name
        for i, n in ipairs(playbackScenes) do
            if n == name then playbackSceneIdx = i; break end
        end
        panel:setPlaybackSceneDisplay(playbackScene)
        panel:rebuildPlaybackRigRows({}, playbackRigModes)
        buildPlaybackSnippet()
    end
end)

panel.onPlaybackRigChanged:Connect(function(rigName, modeKey)
    playbackRigModes[rigName] = modeKey
    buildPlaybackSnippet()
end)

panel.onPlaybackParamsChanged:Connect(function(params)
    if params.fps        ~= nil then playbackFPS       = math.clamp(math.floor(params.fps), 1, 999) end
    if params.loop       ~= nil then playbackLoop      = params.loop end
    if params.movieMode  ~= nil then playbackMovieMode = params.movieMode end
    buildPlaybackSnippet()
end)

panel.onPlaybackCopySnippet:Connect(function(text)
    -- Studio doesn't expose a clipboard API in plugin context.
    -- We set the snippet box text (already set) and print to output as fallback.
    print("[MultiAnimation] Snippet copied to Output — paste it into your LocalScript:\n" .. tostring(text))
end)

panel.onPlaybackPreview:Connect(function()
    -- Preview: execute snippet in Client context via execute_luau is not possible
    -- from plugin. Best UX: print a reminder and let the user run it manually.
    print("[MultiAnimation] To preview, paste the snippet (see Output) into a LocalScript and run in Play mode.")
    buildPlaybackSnippet()
end)

panel.onCopyKeyframeRequested:Connect(doCopyKeyframe)

panel.onPasteKeyframeRequested:Connect(function(mirrored)
    doPasteKeyframe(mirrored)
end)

-- ── Effect track handlers ─────────────────────────────────────────────────────

local function trackEffectInstance(effect)
    local name = effect.Name
    if allRigs[name] or allProps[name] or allEffects[name] then
        warn("[MultiAnimation] Name '" .. name .. "' already in use — rename the effect instance")
        return nil
    end
    local kind = EffectRunner.classify(effect)
    if not kind then return nil end

    allEffects[name] = effect
    -- registerEffect keeps existing data, so re-tracking after × restores events.
    local fx = recorder:registerEffect(name, kind, EffectRunner.defaultAction(kind), effect:GetFullName())
    panel:addEffect(name, fx.action)
    for _, f in ipairs(recorder:getSortedEffectFrames(name)) do
        panel:addEffectMarker(name, f)
    end
    print(string.format("[MultiAnimation] Tracking effect '%s' (%s, default: %s)", name, kind, fx.action))
    return name
end

panel.onTrackEffectRequested:Connect(function()
    local effect = nil
    for _, inst in ipairs(Selection:Get()) do
        effect = EffectRunner.findEffect(inst)
        if effect then break end
    end
    if not effect then
        warn("[MultiAnimation] Select an effect (ParticleEmitter, Sound, light, Beam, Trail) or a part containing one")
        return
    end
    trackEffectInstance(effect)
end)

panel.onEffectActionCycleRequested:Connect(function(name)
    local fx = recorder:getEffect(name)
    if not fx then return end
    local nextAction = EffectRunner.cycleAction(fx.kind, fx.action)
    recorder:setEffectAction(name, nextAction)
    panel:setEffectAction(name, nextAction)
    scheduleAutoSave()
end)

panel.onEffectDoubleClicked:Connect(function(name, frame)
    local fx = recorder:getEffect(name)
    if not fx then return end
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)

    local event = { action = fx.action }
    if fx.action == "emit" then
        event.count = EffectRunner.DEFAULT_EMIT_COUNT
    end
    recorder:setEffectEvent(name, f, event)
    panel:addEffectMarker(name, f)
    scheduleAutoSave()
    print(string.format("[MultiAnimation] Effect event '%s' (%s) at frame %d", name, fx.action, f))
end)

panel.onEffectMarkerClicked:Connect(function(_name, frame)
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
end)

panel.onEffectMarkerDeleteRequested:Connect(function(name, frame)
    recorder:deleteEffectEvent(name, frame)
    panel:removeEffectMarker(name, frame)
    scheduleAutoSave()
end)

panel.onEffectRemoved:Connect(function(name)
    allEffects[name] = nil   -- recorded events stay in the session (like props)
end)

-- ── Camera track handlers ─────────────────────────────────────────────────────

panel.onCameraCaptureRequested:Connect(doCameraCapture)

panel.onCameraPreviewToggled:Connect(function(isOn)
    camPreviewOn = isOn
    if isOn then
        savedCamState = CameraCapture.saveState()
        applyPosesAt(timeline:getCurrent(), false)   -- snap viewport onto the track
    else
        CameraCapture.restoreState(savedCamState)
        savedCamState = nil
    end
end)

panel.onCameraModeToggleRequested:Connect(function()
    local frame = timeline:getCurrent()
    local kf = recorder:getCameraData(frame)
    if not kf then return end
    local newMode = (kf.mode == "cut") and "move" or "cut"
    recorder:setCameraMode(frame, newMode)
    panel:setCameraMarkerMode(frame, newMode)
    panel:setCameraModeDisplay(newMode)
    updateCameraGizmo(frame)
    scheduleAutoSave()
end)

panel.onCameraMarkerClicked:Connect(function(frame)
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
end)

panel.onCameraMarkerDeleteRequested:Connect(function(frame)
    recorder:deleteCameraKeyframe(frame)
    panel:removeCameraKeyframeMarker(frame)
    updateCameraGizmo(frame)   -- keyframe gone → gizmo removed
    panel:setCameraModeDisplay(nil)
    scheduleAutoSave()
end)

panel.onCameraLaneDoubleClicked:Connect(function(frame)
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
    doCameraCapture()
end)

local simpleScrubbing = false  -- true while Simple Mode scrubber is being dragged

panel.onFrameChanged:Connect(function(newFrame)
    -- Simple Mode: auto-capture the departure frame when navigating via icons or
    -- nav buttons (scrubber drag is handled by onScrubBegan instead).
    if mode == "simple" and not isPlaying and not simpleScrubbing then
        local departureFrame = timeline:getCurrent()
        if departureFrame ~= newFrame and simpleFrameHasData(departureFrame) then
            doSimpleCaptureFrame(departureFrame)
            scheduleAutoSave()
        end
    end
    local f = timeline:setCurrent(newFrame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
    if simpleOnionOn and mode == "simple" then updateOnionSkin() end
end)

panel.onScrubBegan:Connect(function()
    if not isPlaying then
        local frame = timeline:getCurrent()
        if mode == "simple" then
            -- Simple Mode: auto-capture the departure frame so pose changes
            -- made while parked at a frame are not lost on scrub.
            simpleScrubbing = true
            if simpleFrameHasData(frame) then
                doSimpleCaptureFrame(frame)
                scheduleAutoSave()
            end
        else
            -- Advanced Mode: re-capture if there's an existing keyframe here.
            local activeRigs  = panel:getActiveRigs()
            local activeProps = panel:getActiveProps()
            local shouldUpdate = false
            for rigName in pairs(activeRigs) do
                if recorder:hasKeyframe(rigName, frame) then shouldUpdate = true; break end
            end
            if not shouldUpdate then
                for propName in pairs(activeProps) do
                    if recorder:getPropData(propName, frame) ~= nil then shouldUpdate = true; break end
                end
            end
            if shouldUpdate then
                recorder:addKeyframe(frame, activeRigs, activeProps)
                scheduleAutoSave()
            end
        end
    end
    ChangeHistoryService:SetEnabled(false)
end)
panel.onScrubEnded:Connect(function()
    simpleScrubbing = false
    ChangeHistoryService:SetEnabled(true)
    ChangeHistoryService:SetWaypoint("MultiAnim_Scrub")
end)

panel.onMarkerClicked:Connect(function(rigName, frame)
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
    print(string.format("[MultiAnimation] Jumped to frame %d", f))
end)

panel.onRewindRequested:Connect(function()
    local f = timeline:setCurrent(1)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
end)
panel.onFastForwardRequested:Connect(function()
    local f = timeline:setCurrent(timeline:getFrameCount())
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
end)

panel.onPrevKeyframeRequested:Connect(function()
    local frames = allKeyframesSorted()
    local f = timeline:prevKeyframe(frames)
    if f then
        timeline:setCurrent(f)
        panel:setFrameDisplay(f, timeline:getFrameCount())
        applyPosesAt(f, false)
    end
end)
panel.onNextKeyframeRequested:Connect(function()
    local frames = allKeyframesSorted()
    local f = timeline:nextKeyframe(frames)
    if f then
        timeline:setCurrent(f)
        panel:setFrameDisplay(f, timeline:getFrameCount())
        applyPosesAt(f, false)
    end
end)

panel.onTimelineDoubleClicked:Connect(function(rigName, frame)
    local model = allRigs[rigName]
    if not model then return end
    local missing = JointCapture.validate(model)
    if #missing > 0 then
        warn(string.format("[MultiAnimation] Rig '%s' broken — cannot capture: %s",
            rigName, table.concat(missing, ", ")))
        return
    end
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
    recorder:addKeyframe(f, { [rigName] = model }, {})
    panel:addKeyframeMarker(rigName, f)
    scheduleAutoSave()
    print(string.format("[MultiAnimation] Keyframe added at frame %d for %s", f, rigName))
end)

panel.onMarkerDeleteRequested:Connect(function(rigName, frame)
    recorder:deleteRigKeyframe(rigName, frame)
    panel:removeKeyframeMarker(rigName, frame)
    print(string.format("[MultiAnimation] Deleted keyframe at frame %d for %s", frame, rigName))
end)

-- ── Prop event handlers ───────────────────────────────────────────────────────

panel.onTrackPartRequested:Connect(function()
    if isPlaying then return end
    local sel = Selection:Get()
    local part = nil
    for _, inst in ipairs(sel) do
        if inst:IsA("BasePart") then part = inst; break end
    end
    if not part then
        warn("[MultiAnimation] Track Part: select a BasePart in the viewport first")
        return
    end
    local propName = part.Name
    if allRigs[propName] or allProps[propName] then
        warn(string.format(
            "[MultiAnimation] Track Part: name '%s' already in use — rename the part first",
            propName))
        return
    end
    allProps[propName] = part
    panel:addProp(propName, part)
    -- Restore any markers from recorder (e.g. from a loaded session)
    for _, frame in ipairs(recorder:getSortedPropFrames(propName)) do
        panel:addPropKeyframeMarker(propName, frame)
    end
    print("[MultiAnimation] Tracking prop: " .. propName)
end)

panel.onPropRemoved:Connect(function(propName)
    allProps[propName] = nil
    recorder:deleteProp(propName)
    print("[MultiAnimation] Removed prop: " .. propName)
end)

panel.onPropDoubleClicked:Connect(function(propName, frame)
    local part = allProps[propName]
    if not part then return end
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
    recorder:addKeyframe(f, {}, { [propName] = part })
    panel:addPropKeyframeMarker(propName, f)
    scheduleAutoSave()
    print(string.format("[MultiAnimation] Prop keyframe added at frame %d for %s", f, propName))
end)

panel.onPropMarkerDeleteRequested:Connect(function(propName, frame)
    recorder:deletePropKeyframe(propName, frame)
    panel:removePropKeyframeMarker(propName, frame)
    print(string.format("[MultiAnimation] Deleted prop keyframe at frame %d for %s", frame, propName))
end)

panel.onNewSessionConfirmed:Connect(function()
    -- Reconnect before re-scan so rest poses are captured from a clean rig.
    reconnectAllRigs()
    -- Clear prop UI
    for propName in pairs(allProps) do
        panel:removeProp(propName)
    end
    allProps = {}
    -- Clear camera UI (markers + gizmos) before the data goes away.
    for _, f in ipairs(recorder:getSortedCameraFrames()) do
        panel:removeCameraKeyframeMarker(f)
    end
    clearCameraGizmos()
    panel:setCameraModeDisplay(nil)
    -- Clear effect UI
    for name in pairs(recorder:getSession().effects or {}) do
        panel:removeEffect(name)
    end
    allEffects = {}
    recorder:clearSession()
    timeline:setCurrent(1)
    scanAndSetup()
    panel:setFrameDisplay(1, timeline:getFrameCount())
    print("[MultiAnimation] New session started")
end)

panel.onSaveConfirmed:Connect(function(name)
    saveNamed(name)
end)
panel.onLoadRequested:Connect(function()
    panel:showLoadList(getIndex())
end)
panel.onLoadNamedRequested:Connect(function(name)
    loadNamed(name)
    panel:hideLoadList()
end)
panel.onPreviewRequested:Connect(startPlayback)
panel.onStopRequested:Connect(stopPlayback)

panel.onExportRequested:Connect(function(sceneName)
    local ok, result = Exporter.export(recorder:getSession(), sceneName)
    if not ok then
        warn(string.format("[MultiAnimation] Export failed: %s", result))
    end
end)

-- ── Viewport selection → rig selector sync ───────────────────────────────────

local function findRigForInstance(instance)
    local current = instance
    while current and current ~= game do
        for name, model in pairs(allRigs) do
            if current == model then return name end
        end
        current = current.Parent
    end
    return nil
end

track(Selection.SelectionChanged:Connect(function()
    if isPlaying then return end
    local selected = Selection:Get()

    -- Clicking a camera gizmo jumps the timeline to its keyframe.
    for _, inst in ipairs(selected) do
        local frameStr = inst.Name:match("^CamKF_(%d+)$")
        if frameStr and inst.Parent and inst.Parent.Name == CAM_GIZMO_FOLDER then
            local f = timeline:setCurrent(tonumber(frameStr))
            panel:setFrameDisplay(f, timeline:getFrameCount())
            applyPosesAt(f, false)
            return
        end
    end

    local foundRigs = {}
    for _, inst in ipairs(selected) do
        local rigName = findRigForInstance(inst)
        if rigName then foundRigs[rigName] = true end
    end
    if next(foundRigs) then
        panel:setActiveRigs(foundRigs)
    end
end))

-- ── Clean up on unload ────────────────────────────────────────────────────────
-- Reconnect all Motor6D joints so the rig is in a clean state when the plugin
-- is disabled or Studio is closed.

track(plugin.Unloading:Connect(function()
    stopPlayback()
    reconnectAllRigs()
    if camPreviewOn then
        CameraCapture.restoreState(savedCamState)
    end
    if simpleLookThroughOn then
        setSimpleLookThroughOn(false)
    end
    if simpleOnionOn then
        setSimpleOnionOn(false)
    end
    clearCameraGizmos()
    clearOnionSkin()
    -- testBridge is declared below; guard for the unload-before-init edge.
    local bridge = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
    if bridge then bridge:Destroy() end
end))

-- ── FIGURES auto-detect (ChildAdded / ChildRemoved) ──────────────────────────

local function rebuildRigUI()
    panel:setRigs(allRigs)
    for rigName in pairs(allRigs) do
        for _, f in ipairs(recorder:getSortedFrames(rigName)) do
            panel:addKeyframeMarker(rigName, f)
        end
    end
    panel:setFrameDisplay(timeline:getCurrent(), timeline:getFrameCount())
end

local figuresFolder = workspace:FindFirstChild("FIGURES")
if figuresFolder then
    track(figuresFolder.ChildAdded:Connect(function(child)
        -- Defer one frame so the model is fully parented/loaded.
        task.defer(function()
            if not child or not child.Parent then return end
            if allRigs[child.Name] or allProps[child.Name] or child.Name == SIMPLE_CAMERA_NAME then return end   -- already tracked
            -- Let RigScanner decide if it's a valid R6 rig.
            local fresh = RigScanner.scan()
            if fresh[child.Name] then
                allRigs[child.Name] = child
                recorder:captureRestPose(child.Name, child)
                disconnectRig(child.Name, child)
                rebuildRigUI()
                print("[MultiAnimation] Auto-detected rig: " .. child.Name)
            elseif mode == "simple" then
                local part = getPropPart(child)
                if part then
                    allProps[child.Name] = part
                    panel:addProp(child.Name, part)
                    print("[MultiAnimation] Simple: auto-tracking prop " .. child.Name)
                end
            end
        end)
    end))

    track(figuresFolder.ChildRemoved:Connect(function(child)
        if allRigs[child.Name] then
            allRigs[child.Name] = nil
            motorStates[child.Name] = nil   -- can't reconnect a removed model
            rebuildRigUI()
            print("[MultiAnimation] Rig removed from scene: " .. child.Name)
        elseif child.Name == SIMPLE_CAMERA_NAME then
            simpleCameraPart = nil
            if simpleLookThroughOn then
                setSimpleLookThroughOn(false)
                panel:setSimpleLookThroughState(false)
            end
            print("[MultiAnimation] Simple: camera object removed from scene")
        elseif allProps[child.Name] and mode == "simple" then
            panel:removeProp(child.Name)
            allProps[child.Name] = nil
            print("[MultiAnimation] Simple: prop removed from scene: " .. child.Name)
        end
    end))
end

-- ── Initial load ──────────────────────────────────────────────────────────────

scanAndSetup()

-- ── Test bridge ───────────────────────────────────────────────────────────────
-- Lets tests/test_ui_*.lua drive the live panel from execute_luau.
-- See core/TestBridge.lua for the protocol.

local TestBridge = require(script.core.TestBridge)
local testBridge = TestBridge.start({
    ping = function() return "pong" end,

    getRigs = function()
        local names = {}
        for n in pairs(allRigs) do table.insert(names, n) end
        table.sort(names)
        return names
    end,

    getActiveRigs = function()
        local names = {}
        for n in pairs(panel:getActiveRigs()) do table.insert(names, n) end
        table.sort(names)
        return names
    end,

    setActiveRig = function(a)
        if not allRigs[a.name] then error("no such rig: " .. tostring(a.name)) end
        panel:setActiveRigs({ [a.name] = true })
        return true
    end,

    getCurrentFrame = function() return timeline:getCurrent() end,
    getFrameCount   = function() return timeline:getFrameCount() end,

    setFrame = function(a)
        local f = timeline:setCurrent(a.frame)
        panel:setFrameDisplay(f, timeline:getFrameCount())
        applyPosesAt(f, false)
        return f
    end,

    stepFrame = function(a)
        doStepFrame(a.delta or 1)
        return timeline:getCurrent()
    end,

    addKeyframe = function()
        doAddKeyframe()
        return timeline:getCurrent()
    end,

    getFrames = function(a)
        return recorder:getSortedFrames(a.rig)
    end,

    deleteKeyframe = function(a)
        recorder:deleteRigKeyframe(a.rig, a.frame)
        panel:removeKeyframeMarker(a.rig, a.frame)
        return true
    end,

    -- Camera track (Phase 8)
    captureCamera = function()
        doCameraCapture()
        local kf = recorder:getCameraData(timeline:getCurrent())
        return kf and { frame = timeline:getCurrent(), fov = kf.fov, mode = kf.mode } or nil
    end,

    getCameraFrames = function()
        return recorder:getSortedCameraFrames()
    end,

    getCameraKeyframe = function(a)
        local kf = recorder:getCameraData(a.frame)
        if not kf then return nil end
        return { fov = kf.fov, mode = kf.mode, cf = { kf.cf:GetComponents() } }
    end,

    setCameraMode = function(a)
        local ok = recorder:setCameraMode(a.frame, a.mode)
        if ok then
            panel:setCameraMarkerMode(a.frame, a.mode)
            updateCameraGizmo(a.frame)
        end
        return ok
    end,

    deleteCameraKeyframe = function(a)
        recorder:deleteCameraKeyframe(a.frame)
        panel:removeCameraKeyframeMarker(a.frame)
        updateCameraGizmo(a.frame)
        return true
    end,

    getInterpolatedCamera = function(a)
        local cam = Interpolator.getCameraData(recorder, a.frame)
        if not cam then return nil end
        return { fov = cam.fov, cf = { cam.cf:GetComponents() } }
    end,

    setCameraPreview = function(a)
        panel:setCameraPreviewState(a.on and true or false)
        camPreviewOn = a.on and true or false
        if camPreviewOn then
            savedCamState = savedCamState or CameraCapture.saveState()
            applyPosesAt(timeline:getCurrent(), false)
        else
            CameraCapture.restoreState(savedCamState)
            savedCamState = nil
        end
        return camPreviewOn
    end,

    -- Add Rig / keyframe clipboard (Phase 9)
    addRig = function()
        return doAddRig()
    end,

    copyKeyframe = function()
        return doCopyKeyframe()
    end,

    pasteKeyframe = function(a)
        return doPasteKeyframe(a.mirrored == true)
    end,

    getClipboard = function()
        if not kfClipboard then return nil end
        return { rig = kfClipboard.rig, frame = kfClipboard.frame }
    end,

    clearClipboard = function()
        kfClipboard = nil
        panel:setClipboardDisplay(nil)
        return true
    end,

    getJointCF = function(a)
        local jd = recorder:getJointData(a.rig, a.frame)
        local cf = jd and jd[a.joint]
        return cf and { cf:GetComponents() } or nil
    end,

    setJointCF = function(a)
        local jd = recorder:getJointData(a.rig, a.frame)
        if not jd then return false end
        jd[a.joint] = CFrame.new(
            a.cf[1],  a.cf[2],  a.cf[3],
            a.cf[4],  a.cf[5],  a.cf[6],
            a.cf[7],  a.cf[8],  a.cf[9],
            a.cf[10], a.cf[11], a.cf[12]
        )
        return true
    end,

    -- Effect track (Phase 9)
    trackEffect = function(a)
        -- a.path: dot path from game, e.g. "Workspace.FXPart.Spark"
        local inst = game
        for part in string.gmatch(a.path, "[^.]+") do
            inst = inst:FindFirstChild(part) or (inst == game and game:GetService(part))
            if not inst then return nil end
        end
        local effect = EffectRunner.findEffect(inst)
        if not effect then return nil end
        return trackEffectInstance(effect)
    end,

    getEffects = function()
        local names = {}
        for n in pairs(recorder:getSession().effects or {}) do table.insert(names, n) end
        table.sort(names)
        return names
    end,

    getEffectInfo = function(a)
        local fx = recorder:getEffect(a.name)
        if not fx then return nil end
        return { kind = fx.kind, action = fx.action, linked = allEffects[a.name] ~= nil }
    end,

    cycleEffectAction = function(a)
        local fx = recorder:getEffect(a.name)
        if not fx then return nil end
        local nextAction = EffectRunner.cycleAction(fx.kind, fx.action)
        recorder:setEffectAction(a.name, nextAction)
        panel:setEffectAction(a.name, nextAction)
        return nextAction
    end,

    addEffectEvent = function(a)
        local fx = recorder:getEffect(a.name)
        if not fx then return false end
        local event = { action = fx.action }
        if fx.action == "emit" then event.count = EffectRunner.DEFAULT_EMIT_COUNT end
        recorder:setEffectEvent(a.name, a.frame, event)
        panel:addEffectMarker(a.name, a.frame)
        return true
    end,

    getEffectFrames = function(a)
        return recorder:getSortedEffectFrames(a.name)
    end,

    getEffectEvent = function(a)
        local ev = recorder:getEffectEvent(a.name, a.frame)
        return ev and { action = ev.action, count = ev.count } or nil
    end,

    deleteEffectEvent = function(a)
        recorder:deleteEffectEvent(a.name, a.frame)
        panel:removeEffectMarker(a.name, a.frame)
        return true
    end,

    untrackEffect = function(a)
        panel:removeEffect(a.name)
        allEffects[a.name] = nil
        return true
    end,

    fireEffect = function(a)
        local inst = allEffects[a.name]
        local ev = recorder:getEffectEvent(a.name, a.frame)
        if not (inst and ev) then return false end
        EffectRunner.fire(inst, ev)
        return true
    end,

    -- Simple Mode
    getMode = function() return mode end,

    setMode = function(a)
        if a.mode == "simple" then
            advancedFrameCount = timeline:getFrameCount()
            mode = a.mode
            panel:setMode(a.mode)
            clearCameraGizmos()
            doSimpleScan()
        elseif a.mode == "playback" then
            if not advancedFrameCount then
                advancedFrameCount = timeline:getFrameCount()
            end
            mode = a.mode
            panel:setMode(a.mode)
            doPlaybackScan()
        else
            mode = a.mode
            panel:setMode(a.mode)
            if advancedFrameCount then
                timeline:setFrameCount(advancedFrameCount)
                recorder:setFrameCount(advancedFrameCount)
                panel:setFrameCount(advancedFrameCount)
                advancedFrameCount = nil
            end
            rebuildCameraUI()
        end
        return mode
    end,

    simpleAddFrame = function()
        doSimpleAddFrame()
        return timeline:getCurrent()
    end,

    simpleInsertFrame = function()
        doSimpleInsertFrame()
        return timeline:getCurrent()
    end,

    simpleDeleteFrame = function()
        doSimpleDeleteFrame()
        return timeline:getCurrent()
    end,

    -- Legacy aliases kept for backward compatibility with any saved test scripts.
    simpleStepForward = function()
        doSimpleAddFrame()
        return timeline:getCurrent()
    end,

    simpleDeleteKeyframe = function()
        doSimpleDeleteFrame()
        return timeline:getCurrent()
    end,

    setSimpleCamera = function(a)
        setSimpleCameraOn(a.on and true or false)
        return simpleCameraOn
    end,

    simpleFrameHasData = function(a)
        return simpleFrameHasData(a.frame)
    end,

    getSimpleProps = function()
        local names = {}
        for n in pairs(allProps) do table.insert(names, n) end
        table.sort(names)
        return names
    end,

    isPlaying = function()
        return isPlaying
    end,

    simpleTogglePlay = function()
        if isPlaying then stopPlayback() else startPlayback() end
        return isPlaying
    end,

    setSimpleLookThrough = function(a)
        local result = setSimpleLookThroughOn(a.on and true or false)
        panel:setSimpleLookThroughState(result)
        return result
    end,

    getSimpleLookThrough = function()
        return simpleLookThroughOn
    end,

    setSimpleOnion = function(a)
        setSimpleOnionOn(a.on and true or false)
        return simpleOnionOn
    end,

    getSimpleOnion = function()
        return simpleOnionOn
    end,

    setSimpleCameraFOV = function(a)
        simpleCameraFOV = a.fov
        if simpleCameraPart then
            simpleCameraPart:SetAttribute("FOV", a.fov)
            drawSimpleCameraFrustum(simpleCameraPart, a.fov)
        end
        return simpleCameraFOV
    end,

    getSimpleCameraInfo = function()
        if not (simpleCameraPart and simpleCameraPart.Parent) then return nil end
        return { fov = simpleCameraFOV, cf = { simpleCameraPart.CFrame:GetComponents() } }
    end,

    getSimpleCameraFrustumInfo = function()
        if not (simpleCameraPart and simpleCameraPart.Parent) then return nil end
        local folder = simpleCameraPart:FindFirstChild("FOVFrustum")
        if not folder then return nil end
        local edgeCount, allWelded = 0, true
        for _, edge in ipairs(folder:GetChildren()) do
            if edge:IsA("BasePart") then
                edgeCount += 1
                local weld = edge:FindFirstChildOfClass("WeldConstraint")
                if not (weld and weld.Part0 == simpleCameraPart and weld.Part1 == edge) then
                    allWelded = false
                end
            end
        end
        return { className = folder.ClassName, edgeCount = edgeCount, allWelded = allWelded }
    end,

    getSimpleFPS = function()
        return timeline:getFps()
    end,

    setSimpleFPS = function(a)
        local fps = math.clamp(math.floor(tonumber(a.fps) or 30), 1, 999)
        timeline:setFps(fps)
        recorder:setFps(fps)
        panel:setSimpleFPSDisplay(fps)
        return fps
    end,

    -- Simulates clicking a frame icon: auto-captures the departure frame (same
    -- logic as onFrameChanged in Simple Mode), then navigates to targetFrame.
    simpleNavigate = function(a)
        local targetFrame = a.frame
        if mode == "simple" and not isPlaying then
            local departureFrame = timeline:getCurrent()
            if departureFrame ~= targetFrame and simpleFrameHasData(departureFrame) then
                doSimpleCaptureFrame(departureFrame)
                scheduleAutoSave()
            end
        end
        local f = timeline:setCurrent(targetFrame)
        panel:setFrameDisplay(f, timeline:getFrameCount())
        applyPosesAt(f, false)
        return f
    end,

    -- ── Playback tab TestBridge commands ─────────────────────────────────────
    -- Switch to (or query) playback mode.
    setPlaybackMode = function()
        if mode ~= "playback" then
            if not advancedFrameCount then
                advancedFrameCount = timeline:getFrameCount()
            end
            mode = "playback"
            panel:setMode("playback")
            doPlaybackScan()
        end
        return mode
    end,

    getPlaybackMode = function()
        return mode
    end,

    -- Refresh the playback scene list from saved sessions.
    refreshPlaybackScenes = function()
        doPlaybackScan()
        return { scene = playbackScene, scenes = playbackScenes }
    end,

    -- Select a specific scene by name.
    setPlaybackScene = function(a)
        playbackScene = a.name
        for i, n in ipairs(playbackScenes) do
            if n == a.name then playbackSceneIdx = i; break end
        end
        panel:setPlaybackSceneDisplay(playbackScene)
        panel:rebuildPlaybackRigRows({}, playbackRigModes)
        buildPlaybackSnippet()
        return playbackScene
    end,

    getPlaybackScene = function()
        return playbackScene
    end,

    -- Simulate cycling a rig's mode.
    setPlaybackRigMode = function(a)
        playbackRigModes[a.rigName] = a.mode
        buildPlaybackSnippet()
        return playbackRigModes[a.rigName]
    end,

    getPlaybackRigModes = function()
        return playbackRigModes
    end,

    -- Set playback params.
    setPlaybackParams = function(a)
        if a.fps        ~= nil then playbackFPS       = math.clamp(math.floor(tonumber(a.fps) or 30), 1, 999) end
        if a.loop       ~= nil then playbackLoop      = a.loop and true or false end
        if a.movieMode  ~= nil then playbackMovieMode = a.movieMode and true or false end
        panel:setPlaybackFPSDisplay(playbackFPS)
        panel:setPlaybackLoopDisplay(playbackLoop)
        panel:setPlaybackMovieModeDisplay(playbackMovieMode)
        buildPlaybackSnippet()
        return { fps = playbackFPS, loop = playbackLoop, movieMode = playbackMovieMode }
    end,

    getPlaybackParams = function()
        return { fps = playbackFPS, loop = playbackLoop, movieMode = playbackMovieMode }
    end,

    -- Returns the current snippet text.
    getPlaybackSnippet = function()
        buildPlaybackSnippet()
        return panel._pbSnipBox and panel._pbSnipBox.Text or ""
    end,
})

-- ── devsync teardown registration ─────────────────────────────────────────────
-- The dev loader (devsync.py + MultiAnimationDevLoader) re-runs this source in
-- the same plugin VM on every push; this closure lets the next boot cleanly
-- dismantle this one (see the matching _G.__MultiAnimTeardown call at the top).

_G.__MultiAnimTeardown = function()
    pcall(stopPlayback)
    pcall(reconnectAllRigs)
    if camPreviewOn then
        pcall(function() CameraCapture.restoreState(savedCamState) end)
    end
    pcall(clearCameraGizmos)
    for _, c in ipairs(devConns) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function() testBridge:Destroy() end)
    -- Toolbar/button are reused across boots (IDs can't be re-created in
    -- this plugin VM) — only the widget is destroyed and rebuilt.
    pcall(function() widget:Destroy() end)
end
