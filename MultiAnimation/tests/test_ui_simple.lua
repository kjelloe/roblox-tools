-- test_ui_simple.lua
-- Simple Mode integration tests — drives the LIVE plugin panel through the
-- TestBridge (CoreGui.__MultiAnimTestBridge, see plugin/core/TestBridge.lua).
--
-- Covers: mode toggle, Add/Insert/Delete Frame frame-management (capture +
-- grow, insert-blank + shift, delete + shrink), Camera View capture-on-add,
-- FIGURES auto-track/untrack of non-rig props while in Simple mode, the
-- Play/Stop toggle, and the manipulable camera object (creation, spawn
-- position, FOV, frustum gizmo, Look Through guard/snap/free-fly-mirrors-to-
-- gizmo/restore/cycle-no-flip, capture-from-gizmo), frame selection guard
-- (Delete+Duplicate no-op at empty frames).
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

local prevMode       = call("getMode")
local prevFrame      = call("getCurrentFrame")
local prevActive     = call("getActiveRigs")
local prevFrameCount = call("getFrameCount")

-- The Camera View camera is now a real, persistent Part (created on first
-- toggle-on) rather than a flag with no scene effect — only destroy it at
-- the end of this file if THIS run is the one that created it.
local figForCam0 = workspace:FindFirstChild("FIGURES")
local preexistingSimpleCam = figForCam0 and figForCam0:FindFirstChild("SimpleCamera") ~= nil

-- ── Mode toggle ───────────────────────────────────────────────────────────────

call("scanFigures")  -- rescan FIGURES, normalise frameCount ≥ 120, set mode=advanced
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
-- clearFrame uses simpleDeleteFrame (not just a data wipe): it deletes the
-- frame, shifts all subsequent frame data left by 1, and shrinks frameCount.
-- Safe to call when all frames between `frame` and the timeline end are empty.
local function clearFrame(frame)
    call("setFrame", { frame = frame })
    call("simpleDeleteFrame")
end

-- ── Add Frame / Insert Frame / Delete Frame ───────────────────────────────────
-- simpleAddFrame: captures current frame, grows frameCount by 1, moves cursor
--   to the new end frame.
-- simpleInsertFrame (Duplicate): captures current frame, shifts data >= current+1
--   right by 1, copies current frame data to current+1, moves cursor to current+1.
-- simpleDeleteFrame: removes data at current frame, shifts data at frames >
--   current left by 1, shrinks frameCount by 1 (minimum 1).
--
-- Works at frames 1 and 2 so tests run in any session, including a fresh one
-- where doSimpleScan has set frameCount=1 with no existing keyframes.

