-- tests/test_interpolator.lua
-- Tests Timeline + Interpolator math.  No Roblox instances required.
-- Run via MCP execute_luau (paste this file).

-- Minimal stubs for modules we can't require in execute_luau context
local Timeline = {}
Timeline.__index = Timeline
function Timeline.new(fps, frameCount)
    return setmetatable({ _fps=fps, _frameCount=frameCount, _current=1 }, Timeline)
end
function Timeline:getCurrent()    return self._current    end
function Timeline:getFrameCount() return self._frameCount end
function Timeline:getFps()        return self._fps        end
function Timeline:setCurrent(f)
    self._current = math.clamp(math.floor(f), 1, self._frameCount)
    return self._current
end
function Timeline:prevKeyframe(frames)
    local r = nil
    for _, f in ipairs(frames) do
        if f < self._current then r = f else break end
    end
    return r
end
function Timeline:nextKeyframe(frames)
    for _, f in ipairs(frames) do
        if f > self._current then return f end
    end
    return nil
end

-- Minimal surrounding() that mirrors Interpolator.surrounding
local function surrounding(sortedFrames, q)
    if #sortedFrames == 0 then return nil, nil, 0 end
    if #sortedFrames == 1 then return sortedFrames[1], sortedFrames[1], 0 end
    if q <= sortedFrames[1] then return sortedFrames[1], sortedFrames[1], 0 end
    if q >= sortedFrames[#sortedFrames] then
        local last = sortedFrames[#sortedFrames]
        return last, last, 0
    end
    for i = 1, #sortedFrames - 1 do
        local a, b = sortedFrames[i], sortedFrames[i+1]
        if q >= a and q <= b then
            return a, b, (q - a) / (b - a)
        end
    end
    return nil, nil, 0
end

-- ── Assertions ────────────────────────────────────────────────────────────────

local passed, failed = 0, 0

local function ok(label, cond, extra)
    if cond then
        print("PASS  " .. label)
        passed += 1
    else
        print("FAIL  " .. label .. (extra and ("  >> " .. tostring(extra)) or ""))
        failed += 1
    end
end

local function approx(a, b, eps)
    return math.abs(a - b) < (eps or 1e-6)
end

-- ── Timeline tests ────────────────────────────────────────────────────────────

local tl = Timeline.new(24, 120)

ok("Timeline setCurrent clamps to 1", tl:setCurrent(0) == 1)
ok("Timeline setCurrent clamps to frameCount", tl:setCurrent(200) == 120)
ok("Timeline setCurrent floors fractional", tl:setCurrent(5.9) == 5)

local frames = {1, 12, 48, 96}

tl:setCurrent(1)
ok("prevKeyframe at frame 1 = nil", tl:prevKeyframe(frames) == nil)
ok("nextKeyframe at frame 1 = 12", tl:nextKeyframe(frames) == 12)

tl:setCurrent(12)
ok("prevKeyframe at frame 12 = 1", tl:prevKeyframe(frames) == 1)
ok("nextKeyframe at frame 12 = 48", tl:nextKeyframe(frames) == 48)

tl:setCurrent(96)
ok("prevKeyframe at frame 96 = 48", tl:prevKeyframe(frames) == 48)
ok("nextKeyframe at frame 96 = nil (last)", tl:nextKeyframe(frames) == nil)

-- ── Interpolation math tests ──────────────────────────────────────────────────

-- Empty frames
local fA, fB, alpha = surrounding({}, 5)
ok("surrounding empty = nil, nil, 0", fA == nil and fB == nil and alpha == 0)

-- Single frame
fA, fB, alpha = surrounding({10}, 5)
ok("surrounding single-frame clamp low", fA == 10 and fB == 10 and alpha == 0)
fA, fB, alpha = surrounding({10}, 15)
ok("surrounding single-frame clamp high", fA == 10 and fB == 10 and alpha == 0)
fA, fB, alpha = surrounding({10}, 10)
ok("surrounding single-frame exact", fA == 10 and fB == 10 and alpha == 0)

-- Two frames
fA, fB, alpha = surrounding({1, 12}, 1)
ok("surrounding at lower bound: alpha=0, fA=1, fB=1",
    fA == 1 and fB == 1 and alpha == 0)

fA, fB, alpha = surrounding({1, 12}, 12)
ok("surrounding at upper bound: fA=12, fB=12, alpha=0",
    fA == 12 and fB == 12 and alpha == 0)

fA, fB, alpha = surrounding({1, 12}, 6.5)
ok("surrounding midpoint: fA=1, fB=12, alpha=0.5",
    fA == 1 and fB == 12 and approx(alpha, 0.5),
    string.format("got fA=%s fB=%s alpha=%.4f", tostring(fA), tostring(fB), alpha))

fA, fB, alpha = surrounding({1, 12}, 4)   -- 3/11 into [1..12]
local expectedAlpha = (4-1)/(12-1)
ok("surrounding at frame 4 in [1,12]: alpha = 3/11",
    fA == 1 and fB == 12 and approx(alpha, expectedAlpha),
    string.format("got alpha=%.6f expected=%.6f", alpha, expectedAlpha))

-- Three frames
fA, fB, alpha = surrounding({1, 12, 48}, 30)
expectedAlpha = (30-12)/(48-12)
ok("surrounding frame 30 in [12,48]: correct segment and alpha",
    fA == 12 and fB == 48 and approx(alpha, expectedAlpha),
    string.format("fA=%s fB=%s alpha=%.6f (expected %.6f)",
        tostring(fA), tostring(fB), alpha, expectedAlpha))

-- ── CFrame lerp sanity ────────────────────────────────────────────────────────

local cfA = CFrame.new(0, 0, 0)
local cfB = CFrame.new(10, 0, 0)
local mid  = cfA:Lerp(cfB, 0.5)
ok("CFrame Lerp midpoint X=5", approx(mid.Position.X, 5))

-- Rotation lerp
local cfR = CFrame.Angles(0, math.pi, 0)  -- 180° around Y
local mid2 = CFrame.identity:Lerp(cfR, 0.5)
local _, yRot, _ = mid2:ToEulerAnglesXYZ()
ok("CFrame Lerp 0→180° Y-rotation midpoint ≈ 90°",
    approx(math.abs(yRot), math.pi/2, 0.01),
    string.format("got %.4f rad", yRot))

-- ── Summary ───────────────────────────────────────────────────────────────────

print(string.format("\n=== %d passed, %d failed ===", passed, failed))
if failed == 0 then
    print("ALL TESTS PASSED")
else
    print("FAILURES DETECTED — see FAIL lines above")
end
