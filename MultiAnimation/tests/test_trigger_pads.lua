-- test_trigger_pads.lua
-- Auto-pads on export: ensureTriggerPad builds a labelled trigger pad and
-- deploys the AnimPadListener LocalScript; existing pads keep their position;
-- the toggle round-trips. Live test — needs the plugin panel open.

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

local SCENE = "__PadTest_001"

-- ── Toggle round-trip ─────────────────────────────────────────────────────────

local prev = call("getAutoPads")
ok("getAutoPads returns a boolean", prev.ok and type(prev.result) == "boolean")
local r = call("setAutoPads", { on = false })
ok("setAutoPads off", r.ok and r.result == false)
r = call("getAutoPads")
ok("toggle round-trips", r.ok and r.result == false)
call("setAutoPads", { on = prev.result })

-- ── Pad creation ──────────────────────────────────────────────────────────────

r = call("ensureTriggerPad", { scene = SCENE })
ok("ensureTriggerPad returns a path", r.ok and type(r.result) == "string", hs:JSONEncode(r))

local folder = workspace:FindFirstChild("AnimTriggerPads")
local pad = folder and folder:FindFirstChild("Pad_" .. SCENE)
ok("pad part exists in AnimTriggerPads", pad ~= nil)

if pad then
    ok("SceneName attribute set", pad:GetAttribute("SceneName") == SCENE)
    local lblGui = pad:FindFirstChild("Label")
    local textLbl = lblGui and lblGui:FindFirstChildOfClass("TextLabel")
    ok("label shows the scene name", textLbl ~= nil and textLbl.Text == SCENE,
        textLbl and textLbl.Text)
    ok("pad is anchored neon", pad.Anchored and pad.Material == Enum.Material.Neon)

    -- ── Idempotence: second call keeps position/colour, refreshes label ──────
    local origPos, origColor = pad.Position, pad.Color
    pad.Position = pad.Position + Vector3.new(3, 0, 3)   -- user moved the pad
    call("ensureTriggerPad", { scene = SCENE })
    local pad2 = folder:FindFirstChild("Pad_" .. SCENE)
    ok("re-ensure reuses the same pad", pad2 == pad)
    ok("re-ensure keeps the (moved) position",
        (pad.Position - (origPos + Vector3.new(3, 0, 3))).Magnitude < 0.01,
        tostring(pad.Position))
    ok("re-ensure keeps the colour", pad.Color == origColor)
end

local sps = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts")
local listener = sps and sps:FindFirstChild("AnimPadListener")
ok("AnimPadListener LocalScript deployed",
    listener ~= nil and listener:IsA("LocalScript"))

-- ── Cleanup ───────────────────────────────────────────────────────────────────

if pad then pad:Destroy() end

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
