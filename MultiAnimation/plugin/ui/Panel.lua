-- Panel — root UI layout for the MultiAnimation dock widget.
--
-- Sections:
--   RIGS IN SCENE   — RigSelector toggle buttons + Refresh
--   TIMELINE        — TrackLane rows, one per rig
--   CONTROLS        — scrubber, frame nav, Add Keyframe, Preview, Export
--
-- Events fired (consumed by init.server.lua):
--   onRefreshRequested
--   onAddKeyframeRequested
--   onFrameChanged(frame)            ← step buttons, textbox, scrubber drag
--   onMarkerClicked(rigName, frame)  ← clicking a dot on a TrackLane
--   onPreviewRequested
--   onStopRequested
--   onExportRequested
--   onScrubBegan()                   ← drag start (pause ChangeHistory)
--   onScrubEnded()                   ← drag end   (resume ChangeHistory)
--   onPrevKeyframeRequested
--   onNextKeyframeRequested
--
-- Methods called by init.server.lua:
--   panel:setRigs(rigsTable)
--   panel:getActiveRigs()
--   panel:addKeyframeMarker(rigName, frame)
--   panel:removeKeyframeMarker(rigName, frame)
--   panel:setFrameDisplay(current, total)
--   panel:setFrameCount(n)
--   panel:setPlaybackState(isPlaying)   ← dims/enables buttons

local RigSelector = require(script.Parent.RigSelector)
local TrackLane   = require(script.Parent.TrackLane)
local Scrubber    = require(script.Parent.Scrubber)

local C = {
    bg        = Color3.fromRGB(46,  46,  46),
    sectionBg = Color3.fromRGB(37,  37,  37),
    header    = Color3.fromRGB(140, 140, 140),
    divider   = Color3.fromRGB(62,  62,  62),
    btnBg     = Color3.fromRGB(68,  68,  68),
    btnHover  = Color3.fromRGB(90,  90,  90),
    btnAccent = Color3.fromRGB(0,  148, 214),
    btnAccHov = Color3.fromRGB(30, 170, 240),
    btnDim    = Color3.fromRGB(50,  50,  50),
    btnText   = Color3.fromRGB(210, 210, 210),
    btnDimTxt = Color3.fromRGB(100, 100, 100),
    muted     = Color3.fromRGB(100, 100, 100),
    inputBg   = Color3.fromRGB(55,  55,  55),
    inputText = Color3.fromRGB(220, 220, 220),
}

local Panel = {}
Panel.__index = Panel

-- ── helpers ───────────────────────────────────────────────────────────────────

local function listLayout(parent, dir, padding, order)
    local l = Instance.new("UIListLayout")
    l.FillDirection = dir or Enum.FillDirection.Vertical
    l.SortOrder     = Enum.SortOrder.LayoutOrder
    l.Padding       = UDim.new(0, padding or 4)
    if order then l.LayoutOrder = order end
    l.Parent = parent
    return l
end

local function addPadding(parent, h, v)
    local p = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, h or 8)
    p.PaddingRight  = UDim.new(0, h or 8)
    p.PaddingTop    = UDim.new(0, v or 6)
    p.PaddingBottom = UDim.new(0, v or 6)
    p.Parent = parent
end

local function section(parent, title, order)
    local f = Instance.new("Frame")
    f.Name            = "Sec_" .. title:gsub("%W", "_")
    f.Size            = UDim2.new(1, 0, 0, 0)
    f.AutomaticSize   = Enum.AutomaticSize.Y
    f.BackgroundColor3 = C.sectionBg
    f.BorderSizePixel = 0
    f.LayoutOrder     = order
    f.Parent          = parent
    listLayout(f, Enum.FillDirection.Vertical, 4)
    addPadding(f, 8, 6)
    local hdr = Instance.new("TextLabel")
    hdr.Size             = UDim2.new(1, 0, 0, 13)
    hdr.BackgroundTransparency = 1
    hdr.TextColor3       = C.header
    hdr.Text             = title
    hdr.TextSize         = 10
    hdr.Font             = Enum.Font.GothamBold
    hdr.TextXAlignment   = Enum.TextXAlignment.Left
    hdr.LayoutOrder      = 0
    hdr.Parent           = f
    return f
end

