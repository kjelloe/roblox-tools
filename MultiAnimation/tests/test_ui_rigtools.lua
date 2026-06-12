-- test_ui_rigtools.lua
-- Phase 9 UI integration via the TestBridge: "+ Add Rig" and the keyframe
-- clipboard (copy / paste / paste-mirrored). Cleans up everything it creates.

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

local function approx(a, b) return math.abs(a - b) < 0.001 end

local function mirrorComponents(c)
    -- (x,y,z, r00..r22) reflected across the YZ plane — must match the plugin.
    return { -c[1], c[2], c[3],
             c[4], -c[5], -c[6],
            -c[7],  c[8],  c[9],
            -c[10], c[11], c[12] }
end

local prevFrame = call("getCurrentFrame")

-- Pasting triggers applyPosesAt, which moves REAL rig parts in the viewport.
-- Snapshot every part CFrame up front and restore on exit, or the rigs are
-- left posed and later tests (rest-pose checks) fail.
local partSnapshots = {}
local function snapshotRigs()
    for _, model in ipairs(workspace.FIGURES:GetChildren()) do
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                partSnapshots[p] = p.CFrame
            end
        end
    end
end
local function restoreRigs()
    for p, cf in pairs(partSnapshots) do
        if p.Parent then p.CFrame = cf end
    end
end
snapshotRigs()

-- ── + Add Rig ─────────────────────────────────────────────────────────────────

local r = call("getRigs")
local rigsBefore = (r.ok and r.result) or {}
ok("at least 2 rigs to start", #rigsBefore >= 2)

r = call("addRig")
ok("addRig returns a name", r.ok and type(r.result) == "string", r.err)
local newRig = r.ok and r.result

if newRig then
    ok("name follows RigN pattern", newRig:match("^Rig%d+$") ~= nil, newRig)

    local model = workspace.FIGURES:FindFirstChild(newRig)
    ok("clone exists in FIGURES", model ~= nil)

    task.wait(0.2)   -- let the deferred auto-detect run
    r = call("getRigs")
    local detected = false
    for _, n in ipairs((r.ok and r.result) or {}) do
        if n == newRig then detected = true end
    end
    ok("plugin auto-detected the new rig", detected)

    -- Cleanup: remove the clone; ChildRemoved untracks it.
    if model then model:Destroy() end
    task.wait(0.1)
    r = call("getRigs")
    ok("rig count restored after cleanup", r.ok and #r.result == #rigsBefore,
        r.ok and #r.result or r.err)
end

-- ── Keyframe clipboard: copy / paste / mirror ─────────────────────────────────

r = call("getRigs")
local rigs = (r.ok and r.result) or {}
local rigA, rigB = rigs[1], rigs[2]
if not (rigA and rigB and rigA ~= rigB) then
    table.insert(out, "SKIP  clipboard tests (need two rigs)")
    return finish()
end

r = call("getFrameCount")
local frameCount = (r.ok and r.result) or 120
local PARK = frameCount - 17

-- Skip rather than clobber if the parking frame holds user data.
local occupied = false
for _, rig in ipairs({ rigA, rigB }) do
    r = call("getFrames", { rig = rig })
    for _, f in ipairs((r.ok and r.result) or {}) do
        if f == PARK then occupied = true end
    end
end
if occupied then
    table.insert(out, "SKIP  clipboard tests (frame " .. PARK .. " has user data)")
    return finish()
end

-- Empty-clipboard paste is rejected cleanly (clipboard may hold older session
-- data, so only assert when it reports empty).
r = call("getClipboard")
if r.ok and r.result == nil then
    r = call("pasteKeyframe", { mirrored = false })
    ok("paste with empty clipboard returns false", r.ok and r.result == false, r.err)
end

-- Record a source keyframe on rigA and give it a distinctive right-shoulder pose.
call("setActiveRig", { name = rigA })
call("setFrame", { frame = PARK })
r = call("addKeyframe")
ok("source keyframe recorded on " .. rigA, r.ok, r.err)

local poseCF = CFrame.new(0.4, 0.15, -0.2) * CFrame.Angles(0.7, 0.35, -0.5)
local poseComponents = { poseCF:GetComponents() }
r = call("setJointCF", { rig = rigA, frame = PARK, joint = "Right Shoulder", cf = poseComponents })
ok("distinctive Right Shoulder pose injected", r.ok and r.result == true, r.err)

-- Copy
r = call("copyKeyframe")
ok("copyKeyframe succeeds", r.ok and r.result == true, r.err)
r = call("getClipboard")
ok("clipboard reports source rig@frame",
    r.ok and r.result and r.result.rig == rigA and r.result.frame == PARK,
    r.ok and HttpService:JSONEncode(r.result or {}) or r.err)

-- Plain paste onto rigB
call("setActiveRig", { name = rigB })
r = call("pasteKeyframe", { mirrored = false })
ok("plain paste onto " .. rigB, r.ok and r.result == true, r.err)

r = call("getFrames", { rig = rigB })
local pasted = false
for _, f in ipairs((r.ok and r.result) or {}) do
    if f == PARK then pasted = true end
end
ok("target rig gained the keyframe", pasted)

r = call("getJointCF", { rig = rigB, frame = PARK, joint = "Right Shoulder" })
local plainMatch = r.ok and r.result ~= nil
if plainMatch then
    for i = 1, 12 do
        if not approx(r.result[i], poseComponents[i]) then plainMatch = false end
    end
end
ok("plain paste copies the joint transform exactly", plainMatch, r.err)

-- Mirrored paste onto rigB (overwrites the same frame)
r = call("pasteKeyframe", { mirrored = true })
ok("mirrored paste onto " .. rigB, r.ok and r.result == true, r.err)

-- The RIGHT shoulder pose must land on the LEFT shoulder, X-mirrored.
r = call("getJointCF", { rig = rigB, frame = PARK, joint = "Left Shoulder" })
local expected = mirrorComponents(poseComponents)
local mirMatch = r.ok and r.result ~= nil
if mirMatch then
    for i = 1, 12 do
        if not approx(r.result[i], expected[i]) then mirMatch = false end
    end
end
ok("mirrored paste: right-shoulder pose lands on LEFT shoulder, X-mirrored", mirMatch, r.err)

-- Centre joints (Neck) must be present and mirrored in place.
r = call("getJointCF", { rig = rigB, frame = PARK, joint = "Neck" })
ok("centre joint (Neck) present after mirrored paste", r.ok and r.result ~= nil, r.err)

-- ── Cleanup ───────────────────────────────────────────────────────────────────

call("deleteKeyframe", { rig = rigA, frame = PARK })
call("deleteKeyframe", { rig = rigB, frame = PARK })

local clean = true
for _, rig in ipairs({ rigA, rigB }) do
    r = call("getFrames", { rig = rig })
    for _, f in ipairs((r.ok and r.result) or {}) do
        if f == PARK then clean = false end
    end
end
ok("parking-frame keyframes cleaned up", clean)

-- Put every rig part back exactly where it started.
restoreRigs()
local restored = true
for p, cf in pairs(partSnapshots) do
    if p.Parent and (p.CFrame.Position - cf.Position).Magnitude > 0.001 then
        restored = false
    end
end
ok("rig part CFrames restored to pre-test state", restored)

if prevFrame.ok then call("setFrame", { frame = prevFrame.result }) end

return finish()