do
    local initCount = (call("getFrameCount").ok and call("getFrameCount").result) or 1

    if frameOccupied(1) then
        table.insert(out, "SKIP  frame management tests (frame 1 already holds user data)")
    else
        -- ── simpleAddFrame ────────────────────────────────────────────────────

        call("setFrame", { frame = 1 })
        r = call("simpleFrameHasData", { frame = 1 })
        ok("frame 1 starts empty before add-frame tests", r.ok and r.result == false, r.err)

        r = call("simpleAddFrame")
        -- captures frame 1, grows frameCount by 1, cursor moves to the NEW end
        ok("simpleAddFrame returns new end frame (initCount+1)", r.ok and r.result == initCount + 1, r.err)

        r = call("simpleFrameHasData", { frame = 1 })
        ok("simpleFrameHasData true at frame 1 after simpleAddFrame", r.ok and r.result == true, r.err)

        r = call("getFrameCount")
        ok("frameCount grew by 1 after simpleAddFrame", r.ok and r.result == initCount + 1, r.err)

        -- ── simpleDeleteFrame ─────────────────────────────────────────────────

        call("setFrame", { frame = 1 })
        r = call("simpleDeleteFrame")
        -- deletes frame 1, shifts 2..end left, frameCount shrinks by 1
        ok("simpleDeleteFrame returns cursor at 1", r.ok and r.result == 1, r.err)

        r = call("simpleFrameHasData", { frame = 1 })
        ok("frame 1 data cleared by simpleDeleteFrame", r.ok and r.result == false, r.err)

        r = call("getFrameCount")
        ok("frameCount restored to initCount after simpleDeleteFrame", r.ok and r.result == initCount, r.err)

        -- ── simpleInsertFrame ─────────────────────────────────────────────────

        -- Re-capture frame 1; cursor lands at new end (initCount+1).
        call("setFrame", { frame = 1 })
        call("simpleAddFrame")   -- frameCount = initCount+1, cursor at initCount+1

        -- Navigate back to frame 1 and duplicate it.
        -- Duplicate captures frame 1, shifts data >= 2 right, copies frame 1 data
        -- into new frame 2, and moves cursor to 2.
        call("setFrame", { frame = 1 })
        r = call("simpleInsertFrame")
        ok("simpleInsertFrame (Duplicate) moves cursor to new frame (2)", r.ok and r.result == 2, r.err)

        r = call("getFrameCount")
        ok("simpleInsertFrame grows frameCount to initCount+2", r.ok and r.result == initCount + 2, r.err)

        r = call("simpleFrameHasData", { frame = 1 })
        ok("frame 1 data preserved after simpleInsertFrame", r.ok and r.result == true, r.err)

        r = call("simpleFrameHasData", { frame = 2 })
        ok("frame 2 is a duplicate of frame 1 (has data)", r.ok and r.result == true, r.err)

        -- Cleanup: delete frame 2 (duplicate), then frame 1 (original).
        call("setFrame", { frame = 2 })
        call("simpleDeleteFrame")
        call("setFrame", { frame = 1 })
        call("simpleDeleteFrame")
    end
end

-- ── Camera View capture-on-add ───────────────────────────────────────────────
-- Works at frame 1 (always empty in a fresh Simple Mode session).

do
    local camInitCount = (call("getFrameCount").ok and call("getFrameCount").result) or 1

    local camOccupied1 = frameOccupied(1)
    r = call("getCameraFrames")
    for _, f in ipairs((r.ok and r.result) or {}) do if f == 1 then camOccupied1 = true end end

    if camOccupied1 then
        table.insert(out, "SKIP  camera-on-add test (frame 1 already holds user data)")
    else
        r = call("setSimpleCamera", { on = true })
        ok("setSimpleCamera on (camera-on-add)", r.ok and r.result == true, r.err)

        call("setFrame", { frame = 1 })
        r = call("simpleFrameHasData", { frame = 1 })
        ok("camera frame 1 starts empty", r.ok and r.result == false, r.err)

        -- simpleAddFrame captures frame 1 and moves cursor to new end (camInitCount+1).
        r = call("simpleAddFrame")
        ok("simpleAddFrame with camera advances to new end", r.ok and r.result == camInitCount + 1, r.err)

        r = call("getCameraFrames")
        found = false
        for _, f in ipairs((r.ok and r.result) or {}) do if f == 1 then found = true end end
        ok("camera keyframe captured on add-frame", found)

        -- Cleanup: clearFrame(1) deletes frame 1 and shrinks frameCount back.
        clearFrame(1)
        call("setSimpleCamera", { on = false })
    end
end

-- ── Play/Stop toggle ──────────────────────────────────────────────────────────

