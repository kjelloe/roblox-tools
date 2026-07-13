-- test_subtitle_core.lua — headless tests for subtitle Recorder CRUD,
-- style management, and getActiveSubtitleAt stepped lookup.

local passed, failed = 0, 0
local function ok(cond, label)
    if cond then passed = passed + 1
    else failed = failed + 1; warn("FAIL: " .. label) end
end

-- ── Inline Recorder subset ────────────────────────────────────────────────────

local Rec = {}
Rec.__index = Rec
function Rec.new()
    local s = setmetatable({}, Rec)
    s._session = {
        subtitlesEnabled = false,
        subtitles        = {},
        subtitleStyle    = {
            fontAsset="rbxasset://fonts/families/GothamSSm.json",fontWeight="Regular",
            size=28,textColorR=255,textColorG=255,textColorB=255,textTransparency=0,
            strokeColorR=0,strokeColorG=0,strokeColorB=0,strokeTransparency=0,
            bgColorR=0,bgColorG=0,bgColorB=0,bgTransparency=0.6,xOffset=0.05,yOffset=0.85,
        },
    }
    return s
end
function Rec:setSubtitlesEnabled(v) self._session.subtitlesEnabled = v == true end
function Rec:getSubtitlesEnabled() return self._session.subtitlesEnabled end
function Rec:setSubtitleStyle(patch) for k,v in pairs(patch) do self._session.subtitleStyle[k]=v end end
function Rec:getSubtitleStyle() return self._session.subtitleStyle end
function Rec:setSubtitleEvent(frame, text)
    local s = self._session.subtitles
    for i,ev in ipairs(s) do
        if ev.frame == frame then ev.text = text; return end
        if ev.frame > frame then table.insert(s, i, {frame=frame, text=text}); return end
    end
    table.insert(s, {frame=frame, text=text})
end
function Rec:removeSubtitleEvent(frame)
    local s = self._session.subtitles
    for i,ev in ipairs(s) do if ev.frame == frame then table.remove(s,i); return end end
end
function Rec:getSubtitleEventAt(frame)
    for _,ev in ipairs(self._session.subtitles) do if ev.frame == frame then return ev end end
    return nil
end
function Rec:getActiveSubtitleAt(frame)
    local active
    for _,ev in ipairs(self._session.subtitles) do
        if ev.frame <= frame then active = ev else break end
    end
    if active and active.text ~= "" then return active.text end
    return nil
end
function Rec:getSubtitleEvents() return self._session.subtitles end
function Rec:clearSubtitles()
    self._session.subtitles = {}
    self._session.subtitlesEnabled = false
end

-- ── Tests ─────────────────────────────────────────────────────────────────────

local r = Rec.new()

-- 1. enabled defaults false
ok(r:getSubtitlesEnabled() == false, "subtitlesEnabled defaults false")

-- 2. setSubtitlesEnabled true
r:setSubtitlesEnabled(true)
ok(r:getSubtitlesEnabled() == true, "setSubtitlesEnabled true")

-- 3. setSubtitlesEnabled false
r:setSubtitlesEnabled(false)
ok(r:getSubtitlesEnabled() == false, "setSubtitlesEnabled false")

