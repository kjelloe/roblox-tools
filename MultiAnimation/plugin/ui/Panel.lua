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

local function _relTime(ts)
    local d = os.time() - ts
    if d < 60      then return "just now"
    elseif d < 3600   then return math.floor(d / 60)   .. "m ago"
    elseif d < 86400  then return math.floor(d / 3600) .. "h ago"
    elseif d < 172800 then return "yesterday"
    else return math.floor(d / 86400) .. "d ago"
    end
end

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
    local eSave     = mkEvent("onSaveConfirmed")
    local eReload   = mkEvent("onLoadRequested")
    local eMarkerDel = Instance.new("BindableEvent")
    self.onMarkerDeleteRequested = eMarkerDel.Event
    self._eMarkerDel = eMarkerDel
    table.insert(evts, eMarkerDel)

    local eTimeDbl = Instance.new("BindableEvent")
    self.onTimelineDoubleClicked = eTimeDbl.Event
    self._eTimeDbl = eTimeDbl
    table.insert(evts, eTimeDbl)

    local eLoadNamed = Instance.new("BindableEvent")
    self.onLoadNamedRequested = eLoadNamed.Event
    self._eLoadNamed = eLoadNamed
    table.insert(evts, eLoadNamed)

    self._evts = evts
    self._lastSaveName = nil

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
    local saveAsBtn  = btn(sessionRow, "Save As",    2)
    local loadBtn    = btn(sessionRow, "Load",        3)
    refreshBtn.MouseButton1Click:Connect(function() eRefresh:Fire() end)
    saveAsBtn.MouseButton1Click:Connect(function() self:_showSaveOverlay() end)
    loadBtn.MouseButton1Click:Connect(function() eReload:Fire() end)

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

    -- ── Save As overlay ───────────────────────────────────────────────────────
    local saveOv = Instance.new("Frame")
    saveOv.Name            = "SaveOverlay"
    saveOv.Size            = UDim2.new(0, 234, 0, 108)
    saveOv.AnchorPoint     = Vector2.new(0.5, 0.5)
    saveOv.Position        = UDim2.new(0.5, 0, 0.5, 0)
    saveOv.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    saveOv.BorderSizePixel = 0
    saveOv.ZIndex          = 50
    saveOv.Visible         = false
    saveOv.Parent          = widget
    Instance.new("UICorner", saveOv).CornerRadius = UDim.new(0, 6)
    local _sStroke = Instance.new("UIStroke")
    _sStroke.Color     = Color3.fromRGB(90, 90, 90)
    _sStroke.Thickness = 1
    _sStroke.Parent    = saveOv
    listLayout(saveOv, Enum.FillDirection.Vertical, 8)
    addPadding(saveOv, 10, 10)

    local saveOvHdr = Instance.new("TextLabel")
    saveOvHdr.Size               = UDim2.new(1, 0, 0, 13)
    saveOvHdr.BackgroundTransparency = 1
    saveOvHdr.TextColor3         = C.header
    saveOvHdr.Text               = "SAVE AS"
    saveOvHdr.TextSize           = 10
    saveOvHdr.Font               = Enum.Font.GothamBold
    saveOvHdr.TextXAlignment     = Enum.TextXAlignment.Left
    saveOvHdr.LayoutOrder        = 1
    saveOvHdr.Parent             = saveOv

    local saveOvBox = textBox(saveOv, "Scene_001", 0, 2)
    saveOvBox.Size          = UDim2.new(1, 0, 0, 26)
    saveOvBox.AutomaticSize = Enum.AutomaticSize.None

    local saveOvRow    = hrow(saveOv, 3, 6)
    local saveOvOk     = btn(saveOvRow, "Save",   1, true)
    local saveOvCancel = btn(saveOvRow, "Cancel", 2)

    local function _doSave()
        local name = saveOvBox.Text:match("^%s*(.-)%s*$")
        if name ~= "" then
            self._lastSaveName = name
            saveOv.Visible = false
            eSave:Fire(name)
        end
    end
    saveOvBox.FocusLost:Connect(function(enter) if enter then _doSave() end end)
    saveOvOk.MouseButton1Click:Connect(_doSave)
    saveOvCancel.MouseButton1Click:Connect(function() saveOv.Visible = false end)

    self._saveOverlay = saveOv
    self._saveOvBox   = saveOvBox

    -- ── Load list overlay ─────────────────────────────────────────────────────
    local loadOv = Instance.new("Frame")
    loadOv.Name             = "LoadOverlay"
    loadOv.Size             = UDim2.new(1, 0, 1, 0)
    loadOv.BackgroundColor3 = C.bg
    loadOv.BorderSizePixel  = 0
    loadOv.ZIndex           = 50
    loadOv.Visible          = false
    loadOv.Parent           = widget

    local loadHdr = Instance.new("Frame")
    loadHdr.Size             = UDim2.new(1, 0, 0, 34)
    loadHdr.BackgroundColor3 = C.sectionBg
    loadHdr.BorderSizePixel  = 0
    loadHdr.ZIndex           = 51
    loadHdr.Parent           = loadOv

    local loadHdrTitle = Instance.new("TextLabel")
    loadHdrTitle.Size               = UDim2.new(1, -34, 1, 0)
    loadHdrTitle.Position           = UDim2.new(0, 10, 0, 0)
    loadHdrTitle.BackgroundTransparency = 1
    loadHdrTitle.TextColor3         = C.header
    loadHdrTitle.Text               = "LOAD SESSION"
    loadHdrTitle.TextSize           = 10
    loadHdrTitle.Font               = Enum.Font.GothamBold
    loadHdrTitle.TextXAlignment     = Enum.TextXAlignment.Left
    loadHdrTitle.ZIndex             = 52
    loadHdrTitle.Parent             = loadHdr

    local loadHdrClose = Instance.new("TextButton")
    loadHdrClose.Size               = UDim2.new(0, 34, 1, 0)
    loadHdrClose.Position           = UDim2.new(1, -34, 0, 0)
    loadHdrClose.BackgroundTransparency = 1
    loadHdrClose.TextColor3         = C.muted
    loadHdrClose.Text               = "✕"
    loadHdrClose.TextSize           = 14
    loadHdrClose.Font               = Enum.Font.Gotham
    loadHdrClose.ZIndex             = 52
    loadHdrClose.Parent             = loadHdr
    loadHdrClose.MouseButton1Click:Connect(function() loadOv.Visible = false end)

    local loadScroll = Instance.new("ScrollingFrame")
    loadScroll.Size                 = UDim2.new(1, 0, 1, -34)
    loadScroll.Position             = UDim2.new(0, 0, 0, 34)
    loadScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
    loadScroll.ScrollBarThickness   = 5
    loadScroll.ScrollBarImageColor3 = C.btnBg
    loadScroll.BackgroundTransparency = 1
    loadScroll.BorderSizePixel      = 0
    loadScroll.ZIndex               = 51
    loadScroll.Parent               = loadOv

    local _scrollLayout = Instance.new("UIListLayout")
    _scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    _scrollLayout.Padding   = UDim.new(0, 1)
    _scrollLayout.Parent    = loadScroll

    self._loadOverlay = loadOv
    self._loadScroll  = loadScroll

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
        lane.onMarkerDeleteRequested:Connect(function(frame)
            self._eMarkerDel:Fire(name, frame)
        end)
        lane.onDoubleClicked:Connect(function(frame)
            self._eTimeDbl:Fire(name, frame)
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

function Panel:setActiveRigs(rigNames)
    self.rigSelector:setActiveRigs(rigNames)
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

function Panel:_showSaveOverlay()
    self._saveOvBox.Text = self._lastSaveName or "Scene_001"
    self._saveOverlay.Visible = true
    task.defer(function()
        if self._saveOvBox and self._saveOvBox.Parent then
            self._saveOvBox:CaptureFocus()
        end
    end)
end

local _ROW_H = 36

function Panel:showLoadList(saves)
    for _, c in ipairs(self._loadScroll:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    if #saves == 0 then
        local e = Instance.new("TextLabel")
        e.Size               = UDim2.new(1, 0, 0, 40)
        e.BackgroundTransparency = 1
        e.TextColor3         = C.muted
        e.Text               = "No saved sessions"
        e.TextSize           = 11
        e.Font               = Enum.Font.Gotham
        e.TextXAlignment     = Enum.TextXAlignment.Center
        e.LayoutOrder        = 1
        e.Parent             = self._loadScroll
        self._loadScroll.CanvasSize = UDim2.new(0, 0, 0, 40)
    else
        for i, entry in ipairs(saves) do
            local rowBg = (i % 2 == 0) and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(46, 46, 46)
            local row = Instance.new("TextButton")
            row.Size             = UDim2.new(1, 0, 0, _ROW_H)
            row.BackgroundColor3 = rowBg
            row.BorderSizePixel  = 0
            row.Text             = ""
            row.AutoButtonColor  = false
            row.ZIndex           = 52
            row.LayoutOrder      = i
            row.Parent           = self._loadScroll

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size             = UDim2.new(1, -158, 1, 0)
            nameLbl.Position         = UDim2.new(0, 10, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.TextColor3       = C.inputText
            nameLbl.Text             = entry.name
            nameLbl.TextSize         = 12
            nameLbl.Font             = Enum.Font.Gotham
            nameLbl.TextXAlignment   = Enum.TextXAlignment.Left
            nameLbl.TextTruncate     = Enum.TextTruncate.AtEnd
            nameLbl.ZIndex           = 53
            nameLbl.Parent           = row

            local timeLbl = Instance.new("TextLabel")
            timeLbl.Size             = UDim2.new(0, 148, 1, 0)
            timeLbl.Position         = UDim2.new(1, -153, 0, 0)
            timeLbl.BackgroundTransparency = 1
            timeLbl.TextColor3       = C.muted
            timeLbl.Text             = os.date("%Y-%m-%d %H:%M:%S", entry.savedAt)
            timeLbl.TextSize         = 10
            timeLbl.Font             = Enum.Font.Gotham
            timeLbl.TextXAlignment   = Enum.TextXAlignment.Right
            timeLbl.ZIndex           = 53
            timeLbl.Parent           = row

            row.MouseEnter:Connect(function() row.BackgroundColor3 = C.btnHover end)
            row.MouseLeave:Connect(function() row.BackgroundColor3 = rowBg end)
            local name = entry.name
            row.MouseButton1Click:Connect(function() self._eLoadNamed:Fire(name) end)
        end
        self._loadScroll.CanvasSize = UDim2.new(0, 0, 0, #saves * (_ROW_H + 1))
    end
    self._loadOverlay.Visible = true
end

function Panel:hideLoadList()
    self._loadOverlay.Visible = false
end

function Panel:destroy()
    if self._scrubber then self._scrubber:destroy() end
    for _, e in ipairs(self._evts) do e:Destroy() end
    for _, lane in pairs(self._trackLanes) do lane:destroy() end
    self.rigSelector:destroy()
end

return Panel
