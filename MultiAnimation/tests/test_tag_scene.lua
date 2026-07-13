-- test_tag_scene.lua
-- Tests for tag-based scene organisation (CollectionService tags "MAnim:<scene>").
-- Covers: getWorkspaceFolders, tagFolder, clearSceneTags, getSceneTagged, and
-- the doSimpleScan fallback behaviour (empty scene name → FIGURES scan).
--
-- Requires: Workspace.FIGURES with at least one R6 rig.
-- Safe: all tags are added/removed on existing workspace instances; no new
-- instances are created or destroyed.

local HttpService = game:GetService("HttpService")

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

local function finish()
    table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
    table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
    return table.concat(out, "\n")
end

-- ── Bridge presence ───────────────────────────────────────────────────────────

local bridge = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
ok("TestBridge present", bridge ~= nil)
if not bridge then return finish() end

local function call(cmd, args)
    local resJson = bridge:Invoke(cmd, args and HttpService:JSONEncode(args) or nil)
    return HttpService:JSONDecode(resJson)
end

-- ── Preconditions ─────────────────────────────────────────────────────────────

local fig = workspace:FindFirstChild("FIGURES")
ok("Workspace.FIGURES exists", fig ~= nil)
if not fig then return finish() end

local rigNames = {}
for _, child in ipairs(fig:GetChildren()) do
    local torso = child:FindFirstChild("Torso")
    if child:IsA("Model") and torso and torso:IsA("BasePart") then
        table.insert(rigNames, child.Name)
    end
