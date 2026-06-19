-- test_ui_playback.lua
-- Tests for the Playback tab UI via the TestBridge.
-- Requires the MultiAnimation plugin to be loaded and the TestBridge active.
-- Returns "ALL TESTS PASSED (N)" or a FAIL line.

local bridge = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
if not bridge then
    return "\n=== 0 passed, 0 failed ===\nSKIP: TestBridge not found — plugin not loaded"
end

local HttpService = game:GetService("HttpService")

local PASS, FAIL = 0, 0
local function ok(cond, name)
    if cond then PASS += 1
    else FAIL += 1; warn("FAIL: " .. tostring(name)) end
end

local function call(cmd, args)
    local argsJson = args and HttpService:JSONEncode(args) or nil
    local ok2, resJson = pcall(function() return bridge:Invoke(cmd, argsJson) end)
    if not ok2 then warn("TestBridge error (" .. cmd .. "): " .. tostring(resJson)); return nil end
    local res = HttpService:JSONDecode(resJson)
    if not res.ok then warn("Bridge cmd '" .. cmd .. "' failed: " .. tostring(res.err)); return nil end
    return res.result
end

-- ── Capture initial state so we can restore it at the end ────────────────────
local origMode       = call("getMode") or "advanced"
local origFrameCount = call("getFrameCount") or 120

-- ── 1. Mode switch to Playback ────────────────────────────────────────────────
call("setPlaybackMode")
ok(call("getPlaybackMode") == "playback", "mode switches to 'playback'")

-- ── 2. Scene list refresh ─────────────────────────────────────────────────────
local scanResult = call("refreshPlaybackScenes")
ok(type(scanResult) == "table", "refreshPlaybackScenes returns a table")
ok(type(scanResult.scenes) == "table", "result has .scenes list")
-- scene may be nil if nothing is saved — both nil and string are valid
local sceneType = type(scanResult.scene)
ok(sceneType == "string" or sceneType == "nil", "result .scene is string or nil")

-- ── 3. Scene selection (with a synthetic name if needed) ──────────────────────
-- We synthesise a saved scene record so the panel has something to select.
-- Directly invoke the TestBridge setPlaybackScene command.
local syntheticName = "__PBTest_" .. tostring(os.time())
call("setPlaybackScene", { name = syntheticName })
ok(call("getPlaybackScene") == syntheticName, "setPlaybackScene stores scene name")

-- ── 4. Rig mode cycling ───────────────────────────────────────────────────────
-- setPlaybackRigMode changes the stored mode key.
call("setPlaybackRigMode", { rigName = "Rig1", mode = "fixed" })
local modes = call("getPlaybackRigModes")
ok(type(modes) == "table", "getPlaybackRigModes returns table")
ok(modes.Rig1 == "fixed", "setPlaybackRigMode stores 'fixed' for Rig1")

call("setPlaybackRigMode", { rigName = "Rig1", mode = "localClone" })
modes = call("getPlaybackRigModes")
ok(modes.Rig1 == "localClone", "setPlaybackRigMode updates to 'localClone'")

call("setPlaybackRigMode", { rigName = "Rig1", mode = "localDirect" })
modes = call("getPlaybackRigModes")
ok(modes.Rig1 == "localDirect", "setPlaybackRigMode updates to 'localDirect'")

call("setPlaybackRigMode", { rigName = "Rig1", mode = "userIdClone" })
modes = call("getPlaybackRigModes")
ok(modes.Rig1 == "userIdClone", "setPlaybackRigMode stores 'userIdClone'")

call("setPlaybackRigMode", { rigName = "Rig1", mode = "userIdDirect" })
modes = call("getPlaybackRigModes")
ok(modes.Rig1 == "userIdDirect", "setPlaybackRigMode stores 'userIdDirect'")

-- ── 5. Params: FPS ────────────────────────────────────────────────────────────
local params = call("setPlaybackParams", { fps = 24 })
ok(type(params) == "table", "setPlaybackParams returns table")
ok(params.fps == 24, "setPlaybackParams: fps=24 round-trips")

params = call("setPlaybackParams", { fps = 60 })
ok(params.fps == 60, "setPlaybackParams: fps=60 round-trips")

params = call("setPlaybackParams", { fps = 0 })
ok(params.fps == 1, "setPlaybackParams: fps=0 clamped to 1")

