-- AnimPadListener — deployed by the Exporter as a LocalScript in
-- StarterPlayerScripts when Auto-pads is enabled. Step on a pad in
-- workspace.AnimTriggerPads and the scene named in its SceneName attribute
-- plays via CutscenePlayer (movieMode, debounced; the pad flashes amber while
-- the cutscene runs).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CutscenePlayer = require(RS:WaitForChild("CutscenePlayer"))

local pads = workspace:WaitForChild("AnimTriggerPads", 30)
if not pads then return end

local busy = false

local function hook(pad)
    if not pad:IsA("BasePart") then return end
    local scene = pad:GetAttribute("SceneName")
    if not scene then return end
    pad.Touched:Connect(function(hit)
        local char = Players.LocalPlayer.Character
        if busy or not char or not hit:IsDescendantOf(char) then return end
        busy = true
        local orig = pad.Color
        pad.Color = Color3.fromRGB(255, 200, 60)
        local handle = CutscenePlayer.play(scene, {}, { movieMode = true })
        handle.onComplete(function()
            pad.Color = orig
            busy = false
        end)
    end)
end

for _, pad in ipairs(pads:GetChildren()) do
    hook(pad)
end
pads.ChildAdded:Connect(hook)
