-- test_subtitle_exporter.lua — headless tests for buildSubtitleTrackSource output.

local passed, failed = 0, 0
local function ok(cond, label)
    if cond then passed = passed + 1
    else failed = failed + 1; warn("FAIL: " .. label) end
end

-- ── Inline builder (mirrors Exporter.buildSubtitleTrackSource) ────────────────

local function buildSubtitleTrackSource(session)
    local style = session.subtitleStyle or {}
    local lines = {}
    local function add(s) table.insert(lines, s) end
    add("return {")
    add("    style = {")
    add(string.format("        fontAsset          = %q,",          style.fontAsset          or "rbxasset://fonts/families/GothamSSm.json"))
    add(string.format("        fontWeight         = %q,",          style.fontWeight         or "Regular"))
    add(string.format("        size               = %d,",           style.size               or 28))
    add(string.format("        textColorR         = %d, textColorG = %d, textColorB = %d,", style.textColorR or 255, style.textColorG or 255, style.textColorB or 255))
    add(string.format("        textTransparency   = %.3f,",         style.textTransparency   or 0))
    add(string.format("        strokeColorR       = %d, strokeColorG = %d, strokeColorB = %d,", style.strokeColorR or 0, style.strokeColorG or 0, style.strokeColorB or 0))
    add(string.format("        strokeTransparency = %.3f,",         style.strokeTransparency or 0))
    add(string.format("        bgColorR           = %d, bgColorG = %d, bgColorB = %d,", style.bgColorR or 0, style.bgColorG or 0, style.bgColorB or 0))
    add(string.format("        bgTransparency     = %.3f,",         style.bgTransparency     or 0.6))
    add(string.format("        xOffset            = %.4f,",         style.xOffset            or 0.05))
    add(string.format("        yOffset            = %.4f,",         style.yOffset            or 0.85))
    add("    },")
    add("    events = {")
    for _, ev in ipairs(session.subtitles or {}) do
        add(string.format("        {frame = %d, text = %q},", ev.frame, ev.text))
    end
    add("    },")
    add("}")
    return table.concat(lines, "\n")
end

local function load(src)
    local fn, err = loadstring(src)
    if not fn then return nil, err end
    return pcall(fn)
end

-- ── 1. Empty events ───────────────────────────────────────────────────────────
do
    local src = buildSubtitleTrackSource({ subtitles = {}, subtitleStyle = {} })
    local ok1, t = load(src)
    ok(ok1, "empty: loadstring ok")
    ok(type(t) == "table", "empty: returns table")
    ok(type(t.events) == "table", "empty: events field present")
    ok(#t.events == 0, "empty: events is empty")
    ok(type(t.style) == "table", "empty: style field present")
end

-- ── 2. Default style values ───────────────────────────────────────────────────
do
    local src = buildSubtitleTrackSource({ subtitles = {}, subtitleStyle = {} })
    local _, t = load(src)
    ok(t.style.size == 28, "default size 28")
    ok(t.style.fontWeight == "Regular", "default fontWeight")
    ok(t.style.yOffset == 0.85, "default yOffset 0.85")
    ok(t.style.bgTransparency == 0.6, "default bgTransparency 0.6")
    ok(t.style.xOffset == 0.05, "default xOffset 0.05")
    ok(t.style.textColorR == 255 and t.style.textColorG == 255 and t.style.textColorB == 255,
        "default text color white")
    ok(t.style.strokeColorR == 0 and t.style.strokeColorG == 0 and t.style.strokeColorB == 0,
        "default stroke color black")
end

-- ── 3. Single event ───────────────────────────────────────────────────────────
do
    local session = {
        subtitles     = { { frame = 5, text = "Hello world" } },
        subtitleStyle = {},
    }
    local src = buildSubtitleTrackSource(session)
    local _, t = load(src)
    ok(#t.events == 1, "single event count")
    ok(t.events[1].frame == 5, "single event frame")
    ok(t.events[1].text == "Hello world", "single event text")
end

-- ── 4. Multiple events preserve order ────────────────────────────────────────
do
    local session = {
        subtitles = {
            { frame = 1,  text = "Opening" },
            { frame = 10, text = "Middle" },
            { frame = 20, text = "End" },
        },
        subtitleStyle = {},
    }
    local src = buildSubtitleTrackSource(session)
    local _, t = load(src)
    ok(#t.events == 3, "multi event count")
    ok(t.events[1].frame == 1  and t.events[1].text == "Opening", "event 1 ok")
    ok(t.events[2].frame == 10 and t.events[2].text == "Middle",  "event 2 ok")
    ok(t.events[3].frame == 20 and t.events[3].text == "End",     "event 3 ok")
end

-- ── 5. Custom style fields round-trip ────────────────────────────────────────
do
    local style = {
        fontAsset         = "rbxasset://fonts/families/Ubuntu.json",
        fontWeight        = "Bold",
        size              = 36,
        textColorR        = 200, textColorG = 100, textColorB = 50,
        textTransparency  = 0.1,
        strokeColorR      = 10,  strokeColorG = 20,  strokeColorB = 30,
        strokeTransparency = 0.5,
        bgColorR          = 40,  bgColorG = 50, bgColorB = 60,
        bgTransparency    = 0.75,
        xOffset           = 0.1,
        yOffset           = 0.8,
    }
    local src = buildSubtitleTrackSource({ subtitles = {}, subtitleStyle = style })
    local _, t = load(src)
    ok(t.style.fontAsset == "rbxasset://fonts/families/Ubuntu.json", "custom fontAsset")
    ok(t.style.fontWeight == "Bold", "custom fontWeight")
    ok(t.style.size == 36, "custom size")
    ok(t.style.textColorR == 200 and t.style.textColorG == 100 and t.style.textColorB == 50,
        "custom text color")
    ok(math.abs(t.style.textTransparency - 0.1) < 0.001, "custom textTransparency")
    ok(t.style.strokeColorR == 10 and t.style.strokeColorG == 20 and t.style.strokeColorB == 30,
        "custom stroke color")
    ok(math.abs(t.style.strokeTransparency - 0.5) < 0.001, "custom strokeTransparency")
    ok(t.style.bgColorR == 40 and t.style.bgColorG == 50 and t.style.bgColorB == 60,
        "custom bg color")
    ok(math.abs(t.style.bgTransparency - 0.75) < 0.001, "custom bgTransparency")
    ok(math.abs(t.style.xOffset - 0.1) < 0.0001, "custom xOffset")
    ok(math.abs(t.style.yOffset - 0.8) < 0.0001, "custom yOffset")
end

-- ── 6. Text with special characters survives round-trip ──────────────────────
do
    local text = 'He said "hello" & she\'s fine'
    local session = { subtitles = { {frame=1, text=text} }, subtitleStyle = {} }
    local src = buildSubtitleTrackSource(session)
    local _, t = load(src)
    ok(t.events[1].text == text, "special chars round-trip")
end

-- ── 7. Source is valid Lua (no stray syntax errors) ──────────────────────────
do
    local session = {
        subtitles = {
            {frame=1, text="Line one"},
            {frame=30, text="Line two with more words"},
        },
        subtitleStyle = { size=24, fontWeight="SemiBold", yOffset=0.9 },
    }
    local src = buildSubtitleTrackSource(session)
    local fn, err = loadstring(src)
    ok(fn ~= nil, "multi-event source is valid Lua: " .. tostring(err))
end

local total = passed + failed
if failed == 0 then
    return string.format("ALL TESTS PASSED (%d/%d)\n=== %d passed, %d failed ===", total, total, passed, failed)
end
return string.format("=== %d passed, %d failed ===", passed, failed)