params = call("setPlaybackParams", { fps = 9999 })
ok(params.fps == 999, "setPlaybackParams: fps=9999 clamped to 999")

-- ── 6. Params: Loop ───────────────────────────────────────────────────────────
params = call("setPlaybackParams", { loop = true })
ok(params.loop == true, "setPlaybackParams: loop=true stored")

params = call("setPlaybackParams", { loop = false })
ok(params.loop == false, "setPlaybackParams: loop=false stored")

-- ── 7. Params: MovieMode ──────────────────────────────────────────────────────
params = call("setPlaybackParams", { movieMode = true })
ok(params.movieMode == true, "setPlaybackParams: movieMode=true stored")

params = call("setPlaybackParams", { movieMode = false })
ok(params.movieMode == false, "setPlaybackParams: movieMode=false stored")

-- ── 8. getPlaybackParams round-trip ──────────────────────────────────────────
call("setPlaybackParams", { fps = 30, loop = false, movieMode = false })
local gotParams = call("getPlaybackParams")
ok(gotParams ~= nil, "getPlaybackParams returns non-nil")
ok(gotParams.fps == 30, "getPlaybackParams: fps=30")
ok(gotParams.loop == false, "getPlaybackParams: loop=false")
ok(gotParams.movieMode == false, "getPlaybackParams: movieMode=false")

-- ── 9. Snippet generation: contains scene name ────────────────────────────────
call("setPlaybackScene", { name = "TestScene" })
call("setPlaybackRigMode", { rigName = "Rig1", mode = "fixed" })
call("setPlaybackParams",  { fps = 30, loop = false, movieMode = false })
local snippet = call("getPlaybackSnippet")
ok(type(snippet) == "string", "getPlaybackSnippet returns string")
ok(snippet:find("TestScene") ~= nil, "snippet contains scene name")

-- ── 10. Snippet contains CutscenePlayer.play call ─────────────────────────────
ok(snippet:find("CutscenePlayer") ~= nil, "snippet references CutscenePlayer")
ok(snippet:find("%.play%(") ~= nil, "snippet calls .play()")

-- ── 11. Snippet: fixed rig references workspace.FIGURES ───────────────────────
call("setPlaybackRigMode", { rigName = "Rig1", mode = "fixed" })
snippet = call("getPlaybackSnippet")
ok(snippet:find("workspace%.FIGURES%.Rig1") ~= nil, "fixed rig: snippet references workspace.FIGURES.Rig1")

-- ── 12. Snippet: localClone references LocalPlayer ────────────────────────────
call("setPlaybackRigMode", { rigName = "Rig1", mode = "localClone" })
snippet = call("getPlaybackSnippet")
ok(snippet:find("LocalPlayer") ~= nil, "localClone: snippet references LocalPlayer")
ok(snippet:find('"clone"') ~= nil, 'localClone: snippet contains mode="clone"')

-- ── 13. Snippet: localDirect references LocalPlayer ──────────────────────────
call("setPlaybackRigMode", { rigName = "Rig1", mode = "localDirect" })
snippet = call("getPlaybackSnippet")
ok(snippet:find("LocalPlayer") ~= nil, "localDirect: snippet references LocalPlayer")
ok(snippet:find('"direct"') ~= nil, 'localDirect: snippet contains mode="direct"')

-- ── 14. Snippet: userIdClone has placeholder userId ───────────────────────────
call("setPlaybackRigMode", { rigName = "Rig1", mode = "userIdClone" })
snippet = call("getPlaybackSnippet")
ok(snippet:find("userId") ~= nil, "userIdClone: snippet contains 'userId'")
ok(snippet:find('"clone"') ~= nil, 'userIdClone: snippet contains mode="clone"')

-- ── 15. Snippet: loop=true changes snippet ────────────────────────────────────
call("setPlaybackParams", { loop = true })
snippet = call("getPlaybackSnippet")
ok(snippet:find("loop = true") ~= nil, "snippet: loop=true reflected in snippet")

-- ── 16. Snippet: loop=false changes snippet ───────────────────────────────────
call("setPlaybackParams", { loop = false })
snippet = call("getPlaybackSnippet")
ok(snippet:find("loop = false") ~= nil, "snippet: loop=false reflected in snippet")