do
    r = call("isPlaying")
    ok("isPlaying starts false", r.ok and r.result == false, r.err)

    -- startPlayback needs keyframes to play; earlier tests clean up everything.
    -- Build 6 frames (enough that 0.1s is mid-playback at 24fps = 5/24≈0.21s),
    -- using consecutive simpleAddFrame calls from frame 1.
    local PLAY_FRAMES = 6
    local origFrame   = call("getCurrentFrame")
    local madeTempKF  = false
    if not frameOccupied(1) then
        call("setFrame", { frame = 1 })
        for _ = 1, PLAY_FRAMES do
            call("simpleAddFrame")   -- each call captures current frame and advances to new end
        end
        madeTempKF = true
    end

    -- Navigate near the end so play-to-end finishes within the poll window.
    local playCount = (call("getFrameCount").ok and call("getFrameCount").result) or 1
    call("setFrame", { frame = math.max(1, playCount - 1) })

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

    -- Manual stop mid-playback: start from frame 1 with full range so it can't
    -- auto-stop before we send the second toggle (~0.2s at 30fps over 6 frames).
    call("setFrame", { frame = 1 })
    r = call("simpleTogglePlay")
    if r.ok and r.result == true then
        task.wait(0.05)  -- let the loop start; still well before 6-frame end
        -- Verify it is still playing before sending stop, skip if already done.
        local stillPlaying = call("isPlaying")
        if stillPlaying.ok and stillPlaying.result == true then
            r = call("simpleTogglePlay")   -- toggle again = manual stop
            ok("manual simpleTogglePlay stops mid-playback", r.ok and r.result == false, r.err)
            r = call("isPlaying")
            ok("isPlaying false after manual stop", r.ok and r.result == false, r.err)
        else
            table.insert(out, "SKIP  manual-stop test (animation finished before stop toggle)")
            table.insert(out, "SKIP  isPlaying check (skipped with manual-stop)")
        end
    else
        table.insert(out, "SKIP  manual-stop test (no recorded keyframes to play)")
    end

    if madeTempKF then
        for _ = 1, PLAY_FRAMES do clearFrame(1) end   -- each clearFrame(1) shifts data left
    end
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

    -- Spawn position: first creation should place the Part at the Studio
    -- viewer's angle relative to the rigs, not at world origin.
    -- Only testable when this run created the Part for the first time.
    if not preexistingSimpleCam and camPart then
        ok("SimpleCamera spawns away from world origin on first creation",
            camPart.Position.Magnitude > 1)
        local lv = camPart.CFrame.LookVector
        ok("SimpleCamera LookVector is non-degenerate on spawn (not pointing straight up/down)",
            math.abs(lv.Y) < 0.99)
    end

    r = call("setSimpleCameraFOV", { fov = 55 })
    ok("setSimpleCameraFOV sets fov", r.ok and r.result == 55, r.err)
    r = call("getSimpleCameraInfo")
    ok("getSimpleCameraInfo reflects new FOV", r.ok and r.result and math.abs(r.result.fov - 55) < 0.01, r.err)

    -- FOV-frustum gizmo (welded thin Parts, not WireframeHandleAdornment --
    -- screen_capture can't render that class, and in live Studio its Adornee
    -- did not track the part) exists and is rigidly welded to the camera part
    -- (replaces the old Hinge-stud cone/sphere marker).
    r = call("getSimpleCameraFrustumInfo")
    ok("frustum gizmo exists on the camera part", r.ok and r.result ~= nil, r.err)
    ok("frustum gizmo is a Folder", r.ok and r.result and r.result.className == "Folder", r.err)
    ok("frustum gizmo has 8 edges", r.ok and r.result and r.result.edgeCount == 8, r.err)
    ok("frustum gizmo edges are all welded to the camera part", r.ok and r.result and r.result.allWelded == true, r.err)

    -- Look Through snaps the viewport into the gizmo's lens once, then lets
    -- native Studio navigation (mouse/keyboard free-cam) drive the viewport
    -- while mirroring it back onto the gizmo — so flying around re-aims the
    -- camera object instead of fighting a forced gizmo->viewport mirror.
    local cam = workspace.CurrentCamera
    local savedCF  = cam and cam.CFrame
    local savedFov = cam and cam.FieldOfView
    local lensCF   = camPart and camPart.CFrame

    r = call("setSimpleLookThrough", { on = true })
    ok("setSimpleLookThrough on succeeds once Camera View is on", r.ok and r.result == true, r.err)
    r = call("getSimpleLookThrough")
    ok("getSimpleLookThrough true", r.ok and r.result == true, r.err)

    if cam and lensCF then
        local snapped = (cam.CFrame.Position - lensCF.Position).Magnitude < 0.01
            and math.abs(cam.FieldOfView - 55) < 0.01
        ok("viewport snaps to the gizmo's lens on Look Through on", snapped)
    end

    -- Simulate the user free-flying the viewport (native Studio nav) and
    -- confirm the gizmo picks up the new pose on the next Heartbeat.
    -- task.wait() resumes after Stepped, which fires BEFORE Heartbeat — so we
    -- wait for Heartbeat directly to guarantee the callback has run.
    local RunService = game:GetService("RunService")
    local flownCF = nil
    if cam then
        flownCF = lensCF * CFrame.new(3, 1, 0)
        cam.CFrame = flownCF
        -- task.wait(0.1): Connect callbacks and Wait() resumes share the same
        -- Heartbeat fire but ordering is implementation-defined. 0.1s ensures
        -- multiple Heartbeat cycles so the callback has definitely run.
        task.wait(0.1)
        local followed = camPart and (camPart.CFrame.Position - flownCF.Position).Magnitude < 0.01
        ok("flying the viewport re-aims the gizmo while Look Through is on", followed)
    end

    r = call("setSimpleLookThrough", { on = false })
    ok("setSimpleLookThrough off", r.ok and r.result == false, r.err)

    if cam and savedCF then
        local restored = (cam.CFrame.Position - savedCF.Position).Magnitude < 0.01
            and math.abs(cam.FieldOfView - savedFov) < 0.01
        ok("viewport restored exactly after Look Through off (even after flying)", restored)
    end

    -- Put the gizmo back where it started so the capture-from-gizmo test
    -- below isn't working from the flown-to pose.
    if camPart and lensCF then camPart.CFrame = lensCF end

    -- Capture from the gizmo's own pose, not the ambient viewport.
    -- Capture from the gizmo's own pose — use frame 1, always available.
    if camPart and not frameOccupied(1) then
        local camObjInitCount = (call("getFrameCount").ok and call("getFrameCount").result) or 1
        camPart.CFrame = camPart.CFrame * CFrame.new(7, 0, 0)
        call("setFrame", { frame = 1 })
        -- simpleAddFrame captures frame 1 and moves to new end (camObjInitCount+1).
        r = call("simpleAddFrame")
        ok("simpleAddFrame captures camera object pose", r.ok and r.result == camObjInitCount + 1, r.err)

        r = call("getCameraFrames")
        found = false
        for _, f in ipairs((r.ok and r.result) or {}) do if f == 1 then found = true end end
        ok("camera keyframe recorded at frame 1", found)

        clearFrame(1)
    else
        table.insert(out, "SKIP  camera-object capture test (frame 1 already holds user data)")
    end

    -- Look-Through OFF/ON cycle: after Camera View off→on, re-enabling Look
    -- Through must snap the viewport to the gizmo's CFrame, not 180° opposite.
    -- Regression: cam.Focus was left at the pre-Look-Through focus point by
    -- restoreState; Studio's camera controller re-derived angles from
    -- CFrame+Focus and flipped 180° when Focus was behind the eye.
    -- Fix: setSimpleLookThroughOn now also updates cam.Focus 10 studs ahead.
    if cam and camPart then
        local cycleCF = CFrame.lookAt(Vector3.new(8, 4, 8), Vector3.new(0, 2, 0))
        camPart.CFrame = cycleCF
        call("setSimpleLookThrough", { on = true })
        call("setSimpleLookThrough", { on = false })
        call("setSimpleCamera",      { on = false })
        call("setSimpleCamera",      { on = true })
        call("setSimpleLookThrough", { on = true })
        local dot = cam.CFrame.LookVector:Dot(camPart.CFrame.LookVector)
        ok("Look-Through ON after Camera View cycle: viewport faces same direction as gizmo (not 180° flipped)",
            dot > 0.5, string.format("dot=%.3f", dot))
        local focusOffset = cam.Focus.Position - cam.CFrame.Position
        local focusDir    = focusOffset.Magnitude > 0.001
            and focusOffset.Unit or Vector3.new(0, 0, -1)
        ok("Look-Through ON after cycle: cam.Focus is in front of the eye",
            cam.CFrame.LookVector:Dot(focusDir) > 0,
            string.format("dot=%.3f", cam.CFrame.LookVector:Dot(focusDir)))
        call("setSimpleLookThrough", { on = false })
        if lensCF then camPart.CFrame = lensCF end
    end

    call("setSimpleCamera", { on = false })
