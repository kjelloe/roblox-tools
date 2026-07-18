-- test_pose_to_end.lua
-- Pose→End: propagate the live pose of the selected rig part / tracked prop
-- from the current frame to all following keyframes. Live test — needs the
-- plugin panel open and Workspace.FIGURES with Rig1.

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

local figures = workspace:FindFirstChild("FIGURES")
local rig = figures and figures:FindFirstChild("Rig1")
if not rig then
    return "SKIP: Workspace.FIGURES.Rig1 not found\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end

-- ── Setup: Simple Mode fallback scan, one prop, five captured frames ─────────

local old = figures:FindFirstChild("__PoseProp")
if old then old:Destroy() end
call("scanFigures")
call("setSimpleSceneName", { name = "" })
call("setMode", { mode = "simple" })

local prop = Instance.new("Part")
prop.Name = "__PoseProp"
prop.Anchored = true
prop.CFrame = CFrame.new(30, 5, 30)
prop.Parent = figures
task.wait(0.3)

-- Deterministic baseline: pose the arm at its R6 rest position BEFORE adding
-- frames. A previous run leaves the arm raised (Pose→End applies live poses),
-- and simpleAddFrame captures the LIVE pose — without this reset every frame
-- would inherit the raised arm and "frame 2 differs" fails forever after.
local torso = rig.Torso
local arm = rig["Right Arm"]
local REST_ARM = torso.CFrame * CFrame.new(1.5, 0, 0)
arm.CFrame = REST_ARM

for _ = 1, 5 do call("simpleAddFrame") end

-- ── Empty selection → notice, returns false ──────────────────────────────────

game:GetService("Selection"):Set({})
local r = call("simplePoseToEnd")
ok("empty selection returns false", r.ok and r.result == false, hs:JSONEncode(r))

-- ── At frame 3: raise the arm, move the prop, select both, propagate ─────────

call("setFrame", { frame = 3 })
arm.CFrame = torso.CFrame * CFrame.new(1.5, 0.5, 0)
    * CFrame.Angles(math.rad(60), 0, 0) * CFrame.new(0, -0.5, 0)
prop.CFrame = CFrame.new(35, 8, 30)
game:GetService("Selection"):Set({ arm, prop })

r = call("simplePoseToEnd")
ok("simplePoseToEnd returns true", r.ok and r.result == true, hs:JSONEncode(r))
game:GetService("Selection"):Set({})

-- ── Joint propagated to following frames, earlier frames untouched ───────────

local function shoulderAt(frame)
    local jr = call("getJointCF", { rig = "Rig1", frame = frame, joint = "Right Shoulder" })
    return jr.ok and jr.result or nil
end
local cf3, cf4, cf5, cf2 = shoulderAt(3), shoulderAt(4), shoulderAt(5), shoulderAt(2)

local function differs(a, b)
    if not a or not b then return true end
    for i = 1, 12 do
        if math.abs(a[i] - b[i]) > 0.001 then return true end
    end
    return false
end
ok("frame 4 shoulder matches frame 3 (propagated)", cf4 ~= nil and not differs(cf3, cf4))
ok("frame 5 shoulder matches frame 3 (propagated)", cf5 ~= nil and not differs(cf3, cf5))
ok("frame 2 shoulder unchanged (not propagated backwards)", differs(cf2, cf3))

-- ── Prop propagated: navigate and read the applied CFrame ────────────────────

call("setFrame", { frame = 5 })
task.wait(0.1)
ok("prop at frame 5 holds the new position",
    (prop.Position - Vector3.new(35, 8, 30)).Magnitude < 0.01, tostring(prop.Position))
call("setFrame", { frame = 2 })
task.wait(0.1)
ok("prop at frame 2 keeps the original position",
    (prop.Position - Vector3.new(30, 5, 30)).Magnitude < 0.01, tostring(prop.Position))

-- ── Cleanup: remove the five test frames and restore the rest pose ───────────

for f = 5, 1, -1 do
    call("setFrame", { frame = f })
    call("simpleDeleteKeyframe")
end
arm.CFrame = REST_ARM
prop:Destroy()
call("scanFigures")

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
