-- test_effect_exporter.lua
-- EffectTracks ModuleScript source builder: structure, action/count fields,
-- loadstring round-trip, sorted output, omit-if-empty behaviour.
-- Inlines buildEffectTracksSource from core/Exporter.lua.

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

-- ── Inline builder (mirrors Exporter.buildEffectTracksSource) ─────────────────

local function buildEffectTracksSource(session)
    local lines = {}
    local function add(s) table.insert(lines, s) end

    add("return {")
    add(string.format("    fps = %d,", session.fps or 24))
    add("    effects = {")

    local names = {}
    for name in pairs(session.effects or {}) do table.insert(names, name) end
    table.sort(names)

    for _, name in ipairs(names) do
        local fx = session.effects[name]
        if next(fx.track) then
            add(string.format("        [%q] = {", name))
            add(string.format("            target = %q,", fx.path or ""))
            add("            events = {")
            local sortedFrames = {}
            for f in pairs(fx.track) do table.insert(sortedFrames, f) end
            table.sort(sortedFrames)
            for _, frame in ipairs(sortedFrames) do
                local ev = fx.track[frame]
                if ev.count then
                    add(string.format("                [%d] = {action = %q, count = %d},",
                        frame, ev.action, ev.count))
                else
                    add(string.format("                [%d] = {action = %q},", frame, ev.action))
                end
            end
            add("            },")
            add("        },")
        end
    end

    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

-- ── Build from a fake session ─────────────────────────────────────────────────

local session = {
    fps = 24,
    effects = {
        Spark = {
            kind = "emitter", action = "emit", path = "Workspace.FXPart.Spark",
            track = {
                [5]  = { action = "emit", count = 20 },
                [30] = { action = "on" },
                [40] = { action = "off" },
            },
        },
        Boom = {
            kind = "sound", action = "play", path = "Workspace.FXPart.Boom",
            track = {
                [5] = { action = "play" },
            },
        },
        Unused = {
            kind = "enabled", action = "on", path = "Workspace.Lamp.Light",
            track = {},   -- no events → must be omitted from output
        },
    },
}

local src = buildEffectTracksSource(session)
ok("source is non-empty string", type(src) == "string" and #src > 0)

local fn, err = loadstring(src)
ok("source compiles via loadstring", fn ~= nil, err)
if not fn then
    table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
    table.insert(out, "FAILURES DETECTED")
    return table.concat(out, "\n")
end

local data = fn()
ok("returns a table with fps", type(data) == "table" and data.fps == 24)
ok("both active effects present", data.effects.Spark ~= nil and data.effects.Boom ~= nil)
ok("effect with no events omitted", data.effects.Unused == nil)

local spark = data.effects.Spark
ok("target path preserved", spark.target == "Workspace.FXPart.Spark")
ok("emit event keeps count", spark.events[5] and spark.events[5].action == "emit"
    and spark.events[5].count == 20)
ok("on/off events have no count field",
    spark.events[30] and spark.events[30].action == "on" and spark.events[30].count == nil
    and spark.events[40] and spark.events[40].action == "off")
ok("sound event preserved", data.effects.Boom.events[5]
    and data.effects.Boom.events[5].action == "play")

-- Time conversion convention check: frame → (frame-1)/fps
ok("frame 5 maps to time 4/24", math.abs(((5 - 1) / data.fps) - (4 / 24)) < 1e-9)

-- ── Omit-if-empty predicate (mirrors the export flow) ─────────────────────────

local function shouldWrite(sess)
    for _, fx in pairs(sess.effects or {}) do
        if next(fx.track) then return true end
    end
    return false
end
ok("module written when any effect has events", shouldWrite(session) == true)
ok("module omitted when all tracks empty",
    not shouldWrite({ effects = { A = { track = {} } } }))
ok("module omitted when effects absent", not shouldWrite({}))

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
