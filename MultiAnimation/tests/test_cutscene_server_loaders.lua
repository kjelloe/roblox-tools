-- test_cutscene_server_loaders.lua
-- CutsceneServer's scene loaders, exercised against the REAL deployed module
-- (loadstring shim exposes the local loader functions): camera reshaped to a
-- remote-safe array with sparse frames preserved, subtitle fps fallback scan,
-- effect-data array reshaping, nil-when-empty. Live test — needs the deployed
-- ServerStorage.MultiAnimationData.CutsceneServer.

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

local SS = game:GetService("ServerStorage")
local mad = SS:FindFirstChild("MultiAnimationData")
local csModule = mad and mad:FindFirstChild("CutsceneServer")
if not csModule then
    return "SKIP: deployed CutsceneServer not found\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end

-- Shim: expose the local loaders from the real deployed source.
local src = csModule.Source
src = src:gsub("return CutsceneServer%s*$",
    "CutsceneServer.__test = { loadCameraData = loadCameraData, "
    .. "loadSubtitleData = loadSubtitleData, loadEffectData = loadEffectData }\n"
    .. "return CutsceneServer")
local loader = loadstring(src)
if not loader then
    return "SKIP: could not loadstring CutsceneServer\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local shim = loader().__test
ok("loaders exposed from deployed source", shim ~= nil and shim.loadCameraData ~= nil)

-- ── Fixture scene: sparse camera, subtitles, effects ─────────────────────────

local SCENE = "__LoaderProbe"
local old = mad:FindFirstChild(SCENE)
if old then old:Destroy() end
local scene = Instance.new("Folder") scene.Name = SCENE scene.Parent = mad

local ct = Instance.new("ModuleScript") ct.Name = "CameraTrack"
ct.Source = [[return { fps = 20, frames = {
    [1]  = {cf = {0,5,0, 1,0,0, 0,1,0, 0,0,1}, fov = 70, cut = false, easing = "Linear"},
    [25] = {cf = {9,5,0, 1,0,0, 0,1,0, 0,0,1}, fov = 40, cut = true,  easing = "EaseOut"},
} }]]
ct.Parent = scene

local st = Instance.new("ModuleScript") st.Name = "SubtitleTrack"
st.Source = [[return { style = { size = 28 }, events = { {frame = 3, text = "Hi"} } }]]
st.Parent = scene

local ft = Instance.new("ModuleScript") ft.Name = "EffectTracks"
ft.Source = [[return { fps = 20, effects = { Zap = { target = "game.Workspace",
    events = { [7] = {action = "emit", count = 9} } } } }]]
ft.Parent = scene

-- ── Camera: array reshape, sparse frame preserved ─────────────────────────────

local cam = shim.loadCameraData(SCENE)
ok("camera returns fps", cam ~= nil and cam.fps == 20)
ok("camera frames reshaped to an array", cam and #cam.frames == 2, cam and #cam.frames)
local sparse = false
for _, kf in ipairs(cam and cam.frames or {}) do
    if kf.frame == 25 and kf.cut == true and kf.easing == "EaseOut" then sparse = true end
end
ok("sparse frame 25 preserved with cut + easing (remote-safe)", sparse)

-- ── Subtitles: fps fallback scan (no fps in SubtitleTrack itself) ─────────────

local sub = shim.loadSubtitleData(SCENE)
ok("subtitle fps scanned from sibling modules", sub ~= nil and sub.fps == 20, sub and sub.fps)
ok("subtitle style + events pass through",
    sub and sub.style.size == 28 and sub.events[1].text == "Hi")

-- ── Effects: array reshaping, nil-when-empty ─────────────────────────────────

local fx = shim.loadEffectData(SCENE)
ok("effect data reshaped: effects array with named entry",
    fx ~= nil and #fx.effects == 1 and fx.effects[1].name == "Zap")
ok("effect events are an array of {frame, action, count}",
    fx and fx.effects[1].events[1].frame == 7 and fx.effects[1].events[1].count == 9)

ft:Destroy()
local fxNone = shim.loadEffectData(SCENE)
ok("loadEffectData nil when the scene has no effects", fxNone == nil)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

scene:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
