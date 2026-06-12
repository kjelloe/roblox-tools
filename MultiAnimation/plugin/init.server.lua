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
    -- Keep the "Cam KF: move/cut/—" button reflecting the current frame.
    local camKF = recorder:getCameraData(math.floor(queryFrame + 0.5))
    panel:setCameraModeDisplay(camKF and camKF.mode or nil)
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
    local out = { fps = session.fps, frameCount = session.frameCount, rigs = {}, props = {} }
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

    recorder:clearSession()
    local fps        = data.fps        or 24
    local frameCount = data.frameCount or 120
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

    playConn = RunService.Heartbeat:Connect(function()
        local elapsed  = tick() - startTick
        local rawFrame = startFrame + elapsed * fps
        local intFrame = math.min(math.floor(rawFrame), lastFrame)

        applyPosesAt(rawFrame, true)

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

panel.onFrameChanged:Connect(function(newFrame)
    local f = timeline:setCurrent(newFrame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
end)

panel.onScrubBegan:Connect(function()
    -- Auto-update existing keyframe at the departure frame.
    -- If the user was parked at a keyframe and manually adjusted the rig/prop pose,
    -- re-capture it now so the change is saved without an explicit "Add Keyframe" click.
    -- Idempotent if nothing changed (captures the same values).
    if not isPlaying then
        local frame       = timeline:getCurrent()
        local activeRigs  = panel:getActiveRigs()
        local activeProps = panel:getActiveProps()

        local shouldUpdate = false
        for rigName in pairs(activeRigs) do
            if recorder:hasKeyframe(rigName, frame) then
                shouldUpdate = true; break
            end
        end
        if not shouldUpdate then
            for propName in pairs(activeProps) do
                if recorder:getPropData(propName, frame) ~= nil then
                    shouldUpdate = true; break
                end
            end
        end

        if shouldUpdate then
            recorder:addKeyframe(frame, activeRigs, activeProps)
            scheduleAutoSave()
        end
    end

    ChangeHistoryService:SetEnabled(false)
end)
panel.onScrubEnded:Connect(function()
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
    -- Recorder data is intentionally kept so export still works
    print("[MultiAnimation] Stopped tracking prop: " .. propName)
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
    clearCameraGizmos()
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
            if allRigs[child.Name] then return end   -- already tracked
            -- Let RigScanner decide if it's a valid R6 rig.
            local fresh = RigScanner.scan()
            if fresh[child.Name] then
                allRigs[child.Name] = child
                recorder:captureRestPose(child.Name, child)
                disconnectRig(child.Name, child)
                rebuildRigUI()
                print("[MultiAnimation] Auto-detected rig: " .. child.Name)
            end
        end)
    end))

    track(figuresFolder.ChildRemoved:Connect(function(child)
        if allRigs[child.Name] then
            allRigs[child.Name] = nil
            motorStates[child.Name] = nil   -- can't reconnect a removed model
            rebuildRigUI()
            print("[MultiAnimation] Rig removed from scene: " .. child.Name)
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
