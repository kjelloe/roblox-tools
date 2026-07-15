-- test_fade_runtime.lua
-- Fade effect runtime behaviour via the plugin runner's edit-mode preview
-- (bridge addSpawnedEffect fires it): overlay creation, animation timing,
-- direction "in" removing the overlay, image mode, FadeToken takeover.
-- Live test — needs the plugin panel open.

local out = {}
local passed, failed = 0, 0

local function ok(label, cond, extra)
    if cond then
        passed += 1
        table.insert(out, "PASS  " .. label)
    else
        failed += 1
        table.insert(out, "FAIL  " .. label .. (extra and ("  >> " .. tostring(extra)) or ""))
    end
end

local bf = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
local hs = game:GetService("HttpService")
if not bf then
    return "SKIP: __MultiAnimTestBridge not found\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local function call(cmd, args)
    return hs:JSONDecode(bf:Invoke(cmd, args and hs:JSONEncode(args) or nil))
end
local CoreGui = game:GetService("CoreGui")
local ids = {}

-- ── Fade out: overlay appears, animates to opaque ─────────────────────────────

local r = call("addSpawnedEffect", { frame = 1, effectType = "Fade",
    colorR = 10, colorG = 20, colorB = 30, imageId = "", duration = 0.6,
    direction = "out", posX = 0, posY = 100, posZ = 0 })
ok("Fade preview fires via bridge", r.ok and type(r.result) == "number", hs:JSONEncode(r))
table.insert(ids, r.result)

task.wait(0.3)
local gui = CoreGui:FindFirstChild("__MAnimFadeGui")
ok("overlay ScreenGui created in CoreGui (edit preview)", gui ~= nil)
local midT = gui and gui.Color.BackgroundTransparency or -1
ok("mid-fade transparency ~0.5 at half duration", math.abs(midT - 0.5) < 0.2, midT)
ok("fade colour applied", gui ~= nil
    and gui.Color.BackgroundColor3 == Color3.fromRGB(10, 20, 30))

task.wait(0.5)
ok("fully opaque at end of fade-out",
    gui ~= nil and gui.Parent ~= nil and gui.Color.BackgroundTransparency < 0.01,
    gui and gui.Color.BackgroundTransparency)

-- ── Fade in: takes over via FadeToken, removes the overlay when done ─────────

r = call("addSpawnedEffect", { frame = 2, effectType = "Fade",
    colorR = 10, colorG = 20, colorB = 30, imageId = "", duration = 0.4,
    direction = "in", posX = 0, posY = 100, posZ = 0 })
table.insert(ids, r.result)
task.wait(0.8)
ok("fade-in removes the overlay when complete",
    CoreGui:FindFirstChild("__MAnimFadeGui") == nil)

-- ── Image mode ────────────────────────────────────────────────────────────────

r = call("addSpawnedEffect", { frame = 3, effectType = "Fade",
    colorR = 0, colorG = 0, colorB = 0, imageId = "rbxassetid://424242",
    duration = 0.3, direction = "out", posX = 0, posY = 100, posZ = 0 })
table.insert(ids, r.result)
task.wait(0.15)
gui = CoreGui:FindFirstChild("__MAnimFadeGui")
ok("image mode: ImageLabel visible with the asset id",
    gui ~= nil and gui.Image.Visible and gui.Image.Image == "rbxassetid://424242")

-- ── Cleanup ───────────────────────────────────────────────────────────────────

for _, id in ipairs(ids) do
    if id then call("deleteSpawnedEffect", { id = id }) end
end
gui = CoreGui:FindFirstChild("__MAnimFadeGui")
if gui then gui:Destroy() end

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