local function divider(parent, order)
    local d = Instance.new("Frame")
    d.Size             = UDim2.new(1, 0, 0, 1)
    d.BackgroundColor3 = C.divider
    d.BorderSizePixel  = 0
    d.LayoutOrder      = order
    d.Parent           = parent
end

local function hrow(parent, order, gap)
    local f = Instance.new("Frame")
    f.Size          = UDim2.new(1, 0, 0, 0)
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.BackgroundTransparency = 1
    f.LayoutOrder   = order
    f.Parent        = parent
    listLayout(f, Enum.FillDirection.Horizontal, gap or 4)
    return f
end

local function btn(parent, text, order, accent)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 0, 0, 24)
    b.AutomaticSize    = Enum.AutomaticSize.X
    b.BackgroundColor3 = accent and C.btnAccent or C.btnBg
    b.BorderSizePixel  = 0
    b.TextColor3       = C.btnText
    b.Text             = "  " .. text .. "  "
    b.TextSize         = 12
    b.Font             = Enum.Font.Gotham
    b.AutoButtonColor  = false
    b.LayoutOrder      = order or 1
    b.Parent           = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    local hov = accent and C.btnAccHov or C.btnHover
    local def = accent and C.btnAccent or C.btnBg
    b.MouseEnter:Connect(function() if b.Active then b.BackgroundColor3 = hov end end)
    b.MouseLeave:Connect(function() if b.Active then b.BackgroundColor3 = def end end)
    return b
end

local function smallBtn(parent, text, order)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 26, 0, 22)
    b.BackgroundColor3 = C.btnBg
    b.BorderSizePixel  = 0
    b.TextColor3       = C.btnText
    b.Text             = text
    b.TextSize         = 13
    b.Font             = Enum.Font.Gotham
    b.AutoButtonColor  = false
    b.LayoutOrder      = order or 1
    b.Parent           = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = C.btnHover end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = C.btnBg   end)
    return b
end

local function textBox(parent, default, width, order)
    local box = Instance.new("TextBox")
    box.Size             = UDim2.new(0, width or 44, 0, 22)
    box.BackgroundColor3 = C.inputBg
    box.BorderSizePixel  = 0
    box.TextColor3       = C.inputText
    box.Text             = tostring(default)
    box.TextSize         = 12
    box.Font             = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.LayoutOrder      = order or 1
    box.Parent           = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    return box
end

local function lbl(parent, text, w, order)
    local l = Instance.new("TextLabel")
    l.Size             = UDim2.new(0, w or 0, 0, 22)
    l.AutomaticSize    = (w == nil) and Enum.AutomaticSize.X or Enum.AutomaticSize.None
    l.BackgroundTransparency = 1
    l.TextColor3       = C.muted
    l.Text             = text
    l.TextSize         = 11
    l.Font             = Enum.Font.Gotham
    l.TextXAlignment   = Enum.TextXAlignment.Left
    l.LayoutOrder      = order or 1
    l.Parent           = parent
    return l
end

-- ── Panel.new ─────────────────────────────────────────────────────────────────