-- ── 17. Snippet: movieMode=true changes snippet ───────────────────────────────
call("setPlaybackParams", { movieMode = true })
snippet = call("getPlaybackSnippet")
ok(snippet:find("movieMode = true") ~= nil, "snippet: movieMode=true reflected in snippet")

-- ── 18. Snippet: movieMode=false changes snippet ─────────────────────────────
call("setPlaybackParams", { movieMode = false })
snippet = call("getPlaybackSnippet")
ok(snippet:find("movieMode = false") ~= nil, "snippet: movieMode=false reflected in snippet")

-- ── 19. Snippet: FPS reflected in snippet ────────────────────────────────────
call("setPlaybackParams", { fps = 24 })
snippet = call("getPlaybackSnippet")
ok(snippet:find("fps = 24") ~= nil, "snippet: fps=24 reflected in snippet")

-- ── 20. Mode switch away from playback and back ───────────────────────────────
call("setMode", { mode = "advanced" })
ok(call("getMode") == "advanced" or call("getPlaybackMode") == "advanced",
    "can switch away from playback mode")

call("setPlaybackMode")
ok(call("getPlaybackMode") == "playback", "can switch back to playback mode")

-- ── 21. refreshPlaybackScenes reflects getIndex ───────────────────────────────
local scan2 = call("refreshPlaybackScenes")
ok(type(scan2) == "table" and type(scan2.scenes) == "table",
    "refreshPlaybackScenes after mode-switch returns valid table")

-- ── 22. Multiple rig modes in one snippet ────────────────────────────────────
call("setPlaybackScene", { name = "MultiRigScene" })
call("setPlaybackRigMode", { rigName = "Rig1", mode = "fixed" })
call("setPlaybackRigMode", { rigName = "Rig2", mode = "localClone" })
snippet = call("getPlaybackSnippet")
ok(snippet:find("Rig1") ~= nil and snippet:find("Rig2") ~= nil,
    "multi-rig snippet contains both Rig1 and Rig2")
ok(snippet:find("workspace%.FIGURES%.Rig1") ~= nil, "multi-rig: Rig1 is fixed")
ok(snippet:find("LocalPlayer") ~= nil, "multi-rig: Rig2 references LocalPlayer")

-- ── 23. No scene selected → snippet shows placeholder ────────────────────────
-- Directly wipe playbackScene via setPlaybackScene to a non-existent name,
-- then refreshPlaybackScenes without any saves should give "—" or empty.
-- (We can't force playbackScene=nil from outside, so test with refreshPlaybackScenes
-- returning 0 scenes only if the suite ran against a clean plugin state.)
-- Minimal test: snippet is always a string.
snippet = call("getPlaybackSnippet")
ok(type(snippet) == "string", "getPlaybackSnippet always returns a string")

-- ── 24. setPlaybackParams partial update preserves other fields ───────────────
call("setPlaybackParams", { fps = 30, loop = true, movieMode = true })
call("setPlaybackParams", { fps = 48 })  -- only fps
gotParams = call("getPlaybackParams")
ok(gotParams.fps == 48, "partial setPlaybackParams: fps updated")
ok(gotParams.loop == true, "partial setPlaybackParams: loop preserved")
ok(gotParams.movieMode == true, "partial setPlaybackParams: movieMode preserved")

-- ── 25. Playback tab stays in playback mode (no implicit mode switch) ─────────
ok(call("getPlaybackMode") == "playback", "mode is still 'playback' at end of test")

-- ── 26. frameCount preserved through playback→advanced round-trip ────────────
-- Regression: entering playback used to skip saving advancedFrameCount, so the
-- advanced frame count was lost when restoring (the restore branch found nil).
call("setMode", { mode = (origMode and origMode ~= "playback") and origMode or "advanced" })
local fcAfter = call("getFrameCount") or 0
ok(fcAfter >= origFrameCount,
    string.format("frameCount restored after playback→advanced (%d→%d)", origFrameCount, fcAfter))

-- ── Restore original state ────────────────────────────────────────────────────
-- (mode already restored in test 26 above)
-- Reset playback state
call("setPlaybackParams", { fps = 30, loop = false, movieMode = false })

-- ──────────────────────────────────────────────────────────────────────────────
-- Result
-- ──────────────────────────────────────────────────────────────────────────────

local summary = string.format("\n=== %d passed, %d failed ===", PASS, FAIL)
return summary .. "\n" .. (FAIL == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
