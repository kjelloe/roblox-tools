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
--
-- COORDINATE / INPUT NOTES (Studio DockWidget context)
--   Only GuiObject events work reliably in a Studio plugin DockWidget.
--   UserInputService.InputChanged (MouseMovement) does not fire over the panel.
--   UserInputService:IsMouseButtonPressed() always returns false over the panel.
--   Solution: at drag-start create a transparent overlay Frame covering the full
--   panel (dragRoot). overlay.InputChanged captures movement. The element that
--   received InputBegan owns the mouse-button capture, so its InputEnded fires
--   on release even if the mouse has moved elsewhere.

local Scrubber = {}
Scrubber.__index = Scrubber

local TRACK_H   = 14
local THUMB_W   = 10
local THUMB_H   = 18
local TRACK_BG  = Color3.fromRGB(28,  28,  28)
local FILL_COL  = Color3.fromRGB(0,  100, 170)
local THUMB_COL = Color3.fromRGB(210, 210, 210)
local THUMB_HOV = Color3.fromRGB(255, 255, 255)

-- dragRoot: the root Frame of the panel (passed from Panel.new).
-- A full-size transparent overlay is parented here during drag so that
-- InputChanged fires for mouse movement anywhere inside the panel.
function Scrubber.new(parent, frameCount, layoutOrder, dragRoot)
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

    -- Container
    local container = Instance.new("Frame")
    container.Name             = "ScrubberContainer"
    container.Size             = UDim2.new(1, 0, 0, THUMB_H + 2)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = false
    container.LayoutOrder      = layoutOrder or 1
    container.Parent           = parent

    -- Track rail
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

    -- Fill bar
    local fill = Instance.new("Frame")
    fill.Name             = "Fill"
    fill.Size             = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = FILL_COL
    fill.BorderSizePixel  = 0
    fill.ZIndex           = 2
    fill.Parent           = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

    -- Hit area (receives clicks on the track, behind the thumb)
    local hitArea = Instance.new("TextButton")
    hitArea.Name             = "HitArea"
    hitArea.Size             = UDim2.new(1, 0, 1, 0)
    hitArea.BackgroundTransparency = 1
    hitArea.Text             = ""
    hitArea.AutoButtonColor  = false
    hitArea.ZIndex           = 3
    hitArea.Parent           = track

    -- Thumb (draggable handle)
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

    self._track = track
    self._fill  = fill
    self._thumb = thumb

    -- ── Helpers ───────────────────────────────────────────────────────────────

    local function frameFromInputX(inputX)
        local left  = track.AbsolutePosition.X
        local width = track.AbsoluteSize.X
        if width <= 0 then return self._current end
        local frac = math.clamp((inputX - left) / width, 0, 1)
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

    -- ── Drag ─────────────────────────────────────────────────────────────────
    --
    -- sourceElement: the thumb or hitArea that received InputBegan.
    --   Roblox routes InputEnded to whichever element got InputBegan,
    --   so we listen there for the mouse-button release.
    --
    -- overlay: full-panel transparent Frame whose InputChanged tracks
    --   mouse movement while the button is held.  Destroyed on drag end.

    local function startDragAt(inputX, sourceElement)
        local frame = frameFromInputX(inputX)

        self._dragging = true
        self._current  = frame
        updateVisual(frame)
        thumb.BackgroundColor3 = THUMB_HOV
        eBegan:Fire()
        eChanged:Fire(frame)

        -- Transparent overlay covering the panel so InputChanged fires everywhere
        local overlay
        if dragRoot then
            overlay = Instance.new("Frame")
            overlay.Name             = "ScrubDragOverlay"
            overlay.Size             = UDim2.new(1, 0, 1, 0)
            overlay.BackgroundTransparency = 1
            overlay.BorderSizePixel  = 0
            overlay.ZIndex           = 999
            overlay.Parent           = dragRoot
        end

        local cleanedUp = false
        local sourceEndConn

        local function cleanup()
            if cleanedUp then return end
            cleanedUp = true
            if sourceEndConn then sourceEndConn:Disconnect() end
            if overlay then overlay:Destroy() end
            self._dragging = false
            thumb.BackgroundColor3 = THUMB_COL
            eEnded:Fire()
        end

        -- Movement: overlay.InputChanged fires while mouse is over overlay
        if overlay then
            overlay.InputChanged:Connect(function(input)
                if not self._dragging then return end
                if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
                local f = frameFromInputX(input.Position.X)
                if f ~= self._current then
                    self._current = f
                    updateVisual(f)
                    eChanged:Fire(f)
                end
            end)

            -- Release detected on overlay (mouse released while over the panel)
            overlay.InputEnded:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
                cleanup()
            end)
        end

        -- Release detected on source element (GuiObject owns the button capture
        -- and fires InputEnded on release even if mouse has moved away)
        sourceEndConn = sourceElement.InputEnded:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            cleanup()
        end)
    end

    -- ── Click events ──────────────────────────────────────────────────────────

    thumb.MouseEnter:Connect(function()
        if not self._dragging then thumb.BackgroundColor3 = THUMB_HOV end
    end)
    thumb.MouseLeave:Connect(function()
        if not self._dragging then thumb.BackgroundColor3 = THUMB_COL end
    end)

    thumb.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        startDragAt(input.Position.X, thumb)
    end)

    hitArea.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        startDragAt(input.Position.X, hitArea)
    end)

    self._conns = {}   -- no persistent UserInputService connections needed
    return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

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
        self._track.Parent:Destroy()
    end
end

return Scrubber
