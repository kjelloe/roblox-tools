-- test_easing_core.lua — per-keyframe easing: Recorder CRUD + Interpolator math
-- Run via: mcp luau -f tests/test_easing_core.lua

local pass, fail = 0, 0
local function check(label, ok)
    if ok then pass += 1
    else fail += 1; warn("FAIL: " .. label)
    end
end

-- ── inline Recorder (subset) ──────────────────────────────────────────────────
local Rec = {}
Rec.__index = Rec
function Rec.new()
    return setmetatable({
        rigs = {}, props = {}, camera = { track = {} }
    }, Rec)
end
function Rec:_rig(n)
    if not self.rigs[n] then
        self.rigs[n] = { jointTrack={}, scaleTrack={}, rootTrack={}, easingTrack={} }
    end
    return self.rigs[n]
end
function Rec:setEasing(rig, frame, e) self:_rig(rig).easingTrack[frame] = e end
function Rec:getEasing(rig, frame)
    local r = self.rigs[rig]
    return (r and r.easingTrack and r.easingTrack[frame]) or "Linear"
end
function Rec:setJointData(rig, frame, jd) self:_rig(rig).jointTrack[frame] = jd end
function Rec:getJointData(rig, frame)
    local r = self.rigs[rig]; return r and r.jointTrack[frame]
