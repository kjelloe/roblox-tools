-- LetterboxGui — client-side cinematic letterbox bars (top 10% + bottom 10%).
-- Require from a LocalScript; call show() before playback, hide() after.

local LetterboxGui = {}

local _gui = nil

local function mkBar(parent, isTop)
    local f             = Instance.new("Frame")
    f.Size              = UDim2.new(1, 0, 0.1, 0)
    f.Position          = UDim2.new(0, 0, isTop and 0 or 0.9, 0)
    f.BackgroundColor3  = Color3.new(0, 0, 0)
    f.BorderSizePixel   = 0
    f.ZIndex            = 100
    f.Parent            = parent
    return f
end

function LetterboxGui.show()
    if _gui then return end
    local Players = game:GetService("Players")
    local player  = Players.LocalPlayer
    if not player then return end
    local playerGui = player:WaitForChild("PlayerGui")

    _gui                = Instance.new("ScreenGui")
    _gui.Name           = "MultiAnimLetterbox"
    _gui.ResetOnSpawn   = false
    _gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _gui.IgnoreGuiInset = true
    _gui.DisplayOrder   = 200
    _gui.Parent         = playerGui

    mkBar(_gui, true)   -- top bar
    mkBar(_gui, false)  -- bottom bar
end

function LetterboxGui.hide()
    if _gui then
        _gui:Destroy()
        _gui = nil
    end
end

-- Returns true if the letterbox is currently showing.
function LetterboxGui.isVisible()
    return _gui ~= nil
end

return LetterboxGui
