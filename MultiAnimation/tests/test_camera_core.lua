-- test_camera_core.lua
-- Camera track logic: keyframe CRUD, cut-vs-move interpolation, FOV lerp.
-- Inlines the Recorder camera accessors and Interpolator.getCameraData logic
-- so no require() into the plugin is needed.

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
local function approxCF(a, b, eps)
    eps = eps or 0.001
    return (a.Position - b.Position).Magnitude < eps
       and (a.XVector - b.XVector).Magnitude < eps
end

-- ── Inline camera track store (mirrors Recorder) ──────────────────────────────

local track = {}

local function addCameraKeyframe(frame, cf, fov, mode)
    track[frame] = { cf = cf, fov = fov or 70, mode = mode or "move" }
end

local function getCameraData(frame) return track[frame] end

local function getSortedCameraFrames()
    local frames = {}
    for f in pairs(track) do table.insert(frames, f) end
    table.sort(frames)
    return frames
end

-- ── Inline interpolation (mirrors Interpolator.getCameraData) ─────────────────

local function surrounding(sorted, q)
    if #sorted == 0 then return nil, nil, 0 end
    if #sorted == 1 then return sorted[1], sorted[1], 0 end
    if q <= sorted[1] then return sorted[1], sorted[1], 0 end
    if q >= sorted[#sorted] then
        local last = sorted[#sorted]
        return last, last, 0
    end
    for i = 1, #sorted - 1 do
        local a, b = sorted[i], sorted[i + 1]
        if q >= a and q <= b then
            return a, b, (q - a) / (b - a)
        end
    end
    return nil, nil, 0
end

local function interpCamera(queryFrame)
    local sorted = getSortedCameraFrames()
    if #sorted == 0 then return nil end
    local fA, fB, alpha = surrounding(sorted, queryFrame)
    if not fA then return nil end
    local dataA = getCameraData(fA)
    if fA == fB or alpha == 0 then return { cf = dataA.cf, fov = dataA.fov } end
    local dataB = getCameraData(fB)
    if not dataB then return { cf = dataA.cf, fov = dataA.fov } end
    if dataB.mode == "cut" then
        if alpha >= 1 then return { cf = dataB.cf, fov = dataB.fov } end
        return { cf = dataA.cf, fov = dataA.fov }
    end
    return {
        cf  = dataA.cf:Lerp(dataB.cf, alpha),
        fov = dataA.fov + (dataB.fov - dataA.fov) * alpha,
    }
end

-- ── CRUD ──────────────────────────────────────────────────────────────────────

ok("empty track interpolates to nil", interpCamera(10) == nil)

local cfA = CFrame.new(0, 5, 0)
local cfB = CFrame.new(10, 5, 0) * CFrame.Angles(0, math.pi / 2, 0)
local cfC = CFrame.new(0, 20, -30)

addCameraKeyframe(1,  cfA, 70, "move")
addCameraKeyframe(11, cfB, 40, "move")
addCameraKeyframe(21, cfC, 90, "cut")

ok("sorted frames = 1,11,21", table.concat(getSortedCameraFrames(), ",") == "1,11,21")
ok("defaults applied (fov 70, mode move)", (function()
    addCameraKeyframe(99, CFrame.new())
    local kf = getCameraData(99)
    local good = kf.fov == 70 and kf.mode == "move"
    track[99] = nil
    return good
end)())
ok("overwrite keyframe keeps single entry", (function()
    addCameraKeyframe(11, cfB, 45, "move")
    return #getSortedCameraFrames() == 3 and getCameraData(11).fov == 45
end)())
addCameraKeyframe(11, cfB, 40, "move")   -- restore

-- ── Move interpolation ────────────────────────────────────────────────────────

local r = interpCamera(1)
ok("exact first keyframe", approxCF(r.cf, cfA) and approx(r.fov, 70))

r = interpCamera(6)   -- midpoint of [1, 11]
ok("midpoint CFrame lerped", approxCF(r.cf, cfA:Lerp(cfB, 0.5)),
    tostring(r.cf.Position))
ok("midpoint FOV lerped (70→40 = 55)", approx(r.fov, 55), r.fov)

r = interpCamera(11)
ok("exact second keyframe (fov 40)", approxCF(r.cf, cfB) and approx(r.fov, 40))

-- Clamps
r = interpCamera(-5)
ok("clamps below range to first keyframe", approxCF(r.cf, cfA))
r = interpCamera(500)
ok("clamps above range to last keyframe", approxCF(r.cf, cfC) and approx(r.fov, 90))

-- ── Cut semantics ─────────────────────────────────────────────────────────────

r = interpCamera(16)   -- midway between 11 (move) and 21 (cut)
ok("holds previous shot before a cut (CFrame)", approxCF(r.cf, cfB),
    tostring(r.cf.Position))
ok("holds previous shot before a cut (FOV)", approx(r.fov, 40), r.fov)

r = interpCamera(20.9) -- just before the cut
ok("still holding right before the cut", approxCF(r.cf, cfB))

r = interpCamera(21)   -- the cut frame itself
ok("jumps exactly at the cut frame", approxCF(r.cf, cfC) and approx(r.fov, 90),
    string.format("fov=%s", tostring(r.fov)))

-- Mode flip: turning the cut into a move makes it interpolate
track[21].mode = "move"
r = interpCamera(16)
ok("mode flipped to move → interpolates", approxCF(r.cf, cfB:Lerp(cfC, 0.5)))
track[21].mode = "cut"

-- ── Delete ────────────────────────────────────────────────────────────────────

track[11] = nil
ok("delete middle keyframe", #getSortedCameraFrames() == 2)
r = interpCamera(11)   -- now between 1 (move) and 21 (cut) → holds frame 1
ok("after delete, hold-before-cut spans the gap", approxCF(r.cf, cfA))

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
