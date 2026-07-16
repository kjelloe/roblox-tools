-- test_prop_state.lua
-- Prop visual-state tracks: captureState/applyState round-trip on real Parts,
-- lerpState blend math (transparency/colour lerp, material stepped), unknown-
-- material tolerance. The inline copies of lerpState/applyPartState are
-- registered in run_tests.py copy-sync so drift against the deployed code
-- fails the run. Headless — creates temp Parts, cleans up on exit.

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

local function near(a, b, eps)
    return math.abs(a - b) <= (eps or 0.001)
end

-- ── Inline PropCapture state logic (copy-sync: applyPartState) ────────────────

local function captureState(part)
    local c = part.Color
    return { t = part.Transparency, c = { c.R, c.G, c.B }, m = part.Material.Name }
end

local function applyPartState(part, st)
    if st.t then part.Transparency = st.t end
    if st.c then part.Color = Color3.new(st.c[1], st.c[2], st.c[3]) end
    if st.m then
        local ok, mat = pcall(function() return Enum.Material[st.m] end)
        if ok and mat then part.Material = mat end
    end
end

-- ── Inline state blend (copy-sync: lerpState) ─────────────────────────────────

local function lerpState(sa, sb, t)
    return {
        t = sa.t + (sb.t - sa.t) * t,
        c = { sa.c[1] + (sb.c[1] - sa.c[1]) * t,
              sa.c[2] + (sb.c[2] - sa.c[2]) * t,
              sa.c[3] + (sb.c[3] - sa.c[3]) * t },
        m = sa.m,
    }
end

-- ── Capture round-trip on real Parts ──────────────────────────────────────────

local pa = Instance.new("Part")
pa.Name = "__PropStateA"
pa.Anchored = true
pa.Transparency = 0.25
pa.Color = Color3.fromRGB(255, 0, 0)
pa.Material = Enum.Material.Neon
pa.Parent = workspace

local pb = Instance.new("Part")
pb.Name = "__PropStateB"
pb.Anchored = true
pb.Parent = workspace

local st = captureState(pa)
ok("captureState transparency", near(st.t, 0.25), st.t)
ok("captureState colour as 0-1 floats", near(st.c[1], 1) and near(st.c[2], 0) and near(st.c[3], 0))
ok("captureState material name", st.m == "Neon", st.m)

applyPartState(pb, st)
ok("applyState transparency round-trip", near(pb.Transparency, 0.25), pb.Transparency)
ok("applyState colour round-trip", near(pb.Color.R, 1) and near(pb.Color.B, 0))
ok("applyState material round-trip", pb.Material == Enum.Material.Neon, tostring(pb.Material))

-- ── Blend math ────────────────────────────────────────────────────────────────

local sA = { t = 1, c = { 1, 0, 0 }, m = "Concrete" }
local sB = { t = 0, c = { 0, 0, 1 }, m = "Neon" }

local mid = lerpState(sA, sB, 0.5)
ok("lerpState transparency midpoint", near(mid.t, 0.5), mid.t)
ok("lerpState colour midpoint", near(mid.c[1], 0.5) and near(mid.c[2], 0) and near(mid.c[3], 0.5))
ok("lerpState material stepped (holds earlier keyframe)", mid.m == "Concrete", mid.m)

ok("lerpState t=0 returns A values", near(lerpState(sA, sB, 0).t, 1))
ok("lerpState t=1 reaches B values", near(lerpState(sA, sB, 1).t, 0))

-- ── Unknown material tolerated (Roblox renames across versions) ───────────────

local before = pb.Material
local okCall = pcall(applyPartState, pb, { t = 0, c = { 0, 0, 0 }, m = "NotARealMaterial" })
ok("unknown material name does not error", okCall)
ok("unknown material leaves part material unchanged", pb.Material == before, tostring(pb.Material))

-- ── Cleanup ───────────────────────────────────────────────────────────────────

pa:Destroy()
pb:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
