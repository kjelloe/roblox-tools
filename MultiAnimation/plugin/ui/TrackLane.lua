-- TrackLane — one horizontal keyframe lane for a single rig.
--
-- Layout:
--   [RigName label (fixed width)] [track area (fills remaining width)]
--
-- Markers are positioned proportionally: xOffset = (frame-1)/(frameCount-1) * trackWidth
-- Fires onMarkerClicked(frame) when a dot is clicked.

local KeyframeMarker = require(script.Parent.KeyframeMarker)

local LABEL_W    = 52
local LANE_H     = 28
local TRACK_BG   = Color3.fromRGB(30, 30, 30)
local LABEL_COL  = Color3.fromRGB(180, 180, 180)
local LINE_COL   = Color3.fromRGB(70, 70, 70)

local TrackLane = {}
TrackLane.__index = TrackLane

-- colour is optional; nil uses the default yellow for rigs.
-- Pass teal Color3 for prop track lanes.
function TrackLane.new(parent, rigName, frameCount, layoutOrder, colour)
    local self = setmetatable({}, TrackLane)
    self._rigName    = rigName
    self._frameCount = frameCount
    self._markers    = {}   -- { [frame] = KeyframeMarker }
    self._colour     = colour  -- passed to KeyframeMarker.new

    local markerClicked = Instance.new("BindableEvent")
    self.onMarkerClicked = markerClicked.Event
    self._markerClicked  = markerClicked

    local markerDeleteRequested = Instance.new("BindableEvent")
    self.onMarkerDeleteRequested = markerDeleteRequested.Event
    self._markerDeleteRequested  = markerDeleteRequested

    local doubleClicked = Instance.new("BindableEvent")
    self.onDoubleClicked = doubleClicked.Event
    self._doubleClicked  = doubleClicked

    -- Row container
    local row = Instance.new("Frame")
    row.Name            = "Lane_" .. rigName
    row.Size            = UDim2.new(1, 0, 0, LANE_H)
    row.BackgroundTransparency = 1
    row.LayoutOrder     = layoutOrder or 1
    row.Parent          = parent

    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.SortOrder     = Enum.SortOrder.LayoutOrder
    rowLayout.Padding       = UDim.new(0, 4)
    rowLayout.Parent        = row

    -- Rig name label
    local label = Instance.new("TextLabel")
    label.Size               = UDim2.new(0, LABEL_W, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3         = LABEL_COL
    label.Text               = rigName
    label.TextSize           = 11
    label.Font               = Enum.Font.Gotham
    label.TextXAlignment     = Enum.TextXAlignment.Right
    label.TextTruncate       = Enum.TextTruncate.AtEnd
    label.LayoutOrder        = 1
    label.Parent             = row

    -- Track area
    local track = Instance.new("Frame")
    track.Name               = "Track"
    track.Size               = UDim2.new(1, -(LABEL_W + 4), 1, 0)
    track.BackgroundColor3   = TRACK_BG
    track.BorderSizePixel    = 0
    track.ClipsDescendants   = true
    track.LayoutOrder        = 2
    track.Parent             = row

    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 3)

    -- Centre line
    local line = Instance.new("Frame")
    line.Size               = UDim2.new(1, 0, 0, 1)
    line.AnchorPoint        = Vector2.new(0, 0.5)
    line.Position           = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3   = LINE_COL
    line.BorderSizePixel    = 0
    line.ZIndex             = 1
    line.Parent             = track

    -- Double-click on track background → add keyframe at that position
    local lastClickTime = 0
    local DBLCLICK = 0.35
    track.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local now = tick()
        if now - lastClickTime < DBLCLICK then
            local relX  = input.Position.X - track.AbsolutePosition.X
            local w     = track.AbsoluteSize.X
            local frame = 1
            if w > 0 and self._frameCount > 1 then
                frame = math.clamp(
                    math.round((relX / w) * (self._frameCount - 1)) + 1,
                    1, self._frameCount)
            end
            doubleClicked:Fire(frame)
            lastClickTime = 0   -- prevent triple-click retriggering
        else
            lastClickTime = now
        end
    end)

    self._row   = row
    self._track = track
    return self
end

function TrackLane:_markerXOffset(frame)
    if self._frameCount <= 1 then return 0 end
    -- Use AbsoluteSize if available, else assume full width
    local w = self._track.AbsoluteSize.X
    if w == 0 then w = 200 end
    return math.round(((frame - 1) / (self._frameCount - 1)) * w)
end

-- Add or overwrite a keyframe marker at the given frame.
function TrackLane:addMarker(frame)
    if self._markers[frame] then
        self._markers[frame]:destroy()
    end

    local marker = KeyframeMarker.new(self._track, frame, self._colour)
    marker:setXOffset(self:_markerXOffset(frame))

    marker.onClicked:Connect(function(f)
        self._markerClicked:Fire(f)
    end)
    marker.onDeleteRequested:Connect(function(f)
        self._markerDeleteRequested:Fire(f)
    end)

    self._markers[frame] = marker
end

function TrackLane:removeMarker(frame)
    if self._markers[frame] then
        self._markers[frame]:destroy()
        self._markers[frame] = nil
    end
end

function TrackLane:clearMarkers()
    for _, m in pairs(self._markers) do
        m:destroy()
    end
    self._markers = {}
end

function TrackLane:setFrameCount(frameCount)
    self._frameCount = frameCount
    -- Reposition all existing markers
    for frame, marker in pairs(self._markers) do
        marker:setXOffset(self:_markerXOffset(frame))
    end
end

-- Highlight the marker at `frame` (e.g. when scrubber lands on it).
function TrackLane:setActiveFrame(frame)
    for f, marker in pairs(self._markers) do
        marker:setActive(f == frame)
    end
end

function TrackLane:destroy()
    self:clearMarkers()
    self._markerClicked:Destroy()
    self._markerDeleteRequested:Destroy()
    self._doubleClicked:Destroy()
    if self._row and self._row.Parent then
        self._row:Destroy()
    end
end

return TrackLane
