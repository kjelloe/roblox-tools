-- test_camera_capture.lua
-- Camera-capture regression coverage for Simple Mode navigation, including the
-- Look Through viewport mirror. Guards the drift bug where every navigation
-- departure rewrote the frame's camera keyframe from the live viewport:
-- stepping through frames mutated saved keyframes, reset cut→move, and
-- restamped easing. Builds its frames at the END of the timeline (Simple Mode
-- collapses frameCount to the data extent, so fixed high parking frames don't
-- exist) and cleans them up afterwards. Live test — needs the plugin panel.

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

local bf = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
local hs = game:GetService("HttpService")
if not bf then
    return "SKIP: __MultiAnimTestBridge not found\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local function call(cmd, args)
    return hs:JSONDecode(bf:Invoke(cmd, args and hs:JSONEncode(args) or nil))
end

local function sameKF(a, b, eps)
    if not a or not b then return false end
    eps = eps or 0.001
    if math.abs(a.fov - b.fov) > eps then return false end
    for i = 1, 12 do
        if math.abs(a.cf[i] - b.cf[i]) > eps then return false end
    end
    return true
end

call("scanFigures")
call("setMode", { mode = "simple" })
call("setSimpleCamera", { on = true })

if call("getSimpleCameraInfo").result == nil then
    return "SKIP: no active SimpleCamera part\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local cam = workspace.CurrentCamera

-- Re-aim the ACTIVE gizmo through the bridge — tagged scenes can each carry a
-- SimpleCamera part, so a workspace search can grab the wrong one.
local function aimCamera(x, y, z)
    call("setSimpleCameraCF", { x = x, y = y, z = z, tx = 0, ty = 3, tz = 0 })
end

-- ── Author two keyframes at the end of the timeline via Add Frame ─────────────
-- Add captures the current frame and advances into a new blank end slot, so
-- F1/F2 land beyond any pre-existing session data; EMPTY is the final blank.

local fc0 = call("getFrameCount").result or 1
local base = fc0
local baseHadData = call("simpleFrameHasData", { frame = base }).result == true
call("simpleNavigate", { frame = base })
call("simpleAddFrame")                     -- (re)captures base, cursor → base+1
local F1, F2, EMPTY = base + 1, base + 2, base + 3
aimCamera(40, 12, 40)
call("simpleAddFrame")                     -- captures F1 = shot 1, cursor → F2
aimCamera(-30, 8, 35)
call("simpleAddFrame")                     -- captures F2 = shot 2, cursor → EMPTY

local kf1 = call("getCameraKeyframe", { frame = F1 }).result
local kf2 = call("getCameraKeyframe", { frame = F2 }).result
ok("camera keyframe authored at F1 from the gizmo pose",
    kf1 ~= nil and math.abs(kf1.cf[1] - 40) < 0.01, kf1 and kf1.cf[1])
ok("camera keyframe authored at F2 from the gizmo pose",
    kf2 ~= nil and math.abs(kf2.cf[1] - (-30)) < 0.01, kf2 and kf2.cf[1])

call("setCameraMode",   { frame = F1, mode = "cut" })
call("setCameraEasing", { frame = F2, easing = "Bounce" })
kf1 = call("getCameraKeyframe", { frame = F1 }).result
kf2 = call("getCameraKeyframe", { frame = F2 }).result

-- ── Stability: stepping through frames must not rewrite keyframes ─────────────

for _ = 1, 2 do
    call("simpleNavigate", { frame = F1 })
    call("simpleNavigate", { frame = F2 })
end
local kf1b = call("getCameraKeyframe", { frame = F1 }).result
local kf2b = call("getCameraKeyframe", { frame = F2 }).result
ok("navigation leaves keyframe 1 bit-stable (Look Through off)", sameKF(kf1, kf1b))
ok("navigation leaves keyframe 2 bit-stable (Look Through off)", sameKF(kf2, kf2b))
ok("cut mode survives navigation", kf1b and kf1b.mode == "cut", kf1b and kf1b.mode)
ok("camera easing survives navigation",
    call("getCameraEasing", { frame = F2 }).result == "Bounce")

-- ── Look Through ON: the viewport mirror must not corrupt keyframes ───────────

call("setSimpleLookThrough", { on = true })
task.wait(0.15)

for _ = 1, 2 do
    call("simpleNavigate", { frame = F1 })
    task.wait(0.15)   -- let the Heartbeat mirror (viewport → gizmo) run
    call("simpleNavigate", { frame = F2 })
    task.wait(0.15)
end
local kf1c = call("getCameraKeyframe", { frame = F1 }).result
local kf2c = call("getCameraKeyframe", { frame = F2 }).result
ok("keyframe 1 bit-stable across Look Through step-through", sameKF(kf1, kf1c))
ok("keyframe 2 bit-stable across Look Through step-through", sameKF(kf2, kf2c))