function Panel.new(widget)
    local self = setmetatable({}, Panel)

    -- Events
    local evts = {}
    local function mkEvent(name)
        local e = Instance.new("BindableEvent")
        self[name] = e.Event
        table.insert(evts, e)
        return e
    end
    local eRefresh  = mkEvent("onRefreshRequested")
    local eAddKF    = mkEvent("onAddKeyframeRequested")
    local eFrame    = mkEvent("onFrameChanged")
    local eMarker   = mkEvent("onMarkerClicked")
    local ePreview  = mkEvent("onPreviewRequested")
    local eStop     = mkEvent("onStopRequested")
    local eExport   = mkEvent("onExportRequested")
    local eScrubBgn = mkEvent("onScrubBegan")
    local eScrubEnd = mkEvent("onScrubEnded")
    local ePrevKF   = mkEvent("onPrevKeyframeRequested")
    local eNextKF   = mkEvent("onNextKeyframeRequested")
    local eRewind   = mkEvent("onRewindRequested")
    local eFF       = mkEvent("onFastForwardRequested")
    local eSave     = mkEvent("onSaveRequested")
    local eReload   = mkEvent("onReloadRequested")
    self._evts = evts

    self._trackLanes   = {}
    self._frameCount   = 120
    self._currentFrame = 1
    self._isPlaying    = false

    -- Root
    local root = Instance.new("Frame")
    root.Name             = "MultiAnimRoot"
    root.Size             = UDim2.new(1, 0, 1, 0)
    root.BackgroundColor3 = C.bg
    root.BorderSizePixel  = 0
    root.Parent           = widget
    listLayout(root, Enum.FillDirection.Vertical, 2)

    -- ── RIGS ─────────────────────────────────────────────────────────────────
    local rigsSec = section(root, "RIGS IN SCENE", 1)
    self.rigSelector = RigSelector.new(rigsSec)
    divider(rigsSec, 5)
    local sessionRow = hrow(rigsSec, 6, 4)
    local refreshBtn = btn(sessionRow, "↺  Refresh", 1)
    local saveBtn    = btn(sessionRow, "Save",       2)
    local reloadBtn  = btn(sessionRow, "Load",       3)
    refreshBtn.MouseButton1Click:Connect(function() eRefresh:Fire() end)
    saveBtn.MouseButton1Click:Connect(function() eSave:Fire() end)
    reloadBtn.MouseButton1Click:Connect(function() eReload:Fire() end)

    divider(root, 2)

    -- ── TIMELINE ─────────────────────────────────────────────────────────────
    local tlSec = section(root, "TIMELINE", 3)
    self._tlSec = tlSec

    divider(root, 4)

    -- ── CONTROLS ─────────────────────────────────────────────────────────────
    local ctrlSec = section(root, "CONTROLS", 5)

    -- Row 1: frame navigation
    local navRow = hrow(ctrlSec, 1, 4)

    local prevKFBtn  = smallBtn(navRow, "|◄", 1)
    local prevFrBtn  = smallBtn(navRow, "◄",  2)
    lbl(navRow, "Frame:", 38, 3)
    local frameBox   = textBox(navRow, "1",   36, 4)
    local nextFrBtn  = smallBtn(navRow, "►",  5)
    local nextKFBtn  = smallBtn(navRow, "►|", 6)
    lbl(navRow, "/", 8, 7)
    local totalBox   = textBox(navRow, "120", 36, 8)
    lbl(navRow, "fps:", 26, 9)
    local fpsBox     = textBox(navRow, "24",  28, 10)

    self._frameBox = frameBox
    self._totalBox = totalBox
    self._fpsBox   = fpsBox

    -- Row 2: scrubber
    local scrubRow = Instance.new("Frame")
    scrubRow.Name          = "ScrubRow"
    scrubRow.Size          = UDim2.new(1, 0, 0, 0)
    scrubRow.AutomaticSize = Enum.AutomaticSize.Y
    scrubRow.BackgroundTransparency = 1
    scrubRow.LayoutOrder   = 2
    scrubRow.Parent        = ctrlSec

    self._scrubber = Scrubber.new(scrubRow, 120, 1, widget)
    self._scrubber.onFrameChanged:Connect(function(f)
        self._currentFrame = f
        if frameBox then frameBox.Text = tostring(f) end
        eFrame:Fire(f)
    end)
    self._scrubber.onDragBegan:Connect(function() eScrubBgn:Fire() end)
    self._scrubber.onDragEnded:Connect(function() eScrubEnd:Fire() end)

    -- Row 3: scene name input
    local sceneRow     = hrow(ctrlSec, 3, 4)
    lbl(sceneRow, "Scene:", 42, 1)
    local sceneNameBox = textBox(sceneRow, "Scene_001", 120, 2)
    self._sceneNameBox = sceneNameBox

    -- Row 4: action buttons
    local actRow = hrow(ctrlSec, 4, 4)

    local addKFBtn  = btn(actRow, "+ Add Keyframe", 1, true)
    local previewBtn = btn(actRow, "▶  Preview",     2)
    local stopBtn    = btn(actRow, "■  Stop",         3)
    local exportBtn  = btn(actRow, "⬆  Export",       4)

    self._addKFBtn   = addKFBtn
    self._previewBtn = previewBtn
    self._stopBtn    = stopBtn

    -- ── Wire controls ─────────────────────────────────────────────────────────

    addKFBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eAddKF:Fire() end
    end)
    previewBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then ePreview:Fire() end
    end)
    stopBtn.MouseButton1Click:Connect(function()
        eStop:Fire()
    end)
    exportBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eExport:Fire(sceneNameBox.Text) end
    end)

    prevKFBtn.MouseButton1Click:Connect(function() eRewind:Fire() end)   -- |◄ = go to frame 1
    nextKFBtn.MouseButton1Click:Connect(function() eFF:Fire() end)       -- ►| = go to last frame

    prevFrBtn.MouseButton1Click:Connect(function()                        -- ◄ = step -1
        local f = math.max(1, self._currentFrame - 1)
        eFrame:Fire(f)
    end)
    nextFrBtn.MouseButton1Click:Connect(function()                        -- ► = step +1
        local f = math.min(self._frameCount, self._currentFrame + 1)
        eFrame:Fire(f)
    end)

    -- Frame textbox commit
    frameBox.FocusLost:Connect(function()
        local n = tonumber(frameBox.Text)
        if n then
            n = math.clamp(math.floor(n), 1, self._frameCount)
            eFrame:Fire(n)
        else
            frameBox.Text = tostring(self._currentFrame)
        end
    end)

    -- Total frame count textbox commit
    totalBox.FocusLost:Connect(function()
        local n = tonumber(totalBox.Text)
        if n then
            n = math.max(2, math.floor(n))
            self:setFrameCount(n)
        else
            totalBox.Text = tostring(self._frameCount)
        end
    end)

    self._root = root
    return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Panel:setRigs(rigs)
    self.rigSelector:setRigs(rigs)

    for _, lane in pairs(self._trackLanes) do lane:destroy() end
    self._trackLanes = {}

    local order = 1
    for name in pairs(rigs) do
        local lane = TrackLane.new(self._tlSec, name, self._frameCount, order)
        lane.onMarkerClicked:Connect(function(frame)
            self._evts[4]:Fire(name, frame)   -- eMarker
        end)
        self._trackLanes[name] = lane
        order += 1
    end

    local empty = self._tlSec:FindFirstChild("__tlEmpty")
    if next(rigs) == nil then
        if not empty then
            local l = Instance.new("TextLabel")
            l.Name = "__tlEmpty"
            l.Size = UDim2.new(1, 0, 0, 20)
            l.BackgroundTransparency = 1
            l.TextColor3 = C.muted
            l.Text = "— no rigs — press Refresh"
            l.TextSize = 11
            l.Font = Enum.Font.Gotham
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.LayoutOrder = 99
            l.Parent = self._tlSec
        end
    else
        if empty then empty:Destroy() end
    end
