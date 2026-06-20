-- test_ui_camera.lua
-- Camera track UI integration — drives the LIVE plugin through the TestBridge.
-- Captures a camera keyframe at a parking frame, exercises mode toggling,
-- interpolation, gizmo lifecycle, and preview state restore; deletes
-- everything it created and restores the timeline position.

local HttpService = game:GetService("HttpService")

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

local function finish()
    table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
    table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
    return table.concat(out, "\n")
end

local bridge = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
ok("TestBridge present (is the plugin running?)", bridge ~= nil)
if not bridge then return finish() end

local function call(cmd, args)
    local resJson = bridge:Invoke(cmd, args and HttpService:JSONEncode(args) or nil)
    return HttpService:JSONDecode(resJson)
end

local GIZMO_FOLDER = "__MultiAnimCameraGizmos"
local function gizmoFor(frame)
    local folder = workspace:FindFirstChild(GIZMO_FOLDER)
    return folder and folder:FindFirstChild("CamKF_" .. frame)
end

local prevFrame = call("getCurrentFrame")

-- ── Capture at two parking frames ─────────────────────────────────────────────

local r = call("getFrameCount")
local frameCount = (r.ok and r.result) or 120
local PARK_A = frameCount - 11
local PARK_B = frameCount - 5

r = call("getCameraFrames")
local preexisting = {}
for _, f in ipairs((r.ok and r.result) or {}) do preexisting[f] = true end

if preexisting[PARK_A] or preexisting[PARK_B] then
    table.insert(out, "SKIP  camera round-trip (parking frames hold user data)")
    return finish()
end

call("setFrame", { frame = PARK_A })
r = call("captureCamera")
ok("captureCamera at frame " .. PARK_A, r.ok and r.result and r.result.frame == PARK_A, r.err)
ok("captured keyframe defaults to move", r.ok and r.result and r.result.mode == "move")
local capturedFov = r.ok and r.result and r.result.fov

call("setFrame", { frame = PARK_B })
r = call("captureCamera")
ok("captureCamera at frame " .. PARK_B, r.ok and r.result and r.result.frame == PARK_B, r.err)

r = call("getCameraFrames")
local haveA, haveB = false, false
for _, f in ipairs((r.ok and r.result) or {}) do
    if f == PARK_A then haveA = true end
    if f == PARK_B then haveB = true end
end
ok("both camera keyframes recorded", haveA and haveB)

-- ── Gizmos ────────────────────────────────────────────────────────────────────

local gA, gB = gizmoFor(PARK_A), gizmoFor(PARK_B)
ok("gizmo parts created for both keyframes", gA ~= nil and gB ~= nil)
ok("gizmos are not Archivable (never saved with place)",
    gA ~= nil and gA.Archivable == false)

-- ── Mode toggle (move → cut) ──────────────────────────────────────────────────

r = call("setCameraMode", { frame = PARK_B, mode = "cut" })
ok("setCameraMode cut", r.ok and r.result == true, r.err)

r = call("getCameraKeyframe", { frame = PARK_B })
ok("keyframe reports cut mode", r.ok and r.result and r.result.mode == "cut", r.err)
ok("keyframe preserves fov through mode change",
    r.ok and r.result and capturedFov and math.abs(r.result.fov - capturedFov) < 0.01)

-- ── Cut-aware interpolation through the bridge ────────────────────────────────

local midFrame = math.floor((PARK_A + PARK_B) / 2)
r = call("getInterpolatedCamera", { frame = midFrame })
ok("interpolated camera exists between keyframes", r.ok and r.result ~= nil, r.err)
if r.ok and r.result then
    local kfA = call("getCameraKeyframe", { frame = PARK_A })
    -- PARK_B is a cut → midway must HOLD the PARK_A shot exactly.
    if kfA.ok and kfA.result and kfA.result.cf then
        local same = true
        for i = 1, 12 do
            if math.abs(r.result.cf[i] - kfA.result.cf[i]) > 0.001 then same = false end
        end
        ok("hold-before-cut: midway equals previous keyframe", same)
    else
        table.insert(out, "SKIP  hold-before-cut (keyframe A not found)")
    end
end

-- ── Camera preview round-trip restores the viewport ───────────────────────────

local camBefore = workspace.CurrentCamera.CFrame
r = call("setCameraPreview", { on = true })
ok("preview ON", r.ok and r.result == true, r.err)
r = call("setCameraPreview", { on = false })
ok("preview OFF", r.ok and r.result == false, r.err)
local camAfter = workspace.CurrentCamera.CFrame
ok("viewport camera restored after preview round-trip",
    (camBefore.Position - camAfter.Position).Magnitude < 0.01,
    tostring((camBefore.Position - camAfter.Position).Magnitude))

-- ── Cleanup: delete both keyframes; gizmos must vanish ────────────────────────

call("deleteCameraKeyframe", { frame = PARK_A })
call("deleteCameraKeyframe", { frame = PARK_B })

r = call("getCameraFrames")
local leftover = false
for _, f in ipairs((r.ok and r.result) or {}) do
    if f == PARK_A or f == PARK_B then leftover = true end
end
ok("camera keyframes deleted", not leftover)
ok("gizmos removed with their keyframes",
    gizmoFor(PARK_A) == nil and gizmoFor(PARK_B) == nil)

-- Restore timeline position
if prevFrame.ok then call("setFrame", { frame = prevFrame.result }) end

return finish()
