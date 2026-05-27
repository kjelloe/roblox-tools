-- MultiAnimation Plugin — entry point
-- Creates the toolbar button and dock widget, then wires all modules together.

local RigScanner = require(script.core.RigScanner)
local Recorder   = require(script.core.Recorder)
local Timeline   = require(script.core.Timeline)
local Panel      = require(script.ui.Panel)

-- ── Toolbar ───────────────────────────────────────────────────────────────────

local toolbar = plugin:CreateToolbar("MultiAnimation")

local toggleButton = toolbar:CreateButton(
    "MultiAnimation",
    "Open / close the MultiAnimation panel",
    ""
)

-- ── Dock widget ───────────────────────────────────────────────────────────────

local widgetInfo = DockWidgetPluginGuiInfo.new(
    Enum.InitialDockState.Bottom,
    false,  -- initial enabled state
    false,  -- override previous state
    300,    -- default width
    200,    -- default height
    220,    -- min width
    140     -- min height
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

-- ── Core components ───────────────────────────────────────────────────────────

local timeline = Timeline.new(24, 120)
local recorder = Recorder.new()

-- ── Panel ─────────────────────────────────────────────────────────────────────

local panel = Panel.new(widget)

-- ── Wiring ────────────────────────────────────────────────────────────────────

-- Refresh: rescan FIGURES, rebuild rig list and track lanes
panel.onRefreshRequested:Connect(function()
    local rigs = RigScanner.scan()

    -- Capture rest poses for any newly discovered rigs
    for name, model in pairs(rigs) do
        recorder:captureRestPose(name, model)
    end

    panel:setRigs(rigs)
    panel:setFrameDisplay(timeline:getCurrent(), timeline:getFrameCount())
end)

-- Add Keyframe: snapshot active rigs at current frame
panel.onAddKeyframeRequested:Connect(function()
    local frame      = timeline:getCurrent()
    local activeRigs = panel:getActiveRigs()

    if next(activeRigs) == nil then
        warn("[MultiAnimation] No active rigs — toggle at least one rig on")
        return
    end

    recorder:addKeyframe(frame, activeRigs)

    -- Update track lane markers for every rig that was recorded
    for rigName in pairs(activeRigs) do
        panel:addKeyframeMarker(rigName, frame)
    end

    print(string.format("[MultiAnimation] Keyframe added at frame %d", frame))
end)

-- Frame navigation: update timeline + display
panel.onFrameChanged:Connect(function(newFrame)
    local f = timeline:setCurrent(newFrame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
end)

-- Marker clicked: jump to that frame
panel.onMarkerClicked:Connect(function(rigName, frame)
    local f = timeline:setCurrent(frame)
    panel:setFrameDisplay(f, timeline:getFrameCount())
    print(string.format("[MultiAnimation] Jumped to frame %d (via %s marker)", f, rigName))
end)

-- ── Initial load ──────────────────────────────────────────────────────────────

local rigs = RigScanner.scan()
for name, model in pairs(rigs) do
    recorder:captureRestPose(name, model)
end
panel:setRigs(rigs)
panel:setFrameDisplay(timeline:getCurrent(), timeline:getFrameCount())
