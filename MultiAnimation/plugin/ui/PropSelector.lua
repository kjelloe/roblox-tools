-- PropSelector — "PROPS IN SCENE" section content.
-- Creates a "Track Part" button and dynamic per-prop multi-select toggle rows.
-- Props are multi-select (independent of the exclusive rig selector).

local C = {
    btnBg      = Color3.fromRGB(68,  68,  68),
    btnHover   = Color3.fromRGB(90,  90,  90),
    btnActive  = Color3.fromRGB(0,  130, 130),
    btnActHov  = Color3.fromRGB(0,  160, 160),
    btnText    = Color3.fromRGB(210, 210, 210),
    removeBg   = Color3.fromRGB(100,  50,  50),
    removeHov  = Color3.fromRGB(150,  65,  65),
    muted      = Color3.fromRGB(100, 100, 100),
}

local PropSelector = {}
PropSelector.__index = PropSelector

function PropSelector.new(parent)
    local self = setmetatable({}, PropSelector)

    local eTrack = Instance.new("BindableEvent")
    self.onTrackPartRequested = eTrack.Event
    self._eTrack = eTrack

    local eToggle = Instance.new("BindableEvent")
    self.onPropToggled = eToggle.Event
    self._eToggle = eToggle

    local eRemove = Instance.new("BindableEvent")
    self.onPropRemoved = eRemove.Event
    self._eRemove = eRemove

    -- "Track Part" row
    local trackRow = Instance.new("Frame")
    trackRow.Name          = "TrackPartRow"
    trackRow.Size          = UDim2.new(1, 0, 0, 24)
    trackRow.BackgroundTransparency = 1
    trackRow.LayoutOrder   = 1
    trackRow.Parent        = parent

    local trackBtn = Instance.new("TextButton")
    trackBtn.Size             = UDim2.new(0, 0, 1, 0)
    trackBtn.AutomaticSize    = Enum.AutomaticSize.X
    trackBtn.BackgroundColor3 = C.btnBg
    trackBtn.BorderSizePixel  = 0
    trackBtn.TextColor3       = C.btnText
    trackBtn.Text             = "  + Track Part  "
    trackBtn.TextSize         = 12
    trackBtn.Font             = Enum.Font.Gotham
    trackBtn.AutoButtonColor  = false
    trackBtn.Parent           = trackRow
    Instance.new("UICorner", trackBtn).CornerRadius = UDim.new(0, 4)
    trackBtn.MouseEnter:Connect(function() trackBtn.BackgroundColor3 = C.btnHover end)
    trackBtn.MouseLeave:Connect(function() trackBtn.BackgroundColor3 = C.btnBg   end)
    trackBtn.MouseButton1Click:Connect(function() eTrack:Fire() end)

    -- Props container — rows appended dynamically
    local propsContainer = Instance.new("Frame")
    propsContainer.Name          = "PropsContainer"
    propsContainer.Size          = UDim2.new(1, 0, 0, 0)
    propsContainer.AutomaticSize = Enum.AutomaticSize.Y
    propsContainer.BackgroundTransparency = 1
    propsContainer.LayoutOrder   = 2
    propsContainer.Parent        = parent

    local pcl = Instance.new("UIListLayout")
    pcl.FillDirection = Enum.FillDirection.Vertical
    pcl.SortOrder     = Enum.SortOrder.LayoutOrder
    pcl.Padding       = UDim.new(0, 3)
    pcl.Parent        = propsContainer

    self._propsContainer = propsContainer
    self._props          = {}   -- { [propName] = { active, row, btn } }
    self._parts          = {}   -- { [propName] = BasePart }
    self._order          = 0

    return self
end

function PropSelector:addProp(propName, part)
    if self._props[propName] then return end
    self._parts[propName] = part
    self._order += 1

    local row = Instance.new("Frame")
    row.Name          = "PropRow_" .. propName
    row.Size          = UDim2.new(1, 0, 0, 26)
    row.BackgroundTransparency = 1
    row.LayoutOrder   = self._order
    row.Parent        = self._propsContainer

    -- Toggle button fills left side
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Position         = UDim2.new(0, 0, 0, 0)
    toggleBtn.Size             = UDim2.new(1, -30, 1, 0)
    toggleBtn.BackgroundColor3 = C.btnActive
    toggleBtn.BorderSizePixel  = 0
    toggleBtn.TextColor3       = C.btnText
    toggleBtn.Text             = "  " .. propName
    toggleBtn.TextSize         = 12
    toggleBtn.Font             = Enum.Font.Gotham
    toggleBtn.AutoButtonColor  = false
    toggleBtn.TextXAlignment   = Enum.TextXAlignment.Left
    toggleBtn.TextTruncate     = Enum.TextTruncate.AtEnd
    toggleBtn.Parent           = row
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 4)

    -- × remove button on the right
    local removeBtn = Instance.new("TextButton")
    removeBtn.AnchorPoint      = Vector2.new(1, 0)
    removeBtn.Position         = UDim2.new(1, 0, 0, 0)
    removeBtn.Size             = UDim2.new(0, 26, 1, 0)
    removeBtn.BackgroundColor3 = C.removeBg
    removeBtn.BorderSizePixel  = 0
    removeBtn.TextColor3       = C.btnText
    removeBtn.Text             = "×"
    removeBtn.TextSize         = 14
    removeBtn.Font             = Enum.Font.Gotham
    removeBtn.AutoButtonColor  = false
    removeBtn.Parent           = row
    Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 4)

    local entry = { active = true, row = row, btn = toggleBtn }
    self._props[propName] = entry

    local function refreshToggle()
        toggleBtn.BackgroundColor3 = entry.active and C.btnActive or C.btnBg
    end

    toggleBtn.MouseButton1Click:Connect(function()
        entry.active = not entry.active
        refreshToggle()
        self._eToggle:Fire(propName, entry.active)
    end)
    toggleBtn.MouseEnter:Connect(function()
        toggleBtn.BackgroundColor3 = entry.active and C.btnActHov or C.btnHover
    end)
    toggleBtn.MouseLeave:Connect(function() refreshToggle() end)

    removeBtn.MouseEnter:Connect(function() removeBtn.BackgroundColor3 = C.removeHov end)
    removeBtn.MouseLeave:Connect(function() removeBtn.BackgroundColor3 = C.removeBg  end)
    local capturedName = propName
    removeBtn.MouseButton1Click:Connect(function()
        self._eRemove:Fire(capturedName)
    end)
end

function PropSelector:removeProp(propName)
    local entry = self._props[propName]
    if not entry then return end
    entry.row:Destroy()
    self._props[propName] = nil
    self._parts[propName] = nil
end

-- Returns { [propName] = BasePart } for all active (checked) props that have a linked part.
function PropSelector:getActiveProps()
    local result = {}
    for name, entry in pairs(self._props) do
        if entry.active and self._parts[name] then
            result[name] = self._parts[name]
        end
    end
    return result
end

function PropSelector:destroy()
    self._eTrack:Destroy()
    self._eToggle:Destroy()
    self._eRemove:Destroy()
end

return PropSelector