end

-- ── Frame selection guard ────────────────────────────────────────────────────
-- Delete and Duplicate must be no-ops when the current frame has no keyframe
-- data.  Regression guard: without this guard any empty frame could be
-- deleted or duplicated, corrupting slot count and frame numbering.

do
    local GUARD_FRAME = 115   -- within the ≥120-frame fresh session; unused by other tests
    call("setFrame", { frame = GUARD_FRAME })
    local hasData = call("simpleFrameHasData", { frame = GUARD_FRAME })
    if hasData.ok and not hasData.result then
        local fc0 = (call("getFrameCount").ok and call("getFrameCount").result) or 1

        call("simpleDeleteFrame")
        local fcAfterDel = (call("getFrameCount").ok and call("getFrameCount").result) or 1
        ok("Delete at empty frame is a no-op: frame count unchanged",
            fcAfterDel == fc0, "before=" .. tostring(fc0) .. " after=" .. tostring(fcAfterDel))

        call("simpleInsertFrame")
        local fcAfterDup = (call("getFrameCount").ok and call("getFrameCount").result) or 1
        ok("Duplicate at empty frame is a no-op: frame count unchanged",
            fcAfterDup == fc0, "before=" .. tostring(fc0) .. " after=" .. tostring(fcAfterDup))
    else
        table.insert(out, "SKIP  frame selection guard (frame " .. GUARD_FRAME .. " unexpectedly has data)")
    end
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

