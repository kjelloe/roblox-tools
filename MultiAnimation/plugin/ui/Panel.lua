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

local RigSelector  = require(script.Parent.RigSelector)
local PropSelector = require(script.Parent.PropSelector)
local TrackLane    = require(script.Parent.TrackLane)
local Scrubber     = require(script.Parent.Scrubber)

local PROP_COLOUR       = Color3.fromRGB(0, 207, 207)   -- teal for prop keyframe dots
local CAMERA_COLOUR     = Color3.fromRGB(255, 150, 40)   -- orange: camera "move" keyframes
local CAMERA_CUT_COLOUR = Color3.fromRGB(255, 80, 80)    -- red: camera "cut" keyframes
local EFFECT_COLOUR     = Color3.fromRGB(190, 120, 255)  -- purple: effect event dots

local EASING_OPTIONS = {
    { text = "Linear",    easing = "Linear"    },
    { text = "Ease In",   easing = "EaseIn"    },
    { text = "Ease Out",  easing = "EaseOut"   },
    { text = "EaseInOut", easing = "EaseInOut" },
    { text = "Constant",  easing = "Constant"  },
    { text = "Bounce",    easing = "Bounce"    },
    { text = "Elastic",   easing = "Elastic"   },
}

-- Simple Mode frame icon strip
local SIMPLE_ICON_W  = 28   -- px per frame slot (icon + scrubber share this grid)
local SIMPLE_ICON_H  = 24   -- px height of the icon row

local C = {
    bg        = Color3.fromRGB(46,  46,  46),
    sectionBg = Color3.fromRGB(37,  37,  37),
    header    = Color3.fromRGB(160, 160, 160),
    divider   = Color3.fromRGB(62,  62,  62),
    btnBg     = Color3.fromRGB(68,  68,  68),
    btnHover  = Color3.fromRGB(90,  90,  90),
    btnAccent = Color3.fromRGB(0,  148, 214),
    btnAccHov = Color3.fromRGB(30, 170, 240),
    btnDim    = Color3.fromRGB(50,  50,  50),
    btnDanger    = Color3.fromRGB(160, 50,  50),
    btnDangerHov = Color3.fromRGB(195, 70,  70),
    btnText   = Color3.fromRGB(210, 210, 210),
    btnDimTxt = Color3.fromRGB(100, 100, 100),
    muted     = Color3.fromRGB(170, 170, 170),
    ovText    = Color3.fromRGB(205, 205, 205),
    iconSel   = Color3.fromRGB(100, 190, 255),  -- selected frame icon highlight
    inputBg   = Color3.fromRGB(55,  55,  55),
    inputText = Color3.fromRGB(220, 220, 220),
    warning   = Color3.fromRGB(255, 210, 60),
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

local function section(parent, title, order, rightHint)
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
    -- Header row: title on left, optional right-aligned hint on the same line.
    local hdrFrame = Instance.new("Frame")
    hdrFrame.Size             = UDim2.new(1, 0, 0, 13)
    hdrFrame.BackgroundTransparency = 1
    hdrFrame.LayoutOrder      = 0
    hdrFrame.Parent           = f
    local hdr = Instance.new("TextLabel")
    hdr.Size             = UDim2.new(1, 0, 1, 0)
    hdr.BackgroundTransparency = 1
    hdr.TextColor3       = C.header
    hdr.Text             = title
    hdr.TextSize         = 10
    hdr.Font             = Enum.Font.GothamBold
    hdr.TextXAlignment   = Enum.TextXAlignment.Left
    hdr.Parent           = hdrFrame
    if rightHint then
        local hint = Instance.new("TextLabel")
        hint.Size             = UDim2.new(1, 0, 1, 0)
        hint.BackgroundTransparency = 1
        hint.TextColor3       = C.muted
        hint.Text             = rightHint
        hint.TextSize         = 9
        hint.Font             = Enum.Font.Gotham
        hint.TextXAlignment   = Enum.TextXAlignment.Right
        hint.Parent           = hdrFrame
    end
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

-- Replace any character that is not alphanumeric or underscore with "_".
-- Applied to scene names before they are stored or fired so tags, export
-- paths, and slot keys are always safe identifiers.
local function sanitizeSceneName(name)
    if not name or name == "" then return name end
    return (name:gsub("[^%w_]", "_"))
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

local function btn(parent, text, order, accent, danger)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 0, 0, 24)
    b.AutomaticSize    = Enum.AutomaticSize.X
    b.BackgroundColor3 = danger and C.btnDanger or (accent and C.btnAccent or C.btnBg)
    b.BorderSizePixel  = 0
    b.TextColor3       = C.btnText
    b.Text             = "  " .. text .. "  "
    b.TextSize         = 12
    b.Font             = Enum.Font.Gotham
    b.AutoButtonColor  = false
    b.LayoutOrder      = order or 1
    b.Parent           = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
    local hov = danger and C.btnDangerHov or (accent and C.btnAccHov or C.btnHover)
    local def = danger and C.btnDanger    or (accent and C.btnAccent  or C.btnBg)
    b.MouseEnter:Connect(function() if b.Active then b.BackgroundColor3 = hov end end)
    b.MouseLeave:Connect(function() if b.Active then b.BackgroundColor3 = def end end)
    return b
end

local TextService = game:GetService("TextService")