-- 4. no events initially
ok(#r:getSubtitleEvents() == 0, "no subtitle events initially")

-- 5. add event
r:setSubtitleEvent(5, "Hello world")
ok(#r:getSubtitleEvents() == 1, "one event after add")

-- 6. event has correct frame
ok(r:getSubtitleEvents()[1].frame == 5, "event frame is 5")

-- 7. event has correct text
ok(r:getSubtitleEvents()[1].text == "Hello world", "event text correct")

-- 8. getSubtitleEventAt hit
ok(r:getSubtitleEventAt(5) ~= nil, "getSubtitleEventAt(5) found")

-- 9. getSubtitleEventAt miss
ok(r:getSubtitleEventAt(4) == nil, "getSubtitleEventAt(4) nil")

-- 10. getActiveSubtitleAt before any event → nil
ok(r:getActiveSubtitleAt(4) == nil, "getActiveSubtitleAt before first event is nil")

-- 11. getActiveSubtitleAt at event frame
ok(r:getActiveSubtitleAt(5) == "Hello world", "getActiveSubtitleAt at event frame")

-- 12. getActiveSubtitleAt after event frame (inherits)
ok(r:getActiveSubtitleAt(10) == "Hello world", "getActiveSubtitleAt inherits after event")

-- 13. add second event; sorted insert
r:setSubtitleEvent(15, "Goodbye")
ok(#r:getSubtitleEvents() == 2, "two events after second add")
ok(r:getSubtitleEvents()[1].frame == 5,  "first event still frame 5")
ok(r:getSubtitleEvents()[2].frame == 15, "second event frame 15")

-- 15. insert event between existing: sorted
r:setSubtitleEvent(10, "Middle")
ok(r:getSubtitleEvents()[2].frame == 10, "middle insert at correct position")
ok(r:getSubtitleEvents()[3].frame == 15, "third event stays at 15")

-- 16. update existing event
r:setSubtitleEvent(10, "Middle Updated")
ok(r:getSubtitleEventAt(10).text == "Middle Updated", "update existing event text")
ok(#r:getSubtitleEvents() == 3, "update does not add duplicate")

-- 17. stepped lookup: frame in 10-14 → Middle Updated
ok(r:getActiveSubtitleAt(12) == "Middle Updated", "stepped lookup between 10 and 15")

-- 18. stepped lookup: frame ≥ 15 → Goodbye
ok(r:getActiveSubtitleAt(20) == "Goodbye", "stepped lookup after 15")

-- 18b. empty-text event acts as a clear marker (hides, not empty bar)
r:setSubtitleEvent(18, "")
ok(r:getActiveSubtitleAt(19) == nil, "empty-text event clears active subtitle")
ok(r:getActiveSubtitleAt(16) == "Goodbye", "text before clear marker unaffected")
r:removeSubtitleEvent(18)

-- 19. remove event
r:removeSubtitleEvent(10)
ok(#r:getSubtitleEvents() == 2, "event removed")
ok(r:getSubtitleEventAt(10) == nil, "removed event not found")

-- 20. after remove, frame 12 inherits from frame 5 again
ok(r:getActiveSubtitleAt(12) == "Hello world", "inheritance resets after remove")

-- 21. remove non-existent frame is safe
r:removeSubtitleEvent(99)
ok(#r:getSubtitleEvents() == 2, "remove non-existent is no-op")

-- 22. clearSubtitles
r:clearSubtitles()
ok(#r:getSubtitleEvents() == 0, "clearSubtitles empties events")
ok(r:getSubtitlesEnabled() == false, "clearSubtitles resets enabled")

-- 23. style defaults
local style = r:getSubtitleStyle()
ok(style.size == 28, "default size 28")
ok(style.fontWeight == "Regular", "default fontWeight Regular")
ok(style.yOffset == 0.85, "default yOffset 0.85")
ok(style.bgTransparency == 0.6, "default bgTransparency 0.6")

-- 24. setSubtitleStyle partial patch
r:setSubtitleStyle({ size = 36, yOffset = 0.9 })
local s2 = r:getSubtitleStyle()
ok(s2.size == 36, "style patch: size updated")
ok(s2.yOffset == 0.9, "style patch: yOffset updated")
ok(s2.fontWeight == "Regular", "style patch: unpatched field preserved")

-- 25. style color patch
r:setSubtitleStyle({ textColorR = 200, textColorG = 100, textColorB = 50 })
local s3 = r:getSubtitleStyle()
ok(s3.textColorR == 200 and s3.textColorG == 100 and s3.textColorB == 50, "style color patch")

-- 26. add event at frame 1 inserts before others
r:setSubtitleEvent(5, "Five")
r:setSubtitleEvent(1, "One")
ok(r:getSubtitleEvents()[1].frame == 1, "frame 1 inserted first")
ok(r:getSubtitleEvents()[2].frame == 5, "frame 5 second")

-- 27. getActiveSubtitleAt(1)
ok(r:getActiveSubtitleAt(1) == "One", "active at frame 1")

-- 28. getActiveSubtitleAt(3) inherits from frame 1
ok(r:getActiveSubtitleAt(3) == "One", "active at frame 3 inherits frame 1")

local total = passed + failed
if failed == 0 then
    return string.format("ALL TESTS PASSED (%d/%d)\n=== %d passed, %d failed ===", total, total, passed, failed)
end
return string.format("=== %d passed, %d failed ===", passed, failed)