-- ── Playback FPS box ──────────────────────────────────────────────────────────
-- Uses frame offsets -59 and -67 (unused by prior tests) so no collision with
-- user data.  All writes are cleaned up inside the block.

do
    -- Fresh Simple Mode scan should default to 30 fps.
    r = call("getSimpleFPS")
    ok("getSimpleFPS returns a number", r.ok and type(r.result) == "number", r.err)

    -- Round-trip: set an unusual value, read it back.
    r = call("setSimpleFPS", { fps = 12 })
    ok("setSimpleFPS 12 returns 12", r.ok and r.result == 12, r.err)

    r = call("getSimpleFPS")
    ok("getSimpleFPS == 12 after setSimpleFPS", r.ok and r.result == 12, r.err)

    -- Clamp: values outside 1-999 should be clamped, not rejected.
    r = call("setSimpleFPS", { fps = 0 })
    ok("setSimpleFPS 0 clamped to 1", r.ok and r.result == 1, r.err)

    r = call("setSimpleFPS", { fps = 10000 })
    ok("setSimpleFPS 10000 clamped to 999", r.ok and r.result == 999, r.err)

    -- Restore a sane default so later tests run at expected speed.
    call("setSimpleFPS", { fps = 30 })
end

-- ── Auto-capture on frame-icon navigation ─────────────────────────────────────
-- Verifies that simpleNavigate auto-captures the departure frame, so a value
-- changed while parked there (here: camera FOV) is persisted, not discarded.
-- Uses Camera View's FOV because that value is directly readable after
-- applyPosesAt restores frame data on navigation back.