-- Fixes a btn()'s width to `multiplier` times its natural (auto-sized) text
-- width, centering the label inside the extra space.
local function widenButton(b, multiplier)
    local natural = TextService:GetTextSize(b.Text, b.TextSize, b.Font, Vector2.new(2000, 100))
    b.AutomaticSize = Enum.AutomaticSize.None
    b.Size = UDim2.new(0, math.ceil(natural.X * multiplier), 0, 24)
    b.TextXAlignment = Enum.TextXAlignment.Center
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
    self._eFrame    = eFrame
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
    local eSave         = mkEvent("onSaveConfirmed")
    local eReload       = mkEvent("onLoadRequested")
    local eFileExport   = mkEvent("onFileExportRequested")
    local eFileImport   = mkEvent("onFileImportRequested")
    local eDeleteReq  = mkEvent("onDeleteRequested")
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

    local eDeleteNamed = Instance.new("BindableEvent")
    self.onDeleteNamedRequested = eDeleteNamed.Event
    self._eDeleteNamed = eDeleteNamed
    table.insert(evts, eDeleteNamed)

    local eNewSession = mkEvent("onNewSessionConfirmed")

    local eTrackPart = Instance.new("BindableEvent")
    self.onTrackPartRequested = eTrackPart.Event
    self._eTrackPart = eTrackPart
    table.insert(evts, eTrackPart)

    local ePropRemoved = Instance.new("BindableEvent")
    self.onPropRemoved = ePropRemoved.Event
    self._ePropRemoved = ePropRemoved
    table.insert(evts, ePropRemoved)

    local ePropDbl = Instance.new("BindableEvent")
    self.onPropDoubleClicked = ePropDbl.Event
    self._ePropDbl = ePropDbl
    table.insert(evts, ePropDbl)

    local ePropMarkerDel = Instance.new("BindableEvent")
    self.onPropMarkerDeleteRequested = ePropMarkerDel.Event
    self._ePropMarkerDel = ePropMarkerDel
    table.insert(evts, ePropMarkerDel)

    -- Camera track events (Phase 8)
    local eCamCapture = mkEvent("onCameraCaptureRequested")
    local eCamMode    = mkEvent("onCameraModeToggleRequested")
    self._eCamCapture = eCamCapture
    self._eCamMode    = eCamMode

    local eCamPreview = Instance.new("BindableEvent")
    self.onCameraPreviewToggled = eCamPreview.Event
    self._eCamPreview = eCamPreview
    table.insert(evts, eCamPreview)

    local eCamMarker = Instance.new("BindableEvent")
    self.onCameraMarkerClicked = eCamMarker.Event
    self._eCamMarker = eCamMarker
    table.insert(evts, eCamMarker)

    local eCamDel = Instance.new("BindableEvent")
    self.onCameraMarkerDeleteRequested = eCamDel.Event
    self._eCamDel = eCamDel
    table.insert(evts, eCamDel)

    local eCamDbl = Instance.new("BindableEvent")
    self.onCameraLaneDoubleClicked = eCamDbl.Event
    self._eCamDbl = eCamDbl
    table.insert(evts, eCamDbl)

    -- Phase 9: + Add Rig button and keyframe clipboard
    local eAddRig = mkEvent("onAddRigRequested")
    local eCopyKF = mkEvent("onCopyKeyframeRequested")

    local ePasteKF = Instance.new("BindableEvent")
    self.onPasteKeyframeRequested = ePasteKF.Event   -- fires (mirrored: bool)
    self._ePasteKF = ePasteKF
    table.insert(evts, ePasteKF)

    -- Phase 9: effect track
    local eTrackFx = mkEvent("onTrackEffectRequested")
    self._eTrackFx = eTrackFx

    -- Simple Mode
    local eMode             = mkEvent("onModeChanged")
    local eSimpleAddFrame   = mkEvent("onSimpleAddFrame")
    local eSimpleInsertFrame= mkEvent("onSimpleInsertFrame")
    local eSimpleDeleteFrame= mkEvent("onSimpleDeleteFrame")
    local eSimpleAttach     = mkEvent("onSimplePropAttach")
    local eSimpleCam          = mkEvent("onSimpleCameraToggled")
    local eSimpleFOV          = mkEvent("onSimpleFOVChanged")
    local eSimpleLook         = mkEvent("onSimpleLookThroughToggled")
    local eSimpleFPS          = mkEvent("onSimpleFPSChanged")
    local eSimpleOnion        = mkEvent("onSimpleOnionToggled")
    local eSimpleCamDeleteFrom= mkEvent("onSimpleCamDeleteFrom")
    local eTagFolderReq          = mkEvent("onTagFolderListRequested")        -- fires ()
    local eTagAllIn              = mkEvent("onTagAllInRequested")             -- fires (folder, {rigs,props,effects})
    local eClearSceneTags        = mkEvent("onClearSceneTagsRequested")       -- fires ()
    local eNewAnimation          = mkEvent("onNewAnimationRequested")         -- fires (newName)
    local eClearSceneTagsPreview = mkEvent("onClearSceneTagsPreviewRequested")-- fires ()
    local eNewAnimationPreview   = mkEvent("onNewAnimationPreviewRequested")  -- fires (newName)
    local eRefreshTags           = mkEvent("onRefreshTagsRequested")          -- fires ()
    local eSceneRenamed          = mkEvent("onSceneRenamed")                  -- fires (oldName, newName)

    -- Playback tab events
    local ePlaybackSceneChanged   = mkEvent("onPlaybackSceneChanged")    -- fires (sceneName)
    local ePlaybackRig            = Instance.new("BindableEvent")        -- fires (rigName, entry)
    self.onPlaybackRigChanged     = ePlaybackRig.Event
    self._ePlaybackRig            = ePlaybackRig
    table.insert(evts, ePlaybackRig)
    local ePlaybackParams         = mkEvent("onPlaybackParamsChanged")   -- fires ({fps,loop,movieMode})
    local eAutoPads               = mkEvent("onAutoPadsToggled")          -- fires (bool)
    local ePlaybackCopy           = mkEvent("onPlaybackCopySnippet")
    local ePlaybackPreview        = mkEvent("onPlaybackPreview")

    local eFxRemoved = Instance.new("BindableEvent")
    self.onEffectRemoved = eFxRemoved.Event
    self._eFxRemoved = eFxRemoved
    table.insert(evts, eFxRemoved)

    local eFxCycle = Instance.new("BindableEvent")
    self.onEffectActionCycleRequested = eFxCycle.Event   -- fires (name)
    self._eFxCycle = eFxCycle
    table.insert(evts, eFxCycle)

    local eFxDbl = Instance.new("BindableEvent")
    self.onEffectDoubleClicked = eFxDbl.Event            -- fires (name, frame)
    self._eFxDbl = eFxDbl
    table.insert(evts, eFxDbl)

    local eFxMarker = Instance.new("BindableEvent")
    self.onEffectMarkerClicked = eFxMarker.Event         -- fires (name, frame)
    self._eFxMarker = eFxMarker
    table.insert(evts, eFxMarker)

    local eFxDel = Instance.new("BindableEvent")
    self.onEffectMarkerDeleteRequested = eFxDel.Event    -- fires (name, frame)
    self._eFxDel = eFxDel
    table.insert(evts, eFxDel)

    local eMarkerEasing = Instance.new("BindableEvent")
    self.onMarkerEasingChanged = eMarkerEasing.Event     -- fires (trackType, name, frame, easing)
    self._eMarkerEasing = eMarkerEasing
    table.insert(evts, eMarkerEasing)

    local eSimpleEasing = Instance.new("BindableEvent")
    self.onSimpleEasingChanged = eSimpleEasing.Event     -- fires (easing)
    self._eSimpleEasing = eSimpleEasing
    table.insert(evts, eSimpleEasing)

    self.onFileExportRequested = eFileExport.Event
    self.onFileImportRequested = eFileImport.Event
    table.insert(evts, eFileExport)
    table.insert(evts, eFileImport)

    -- SpawnedEffects events
    local eSpawnedFxAdd     = mkEvent("onSpawnedFxAdded")       -- fires (data{frame,effectType,posX/Y/Z,...params})
    local eSpawnedFxUpdate  = mkEvent("onSpawnedFxUpdated")     -- fires (data{id,...params})
    local eSpawnedFxDelete  = mkEvent("onSpawnedFxDeleted")     -- fires (id)
    local eSpawnedFxPickPos = mkEvent("onSpawnedFxPickPosRequested") -- fires ()

    -- Subtitle events
    local eSubtitleEnabled = mkEvent("onSubtitleEnabledChanged") -- fires (bool)
    local eSubtitleText    = mkEvent("onSubtitleTextChanged")    -- fires (text)
    local eSubtitleShow    = mkEvent("onSubtitleShowChanged")    -- fires (frame, bool)
    local eSubtitleStyle   = mkEvent("onSubtitleStyleChanged")   -- fires (styleTable)

    self._evts = evts
    self._lastSaveName = nil

    self._trackLanes      = {}
    self._propTrackLanes  = {}
    self._effectLanes     = {}     -- { [effectName] = TrackLane }
    self._effectChips     = {}     -- { [effectName] = chip container Frame }
    self._cameraLane      = nil    -- created lazily on first camera keyframe
    self._camPreviewOn   = false
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

    -- ── Mode toggle (Simple / Advanced) — always visible, never hidden ────────
    self._mode = "advanced"
    local modeRow = hrow(root, 0, 4)

    local function modeToggleBtn(text, order)
        local b = Instance.new("TextButton")
        b.Size             = UDim2.new(0, 0, 0, 24)
        b.AutomaticSize    = Enum.AutomaticSize.X
        b.BackgroundColor3 = C.btnBg
        b.BorderSizePixel  = 0
        b.TextColor3       = C.btnText
        b.Text             = "  " .. text .. "  "
        b.TextSize         = 12
        b.Font             = Enum.Font.GothamBold
        b.AutoButtonColor  = false
        b.LayoutOrder      = order
        b.Parent           = modeRow
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        return b
    end

    local modeSimpleBtn   = modeToggleBtn("Simple",   1)
    local modeAdvBtn      = modeToggleBtn("Advanced", 2)
    local modePlaybackBtn = modeToggleBtn("Playback", 3)

    local function refreshModeButtons()
        modeSimpleBtn.BackgroundColor3   = (self._mode == "simple")   and C.btnAccent or C.btnBg
        modeAdvBtn.BackgroundColor3      = (self._mode == "advanced") and C.btnAccent or C.btnBg
        modePlaybackBtn.BackgroundColor3 = (self._mode == "playback") and C.btnAccent or C.btnBg
    end
    refreshModeButtons()
    self._refreshModeButtons = refreshModeButtons

    modeSimpleBtn.MouseButton1Click:Connect(function()
        if self._isPlaying or self._mode == "simple" then return end
        self._mode = "simple"
        refreshModeButtons()
        self:_applyModeVisibility()
        eMode:Fire("simple")
    end)
    modeAdvBtn.MouseButton1Click:Connect(function()
        if self._isPlaying or self._mode == "advanced" then return end
        self._mode = "advanced"
        refreshModeButtons()
        self:_applyModeVisibility()
        eMode:Fire("advanced")
    end)
    modePlaybackBtn.MouseButton1Click:Connect(function()
        if self._isPlaying or self._mode == "playback" then return end
        self._mode = "playback"
        refreshModeButtons()
        self:_applyModeVisibility()
        eMode:Fire("playback")
    end)

    -- ── Advanced-mode wrapper — every Advanced section lives in here so the
    -- whole set can be hidden/shown as one unit when the mode toggles. ──────
    local advancedWrap = Instance.new("Frame")
    advancedWrap.Name             = "AdvancedWrap"
    advancedWrap.Size             = UDim2.new(1, 0, 0, 0)
    advancedWrap.AutomaticSize    = Enum.AutomaticSize.Y
    advancedWrap.BackgroundTransparency = 1
    advancedWrap.LayoutOrder      = 1
    advancedWrap.Parent           = root
    listLayout(advancedWrap, Enum.FillDirection.Vertical, 2)
    self._advancedWrap = advancedWrap

    -- ── RIGS ─────────────────────────────────────────────────────────────────
    local rigsSec = section(advancedWrap, "RIGS IN SCENE", 1, "K:KF   J:←   L:→   C:📷")
    self.rigSelector = RigSelector.new(rigsSec)
    divider(rigsSec, 5)
    local sessionRow = hrow(rigsSec, 6, 4)
    local refreshBtn = btn(sessionRow, "↺  Refresh", 1)
    local addRigBtn  = btn(sessionRow, "+ Rig",      2)
    local saveAsBtn  = btn(sessionRow, "Save As",    3)
    local loadBtn    = btn(sessionRow, "Load",        4)
    local newBtn     = btn(sessionRow, "New",         5)
    refreshBtn.MouseButton1Click:Connect(function() eRefresh:Fire() end)
    addRigBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eAddRig:Fire() end
    end)
    saveAsBtn.MouseButton1Click:Connect(function() self:_showSaveOverlay() end)
    loadBtn.MouseButton1Click:Connect(function() eReload:Fire() end)
    newBtn.MouseButton1Click:Connect(function() self:_showNewOverlay() end)
    do
        local xferRow = hrow(rigsSec, 7, 4)
        local exportFileBtn = btn(xferRow, "Export File", 1)
        local importFileBtn = btn(xferRow, "Import File", 2)
        exportFileBtn.MouseButton1Click:Connect(function()
            if not self._isPlaying then eFileExport:Fire() end
        end)
        importFileBtn.MouseButton1Click:Connect(function()
            if not self._isPlaying then eFileImport:Fire() end
        end)
    end

    divider(advancedWrap, 2)

    -- ── PROPS ─────────────────────────────────────────────────────────────────
    local propsSec = section(advancedWrap, "PROPS IN SCENE", 3)
    self.propSelector = PropSelector.new(propsSec)
    self.propSelector.onTrackPartRequested:Connect(function()
        self._eTrackPart:Fire()
    end)
    self.propSelector.onPropRemoved:Connect(function(propName)
        self:removeProp(propName)
        self._ePropRemoved:Fire(propName)
    end)

    -- Effects row: tracked effect chips live here. Clicking a chip cycles the
    -- effect's default action; × untracks it (data kept, like props).
    divider(propsSec, 8)
    local fxRow = hrow(propsSec, 9, 4)
    lbl(fxRow, "FX:", 24, 1)
    local trackFxBtn = btn(fxRow, "Track Effect", 2)
    trackFxBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eTrackFx:Fire() end
    end)
    self._fxRow = fxRow

    divider(advancedWrap, 4)

    -- ── TIMELINE ─────────────────────────────────────────────────────────────
    local tlSec = section(advancedWrap, "TIMELINE", 5)
    self._tlSec = tlSec

    divider(advancedWrap, 6)

    -- ── CONTROLS ─────────────────────────────────────────────────────────────
    local ctrlSec = section(advancedWrap, "CONTROLS", 7)

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

    -- Row 2: step size (frame step for , / . shortcuts)
    local stepRow = hrow(ctrlSec, 2, 4)
    lbl(stepRow, "Step:", 34, 1)
    local stepBox = textBox(stepRow, "2", 32, 2)
    local stepHint = Instance.new("TextLabel")
    stepHint.Size               = UDim2.new(0, 0, 0, 22)
    stepHint.AutomaticSize      = Enum.AutomaticSize.X
    stepHint.BackgroundTransparency = 1
    stepHint.TextColor3         = C.muted
    stepHint.Text               = "frames  ( J←  L→ )"
    stepHint.TextSize           = 10
    stepHint.Font               = Enum.Font.Gotham
    stepHint.TextXAlignment     = Enum.TextXAlignment.Left
    stepHint.LayoutOrder        = 3
    stepHint.Parent             = stepRow
    self._stepBox = stepBox

    -- Row 3: scrubber
    local scrubRow = Instance.new("Frame")
    scrubRow.Name          = "ScrubRow"
    scrubRow.Size          = UDim2.new(1, 0, 0, 0)
    scrubRow.AutomaticSize = Enum.AutomaticSize.Y
    scrubRow.BackgroundTransparency = 1
    scrubRow.LayoutOrder   = 3
    scrubRow.Parent        = ctrlSec

    -- 56 = TrackLane LABEL_W (52) + UIListLayout gap (4) — aligns thumb with KF dots
    self._scrubber = Scrubber.new(scrubRow, 120, 1, widget, 56)
    self._scrubber.onFrameChanged:Connect(function(f)
        self._currentFrame = f
        if frameBox then frameBox.Text = tostring(f) end
        eFrame:Fire(f)
    end)
    self._scrubber.onDragBegan:Connect(function() eScrubBgn:Fire() end)
    self._scrubber.onDragEnded:Connect(function() eScrubEnd:Fire() end)

    -- Row 4: scene name + export + camera controls (all in one compact row)
    local sceneRow     = hrow(ctrlSec, 4, 4)
    lbl(sceneRow, "Scene:", 42, 1)
    local sceneNameBox = textBox(sceneRow, "Scene_001", 80, 2)
    self._sceneNameBox = sceneNameBox
    local saveBtn        = btn(sceneRow, "💾 Save",   3)
    local exportBtn      = btn(sceneRow, "⬆  Export",  4)
    local camCaptureBtn  = btn(sceneRow, "📷 Cam KF",  5)
    local camPreviewBtn  = btn(sceneRow, "Cam:OFF",    6)
    local camModeBtn     = btn(sceneRow, "KF:—",       7)
    self._camPreviewBtn = camPreviewBtn
    self._camModeBtn    = camModeBtn

    saveBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eSave:Fire(sceneNameBox.Text) end
    end)
    camCaptureBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eCamCapture:Fire() end
    end)
    camPreviewBtn.MouseButton1Click:Connect(function()
        self._camPreviewOn = not self._camPreviewOn
        self:setCameraPreviewState(self._camPreviewOn)
        eCamPreview:Fire(self._camPreviewOn)
    end)
    camModeBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eCamMode:Fire() end
    end)

    -- Row 5: action buttons (Add KF / Preview / Stop)
    local actRow = hrow(ctrlSec, 5, 4)

    local addKFBtn  = btn(actRow, "+ Add Keyframe", 1, true)
    local previewBtn = btn(actRow, "▶  Preview",     2)
    local stopBtn    = btn(actRow, "■  Stop",         3)

    self._addKFBtn   = addKFBtn
    self._previewBtn = previewBtn
    self._stopBtn    = stopBtn

    -- Row 6: keyframe clipboard (copy a rig's pose to another rig / frame)
    local clipRow = hrow(ctrlSec, 6, 4)
    local copyKFBtn   = btn(clipRow, "Copy KF",        1)
    local pasteKFBtn  = btn(clipRow, "Paste KF",       2)
    local pasteMirBtn = btn(clipRow, "Paste Mirrored", 3)
    local clipLbl     = lbl(clipRow, "", 110, 4)
    self._clipLbl = clipLbl

    copyKFBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eCopyKF:Fire() end
    end)
    pasteKFBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then ePasteKF:Fire(false) end
    end)
    pasteMirBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then ePasteKF:Fire(true) end
    end)

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

    do -- ── SIMPLE MODE ──────────────────────────────────────────────────────
    -- Self-contained controls: Delete Keyframe, scrubber, frame nav, Camera
    -- View toggle, Scene name + Save + Export. No rig/prop selection UI —
    -- everything in Workspace.FIGURES is auto-tracked (see init.server.lua).
    local simpleSec = section(root, "SIMPLE MODE", 1)
    simpleSec.Visible = false
    self._simpleSec = simpleSec

    local simpleActionRow = hrow(simpleSec, 2, 4)
    local simpleDelFrameBtn = btn(simpleActionRow, "🗑 Del Frame", 1)
    simpleDelFrameBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eSimpleDeleteFrame:Fire() end
    end)
    local simpleInsertBtn = btn(simpleActionRow, "Duplicate", 2)
    simpleInsertBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eSimpleInsertFrame:Fire() end
    end)
    local simplePlayBtn = btn(simpleActionRow, "▶  Play", 3, true)
    widenButton(simplePlayBtn, 2.5)
    self._simplePlayBtn = simplePlayBtn
    simplePlayBtn.MouseButton1Click:Connect(function()
        if self._isPlaying then eStop:Fire() else ePreview:Fire() end
    end)
    local simpleAddBtn = btn(simpleActionRow, "+ Add Frame", 4)
    simpleAddBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eSimpleAddFrame:Fire() end
    end)
    local simpleEaseBtn = btn(simpleActionRow, "Ease: Linear", 5)
    self._simpleEaseBtn = simpleEaseBtn
    local simpleEffectsBtn = btn(simpleActionRow, "Add effect", 6)
    simpleEffectsBtn.MouseButton1Click:Connect(function()
        if self._isPlaying then return end
        self:showSpawnedFxOverlay(self._currentFrame, nil)
    end)
    local simpleAttachBtn = btn(simpleActionRow, "Attach", 7)
    simpleAttachBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eSimpleAttach:Fire() end
    end)
    do -- Pose→End (do-block: Panel.new is at the 200-local-register ceiling)
        local ePoseEnd = mkEvent("onSimplePoseToEnd")
        local poseEndBtn = btn(simpleActionRow, "Apply→End", 8)
        poseEndBtn.MouseButton1Click:Connect(function()
            if not self._isPlaying then ePoseEnd:Fire() end
        end)
    end
    simpleEaseBtn.MouseButton1Click:Connect(function()
        if self._isPlaying then return end
        local absPos = simpleEaseBtn.AbsolutePosition
        local items = {}
        for _, opt in ipairs(EASING_OPTIONS) do
            local easing = opt.easing
            table.insert(items, {
                text = opt.text,
                action = function()
                    simpleEaseBtn.Text = "  Ease: " .. easing .. "  "
                    eSimpleEasing:Fire(easing)
                end,
            })
        end
        self:_showMenu(items, absPos.X - self._ctxOverlay.AbsolutePosition.X,
            absPos.Y + simpleEaseBtn.AbsoluteSize.Y + 2 - self._ctxOverlay.AbsolutePosition.Y)
    end)

    -- Frame icon strip: one clickable chip per keyframed frame, above the scrubber.
    -- Width is driven by setSimpleIconWidth(); starts at 1 slot.
    -- Inline notice bar: shown briefly when an action is blocked (e.g. no frame selected).
    -- Amber background, auto-hides after 2.5s via showSimpleNotice().
    local noticeBar = Instance.new("Frame")
    noticeBar.Name               = "SimpleNoticeBar"
    noticeBar.Size               = UDim2.new(1, 0, 0, 20)
    noticeBar.BackgroundColor3   = Color3.fromRGB(255, 200, 50)
    noticeBar.BorderSizePixel    = 0
    noticeBar.LayoutOrder        = 3
    noticeBar.Visible            = false
    noticeBar.Parent             = simpleSec
    local noticeLbl = Instance.new("TextLabel")
    noticeLbl.Size               = UDim2.new(1, -8, 1, 0)
    noticeLbl.Position           = UDim2.new(0, 4, 0, 0)
    noticeLbl.BackgroundTransparency = 1
    noticeLbl.TextColor3         = Color3.fromRGB(40, 25, 0)
    noticeLbl.Font               = Enum.Font.GothamMedium
    noticeLbl.TextSize           = 11
    noticeLbl.TextXAlignment     = Enum.TextXAlignment.Left
    noticeLbl.Text               = ""
    noticeLbl.Parent             = noticeBar
    self._noticeBar  = noticeBar
    self._noticeLbl  = noticeLbl

    local simpleIconRow = Instance.new("Frame")
    simpleIconRow.Name             = "SimpleIconRow"
    simpleIconRow.Size             = UDim2.new(0, SIMPLE_ICON_W, 0, SIMPLE_ICON_H)
    simpleIconRow.BackgroundTransparency = 1
    simpleIconRow.LayoutOrder      = 4
    simpleIconRow.Parent           = simpleSec
    self._simpleIconRow = simpleIconRow
    self._simpleIcons   = {}   -- [frame] = TextButton

    local simpleScrubRow = Instance.new("Frame")
    simpleScrubRow.Name             = "SimpleScrubRow"
    simpleScrubRow.Size             = UDim2.new(0, SIMPLE_ICON_W, 0, 0)
    simpleScrubRow.AutomaticSize    = Enum.AutomaticSize.Y
    simpleScrubRow.BackgroundTransparency = 1
    simpleScrubRow.LayoutOrder      = 5
    simpleScrubRow.Parent           = simpleSec
    self._simpleScrubRow = simpleScrubRow

    -- leftOffset = rightOffset = SIMPLE_ICON_W/2 so the thumb centres on each
    -- icon slot rather than landing on the slot's left edge.
    self._simpleScrubber = Scrubber.new(simpleScrubRow, 1, 1, widget,
        SIMPLE_ICON_W / 2, SIMPLE_ICON_W / 2)
    -- _simpleSlotFrames[slotIdx] = actualFrame (set by setSimpleSlots)
    self._simpleSlotFrames   = {}
    self._simpleFrameToSlot  = {}
    self._simpleScrubber.onFrameChanged:Connect(function(slotIdx)
        local frame = self._simpleSlotFrames[slotIdx] or slotIdx
        self._currentFrame = frame
        if frameBox then frameBox.Text = tostring(frame) end
        if self._simpleFrameBox then self._simpleFrameBox.Text = tostring(frame) end
        eFrame:Fire(frame)
    end)
    self._simpleScrubber.onDragBegan:Connect(function() eScrubBgn:Fire() end)
    self._simpleScrubber.onDragEnded:Connect(function() eScrubEnd:Fire() end)

    local simpleNavRow = hrow(simpleSec, 6, 4)
    local simplePrevKFBtn = smallBtn(simpleNavRow, "|◄", 1)
    local simplePrevBtn   = smallBtn(simpleNavRow, "◄",  2)
    lbl(simpleNavRow, "Frame:", 38, 3)
    local simpleFrameBox  = textBox(simpleNavRow, "1",   36, 4)
    local simpleNextBtn   = smallBtn(simpleNavRow, "►",  5)
    local simpleNextKFBtn = smallBtn(simpleNavRow, "►|", 6)
    lbl(simpleNavRow, "/", 8, 7)
    local simpleTotalBox  = textBox(simpleNavRow, "1", 36, 8)
    lbl(simpleNavRow, " @", 14, 9)
    local simpleFPSBox    = textBox(simpleNavRow, "30", 30, 10)
    lbl(simpleNavRow, "fps", nil, 11)
    self._simpleFrameBox = simpleFrameBox
    self._simpleTotalBox = simpleTotalBox
    self._simpleFPSBox   = simpleFPSBox

    simplePrevKFBtn.MouseButton1Click:Connect(function() eRewind:Fire() end)
    simpleNextKFBtn.MouseButton1Click:Connect(function() eFF:Fire() end)
    simplePrevBtn.MouseButton1Click:Connect(function()
        local f = math.max(1, self._currentFrame - 1)
        eFrame:Fire(f)
    end)
    simpleNextBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then
            local f = math.min(self._currentFrame + 1, self._frameCount)
            eFrame:Fire(f)
        end
    end)
    simpleFrameBox.FocusLost:Connect(function()
        local n = tonumber(simpleFrameBox.Text)
        if n then
            n = math.clamp(math.floor(n), 1, self._frameCount)
            eFrame:Fire(n)
        else
            simpleFrameBox.Text = tostring(self._currentFrame)
        end
    end)
    simpleFPSBox.FocusLost:Connect(function()
        local n = tonumber(simpleFPSBox.Text)
        if n then
            n = math.clamp(math.floor(n), 1, 999)
            simpleFPSBox.Text = tostring(n)
            eSimpleFPS:Fire(n)
        else
            simpleFPSBox.Text = tostring(self._simpleFPS or 30)
        end
    end)

    local simpleCamRow = hrow(simpleSec, 7, 4)
    local simpleCamBtn = btn(simpleCamRow, "Camera View: OFF", 1)
    self._simpleCamBtn = simpleCamBtn
    self._simpleCamOn = false
    simpleCamBtn.MouseButton1Click:Connect(function()
        self._simpleCamOn = not self._simpleCamOn
        simpleCamBtn.Text = "Camera View: " .. (self._simpleCamOn and "ON" or "OFF")
        self:_refreshPinCamEnabled()
        eSimpleCam:Fire(self._simpleCamOn)
    end)
    lbl(simpleCamRow, "FOV:", 28, 2)
    local simpleFOVBox = textBox(simpleCamRow, "70", 36, 3)
    self._simpleFOVBox = simpleFOVBox
    simpleFOVBox.FocusLost:Connect(function()
        local n = tonumber(simpleFOVBox.Text)
        if n then
            n = math.clamp(n, 1, 120)
            simpleFOVBox.Text = tostring(n)
            eSimpleFOV:Fire(n)
        else
            simpleFOVBox.Text = tostring(self._simpleFOV or 70)
        end
    end)
    local simpleLookBtn = btn(simpleCamRow, "Look Through: OFF", 4)
    self._simpleLookBtn = simpleLookBtn
    self._simpleLookOn  = false
    simpleLookBtn.MouseButton1Click:Connect(function()
        eSimpleLook:Fire(not self._simpleLookOn)
    end)
    -- Pin Cam: stamp the current camera at the current frame — the hold-
    -- keyframe authoring aid. Greyed out (inert) while Camera View is off.
    -- do…end: Panel.new rides the 200-local-register ceiling; new locals must
    -- live in a block so their registers are freed.
    do
        local eSimplePinCam = mkEvent("onSimplePinCamera")
        local simplePinBtn = btn(simpleCamRow, "📌 Pin Cam", 5)
        self._simplePinBtn = simplePinBtn
        simplePinBtn.MouseButton1Click:Connect(function()
            if self._simpleCamOn then eSimplePinCam:Fire() end
        end)
        self:_refreshPinCamEnabled()
    end
    -- KF mode toggle: same recorder-side toggle as the Advanced "KF:" button
    -- (fires the shared _eCamMode event). Greyed out while Camera View is off.
    do
        local simpleCamModeBtn = btn(simpleCamRow, "KF:—", 6)
        self._simpleCamModeBtn = simpleCamModeBtn
        simpleCamModeBtn.MouseButton1Click:Connect(function()
            if self._simpleCamOn and not self._isPlaying then
                self._eCamMode:Fire()
            end
        end)
        self:_refreshPinCamEnabled()
    end
    local simpleOnionBtn = btn(simpleCamRow, "Onion Skin: OFF", 7)
    self._simpleOnionBtn = simpleOnionBtn
    self._simpleOnionOn  = false
    simpleOnionBtn.MouseButton1Click:Connect(function()
        self._simpleOnionOn = not self._simpleOnionOn
        simpleOnionBtn.Text = "Onion Skin: " .. (self._simpleOnionOn and "ON" or "OFF")
        eSimpleOnion:Fire(self._simpleOnionOn)
    end)
    self.onSimpleOnionToggled = eSimpleOnion.Event
    local simpleCamDelBtn = btn(simpleCamRow, "Del Cam >=Here", 8, false, true)
    simpleCamDelBtn.MouseButton1Click:Connect(function()
        eSimpleCamDeleteFrom:Fire()
    end)
    self.onSimpleCamDeleteFrom = eSimpleCamDeleteFrom.Event

    local simpleSceneRow = hrow(simpleSec, 8, 4)
    lbl(simpleSceneRow, "Scene:", 42, 1)
    local simpleSceneBox = textBox(simpleSceneRow, "Scene_001", 160, 2)
    self._simpleSceneBox = simpleSceneBox
    self._lastSceneName  = simpleSceneBox.Text
    simpleSceneBox.FocusLost:Connect(function()
        local safe = sanitizeSceneName(simpleSceneBox.Text)
        if safe ~= simpleSceneBox.Text then simpleSceneBox.Text = safe end
        if safe ~= self._lastSceneName and self._lastSceneName ~= "" then
            eSceneRenamed:Fire(self._lastSceneName, safe)
        end
        self._lastSceneName = safe
    end)
    self.onSceneRenamed = eSceneRenamed.Event
    local simpleSaveBtn   = btn(simpleSceneRow, "💾 Save",   3)
    local simpleExportBtn = btn(simpleSceneRow, "⬆  Export", 4, true)
    local simpleSaveAsBtn = btn(simpleSceneRow, "Save As",   5)
    local simpleLoadBtn   = btn(simpleSceneRow, "Load",      6)
    local simpleNewBtn    = btn(simpleSceneRow, "New",        7)
    local simpleDeleteBtn = btn(simpleSceneRow, "Delete",     8, false, true)
    simpleSaveBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eSave:Fire(simpleSceneBox.Text) end
    end)
    simpleExportBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eExport:Fire(simpleSceneBox.Text) end
    end)
    simpleSaveAsBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then self:_showSaveOverlay() end
    end)
    simpleLoadBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eReload:Fire() end
    end)
    simpleNewBtn.MouseButton1Click:Connect(function()
        if self._isPlaying then return end
        local name = simpleSceneBox.Text or "Scene_001"
        -- Auto-increment: "Scene_001" → "Scene_002", "Foo" → "Foo_001"
        local base, num = name:match("^(.-)_(%d+)$")
        local newName
        if base and num then
            local n = tonumber(num) + 1
            newName = base .. "_" .. string.format("%0" .. #num .. "d", n)
        else
            newName = name .. "_001"
        end
        eNewAnimationPreview:Fire(name, newName)
    end)
    simpleDeleteBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eDeleteReq:Fire() end
    end)
    self.onNewAnimationRequested          = eNewAnimation.Event
    self.onNewAnimationPreviewRequested   = eNewAnimationPreview.Event
    self.onClearSceneTagsPreviewRequested = eClearSceneTagsPreview.Event

    -- ── Tag row ───────────────────────────────────────────────────────────────
    -- "Tag all in: [folder ▼] [Rigs] [Props] [Effects]  [Clear scene tags]"
    local simpleTagRow = hrow(simpleSec, 1, 4)
    lbl(simpleTagRow, "Tag:", 30, 1)

    local tagFolderBtn = btn(simpleTagRow, "folder ▼", 2)
    self._tagFolderBtn    = tagFolderBtn
    self._tagFolderName   = nil   -- nil = nothing selected yet

    -- Checkbox-style toggles: standalone TextButton owns all its handlers so
    -- btn()'s static hover closures can't overwrite the dynamic active color.
    -- Returns: button, getter(), setter(bool)
    local function toggleBtn(parent, text, order, default)
        local b = Instance.new("TextButton")
        b.Size             = UDim2.new(0, 0, 0, 24)
        b.AutomaticSize    = Enum.AutomaticSize.X
        b.BorderSizePixel  = 0
        b.TextColor3       = C.btnText
        b.Text             = "  " .. text .. "  "
        b.TextSize         = 12
        b.Font             = Enum.Font.Gotham
        b.AutoButtonColor  = false
        b.LayoutOrder      = order or 1
        b.Parent           = parent
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        local active = default
        local function paint(hover)
            b.BackgroundColor3 = active
                and (hover and C.btnAccHov or C.btnAccent)
                or  (hover and C.btnHover  or C.btnBg)
        end
        paint(false)
        b.MouseEnter:Connect(function()  paint(true)  end)
        b.MouseLeave:Connect(function()  paint(false) end)
        b.MouseButton1Click:Connect(function()
            active = not active
            paint(false)
        end)
        return b,
            function()      return active end,
            function(v) active = v; paint(false) end
    end

    local tagRigsBtn,    getRigsOn,    setRigsOn    = toggleBtn(simpleTagRow, "Rigs",    3, true)
    local tagPropsBtn,   getPropsOn,   setPropsOn   = toggleBtn(simpleTagRow, "Props",   4, true)
    local tagEffectsBtn, getEffectsOn, setEffectsOn = toggleBtn(simpleTagRow, "Effects", 5, false)
    self._tagRigsBtn    = tagRigsBtn
    self._tagPropsBtn   = tagPropsBtn
    self._tagEffectsBtn = tagEffectsBtn

    function self:resetTagToggles()
        setRigsOn(true); setPropsOn(true); setEffectsOn(false)
    end

    function self:getTagToggles()
        return { rigs = getRigsOn(), props = getPropsOn(), effects = getEffectsOn() }
    end

    local refreshTagsBtn = btn(simpleTagRow, "Refresh tags", 6)
    refreshTagsBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eRefreshTags:Fire() end
    end)

    local clearTagsBtn = btn(simpleTagRow, "Clear scene tags", 7)
    clearTagsBtn.MouseButton1Click:Connect(function()
        if not self._isPlaying then eClearSceneTagsPreview:Fire() end
    end)

    local manualTagLbl = lbl(simpleTagRow, "", nil, 8)
    manualTagLbl.TextSize = 10
    local function updateManualTagLbl()
        local name = (simpleSceneBox and simpleSceneBox.Text) or "Scene_001"
        manualTagLbl.Text = "  Manual tag: MAnim:" .. name
    end
    updateManualTagLbl()
    if simpleSceneBox then
        simpleSceneBox:GetPropertyChangedSignal("Text"):Connect(updateManualTagLbl)
    end

    tagFolderBtn.MouseButton1Click:Connect(function()
        if self._isPlaying then return end
        -- Request a fresh folder list from init.server.lua, which will call
        -- panel:openTagFolderDropdown(names) to show the popup.
        eTagFolderReq:Fire()
    end)

    self.onTagFolderListRequested  = eTagFolderReq.Event
    self.onTagAllInRequested       = eTagAllIn.Event
    self.onClearSceneTagsRequested = eClearSceneTags.Event
    self.onRefreshTagsRequested    = eRefreshTags.Event

    -- Folder picker: filter input + scrollable list.
    do
        local FP_W    = 220
        local ROW_H   = 22
        local MAX_VIS = 8   -- max visible rows before scrolling

        local fpOverlay = Instance.new("TextButton")
        fpOverlay.Size                  = UDim2.new(1, 0, 1, 0)
        fpOverlay.BackgroundTransparency = 1
        fpOverlay.Text                  = ""
        fpOverlay.AutoButtonColor       = false
        fpOverlay.ZIndex                = 44
        fpOverlay.Visible               = false
        fpOverlay.Parent                = widget

        local fpFrame = Instance.new("Frame")
        fpFrame.Size             = UDim2.new(0, FP_W, 0, 0)
        fpFrame.AutomaticSize    = Enum.AutomaticSize.Y
        fpFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        fpFrame.BorderSizePixel  = 0
        fpFrame.ZIndex           = 45
        fpFrame.Visible          = false
        fpFrame.Parent           = widget
        Instance.new("UICorner", fpFrame).CornerRadius = UDim.new(0, 4)
        local _fpStroke = Instance.new("UIStroke")
        _fpStroke.Color     = Color3.fromRGB(90, 90, 90)
        _fpStroke.Thickness = 1
        _fpStroke.Parent    = fpFrame
        listLayout(fpFrame, Enum.FillDirection.Vertical, 0)

        local fpFilter = Instance.new("TextBox")
        fpFilter.Size               = UDim2.new(1, 0, 0, ROW_H)
        fpFilter.BackgroundColor3   = Color3.fromRGB(35, 35, 35)
        fpFilter.BorderSizePixel    = 0
        fpFilter.TextColor3         = C.inputText
        fpFilter.PlaceholderText    = "filter…"
        fpFilter.PlaceholderColor3  = C.muted
        fpFilter.Text               = ""
        fpFilter.TextSize           = 11
        fpFilter.Font               = Enum.Font.Gotham
        fpFilter.TextXAlignment     = Enum.TextXAlignment.Left
        fpFilter.ClearTextOnFocus   = false
        fpFilter.ZIndex             = 46
        fpFilter.LayoutOrder        = 1
        fpFilter.Parent             = fpFrame
        local _fpPad = Instance.new("UIPadding")
        _fpPad.PaddingLeft  = UDim.new(0, 6)
        _fpPad.PaddingRight = UDim.new(0, 4)
        _fpPad.Parent       = fpFilter

        local fpScroll = Instance.new("ScrollingFrame")
        fpScroll.Size                 = UDim2.new(1, 0, 0, ROW_H)
        fpScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
        fpScroll.AutomaticCanvasSize  = Enum.AutomaticSize.Y
        fpScroll.ScrollBarThickness   = 4
        fpScroll.BackgroundTransparency = 1
        fpScroll.BorderSizePixel      = 0
        fpScroll.ZIndex               = 46
        fpScroll.LayoutOrder          = 2
        fpScroll.Parent               = fpFrame
        listLayout(fpScroll, Enum.FillDirection.Vertical, 0)

        local _fpAllNames = {}
        local _fpOnSelect = nil

        local function fpHide()
            fpOverlay.Visible = false
            fpFrame.Visible   = false
        end

        local function fpRebuild(filter)
            for _, c in ipairs(fpScroll:GetChildren()) do
                if c:IsA("GuiObject") then c:Destroy() end
            end
            local lf      = filter:lower()
            local visible = 0
            for _, name in ipairs(_fpAllNames) do
                if lf == "" or name:lower():find(lf, 1, true) then
                    visible += 1
                    local r = Instance.new("TextButton")
                    r.Size             = UDim2.new(1, 0, 0, ROW_H)
                    r.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
                    r.BorderSizePixel  = 0
                    r.TextColor3       = Color3.fromRGB(210, 210, 210)
                    r.Text             = "  " .. name
                    r.TextSize         = 11
                    r.Font             = Enum.Font.Gotham
                    r.TextXAlignment   = Enum.TextXAlignment.Left
                    r.AutoButtonColor  = false
                    r.ZIndex           = 47
                    r.LayoutOrder      = visible
                    r.Parent           = fpScroll
                    r.MouseEnter:Connect(function() r.BackgroundColor3 = Color3.fromRGB(70, 70, 70) end)
                    r.MouseLeave:Connect(function() r.BackgroundColor3 = Color3.fromRGB(50, 50, 50) end)
                    local n = name
                    r.MouseButton1Click:Connect(function()
                        fpHide()
                        if _fpOnSelect then _fpOnSelect(n) end
                    end)
                end
            end
            fpScroll.Size = UDim2.new(1, 0, 0, math.max(math.min(visible, MAX_VIS) * ROW_H, ROW_H))
        end

        fpFilter:GetPropertyChangedSignal("Text"):Connect(function()
            fpRebuild(fpFilter.Text)
        end)
        fpOverlay.MouseButton1Click:Connect(fpHide)

        function self:openTagFolderDropdown(folderNames)
            if not folderNames or #folderNames == 0 then return end
            _fpAllNames = folderNames
            _fpOnSelect = function(folderName)
                self._tagFolderName = folderName
                tagFolderBtn.Text   = "  " .. folderName .. " ▼  "
                eTagAllIn:Fire(folderName, {
                    rigs    = getRigsOn(),
                    props   = getPropsOn(),
                    effects = getEffectsOn(),
                })
            end
            fpFilter.Text = ""
            fpRebuild("")

            local absPos = tagFolderBtn.AbsolutePosition
            local ox = self._ctxOverlay.AbsolutePosition.X
            local oy = self._ctxOverlay.AbsolutePosition.Y
            local px = math.min(absPos.X - ox, self._ctxOverlay.AbsoluteSize.X - FP_W - 4)
            local py = absPos.Y + tagFolderBtn.AbsoluteSize.Y + 2 - oy
            fpFrame.Position  = UDim2.new(0, px, 0, py)
            fpOverlay.Visible = true
            fpFrame.Visible   = true
        end
    end

    -- Expose the current simple scene name for tagging logic.
    function self:getSimpleSceneName()
        return simpleSceneBox and simpleSceneBox.Text or ""
    end

    do -- ── SUBTITLE ROW + STYLE OVERLAY ───────────────────────────────────────
    local simpleSubRow = hrow(simpleSec, 8, 4)
    local subEnabledBtn = btn(simpleSubRow, "Sub-titles: OFF", 1)
    self._subEnabledOn  = false
    local subTextBox    = textBox(simpleSubRow, "", 140, 2)
    subTextBox.PlaceholderText    = "Subtitle text…"
    subTextBox.ClearTextOnFocus   = false
    self._subTextBox = subTextBox
    local subShowBtn = btn(simpleSubRow, "Show at 1", 3)
    self._subShowBtn = subShowBtn
    self._subShowOn  = false
    local subStyleBtn = btn(simpleSubRow, "Style…", 4)

    subEnabledBtn.MouseButton1Click:Connect(function()
        self._subEnabledOn = not self._subEnabledOn
        subEnabledBtn.Text = "Sub-titles: " .. (self._subEnabledOn and "ON" or "OFF")
        eSubtitleEnabled:Fire(self._subEnabledOn)
    end)
    subTextBox.FocusLost:Connect(function()
        eSubtitleText:Fire(subTextBox.Text)
    end)
    subShowBtn.MouseButton1Click:Connect(function()
        self._subShowOn = not self._subShowOn
        subShowBtn.Text = (self._subShowOn and "✓" or "○") .. " Frame " .. tostring(self._currentFrame)
        eSubtitleShow:Fire(self._currentFrame, self._subShowOn)
    end)
    self.onSubtitleEnabledChanged = eSubtitleEnabled.Event
    self.onSubtitleTextChanged    = eSubtitleText.Event
    self.onSubtitleShowChanged    = eSubtitleShow.Event
    self.onSubtitleStyleChanged   = eSubtitleStyle.Event

    function self:setSubtitleEnabled(on)
        self._subEnabledOn = on
        subEnabledBtn.Text = "Sub-titles: " .. (on and "ON" or "OFF")
    end

    function self:setSubtitleText(text)
        subTextBox.Text = text or ""
    end

    function self:getSubtitleText()
        return subTextBox.Text
    end

    function self:updateSubtitleShowBtn(frame, hasEvent)
        self._subShowOn  = hasEvent
        subShowBtn.Text  = (hasEvent and "✓" or "○") .. " Frame " .. tostring(frame)
    end

    -- ── Subtitle Style Overlay ────────────────────────────────────────────────
    local SUBTITLE_FONTS = {
        { name = "Gotham",       asset = "rbxasset://fonts/families/GothamSSm.json"     },
        { name = "Source Sans",  asset = "rbxasset://fonts/families/SourceSansPro.json" },
        { name = "Arial",        asset = "rbxasset://fonts/families/Arimo.json"         },
        { name = "Roboto Mono",  asset = "rbxasset://fonts/families/RobotoMono.json"    },
        { name = "Bangers",      asset = "rbxasset://fonts/families/Bangers.json"       },
        { name = "Oswald",       asset = "rbxasset://fonts/families/Oswald.json"        },
        { name = "Ubuntu",       asset = "rbxasset://fonts/families/Ubuntu.json"        },
        { name = "Nunito",       asset = "rbxasset://fonts/families/Nunito.json"        },
    }
    local FONT_WEIGHTS = { "Thin","Light","Regular","Medium","SemiBold","Bold","ExtraBold","Heavy" }

    local subStyleOv = Instance.new("Frame")
    subStyleOv.Name             = "SubtitleStyleOverlay"
    subStyleOv.Size             = UDim2.new(0, 260, 0, 0)
    subStyleOv.AutomaticSize    = Enum.AutomaticSize.Y
    subStyleOv.AnchorPoint      = Vector2.new(0.5, 0.5)
    subStyleOv.Position         = UDim2.new(0.5, 0, 0.5, 0)
    subStyleOv.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    subStyleOv.BorderSizePixel  = 0
    subStyleOv.ZIndex           = 55
    subStyleOv.Visible          = false
    subStyleOv.Parent           = widget
    Instance.new("UICorner", subStyleOv).CornerRadius = UDim.new(0, 6)
    local _subStroke = Instance.new("UIStroke")
    _subStroke.Color     = Color3.fromRGB(90, 90, 90)
    _subStroke.Thickness = 1
    _subStroke.Parent    = subStyleOv
    listLayout(subStyleOv, Enum.FillDirection.Vertical, 4)
    addPadding(subStyleOv, 10, 10)

    local subOvHdr = Instance.new("Frame")
    subOvHdr.Size                   = UDim2.new(1, 0, 0, 20)
    subOvHdr.BackgroundTransparency = 1
    subOvHdr.LayoutOrder            = 1
    subOvHdr.ZIndex                 = 56
    subOvHdr.Parent                 = subStyleOv
    local subOvTitle = Instance.new("TextLabel")
    subOvTitle.Size               = UDim2.new(1, -24, 1, 0)
    subOvTitle.BackgroundTransparency = 1
    subOvTitle.TextColor3         = C.header
    subOvTitle.TextSize           = 10
    subOvTitle.Font               = Enum.Font.GothamBold
    subOvTitle.TextXAlignment     = Enum.TextXAlignment.Left
    subOvTitle.Text               = "SUBTITLE STYLE"
    subOvTitle.ZIndex             = 56
    subOvTitle.Parent             = subOvHdr
    local subOvClose = Instance.new("TextButton")
    subOvClose.Size               = UDim2.new(0, 20, 1, 0)
    subOvClose.Position           = UDim2.new(1, -20, 0, 0)
    subOvClose.BackgroundTransparency = 1
    subOvClose.TextColor3         = C.muted
    subOvClose.Text               = "✕"
    subOvClose.TextSize           = 14
    subOvClose.Font               = Enum.Font.Gotham
    subOvClose.ZIndex             = 56
    subOvClose.Parent             = subOvHdr
    subOvClose.MouseButton1Click:Connect(function() subStyleOv.Visible = false end)

    -- Font family cycle
    local subFontRow = hrow(subStyleOv, 2, 4)
    lbl(subFontRow, "Font:", 44, 1)
    local subFontBtn = btn(subFontRow, SUBTITLE_FONTS[1].name, 2)
    subFontBtn.ZIndex = 56
    local _subFontIdx = 1
    subFontBtn.MouseButton1Click:Connect(function()
        _subFontIdx = (_subFontIdx % #SUBTITLE_FONTS) + 1
        subFontBtn.Text = SUBTITLE_FONTS[_subFontIdx].name
        eSubtitleStyle:Fire({ fontAsset = SUBTITLE_FONTS[_subFontIdx].asset })
    end)

    -- Font weight cycle
    local subWeightRow = hrow(subStyleOv, 3, 4)
    lbl(subWeightRow, "Weight:", 44, 1)
    local subWeightBtn = btn(subWeightRow, "Regular", 2)
    subWeightBtn.ZIndex = 56
    local _subWeightIdx = 3  -- "Regular"
    subWeightBtn.MouseButton1Click:Connect(function()
        _subWeightIdx = (_subWeightIdx % #FONT_WEIGHTS) + 1
        subWeightBtn.Text = FONT_WEIGHTS[_subWeightIdx]
        eSubtitleStyle:Fire({ fontWeight = FONT_WEIGHTS[_subWeightIdx] })
    end)

    -- Helper: numeric input row that fires a style field
    local function subNumRow(order, label, defVal, key, min, max, isFloat)
        local row = hrow(subStyleOv, order, 4)
        lbl(row, label .. ":", 80, 1)
        local box = textBox(row, tostring(defVal), 70, 2)
        box.ZIndex = 56
        box.ClearTextOnFocus = false
        box.FocusLost:Connect(function()
            local n = tonumber(box.Text)
            if n then
                n = math.clamp(n, min, max)
                box.Text = isFloat and string.format("%.2f", n) or tostring(math.floor(n))
                local patch = {}; patch[key] = n
                eSubtitleStyle:Fire(patch)
            else
                box.Text = tostring(defVal)
            end
        end)
        return box
    end

    -- Helper: R/G/B row
    local function subRGBRow(order, label, r, g, b, keyR, keyG, keyB)
        local row = hrow(subStyleOv, order, 4)
        lbl(row, label .. ":", 80, 1)
        local rBox = textBox(row, tostring(r), 38, 2)
        local gBox = textBox(row, tostring(g), 38, 3)
        local bBox = textBox(row, tostring(b), 38, 4)
        for _, box in ipairs({ rBox, gBox, bBox }) do
            box.ZIndex = 56; box.ClearTextOnFocus = false
        end
        local function commit()
            local rv = math.clamp(math.floor(tonumber(rBox.Text) or r), 0, 255)
            local gv = math.clamp(math.floor(tonumber(gBox.Text) or g), 0, 255)
            local bv = math.clamp(math.floor(tonumber(bBox.Text) or b), 0, 255)
            rBox.Text = tostring(rv); gBox.Text = tostring(gv); bBox.Text = tostring(bv)
            local patch = {}
            patch[keyR] = rv; patch[keyG] = gv; patch[keyB] = bv
            eSubtitleStyle:Fire(patch)
        end
        rBox.FocusLost:Connect(commit); gBox.FocusLost:Connect(commit); bBox.FocusLost:Connect(commit)
        return rBox, gBox, bBox
    end

    subNumRow(4,  "Size",           28,  "size",               6,   200, false)
    subRGBRow(5,  "Text Color",     255, 255, 255, "textColorR",   "textColorG",   "textColorB")
    subNumRow(6,  "Text Alpha",     0,   "textTransparency",   0,   1,   true)
    subRGBRow(7,  "Stroke Color",   0,   0,   0,   "strokeColorR", "strokeColorG", "strokeColorB")
    subNumRow(8,  "Stroke Alpha",   0,   "strokeTransparency", 0,   1,   true)
    subRGBRow(9,  "BG Color",       0,   0,   0,   "bgColorR",     "bgColorG",     "bgColorB")
    subNumRow(10, "BG Alpha",       0.6, "bgTransparency",     0,   1,   true)
    subNumRow(11, "X Offset (0-1)", 0.05,"xOffset",            0,   1,   true)
    subNumRow(12, "Y Offset (0-1)", 0.85,"yOffset",            0,   1,   true)

    subStyleBtn.MouseButton1Click:Connect(function()
        subStyleOv.Visible = not subStyleOv.Visible
    end)

    -- Public: sync style overlay controls from a loaded style table
    function self:setSubtitleStyleDisplay(style)
        style = style or {}
        if style.fontAsset then
            for i, f in ipairs(SUBTITLE_FONTS) do
                if f.asset == style.fontAsset then
                    _subFontIdx = i; subFontBtn.Text = f.name; break
                end
            end
        end
        if style.fontWeight then
            for i, w in ipairs(FONT_WEIGHTS) do
                if w == style.fontWeight then
                    _subWeightIdx = i; subWeightBtn.Text = w; break
                end
            end
        end
    end

    end -- ── SUBTITLE ROW + STYLE OVERLAY ───────────────────────────────────────

    end -- ── end SIMPLE MODE ──────────────────────────────────────────────────

    do -- ── OVERLAYS ─────────────────────────────────────────────────────────
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
        local name = sanitizeSceneName(saveOvBox.Text:match("^%s*(.-)%s*$"))
        if name ~= "" then
            self._lastSaveName = name
            saveOvBox.Text = name
            -- keep both scene name boxes in sync with the saved name
            if self._sceneNameBox    then self._sceneNameBox.Text    = name end
            if self._simpleSceneBox  then self._simpleSceneBox.Text  = name end
            self._lastSceneName = name
            saveOv.Visible = false
            eSave:Fire(name)
        end
    end
    saveOvBox.FocusLost:Connect(function(enter) if enter then _doSave() end end)
    saveOvOk.MouseButton1Click:Connect(_doSave)
    saveOvCancel.MouseButton1Click:Connect(function() saveOv.Visible = false end)

    self._saveOverlay = saveOv
    self._saveOvBox   = saveOvBox

    -- ── New Session confirmation overlay ──────────────────────────────────────
    local newOv = Instance.new("Frame")
    newOv.Name            = "NewOverlay"
    newOv.Size            = UDim2.new(0, 220, 0, 90)
    newOv.AnchorPoint     = Vector2.new(0.5, 0.5)
    newOv.Position        = UDim2.new(0.5, 0, 0.5, 0)
    newOv.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    newOv.BorderSizePixel = 0
    newOv.ZIndex          = 50
    newOv.Visible         = false
    newOv.Parent          = widget
    Instance.new("UICorner", newOv).CornerRadius = UDim.new(0, 6)
    local _nStroke = Instance.new("UIStroke")
    _nStroke.Color     = Color3.fromRGB(90, 90, 90)
    _nStroke.Thickness = 1
    _nStroke.Parent    = newOv
    listLayout(newOv, Enum.FillDirection.Vertical, 8)
    addPadding(newOv, 10, 10)

    local newOvHdr = Instance.new("TextLabel")
    newOvHdr.Size               = UDim2.new(1, 0, 0, 13)
    newOvHdr.BackgroundTransparency = 1
    newOvHdr.TextColor3         = C.header
    newOvHdr.Text               = "NEW SESSION"
    newOvHdr.TextSize           = 10
    newOvHdr.Font               = Enum.Font.GothamBold
    newOvHdr.TextXAlignment     = Enum.TextXAlignment.Left
    newOvHdr.LayoutOrder        = 1
    newOvHdr.Parent             = newOv

    local newOvMsg = Instance.new("TextLabel")
    newOvMsg.Size               = UDim2.new(1, 0, 0, 16)
    newOvMsg.BackgroundTransparency = 1
    newOvMsg.TextColor3         = C.ovText
    newOvMsg.Text               = "Clear all keyframes and start fresh?"
    newOvMsg.TextSize           = 11
    newOvMsg.Font               = Enum.Font.Gotham
    newOvMsg.TextXAlignment     = Enum.TextXAlignment.Left
    newOvMsg.LayoutOrder        = 2
    newOvMsg.Parent             = newOv

    local newOvRow    = hrow(newOv, 3, 6)
    local newOvOk     = btn(newOvRow, "Clear All", 1)
    local newOvCancel = btn(newOvRow, "Cancel",    2)
    newOvOk.MouseButton1Click:Connect(function()
        newOv.Visible = false
        eNewSession:Fire()
    end)
    newOvCancel.MouseButton1Click:Connect(function() newOv.Visible = false end)
    self._newOverlay = newOv

    -- ── Generic tag-action confirm overlay ────────────────────────────────────
    local tagConfOv = Instance.new("Frame")
    tagConfOv.Name            = "TagConfirmOverlay"
    tagConfOv.Size            = UDim2.new(0, 260, 0, 110)
    tagConfOv.AnchorPoint     = Vector2.new(0.5, 0.5)
    tagConfOv.Position        = UDim2.new(0.5, 0, 0.5, 0)
    tagConfOv.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    tagConfOv.BorderSizePixel = 0
    tagConfOv.ZIndex          = 50
    tagConfOv.Visible         = false
    tagConfOv.Parent          = widget
    Instance.new("UICorner", tagConfOv).CornerRadius = UDim.new(0, 6)
    local _tcStroke = Instance.new("UIStroke")
    _tcStroke.Color     = Color3.fromRGB(90, 90, 90)
    _tcStroke.Thickness = 1
    _tcStroke.Parent    = tagConfOv
    listLayout(tagConfOv, Enum.FillDirection.Vertical, 6)
    addPadding(tagConfOv, 10, 10)

    local tagConfHdr = Instance.new("TextLabel")
    tagConfHdr.Size               = UDim2.new(1, 0, 0, 13)
    tagConfHdr.BackgroundTransparency = 1
    tagConfHdr.TextColor3         = C.header
    tagConfHdr.Text               = ""
    tagConfHdr.TextSize           = 10
    tagConfHdr.Font               = Enum.Font.GothamBold
    tagConfHdr.TextXAlignment     = Enum.TextXAlignment.Left
    tagConfHdr.LayoutOrder        = 1
    tagConfHdr.Parent             = tagConfOv

    local tagConfMsg = Instance.new("TextLabel")
    tagConfMsg.Size               = UDim2.new(1, 0, 0, 60)
    tagConfMsg.BackgroundTransparency = 1
    tagConfMsg.TextColor3         = C.ovText
    tagConfMsg.Text               = ""
    tagConfMsg.TextSize           = 11
    tagConfMsg.Font               = Enum.Font.Gotham
    tagConfMsg.TextXAlignment     = Enum.TextXAlignment.Left
    tagConfMsg.TextYAlignment     = Enum.TextYAlignment.Top
    tagConfMsg.TextWrapped        = true
    tagConfMsg.LayoutOrder        = 2
    tagConfMsg.Parent             = tagConfOv

    local tagConfRow    = hrow(tagConfOv, 3, 6)
    local tagConfOk     = btn(tagConfRow, "OK",     1)
    local tagConfCancel = btn(tagConfRow, "Cancel", 2)
    local _tagConfCallback       = nil
    local _tagConfCancelCallback = nil
    tagConfOk.MouseButton1Click:Connect(function()
        tagConfOv.Visible     = false
        tagConfCancel.Visible = true
        local cb = _tagConfCallback
        _tagConfCallback       = nil
        _tagConfCancelCallback = nil
        if cb then cb() end
    end)
    tagConfCancel.MouseButton1Click:Connect(function()
        tagConfOv.Visible = false
        local cb = _tagConfCancelCallback
        _tagConfCallback       = nil
        _tagConfCancelCallback = nil
        if cb then cb() end
    end)

    function self:showTagConfirm(header, message, onOkay, onCancel)
        tagConfHdr.Text          = header
        tagConfMsg.Text          = message
        _tagConfCallback         = onOkay
        _tagConfCancelCallback   = onCancel
        tagConfCancel.Visible    = true
        tagConfOv.Visible        = true
    end

    function self:showWarning(header, message)
        tagConfHdr.Text          = header
        tagConfMsg.Text          = message
        _tagConfCallback         = nil
        _tagConfCancelCallback   = nil
        tagConfCancel.Visible    = false
        tagConfOv.Visible        = true
    end

    function self:setSimpleSceneName(name)
        local safe = sanitizeSceneName(name) or ""
        if self._simpleSceneBox then self._simpleSceneBox.Text = safe end
        self._lastSceneName = safe
    end

    function self:setTagFolder(name)
        self._tagFolderName = name or nil
        if self._tagFolderBtn then
            self._tagFolderBtn.Text = name and ("  " .. name .. " ▼  ") or "folder ▼"
        end
    end

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

    local loadCancelRow = Instance.new("Frame")
    loadCancelRow.Size               = UDim2.new(1, 0, 0, 36)
    loadCancelRow.Position           = UDim2.new(0, 0, 1, -36)
    loadCancelRow.BackgroundColor3   = C.sectionBg
    loadCancelRow.BorderSizePixel    = 0
    loadCancelRow.ZIndex             = 51
    loadCancelRow.Parent             = loadOv

    local loadCancelBtn = Instance.new("TextButton")
    loadCancelBtn.Size               = UDim2.new(0, 80, 0, 24)
    loadCancelBtn.Position           = UDim2.new(0.5, -40, 0.5, -12)
    loadCancelBtn.BackgroundColor3   = C.btnBg
    loadCancelBtn.BorderSizePixel    = 0
    loadCancelBtn.TextColor3         = C.btnText
    loadCancelBtn.Text               = "  Cancel  "
    loadCancelBtn.TextSize           = 12
    loadCancelBtn.Font               = Enum.Font.Gotham
    loadCancelBtn.AutoButtonColor    = false
    loadCancelBtn.ZIndex             = 52
    loadCancelBtn.Parent             = loadCancelRow
    Instance.new("UICorner", loadCancelBtn).CornerRadius = UDim.new(0, 4)
    loadCancelBtn.MouseEnter:Connect(function() loadCancelBtn.BackgroundColor3 = C.btnHover end)
    loadCancelBtn.MouseLeave:Connect(function() loadCancelBtn.BackgroundColor3 = C.btnBg end)
    loadCancelBtn.MouseButton1Click:Connect(function() loadOv.Visible = false end)

    local loadScroll = Instance.new("ScrollingFrame")
    loadScroll.Size                 = UDim2.new(1, 0, 1, -70)
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
    end -- ── end OVERLAYS ──────────────────────────────────────────────────────

    do -- DELETE OVERLAY ────────────────────────────────────────────────────────
    local delOv = Instance.new("Frame")
    delOv.Name             = "DeleteOverlay"
    delOv.Size             = UDim2.new(1, 0, 1, 0)
    delOv.BackgroundColor3 = C.bg
    delOv.BorderSizePixel  = 0
    delOv.ZIndex           = 50
    delOv.Visible          = false
    delOv.Parent           = widget

    local delHdr = Instance.new("Frame")
    delHdr.Size             = UDim2.new(1, 0, 0, 34)
    delHdr.BackgroundColor3 = C.sectionBg
    delHdr.BorderSizePixel  = 0
    delHdr.ZIndex           = 51
    delHdr.Parent           = delOv

    local delHdrTitle = Instance.new("TextLabel")
    delHdrTitle.Size               = UDim2.new(1, -34, 1, 0)
    delHdrTitle.Position           = UDim2.new(0, 10, 0, 0)
    delHdrTitle.BackgroundTransparency = 1
    delHdrTitle.TextColor3         = C.header
    delHdrTitle.Text               = "DELETE SESSION"
    delHdrTitle.TextSize           = 10
    delHdrTitle.Font               = Enum.Font.GothamBold
    delHdrTitle.TextXAlignment     = Enum.TextXAlignment.Left
    delHdrTitle.ZIndex             = 52
    delHdrTitle.Parent             = delHdr

    local delHdrClose = Instance.new("TextButton")
    delHdrClose.Size               = UDim2.new(0, 34, 1, 0)
    delHdrClose.Position           = UDim2.new(1, -34, 0, 0)
    delHdrClose.BackgroundTransparency = 1
    delHdrClose.TextColor3         = C.muted
    delHdrClose.Text               = "✕"
    delHdrClose.TextSize           = 14
    delHdrClose.Font               = Enum.Font.Gotham
    delHdrClose.ZIndex             = 52
    delHdrClose.Parent             = delHdr
    delHdrClose.MouseButton1Click:Connect(function() delOv.Visible = false end)

    local delScroll = Instance.new("ScrollingFrame")
    delScroll.Size                 = UDim2.new(1, 0, 1, -70)
    delScroll.Position             = UDim2.new(0, 0, 0, 34)
    delScroll.CanvasSize           = UDim2.new(0, 0, 0, 0)
    delScroll.ScrollBarThickness   = 5
    delScroll.ScrollBarImageColor3 = C.btnBg
    delScroll.BackgroundTransparency = 1
    delScroll.BorderSizePixel      = 0
    delScroll.ZIndex               = 51
    delScroll.Parent               = delOv

    local _delScrollLayout = Instance.new("UIListLayout")
    _delScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
    _delScrollLayout.Padding   = UDim.new(0, 1)
    _delScrollLayout.Parent    = delScroll

    local delCancelRow = Instance.new("Frame")
    delCancelRow.Size               = UDim2.new(1, 0, 0, 36)
    delCancelRow.Position           = UDim2.new(0, 0, 1, -36)
    delCancelRow.BackgroundColor3   = C.sectionBg
    delCancelRow.BorderSizePixel    = 0
    delCancelRow.ZIndex             = 51
    delCancelRow.Parent             = delOv

    local delCancelBtn = Instance.new("TextButton")
    delCancelBtn.Size               = UDim2.new(0, 80, 0, 24)
    delCancelBtn.Position           = UDim2.new(0.5, -40, 0.5, -12)
    delCancelBtn.BackgroundColor3   = C.btnBg
    delCancelBtn.BorderSizePixel    = 0
    delCancelBtn.TextColor3         = C.btnText
    delCancelBtn.Text               = "  Cancel  "
    delCancelBtn.TextSize           = 12
    delCancelBtn.Font               = Enum.Font.Gotham
    delCancelBtn.AutoButtonColor    = false
    delCancelBtn.ZIndex             = 52
    delCancelBtn.Parent             = delCancelRow
    Instance.new("UICorner", delCancelBtn).CornerRadius = UDim.new(0, 4)
    delCancelBtn.MouseEnter:Connect(function() delCancelBtn.BackgroundColor3 = C.btnHover end)
    delCancelBtn.MouseLeave:Connect(function() delCancelBtn.BackgroundColor3 = C.btnBg end)
    delCancelBtn.MouseButton1Click:Connect(function() delOv.Visible = false end)

    -- Confirmation card (shown on top of the list when a scene is clicked)
    local delConfOv = Instance.new("Frame")
    delConfOv.Size             = UDim2.new(1, 0, 1, 0)
    delConfOv.BackgroundColor3 = C.bg
    delConfOv.BackgroundTransparency = 0.08
    delConfOv.BorderSizePixel  = 0
    delConfOv.ZIndex           = 60
    delConfOv.Visible          = false
    delConfOv.Parent           = delOv

    local delConfCard = Instance.new("Frame")
    delConfCard.Size             = UDim2.new(1, -40, 0, 130)
    delConfCard.Position         = UDim2.new(0, 20, 0.5, -65)
    delConfCard.BackgroundColor3 = C.sectionBg
    delConfCard.BorderSizePixel  = 0
    delConfCard.ZIndex           = 61
    delConfCard.Parent           = delConfOv
    Instance.new("UICorner", delConfCard).CornerRadius = UDim.new(0, 6)

    local delConfMsg = Instance.new("TextLabel")
    delConfMsg.Size               = UDim2.new(1, -20, 0, 60)
    delConfMsg.Position           = UDim2.new(0, 10, 0, 14)
    delConfMsg.BackgroundTransparency = 1
    delConfMsg.TextColor3         = C.ovText
    delConfMsg.Text               = "Are you sure you want to delete this session?"
    delConfMsg.TextSize           = 13
    delConfMsg.Font               = Enum.Font.Gotham
    delConfMsg.TextXAlignment     = Enum.TextXAlignment.Center
    delConfMsg.TextWrapped        = true
    delConfMsg.ZIndex             = 62
    delConfMsg.Parent             = delConfCard

    local delConfBtnRow = Instance.new("Frame")
    delConfBtnRow.Size               = UDim2.new(1, -20, 0, 36)
    delConfBtnRow.Position           = UDim2.new(0, 10, 0, 82)
    delConfBtnRow.BackgroundTransparency = 1
    delConfBtnRow.ZIndex             = 62
    delConfBtnRow.Parent             = delConfCard

    local _confLayout = Instance.new("UIListLayout")
    _confLayout.FillDirection        = Enum.FillDirection.Horizontal
    _confLayout.HorizontalAlignment  = Enum.HorizontalAlignment.Center
    _confLayout.VerticalAlignment    = Enum.VerticalAlignment.Center
    _confLayout.Padding              = UDim.new(0, 12)
    _confLayout.Parent               = delConfBtnRow

    local delConfYes = Instance.new("TextButton")
    delConfYes.Size                  = UDim2.new(0, 72, 0, 28)
    delConfYes.BackgroundColor3      = C.btnDanger
    delConfYes.BorderSizePixel       = 0
    delConfYes.TextColor3            = C.btnText
    delConfYes.Text                  = "  Yes  "
    delConfYes.TextSize              = 12
    delConfYes.Font                  = Enum.Font.GothamBold
    delConfYes.AutoButtonColor       = false
    delConfYes.ZIndex                = 63
    delConfYes.Parent                = delConfBtnRow
    Instance.new("UICorner", delConfYes).CornerRadius = UDim.new(0, 4)
    delConfYes.MouseEnter:Connect(function() delConfYes.BackgroundColor3 = C.btnDangerHov end)
    delConfYes.MouseLeave:Connect(function() delConfYes.BackgroundColor3 = C.btnDanger end)

    local delConfNo = Instance.new("TextButton")
    delConfNo.Size                   = UDim2.new(0, 72, 0, 28)
    delConfNo.BackgroundColor3       = C.btnBg
    delConfNo.BorderSizePixel        = 0
    delConfNo.TextColor3             = C.btnText
    delConfNo.Text                   = "  No  "
    delConfNo.TextSize               = 12
    delConfNo.Font                   = Enum.Font.Gotham
    delConfNo.AutoButtonColor        = false
    delConfNo.ZIndex                 = 63
    delConfNo.Parent                 = delConfBtnRow
    Instance.new("UICorner", delConfNo).CornerRadius = UDim.new(0, 4)
    delConfNo.MouseEnter:Connect(function() delConfNo.BackgroundColor3 = C.btnHover end)
    delConfNo.MouseLeave:Connect(function() delConfNo.BackgroundColor3 = C.btnBg end)
    delConfNo.MouseButton1Click:Connect(function() delConfOv.Visible = false end)

    delConfYes.MouseButton1Click:Connect(function()
        local nm = self._delPendingName
        if nm then
            eDeleteNamed:Fire(nm)
            self._delPendingName = nil
        end
        delConfOv.Visible = false
    end)

    self._deleteOverlay  = delOv
    self._deleteScroll   = delScroll
    self._delConfOv      = delConfOv
    self._delConfMsg     = delConfMsg
    self._delPendingName = nil
    end -- ── end DELETE OVERLAY ──────────────────────────────────────────────

    do -- SPAWNED FX OVERLAY
    -- Card overlay for adding/editing single-frame spawned effects (Explosion, Smoke, Sound).
    -- Opened by the Effects button in Simple Mode action row, or by clicking a gizmo sphere.
    local FX_TYPES = { "Explosion", "Smoke", "Sound", "Fade" }
    local FX_DEFAULTS = {
        Explosion = { size=3, colorR=255, colorG=80,  colorB=0,   count=50, duration=0.6, speed=20, lifetime=1.0 },
        Smoke     = { size=5, colorR=160, colorG=160, colorB=160, count=25, duration=4.0, speed=4,  lifetime=5.0 },
        Sound     = { soundId="", volume=1, maxDistance=80 },
        Fade      = { colorR=0, colorG=0, colorB=0, imageId="", duration=1.0, direction="out" },
    }
    local FX_PROPS = {
        { key="size",     label="Size"     },
        { key="colorR",   label="Color R"  },
        { key="colorG",   label="Color G"  },
        { key="colorB",   label="Color B"  },
        { key="count",    label="Count"    },
        { key="duration", label="Duration" },
        { key="speed",    label="Speed"    },
        { key="lifetime", label="Lifetime" },
    }
    -- Fade reuses the colour + duration rows; these are particle-only.
    local FX_PARTICLE_ONLY = { size=true, count=true, speed=true, lifetime=true }

    local fxOv = Instance.new("Frame")
    fxOv.Name              = "SpawnedFxOverlay"
    fxOv.Size              = UDim2.new(0, 240, 0, 0)
    fxOv.AutomaticSize     = Enum.AutomaticSize.Y
    fxOv.AnchorPoint       = Vector2.new(0.5, 0.5)
    fxOv.Position          = UDim2.new(0.5, 0, 0.5, 0)
    fxOv.BackgroundColor3  = Color3.fromRGB(55, 55, 55)
    fxOv.BorderSizePixel   = 0
    fxOv.ZIndex            = 55
    fxOv.Visible           = false
    fxOv.Parent            = widget
    Instance.new("UICorner", fxOv).CornerRadius = UDim.new(0, 6)
    local _fxStroke = Instance.new("UIStroke")
    _fxStroke.Color     = Color3.fromRGB(90, 90, 90)
    _fxStroke.Thickness = 1
    _fxStroke.Parent    = fxOv
    listLayout(fxOv, Enum.FillDirection.Vertical, 4)
    addPadding(fxOv, 10, 10)

    -- Header row
    local fxHdrRow = Instance.new("Frame")
    fxHdrRow.Size                    = UDim2.new(1, 0, 0, 20)
    fxHdrRow.BackgroundTransparency  = 1
    fxHdrRow.LayoutOrder             = 1
    fxHdrRow.ZIndex                  = 56
    fxHdrRow.Parent                  = fxOv
    local fxOvTitle = Instance.new("TextLabel")
    fxOvTitle.Size               = UDim2.new(1, -24, 1, 0)
    fxOvTitle.BackgroundTransparency = 1
    fxOvTitle.TextColor3         = C.header
    fxOvTitle.TextSize           = 10
    fxOvTitle.Font               = Enum.Font.GothamBold
    fxOvTitle.TextXAlignment     = Enum.TextXAlignment.Left
    fxOvTitle.Text               = "ADD EFFECT  •  FRAME 1"
    fxOvTitle.ZIndex             = 56
    fxOvTitle.Parent             = fxHdrRow
    local fxOvClose = Instance.new("TextButton")
    fxOvClose.Size               = UDim2.new(0, 20, 1, 0)
    fxOvClose.Position           = UDim2.new(1, -20, 0, 0)
    fxOvClose.BackgroundTransparency = 1
    fxOvClose.TextColor3         = C.muted
    fxOvClose.Text               = "✕"
    fxOvClose.TextSize           = 14
    fxOvClose.Font               = Enum.Font.Gotham
    fxOvClose.ZIndex             = 56
    fxOvClose.Parent             = fxHdrRow
    fxOvClose.MouseButton1Click:Connect(function() fxOv.Visible = false end)

    -- Type cycle row
    local fxTypeRow = hrow(fxOv, 2, 4)
    lbl(fxTypeRow, "Type:", 38, 1)
    local fxTypeBtn = btn(fxTypeRow, "Explosion", 2)
    fxTypeBtn.ZIndex = 56

    -- Particle property input rows (LayoutOrder 3-9; hidden when type == Sound)
    local fxBoxes = {}
    local fxBoxRows = {}
    for i, prop in ipairs(FX_PROPS) do
        local row = hrow(fxOv, 2 + i, 4)
        lbl(row, prop.label .. ":", 70, 1)
        local defVal = FX_DEFAULTS.Explosion[prop.key]
        local box = textBox(row, tostring(defVal ~= nil and defVal or ""), 90, 2)
        box.ZIndex = 56
        fxBoxes[prop.key] = box
        fxBoxRows[prop.key] = row
    end

    -- Sound-specific rows (LayoutOrder 3-5; hidden by default; shown only for Sound type)
    local fxSoundIdRow = hrow(fxOv, 3, 4)
    fxSoundIdRow.Visible = false
    lbl(fxSoundIdRow, "Sound ID:", 62, 1)
    local fxSoundIdBox = textBox(fxSoundIdRow, "rbxassetid://", 140, 2)
    fxSoundIdBox.ZIndex = 56; fxSoundIdBox.ClearTextOnFocus = false

    local fxSoundVolRow = hrow(fxOv, 4, 4)
    fxSoundVolRow.Visible = false
    lbl(fxSoundVolRow, "Volume:", 62, 1)
    local fxSoundVolBox = textBox(fxSoundVolRow, "1", 80, 2)
    fxSoundVolBox.ZIndex = 56

    local fxSoundDistRow = hrow(fxOv, 5, 4)
    fxSoundDistRow.Visible = false
    lbl(fxSoundDistRow, "Max Dist:", 62, 1)
    local fxSoundDistBox = textBox(fxSoundDistRow, "80", 80, 2)
    fxSoundDistBox.ZIndex = 56

    -- Fade-specific rows (hidden by default)
    local fxFadeImgRow = hrow(fxOv, 8, 4)
    fxFadeImgRow.Visible = false
    lbl(fxFadeImgRow, "Image ID:", 62, 1)
    local fxFadeImgBox = textBox(fxFadeImgRow, "", 140, 2)
    fxFadeImgBox.PlaceholderText = "rbxassetid:// (optional)"
    fxFadeImgBox.ZIndex = 56; fxFadeImgBox.ClearTextOnFocus = false

    local fxFadeDirRow = hrow(fxOv, 9, 4)
    fxFadeDirRow.Visible = false
    lbl(fxFadeDirRow, "Direction:", 62, 1)
    local fxFadeDirBtn = btn(fxFadeDirRow, "out (to colour)", 2)
    fxFadeDirBtn.ZIndex = 56
    self._spawnedFxDir = "out"
    fxFadeDirBtn.MouseButton1Click:Connect(function()
        self._spawnedFxDir = self._spawnedFxDir == "out" and "in" or "out"
        fxFadeDirBtn.Text = self._spawnedFxDir == "out"
            and "  out (to colour)  " or "  in (reveal scene)  "
    end)

    local function fxApplyTypeVisibility(effectType)
        local isSound = effectType == "Sound"
        local isFade  = effectType == "Fade"
        for _, prop in ipairs(FX_PROPS) do
            local vis = not isSound
            if isFade and FX_PARTICLE_ONLY[prop.key] then vis = false end
            fxBoxRows[prop.key].Visible = vis
        end
        fxSoundIdRow.Visible   = isSound
        fxSoundVolRow.Visible  = isSound
        fxSoundDistRow.Visible = isSound
        fxFadeImgRow.Visible   = isFade
        fxFadeDirRow.Visible   = isFade
    end

    -- Position row
    local fxPosRow = hrow(fxOv, 10, 4)
    local fxPickBtn = btn(fxPosRow, "Select Position", 1)
    fxPickBtn.ZIndex = 56
    fxPickBtn.MouseButton1Click:Connect(function()
        eSpawnedFxPickPos:Fire()
    end)
    local fxCoordLbl = Instance.new("TextLabel")
    fxCoordLbl.Size                    = UDim2.new(0, 130, 0, 24)
    fxCoordLbl.BackgroundTransparency  = 1
    fxCoordLbl.TextColor3              = C.muted
    fxCoordLbl.TextSize                = 10
    fxCoordLbl.Font                    = Enum.Font.Gotham
    fxCoordLbl.Text                    = "X: —  Y: —  Z: —"
    fxCoordLbl.TextXAlignment          = Enum.TextXAlignment.Left
    fxCoordLbl.LayoutOrder             = 2
    fxCoordLbl.ZIndex                  = 56
    fxCoordLbl.Parent                  = fxPosRow

    -- Bottom buttons row
    local fxBtnRow = hrow(fxOv, 11, 6)
    local fxAddBtn = btn(fxBtnRow, "Add to Frame", 1, true)
    fxAddBtn.ZIndex = 56
    local fxCancelBtn = btn(fxBtnRow, "Cancel", 2)
    fxCancelBtn.ZIndex = 56
    local fxDeleteBtn = btn(fxBtnRow, "Delete", 3)
    fxDeleteBtn.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
    fxDeleteBtn.ZIndex = 56
    fxDeleteBtn.Visible = false
    fxCancelBtn.MouseButton1Click:Connect(function() fxOv.Visible = false end)

    fxTypeBtn.MouseButton1Click:Connect(function()
        local cur = self._spawnedFxType or "Explosion"
        local nextType = FX_TYPES[1]
        for i, t in ipairs(FX_TYPES) do
            if t == cur and FX_TYPES[i + 1] then nextType = FX_TYPES[i + 1]; break end
        end
        self._spawnedFxType = nextType
        fxTypeBtn.Text = "  " .. nextType .. "  "
        fxApplyTypeVisibility(nextType)
        fxPosRow.Visible = nextType ~= "Fade"
        local p = FX_DEFAULTS[nextType]
        if p then
            if nextType == "Sound" then
                fxSoundIdBox.Text  = p.soundId or ""
                fxSoundVolBox.Text = tostring(p.volume or 1)
                fxSoundDistBox.Text = tostring(p.maxDistance or 80)
            else
                for _, prop in ipairs(FX_PROPS) do
                    if p[prop.key] ~= nil then fxBoxes[prop.key].Text = tostring(p[prop.key]) end
                end
                if nextType == "Fade" then
                    fxFadeImgBox.Text = p.imageId or ""
                    self._spawnedFxDir = p.direction or "out"
                    fxFadeDirBtn.Text = "  out (to colour)  "
                end
            end
        end
    end)

    fxAddBtn.MouseButton1Click:Connect(function()
        local isFade = self._spawnedFxType == "Fade"
        local pos = self._spawnedFxPos
        if not pos and not isFade then return end
        local data = {
            frame      = self._spawnedFxFrame or 1,
            effectType = self._spawnedFxType  or "Explosion",
        }
        if pos then
            data.posX, data.posY, data.posZ = pos.X, pos.Y, pos.Z
        end
        if self._spawnedFxType == "Sound" then
            data.soundId     = fxSoundIdBox.Text
            data.volume      = tonumber(fxSoundVolBox.Text) or 1
            data.maxDistance = tonumber(fxSoundDistBox.Text) or 80
        elseif isFade then
            data.colorR   = tonumber(fxBoxes.colorR.Text) or 0
            data.colorG   = tonumber(fxBoxes.colorG.Text) or 0
            data.colorB   = tonumber(fxBoxes.colorB.Text) or 0
            data.duration = tonumber(fxBoxes.duration.Text) or 1
            data.imageId  = fxFadeImgBox.Text
            data.direction = self._spawnedFxDir or "out"
        else
            for _, prop in ipairs(FX_PROPS) do
                data[prop.key] = tonumber(fxBoxes[prop.key].Text) or 1
            end
        end
        if self._spawnedFxEditId then
            data.id = self._spawnedFxEditId
            eSpawnedFxUpdate:Fire(data)
        else
            eSpawnedFxAdd:Fire(data)
        end
        fxOv.Visible = false
    end)

    fxDeleteBtn.MouseButton1Click:Connect(function()
        if self._spawnedFxEditId then
            eSpawnedFxDelete:Fire(self._spawnedFxEditId)
        end
        fxOv.Visible = false
    end)

    self._fxOv        = fxOv
    self._fxOvTitle   = fxOvTitle
    self._fxTypeBtn   = fxTypeBtn
    self._fxBoxes     = fxBoxes
    self._fxCoordLbl  = fxCoordLbl
    self._fxAddBtn    = fxAddBtn
    self._fxDeleteBtn = fxDeleteBtn
    self._spawnedFxType   = "Explosion"
    self._spawnedFxFrame  = 1
    self._spawnedFxEditId = nil
    self._spawnedFxPos    = nil

    function self:showSpawnedFxOverlay(frame, data)
        self._spawnedFxFrame  = frame or 1
        self._spawnedFxEditId = data and data.id or nil
        local effectType = (data and data.effectType) or "Explosion"
        self._spawnedFxType = effectType
        fxTypeBtn.Text = "  " .. effectType .. "  "
        fxApplyTypeVisibility(effectType)
        fxPosRow.Visible = effectType ~= "Fade"
        local isSound = effectType == "Sound"
        local isFade  = effectType == "Fade"
        local defaults = FX_DEFAULTS[effectType] or FX_DEFAULTS.Explosion
        if isFade then
            local src = data or defaults
            self._spawnedFxDir = src.direction or "out"
            fxFadeDirBtn.Text = self._spawnedFxDir == "out"
                and "  out (to colour)  " or "  in (reveal scene)  "
            fxFadeImgBox.Text = src.imageId or ""
        end
        if data then
            if isSound then
                fxSoundIdBox.Text   = data.soundId     or defaults.soundId or ""
                fxSoundVolBox.Text  = tostring(data.volume      ~= nil and data.volume      or (defaults.volume or 1))
                fxSoundDistBox.Text = tostring(data.maxDistance ~= nil and data.maxDistance or (defaults.maxDistance or 80))
            else
                for _, prop in ipairs(FX_PROPS) do
                    fxBoxes[prop.key].Text = tostring(data[prop.key] ~= nil and data[prop.key] or (defaults[prop.key] or ""))
                end
            end
            if data.posX then
                self._spawnedFxPos = Vector3.new(data.posX, data.posY, data.posZ)
                fxCoordLbl.Text = string.format("X:%.1f  Y:%.1f  Z:%.1f", data.posX, data.posY, data.posZ)
            else
                self._spawnedFxPos = nil
                fxCoordLbl.Text = "X: —  Y: —  Z: —"
            end
        else
            if isSound then
                fxSoundIdBox.Text   = defaults.soundId or ""
                fxSoundVolBox.Text  = tostring(defaults.volume or 1)
                fxSoundDistBox.Text = tostring(defaults.maxDistance or 80)
            else
                for _, prop in ipairs(FX_PROPS) do
                    fxBoxes[prop.key].Text = tostring(defaults[prop.key] ~= nil and defaults[prop.key] or "")
                end
            end
            self._spawnedFxPos = nil
            fxCoordLbl.Text = "X: —  Y: —  Z: —"
        end
        fxOvTitle.Text    = data and ("EDIT EFFECT  •  FRAME " .. frame) or ("ADD EFFECT  •  FRAME " .. frame)
        fxDeleteBtn.Visible = data ~= nil
        fxAddBtn.Text     = data and "  Update  " or "  Add to Frame  "
        fxOv.Visible      = true
    end

    function self:setSpawnedFxPosition(pos)
        self._spawnedFxPos = pos
        fxCoordLbl.Text = string.format("X:%.1f  Y:%.1f  Z:%.1f", pos.X, pos.Y, pos.Z)
    end
    end -- SPAWNED FX OVERLAY

    do -- ── PLAYBACK TAB ────────────────────────────────────────────────────
    -- Third mode: select a saved scene, map each rig slot to a workspace rig
    -- or a player (clone/direct), set FPS/Loop/MovieMode, then copy the
    -- generated Lua snippet or preview directly from the plugin.

    local playbackSec = section(root, "PLAYBACK", 1)
    playbackSec.Visible = false
    self._playbackSec = playbackSec

    -- Scene selector row: ◄ [scene name] ►
    local pbSceneRow = hrow(playbackSec, 1, 4)
    local pbScenePrevBtn = smallBtn(pbSceneRow, "◄", 1)
    local pbSceneBox = textBox(pbSceneRow, "—", 120, 2)
    self._pbSceneBox = pbSceneBox
    local pbSceneNextBtn = smallBtn(pbSceneRow, "►", 3)
    pbSceneBox.FocusLost:Connect(function()
        local name = pbSceneBox.Text
        ePlaybackSceneChanged:Fire(name)
    end)
    pbScenePrevBtn.MouseButton1Click:Connect(function()
        ePlaybackSceneChanged:Fire("__prev__")
    end)
    pbSceneNextBtn.MouseButton1Click:Connect(function()
        ePlaybackSceneChanged:Fire("__next__")
    end)

    -- Warning label: shown when selected scene has no export in ServerStorage
    local pbWarnLbl = Instance.new("TextLabel")
    pbWarnLbl.Name                 = "PBExportWarning"
    pbWarnLbl.Size                 = UDim2.new(1, 0, 0, 14)
    pbWarnLbl.BackgroundTransparency = 1
    pbWarnLbl.TextColor3           = C.warning
    pbWarnLbl.Text                 = ""
    pbWarnLbl.TextSize             = 11
    pbWarnLbl.Font                 = Enum.Font.GothamBold
    pbWarnLbl.TextXAlignment       = Enum.TextXAlignment.Left
    pbWarnLbl.LayoutOrder          = 2
    pbWarnLbl.Visible              = false
    pbWarnLbl.Parent               = playbackSec
    self._pbWarnLbl = pbWarnLbl

    function self:setPlaybackExportWarning(msg)
        if self._pbWarnLbl then
            self._pbWarnLbl.Text    = msg or ""
            self._pbWarnLbl.Visible = (msg ~= nil and msg ~= "")
        end
    end

    -- Rig mapping header
    local pbRigHdr = hrow(playbackSec, 3, 2)
    lbl(pbRigHdr, "Rig slot → workspace / player", nil, 1)

    -- Rig rows container (dynamically populated by _rebuildPlaybackRigRows)
    local pbRigContainer = Instance.new("Frame")
    pbRigContainer.Name               = "PBRigContainer"
    pbRigContainer.Size               = UDim2.new(1, 0, 0, 0)
    pbRigContainer.AutomaticSize      = Enum.AutomaticSize.Y
    pbRigContainer.BackgroundTransparency = 1
    pbRigContainer.LayoutOrder        = 4
    pbRigContainer.Parent             = playbackSec
    listLayout(pbRigContainer, Enum.FillDirection.Vertical, 2)
    self._pbRigContainer = pbRigContainer

    -- Rig mode constants (used by _rebuildPlaybackRigRows)
    local RIG_MODES = {
        { key = "fixed",        label = "Fixed rig"          },
        { key = "localClone",   label = "LocalPlayer—clone"  },
        { key = "localDirect",  label = "LocalPlayer—direct" },
        { key = "userIdClone",  label = "UserId—clone"       },
        { key = "userIdDirect", label = "UserId—direct"      },
    }

    -- Params row: Loop / Movie Mode / Reset On End (FPS removed — set during export)
    local pbParamRow = hrow(playbackSec, 5, 4)
    local pbLoopBtn = btn(pbParamRow, "Loop: OFF", 1)
    self._pbLoopBtn = pbLoopBtn
    self._pbLoop = false
    pbLoopBtn.MouseButton1Click:Connect(function()
        self._pbLoop = not self._pbLoop
        pbLoopBtn.Text = "Loop: " .. (self._pbLoop and "ON" or "OFF")
        ePlaybackParams:Fire({ loop = self._pbLoop, movieMode = self._pbMovieMode, resetOnEnd = self._pbResetOnEnd })
    end)
    local pbMovieBtn = btn(pbParamRow, "Movie: ON", 2)
    self._pbMovieBtn = pbMovieBtn
    self._pbMovieMode = true
    pbMovieBtn.MouseButton1Click:Connect(function()
        self._pbMovieMode = not self._pbMovieMode
        pbMovieBtn.Text = "Movie: " .. (self._pbMovieMode and "ON" or "OFF")
        ePlaybackParams:Fire({ loop = self._pbLoop, movieMode = self._pbMovieMode, resetOnEnd = self._pbResetOnEnd })
    end)
    local pbResetBtn = btn(pbParamRow, "Reset: OFF", 3)
    self._pbResetBtn    = pbResetBtn
    self._pbResetOnEnd  = false
    pbResetBtn.MouseButton1Click:Connect(function()
        self._pbResetOnEnd = not self._pbResetOnEnd
        pbResetBtn.Text = "Reset: " .. (self._pbResetOnEnd and "ON" or "OFF")
        ePlaybackParams:Fire({ loop = self._pbLoop, movieMode = self._pbMovieMode, resetOnEnd = self._pbResetOnEnd })
    end)
    -- Auto-pads: build/update a trigger pad for each exported scene
    local pbPadsBtn = btn(pbParamRow, "Pads: ON", 4)
    self._autoPadsOn = true
    pbPadsBtn.MouseButton1Click:Connect(function()
        self._autoPadsOn = not self._autoPadsOn
        pbPadsBtn.Text = "Pads: " .. (self._autoPadsOn and "ON" or "OFF")
        eAutoPads:Fire(self._autoPadsOn)
    end)
    function self:setAutoPadsState(on)
        self._autoPadsOn = on
        pbPadsBtn.Text = "Pads: " .. (on and "ON" or "OFF")
    end

    -- Snippet label
    local pbSnipHdr = hrow(playbackSec, 6, 2)
    lbl(pbSnipHdr, "Lua snippet  (paste into a LocalScript)", nil, 1)

    -- Snippet TextBox (multi-line, read-only display)
    local pbSnipFrame = Instance.new("Frame")
    pbSnipFrame.Name               = "PBSnipFrame"
    pbSnipFrame.Size               = UDim2.new(1, -8, 0, 120)
    pbSnipFrame.BackgroundColor3   = Color3.fromRGB(30, 30, 30)
    pbSnipFrame.BorderSizePixel    = 0
    pbSnipFrame.LayoutOrder        = 7
    pbSnipFrame.Parent             = playbackSec
    Instance.new("UICorner", pbSnipFrame).CornerRadius = UDim.new(0, 4)
    Instance.new("UIPadding", pbSnipFrame).PaddingLeft = UDim.new(0, 4)

    local pbSnipBox = Instance.new("TextBox")
    pbSnipBox.Name              = "SnippetBox"
    pbSnipBox.Size              = UDim2.new(1, 0, 1, 0)
    pbSnipBox.BackgroundTransparency = 1
    pbSnipBox.TextColor3        = Color3.fromRGB(200, 230, 200)
    pbSnipBox.Text              = "-- select a scene above --"
    pbSnipBox.TextSize          = 10
    pbSnipBox.Font              = Enum.Font.Code
    pbSnipBox.TextXAlignment    = Enum.TextXAlignment.Left
    pbSnipBox.TextYAlignment    = Enum.TextYAlignment.Top
    pbSnipBox.MultiLine         = true
    pbSnipBox.TextWrapped       = false
    pbSnipBox.ClearTextOnFocus  = false
    pbSnipBox.Parent            = pbSnipFrame
    self._pbSnipBox = pbSnipBox

    -- Spacer between snippet box and action buttons
    local pbSnipSpacer = Instance.new("Frame")
    pbSnipSpacer.Size               = UDim2.new(1, 0, 0, 6)
    pbSnipSpacer.BackgroundTransparency = 1
    pbSnipSpacer.LayoutOrder        = 8
    pbSnipSpacer.Parent             = playbackSec

    -- Copy Snippet button (below snippet box)
    local pbCopyRow = hrow(playbackSec, 9, 4)
    local pbCopyBtn = btn(pbCopyRow, "📋 Copy Snippet", 1)
    pbCopyBtn.MouseButton1Click:Connect(function()
        ePlaybackCopy:Fire(pbSnipBox.Text)
    end)
    -- Insert the snippet as real Script instances in the place (best-practice
    -- structure); the handler in init.server.lua reads settings (Pads etc.).
    do
        local ePlaybackInsert = mkEvent("onPlaybackInsertSnippet")
        local pbInsertBtn = btn(pbCopyRow, "⬇ Add to Roblox", 2)
        pbInsertBtn.MouseButton1Click:Connect(function()
            ePlaybackInsert:Fire(pbSnipBox.Text)
        end)
    end
    -- Preview button: shows snippet in a modal overlay
    local pbPreviewBtn = btn(pbCopyRow, "Preview", 3, true)

    -- Preview modal overlay (shows full snippet in a larger scrollable box)
    local pbPreviewOv = Instance.new("Frame")
    pbPreviewOv.Name               = "PBPreviewOverlay"
    pbPreviewOv.Size               = UDim2.new(1, -16, 0, 220)
    pbPreviewOv.AnchorPoint        = Vector2.new(0.5, 0.5)
    pbPreviewOv.Position           = UDim2.new(0.5, 0, 0.5, 0)
    pbPreviewOv.BackgroundColor3   = Color3.fromRGB(28, 28, 28)
    pbPreviewOv.BorderSizePixel    = 0
    pbPreviewOv.ZIndex             = 55
    pbPreviewOv.Visible            = false
    pbPreviewOv.Parent             = widget
    Instance.new("UICorner", pbPreviewOv).CornerRadius = UDim.new(0, 6)
    local _pvStroke = Instance.new("UIStroke")
    _pvStroke.Color     = Color3.fromRGB(80, 180, 255)
    _pvStroke.Thickness = 1
    _pvStroke.Parent    = pbPreviewOv
    listLayout(pbPreviewOv, Enum.FillDirection.Vertical, 6)
    addPadding(pbPreviewOv, 8, 8)

    local pvHdrRow = hrow(pbPreviewOv, 1, 4)
    local pvHdrLbl = lbl(pvHdrRow, "Snippet preview", nil, 1)
    pvHdrLbl.TextColor3 = C.header
    local pvCloseBtn = smallBtn(pvHdrRow, "✕", 2)
    pvCloseBtn.MouseButton1Click:Connect(function() pbPreviewOv.Visible = false end)

    local pvSnipBox = Instance.new("TextBox")
    pvSnipBox.Name              = "PreviewSnipBox"
    pvSnipBox.Size              = UDim2.new(1, 0, 1, -34)
    pvSnipBox.BackgroundTransparency = 1
    pvSnipBox.TextColor3        = Color3.fromRGB(200, 230, 200)
    pvSnipBox.Text              = ""
    pvSnipBox.TextSize          = 10
    pvSnipBox.Font              = Enum.Font.Code
    pvSnipBox.TextXAlignment    = Enum.TextXAlignment.Left
    pvSnipBox.TextYAlignment    = Enum.TextYAlignment.Top
    pvSnipBox.MultiLine         = true
    pvSnipBox.TextWrapped       = false
    pvSnipBox.ClearTextOnFocus  = false
    pvSnipBox.LayoutOrder       = 2
    pvSnipBox.Parent            = pbPreviewOv
    pvSnipBox.ZIndex            = 56

    pbPreviewBtn.MouseButton1Click:Connect(function()
        pvSnipBox.Text          = pbSnipBox.Text
        pbPreviewOv.Visible     = true
        ePlaybackPreview:Fire()
    end)

    -- Closure that rebuilds per-rig rows when the scene changes.
    -- `rigNames` is a sorted list of rig name strings from the scene.
    -- `currentModes` is a {[rigName] = modeKey} table (persisted by init.server.lua).
    self._rebuildPlaybackRigRows = function(rigNames, currentModes)
        currentModes = currentModes or {}
        for _, c in ipairs(pbRigContainer:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        self._pbRigModes = {}
        for i, rigName in ipairs(rigNames) do
            local row = hrow(pbRigContainer, i, 2)
            lbl(row, rigName .. ":", 60, 1)
            -- Mode cycle button
            local curMode = currentModes[rigName] or "fixed"
            local modeIdx = 1
            for idx, m in ipairs(RIG_MODES) do if m.key == curMode then modeIdx = idx; break end end
            self._pbRigModes[rigName] = RIG_MODES[modeIdx].key
            local modeBtn = btn(row, RIG_MODES[modeIdx].label, 2)
            modeBtn.MouseButton1Click:Connect(function()
                modeIdx = (modeIdx % #RIG_MODES) + 1
                local m = RIG_MODES[modeIdx]
                modeBtn.Text = m.label
                self._pbRigModes[rigName] = m.key
                ePlaybackRig:Fire(rigName, m.key)
            end)
            -- UserId textbox (only relevant for userId* modes, but always shown)
            local uidBox = textBox(row, "", 60, 3)
            uidBox.PlaceholderText = "UserId"
            self._pbRigUserIds = self._pbRigUserIds or {}
            uidBox.FocusLost:Connect(function()
                self._pbRigUserIds[rigName] = tonumber(uidBox.Text) or nil
                ePlaybackRig:Fire(rigName, self._pbRigModes[rigName])
            end)
        end
    end
    end -- ── end PLAYBACK TAB ────────────────────────────────────────────────

    -- ── Context menu overlay (parented to widget, covers full panel) ─────────
    local ctxOverlay = Instance.new("TextButton")
    ctxOverlay.Name              = "CtxOverlay"
    ctxOverlay.Size              = UDim2.new(1, 0, 1, 0)
    ctxOverlay.BackgroundTransparency = 1
    ctxOverlay.Text              = ""
    ctxOverlay.AutoButtonColor   = false
    ctxOverlay.ZIndex            = 40
    ctxOverlay.Visible           = false
    ctxOverlay.Parent            = widget
    self._ctxOverlay = ctxOverlay

    local ctxMenu = Instance.new("Frame")
    ctxMenu.Name              = "CtxMenu"
    ctxMenu.Size              = UDim2.new(0, 140, 0, 0)
    ctxMenu.AutomaticSize     = Enum.AutomaticSize.Y
    ctxMenu.BackgroundColor3  = Color3.fromRGB(55, 55, 55)
    ctxMenu.BorderSizePixel   = 0
    ctxMenu.ZIndex            = 41
    ctxMenu.Visible           = false
    ctxMenu.Parent            = widget
    Instance.new("UICorner", ctxMenu).CornerRadius = UDim.new(0, 4)
    local ctxLayout = Instance.new("UIListLayout")
    ctxLayout.SortOrder      = Enum.SortOrder.LayoutOrder
    ctxLayout.FillDirection  = Enum.FillDirection.Vertical
    ctxLayout.Padding        = UDim.new(0, 0)
    ctxLayout.Parent         = ctxMenu
    self._ctxMenu = ctxMenu

    ctxOverlay.MouseButton1Click:Connect(function() self:_hideMenu() end)

    -- ── Name-remap dialog ─────────────────────────────────────────────────────
    do
        local remapOv = Instance.new("Frame")
        remapOv.Name             = "NameRemapOverlay"
        remapOv.Size             = UDim2.new(0, 280, 0, 0)
        remapOv.AutomaticSize    = Enum.AutomaticSize.Y
        remapOv.AnchorPoint      = Vector2.new(0.5, 0.5)
        remapOv.Position         = UDim2.new(0.5, 0, 0.5, 0)
        remapOv.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        remapOv.BorderSizePixel  = 0
        remapOv.ZIndex           = 60
        remapOv.Visible          = false
        remapOv.Parent           = widget
        Instance.new("UICorner", remapOv).CornerRadius = UDim.new(0, 6)
        local _rmStroke = Instance.new("UIStroke")
        _rmStroke.Color     = Color3.fromRGB(90, 90, 90)
        _rmStroke.Thickness = 1
        _rmStroke.Parent    = remapOv
        listLayout(remapOv, Enum.FillDirection.Vertical, 4)
        addPadding(remapOv, 10, 10)

        local remapHdr = Instance.new("TextLabel")
        remapHdr.Size                   = UDim2.new(1, 0, 0, 14)
        remapHdr.BackgroundTransparency = 1
        remapHdr.TextColor3             = C.header
        remapHdr.Text                   = "RENAMED OBJECTS"
        remapHdr.TextSize               = 10
        remapHdr.Font                   = Enum.Font.GothamBold
        remapHdr.TextXAlignment         = Enum.TextXAlignment.Left
        remapHdr.LayoutOrder            = 1
        remapHdr.ZIndex                 = 61
        remapHdr.Parent                 = remapOv

        local remapSub = Instance.new("TextLabel")
        remapSub.Size                   = UDim2.new(1, 0, 0, 28)
        remapSub.BackgroundTransparency = 1
        remapSub.TextColor3             = C.muted
        remapSub.Text                   = "Map old track name to new name in folder. Click to cycle."
        remapSub.TextSize               = 10
        remapSub.Font                   = Enum.Font.Gotham
        remapSub.TextXAlignment         = Enum.TextXAlignment.Left
        remapSub.TextWrapped            = true
        remapSub.LayoutOrder            = 2
        remapSub.ZIndex                 = 61
        remapSub.Parent                 = remapOv

        local remapRowsFrame = Instance.new("ScrollingFrame")
        remapRowsFrame.Name                 = "RemapRows"
        remapRowsFrame.Size                 = UDim2.new(1, 0, 0, 120)
        remapRowsFrame.CanvasSize           = UDim2.new(0, 0, 0, 0)
        remapRowsFrame.AutomaticCanvasSize  = Enum.AutomaticSize.Y
        remapRowsFrame.ScrollBarThickness   = 4
        remapRowsFrame.BackgroundTransparency = 1
        remapRowsFrame.BorderSizePixel      = 0
        remapRowsFrame.LayoutOrder          = 3
        remapRowsFrame.ZIndex               = 61
        remapRowsFrame.Parent               = remapOv
        listLayout(remapRowsFrame, Enum.FillDirection.Vertical, 3)

        local remapBtnRow = hrow(remapOv, 4, 4)
        local remapApply  = btn(remapBtnRow, "Apply", 1)
        local remapCancel = btn(remapBtnRow, "Cancel", 2)

        local _remapCallback   = nil
        local _remapSelections = {}

        remapCancel.MouseButton1Click:Connect(function()
            remapOv.Visible = false
            _remapCallback  = nil
        end)
        remapApply.MouseButton1Click:Connect(function()
            remapOv.Visible = false
            if _remapCallback then _remapCallback(_remapSelections) end
            _remapCallback = nil
        end)

        function self:showNameRemapDialog(entries, onApply)
            for _, ch in ipairs(remapRowsFrame:GetChildren()) do
                if ch:IsA("GuiObject") then ch:Destroy() end
            end
            _remapSelections = {}
            _remapCallback   = onApply

            for i, entry in ipairs(entries) do
                local options = { "(skip)" }
                for _, c in ipairs(entry.candidates) do table.insert(options, c) end
                _remapSelections[entry.oldName] = entry.candidates[1]

                local row = Instance.new("Frame")
                row.Size                   = UDim2.new(1, 0, 0, 22)
                row.BackgroundTransparency = 1
                row.LayoutOrder            = i
                row.ZIndex                 = 62
                row.Parent                 = remapRowsFrame

                local oldLbl = Instance.new("TextLabel")
                oldLbl.Size                   = UDim2.new(0.44, 0, 1, 0)
                oldLbl.BackgroundTransparency = 1
                oldLbl.TextColor3             = C.ovText
                oldLbl.Text                   = entry.oldName
                oldLbl.TextSize               = 10
                oldLbl.Font                   = Enum.Font.Gotham
                oldLbl.TextXAlignment         = Enum.TextXAlignment.Left
                oldLbl.TextTruncate           = Enum.TextTruncate.AtEnd
                oldLbl.ZIndex                 = 62
                oldLbl.Parent                 = row

                local arrowLbl = Instance.new("TextLabel")
                arrowLbl.Size                   = UDim2.new(0, 14, 1, 0)
                arrowLbl.Position               = UDim2.new(0.44, 0, 0, 0)
                arrowLbl.BackgroundTransparency = 1
                arrowLbl.TextColor3             = C.muted
                arrowLbl.Text                   = "→"
                arrowLbl.TextSize               = 10
                arrowLbl.Font                   = Enum.Font.Gotham
                arrowLbl.ZIndex                 = 62
                arrowLbl.Parent                 = row

                local cycleBtn = Instance.new("TextButton")
                cycleBtn.Size             = UDim2.new(0.56, -16, 1, -2)
                cycleBtn.Position         = UDim2.new(0.44, 16, 0, 1)
                cycleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
                cycleBtn.BorderSizePixel  = 0
                cycleBtn.TextColor3       = C.btnText
                cycleBtn.Text             = entry.candidates[1]
                cycleBtn.TextSize         = 10
                cycleBtn.Font             = Enum.Font.Gotham
                cycleBtn.TextTruncate     = Enum.TextTruncate.AtEnd
                cycleBtn.ZIndex           = 62
                cycleBtn.Parent           = row
                Instance.new("UICorner", cycleBtn).CornerRadius = UDim.new(0, 3)

                local oldName = entry.oldName
                local optIdx  = 2
                cycleBtn.MouseButton1Click:Connect(function()
                    optIdx = (optIdx % #options) + 1
                    cycleBtn.Text = options[optIdx]
                    _remapSelections[oldName] = options[optIdx] ~= "(skip)" and options[optIdx] or nil
                end)
            end

            remapOv.Visible = true
        end
    end

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
        lane.onMarkerDeleteRequested:Connect(function(frame, pos)
            self:_showContextMenu("rig", name, frame, pos)
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

function Panel:getActiveProps()
    return self.propSelector:getActiveProps()
end

function Panel:getStepSize()
    local n = tonumber(self._stepBox and self._stepBox.Text or "2")
    return math.max(1, math.floor(n or 2))
end

-- Add a prop to the PropSelector and create a teal track lane for it.
function Panel:addProp(propName, part)
    self.propSelector:addProp(propName, part)

    if not self._propTrackLanes[propName] then
        local order = 100 + (function()
            local n = 0
            for _ in pairs(self._propTrackLanes) do n += 1 end
            return n
        end)()
        local lane = TrackLane.new(self._tlSec, propName, self._frameCount, order, PROP_COLOUR)
        lane.onMarkerClicked:Connect(function(frame)
            self._evts[4]:Fire(propName, frame)   -- eMarker (shared with rigs)
        end)
        lane.onMarkerDeleteRequested:Connect(function(frame, pos)
            self:_showContextMenu("prop", propName, frame, pos)
        end)
        lane.onDoubleClicked:Connect(function(frame)
            self._ePropDbl:Fire(propName, frame)
        end)
        self._propTrackLanes[propName] = lane
    end
end

-- Remove a prop from the PropSelector and destroy its track lane.
function Panel:removeProp(propName)
    self.propSelector:removeProp(propName)
    local lane = self._propTrackLanes[propName]
    if lane then
        lane:destroy()
        self._propTrackLanes[propName] = nil
    end
end

function Panel:addPropKeyframeMarker(propName, frame)
    local lane = self._propTrackLanes[propName]
    if lane then lane:addMarker(frame) end
end

function Panel:removePropKeyframeMarker(propName, frame)
    local lane = self._propTrackLanes[propName]
    if lane then lane:removeMarker(frame) end
end

function Panel:addKeyframeMarker(rigName, frame)
    local lane = self._trackLanes[rigName]
    if lane then lane:addMarker(frame) end
end

-- ── Playback tab ──────────────────────────────────────────────────────────────

-- Update the scene name display in the Playback tab.
function Panel:setPlaybackSceneDisplay(name)
    if self._pbSceneBox then
        self._pbSceneBox.Text = name or "—"
    end
end

-- Rebuild per-rig mapping rows for the given scene's rig names.
-- currentModes: { [rigName] = modeKey } (persisted by init.server.lua).
function Panel:rebuildPlaybackRigRows(rigNames, currentModes)
    if self._rebuildPlaybackRigRows then
        self._rebuildPlaybackRigRows(rigNames, currentModes)
    end
end

-- Update the snippet TextBox content.
function Panel:setPlaybackSnippet(text)
    if self._pbSnipBox then
        self._pbSnipBox.Text = text or ""
    end
end

function Panel:focusSnippetBox()
    if self._pbSnipBox then self._pbSnipBox:CaptureFocus() end
end

function Panel:setPlaybackFPSDisplay(_fps) end -- FPS removed from playback tab

-- Push Loop state display.
function Panel:setPlaybackLoopDisplay(on)
    self._pbLoop = on and true or false
    if self._pbLoopBtn then
        self._pbLoopBtn.Text = "Loop: " .. (self._pbLoop and "ON" or "OFF")
    end
end

-- Push ResetOnEnd state display.
function Panel:setPlaybackResetOnEndDisplay(on)
    self._pbResetOnEnd = on and true or false
    if self._pbResetBtn then
        self._pbResetBtn.Text = "Reset: " .. (self._pbResetOnEnd and "ON" or "OFF")
    end
end

-- Push MovieMode state display.
function Panel:setPlaybackMovieModeDisplay(on)
    self._pbMovieMode = on and true or false
    if self._pbMovieBtn then
        self._pbMovieBtn.Text = "Movie: " .. (self._pbMovieMode and "ON" or "OFF")
    end
end

-- Return current rig mode table { [rigName] = modeKey }.
function Panel:getPlaybackRigModes()
    return self._pbRigModes or {}
end

-- Return current per-rig UserIds { [rigName] = userId | nil }.
function Panel:getPlaybackRigUserIds()
    return self._pbRigUserIds or {}
end

-- ── Effects ───────────────────────────────────────────────────────────────────
-- Each tracked effect gets a chip in the FX row (click = cycle action,
-- × = untrack) and a purple track lane for its one-shot events.

function Panel:addEffect(effectName, action)
    if self._effectChips[effectName] then
        self:setEffectAction(effectName, action)
        return
    end

    local chip = Instance.new("Frame")
    chip.Name = "Fx_" .. effectName
    chip.Size = UDim2.new(0, 0, 0, 22)
    chip.AutomaticSize = Enum.AutomaticSize.X
    chip.BackgroundTransparency = 1
    chip.LayoutOrder = 10
    chip.Parent = self._fxRow

    local chipLayout = Instance.new("UIListLayout")
    chipLayout.FillDirection = Enum.FillDirection.Horizontal
    chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
    chipLayout.Padding = UDim.new(0, 2)
    chipLayout.Parent = chip

    local main = Instance.new("TextButton")
    main.Name = "Cycle"
    main.Size = UDim2.new(0, 0, 1, 0)
    main.AutomaticSize = Enum.AutomaticSize.X
    main.BackgroundColor3 = Color3.fromRGB(60, 45, 80)
    main.BorderSizePixel = 0
    main.TextColor3 = EFFECT_COLOUR
    main.Font = Enum.Font.Gotham
    main.TextSize = 11
    main.Text = " " .. effectName .. ": " .. (action or "?") .. " "
    main.LayoutOrder = 1
    main.Parent = chip
    main.MouseButton1Click:Connect(function()
        if not self._isPlaying then self._eFxCycle:Fire(effectName) end
    end)

    local close = Instance.new("TextButton")
    close.Name = "Remove"
    close.Size = UDim2.new(0, 18, 1, 0)
    close.BackgroundColor3 = Color3.fromRGB(60, 45, 80)
    close.BorderSizePixel = 0
    close.TextColor3 = Color3.fromRGB(220, 150, 150)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 11
    close.Text = "×"
    close.LayoutOrder = 2
    close.Parent = chip
    close.MouseButton1Click:Connect(function()
        self:removeEffect(effectName)
        self._eFxRemoved:Fire(effectName)
    end)

    self._effectChips[effectName] = chip

    if not self._effectLanes[effectName] then
        local order = 200 + (function()
            local n = 0
            for _ in pairs(self._effectLanes) do n += 1 end
            return n
        end)()
        local lane = TrackLane.new(self._tlSec, effectName, self._frameCount, order, EFFECT_COLOUR)
        lane.onMarkerClicked:Connect(function(frame)
            self._eFxMarker:Fire(effectName, frame)
        end)
        lane.onMarkerDeleteRequested:Connect(function(frame, pos)
            self:_showContextMenu("effect", effectName, frame, pos)
        end)
        lane.onDoubleClicked:Connect(function(frame)
            self._eFxDbl:Fire(effectName, frame)
        end)
        self._effectLanes[effectName] = lane
    end
end

function Panel:removeEffect(effectName)
    local chip = self._effectChips[effectName]
    if chip then
        chip:Destroy()
        self._effectChips[effectName] = nil
    end
    local lane = self._effectLanes[effectName]
    if lane then
        lane:destroy()
        self._effectLanes[effectName] = nil
    end
end

function Panel:setEffectAction(effectName, action)
    local chip = self._effectChips[effectName]
    local main = chip and chip:FindFirstChild("Cycle")
    if main then
        main.Text = " " .. effectName .. ": " .. action .. " "
    end
end

function Panel:addEffectMarker(effectName, frame)
    local lane = self._effectLanes[effectName]
    if lane then lane:addMarker(frame) end
end

function Panel:removeEffectMarker(effectName, frame)
    local lane = self._effectLanes[effectName]
    if lane then lane:removeMarker(frame) end
end

-- ── Camera lane ───────────────────────────────────────────────────────────────
-- One lane for the whole session, created on the first camera keyframe.
-- Move keyframes are orange, cut keyframes red.

function Panel:_ensureCameraLane()
    if self._cameraLane then return self._cameraLane end
    -- Order 50: below the rig lanes (1..n), above the prop lanes (100+).
    local lane = TrackLane.new(self._tlSec, "Camera", self._frameCount, 50, CAMERA_COLOUR)
    lane.onMarkerClicked:Connect(function(frame)
        self._eCamMarker:Fire(frame)
    end)
    lane.onMarkerDeleteRequested:Connect(function(frame, pos)
        self:_showContextMenu("camera", nil, frame, pos)
    end)
    lane.onDoubleClicked:Connect(function(frame)
        self._eCamDbl:Fire(frame)
    end)
    self._cameraLane = lane
    return lane
end

function Panel:addCameraKeyframeMarker(frame, mode)
    local lane = self:_ensureCameraLane()
    lane:addMarker(frame, mode == "cut" and CAMERA_CUT_COLOUR or CAMERA_COLOUR)
end

function Panel:removeCameraKeyframeMarker(frame)
    if self._cameraLane then self._cameraLane:removeMarker(frame) end
end

function Panel:setCameraMarkerMode(frame, mode)
    if self._cameraLane then
        self._cameraLane:setMarkerColour(frame,
            mode == "cut" and CAMERA_CUT_COLOUR or CAMERA_COLOUR)
    end
end

function Panel:setCameraPreviewState(isOn)
    self._camPreviewOn = isOn
    if self._camPreviewBtn then
        self._camPreviewBtn.Text = isOn and "Cam:ON" or "Cam:OFF"
    end
end

-- Shows an amber inline notification bar for 2.5 seconds. Non-blocking.
function Panel:showSimpleNotice(msg)
    if not self._noticeBar then return end
    self._noticeLbl.Text     = msg
    self._noticeBar.Visible  = true
    self._noticeToken        = (self._noticeToken or 0) + 1
    local tok = self._noticeToken
    task.delay(2.5, function()
        if self._noticeToken == tok and self._noticeBar then
            self._noticeBar.Visible = false
        end
    end)
end

function Panel:setSimpleCameraState(isOn)
    self._simpleCamOn = isOn
    -- simpleCamBtn is a local inside Panel.new; update via the stored reference on self
    if self._simpleCamBtn then
        self._simpleCamBtn.Text = "Camera View: " .. (isOn and "ON" or "OFF")
    end
    self:_refreshPinCamEnabled()
end

-- Pin Cam / KF mode are only meaningful with a camera: grey them out otherwise.
function Panel:_refreshPinCamEnabled()
    local on = self._simpleCamOn == true
    for _, b in ipairs({ self._simplePinBtn, self._simpleCamModeBtn }) do
        if b then
            b.AutoButtonColor = on
            b.TextColor3 = on and C.btnText or C.btnDimTxt
        end
    end
end

function Panel:setSimpleLookThroughState(isOn)
    self._simpleLookOn = isOn
    if self._simpleLookBtn then
        self._simpleLookBtn.Text = "Look Through: " .. (isOn and "ON" or "OFF")
    end
end

function Panel:setSimpleOnionState(isOn)
    self._simpleOnionOn = isOn
    if self._simpleOnionBtn then
        self._simpleOnionBtn.Text = "Onion Skin: " .. (isOn and "ON" or "OFF")
    end
end

function Panel:setSimpleFOVDisplay(fov)
    self._simpleFOV = fov
    if self._simpleFOVBox then
        self._simpleFOVBox.Text = string.format("%.0f", fov)
    end
end

function Panel:setSimpleFPSDisplay(fps)
    self._simpleFPS = fps
    if self._simpleFPSBox then
        self._simpleFPSBox.Text = tostring(math.floor(fps))
    end
end

function Panel:setSimpleEasingDisplay(easing)
    if self._simpleEaseBtn then
        self._simpleEaseBtn.Text = "  Ease: " .. (easing or "Linear") .. "  "
    end
end

function Panel:_hideMenu()
    if self._ctxOverlay then self._ctxOverlay.Visible = false end
    if self._ctxMenu then
        self._ctxMenu.Visible = false
        for _, c in ipairs(self._ctxMenu:GetChildren()) do
            if not c:IsA("UIListLayout") and not c:IsA("UICorner") then c:Destroy() end
        end
    end
end

function Panel:_showMenu(items, posX, posY)
    self:_hideMenu()
    local menu = self._ctxMenu
    if not menu then return end
    local menuW = 140
    for i, item in ipairs(items) do
        local r = Instance.new("TextButton")
        r.Size             = UDim2.new(0, menuW, 0, 24)
        r.BackgroundColor3 = item.isDelete and Color3.fromRGB(65, 40, 40) or Color3.fromRGB(55, 55, 55)
        r.BorderSizePixel  = 0
        r.TextColor3       = item.isDelete and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(210, 210, 210)
        r.Text             = "  " .. item.text
        r.TextSize         = 12
        r.Font             = Enum.Font.Gotham
        r.TextXAlignment   = Enum.TextXAlignment.Left
        r.AutoButtonColor  = false
        r.ZIndex           = 41
        r.LayoutOrder      = i
        r.Parent           = menu
        local defBg = r.BackgroundColor3
        r.MouseEnter:Connect(function() r.BackgroundColor3 = Color3.fromRGB(75, 75, 75) end)
        r.MouseLeave:Connect(function() r.BackgroundColor3 = defBg end)
        if item.action then
            r.MouseButton1Click:Connect(function()
                self:_hideMenu()
                item.action()
            end)
        end
    end
    menu.Position = UDim2.new(0, posX, 0, posY)
    self._ctxOverlay.Visible = true
    menu.Visible = true
end

function Panel:_showContextMenu(trackType, name, frame, absPos)
    local overlay = self._ctxOverlay
    if not overlay then return end
    local ox = overlay.AbsolutePosition.X
    local oy = overlay.AbsolutePosition.Y
    local items = {}
    for _, opt in ipairs(EASING_OPTIONS) do
        local easing = opt.easing
        table.insert(items, {
            text = opt.text,
            action = function()
                self._eMarkerEasing:Fire(trackType, name, frame, easing)
            end,
        })
    end
    table.insert(items, {
        text = "─────────────",
        action = nil,
    })
    table.insert(items, {
        text = "Delete Keyframe",
        isDelete = true,
        action = function()
            if trackType == "rig" then
                self._eMarkerDel:Fire(name, frame)
            elseif trackType == "prop" then
                self._ePropMarkerDel:Fire(name, frame)
            elseif trackType == "camera" then
                self._eCamDel:Fire(frame)
            elseif trackType == "effect" then
                self._eFxDel:Fire(name, frame)
            end
        end,
    })
    self:_showMenu(items, absPos.X - ox, absPos.Y - oy + 8)
end

-- Shows the mode of the camera keyframe at the current frame ("move"/"cut"),
-- or "—" when the current frame has no camera keyframe.
function Panel:setCameraModeDisplay(mode)
    if self._camModeBtn then
        self._camModeBtn.Text = "KF:" .. (mode or "—")
    end
    if self._simpleCamModeBtn then
        self._simpleCamModeBtn.Text = "KF:" .. (mode or "—")
    end
end

-- Shows the keyframe-clipboard source, e.g. "Rig1 @ 12" (empty = nothing copied).
function Panel:setClipboardDisplay(text)
    if self._clipLbl then
        self._clipLbl.Text = text or ""
    end
end

function Panel:removeKeyframeMarker(rigName, frame)
    local lane = self._trackLanes[rigName]
    if lane then lane:removeMarker(frame) end
end

function Panel:setFrameDisplay(current, total)
    local prev = self._currentFrame
    self._currentFrame = current
    if total then self._frameCount = total end
    if self._frameBox then self._frameBox.Text = tostring(current) end
    if total and self._totalBox then self._totalBox.Text = tostring(total) end
    if self._scrubber then self._scrubber:setFrame(current) end
    if self._simpleFrameBox then self._simpleFrameBox.Text = tostring(current) end
    if total and self._simpleTotalBox then self._simpleTotalBox.Text = tostring(total) end
    if self._simpleScrubber then
        local slot = (self._simpleFrameToSlot and self._simpleFrameToSlot[current]) or current
        self._simpleScrubber:setFrame(slot)
    end
    -- Update icon strip highlight
    if self._simpleIcons then
        local prevBtn = self._simpleIcons[prev]
        local curBtn  = self._simpleIcons[current]
        if prevBtn then prevBtn.BackgroundColor3 = C.btnBg end
        if curBtn  then curBtn.BackgroundColor3  = C.iconSel end
    end
    for _, lane in pairs(self._trackLanes) do
        lane:setActiveFrame(current)
    end
    for _, lane in pairs(self._propTrackLanes) do
        lane:setActiveFrame(current)
    end
    for _, lane in pairs(self._effectLanes) do
        lane:setActiveFrame(current)
    end
    if self._cameraLane then
        self._cameraLane:setActiveFrame(current)
    end
end

-- ── Simple Mode frame icon strip ─────────────────────────────────────────────

-- Build one icon at slot position slotIdx (1-based).  slotIdx determines the
-- pixel offset so that icons are always packed with no gaps even when the
-- underlying frame numbers are non-consecutive.
function Panel:addSimpleFrameIcon(frame, slotIdx)
    if not self._simpleIconRow or self._simpleIcons[frame] then return end
    local slot = slotIdx or (self._simpleFrameToSlot and self._simpleFrameToSlot[frame]) or frame
    local b = Instance.new("TextButton")
    b.Name             = "FrameIcon_" .. frame
    b.Size             = UDim2.new(0, SIMPLE_ICON_W - 2, 0, SIMPLE_ICON_H)
    b.Position         = UDim2.new(0, (slot - 1) * SIMPLE_ICON_W + 1, 0, 0)
    b.BackgroundColor3 = (frame == self._currentFrame) and C.iconSel or C.btnBg
    b.BorderSizePixel  = 0
    b.Text             = tostring(frame)
    b.TextColor3       = C.btnText
    b.TextSize         = 11
    b.Font             = Enum.Font.Code
    b.AutoButtonColor  = false
    b.Parent           = self._simpleIconRow
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
    b.MouseEnter:Connect(function()
        if frame ~= self._currentFrame then b.BackgroundColor3 = C.btnHover end
    end)
    b.MouseLeave:Connect(function()
        if frame ~= self._currentFrame then b.BackgroundColor3 = C.btnBg
        else b.BackgroundColor3 = C.iconSel end
    end)
    b.MouseButton1Click:Connect(function()
        self._eFrame:Fire(frame)
    end)
    self._simpleIcons[frame] = b
end

function Panel:removeSimpleFrameIcon(frame)
    local b = self._simpleIcons and self._simpleIcons[frame]
    if b then b:Destroy(); self._simpleIcons[frame] = nil end
end

-- Set the slot mapping AND rebuild the icon strip AND resize the scrubber.
-- sortedFrames: sorted list of all keyframed frame numbers.
-- Icons are packed consecutively (slot 1 = leftmost) so there are no gaps
-- even when frame numbers are non-consecutive.
function Panel:setSimpleSlots(sortedFrames)
    local n = #sortedFrames
    -- Rebuild slot ↔ frame lookup tables
    self._simpleSlotFrames  = {}
    self._simpleFrameToSlot = {}
    for i, f in ipairs(sortedFrames) do
        self._simpleSlotFrames[i]  = f
        self._simpleFrameToSlot[f] = i
    end
    -- Resize icon row and scrubber
    local w = math.max(1, n) * SIMPLE_ICON_W
    if self._simpleIconRow then
        self._simpleIconRow.Size = UDim2.new(0, w, 0, SIMPLE_ICON_H)
    end
    if self._simpleScrubRow then
        self._simpleScrubRow.Size = UDim2.new(0, w, 0, 0)
    end
    if self._simpleScrubber then
        self._simpleScrubber:setFrameCount(math.max(1, n))
    end
    -- Rebuild icons at packed slot positions
    if self._simpleIconRow then
        for _, b in pairs(self._simpleIcons) do b:Destroy() end
        self._simpleIcons = {}
        for i, frame in ipairs(sortedFrames) do
            self:addSimpleFrameIcon(frame, i)
        end
    end
end

-- Legacy: resize only (no slot rebuild).  Kept so callers that already
-- call setSimpleSlots don't also need to avoid setSimpleIconWidth.
function Panel:setSimpleIconWidth(frameCount)
    local n = math.max(1, frameCount)
    local w = n * SIMPLE_ICON_W
    if self._simpleIconRow then
        self._simpleIconRow.Size = UDim2.new(0, w, 0, SIMPLE_ICON_H)
    end
    if self._simpleScrubRow then
        self._simpleScrubRow.Size = UDim2.new(0, w, 0, 0)
    end
    if self._simpleScrubber then
        self._simpleScrubber:setFrameCount(n)
    end
end

function Panel:setFrameCount(n)
    self._frameCount = n
    if self._totalBox then self._totalBox.Text = tostring(n) end
    if self._scrubber then self._scrubber:setFrameCount(n) end
    if self._simpleTotalBox then self._simpleTotalBox.Text = tostring(n) end
    if self._simpleScrubber then self._simpleScrubber:setFrameCount(n) end
    for _, lane in pairs(self._trackLanes) do
        lane:setFrameCount(n)
    end
    for _, lane in pairs(self._propTrackLanes) do
        lane:setFrameCount(n)
    end
    for _, lane in pairs(self._effectLanes) do
        lane:setFrameCount(n)
    end
    if self._cameraLane then
        self._cameraLane:setFrameCount(n)
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
    if self._simplePlayBtn then
        self._simplePlayBtn.Text = isPlaying and "■  Stop" or "▶  Play"
    end
end

-- Programmatic mode switch (used by tests / external callers). Does not fire
-- onModeChanged — callers that need init.server.lua's side effects (e.g. the
-- FIGURES scan) should trigger those themselves, mirroring the button handler.
function Panel:setMode(mode)
    self._mode = mode
    if self._refreshModeButtons then self._refreshModeButtons() end
    self:_applyModeVisibility()
end

function Panel:getMode()
    return self._mode
end

function Panel:_applyModeVisibility()
    local m = self._mode
    self._advancedWrap.Visible = (m == "advanced")
    self._simpleSec.Visible    = (m == "simple")
    self._playbackSec.Visible  = (m == "playback")
end

function Panel:_showNewOverlay()
    self._newOverlay.Visible = true
end

function Panel:_showSaveOverlay()
    local currentName = (self._mode == "simple" and self._simpleSceneBox and self._simpleSceneBox.Text)
        or (self._sceneNameBox and self._sceneNameBox.Text)
        or self._lastSaveName
        or "Scene_001"
    self._saveOvBox.Text = currentName
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

function Panel:showDeleteList(saves)
    for _, c in ipairs(self._deleteScroll:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    self._delConfOv.Visible  = false
    self._delPendingName     = nil
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
        e.Parent             = self._deleteScroll
        self._deleteScroll.CanvasSize = UDim2.new(0, 0, 0, 40)
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
            row.Parent           = self._deleteScroll

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
            row.MouseButton1Click:Connect(function()
                self._delPendingName = name
                self._delConfMsg.Text = 'Are you sure you want to delete\n"' .. name .. '"?'
                self._delConfOv.Visible = true
            end)
        end
        self._deleteScroll.CanvasSize = UDim2.new(0, 0, 0, #saves * (_ROW_H + 1))
    end
    self._deleteOverlay.Visible = true
end

function Panel:hideDeleteList()
    self._deleteOverlay.Visible = false
end

function Panel:destroy()
    if self._scrubber then self._scrubber:destroy() end
    if self._simpleScrubber then self._simpleScrubber:destroy() end
    for _, e in ipairs(self._evts) do e:Destroy() end
    for _, lane in pairs(self._trackLanes) do lane:destroy() end
    for _, lane in pairs(self._propTrackLanes) do lane:destroy() end
    self.rigSelector:destroy()
    self.propSelector:destroy()
end

return Panel
