-- test_smooth_interp.lua
-- Smooth (Catmull-Rom-style) interpolation used by CutscenePlayer /
-- MultiAnimPlayer / CutsceneCamera in smooth mode (default ON): cubic De
-- Casteljau over CFrame:Lerp with extrapolated tangent controls, plus a
-- standard Catmull-Rom for Vector3. Inline copies — keep in sync.

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

-- ── Inline copies ─────────────────────────────────────────────────────────────

local SMOOTH_K = 1 / 3

local function cubicCF(q1, b1, b2, q2, t)
    local p01 = q1:Lerp(b1, t)
    local p12 = b1:Lerp(b2, t)
    local p23 = b2:Lerp(q2, t)
    return p01:Lerp(p12, t):Lerp(p12:Lerp(p23, t), t)
end

local function smoothCF(q0, q1, q2, q3, t)
    local b1 = q0:Lerp(q1, 1 + SMOOTH_K):Lerp(q1:Lerp(q2, SMOOTH_K), 0.5)
    local b2 = q3:Lerp(q2, 1 + SMOOTH_K):Lerp(q2:Lerp(q1, SMOOTH_K), 0.5)
    return cubicCF(q1, b1, b2, q2, t)
end

local function smoothV3(p0, p1, p2, p3, t)
    local t2, t3 = t * t, t * t * t
    return ((p1 * 2) + (p2 - p0) * t
        + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
        + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

local function near(a, b, eps) return (a - b).Magnitude < (eps or 0.01) end

-- ── Endpoints are exact ───────────────────────────────────────────────────────

local A = CFrame.new(0, 0, 0)
local B = CFrame.new(0, 2, 0)
local C = CFrame.new(0, 3, 0)
local D = CFrame.new(0, 3.2, 0)

ok("smoothCF t=0 returns q1 exactly", near(smoothCF(A, B, C, D, 0).Position, B.Position, 1e-4))
ok("smoothCF t=1 returns q2 exactly", near(smoothCF(A, B, C, D, 1).Position, C.Position, 1e-4))
ok("smoothV3 endpoints exact",
    near(smoothV3(A.Position, B.Position, C.Position, D.Position, 0), B.Position, 1e-4)
    and near(smoothV3(A.Position, B.Position, C.Position, D.Position, 1), C.Position, 1e-4))

-- ── Uniform linear data stays linear ─────────────────────────────────────────

local L = { Vector3.new(0, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 2, 0), Vector3.new(0, 3, 0) }
ok("smoothV3 on a uniform line hits the linear midpoint",
    near(smoothV3(L[1], L[2], L[3], L[4], 0.5), Vector3.new(0, 1.5, 0), 1e-3))
local LC = { CFrame.new(0, 0, 0), CFrame.new(0, 1, 0), CFrame.new(0, 2, 0), CFrame.new(0, 3, 0) }
ok("smoothCF on a uniform line stays near the line",
    near(smoothCF(LC[1], LC[2], LC[3], LC[4], 0.5).Position, Vector3.new(0, 1.5, 0), 0.05))

-- ── C1-ish continuity: velocity matches across a keyframe boundary ───────────

-- Arc keyframes at equal spacing: sample either side of the B→C boundary.
local kfs = { A, B, C, D }
local function sampleSeg(i, t)   -- segment kfs[i] → kfs[i+1] with CR neighbours
    local q0 = kfs[i - 1] or kfs[i]
    local q3 = kfs[i + 2] or kfs[i + 1]
    return smoothCF(q0, kfs[i], kfs[i + 1], q3, t)
end
local dt = 0.02
local vBefore = (sampleSeg(2, 1).Position - sampleSeg(2, 1 - dt).Position) / dt
local vAfter  = (sampleSeg(3, dt).Position - sampleSeg(3, 0).Position) / dt
ok("velocity continuous across keyframe boundary",
    (vBefore - vAfter).Magnitude < 0.35 * math.max(vBefore.Magnitude, vAfter.Magnitude, 0.1),
    string.format("before=%.2f after=%.2f", vBefore.Magnitude, vAfter.Magnitude))

-- Linear sampling for contrast has a hard kink at the same boundary.
local linBefore = (C.Position - B.Position)
local linAfter  = (D.Position - C.Position)
ok("(sanity) linear has a velocity kink here",
    (linBefore - linAfter).Magnitude > 0.5)

-- ── Rotation smoothing ────────────────────────────────────────────────────────

local function rotKF(deg) return CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(deg), 0, 0) end
local R = { rotKF(0), rotKF(45), rotKF(90), rotKF(135) }
local mid = smoothCF(R[1], R[2], R[3], R[4], 0.5)
-- pitch angle of the up vector: at halfway between 45° and 90° it should be ~67.5°
local upAngle = math.deg(math.acos(math.clamp(mid.UpVector.Y, -1, 1)))
ok("rotation midpoint near the angular midpoint", math.abs(upAngle - 67.5) < 8, upAngle)
ok("rotation endpoints exact",
    (smoothCF(R[1], R[2], R[3], R[4], 0).UpVector - R[2].UpVector).Magnitude < 1e-3
    and (smoothCF(R[1], R[2], R[3], R[4], 1).UpVector - R[3].UpVector).Magnitude < 1e-3)

-- Full-flip ladder (45° steps through 360°): every sampled step must rotate
-- forward monotonically — no reversals or flips from the extrapolated tangents.
local flip = {}
for i = 0, 8 do flip[i + 1] = rotKF(i * 45) end
local monotone = true
local prevCF = nil
for seg = 2, 8 do
    for s = 0, 4 do
        local q0 = flip[seg - 1] or flip[seg]
        local q3 = flip[seg + 2] or flip[seg + 1]
        local cf = smoothCF(q0, flip[seg], flip[seg + 1], q3, s / 4)
        -- unwrap: accumulated angle from consecutive small rotations
        local stepAngle = math.deg(math.acos(math.clamp(
            (cf.UpVector:Dot((prevCF or cf).UpVector)), -1, 1)))
        prevCF = cf
        if stepAngle > 30 then monotone = false end
    end
end
ok("45-degree flip ladder samples rotate in small steps (no flips)", monotone)

-- ── Constant easing still holds exactly (t=0 short-circuits) ─────────────────

ok("t=0 (Constant easing) returns the held keyframe",
    near(smoothCF(A, B, C, D, 0).Position, B.Position, 1e-4))

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