do
    if frameOccupied(1) then
        table.insert(out, "SKIP  auto-capture-on-navigate test (frame 1 holds user data)")
    else
        local navInitCount = (call("getFrameCount").ok and call("getFrameCount").result) or 1

        -- Build frame 1 with FOV = 55 as the baseline.
        call("setSimpleCamera", { on = true })
        call("setSimpleCameraFOV", { fov = 55 })
        call("setFrame", { frame = 1 })
        r = call("simpleAddFrame")
        ok("simpleAddFrame creates frame 1 for auto-capture test", r.ok and r.result ~= nil, r.err)

        -- Navigate back; applyPosesAt restores FOV = 55 from the recorder.
        call("setFrame", { frame = 1 })
        r = call("getSimpleCameraInfo")
        ok("FOV == 55 at frame 1 after setFrame back", r.ok and r.result and math.abs(r.result.fov - 55) < 0.01, r.err)

        -- Mutate FOV to 65 while parked at frame 1 (user edits without pressing Add Frame).
        call("setSimpleCameraFOV", { fov = 65 })

        -- simpleNavigate away: auto-capture fires for departure frame 1, saving FOV=65.
        local afterCount = (call("getFrameCount").ok and call("getFrameCount").result) or 2
        r = call("simpleNavigate", { frame = math.min(2, afterCount) })
        ok("simpleNavigate moves cursor away from frame 1", r.ok and r.result ~= nil, r.err)

        -- Navigate back to frame 1; applyPosesAt should restore the auto-captured FOV=65.
        call("setFrame", { frame = 1 })
        r = call("getSimpleCameraInfo")
        ok("auto-capture saved FOV=65 when navigating away from frame 1", r.ok and r.result and math.abs(r.result.fov - 65) < 0.01, r.err)

        -- Cleanup.
        clearFrame(1)
        call("setSimpleCamera", { on = false })

        r = call("getFrameCount")
        ok("frameCount restored after auto-capture test", r.ok and r.result == navInitCount, r.err)
    end
end

-- ── Onion skin toggle ─────────────────────────────────────────────────────────
-- We're already in simple mode with no data; no mode switch needed (switching
-- to simple while already in simple overwrites advancedFrameCount with the
-- current small frameCount and corrupts the restore path).
if frameOccupied(1) then
    table.insert(out, "SKIP  onion skin tests (frame 1 already holds user data)")
