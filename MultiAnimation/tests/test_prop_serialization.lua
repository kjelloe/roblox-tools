-- test_prop_serialization.lua
-- Tests the CFrame 12-number array format used by both JSON session persistence
-- and PropTracks ModuleScript export. Verifies that GetComponents() → CFrame.new()
-- round-trips are lossless, and that CFrame:Lerp() behaves correctly for prop animation.
-- Pure math — no workspace instances or module requires needed.

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

local function approx(a, b, eps)  return math.abs(a - b) < (eps or 1e-4) end
local function approxV3(a, b, eps)
    return (a - b).Magnitude < (eps or 1e-4)
end
local function approxCF(a, b, eps)
    eps = eps or 1e-4
    return (a.Position - b.Position).Magnitude < eps
       and (a.XVector  - b.XVector).Magnitude  < eps
       and (a.YVector  - b.YVector).Magnitude  < eps
       and (a.ZVector  - b.ZVector).Magnitude  < eps
end

-- Mirrors serialize path: { cf:GetComponents() }
local function serialize(cf)
    local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
    return {x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22}
end

-- Mirrors deserialize path: CFrame.new(arr[1]…arr[12])
local function deserialize(arr)
    return CFrame.new(
        arr[1], arr[2], arr[3],
        arr[4], arr[5], arr[6],
        arr[7], arr[8], arr[9],
        arr[10], arr[11], arr[12]
    )
end

-- ── Round-trip tests ──────────────────────────────────────────────────────────

-- 1. CFrame.identity round-trips
do
    local cf  = CFrame.identity
    local arr = serialize(cf)
    local got = deserialize(arr)
    ok("identity round-trip", approxCF(cf, got),
        string.format("pos diff %.6f", (cf.Position - got.Position).Magnitude))
end

-- 2. Pure translation round-trips
do
    local cf  = CFrame.new(5.5, -10, 23.7)
    local got = deserialize(serialize(cf))
    ok("translation round-trip (position preserved)",
        approxV3(cf.Position, got.Position),
        string.format("got %s expected %s", tostring(got.Position), tostring(cf.Position)))
end

-- 3. Pure rotation (90° Y) round-trips
do
    local cf  = CFrame.Angles(0, math.pi / 2, 0)
    local got = deserialize(serialize(cf))
    ok("90° Y-rotation round-trip", approxCF(cf, got))
end

-- 4. Combined translation + rotation round-trips losslessly
do
    local cf  = CFrame.new(3, -7, 12) * CFrame.Angles(0.4, 1.2, -0.8)
    local got = deserialize(serialize(cf))
    ok("translate + rotate round-trip (position)",
        approxV3(cf.Position, got.Position),
        string.format("diff %.6f", (cf.Position - got.Position).Magnitude))
    ok("translate + rotate round-trip (rotation XVector)",
        approxV3(cf.XVector, got.XVector),
        string.format("diff %.6f", (cf.XVector - got.XVector).Magnitude))
    ok("translate + rotate round-trip (rotation YVector)",
        approxV3(cf.YVector, got.YVector))
end

-- 5. Array has exactly 12 elements
do
    local arr = serialize(CFrame.new(1, 2, 3) * CFrame.Angles(0.1, 0.2, 0.3))
    ok("serialize produces exactly 12 elements", #arr == 12, tostring(#arr))
end

-- 6. First 3 elements are position (x, y, z)
do
    local cf  = CFrame.new(7, -3, 11)
    local arr = serialize(cf)
    ok("arr[1]=x arr[2]=y arr[3]=z (position first)",
        approx(arr[1], 7) and approx(arr[2], -3) and approx(arr[3], 11),
        string.format("[1]=%.3f [2]=%.3f [3]=%.3f", arr[1], arr[2], arr[3]))
end

-- 7. Elements 4–12 are the rotation matrix rows
do
    local cf  = CFrame.identity   -- rotation matrix = identity
    local arr = serialize(cf)
    -- r00=arr[4]=1, r01=arr[5]=0, r02=arr[6]=0
    -- r10=arr[7]=0, r11=arr[8]=1, r12=arr[9]=0
    -- r20=arr[10]=0, r21=arr[11]=0, r22=arr[12]=1
    ok("identity rotation: arr[4..6] = 1,0,0",
        approx(arr[4],1) and approx(arr[5],0) and approx(arr[6],0))
    ok("identity rotation: arr[7..9] = 0,1,0",
        approx(arr[7],0) and approx(arr[8],1) and approx(arr[9],0))
    ok("identity rotation: arr[10..12] = 0,0,1",
        approx(arr[10],0) and approx(arr[11],0) and approx(arr[12],1))
end

-- ── CFrame:Lerp() boundary and midpoint tests ─────────────────────────────────

-- 8. Lerp at alpha=0 equals source
do
    local cfA = CFrame.new(0, 0, 0)
    local cfB = CFrame.new(100, 50, -30)
    local got = cfA:Lerp(cfB, 0)
    ok("Lerp alpha=0 equals cfA", approxCF(got, cfA))
end

-- 9. Lerp at alpha=1 equals destination
do
    local cfA = CFrame.new(0, 0, 0)
    local cfB = CFrame.new(100, 50, -30)
    local got = cfA:Lerp(cfB, 1)
    ok("Lerp alpha=1 equals cfB", approxCF(got, cfB))
end

-- 10. Lerp at alpha=0.5 midpoint position
do
    local cfA = CFrame.new(0,   0, 0)
    local cfB = CFrame.new(20, 10, 0)
    local mid = cfA:Lerp(cfB, 0.5)
    ok("Lerp alpha=0.5 midpoint position X=10",
        approx(mid.Position.X, 10),
        string.format("got X=%.4f", mid.Position.X))
    ok("Lerp alpha=0.5 midpoint position Y=5",
        approx(mid.Position.Y, 5),
        string.format("got Y=%.4f", mid.Position.Y))
end

-- 11. Slerp: rotation at midpoint is not identity (rotation IS being interpolated)
do
    local cfA = CFrame.new(0, 0, 0)
    local cfB = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0)  -- 180° Y
    local mid = cfA:Lerp(cfB, 0.5)
    local _, yRot, _ = mid:ToEulerAnglesXYZ()
    -- Midpoint of 0→180° slerp should be ≈90°
    ok("slerp midpoint rotation ≈ 90° Y (not 0° or 180°)",
        approx(math.abs(yRot), math.pi / 2, 0.05),
        string.format("got %.4f rad, expected %.4f", math.abs(yRot), math.pi / 2))
end

-- 12. Full round-trip through serialize then reconstruct then lerp matches direct lerp
do
    local cfA = CFrame.new(0, 5, 0) * CFrame.Angles(0.3, 0, 0)
    local cfB = CFrame.new(10, 5, 0) * CFrame.Angles(0.9, 0, 0)
    local direct  = cfA:Lerp(cfB, 0.5)
    local cfA2    = deserialize(serialize(cfA))
    local cfB2    = deserialize(serialize(cfB))
    local indirect = cfA2:Lerp(cfB2, 0.5)
    ok("lerp after serialize/deserialize matches direct lerp",
        approxCF(direct, indirect, 1e-3),
        string.format("pos diff %.6f", (direct.Position - indirect.Position).Magnitude))
end

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
