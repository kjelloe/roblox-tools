-- test_scrubber.lua
-- Run via MCP execute_luau.  Three sections:
--
--   Section 1: Pure math — verifies frameFromInputX logic (no GUI needed).
--   Section 2: Coordinate diagnostic — reads real scrubber positions and shows
--              whether GetMouseLocation() matches AbsolutePosition space.
--   Section 3: InputChanged diagnostic — runs for 2 seconds and counts how many
--              MouseMovement events fire; confirms whether InputChanged works
--              in the DockWidget context (move your mouse while it runs).
--
-- Usage:  move mouse over/around the plugin panel before running section 3.

local UserInputService = game:GetService("UserInputService")

local out = {}
local function p(s) table.insert(out, s) end
local function ok(label, cond, extra)
    p((cond and "PASS" or "FAIL") .. "  " .. label .. (extra ~= nil and ("  [" .. tostring(extra) .. "]") or ""))
end

-- ── Section 1: frame calculation math (mock track) ───────────────────────────

p("── Section 1: frameFromInputX math  (trackLeft=200 trackW=400 fc=120) ──")

local function makeCalc(left, width, fc)
    return function(inputX)
        if width <= 0 then return 1 end
        local frac = math.clamp((inputX - left) / width, 0, 1)
        return math.round(1 + frac * (fc - 1))
    end
end

do
    local f = makeCalc(200, 400, 120)
    ok("frame 1   at left edge    inputX=200", f(200) == 1,   f(200))
    ok("frame 120 at right edge   inputX=600", f(600) == 120, f(600))
    ok("frame 1   before left     inputX=50",  f(50)  == 1,   f(50))
    ok("frame 120 past right      inputX=900", f(900) == 120, f(900))
    ok("frame ~60 midpoint        inputX=400", f(400) >= 59 and f(400) <= 61, f(400))
    ok("frame ~30 at 25%          inputX=300", f(300) >= 29 and f(300) <= 31, f(300))
    ok("frame ~90 at 75%          inputX=500", f(500) >= 89 and f(500) <= 91, f(500))
end

p("")
p("── Section 1b: coordOffset correction math ──")
-- Simulate: AbsolutePosition.X = 500 (Roblox GUI space)
--           GetMouseLocation().X = 50  (OS space, 450px smaller)
--           coordOffset = 500 - 50 = 450
-- During drag: GetMouseLocation() = 80  →  corrected = 80 + 450 = 530
-- Expected frame from corrected = f(530) with trackLeft=500, trackW=200
do
    local trackLeft = 500
    local trackW    = 200
    local fc        = 120
    local f = makeCalc(trackLeft, trackW, fc)
    local coordOffset = trackLeft - 50   -- = 450 (inputX_at_start - mlX_at_start when inputX = trackLeft)
    local function corrected(mlX) return mlX + coordOffset end

    ok("corrected at left  (mlX=50  → corrX=500)",  f(corrected(50))  == 1,   f(corrected(50)))
    ok("corrected at right (mlX=250 → corrX=700)",  f(corrected(250)) == 120, f(corrected(250)))
    ok("corrected at mid   (mlX=150 → corrX=600)",  f(corrected(150)) >= 59 and f(corrected(150)) <= 61, f(corrected(150)))
end

-- ── Section 2: live coordinate diagnostic ────────────────────────────────────

p("")
p("── Section 2: live coordinates ──")

local ml = UserInputService:GetMouseLocation()
p(string.format("GetMouseLocation:  X=%.0f  Y=%.0f  (OS screen space)", ml.X, ml.Y))

local pluginFound = false
for _, gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
    if gui.Name == "MultiAnimation" then
        local root = gui:FindFirstChild("MultiAnimRoot")
        if root then
            local track = root:FindFirstChild("Track", true)
            if track then
                pluginFound = true
                local ap = track.AbsolutePosition
                local as = track.AbsoluteSize
                local offset = ap.X - ml.X
                p(string.format("Track AbsolutePosition: X=%.0f  Y=%.0f", ap.X, ap.Y))
                p(string.format("Track AbsoluteSize:     X=%.0f  Y=%.0f", as.X, as.Y))
                p(string.format("coordOffset (AbsPos.X - mlX) = %.0f", offset))
                if math.abs(offset) > 50 then
                    p("  → MISMATCH confirmed: coordOffset=" .. string.format("%.0f", offset)
                        .. "  Heartbeat+correctedX approach needed for drag.")
                else
                    p("  → Spaces appear consistent (offset < 50px).")
                end
            end
        end
        break
    end
end
if not pluginFound then
    p("Plugin GUI not found — open the MultiAnimation panel first.")
end

-- ── Section 3: InputChanged fires-in-plugin diagnostic ───────────────────────

p("")
p("── Section 3: InputChanged MouseMovement count (2-second window) ──")
p("Move your mouse now...")

local moveCount = 0
local firstMoveX, lastMoveX

local conn = UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    moveCount += 1
    if not firstMoveX then firstMoveX = input.Position.X end
    lastMoveX = input.Position.X
end)

task.wait(2)
conn:Disconnect()

if moveCount == 0 then
    p("FAIL  InputChanged (MouseMovement) fired 0 times over 2 seconds.")
    p("      → UserInputService.InputChanged does NOT fire over DockWidgets.")
    p("      → Heartbeat+IsMouseButtonPressed is the correct drag approach.")
else
    p(string.format("PASS  InputChanged fired %d times  (firstX=%.0f lastX=%.0f)",
        moveCount, firstMoveX or 0, lastMoveX or 0))
    p("      → InputChanged does fire in plugin context.")
end

return table.concat(out, "\n")
