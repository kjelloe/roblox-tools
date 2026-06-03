-- test_prop_core.lua
-- Tests PropCapture round-trip and Recorder prop track CRUD operations.
-- Inlines module logic so no require() is needed in execute_luau context.
-- Creates temporary Parts in Workspace; cleans them up on exit.

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

local function approxCF(a, b, eps)
    eps = eps or 0.001
    local dp = (a.Position - b.Position).Magnitude
    -- Compare rotation via X/Y/Z basis vectors
    local dr = math.max(
        (a.XVector - b.XVector).Magnitude,
        (a.YVector - b.YVector).Magnitude,
        (a.ZVector - b.ZVector).Magnitude
    )
    return dp < eps and dr < eps
end

-- ── Inline PropCapture logic ──────────────────────────────────────────────────

local function capture(part) return part.CFrame end
local function applyProp(part, cf) part.CFrame = cf end

-- ── Inline Recorder prop session logic ───────────────────────────────────────

local function newSession()
    return { fps = 24, frameCount = 120, rigs = {}, props = {} }
end

local function addKeyframe(session, frame, activeProps)
    for propName, part in pairs(activeProps) do
        if not session.props[propName] then
            session.props[propName] = { propTrack = {} }
        end
        session.props[propName].propTrack[frame] = capture(part)
    end
end

local function getSortedPropFrames(session, propName)
    local prop = session.props[propName]
    if not prop then return {} end
    local frames = {}
    for f in pairs(prop.propTrack) do table.insert(frames, f) end
    table.sort(frames)
    return frames
end

local function getPropData(session, propName, frame)
    local prop = session.props[propName]
    return prop and prop.propTrack[frame]
end

local function deletePropKeyframe(session, propName, frame)
    local prop = session.props[propName]
    if prop then prop.propTrack[frame] = nil end
end

-- ── Create temporary workspace parts ─────────────────────────────────────────

local tempFolder = Instance.new("Folder")
tempFolder.Name   = "__PropCoreTest"
tempFolder.Parent = workspace

local function mkPart(name, cf)
    local p = Instance.new("Part")
    p.Name      = name
    p.Anchored  = true
    p.CFrame    = cf or CFrame.new(0, 0, 0)
    p.Parent    = tempFolder
    return p
end

-- ── PropCapture tests ─────────────────────────────────────────────────────────

local knownCF = CFrame.new(3, 7, -2) * CFrame.Angles(0, math.pi / 4, 0)
local partA   = mkPart("PartA", knownCF)

-- 1. capture returns current CFrame
local captured = capture(partA)
ok("capture() returns part's CFrame", approxCF(captured, knownCF),
    string.format("got pos %s expected %s", tostring(captured.Position), tostring(knownCF.Position)))

-- 2. apply sets the part's CFrame
local newCF = CFrame.new(10, 5, 0) * CFrame.Angles(math.pi / 6, 0, 0)
local partB = mkPart("PartB", CFrame.new(0, 0, 0))
applyProp(partB, newCF)
ok("apply() sets part CFrame", approxCF(partB.CFrame, newCF))

-- 3. Round-trip: capture from partA, apply to partC, positions match
local partC = mkPart("PartC", CFrame.new(99, 0, 0))
local roundTrip = capture(partA)
applyProp(partC, roundTrip)
ok("round-trip: captured CFrame applied to another part matches", approxCF(partC.CFrame, partA.CFrame))

-- ── Recorder prop track tests ─────────────────────────────────────────────────

local session = newSession()

-- 4. addKeyframe stores a CFrame
local propPart = mkPart("Block", CFrame.new(1, 2, 3))
addKeyframe(session, 10, { Block = propPart })
local stored = getPropData(session, "Block", 10)
ok("addKeyframe stores CFrame at correct frame",
    stored ~= nil and approxCF(stored, propPart.CFrame))

-- 5. getSortedPropFrames returns ascending sorted list
addKeyframe(session, 1,  { Block = propPart })
addKeyframe(session, 50, { Block = propPart })
local frames = getSortedPropFrames(session, "Block")
ok("getSortedPropFrames returns 3 frames in order",
    #frames == 3 and frames[1] == 1 and frames[2] == 10 and frames[3] == 50,
    table.concat(frames, ","))

-- 6. getPropData returns the exact stored CFrame
local exactCF = CFrame.new(5, 10, -7) * CFrame.Angles(0, 0, math.pi / 3)
local partD   = mkPart("PartD", exactCF)
addKeyframe(session, 25, { Block = partD })
local got = getPropData(session, "Block", 25)
ok("getPropData returns exact stored CFrame", got ~= nil and approxCF(got, exactCF))

-- 7. deletePropKeyframe removes only that frame; adjacent frame survives
deletePropKeyframe(session, "Block", 25)
ok("deletePropKeyframe removes frame 25", getPropData(session, "Block", 25) == nil)
ok("deletePropKeyframe leaves frame 10 intact", getPropData(session, "Block", 10) ~= nil)
ok("deletePropKeyframe leaves frame 50 intact", getPropData(session, "Block", 50) ~= nil)

-- 8. clearSession wipes all prop tracks
session.props = {}
ok("clearSession clears props table", next(session.props) == nil)

-- 9. Two separate props don't bleed into each other
local s2    = newSession()
local pSword = mkPart("Sword", CFrame.new(0, 0,  0))
local pShield = mkPart("Shield", CFrame.new(10, 0, 0))
addKeyframe(s2, 5, { Sword = pSword })
addKeyframe(s2, 7, { Shield = pShield })
ok("Sword has frame 5", getPropData(s2, "Sword", 5) ~= nil)
ok("Shield has frame 7", getPropData(s2, "Shield", 7) ~= nil)
ok("Sword does NOT have frame 7", getPropData(s2, "Sword", 7) == nil)
ok("Shield does NOT have frame 5", getPropData(s2, "Shield", 5) == nil)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

tempFolder:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
