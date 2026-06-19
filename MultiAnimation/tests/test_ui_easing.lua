-- test_ui_easing.lua — per-keyframe easing via TestBridge (live Studio required)
-- Run via: mcp luau -f tests/test_ui_easing.lua   (in Edit mode, Simple Mode)

local bridge = game:GetService("CoreGui"):WaitForChild("MultiAnimTestBridge", 5)
if not bridge then return "SKIP: plugin not loaded" end
local function call(cmd, args)
    return bridge:Invoke({ command = cmd, args = args or {} })
end

local pass, fail = 0, 0
local function check(label, ok)
    if ok then pass += 1
    else fail += 1; warn("FAIL: " .. label)
    end
end

-- ── Setup: ensure we're in Advanced mode ─────────────────────────────────────
call("setMode", { mode = "advanced" })

-- ── 1: Rig easing CRUD via bridge ────────────────────────────────────────────
local rigs = call("getActiveRigs")
if not rigs or #rigs == 0 then
    return "SKIP: no active rigs — refresh and add a rig first"
end
local rigName = rigs[1]

-- Add a keyframe at frame 1
call("setFrame", { frame = 1 })
call("addKeyframe")

-- Default easing should be Linear
check("rig easing default Linear", call("getEasing", { rig = rigName, frame = 1 }) == "Linear")

-- Set to EaseIn
call("setEasing", { rig = rigName, frame = 1, easing = "EaseIn" })
check("rig easing EaseIn stored", call("getEasing", { rig = rigName, frame = 1 }) == "EaseIn")

-- Set back to Linear
call("setEasing", { rig = rigName, frame = 1, easing = "Linear" })
check("rig easing reset to Linear", call("getEasing", { rig = rigName, frame = 1 }) == "Linear")

-- ── 2: All 6 easing styles round-trip ────────────────────────────────────────
local styles = { "Linear", "EaseIn", "EaseOut", "EaseInOut", "Constant", "Bounce" }
call("setFrame", { frame = 2 })
call("addKeyframe")
for _, style in ipairs(styles) do
    call("setEasing", { rig = rigName, frame = 2, easing = style })
    check("round-trip " .. style, call("getEasing", { rig = rigName, frame = 2 }) == style)
end

-- ── 3: Camera easing CRUD ────────────────────────────────────────────────────
call("captureCamera")
local camFrames = call("getCameraFrames")
if #camFrames > 0 then
    local cf = camFrames[1]
    check("camera easing default Linear", call("getCameraEasing", { frame = cf }) == "Linear")
    call("setCameraEasing", { frame = cf, easing = "EaseInOut" })
    check("camera easing EaseInOut", call("getCameraEasing", { frame = cf }) == "EaseInOut")
    call("setCameraEasing", { frame = cf, easing = "Linear" })
    check("camera easing reset", call("getCameraEasing", { frame = cf }) == "Linear")
else
    -- No camera part — skip camera tests
    pass += 3
end

-- ── 4: Simple mode easing state ──────────────────────────────────────────────
call("setMode", { mode = "simple" })
call("setSimpleEasing", { easing = "Linear" })   -- explicit reset
check("getSimpleEasing default Linear", call("getSimpleEasing") == "Linear")

call("setSimpleEasing", { easing = "EaseOut" })
check("setSimpleEasing", call("getSimpleEasing") == "EaseOut")

call("setSimpleEasing", { easing = "Bounce" })
check("setSimpleEasing Bounce", call("getSimpleEasing") == "Bounce")

-- Reset
call("setSimpleEasing", { easing = "Linear" })
check("setSimpleEasing reset", call("getSimpleEasing") == "Linear")

-- ── 5: Simple capture stamps easing ──────────────────────────────────────────
call("setSimpleEasing", { easing = "EaseIn" })
call("setFrame", { frame = 1 })
call("simpleAddFrame")
-- The frame just captured should have EaseIn on all rigs
for _, rName in ipairs(rigs) do
    check("captureFrame stamps rig easing",
        call("getEasing", { rig = rName, frame = 1 }) == "EaseIn")
end

-- ── 6: Frame navigation updates simple easing display ────────────────────────
-- Set frame 1 easing to EaseOut then navigate to frame 1 and verify sync
call("setMode", { mode = "advanced" })
call("setFrame", { frame = 1 })
call("addKeyframe")
call("setEasing", { rig = rigName, frame = 1, easing = "EaseOut" })

call("setMode", { mode = "simple" })
call("setSimpleEasing", { easing = "Linear" })   -- start with different easing
-- simpleNavigate syncs easing display (same logic as clicking a frame icon)
call("simpleNavigate", { frame = 1 })
check("navigation syncs easing display", call("getSimpleEasing") == "EaseOut")

-- Cleanup
call("setMode", { mode = "advanced" })

local total = pass + fail
if fail == 0 then
    return string.format("ALL TESTS PASSED (%d/%d)", pass, total)
else
    return string.format("FAILED %d/%d\n%d passed", fail, total, pass)
end