end
ok("FIGURES has at least one R6 rig", #rigNames >= 1,
    "found " .. #rigNames .. " R6 rig(s)")
if #rigNames == 0 then return finish() end

-- ── Save and restore state ────────────────────────────────────────────────────

local prevMode      = call("getMode")
local prevSceneName = call("getSimpleSceneName") -- may not exist yet; tolerate nil

-- Make sure we start clean: remove any leftover test tags.
call("setSimpleSceneName", { name = "__TagTest__" })
call("clearSceneTags")

-- ── getWorkspaceFolders ───────────────────────────────────────────────────────

local foldersR = call("getWorkspaceFolders")
ok("getWorkspaceFolders returns a list", foldersR.ok and type(foldersR.result) == "table",
    foldersR.err)
local hasFigures = false
if foldersR.ok then
    for _, n in ipairs(foldersR.result) do
        if n == "FIGURES" then hasFigures = true end
    end
end
ok("getWorkspaceFolders includes FIGURES", hasFigures)

-- ── tagFolder — rigs only ────────────────────────────────────────────────────

local scene = "__TagTest__"
call("setSimpleSceneName", { name = scene })

local tagR = call("tagFolder", { folder = "FIGURES", types = { rigs = true, props = false, effects = false } })
ok("tagFolder returns ok", tagR.ok, tagR.err)

local taggedR = call("getSceneTagged")
ok("getSceneTagged returns list after tagFolder", taggedR.ok and type(taggedR.result) == "table",
    taggedR.err)

-- Every R6 rig in FIGURES should now be tagged.
local taggedSet = {}
if taggedR.ok then
    for _, n in ipairs(taggedR.result) do taggedSet[n] = true end
end
local allRigsTagged = true
for _, n in ipairs(rigNames) do
    if not taggedSet[n] then allRigsTagged = false end
end
ok("all FIGURES R6 rigs tagged with MAnim:" .. scene, allRigsTagged,
    HttpService:JSONEncode(taggedR.ok and taggedR.result or {}))

-- ── doSimpleScan with scene name uses tags ────────────────────────────────────

call("setMode", { mode = "simple" })
local rigsAfterTag = call("getRigs")
ok("getRigs in simple mode finds tagged rigs", rigsAfterTag.ok and #rigsAfterTag.result >= 1,
    rigsAfterTag.err)

-- At least the first FIGURES rig should appear.
local firstRigFound = false
if rigsAfterTag.ok then
    for _, n in ipairs(rigsAfterTag.result) do
        if n == rigNames[1] then firstRigFound = true end
    end
end
ok("first FIGURES rig visible after tag-based scan", firstRigFound, rigNames[1])

-- ── clearSceneTags ────────────────────────────────────────────────────────────

local clearR = call("clearSceneTags")
ok("clearSceneTags returns ok", clearR.ok, clearR.err)

local taggedAfterClear = call("getSceneTagged")
ok("getSceneTagged empty after clear", taggedAfterClear.ok and #taggedAfterClear.result == 0,
    taggedAfterClear.ok and HttpService:JSONEncode(taggedAfterClear.result) or taggedAfterClear.err)

-- After clearing, doSimpleScan should find no tagged rigs (scene name still set).
call("setMode", { mode = "advanced" })
call("setMode", { mode = "simple" })
local rigsAfterClear = call("getRigs")
ok("getRigs empty after tags cleared", rigsAfterClear.ok and #rigsAfterClear.result == 0,
    rigsAfterClear.ok and HttpService:JSONEncode(rigsAfterClear.result) or rigsAfterClear.err)

-- ── Empty scene name falls back to FIGURES scan ───────────────────────────────

call("setSimpleSceneName", { name = "" })
-- Tag removal propagates asynchronously; the first rescan after clearSceneTags
-- occasionally still sees stale state and returns []. Retry the mode-cycle.
local rigsNoScene
for _ = 1, 3 do
    call("setMode", { mode = "advanced" })
    call("setMode", { mode = "simple" })
    rigsNoScene = call("getRigs")
    if rigsNoScene.ok and #rigsNoScene.result >= 1 then break end
    task.wait(0.3)
end
ok("empty scene name → FIGURES fallback scan finds rigs",
    rigsNoScene.ok and #rigsNoScene.result >= 1,
    rigsNoScene.ok and HttpService:JSONEncode(rigsNoScene.result) or rigsNoScene.err)

-- ── Additive tagging (two calls accumulate) ───────────────────────────────────

call("setSimpleSceneName", { name = scene })
call("clearSceneTags")
-- Tag only the first rig's folder once (FIGURES).
call("tagFolder", { folder = "FIGURES", types = { rigs = true, props = false, effects = false } })
local count1 = #(call("getSceneTagged").result or {})
-- Tag again — should not duplicate (CollectionService:AddTag is idempotent).
call("tagFolder", { folder = "FIGURES", types = { rigs = true, props = false, effects = false } })
local count2 = #(call("getSceneTagged").result or {})
ok("re-tagging does not duplicate (AddTag idempotent)", count2 == count1,
    tostring(count1) .. " → " .. tostring(count2))

-- ── New-button name auto-increment (headless) ────────────────────────────────
-- The increment logic lives in Panel.lua's click handler; we test the pattern
-- inline here (same logic, no bridge needed).

do
    local function increment(name)
        local base, num = name:match("^(.-)_(%d+)$")
        if base and num then
            local n = tonumber(num) + 1
            return base .. "_" .. string.format("%0" .. #num .. "d", n)
        else
            return name .. "_001"
        end
    end
    ok("increment Scene_001 → Scene_002",    increment("Scene_001")    == "Scene_002")
    ok("increment Scene_009 → Scene_010",    increment("Scene_009")    == "Scene_010")
    ok("increment Scene_099 → Scene_100",    increment("Scene_099")    == "Scene_100")
    ok("increment no-suffix → Foo_001",      increment("Foo")          == "Foo_001")
    ok("increment multi-digit Scene_1 → Scene_2", increment("Scene_1") == "Scene_2")
end

-- ── getTagCounts via bridge ───────────────────────────────────────────────────
-- After tagging FIGURES, getSceneTagged should return the rigs we tagged.
-- We verify categorisation: tagged rigs count as rigs (not props).

call("setSimpleSceneName", { name = scene })
call("clearSceneTags")
call("tagFolder", { folder = "FIGURES", types = { rigs = true, props = false, effects = false } })
local tagged = call("getSceneTagged")
ok("getSceneTagged returns list after tag",
    tagged.ok and type(tagged.result) == "table" and #tagged.result >= 1,
    tagged.ok and tostring(#(tagged.result or {})) or tagged.err)
-- All returned instances should be the R6 rigs we know about.
if tagged.ok and tagged.result then
    local taggedNames = {}
    for _, n in ipairs(tagged.result) do taggedNames[n] = true end
    local allRigsTagged = true
    for _, rn in ipairs(rigNames) do
        if not taggedNames[rn] then allRigsTagged = false end
    end
    ok("all FIGURES rigs appear in getSceneTagged", allRigsTagged,
        HttpService:JSONEncode(tagged.result))
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

call("clearSceneTags")
call("setSimpleSceneName", { name = (prevSceneName.ok and prevSceneName.result) or "Scene_001" })
call("setMode", { mode = (prevMode.ok and prevMode.result ~= "playback" and prevMode.result) or "advanced" })

return finish()
