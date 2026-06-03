-- test_prop_interpolator.lua
-- Tests Interpolator.getPropData (CFrame lerp) and getAllPropFrames.
-- All logic inlined — no require() needed.

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

local function approx(a, b, eps) return math.abs(a - b) < (eps or 0.001) end

local function approxV3(a, b, eps)
    return (a - b).Magnitude < (eps or 0.001)
end

local function approxCF(a, b, eps)
    eps = eps or 0.001
    return (a.Position - b.Position).Magnitude < eps and
           (a.XVector  - b.XVector).Magnitude  < eps and
           (a.YVector  - b.YVector).Magnitude  < eps
end

-- ── Inlined: surrounding() ────────────────────────────────────────────────────

local function surrounding(sortedFrames, q)
    if #sortedFrames == 0 then return nil, nil, 0 end
    if #sortedFrames == 1 then return sortedFrames[1], sortedFrames[1], 0 end
    if q <= sortedFrames[1] then return sortedFrames[1], sortedFrames[1], 0 end
    if q >= sortedFrames[#sortedFrames] then
        local last = sortedFrames[#sortedFrames]
        return last, last, 0
    end
    for i = 1, #sortedFrames - 1 do
        local a, b = sortedFrames[i], sortedFrames[i + 1]
        if q >= a and q <= b then
            return a, b, (q - a) / (b - a)
        end
    end
    return nil, nil, 0
end

-- ── Inlined: minimal Recorder prop storage ────────────────────────────────────

local function newPropSession()
    return { props = {} }
end

local function setPropData(s, propName, frame, cf)
    if not s.props[propName] then s.props[propName] = { propTrack = {} } end
    s.props[propName].propTrack[frame] = cf
end

local function getSortedPropFrames(s, propName)
    local prop = s.props[propName]
    if not prop then return {} end
    local frames = {}
    for f in pairs(prop.propTrack) do table.insert(frames, f) end
    table.sort(frames)
    return frames
end

local function getRawPropData(s, propName, frame)
    local prop = s.props[propName]
    return prop and prop.propTrack[frame]
end

-- ── Inlined: Interpolator.getPropData ────────────────────────────────────────

local function getPropData(s, propName, queryFrame)
    local sorted = getSortedPropFrames(s, propName)
    if #sorted == 0 then return nil end
    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end
    local cfA = getRawPropData(s, propName, fA)
    if fA == fB or alpha == 0 then return cfA end
    local cfB = getRawPropData(s, propName, fB)
    if not cfB then return cfA end
    return cfA:Lerp(cfB, alpha)
end

-- ── Inlined: Interpolator.getAllPropFrames ─────────────────────────────────────

local function getAllPropFrames(s, propNames)
    local seen = {}
    for _, name in ipairs(propNames) do
        for _, f in ipairs(getSortedPropFrames(s, name)) do
            seen[f] = true
        end
    end
    local result = {}
    for f in pairs(seen) do table.insert(result, f) end
    table.sort(result)
    return result
end

-- ── Tests: getPropData ────────────────────────────────────────────────────────

-- 1. Single keyframe → returns that CFrame at any query frame
do
    local s = newPropSession()
    local cf = CFrame.new(3, 5, 1)
    setPropData(s, "Block", 10, cf)
    local r1 = getPropData(s, "Block", 1)
    local r2 = getPropData(s, "Block", 10)
    local r3 = getPropData(s, "Block", 99)
    ok("single KF: query before → clamps to it",   r1 ~= nil and approxCF(r1, cf))
    ok("single KF: query at frame → exact match",  r2 ~= nil and approxCF(r2, cf))
    ok("single KF: query after → clamps to it",    r3 ~= nil and approxCF(r3, cf))
end

-- 2. Query at exact keyframe time → no lerp drift
do
    local s   = newPropSession()
    local cfA = CFrame.new(0, 0, 0)
    local cfB = CFrame.new(100, 0, 0)
    setPropData(s, "Block", 1,  cfA)
    setPropData(s, "Block", 11, cfB)
    local atA = getPropData(s, "Block", 1)
    local atB = getPropData(s, "Block", 11)
    ok("exact frame 1 → cfA (no drift)",  approxCF(atA, cfA))
    ok("exact frame 11 → cfB (no drift)", approxCF(atB, cfB))
end

-- 3. Midpoint between two keyframes → lerped position
do
    local s   = newPropSession()
    local cfA = CFrame.new(0,  0, 0)
    local cfB = CFrame.new(20, 0, 0)
    setPropData(s, "Block", 1, cfA)
    setPropData(s, "Block", 11, cfB)   -- midpoint query = frame 6
    local mid = getPropData(s, "Block", 6)   -- alpha = (6-1)/(11-1) = 0.5
    ok("midpoint position lerped to X=10",
        mid ~= nil and approx(mid.Position.X, 10),
        string.format("got X=%.4f", mid and mid.Position.X or -1))
end

-- 4. Query before first keyframe → clamps to first
do
    local s   = newPropSession()
    local cfA = CFrame.new(5, 0, 0)
    setPropData(s, "Block", 10, cfA)
    setPropData(s, "Block", 20, CFrame.new(50, 0, 0))
    local r = getPropData(s, "Block", 2)
    ok("query before first KF → clamps to first",
        r ~= nil and approx(r.Position.X, 5),
        string.format("got X=%.4f", r and r.Position.X or -1))
end

-- 5. Query after last keyframe → clamps to last
do
    local s   = newPropSession()
    local cfB = CFrame.new(99, 0, 0)
    setPropData(s, "Block", 1,  CFrame.new(0, 0, 0))
    setPropData(s, "Block", 10, cfB)
    local r = getPropData(s, "Block", 50)
    ok("query after last KF → clamps to last",
        r ~= nil and approx(r.Position.X, 99),
        string.format("got X=%.4f", r and r.Position.X or -1))
end

-- 6. No keyframes → returns nil
do
    local s = newPropSession()
    local r = getPropData(s, "Block", 5)
    ok("no keyframes → nil", r == nil)
end

-- 7. Rotation is spherically interpolated (not skipped)
do
    local s   = newPropSession()
    local cfA = CFrame.new(0, 0, 0)
    local cfB = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0)  -- 180° Y
    setPropData(s, "Prop", 1, cfA)
    setPropData(s, "Prop", 11, cfB)
    local mid = getPropData(s, "Prop", 6)   -- alpha = 0.5
    local _, yRot, _ = mid:ToEulerAnglesXYZ()
    ok("rotation lerped at midpoint ≈ 90° Y (not 0° or 180°)",
        approx(math.abs(yRot), math.pi / 2, 0.05),
        string.format("got %.4f rad (expected %.4f)", math.abs(yRot), math.pi / 2))
end

-- ── Tests: getAllPropFrames ────────────────────────────────────────────────────

-- 8. Two props with different frames → merged sorted unique list
do
    local s = newPropSession()
    setPropData(s, "Block", 1,  CFrame.new())
    setPropData(s, "Block", 10, CFrame.new())
    setPropData(s, "Sword", 5,  CFrame.new())
    setPropData(s, "Sword", 10, CFrame.new())   -- duplicate with Block at 10
    local all = getAllPropFrames(s, {"Block", "Sword"})
    ok("getAllPropFrames returns 3 unique sorted frames",
        #all == 3 and all[1] == 1 and all[2] == 5 and all[3] == 10,
        table.concat(all, ","))
end

-- 9. getAllPropFrames with empty prop list → empty
do
    local s = newPropSession()
    local all = getAllPropFrames(s, {})
    ok("getAllPropFrames with no prop names → empty", #all == 0)
end

-- 10. getAllPropFrames with prop that has no data → still works (no error)
do
    local s = newPropSession()
    setPropData(s, "Real", 5, CFrame.new())
    local all = getAllPropFrames(s, {"Real", "Ghost"})
    ok("getAllPropFrames skips props with no data gracefully",
        #all == 1 and all[1] == 5,
        table.concat(all, ","))
end

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
