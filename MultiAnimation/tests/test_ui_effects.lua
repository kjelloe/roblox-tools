-- test_ui_effects.lua
-- Effect track UI integration via the TestBridge: track a temp emitter,
-- cycle its action, add/read/delete events, fire one, untrack.
-- Creates its own temp instances and removes everything it made.

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

-- ── Temp effect setup ─────────────────────────────────────────────────────────

local FX_NAME = "__FxUiTestSpark"

local holder = Instance.new("Part")
holder.Name = "__FxUiTestPart"
holder.Anchored = true
holder.Transparency = 1
holder.CanCollide = false
holder.Position = Vector3.new(0, -85, 0)
holder.Parent = workspace

local emitter = Instance.new("ParticleEmitter")
emitter.Name = FX_NAME
emitter.Enabled = false
emitter.Parent = holder

local function cleanup()
    call("untrackEffect", { name = FX_NAME })
    holder:Destroy()
end

-- ── Track via path (selecting the holder part finds the emitter) ──────────────

local r = call("trackEffect", { path = "Workspace.__FxUiTestPart" })
ok("trackEffect resolves the emitter from its holder part",
    r.ok and r.result == FX_NAME, r.err or tostring(r.result))
if not (r.ok and r.result == FX_NAME) then cleanup(); return finish() end

r = call("getEffects")
local listed = false
for _, n in ipairs((r.ok and r.result) or {}) do
    if n == FX_NAME then listed = true end
end
ok("effect appears in getEffects", listed)

r = call("getEffectInfo", { name = FX_NAME })
ok("classified as emitter with default 'emit', live-linked",
    r.ok and r.result and r.result.kind == "emitter"
    and r.result.action == "emit" and r.result.linked == true,
    r.ok and HttpService:JSONEncode(r.result or {}) or r.err)

-- ── Action cycling ────────────────────────────────────────────────────────────

r = call("cycleEffectAction", { name = FX_NAME })
ok("cycle: emit → on", r.ok and r.result == "on", r.err or tostring(r.result))
r = call("cycleEffectAction", { name = FX_NAME })
ok("cycle: on → off", r.ok and r.result == "off")
r = call("cycleEffectAction", { name = FX_NAME })
ok("cycle wraps: off → emit", r.ok and r.result == "emit")

-- ── Events ────────────────────────────────────────────────────────────────────

local rc = call("getFrameCount")
local frameCount = (rc.ok and rc.result) or 120
local PARK = frameCount - 23

r = call("addEffectEvent", { name = FX_NAME, frame = PARK })
ok("addEffectEvent", r.ok and r.result == true, r.err)

r = call("getEffectEvent", { name = FX_NAME, frame = PARK })
ok("event stored with current default action + count",
    r.ok and r.result and r.result.action == "emit" and r.result.count == 15,
    r.ok and HttpService:JSONEncode(r.result or {}) or r.err)

r = call("getEffectFrames", { name = FX_NAME })
ok("event frame listed", r.ok and #r.result == 1 and r.result[1] == PARK)

-- Cycling the default does NOT rewrite existing events.
call("cycleEffectAction", { name = FX_NAME })   -- emit → on
r = call("getEffectEvent", { name = FX_NAME, frame = PARK })
ok("existing event unchanged after default-action cycle",
    r.ok and r.result and r.result.action == "emit")

-- A second event picks up the new default.
call("addEffectEvent", { name = FX_NAME, frame = PARK + 3 })
r = call("getEffectEvent", { name = FX_NAME, frame = PARK + 3 })
ok("new event uses the cycled default ('on', no count)",
    r.ok and r.result and r.result.action == "on" and r.result.count == nil)

-- ── Live fire through the bridge ──────────────────────────────────────────────

r = call("fireEffect", { name = FX_NAME, frame = PARK + 3 })   -- action "on"
ok("fireEffect executes", r.ok and r.result == true, r.err)
ok("'on' event actually enabled the emitter", emitter.Enabled == true)

r = call("fireEffect", { name = FX_NAME, frame = PARK })       -- action "emit"
ok("emit event fires without error", r.ok and r.result == true, r.err)

-- ── Delete + untrack ──────────────────────────────────────────────────────────

call("deleteEffectEvent", { name = FX_NAME, frame = PARK })
call("deleteEffectEvent", { name = FX_NAME, frame = PARK + 3 })
r = call("getEffectFrames", { name = FX_NAME })
ok("events deleted", r.ok and #r.result == 0)

r = call("untrackEffect", { name = FX_NAME })
ok("untrackEffect", r.ok and r.result == true, r.err)
r = call("getEffectInfo", { name = FX_NAME })
ok("data retained after untrack (like props)", r.ok and r.result ~= nil
    and r.result.linked == false)

holder:Destroy()

return finish()
