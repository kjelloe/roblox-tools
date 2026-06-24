-- SubtitleGui — shows/hides a subtitle overlay in PlayerGui (in-game).
-- Used by CutscenePlayer; deployed to ReplicatedStorage alongside it.
--
-- SubtitleGui.show(text, style)  -- display text with style properties
-- SubtitleGui.hide()             -- remove overlay

local SubtitleGui = {}

local _gui = nil

function SubtitleGui.show(text, style)
    SubtitleGui.hide()
    style = style or {}

    local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 5)
    if not pg then return end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "MultiAnimSubtitleGui"
    sg.ResetOnSpawn   = false
    sg.DisplayOrder   = 201  -- above LetterboxGui (200)
    sg.IgnoreGuiInset = true
    sg.Parent         = pg

    local xOff = style.xOffset or 0.05
    local yOff = style.yOffset or 0.85

    local frame = Instance.new("Frame")
    frame.Size                 = UDim2.new(1 - 2 * xOff, 0, 0, 0)
    frame.AutomaticSize        = Enum.AutomaticSize.Y
    frame.Position             = UDim2.new(xOff, 0, yOff, 0)
    frame.BackgroundColor3     = Color3.fromRGB(
        style.bgColorR or 0, style.bgColorG or 0, style.bgColorB or 0)
    frame.BackgroundTransparency = style.bgTransparency or 0.6
    frame.BorderSizePixel      = 0
    frame.Parent               = sg

    local tl = Instance.new("TextLabel")
    tl.Size               = UDim2.new(1, 0, 0, 0)
    tl.AutomaticSize      = Enum.AutomaticSize.Y
    tl.BackgroundTransparency = 1
    tl.TextWrapped        = true
    tl.TextXAlignment     = Enum.TextXAlignment.Center
    tl.FontFace           = Font.new(
        style.fontAsset or "rbxasset://fonts/families/GothamSSm.json",
        Enum.FontWeight[style.fontWeight] or Enum.FontWeight.Regular
    )
    tl.TextSize           = style.size or 28
    tl.TextColor3         = Color3.fromRGB(
        style.textColorR or 255, style.textColorG or 255, style.textColorB or 255)
    tl.TextStrokeColor3   = Color3.fromRGB(
        style.strokeColorR or 0, style.strokeColorG or 0, style.strokeColorB or 0)
    tl.TextTransparency       = style.textTransparency   or 0
    tl.TextStrokeTransparency = style.strokeTransparency or 0
    tl.Text               = text or ""
    tl.Parent             = frame

    _gui = sg
end

function SubtitleGui.hide()
    if _gui and _gui.Parent then
        _gui:Destroy()
    end
    _gui = nil
end

return SubtitleGui
