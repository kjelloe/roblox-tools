-- test_camera_exporter.lua
-- CameraTrack ModuleScript source builder: structure, cut flags, FOV,
-- loadstring round-trip, and omit-if-empty behaviour.
-- Inlines buildCameraTrackSource from core/Exporter.lua.

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

-- ── Inline builder (mirrors Exporter.buildCameraTrackSource) ──────────────────

local function buildCameraTrackSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    frames = {")

    local track = (session.camera and session.camera.track) or {}
    local sortedFrames = {}
    for f in pairs(track) do table.insert(sortedFrames, f) end
    table.sort(sortedFrames)

    for _, frame in ipairs(sortedFrames) do
        local kf = track[frame]
        local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = kf.cf:GetComponents()
        add(string.format(
            "        [%d] = {cf = {%g,%g,%g, %g,%g,%g, %g,%g,%g, %g,%g,%g}, fov = %g, cut = %s},",
            frame, x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22,
            kf.fov or 70, tostring(kf.mode == "cut")
        ))
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── Build from a fake session ─────────────────────────────────────────────────

local cf1 = CFrame.new(3, 12, -7)
local cf2 = CFrame.new(0, 8, 20) * CFrame.Angles(0.2, math.pi, 0)

local session = {
    fps = 24,
    camera = { track = {
        [1]  = { cf = cf1, fov = 70, mode = "move" },
        [40] = { cf = cf2, fov = 35, mode = "cut"  },
    }},
}

local src = buildCameraTrackSource(session)
ok("source is non-empty string", type(src) == "string" and #src > 0)

local fn, err = loadstring(src)
ok("source compiles via loadstring", fn ~= nil, err)
if not fn then
    table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
    table.insert(out, "FAILURES DETECTED")
    return table.concat(out, "\n")
end

local data = fn()
ok("returns a table", type(data) == "table")
ok("fps preserved", data.fps == 24)
ok("two frames present", data.frames[1] ~= nil and data.frames[40] ~= nil)

local f1, f40 = data.frames[1], data.frames[40]
ok("frame 1 cut flag false", f1.cut == false)
ok("frame 40 cut flag true", f40.cut == true)
ok("frame 1 fov", approx(f1.fov, 70))
ok("frame 40 fov", approx(f40.fov, 35))

-- CFrame round-trip through the 12-number array
local rt1 = CFrame.new(
    f1.cf[1], f1.cf[2], f1.cf[3], f1.cf[4],  f1.cf[5],  f1.cf[6],
    f1.cf[7], f1.cf[8], f1.cf[9], f1.cf[10], f1.cf[11], f1.cf[12])
ok("frame 1 CFrame position round-trips", (rt1.Position - cf1.Position).Magnitude < 0.001)

local rt40 = CFrame.new(
    f40.cf[1], f40.cf[2], f40.cf[3], f40.cf[4],  f40.cf[5],  f40.cf[6],
    f40.cf[7], f40.cf[8], f40.cf[9], f40.cf[10], f40.cf[11], f40.cf[12])
ok("frame 40 rotation round-trips",
    (rt40.XVector - cf2.XVector).Magnitude < 0.001
    and (rt40.ZVector - cf2.ZVector).Magnitude < 0.001)

-- ── Empty / absent camera track ───────────────────────────────────────────────

local emptySrc = buildCameraTrackSource({ fps = 24, camera = { track = {} } })
local emptyData = loadstring(emptySrc)()
ok("empty track builds valid empty frames table", next(emptyData.frames) == nil)

local absentSrc = buildCameraTrackSource({ fps = 24 })
local absentData = loadstring(absentSrc)()
ok("absent camera key tolerated", next(absentData.frames) == nil)

-- The export flow only writes the module when next(track) is truthy —
-- mirror that predicate here.
local function shouldWrite(sess)
    return sess.camera and sess.camera.track and next(sess.camera.track) ~= nil
end
ok("module written when keyframes exist", shouldWrite(session) == true)
ok("module omitted when track empty", not shouldWrite({ camera = { track = {} } }))
ok("module omitted when camera absent", not shouldWrite({}))

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