-- Focus contract: applying a shot must put cam.Focus in front of the eye —
-- a stale/behind Focus makes Studio's camera controller flip the view, which
-- the mirror then feeds back into captures.
call("simpleNavigate", { frame = F1 })
task.wait(0.15)
local focusOffset = cam.Focus.Position - cam.CFrame.Position
ok("cam.Focus sits in front of the eye after navigation apply",
    focusOffset.Magnitude > 0.001 and cam.CFrame.LookVector:Dot(focusOffset.Unit) > 0.9,
    string.format("dot=%.3f", cam.CFrame.LookVector:Dot(
        focusOffset.Magnitude > 0.001 and focusOffset.Unit or Vector3.new(0, 0, -1))))

-- Flying the viewport at a frame IS an intentional camera move in Look
-- Through mode: departure must rewrite that keyframe (and only that one),
-- preserving its easing.
local FLOWN = CFrame.lookAt(Vector3.new(0, 50, -40), Vector3.new(0, 3, 0))
call("simpleNavigate", { frame = F2 })
task.wait(0.15)
cam.CFrame = FLOWN
task.wait(0.25)   -- mirror copies viewport → gizmo
call("simpleNavigate", { frame = F1 })
task.wait(0.15)
local kf2d = call("getCameraKeyframe", { frame = F2 }).result
ok("Look Through fly at a frame rewrites its keyframe",
    kf2d ~= nil and math.abs(kf2d.cf[2] - 50) < 0.5, kf2d and kf2d.cf[2])
ok("easing preserved when a moved camera rewrites its keyframe",
    call("getCameraEasing", { frame = F2 }).result == "Bounce")
local kf1d = call("getCameraKeyframe", { frame = F1 }).result
ok("the other keyframe is untouched by the rewrite", sameKF(kf1, kf1d))

-- ── Empty frames: passing through never creates keyframes; flying does ───────

call("simpleNavigate", { frame = EMPTY })
task.wait(0.15)
call("simpleNavigate", { frame = F1 })
task.wait(0.15)
ok("passing through an empty frame creates no camera keyframe",
    call("getCameraKeyframe", { frame = EMPTY }).result == nil)

call("simpleNavigate", { frame = EMPTY })
task.wait(0.15)
cam.CFrame = CFrame.lookAt(Vector3.new(25, 25, -25), Vector3.new(0, 3, 0))
task.wait(0.25)
call("simpleNavigate", { frame = F1 })
task.wait(0.15)
ok("Look Through fly at an empty frame creates its keyframe",
    call("getCameraKeyframe", { frame = EMPTY }).result ~= nil)

call("setSimpleLookThrough", { on = false })

-- ── Pin Cam: explicit stamp, preserving mode/easing; inert with camera off ───

call("simpleNavigate", { frame = F1 })
task.wait(0.1)
aimCamera(55, 15, 55)
local pr = call("pinCamera")
ok("pinCamera stamps the re-aimed shot at the current frame",
    pr.result == true and math.abs(call("getCameraKeyframe", { frame = F1 }).result.cf[1] - 55) < 0.01)
ok("pinCamera preserves the keyframe's cut mode",
    call("getCameraKeyframe", { frame = F1 }).result.mode == "cut")

call("setSimpleCamera", { on = false })
ok("pinCamera is a no-op while Camera View is off", call("pinCamera").result == false)
call("setSimpleCamera", { on = true })

-- ── Cleanup: delete the frames this test appended (highest first) ─────────────

for _, f in ipairs({ EMPTY, F2, F1 }) do
    call("setFrame", { frame = f })
    call("simpleDeleteKeyframe")   -- doSimpleDeleteFrame: wipes all tracks + shrinks
end
if not baseHadData then
    -- Add re-captured the base frame; remove what we created there.
    call("deleteCameraKeyframe", { frame = base })
    for _, rig in ipairs(call("getRigs").result or {}) do
        call("deleteKeyframe", { rig = rig, frame = base })
    end
    for _, prop in ipairs(call("getSimpleProps").result or {}) do
        call("deletePropKeyframe", { prop = prop, frame = base })
    end
end
call("setSimpleCamera", { on = false })

local fcEnd = call("getFrameCount").result
ok("cleanup: frame count restored", fcEnd == fc0, fcEnd .. " vs " .. fc0)
local leftover = false
for _, f in ipairs(call("getCameraFrames").result or {}) do
    if f == F1 or f == F2 or f == EMPTY then leftover = true end
end
ok("cleanup: no camera keyframes left at appended frames", not leftover)

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