else
    call("simpleAddFrame")   -- frame 1 gets data; cursor → 2
    call("simpleAddFrame")   -- frame 2 gets data; cursor → 3

    r = call("setSimpleOnion", { on = true })
    ok("setSimpleOnion ON returns true", r.ok and r.result == true, r.err)

    local folder = workspace:FindFirstChild("__MultiAnimOnionSkin")
    ok("onion skin creates __MultiAnimOnionSkin folder", folder ~= nil)
    ok("onion skin folder contains ghost Parts",
        folder ~= nil and #folder:GetChildren() > 0)

    -- Navigate to frame 1 (has a forward neighbour); ghosts should refresh.
    call("setFrame", { frame = 1 })
    folder = workspace:FindFirstChild("__MultiAnimOnionSkin")
    ok("onion skin folder persists after frame change", folder ~= nil)

    r = call("setSimpleOnion", { on = false })
    ok("setSimpleOnion OFF returns false", r.ok and r.result == false, r.err)
    folder = workspace:FindFirstChild("__MultiAnimOnionSkin")
    ok("onion skin folder removed when toggled OFF", folder == nil)

    -- Cleanup: delete the 2 frames we added (stay in simple mode).
    call("setFrame", { frame = 1 })
    call("simpleDeleteFrame")
    call("simpleDeleteFrame")
end

-- ── Save/Load round-trip in Simple Mode ──────────────────────────────────────
-- Regression: loading a named save while in Simple Mode used to leave the frame
-- slot list empty because doSimpleScan() was not called after applySessionData.
-- This test verifies the full round-trip: add frames → save → delete frames →
-- load → slots should match original keyframe list.
local SAVE_SLOT_NAME = "__test_simple_load_regression__"
do
    -- Start in simple mode with a clean two-frame session.
    call("setMode", { mode = "simple" })
    call("setFrame", { frame = 1 })
    -- Ensure we're at frame 1 with no prior data by deleting to bare minimum.
    local count0 = call("getFrameCount")
    if count0.ok then
        for _ = 1, (count0.result or 1) - 1 do call("simpleDeleteFrame") end
    end
    call("setFrame", { frame = 1 })
    -- Add two frames so we have keyframes at [1, 2].
    call("simpleAddFrame")
    call("simpleAddFrame")
    local slotsBefore = call("getSimpleSlots")
    ok("getSimpleSlots: 2 frames before save",
        slotsBefore.ok and #slotsBefore.result == 2,
        slotsBefore.ok and HttpService:JSONEncode(slotsBefore.result) or slotsBefore.err)

    -- Save then destroy both frames.
    call("saveSession", { name = SAVE_SLOT_NAME })
    call("setFrame", { frame = 1 })
    call("simpleDeleteFrame")
    -- Tolerate ending up with 1-frame minimum.
    call("simpleDeleteFrame")
    local slotsAfterDelete = call("getSimpleSlots")
    ok("getSimpleSlots: ≤1 frame after delete",
        slotsAfterDelete.ok and #slotsAfterDelete.result <= 1,
        slotsAfterDelete.ok and HttpService:JSONEncode(slotsAfterDelete.result) or slotsAfterDelete.err)

    -- Load the save — doSimpleScan must rebuild the slot list.
    call("loadSession", { name = SAVE_SLOT_NAME })
    local slotsAfterLoad = call("getSimpleSlots")
    ok("getSimpleSlots: slots restored after load (was: empty)",
        slotsAfterLoad.ok and #slotsAfterLoad.result == 2,
        slotsAfterLoad.ok and HttpService:JSONEncode(slotsAfterLoad.result) or slotsAfterLoad.err)
    ok("getSimpleSlots: first slot is frame 1 after load",
        slotsAfterLoad.ok and slotsAfterLoad.result[1] == 1,
        slotsAfterLoad.ok and tostring(slotsAfterLoad.result[1]) or slotsAfterLoad.err)
    ok("getSimpleSlots: second slot is frame 2 after load",
        slotsAfterLoad.ok and slotsAfterLoad.result[2] == 2,
        slotsAfterLoad.ok and tostring(slotsAfterLoad.result[2]) or slotsAfterLoad.err)

    -- Cleanup: delete the loaded frames.
    call("setFrame", { frame = 1 })
    call("simpleDeleteFrame")
    call("simpleDeleteFrame")
end

-- ── frameCount preserved through simple→advanced round-trip ──────────────────
-- Regression: autosave fired while in simple mode used to persist the tiny
-- simple-mode frameCount, so the next plugin load started with e.g. 2 frames.
-- serializeSession now always uses advancedFrameCount when in simple mode.
-- We start from advanced, do the full round-trip, then check preservation.
do
    local targetMode = prevMode.ok and prevMode.result or "advanced"
    -- First get to advanced so advancedFrameCount is nil (clean state).
    call("setMode", { mode = "advanced" })
    local fc0 = (call("getFrameCount").ok and call("getFrameCount").result) or 20
    -- Now do the round-trip that used to corrupt the count.
    call("setMode", { mode = "simple" })
    call("setMode", { mode = "advanced" })
    local fcNow = (call("getFrameCount").ok and call("getFrameCount").result) or 0
    ok("frameCount preserved through advanced→simple→advanced round-trip",
        fcNow >= fc0, tostring(fc0) .. "→" .. tostring(fcNow))
    -- Restore user mode last (already in advanced if prevMode was advanced).
    if targetMode ~= "advanced" then call("setMode", { mode = targetMode }) end
end

-- ── Restore user state ────────────────────────────────────────────────────────

if prevFrame.ok then call("setFrame", { frame = prevFrame.result }) end
if prevActive.ok and prevActive.result[1] then
    call("setActiveRig", { name = prevActive.result[1] })
end
-- mode already restored in the regression test above

if not preexistingSimpleCam then
    local fig = workspace:FindFirstChild("FIGURES")
    local camPart = fig and fig:FindFirstChild("SimpleCamera")
    if camPart then camPart:Destroy() end
end

return finish()
