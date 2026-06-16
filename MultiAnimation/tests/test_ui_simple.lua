-- test_ui_simple.lua
-- Simple Mode integration tests — drives the LIVE plugin panel through the
-- TestBridge (CoreGui.__MultiAnimTestBridge, see plugin/core/TestBridge.lua).
--
-- Covers: mode toggle, idempotent step-forward capture (capture departure
-- frame only if empty), Delete Keyframe "redo" (clears + snaps to previous
-- frame without moving the cursor), Camera View capture-on-step, FIGURES
-- auto-track/untrack of non-rig props while in Simple mode, the Play/Stop
-- toggle, and the manipulable camera object (creation, FOV, Look Through
-- guard/restore, capture-from-gizmo).
--
-- Mutates the session only at parking frames far from real data, which are
-- deleted again before exiting. Restores mode, frame, active rig, and
-- destroys the SimpleCamera object if this run is the one that created it.

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

-- ── Bridge presence ───────────────────────────────────────────────────────────

local bridge = game:GetService("CoreGui"):FindFirstChild("__MultiAnimTestBridge")
ok("TestBridge present (is the plugin running?)", bridge ~= nil)
if not bridge then return finish() end

local function call(cmd, args)
    local resJson = bridge:Invoke(cmd, args and HttpService:JSONEncode(args) or nil)
    return HttpService:JSONDecode(resJson)
end

-- ── Save state to restore at the end ─────────────────────────────────────────

local prevMode   = call("getMode")
local prevFrame  = call("getCurrentFrame")
local prevActive = call("getActiveRigs")

-- The Camera View camera is now a real, persistent Part (created on first
-- toggle-on) rather than a flag with no scene effect — only destroy it at
-- the end of this file if THIS run is the one that created it.
local figForCam0 = workspace:FindFirstChild("FIGURES")
local preexistingSimpleCam = figForCam0 and figForCam0:FindFirstChild("SimpleCamera") ~= nil

-- ── Mode toggle ───────────────────────────────────────────────────────────────

local r = call("setMode", { mode = "simple" })
ok("setMode simple", r.ok and r.result == "simple", r.err)
r = call("getMode")
ok("getMode reflects simple", r.ok and r.result == "simple", r.err)

r = call("setMode", { mode = "advanced" })
ok("setMode advanced", r.ok and r.result == "advanced", r.err)
r = call("getMode")
ok("getMode reflects advanced", r.ok and r.result == "advanced", r.err)

r = call("setMode", { mode = "simple" })
ok("setMode back to simple for the rest of the suite", r.ok and r.result == "simple", r.err)

-- ── Rig discovery (unaffected by mode) ───────────────────────────────────────

