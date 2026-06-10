-- test_track_part.lua
-- Tests the "Track Part" validation logic in isolation via execute_luau.
--
-- Run with: mcp luau -f tests/test_track_part.lua
--
-- Simulates the three guard checks in the onTrackPartRequested handler:
--   1. Selection must contain a BasePart
--   2. Part name must not collide with an existing rig
--   3. Part name must not collide with an existing prop

local results = {}
local passed, failed = 0, 0
local function check(label, cond)
    if cond then passed += 1 else failed += 1 end
    table.insert(results, (cond and "PASS" or "FAIL") .. "  " .. label)
end

-- ── Simulate the guard logic ──────────────────────────────────────────────────

local function trackPartGuard(selectedInstances, allRigs, allProps)
    -- Guard 1: find a BasePart in selection
    local part = nil
    for _, inst in ipairs(selectedInstances) do
        if inst:IsA("BasePart") then part = inst; break end
    end
    if not part then
        return false, "no BasePart selected"
    end

    -- Guard 2+3: name uniqueness
    local propName = part.Name
    if allRigs[propName] or allProps[propName] then
        return false, "name '" .. propName .. "' already in use"
    end

    return true, propName
end

-- ── Test cases ────────────────────────────────────────────────────────────────

-- Helpers: create real BasePart instances so IsA works correctly
local function mkPart(name)
    local p = Instance.new("Part")
    p.Name = name
    return p
end

local function mkModel(name)
    local m = Instance.new("Model")
    m.Name = name
    return m
end

-- 1. Empty selection → reject
do
    local ok, msg = trackPartGuard({}, {}, {})
    check("empty selection rejected", not ok and msg == "no BasePart selected")
end

-- 2. Non-BasePart in selection (e.g. a Model) → reject
do
    local ok, msg = trackPartGuard({ mkModel("MyModel") }, {}, {})
    check("non-BasePart selection rejected", not ok and msg == "no BasePart selected")
end

-- 3. Valid BasePart, no conflicts → accept
do
    local p = mkPart("Block")
    local ok, name = trackPartGuard({ p }, {}, {})
    check("valid part accepted", ok and name == "Block")
end

-- 4. Part name collides with existing rig → reject
do
    local p = mkPart("Rig1")
    local ok, msg = trackPartGuard({ p }, { Rig1 = true }, {})
    check("rig name collision rejected", not ok and msg:find("Rig1"))
end

-- 5. Part name collides with existing prop → reject
do
    local p = mkPart("Block")
    local ok, msg = trackPartGuard({ p }, {}, { Block = true })
    check("prop name collision rejected", not ok and msg:find("Block"))
end

-- 6. Second BasePart in list is ignored if first is valid
do
    local p1 = mkPart("First")
    local p2 = mkPart("Second")
    local ok, name = trackPartGuard({ p1, p2 }, {}, {})
    check("first BasePart wins", ok and name == "First")
end

-- 7. Selection service itself is accessible (catches the original nil bug)
do
    local sel = game:GetService("Selection")
    check("Selection service accessible", sel ~= nil and typeof(sel) == "Instance")
    -- Verify Get() is callable
    local ok2, result = pcall(function() return sel:Get() end)
    check("Selection:Get() callable without error", ok2)
end

-- ── Report ────────────────────────────────────────────────────────────────────

table.insert(results, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(results, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(results, "\n")
