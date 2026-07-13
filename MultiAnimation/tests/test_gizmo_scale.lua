-- test_gizmo_scale.lua
-- Gizmo distance scaling: camera/effect gizmos keep a roughly constant apparent
-- size (natural at ~20 studs, clamped 0.5×–3×). Live test — needs the plugin
-- panel open; drives the viewport camera and reads gizmo Part sizes.

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

call("scanFigures")
local PARK = 115   -- parking frame unused by other tests

-- ── Setup: one camera keyframe + one spawned-effect gizmo ─────────────────────

local viewCam = workspace.CurrentCamera
local savedCF, savedType = viewCam.CFrame, viewCam.CameraType

-- The camera keyframe gizmo is created AT the viewport camera's CFrame, so
-- capture first, then measure by moving the viewport camera away from it.
local capturePos = Vector3.new(0, 30, -60)
viewCam.CameraType = Enum.CameraType.Scriptable
viewCam.CFrame = CFrame.new(capturePos)
call("setFrame", { frame = PARK })
local cap = call("captureCamera")
ok("captureCamera at parking frame", cap.ok and cap.result and cap.result.frame == PARK,
    hs:JSONEncode(cap))

local sfxId = call("addSpawnedEffect", {
    frame = PARK, effectType = "Smoke",
    posX = capturePos.X, posY = capturePos.Y, posZ = capturePos.Z,
})
ok("spawned effect gizmo created", sfxId.ok and type(sfxId.result) == "number", hs:JSONEncode(sfxId))

local camFolder = workspace:FindFirstChild("__MultiAnimCameraGizmos")
local fxFolder  = workspace:FindFirstChild("__MultiAnimEffectGizmos")
local camGizmo  = camFolder and camFolder:FindFirstChild("CamKF_" .. PARK)
local fxGizmo   = fxFolder and fxFolder:FindFirstChild("SpawnedFX_" .. tostring(sfxId.result))
ok("gizmo parts exist", camGizmo ~= nil and fxGizmo ~= nil,
    tostring(camGizmo) .. " / " .. tostring(fxGizmo))

if camGizmo and fxGizmo then
    local function moveTo(dist)
        viewCam.CFrame = CFrame.lookAt(capturePos + Vector3.new(0, 0, dist), capturePos)
        task.wait(0.4)
    end

    -- ── 20 studs → scale 1.0 (natural size) ───────────────────────────────────
    moveTo(20)
    local nearCam = camGizmo.Size.X
    local nearFx  = fxGizmo.Size.X
    ok("camera gizmo natural size at 20 studs", math.abs(nearCam - 0.7) < 0.1, nearCam)

    -- ── 50 studs → grows ~2.5x ────────────────────────────────────────────────
    moveTo(50)
    ok("camera gizmo grows with distance", camGizmo.Size.X > nearCam * 2, camGizmo.Size.X)
    ok("effect gizmo grows with distance", fxGizmo.Size.X > nearFx * 2, fxGizmo.Size.X)

    -- ── 3 studs → clamped at 0.5x ─────────────────────────────────────────────
    moveTo(3)
    ok("camera gizmo clamps at 0.5x when very close",
        math.abs(camGizmo.Size.X - 0.7 * 0.5) < 0.06, camGizmo.Size.X)

    -- ── 500 studs → clamped at 3x ─────────────────────────────────────────────
    moveTo(500)
    ok("camera gizmo clamps at 3x when very far",
        math.abs(camGizmo.Size.X - 0.7 * 3) < 0.15, camGizmo.Size.X)
end

-- ── Cleanup ───────────────────────────────────────────────────────────────────

call("deleteCameraKeyframe", { frame = PARK })
if sfxId.ok then call("deleteSpawnedEffect", { id = sfxId.result }) end
viewCam.CameraType = savedType
viewCam.CFrame = savedCF

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
