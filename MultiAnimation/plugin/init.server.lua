-- MultiAnimation Plugin — entry point
-- Wires all core and UI modules together. Owns the playback loop.
--
-- MOTOR6D SESSION MANAGEMENT
--   Motor6D joints act as welds in Studio edit mode: setting any Part.CFrame
--   moves the entire connected assembly.  We keep ALL Motor6D joints in all
--   rigs DISCONNECTED (Part0 = nil) for the entire plugin session.  This lets
--   the user pose individual limbs freely and lets apply() work correctly.
--   Motors are reconnected only when the plugin unloads (leaving a clean rig).

local RunService           = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService          = game:GetService("HttpService")

local RigScanner   = require(script.core.RigScanner)
local JointCapture = require(script.core.JointCapture)
local Recorder     = require(script.core.Recorder)
local Timeline     = require(script.core.Timeline)
local Interpolator = require(script.core.Interpolator)
local PoseApplier  = require(script.core.PoseApplier)
local Exporter     = require(script.core.Exporter)
local Panel        = require(script.ui.Panel)

-- ── Toolbar & widget ──────────────────────────────────────────────────────────

local toolbar = plugin:CreateToolbar("MultiAnimation")
local toggleButton = toolbar:CreateButton(
    "MultiAnimation",
    "Open / close the MultiAnimation panel",
    ""
)

local widgetInfo = DockWidgetPluginGuiInfo.new(
    Enum.InitialDockState.Bottom,
    false, false, 300, 200, 220, 140
)
local widget = plugin:CreateDockWidgetPluginGui("MultiAnimation", widgetInfo)
widget.Title = "MultiAnimation"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
    toggleButton:SetActive(widget.Enabled)
end)
toggleButton.Click:Connect(function()
    widget.Enabled = not widget.Enabled
end)

-- ── Core state ────────────────────────────────────────────────────────────────

local timeline = Timeline.new(24, 120)
local recorder = Recorder.new()
local panel    = Panel.new(widget)

local allRigs      = {}   -- { [rigName] = Model }
local motorStates  = {}   -- { [rigName] = disconnectAll() state } for cleanup
local isPlaying    = false
local playConn     = nil

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
        if jd then
            if immediate then
                PoseApplier.applyImmediate(model, jd, sd)
            else
                PoseApplier.applyRecorded(model, jd, sd)
            end
        end
    end
end

local function allKeyframesSorted()
    local names = {}
    for n in pairs(allRigs) do table.insert(names, n) end
    return Interpolator.getAllFrames(recorder, names)
end

-- ── Session persistence ───────────────────────────────────────────────────────

local SAVE_KEY = "MultiAnim_Session_v1"

local function serializeSession()
    local session = recorder:getSession()
    local out = { fps = session.fps, frameCount = session.frameCount, rigs = {} }
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
        out.rigs[rigName] = { joints = jOut, scales = sOut }
    end
    return out
end

local function saveSession()
    local ok, err = pcall(function()
        plugin:SetSetting(SAVE_KEY, serializeSession())
    end)
    if ok then
        print("[MultiAnimation] Session saved")
    else
        warn("[MultiAnimation] Save failed: " .. tostring(err))
    end
end

local function loadSession()
    local ok, data = pcall(function()
        return plugin:GetSetting(SAVE_KEY)
    end)
    if not ok or not data or not data.rigs then
        warn("[MultiAnimation] No saved session found")
        return
    end

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
                        arr[1], arr[2], arr[3],
                        arr[4], arr[5], arr[6],
                        arr[7], arr[8], arr[9],
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
    end

    panel:setRigs(allRigs)
    for rigName in pairs(allRigs) do
        for _, frame in ipairs(recorder:getSortedFrames(rigName)) do
            panel:addKeyframeMarker(rigName, frame)
        end
    end
    panel:setFrameCount(frameCount)
    panel:setFrameDisplay(timeline:getCurrent(), frameCount)
    print("[MultiAnimation] Session loaded")
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

panel.onAddKeyframeRequested:Connect(function()
    local frame      = timeline:getCurrent()
    local activeRigs = panel:getActiveRigs()
    if next(activeRigs) == nil then
        warn("[MultiAnimation] No active rigs selected")
        return
    end
    recorder:addKeyframe(frame, activeRigs)
    local rigNames = {}
    for rigName in pairs(activeRigs) do
        panel:addKeyframeMarker(rigName, frame)
        table.insert(rigNames, rigName)
    end
    table.sort(rigNames)
    print(string.format("[MultiAnimation] Keyframe added at frame %d for: %s",
        frame, table.concat(rigNames, ", ")))
end)

panel.onFrameChanged:Connect(function(newFrame)
    local f = timeline:setCurrent(newFrame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
end)

panel.onScrubBegan:Connect(function()
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
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    applyPosesAt(f, false)
    recorder:addKeyframe(f, { [rigName] = model })
    panel:addKeyframeMarker(rigName, f)
    print(string.format("[MultiAnimation] Keyframe added at frame %d for %s", f, rigName))
end)

panel.onMarkerDeleteRequested:Connect(function(rigName, frame)
    recorder:deleteRigKeyframe(rigName, frame)
    panel:removeKeyframeMarker(rigName, frame)
    print(string.format("[MultiAnimation] Deleted keyframe at frame %d for %s", frame, rigName))
end)

panel.onSaveRequested:Connect(saveSession)
panel.onReloadRequested:Connect(loadSession)
panel.onPreviewRequested:Connect(startPlayback)
panel.onStopRequested:Connect(stopPlayback)

panel.onExportRequested:Connect(function(sceneName)
    local ok, result = Exporter.export(recorder:getSession(), sceneName)
    if not ok then
        warn(string.format("[MultiAnimation] Export failed: %s", result))
    end
end)

-- ── Viewport selection → rig selector sync ───────────────────────────────────

local Selection = game:GetService("Selection")

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

Selection.SelectionChanged:Connect(function()
    if isPlaying then return end
    local selected = Selection:Get()
    local foundRigs = {}
    for _, inst in ipairs(selected) do
        local rigName = findRigForInstance(inst)
        if rigName then foundRigs[rigName] = true end
    end
    if next(foundRigs) then
        panel:setActiveRigs(foundRigs)
    end
end)

-- ── Clean up on unload ────────────────────────────────────────────────────────
-- Reconnect all Motor6D joints so the rig is in a clean state when the plugin
-- is disabled or Studio is closed.

plugin.Unloading:Connect(function()
    stopPlayback()
    reconnectAllRigs()
end)

-- ── Initial load ──────────────────────────────────────────────────────────────

scanAndSetup()
