-- test_prop_attach.lua
-- Prop attachment (authoring aid): attachProp/detachProp/getPropAttachments
-- bridge commands and the Heartbeat follow loop. Live test — needs the plugin
-- panel open and Workspace.FIGURES present.

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
    return "SKIP: __MultiAnimTestBridge not found (plugin panel not open)\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end
local function call(cmd, args)
    return hs:JSONDecode(bf:Invoke(cmd, args and hs:JSONEncode(args) or nil))
end

local figures = workspace:FindFirstChild("FIGURES")
if not figures then
    return "SKIP: Workspace.FIGURES not found\n=== 0 passed, 0 failed ===\nALL TESTS PASSED"
end

-- ── Setup: enter Simple Mode first — the live ChildAdded watcher auto-tracks
-- non-rig FIGURES children as props (the initial fallback scan does not).

for _, n in ipairs({ "__AttachProp", "__AttachTarget" }) do
    local old = figures:FindFirstChild(n)
    if old then old:Destroy() end
end
call("scanFigures")
call("setSimpleSceneName", { name = "" })
call("setMode", { mode = "simple" })

local propPart = Instance.new("Part")
propPart.Name = "__AttachProp"
propPart.Anchored = true
propPart.CFrame = CFrame.new(10, 5, 10)
propPart.Parent = figures
local targetPart = Instance.new("Part")
targetPart.Name = "__AttachTarget"
targetPart.Anchored = true
targetPart.CFrame = CFrame.new(20, 5, 20)
targetPart.Parent = figures
task.wait(0.3)   -- ChildAdded handler defers one frame

local props = call("getSimpleProps")
local seen = {}
for _, n in ipairs(props.ok and props.result or {}) do seen[n] = true end
ok("both parts auto-tracked as props", seen["__AttachProp"] and seen["__AttachTarget"],
    hs:JSONEncode(props.result or {}))

-- ── Attach ────────────────────────────────────────────────────────────────────

local r = call("attachProp", { prop = "__AttachProp", part = "Workspace.FIGURES.__AttachTarget" })
ok("attachProp returns true", r.ok and r.result == true, hs:JSONEncode(r))

r = call("getPropAttachments")
ok("getPropAttachments lists the attachment",
    r.ok and #r.result == 1 and r.result[1].prop == "__AttachProp", hs:JSONEncode(r))

-- Offset frozen at attach time: prop is at (10,5,10), target at (20,5,20).
targetPart.CFrame = CFrame.new(25, 5, 20)   -- move target +5 X
task.wait(0.3)                              -- let the follow heartbeat run
ok("prop follows target translation (offset preserved)",
    (propPart.Position - Vector3.new(15, 5, 10)).Magnitude < 0.01,
    tostring(propPart.Position))

targetPart.CFrame = CFrame.new(25, 5, 20) * CFrame.Angles(0, math.rad(90), 0)
task.wait(0.3)
ok("prop follows target rotation (rides the frame)",
    (propPart.Position - Vector3.new(15, 5, 30)).Magnitude < 0.01,
    tostring(propPart.Position))

-- ── Detach ────────────────────────────────────────────────────────────────────

r = call("detachProp", { prop = "__AttachProp" })
ok("detachProp returns true", r.ok and r.result == true, hs:JSONEncode(r))

local before = propPart.Position
targetPart.CFrame = CFrame.new(40, 5, 40)
task.wait(0.3)
ok("prop stays put after detach", (propPart.Position - before).Magnitude < 0.01,
    tostring(propPart.Position))

r = call("getPropAttachments")
ok("attachment list empty after detach", r.ok and #r.result == 0, hs:JSONEncode(r))

-- ── Guards ────────────────────────────────────────────────────────────────────

r = call("attachProp", { prop = "__NoSuchProp", part = "Workspace.FIGURES.__AttachTarget" })
ok("attach unknown prop rejected", r.ok and r.result == false, hs:JSONEncode(r))

r = call("attachProp", { prop = "__AttachProp", part = "Workspace.FIGURES.__AttachProp" })
ok("attach prop to itself rejected", r.ok and r.result == false, hs:JSONEncode(r))

r = call("detachProp", { prop = "__AttachProp" })
ok("detach when not attached returns false", r.ok and r.result == false, hs:JSONEncode(r))

-- ── Cleanup ───────────────────────────────────────────────────────────────────

propPart:Destroy()
targetPart:Destroy()
call("scanFigures")   -- restore standard test-isolation state

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