r = call("getRigs")
ok("getRigs returns at least 1", r.ok and type(r.result) == "table" and #r.result >= 1, r.err)
if not (r.ok and #r.result >= 1) then return finish() end
local rigA = r.result[1]

r = call("getFrameCount")
local frameCount = (r.ok and r.result) or 120
ok("getFrameCount > 0", r.ok and frameCount > 0, r.err)

-- Simple Mode captures ALL rigs/props (and camera, if enabled) in one shot,
-- so occupancy checks and cleanup must be frame-wide, not rig-specific.
local function frameOccupied(frame)
    local hd = call("simpleFrameHasData", { frame = frame })
    return hd.ok and hd.result == true
end
local function clearFrame(frame)
    call("setFrame", { frame = frame })
    call("simpleDeleteKeyframe")
end

-- ── Step-forward capture + idempotent skip + Delete Keyframe redo ──────────────

if frameCount < 40 then
    table.insert(out, "SKIP  step-forward/delete-keyframe tests (frameCount too small for a safe parking frame)")
else
    local PARK = frameCount - 31   -- distinct from other test files' parking offsets (-5/-7/-11/-17/-23)

    local occupied = frameOccupied(PARK) or frameOccupied(PARK + 1)

    if occupied then
        table.insert(out, "SKIP  step-forward/delete-keyframe tests (parking frames already hold user data)")
    else
        call("setFrame", { frame = PARK })
        r = call("simpleFrameHasData", { frame = PARK })
        ok("parking frame starts empty", r.ok and r.result == false, r.err)

        -- Step forward from an empty frame captures it before advancing.
        r = call("simpleStepForward")
        ok("simpleStepForward advances to PARK+1", r.ok and r.result == PARK + 1, r.err)

        r = call("getFrames", { rig = rigA })
        local found = false
        for _, f in ipairs((r.ok and r.result) or {}) do if f == PARK then found = true end end
        ok("departure frame captured on step-forward", found)

        r = call("simpleFrameHasData", { frame = PARK })
        ok("simpleFrameHasData true after capture", r.ok and r.result == true, r.err)

        -- Idempotency: stepping forward from a frame that already has data
        -- must NOT recapture, even if the live pose was mutated afterward.
        call("setFrame", { frame = PARK })   -- reapplies PARK's recorded pose
        local cf1 = call("getJointCF", { rig = rigA, frame = PARK, joint = "RootJoint" })
        ok("captured RootJoint readable", cf1.ok and cf1.result ~= nil, cf1.err)

        local fig = workspace:FindFirstChild("FIGURES")
        local torso = fig and fig:FindFirstChild(rigA) and fig[rigA]:FindFirstChild("Torso")
        if torso then
            torso.CFrame = torso.CFrame * CFrame.new(3, 0, 0)   -- mutate live pose directly, bypassing the bridge
        end

        r = call("simpleStepForward")   -- PARK already has data → must skip recapture
        ok("simpleStepForward (idempotent) advances to PARK+1", r.ok and r.result == PARK + 1, r.err)

        local cf2 = call("getJointCF", { rig = rigA, frame = PARK, joint = "RootJoint" })
        ok("idempotent step-forward did not overwrite existing keyframe",
            cf1.ok and cf2.ok and HttpService:JSONEncode(cf1.result) == HttpService:JSONEncode(cf2.result),
            "before=" .. HttpService:JSONEncode(cf1.result) .. " after=" .. HttpService:JSONEncode(cf2.result))

        call("setFrame", { frame = PARK })   -- snap live pose back, undoing the manual mutation above

        -- Delete Keyframe: clears current frame's data, snaps pose to the
        -- previous frame WITHOUT moving the cursor, enabling re-pose + redo.
        call("setFrame", { frame = PARK + 1 })
        r = call("simpleStepForward")   -- PARK+1 empty → capture it, advance to PARK+2
        ok("captured PARK+1 before delete-keyframe test", r.ok and r.result == PARK + 2, r.err)

        r = call("getFrames", { rig = rigA })
        found = false
        for _, f in ipairs((r.ok and r.result) or {}) do if f == PARK + 1 then found = true end end
        ok("PARK+1 captured", found)

        call("setFrame", { frame = PARK + 1 })
        r = call("simpleDeleteKeyframe")
        ok("simpleDeleteKeyframe does not move the cursor", r.ok and r.result == PARK + 1, r.err)

        r = call("getCurrentFrame")
        ok("cursor still at PARK+1 after delete", r.ok and r.result == PARK + 1, r.err)

        r = call("getFrames", { rig = rigA })
        found = false
        for _, f in ipairs((r.ok and r.result) or {}) do if f == PARK + 1 then found = true end end
        ok("PARK+1 data cleared by delete-keyframe", not found)

        r = call("simpleFrameHasData", { frame = PARK + 1 })
        ok("simpleFrameHasData false after delete", r.ok and r.result == false, r.err)

        -- Redo: stepping forward again from the now-empty PARK+1 re-captures it.
        r = call("simpleStepForward")
        ok("redo: simpleStepForward recaptures PARK+1 and advances to PARK+2", r.ok and r.result == PARK + 2, r.err)

        r = call("getFrames", { rig = rigA })
        found = false
        for _, f in ipairs((r.ok and r.result) or {}) do if f == PARK + 1 then found = true end end
        ok("redo: PARK+1 captured again", found)

        -- Cleanup — clear ALL rigs/props at both touched frames (Simple Mode
        -- captured them together; a rig-specific delete would leak the others).
        clearFrame(PARK)
        clearFrame(PARK + 1)
    end
end

-- ── Camera View capture-on-step ──────────────────────────────────────────────

if frameCount < 45 then
    table.insert(out, "SKIP  camera-on-step test (frameCount too small for a safe parking frame)")
else
    local CAMPARK = frameCount - 41

    r = call("getCameraFrames")
    local camOccupied = frameOccupied(CAMPARK)   -- rigs/props (camera flag is off until we toggle it below)
    for _, f in ipairs((r.ok and r.result) or {}) do if f == CAMPARK then camOccupied = true end end

    if camOccupied then
        table.insert(out, "SKIP  camera-on-step test (parking frame already holds user data)")
    else
        r = call("setSimpleCamera", { on = true })
        ok("setSimpleCamera on", r.ok and r.result == true, r.err)

        call("setFrame", { frame = CAMPARK })
        r = call("simpleFrameHasData", { frame = CAMPARK })
        ok("camera parking frame starts empty", r.ok and r.result == false, r.err)

        r = call("simpleStepForward")
        ok("simpleStepForward advances past camera parking frame", r.ok and r.result == CAMPARK + 1, r.err)

        r = call("getCameraFrames")
        found = false
        for _, f in ipairs((r.ok and r.result) or {}) do if f == CAMPARK then found = true end end
        ok("camera keyframe captured on step-forward", found)

        -- Cleanup — clears all rigs/props too, since the same step-forward
        -- call captured them alongside the camera.
        clearFrame(CAMPARK)
        call("setSimpleCamera", { on = false })
    end
end

-- ── Play/Stop toggle ──────────────────────────────────────────────────────────

do
    r = call("isPlaying")
    ok("isPlaying starts false", r.ok and r.result == false, r.err)

    -- startPlayback needs at least one recorded keyframe to play; the
    -- earlier tests clean up everything they capture, so a fresh session
    -- can reach this point with zero keyframes. Create one temporarily.
    local origFrame  = call("getCurrentFrame")
    local PLAYPARK   = math.max(1, frameCount - 61)   -- distinct from PARK/CAMPARK/CAMOBJPARK
    local madeTempKF = false
    if frameCount >= 70 and not frameOccupied(PLAYPARK) then
        call("setFrame", { frame = PLAYPARK })
        call("simpleStepForward")
        madeTempKF = true
    end

    call("setFrame", { frame = math.max(1, frameCount - 3) })

    r = call("simpleTogglePlay")
    if r.ok and r.result == true then
        ok("simpleTogglePlay starts playback", true)
        local stopped = false
        for _ = 1, 100 do
            task.wait(0.05)
            local p = call("isPlaying")
            if p.ok and p.result == false then stopped = true; break end
        end
        ok("playback reaches the end and auto-stops", stopped)
    else
        table.insert(out, "SKIP  play-to-end test (no recorded keyframes to play)")
    end

    -- Manual stop mid-playback.
    call("setFrame", { frame = 1 })
    r = call("simpleTogglePlay")
    if r.ok and r.result == true then
        task.wait(0.1)
        r = call("simpleTogglePlay")   -- toggle again = manual stop
        ok("manual simpleTogglePlay stops mid-playback", r.ok and r.result == false, r.err)
        r = call("isPlaying")
        ok("isPlaying false after manual stop", r.ok and r.result == false, r.err)
    else
        table.insert(out, "SKIP  manual-stop test (no recorded keyframes to play)")
    end

    if madeTempKF then clearFrame(PLAYPARK) end
    if origFrame.ok then call("setFrame", { frame = origFrame.result }) end
end

-- ── Manipulable camera object: creation, FOV, Look Through, capture ────────────

do
    local fig = workspace:FindFirstChild("FIGURES")

    -- Look Through is rejected while Camera View is off.
    call("setSimpleCamera", { on = false })
    r = call("setSimpleLookThrough", { on = true })
    ok("Look Through rejected when Camera View is off", r.ok and r.result == false, r.err)
    r = call("getSimpleLookThrough")
    ok("getSimpleLookThrough false after rejected request", r.ok and r.result == false, r.err)

    -- Turn Camera View on — creates (or reuses) the manipulable camera object.
    r = call("setSimpleCamera", { on = true })
    ok("setSimpleCamera on", r.ok and r.result == true, r.err)

    r = call("getSimpleCameraInfo")
    ok("getSimpleCameraInfo returns data once Camera View is on", r.ok and r.result ~= nil, r.err)

    local camPart = fig and fig:FindFirstChild("SimpleCamera")
    ok("SimpleCamera part exists in FIGURES", camPart ~= nil)

    r = call("setSimpleCameraFOV", { fov = 55 })
    ok("setSimpleCameraFOV sets fov", r.ok and r.result == 55, r.err)
    r = call("getSimpleCameraInfo")
    ok("getSimpleCameraInfo reflects new FOV", r.ok and r.result and math.abs(r.result.fov - 55) < 0.01, r.err)

    -- Look Through ON mirrors the gizmo onto the viewport; OFF restores it exactly.
    local cam = workspace.CurrentCamera
    local savedCF  = cam and cam.CFrame
    local savedFov = cam and cam.FieldOfView

    r = call("setSimpleLookThrough", { on = true })
    ok("setSimpleLookThrough on succeeds once Camera View is on", r.ok and r.result == true, r.err)
    r = call("getSimpleLookThrough")
    ok("getSimpleLookThrough true", r.ok and r.result == true, r.err)

    r = call("setSimpleLookThrough", { on = false })
    ok("setSimpleLookThrough off", r.ok and r.result == false, r.err)

    if cam and savedCF then
        local restored = (cam.CFrame.Position - savedCF.Position).Magnitude < 0.01
            and math.abs(cam.FieldOfView - savedFov) < 0.01
        ok("viewport restored exactly after Look Through off", restored)
    end

    -- Capture from the gizmo's own pose, not the ambient viewport.
    if camPart and frameCount >= 60 then
        local CAMOBJPARK = frameCount - 53   -- distinct from PARK (-31) / CAMPARK (-41)
        if not frameOccupied(CAMOBJPARK) then
            camPart.CFrame = camPart.CFrame * CFrame.new(7, 0, 0)
            call("setFrame", { frame = CAMOBJPARK })
            r = call("simpleStepForward")
            ok("step-forward captures camera object pose", r.ok and r.result == CAMOBJPARK + 1, r.err)

            r = call("getCameraFrames")
            found = false
            for _, f in ipairs((r.ok and r.result) or {}) do if f == CAMOBJPARK then found = true end end
            ok("camera keyframe recorded at parking frame", found)

            clearFrame(CAMOBJPARK)
        else
            table.insert(out, "SKIP  camera-object capture test (parking frame already holds user data)")
        end
    end

    call("setSimpleCamera", { on = false })
end

-- ── FIGURES auto-track / untrack of non-rig props in Simple mode ───────────────

do
    local fig = workspace:FindFirstChild("FIGURES")
    if not fig then
        table.insert(out, "SKIP  prop auto-track test (no workspace.FIGURES)")
    else
        local testPart = Instance.new("Part")
        testPart.Name = "__TestSimpleProp"
        testPart.Anchored = true
        testPart.Size = Vector3.new(1, 1, 1)
        testPart.CFrame = CFrame.new(0, 200, 0)   -- out of the way
        testPart.Parent = fig

        task.wait(0.2)   -- ChildAdded handler defers one frame

        r = call("getSimpleProps")
        found = false
        for _, n in ipairs((r.ok and r.result) or {}) do if n == "__TestSimpleProp" then found = true end end
        ok("non-rig FIGURES child auto-tracked as a prop in Simple mode", found, r.err)

        testPart:Destroy()
        task.wait(0.1)

        r = call("getSimpleProps")
        found = false
        for _, n in ipairs((r.ok and r.result) or {}) do if n == "__TestSimpleProp" then found = true end end
        ok("removed FIGURES child untracked", not found, r.err)
    end
end

-- ── Restore user state ────────────────────────────────────────────────────────

if prevFrame.ok then call("setFrame", { frame = prevFrame.result }) end
if prevActive.ok and prevActive.result[1] then
    call("setActiveRig", { name = prevActive.result[1] })
end
if prevMode.ok then call("setMode", { mode = prevMode.result }) end

if not preexistingSimpleCam then
    local fig = workspace:FindFirstChild("FIGURES")
    local camPart = fig and fig:FindFirstChild("SimpleCamera")
    if camPart then camPart:Destroy() end
end

return finish()