end

function Panel:getActiveRigs()
    return self.rigSelector:getActiveRigs()
end

function Panel:addKeyframeMarker(rigName, frame)
    local lane = self._trackLanes[rigName]
    if lane then lane:addMarker(frame) end
end

function Panel:removeKeyframeMarker(rigName, frame)
    local lane = self._trackLanes[rigName]
    if lane then lane:removeMarker(frame) end
end

function Panel:setFrameDisplay(current, total)
    self._currentFrame = current
    if total then self._frameCount = total end
    if self._frameBox then self._frameBox.Text = tostring(current) end
    if total and self._totalBox then self._totalBox.Text = tostring(total) end
    if self._scrubber then self._scrubber:setFrame(current) end
    for _, lane in pairs(self._trackLanes) do
        lane:setActiveFrame(current)
    end
end

function Panel:setFrameCount(n)
    self._frameCount = n
    if self._totalBox then self._totalBox.Text = tostring(n) end
    if self._scrubber then self._scrubber:setFrameCount(n) end
    for _, lane in pairs(self._trackLanes) do
        lane:setFrameCount(n)
    end
end

-- Dim/restore buttons during playback
function Panel:setPlaybackState(isPlaying)
    self._isPlaying = isPlaying
    if self._addKFBtn then
        self._addKFBtn.BackgroundColor3 = isPlaying and C.btnDim or C.btnAccent
        self._addKFBtn.TextColor3 = isPlaying and C.btnDimTxt or C.btnText
    end
    if self._previewBtn then
        self._previewBtn.BackgroundColor3 = isPlaying and C.btnDim or C.btnBg
        self._previewBtn.TextColor3 = isPlaying and C.btnDimTxt or C.btnText
    end
end

function Panel:destroy()
    if self._scrubber then self._scrubber:destroy() end
    for _, e in ipairs(self._evts) do e:Destroy() end
    for _, lane in pairs(self._trackLanes) do lane:destroy() end
    self.rigSelector:destroy()
end

return Panel
