-- test_scrubber.lua
-- Run via MCP execute_luau.  Two sections:
--   1. Pure math — frameFromInputX logic with mock coordinates (no GUI needed)
--   2. Live diagnostic — reads the real scrubber's AbsolutePosition/Size and
--      shows all three coordinate values so we can spot any space mismatch.
--
-- Usage:
--   Section 1: always runs, tells you if the math is correct.
--   Section 2: requires Studio to have the MultiAnimation plugin open.
--              Move your mouse over the scrubber before running for best data.

local UserInputService = game:GetService("UserInputService")

local out = {}
local function p(s) table.insert(out, s) end
local function ok(label, cond, extra)
    p((cond and "PASS" or "FAIL") .. "  " .. label .. (extra ~= nil and ("  [" .. tostring(extra) .. "]") or ""))
end

-- ── Section 1: frame calculation math ────────────────────────────────────────

p("── Section 1: frame math (mock track: left=200 width=400 frameCount=120) ──")

local function makeCalc(left, width, frameCount)
    return function(inputX)
        if width <= 0 then return 1 end
        local frac = math.clamp((inputX - left) / width, 0, 1)
        return math.round(1 + frac * (frameCount - 1))
    end
end

do
    local fc = makeCalc(200, 400, 120)
    ok("frame 1 at left edge   (inputX=200)",    fc(200)  == 1,   fc(200))
    ok("frame 120 at right edge(inputX=600)",    fc(600)  == 120, fc(600))
    ok("frame 1 before left    (inputX=50)",     fc(50)   == 1,   fc(50))
    ok("frame 120 after right  (inputX=900)",    fc(900)  == 120, fc(900))
    ok("frame ~60 at midpoint  (inputX=400)",    fc(400) >= 59 and fc(400) <= 61, fc(400))
    ok("frame ~30 at 25%       (inputX=300)",    fc(300) >= 29 and fc(300) <= 31, fc(300))
    ok("frame ~90 at 75%       (inputX=500)",    fc(500) >= 89 and fc(500) <= 91, fc(500))
end

p("")
p("── Section 1b: same math for frameCount=24 (small timeline) ──")

do
    local fc = makeCalc(200, 400, 24)
    ok("frame 1  at left",     fc(200) == 1,  fc(200))
    ok("frame 24 at right",    fc(600) == 24, fc(600))
    ok("frame 12-13 at mid",   fc(400) >= 12 and fc(400) <= 13, fc(400))
end

-- ── Section 2: live coordinate diagnostic ────────────────────────────────────

p("")
p("── Section 2: live coordinate diagnostic ──")

-- GetMouseLocation (OS screen coords — NOT consistent with AbsolutePosition)
local ml = UserInputService:GetMouseLocation()
p("GetMouseLocation():  X=" .. string.format("%.0f", ml.X) .. "  Y=" .. string.format("%.0f", ml.Y))
p("(This value is in OS screen space — expected to differ from AbsolutePosition.X)")

-- Try to find the plugin GUI
local found = false
for _, gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
    if gui.Name == "MultiAnimation" then
        local root = gui:FindFirstChild("MultiAnimRoot")
        if root then
            local track = root:FindFirstChild("Track", true)
            if track then
                found = true
                local ap = track.AbsolutePosition
                local as = track.AbsoluteSize
                p("")
                p("Track.AbsolutePosition: X=" .. string.format("%.0f", ap.X) .. "  Y=" .. string.format("%.0f", ap.Y))
                p("Track.AbsoluteSize:     X=" .. string.format("%.0f", as.X) .. "  Y=" .. string.format("%.0f", as.Y))
                p("")

                if as.X > 0 then
                    -- Show what frame would result from a click at the current mouse position
                    -- using AbsolutePosition (as used in frameFromInputX).
                    local frac = math.clamp((ml.X - ap.X) / as.X, 0, 1)
                    local frameAtMouse_GetMouseLoc = math.round(1 + frac * 119)
                    p("IF GetMouseLocation is used as inputX: frame would be " .. frameAtMouse_GetMouseLoc
                        .. "  (frac=" .. string.format("%.3f", frac) .. ")")
                    p("  If this is always 1, GetMouseLocation X < Track AbsolutePosition X — coordinate space mismatch confirmed.")
                    p("  inputX from input.Position.X (InputBegan) should match AbsolutePosition.X space.")
                else
                    p("Track.AbsoluteSize.X = 0 — widget may not be visible yet")
                end
            else
                p("Track frame not found inside MultiAnimRoot")
            end
        else
            p("MultiAnimRoot not found in MultiAnimation gui")
        end
        break
    end
end

if not found then
    p("MultiAnimation DockWidgetPluginGui not found in CoreGui.")
    p("Make sure the plugin is loaded and the panel is open.")
end

return table.concat(out, "\n")
