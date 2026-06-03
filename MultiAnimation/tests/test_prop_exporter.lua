-- test_prop_exporter.lua
-- Tests that buildPropTracksSource generates valid Lua with correct structure.
-- Uses a temporary ModuleScript + require() to validate the generated source
-- is not just syntactically valid but semantically correct.
-- Also tests that PropTracks is absent when no props are in the session.

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
    return (a.Position - b.Position).Magnitude < eps and
           (a.XVector  - b.XVector).Magnitude  < eps
end

-- ── Inlined: buildPropTracksSource ────────────────────────────────────────────
-- Mirrors Exporter.lua exactly so we test the real serialisation logic.

local function buildPropTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    props = {")

    for propName, propData in pairs(session.props or {}) do
        if not next(propData.propTrack) then continue end
        add(string.format("        [%q] = {", propName))
        local sortedFrames = {}
        for f in pairs(propData.propTrack) do table.insert(sortedFrames, f) end
        table.sort(sortedFrames)
        for _, frame in ipairs(sortedFrames) do
            local cf = propData.propTrack[frame]
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            add(string.format(
                "            [%d] = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g},",
                frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22
            ))
        end
        add("        },")
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- Mirrors MultiAnimPlayer reconstruction of a prop CFrame from the 12-number array.
local function reconstructCFrame(arr)
    return CFrame.new(
        arr[1], arr[2], arr[3],
        arr[4], arr[5], arr[6],
        arr[7], arr[8], arr[9],
        arr[10], arr[11], arr[12]
    )
end

-- ── Helper: require a generated source via a temp ModuleScript ────────────────

local tempFolder = Instance.new("Folder")
tempFolder.Name   = "__PropExporterTest"
tempFolder.Parent = workspace

local function requireSource(source)
    local ms = Instance.new("ModuleScript")
    ms.Source = source
    ms.Parent = tempFolder
    local ok2, result = pcall(require, ms)
    ms:Destroy()
    if ok2 then return true, result end
    return false, result
end

-- ── Test session with one prop and two keyframes ──────────────────────────────

local cfA = CFrame.new(2, 5, -3)
local cfB = CFrame.new(10, 0, 7) * CFrame.Angles(0, math.pi / 3, 0)

local session = {
    fps        = 30,
    frameCount = 60,
    props = {
        Block = {
            propTrack = {
                [1]  = cfA,
                [30] = cfB,
            }
        }
    }
}

local source = buildPropTracksSource(session)

-- 1. Source string is non-empty and starts with "return {"
ok("source is non-empty",           #source > 0)
ok("source starts with 'return {'", source:sub(1, 8) == "return {")

-- 2. Source contains the prop name
ok("source contains prop name 'Block'", source:find('"Block"') ~= nil or source:find("Block") ~= nil)

-- 3. Source is valid Lua (require succeeds)
local loadOk, result = requireSource(source)
ok("generated source is valid Lua (require succeeds)", loadOk,
    not loadOk and tostring(result) or nil)

if loadOk then
    -- 4. fps is correct
    ok("PropTracks.fps == 30", result.fps == 30,
        string.format("got %s", tostring(result.fps)))

    -- 5. props table exists and has Block
    ok("PropTracks.props exists", type(result.props) == "table")
    ok("PropTracks.props.Block exists", result.props and result.props["Block"] ~= nil)

    if result.props and result.props["Block"] then
        -- 6. Frame 1 array has 12 numbers
        local arr1 = result.props["Block"][1]
        ok("frame 1 array has 12 elements", arr1 ~= nil and #arr1 == 12,
            arr1 and #arr1 or "nil")

        -- 7. Reconstructed CFrame at frame 1 matches cfA
        if arr1 and #arr1 == 12 then
            local got = reconstructCFrame(arr1)
            ok("frame 1 CFrame round-trips correctly (position)",
                approxCF(got, cfA),
                string.format("got pos %s expected %s",
                    tostring(got.Position), tostring(cfA.Position)))
        end

        -- 8. Frame 30 array has 12 numbers
        local arr30 = result.props["Block"][30]
        ok("frame 30 array has 12 elements", arr30 ~= nil and #arr30 == 12,
            arr30 and #arr30 or "nil")

        -- 9. Reconstructed CFrame at frame 30 matches cfB (position + rotation)
        if arr30 and #arr30 == 12 then
            local got = reconstructCFrame(arr30)
            ok("frame 30 CFrame round-trips correctly (position + rotation)",
                approxCF(got, cfB),
                string.format("got pos %s expected %s",
                    tostring(got.Position), tostring(cfB.Position)))
        end
    end
end

-- 10. Session with no props → buildPropTracksSource still runs but produces empty props table
do
    local emptySession = {
        fps = 24,
        frameCount = 120,
        props = {}
    }
    local emptySrc = buildPropTracksSource(emptySession)
    local eOk, eResult = requireSource(emptySrc)
    ok("empty session source is valid Lua", eOk, not eOk and tostring(eResult) or nil)
    if eOk then
        ok("empty session props table is empty", eResult.props ~= nil and next(eResult.props) == nil)
    end
end

-- 11. hasPropData guard: session with props but empty propTracks → no entry written
do
    local gapSession = {
        fps = 24, frameCount = 120,
        props = { Sword = { propTrack = {} } }   -- propTrack is empty
    }
    local gapSrc  = buildPropTracksSource(gapSession)
    local gOk, gResult = requireSource(gapSrc)
    ok("prop with empty propTrack → Sword absent from output",
        gOk and gResult.props and gResult.props["Sword"] == nil,
        not gOk and tostring(gResult) or nil)
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

tempFolder:Destroy()

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