end
function Rec:getSortedFrames(rig)
    local r = self.rigs[rig]; if not r then return {} end
    local t = {}; for f in pairs(r.jointTrack) do t[#t+1]=f end
    table.sort(t); return t
end
function Rec:setPropEasing(p, frame, e)
    if not self.props[p] then self.props[p] = { propTrack={}, easingTrack={} } end
    self.props[p].easingTrack[frame] = e
end
function Rec:getPropEasing(p, frame)
    local d = self.props[p]
    return (d and d.easingTrack and d.easingTrack[frame]) or "Linear"
end
function Rec:setPropData(p, frame, cf)
    if not self.props[p] then self.props[p] = { propTrack={}, easingTrack={} } end
    self.props[p].propTrack[frame] = cf
end
function Rec:getPropData(p, frame)
    local d = self.props[p]; return d and d.propTrack[frame]
end
function Rec:getSortedPropFrames(p)
    local d = self.props[p]; if not d then return {} end
    local t={}; for f in pairs(d.propTrack) do t[#t+1]=f end; table.sort(t); return t
end
function Rec:addCameraKeyframe(frame, cf, fov, mode, easing)
    self.camera.track[frame] = { cf=cf, fov=fov or 70, mode=mode or "move", easing=easing or "Linear" }
end
function Rec:getCameraData(frame) return self.camera.track[frame] end
function Rec:setCameraEasing(frame, e)
    local kf = self.camera.track[frame]; if kf then kf.easing=e end; return kf ~= nil
end
function Rec:getCameraEasing(frame)
    local kf = self.camera.track[frame]; return (kf and kf.easing) or "Linear"
end
function Rec:getSortedCameraFrames()
    local t={}; for f in pairs(self.camera.track) do t[#t+1]=f end; table.sort(t); return t
end
function Rec:deleteRigKeyframe(rig, frame)
    local r = self.rigs[rig]; if not r then return end
    r.jointTrack[frame]=nil; r.easingTrack[frame]=nil
end
function Rec:deletePropKeyframe(p, frame)
    local d = self.props[p]; if not d then return end
    d.propTrack[frame]=nil; d.easingTrack[frame]=nil
end
function Rec:shiftFrames(from, delta)
    local function shift(track)
        if not track then return end
        local tmp={}
        for f,v in pairs(track) do if f>=from then tmp[f]=v end end
        for f in pairs(tmp) do track[f]=nil end
        for f,v in pairs(tmp) do track[f+delta]=v end
    end
    for _,r in pairs(self.rigs) do shift(r.jointTrack); shift(r.easingTrack) end
    for _,p in pairs(self.props) do shift(p.propTrack); shift(p.easingTrack) end
end

-- ── inline easedAlpha (pure math, mirrors MultiAnimPlayer) ────────────────────
local function easedAlpha(t, easing)
    if easing == "Constant" then return 0 end
    if easing == "EaseIn"   then return t * t * t end
    if easing == "EaseOut"  then local u = 1-t; return 1 - u*u*u end
    if easing == "EaseInOut" then
        if t < 0.5 then return 4*t*t*t end
        local u = -2*t+2; return 1 - u*u*u/2
    end
    if easing == "Bounce" then
        local n1, d1 = 7.5625, 2.75
        if t < 1/d1 then return n1*t*t
        elseif t < 2/d1 then t=t-1.5/d1; return n1*t*t+0.75
        elseif t < 2.5/d1 then t=t-2.25/d1; return n1*t*t+0.9375
        else t=t-2.625/d1; return n1*t*t+0.984375 end
    end
    return t
end

-- ── 1: Recorder rig easing CRUD ───────────────────────────────────────────────
local r = Rec.new()
check("default rig easing = Linear", r:getEasing("Rig1", 1) == "Linear")
r:setEasing("Rig1", 1, "EaseIn")
check("setEasing stores", r:getEasing("Rig1", 1) == "EaseIn")
r:setEasing("Rig1", 5, "Bounce")
check("easing at f5", r:getEasing("Rig1", 5) == "Bounce")
check("missing frame still Linear", r:getEasing("Rig1", 99) == "Linear")

-- 2: Recorder prop easing CRUD
r:setPropEasing("Prop1", 3, "EaseOut")
check("prop easing stores", r:getPropEasing("Prop1", 3) == "EaseOut")
check("prop easing default", r:getPropEasing("Prop1", 99) == "Linear")

-- 3: Camera easing CRUD
r:addCameraKeyframe(10, CFrame.identity, 70, "move", "EaseInOut")
check("camera easing stored", r:getCameraEasing(10) == "EaseInOut")
r:setCameraEasing(10, "Bounce")
check("setCameraEasing", r:getCameraEasing(10) == "Bounce")
check("setCameraEasing missing = false", r:setCameraEasing(99, "Bounce") == false)

-- 4: deleteRigKeyframe clears easing
r:setJointData("Rig1", 1, { RootJoint = CFrame.identity })
r:setEasing("Rig1", 1, "EaseIn")
r:deleteRigKeyframe("Rig1", 1)
check("deleteRigKeyframe clears easing", r:getEasing("Rig1", 1) == "Linear")

-- 5: deletePropKeyframe clears easing
r:setPropData("Prop1", 3, CFrame.identity)
r:setPropEasing("Prop1", 3, "EaseOut")
r:deletePropKeyframe("Prop1", 3)
check("deletePropKeyframe clears easing", r:getPropEasing("Prop1", 3) == "Linear")

-- 6: shiftFrames shifts easings
local r2 = Rec.new()
r2:setJointData("Rig1", 5, { RootJoint = CFrame.identity })
r2:setEasing("Rig1", 5, "EaseIn")
r2:setJointData("Rig1", 10, { RootJoint = CFrame.identity })
r2:setEasing("Rig1", 10, "EaseOut")
r2:shiftFrames(5, 2)
check("shiftFrames moves easing", r2:getEasing("Rig1", 7) == "EaseIn")
check("shiftFrames moves later easing", r2:getEasing("Rig1", 12) == "EaseOut")
check("shiftFrames clears original", r2:getEasing("Rig1", 5) == "Linear")

-- 7: easedAlpha boundary values
check("Linear t=0 → 0", easedAlpha(0, "Linear") == 0)
check("Linear t=1 → 1", easedAlpha(1, "Linear") == 1)
check("Linear t=0.5", math.abs(easedAlpha(0.5, "Linear") - 0.5) < 1e-6)
check("Constant t=0.5 → 0", easedAlpha(0.5, "Constant") == 0)
check("Constant t=1 → 0", easedAlpha(1, "Constant") == 0)

-- 8: EaseIn is cubic
check("EaseIn t=0 → 0", easedAlpha(0, "EaseIn") == 0)
check("EaseIn t=1 → 1", math.abs(easedAlpha(1, "EaseIn") - 1) < 1e-6)
check("EaseIn t=0.5 < 0.5", easedAlpha(0.5, "EaseIn") < 0.5)

-- 9: EaseOut
check("EaseOut t=0 → 0", easedAlpha(0, "EaseOut") == 0)
check("EaseOut t=1 → 1", math.abs(easedAlpha(1, "EaseOut") - 1) < 1e-6)
check("EaseOut t=0.5 > 0.5", easedAlpha(0.5, "EaseOut") > 0.5)

-- 10: EaseInOut symmetry
local ein = easedAlpha(0.25, "EaseInOut")
local eout = 1 - easedAlpha(0.75, "EaseInOut")
check("EaseInOut antisymmetry", math.abs(ein - eout) < 1e-6)

-- 11: Bounce >= 0 everywhere
local ok = true
for i = 0, 10 do if easedAlpha(i/10, "Bounce") < 0 then ok = false end end
check("Bounce non-negative", ok)

-- 12: Bounce at t=1 approaches 1
check("Bounce t=1 → ~1", math.abs(easedAlpha(1, "Bounce") - 0.984375) < 0.02
    or math.abs(easedAlpha(1, "Bounce") - 1) < 0.02)

-- 13: toSortedKFs backward compat (old format has no .data wrapper)
local function simulateToSortedKFs(frameTable, fps, buildFn)
    local out = {}
    for frame, raw in pairs(frameTable) do
        local actualData = raw.data or raw
        local easing = (type(raw.easing) == "string" and raw.easing) or "Linear"
        out[#out+1] = { time = (frame-1)/fps, data = buildFn(actualData), easing = easing }
    end
    table.sort(out, function(a,b) return a.time < b.time end)
    return out
end

local oldFmt = { [1] = {1,2,3,0,1,0,0,0,1,0,0,0}, [5] = {4,5,6,1,0,0,0,1,0,0,0,1} }
local parsed = simulateToSortedKFs(oldFmt, 24, function(arr)
    return CFrame.new(arr[1],arr[2],arr[3], arr[4],arr[5],arr[6], arr[7],arr[8],arr[9], arr[10],arr[11],arr[12])
end)
check("old format parsed", #parsed == 2)
check("old format easing defaults Linear", parsed[1].easing == "Linear")

local newFmt = {
    [1] = { easing="EaseIn",  data={1,2,3,0,1,0,0,0,1,0,0,0} },
    [5] = { easing="Bounce", data={4,5,6,1,0,0,0,1,0,0,0,1} },
}
local parsed2 = simulateToSortedKFs(newFmt, 24, function(arr)
    return CFrame.new(arr[1],arr[2],arr[3], arr[4],arr[5],arr[6], arr[7],arr[8],arr[9], arr[10],arr[11],arr[12])
end)
check("new format easing EaseIn", parsed2[1].easing == "EaseIn")
check("new format easing Bounce", parsed2[2].easing == "Bounce")

-- 14: multiple rigs independent easings
local r3 = Rec.new()
r3:setEasing("Rig1", 5, "EaseIn")
r3:setEasing("Rig2", 5, "EaseOut")
check("per-rig easing independent", r3:getEasing("Rig1", 5) ~= r3:getEasing("Rig2", 5))

-- Result
local total = pass + fail
if fail == 0 then
    return string.format("ALL TESTS PASSED (%d/%d)", pass, total)
else
    return string.format("FAILED %d/%d\n%d passed", fail, total, pass)
end
