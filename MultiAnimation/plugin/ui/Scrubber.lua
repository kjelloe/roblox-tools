-- Scrubber — horizontal drag slider that maps mouse X position to frame numbers.
--
-- Fires:
--   onFrameChanged(frame)   — fires continuously while dragging
--   onDragBegan()           — fires when drag starts (use to pause history)
--   onDragEnded()           — fires when drag ends   (use to resume history)
--
-- Public methods:
--   scrubber:setFrame(n)        — update thumb position without firing event
--   scrubber:setFrameCount(n)   — update scale (repositions thumb)

local UserInputService = game:GetService("UserInputService")

local TRACK_H   = 14
local THUMB_W   = 10
local THUMB_H   = 18
local TRACK_BG  = Color3.fromRGB(28,  28,  28)
local FILL_COL  = Color3.fromRGB(0,  100, 170)
local THUMB_COL = Color3.fromRGB(210, 210, 210)
local THUMB_HOV = Color3.fromRGB(255, 255, 255)

local Scrubber = {}
Scrubber.__index = Scrubber

function Scrubber.new(parent, frameCount, layoutOrder)
    local self = setmetatable({}, Scrubber)
    self._frameCount = math.max(2, frameCount or 120)
    self._current    = 1
    self._dragging   = false

    local eChanged  = Instance.new("BindableEvent")
    local eBegan    = Instance.new("BindableEvent")
    local eEnded    = Instance.new("BindableEvent")
    self.onFrameChanged = eChanged.Event
    self.onDragBegan    = eBegan.Event
    self.onDragEnded    = eEnded.Event
    self._events = { eChanged, eBegan, eEnded }

    -- Outer container (gives vertical centering room for the tall thumb)
    local container = Instance.new("Frame")
    container.Name             = "ScrubberContainer"
    container.Size             = UDim2.new(1, 0, 0, THUMB_H + 2)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false
    container.LayoutOrder      = layoutOrder or 1
    container.Parent           = parent

    -- Track (the thin horizontal rail)
    local track = Instance.new("Frame")
    track.Name             = "Track"
    track.Size             = UDim2.new(1, 0, 0, TRACK_H)
    track.AnchorPoint      = Vector2.new(0, 0.5)
    track.Position         = UDim2.new(0, 0, 0.5, 0)
    track.BackgroundColor3 = TRACK_BG
    track.BorderSizePixel  = 0
    track.ClipsDescendants = false
    track.ZIndex           = 1
    track.Parent           = container
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 4)

    -- Fill bar (progress)
    local fill = Instance.new("Frame")
    fill.Name             = "Fill"
    fill.Size             = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = FILL_COL
    fill.BorderSizePixel  = 0
    fill.ZIndex           = 2
    fill.Parent           = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

    -- Invisible hit area over the whole track (for click-to-jump)
    local hitArea = Instance.new("TextButton")
    hitArea.Name             = "HitArea"
    hitArea.Size             = UDim2.new(1, 0, 1, 0)
    hitArea.BackgroundTransparency = 1
    hitArea.Text             = ""
    hitArea.AutoButtonColor  = false
    hitArea.ZIndex           = 3
    hitArea.Parent           = track

    -- Thumb (the draggable handle)
    local thumb = Instance.new("TextButton")
    thumb.Name             = "Thumb"
    thumb.Size             = UDim2.new(0, THUMB_W, 0, THUMB_H)
    thumb.AnchorPoint      = Vector2.new(0.5, 0.5)
    thumb.Position         = UDim2.new(0, 0, 0.5, 0)
    thumb.BackgroundColor3 = THUMB_COL
    thumb.BorderSizePixel  = 0
    thumb.Text             = ""
    thumb.AutoButtonColor  = false
    thumb.ZIndex           = 5
    thumb.Parent           = track
    Instance.new("UICorner", thumb).CornerRadius = UDim.new(0, 3)

    self._track   = track
    self._fill    = fill
    self._thumb   = thumb

    -- ── Helpers ───────────────────────────────────────────────────────────────

    local function frameFromScreenX(screenX)
        local left  = track.AbsolutePosition.X
        local width = track.AbsoluteSize.X
        if width <= 0 then return self._current end
        local frac = math.clamp((screenX - left) / width, 0, 1)
        return math.round(1 + frac * (self._frameCount - 1))
    end

    local function updateVisual(frame)
        local frac = (self._frameCount > 1)
            and ((frame - 1) / (self._frameCount - 1))
            or 0
        local w = math.round(frac * track.AbsoluteSize.X)
        fill.Size      = UDim2.new(0, w, 1, 0)
        thumb.Position = UDim2.new(0, w, 0.5, 0)
    end
    self._updateVisual = updateVisual

    -- ── Input handling ────────────────────────────────────────────────────────

    thumb.MouseEnter:Connect(function()
        thumb.BackgroundColor3 = THUMB_HOV
    end)
    thumb.MouseLeave:Connect(function()
        if not self._dragging then thumb.BackgroundColor3 = THUMB_COL end
    end)

    -- Unified drag-start: always uses GetMouseLocation() so coordinate space
    -- matches the AbsolutePosition used in frameFromScreenX.
    local function startDrag()
        local mouseX = UserInputService:GetMouseLocation().X
        local frame  = frameFromScreenX(mouseX)
        self._dragging = true
        self._current  = frame
        updateVisual(frame)
        thumb.BackgroundColor3 = THUMB_HOV
        eBegan:Fire()
        eChanged:Fire(frame)
    end

    -- Clicking the thumb starts a drag from the thumb's current position.
    thumb.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        startDrag()
    end)

    -- Clicking anywhere on the track also starts a drag.
    hitArea.MouseButton1Down:Connect(function()
        startDrag()
    end)

    -- Track mouse movement globally so drag continues past the thumb edges.
    local moveConn = UserInputService.InputChanged:Connect(function(input)
        if not self._dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        -- Guard: release if button was dropped outside the plugin window
        if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            self._dragging = false
            thumb.BackgroundColor3 = THUMB_COL
            eEnded:Fire()
            return
        end
        local frame = frameFromScreenX(UserInputService:GetMouseLocation().X)
        if frame ~= self._current then
            self._current = frame
            updateVisual(frame)
            eChanged:Fire(frame)
        end
    end)

    local endConn = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if not self._dragging then return end
        self._dragging = false
        thumb.BackgroundColor3 = THUMB_COL
        eEnded:Fire()
    end)

    self._conns = { moveConn, endConn }
    return self
end

function Scrubber:setFrame(frame)
    self._current = math.clamp(math.round(frame), 1, self._frameCount)
    self._updateVisual(self._current)
end

function Scrubber:setFrameCount(n)
    self._frameCount = math.max(2, n)
    self._updateVisual(self._current)
end

function Scrubber:destroy()
    for _, c in ipairs(self._conns) do c:Disconnect() end
    for _, e in ipairs(self._events) do e:Destroy() end
    if self._track and self._track.Parent then
        self._track.Parent:Destroy()  -- destroy container
    end
end

return Scrubber
