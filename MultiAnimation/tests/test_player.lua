-- test_player.lua
-- Place as a Script in ServerScriptService (NOT a LocalScript).
-- Run in Play mode (F5) after exporting at least one scene from the plugin.
--
-- Prerequisites:
--   1. Plugin exported a scene (e.g. "Scene_001") → ServerStorage.MultiAnimationData
--   2. ServerStorage.MultiAnimationData.MultiAnimPlayer exists (auto-deployed by Exporter)
--   3. Workspace.FIGURES.Rig1 and Rig2 exist as R6 rigs
--
-- What it tests:
--   - play() starts joint animation + scale track
--   - onFinished fires after the scene completes
--   - stop() fires onFinished immediately and halts playback

local ServerStorage = game:GetService("ServerStorage")

-- Give the DataModel a moment to fully load
task.wait(1)

local mad = ServerStorage:FindFirstChild("MultiAnimationData")
if not mad then
    error("[MultiAnimTest] ServerStorage.MultiAnimationData not found — export a scene first")
end

local player = require(mad.MultiAnimPlayer)

local SCENE = "Scene_001"
local RIGS  = {
    Rig1 = workspace:WaitForChild("FIGURES"):WaitForChild("Rig1"),
    Rig2 = workspace:WaitForChild("FIGURES"):WaitForChild("Rig2"),
}

-- ── Test 1: full playback ─────────────────────────────────────────────────────

print("[MultiAnimTest] Test 1: full playback of '" .. SCENE .. "'")

local finished1 = false
player.onFinished(function(sn)
    print("[MultiAnimTest] onFinished fired — scene: " .. tostring(sn))
    finished1 = true
end)

player.play(SCENE, RIGS)
print("[MultiAnimTest] play() called — watch the viewport for animation")

-- Wait up to 30 seconds for the scene to finish naturally
local waited = 0
while not finished1 and waited < 30 do
    task.wait(0.5)
    waited += 0.5
end

if finished1 then
    print("[MultiAnimTest] PASS  Test 1: scene completed naturally")
else
    print("[MultiAnimTest] FAIL  Test 1: scene did not finish within 30s")
end

task.wait(1)

-- ── Test 2: stop() fires onFinished ──────────────────────────────────────────

print("[MultiAnimTest] Test 2: stop() fires onFinished")

local finished2 = false
player.onFinished(function(sn)
    print("[MultiAnimTest] onFinished (stop) — scene: " .. tostring(sn))
    finished2 = true
end)

player.play(SCENE, RIGS)
task.wait(0.5)   -- let it run briefly
player.stop()

task.wait(0.1)
if finished2 then
    print("[MultiAnimTest] PASS  Test 2: stop() fired onFinished")
else
    print("[MultiAnimTest] FAIL  Test 2: stop() did not fire onFinished")
end

print("[MultiAnimTest] Done.")
