-- RigSelector — renders one toggle button per rig.
--
-- Active rigs (blue) will be included when "Add Keyframe" is pressed.
-- Inactive rigs (grey) keep their recorded data but are not updated.
-- The last active rig cannot be deselected.
--
-- Public API:
--   RigSelector.new(parent)        → selector
--   selector:setRigs(rigsTable)    — rebuilds buttons from { [name]=Model }
--   selector:getActiveRigs()       → { [name]=Model } of active rigs only
--   selector.onActiveRigsChanged   — BindableEvent.Event, fired on every toggle

local COLORS = {
    active   = Color3.fromRGB(0,  148, 214),
    inactive = Color3.fromRGB(68,  68,  68),
    hover    = Color3.fromRGB(90,  90,  90),
    text     = Color3.fromRGB(220, 220, 220),
    textDim  = Color3.fromRGB(160, 160, 160),
}

local RigSelector = {}
RigSelector.__index = RigSelector

function RigSelector.new(parent)
    local self = setmetatable({}, RigSelector)

    local changed = Instance.new("BindableEvent")
    self.onActiveRigsChanged = changed.Event
    self._changed = changed

    -- Wrap in a frame so it sizes to its children
    local container = Instance.new("Frame")
    container.Name = "RigSelectorContainer"
    container.Size = UDim2.new(1, 0, 0, 0)
    container.AutomaticSize = Enum.AutomaticSize.Y
    container.BackgroundTransparency = 1
    container.LayoutOrder = 1
    container.Parent = parent

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Top
    layout.Wraps = true
    layout.SortOrder = Enum.SortOrder.Name
    layout.Padding = UDim.new(0, 6)
    layout.Parent = container

    self._container = container
    self._active  = {}   -- { [rigName] = bool }
    self._buttons = {}   -- { [rigName] = TextButton }
    self._rigs    = {}   -- { [rigName] = Model }

    return self
end

-- Rebuilds toggle buttons from a fresh scan result.
-- All rigs default to active.
function RigSelector:setRigs(rigs)
    -- Destroy existing buttons
    for _, btn in pairs(self._buttons) do
        btn:Destroy()
    end
    self._buttons = {}
    self._active  = {}
    self._rigs    = rigs

    local any = false
    for name in pairs(rigs) do
        self._active[name] = true
        self:_buildButton(name)
        any = true
    end

    if not any then
        -- Show a placeholder when no rigs are found
        local lbl = Instance.new("TextLabel")
        lbl.Name = "__empty"
        lbl.Size = UDim2.new(1, 0, 0, 22)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = COLORS.textDim
        lbl.Text = "No R6 rigs found — press Refresh"
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Gotham
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = self._container
    else
        local old = self._container:FindFirstChild("__empty")
        if old then old:Destroy() end
    end

    self._changed:Fire(self:getActiveRigs())
end

function RigSelector:getActiveRigs()
    local result = {}
    for name, active in pairs(self._active) do
        if active then
            result[name] = self._rigs[name]
        end
    end
    return result
end

function RigSelector:_activeCount()
    local n = 0
    for _, v in pairs(self._active) do
        if v then n += 1 end
    end
    return n
end

function RigSelector:_buildButton(name)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, 88, 0, 28)
    btn.BackgroundColor3 = COLORS.active
    btn.BorderSizePixel = 0
    btn.TextColor3 = COLORS.text
    btn.Text = "✓  " .. name
    btn.TextSize = 12
    btn.Font = Enum.Font.Gotham
    btn.AutoButtonColor = false
    btn.Parent = self._container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        local isActive = self._active[name]

        -- Cannot deselect the last active rig
        if isActive and self:_activeCount() <= 1 then return end

        self._active[name] = not isActive
        self:_refreshButton(name)
        self._changed:Fire(self:getActiveRigs())
    end)

    btn.MouseEnter:Connect(function()
        if not self._active[name] then
            btn.BackgroundColor3 = COLORS.hover
        end
    end)
    btn.MouseLeave:Connect(function()
        if not self._active[name] then
            btn.BackgroundColor3 = COLORS.inactive
        end
    end)

    self._buttons[name] = btn
end

function RigSelector:setActiveRigs(rigNames)
    for name in pairs(self._active) do
        self._active[name] = rigNames[name] == true
    end
    for name in pairs(self._buttons) do
        self:_refreshButton(name)
    end
    self._changed:Fire(self:getActiveRigs())
end

function RigSelector:_refreshButton(name)
    local btn = self._buttons[name]
    if not btn then return end
    local active = self._active[name]
    btn.BackgroundColor3 = active and COLORS.active or COLORS.inactive
    btn.Text = (active and "✓  " or "○  ") .. name
end

function RigSelector:destroy()
    self._changed:Destroy()
end

return RigSelector
