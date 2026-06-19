-- KeyframeMarker — a single clickable dot on a TrackLane.
--
-- Positioned by the TrackLane at the correct proportional X offset.
-- Fires onClicked(frame) when the user clicks it.

local MARKER_SIZE   = 10
local COLOR_DEFAULT = Color3.fromRGB(255, 200,  60)   -- yellow (rig)
local COLOR_ACTIVE  = Color3.fromRGB(255, 255, 255)

local KeyframeMarker = {}
KeyframeMarker.__index = KeyframeMarker

-- colour is optional; defaults to yellow. Pass teal for prop markers.
function KeyframeMarker.new(parent, frame, colour)
    local self = setmetatable({}, KeyframeMarker)
    self.frame = frame

    local baseColor  = colour or COLOR_DEFAULT
    self._baseColor  = baseColor

    local clicked = Instance.new("BindableEvent")
    self.onClicked = clicked.Event
    self._clicked  = clicked

    local deleteRequested = Instance.new("BindableEvent")
    self.onDeleteRequested = deleteRequested.Event
    self._deleteRequested  = deleteRequested

    local btn = Instance.new("TextButton")
    btn.Name            = "KF_" .. frame
    btn.Size            = UDim2.new(0, MARKER_SIZE, 0, MARKER_SIZE)
    btn.AnchorPoint     = Vector2.new(0.5, 0.5)
    -- X position is set by TrackLane; Y centred in lane
    btn.Position        = UDim2.new(0, 0, 0.5, 0)
    btn.BackgroundColor3 = baseColor
    btn.BorderSizePixel = 0
    btn.Text            = ""
    btn.AutoButtonColor = false
    btn.ZIndex          = 3
    btn.Parent          = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)   -- full circle
    corner.Parent       = btn

    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = self._baseColor:Lerp(Color3.new(1, 1, 1), 0.35)
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = self._baseColor
    end)
    btn.MouseButton2Click:Connect(function()
        deleteRequested:Fire(frame, btn.AbsolutePosition)
    end)

    btn.MouseButton1Click:Connect(function()
        btn.BackgroundColor3 = COLOR_ACTIVE
        task.delay(0.1, function()
            if btn and btn.Parent then
                btn.BackgroundColor3 = self._baseColor
            end
        end)
        clicked:Fire(frame)
    end)

    self._btn = btn
    return self
end

function KeyframeMarker:setXOffset(xPixels)
    self._btn.Position = UDim2.new(0, xPixels, 0.5, 0)
end

function KeyframeMarker:setActive(isActive)
    self._btn.BackgroundColor3 = isActive and COLOR_ACTIVE or self._baseColor
end

function KeyframeMarker:setColour(colour)
    self._baseColor = colour
    self._btn.BackgroundColor3 = colour
end

function KeyframeMarker:destroy()
    self._clicked:Destroy()
    self._deleteRequested:Destroy()
    if self._btn and self._btn.Parent then
        self._btn:Destroy()
    end
end

return KeyframeMarker
