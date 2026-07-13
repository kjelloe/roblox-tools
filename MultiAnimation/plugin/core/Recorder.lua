-- Recorder — owns the session data and drives JointCapture / ScaleCapture.
--
-- Session shape (matches DATA_FORMAT.md):
--   session.fps, session.frameCount
--   session.rigs[rigName].jointTrack[frame] = { [jointName]=CFrame }
--   session.rigs[rigName].scaleTrack[frame] = { [partName]=Vector3 }
--
-- addKeyframe fires onKeyframeAdded with (rigName, frame) for each recorded rig.

local JointCapture = require(script.Parent.JointCapture)
local ScaleCapture = require(script.Parent.ScaleCapture)
local PropCapture  = require(script.Parent.PropCapture)

local Recorder = {}
Recorder.__index = Recorder

function Recorder.new()
    local self = setmetatable({}, Recorder)

    local added = Instance.new("BindableEvent")
    self.onKeyframeAdded = added.Event
    self._added = added

    self._session = {
        fps            = 24,
        frameCount     = 120,
        rigs           = {},
        props          = {},
        camera         = { track = {} },   -- [frame] = {cf=CFrame, fov=number, mode="move"|"cut"}
        effects        = {},               -- [name] = {kind, action, path, track={[frame]={action,count}}}
        spawnedEffects = {},               -- array of {id, frame, effectType, posX/Y/Z, ...}
        subtitlesEnabled = false,
        subtitleStyle    = {
            fontAsset         = "rbxasset://fonts/families/GothamSSm.json",
            fontWeight        = "Regular",
            size              = 28,
            textColorR        = 255, textColorG = 255, textColorB = 255,
            textTransparency  = 0,
            strokeColorR      = 0,   strokeColorG = 0,  strokeColorB = 0,
            strokeTransparency = 0,
            bgColorR          = 0,   bgColorG = 0,  bgColorB = 0,
            bgTransparency    = 0.6,
            xOffset           = 0.05,
            yOffset           = 0.85,
        },
        subtitles = {},  -- sorted array of {frame, text}
    }
    self._nextSpawnedEffectId = 1

    self._restPoses = {}   -- { [rigName] = jointData } captured at session start

    return self
end

-- Call once per rig when recording begins to store the rest pose.
-- Returns {joints={[jointName]=CFrame}, scales={[partName]=Vector3}}.
function Recorder:captureRestPose(rigName, model)
    self._restPoses[rigName] = {
        joints = JointCapture.captureRestPose(model),
        scales = ScaleCapture.capture(model),
    }
end

function Recorder:getRestPose(rigName)
    return self._restPoses[rigName]   -- {joints=..., scales=...}
end

-- Record current pose of all activeRigs (and activeProps) at the given frame.
-- Overwrites existing data for that frame (idempotent per rig/prop).
function Recorder:addKeyframe(frame, activeRigs, activeProps)
    for rigName, model in pairs(activeRigs) do
        if not self._session.rigs[rigName] then
            self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {}, easingTrack = {} }
        end

        local rig = self._session.rigs[rigName]
        rig.jointTrack[frame] = JointCapture.capture(model)
        rig.scaleTrack[frame] = ScaleCapture.capture(model)

        -- Capture world-space HumanoidRootPart CFrame so whole-model movement is recorded.
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then
            rig.rootTrack = rig.rootTrack or {}
            rig.rootTrack[frame] = hrp.CFrame
        end

        self._added:Fire(rigName, frame)
    end

    for propName, part in pairs(activeProps or {}) do
        if not self._session.props[propName] then
            self._session.props[propName] = { propTrack = {} }
        end
        self._session.props[propName].propTrack[frame] = PropCapture.capture(part)
    end
end

function Recorder:hasKeyframe(rigName, frame)
    local rig = self._session.rigs[rigName]
    return rig and rig.jointTrack[frame] ~= nil
end

-- Returns a sorted list of frame numbers that have keyframes for rigName.
function Recorder:getSortedFrames(rigName)
    local rig = self._session.rigs[rigName]
    if not rig then return {} end
    local frames = {}
    for f in pairs(rig.jointTrack) do
        table.insert(frames, f)
    end
    table.sort(frames)
    return frames
end

function Recorder:getJointData(rigName, frame)
    local rig = self._session.rigs[rigName]
    return rig and rig.jointTrack[frame]
end

function Recorder:getScaleData(rigName, frame)
    local rig = self._session.rigs[rigName]
    return rig and rig.scaleTrack[frame]
end

function Recorder:getSession()
    return self._session
end

function Recorder:setFps(fps)
    self._session.fps = fps
end

function Recorder:setFrameCount(n)
    self._session.frameCount = n
end

-- Remove the keyframe at `frame` for a single rig only.
function Recorder:deleteRigKeyframe(rigName, frame)
    local rig = self._session.rigs[rigName]
    if rig then
        rig.jointTrack[frame] = nil
        rig.scaleTrack[frame] = nil
        if rig.rootTrack then rig.rootTrack[frame] = nil end
        if rig.easingTrack then rig.easingTrack[frame] = nil end
    end
end

-- Root track accessors (world-space HumanoidRootPart CFrame per frame).
function Recorder:getSortedRootFrames(rigName)
    local rig = self._session.rigs[rigName]
    if not rig or not rig.rootTrack then return {} end
    local frames = {}
    for f in pairs(rig.rootTrack) do table.insert(frames, f) end
    table.sort(frames)
    return frames
end

function Recorder:getRootData(rigName, frame)
    local rig = self._session.rigs[rigName]
    return rig and rig.rootTrack and rig.rootTrack[frame]
end

function Recorder:setRootData(rigName, frame, cf)
    if not self._session.rigs[rigName] then
        self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {}, easingTrack = {} }
    end
    local rig = self._session.rigs[rigName]
    rig.rootTrack = rig.rootTrack or {}
    rig.rootTrack[frame] = cf
end

function Recorder:getEasing(rigName, frame)
    local rig = self._session.rigs[rigName]
    return (rig and rig.easingTrack and rig.easingTrack[frame]) or "Linear"
end

function Recorder:setEasing(rigName, frame, easing)
    local rig = self._session.rigs[rigName]
    if rig then
        rig.easingTrack = rig.easingTrack or {}
        rig.easingTrack[frame] = easing
    end
end

-- Prop track accessors.
function Recorder:getSortedPropFrames(propName)
    local prop = self._session.props and self._session.props[propName]
    if not prop then return {} end
    local frames = {}
    for f in pairs(prop.propTrack) do table.insert(frames, f) end
    table.sort(frames)
    return frames
end

function Recorder:getPropData(propName, frame)
    local prop = self._session.props and self._session.props[propName]
    return prop and prop.propTrack[frame]
end

function Recorder:setPropData(propName, frame, cf)
    if not self._session.props then self._session.props = {} end
    if not self._session.props[propName] then
        self._session.props[propName] = { propTrack = {} }
    end
    self._session.props[propName].propTrack[frame] = cf
end

function Recorder:deletePropKeyframe(propName, frame)
    local prop = self._session.props and self._session.props[propName]
    if prop then
        prop.propTrack[frame] = nil
        if prop.easingTrack then prop.easingTrack[frame] = nil end
    end
end

function Recorder:getPropEasing(propName, frame)
    local prop = self._session.props and self._session.props[propName]
    return (prop and prop.easingTrack and prop.easingTrack[frame]) or "Linear"
end

function Recorder:setPropEasing(propName, frame, easing)
    if not self._session.props then self._session.props = {} end
    if not self._session.props[propName] then
        self._session.props[propName] = { propTrack = {}, easingTrack = {} }
    end
    local prop = self._session.props[propName]
    prop.easingTrack = prop.easingTrack or {}
    prop.easingTrack[frame] = easing
end

function Recorder:deleteProp(propName)
    if self._session.props then
        self._session.props[propName] = nil
    end
end

-- Camera track accessors. One track for the whole session;
-- each keyframe = {cf, fov, mode} where mode is "move" (interpolate from the
-- previous keyframe) or "cut" (hard jump at this frame).
function Recorder:addCameraKeyframe(frame, cf, fov, mode, easing)
    self._session.camera = self._session.camera or { track = {} }
    self._session.camera.track[frame] = {
        cf     = cf,
        fov    = fov or 70,
        mode   = mode or "move",
        easing = easing or "Linear",
    }
end

function Recorder:getCameraData(frame)
    local cam = self._session.camera
    return cam and cam.track[frame]
end

function Recorder:getSortedCameraFrames()
    local cam = self._session.camera
    if not cam then return {} end
    local frames = {}
    for f in pairs(cam.track) do table.insert(frames, f) end
    table.sort(frames)
    return frames
end

function Recorder:setCameraMode(frame, mode)
    local kf = self:getCameraData(frame)
    if kf then kf.mode = mode end
    return kf ~= nil
end

function Recorder:getCameraEasing(frame)
    local kf = self:getCameraData(frame)
    return (kf and kf.easing) or "Linear"
end

function Recorder:setCameraEasing(frame, easing)
    local kf = self:getCameraData(frame)
    if kf then kf.easing = easing end
    return kf ~= nil
end

function Recorder:deleteCameraKeyframe(frame)
    local cam = self._session.camera
    if cam then cam.track[frame] = nil end
end

-- Effect track accessors. Each effect is a named instance (ParticleEmitter,
-- Sound, light, …) with one-shot events keyed by frame.
function Recorder:registerEffect(name, kind, action, path)
    self._session.effects = self._session.effects or {}
    local existing = self._session.effects[name]
    if existing then
        existing.kind = kind; existing.action = action; existing.path = path
    else
        self._session.effects[name] = { kind = kind, action = action, path = path, track = {} }
    end
    return self._session.effects[name]
end

function Recorder:getEffect(name)
    return self._session.effects and self._session.effects[name]
end

function Recorder:setEffectAction(name, action)
    local fx = self:getEffect(name)
    if fx then fx.action = action end
    return fx ~= nil
end

function Recorder:setEffectEvent(name, frame, event)
    local fx = self:getEffect(name)
    if not fx then return false end
    fx.track[frame] = event
    return true
end

function Recorder:getEffectEvent(name, frame)
    local fx = self:getEffect(name)
    return fx and fx.track[frame]
end

function Recorder:getSortedEffectFrames(name)
    local fx = self:getEffect(name)
    if not fx then return {} end
    local frames = {}
    for f in pairs(fx.track) do table.insert(frames, f) end
    table.sort(frames)
    return frames
end

function Recorder:deleteEffectEvent(name, frame)
    local fx = self:getEffect(name)
    if fx then fx.track[frame] = nil end
end

function Recorder:clearSession()
    self._session.rigs            = {}
    self._session.props           = {}
    self._session.camera          = { track = {} }
    self._session.effects         = {}
    self._session.spawnedEffects  = {}
    self._nextSpawnedEffectId     = 1
    self._restPoses               = {}
    self._session.subtitlesEnabled = false
    self._session.subtitles        = {}
    self._session.subtitleStyle    = {
        fontAsset         = "rbxasset://fonts/families/GothamSSm.json",
        fontWeight        = "Regular",
        size              = 28,
        textColorR        = 255, textColorG = 255, textColorB = 255,
        textTransparency  = 0,
        strokeColorR      = 0,   strokeColorG = 0,  strokeColorB = 0,
        strokeTransparency = 0,
        bgColorR          = 0,   bgColorG = 0,  bgColorB = 0,
        bgTransparency    = 0.6,
        xOffset           = 0.05,
        yOffset           = 0.85,
    }
end

-- ── SpawnedEffects CRUD ───────────────────────────────────────────────────────

function Recorder:addSpawnedEffect(data)
    local fx = {}
    for k, v in pairs(data) do fx[k] = v end
    if not fx.id then
        fx.id = self._nextSpawnedEffectId
        self._nextSpawnedEffectId = self._nextSpawnedEffectId + 1
    elseif fx.id >= self._nextSpawnedEffectId then
        self._nextSpawnedEffectId = fx.id + 1
    end
    table.insert(self._session.spawnedEffects, fx)
    return fx
end

function Recorder:updateSpawnedEffect(id, newData)
    for i, fx in ipairs(self._session.spawnedEffects) do
        if fx.id == id then
            for k, v in pairs(newData) do fx[k] = v end
            fx.id = id  -- preserve id
            self._session.spawnedEffects[i] = fx
            return fx
        end
    end
end

function Recorder:deleteSpawnedEffect(id)
    for i, fx in ipairs(self._session.spawnedEffects) do
        if fx.id == id then
            table.remove(self._session.spawnedEffects, i)
            return
        end
    end
end

function Recorder:getSpawnedEffects()
    return self._session.spawnedEffects
end

function Recorder:getSpawnedEffectById(id)
    for _, fx in ipairs(self._session.spawnedEffects) do
        if fx.id == id then return fx end
    end
    return nil
end

function Recorder:setJointData(rigName, frame, jointData)
    if not self._session.rigs[rigName] then
        self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {}, easingTrack = {} }
    end
    self._session.rigs[rigName].jointTrack[frame] = jointData
end

function Recorder:setScaleData(rigName, frame, scaleData)
    if not self._session.rigs[rigName] then
        self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {}, easingTrack = {} }
    end
    self._session.rigs[rigName].scaleTrack[frame] = scaleData
end

-- Shift all frame data at frames >= fromFrame by delta (positive=insert space,
-- negative=close a gap). Collect→clear→write in that order so frames don't
-- collide when delta<0 and the destination range overlaps the source range.
function Recorder:shiftFrames(fromFrame, delta)
    local function shiftTrack(track)
        if not track then return end
        local toMove = {}
        for f, v in pairs(track) do
            if f >= fromFrame then toMove[f] = v end
        end
        for f in pairs(toMove) do track[f] = nil end
        for f, v in pairs(toMove) do track[f + delta] = v end
    end
    for _, rig in pairs(self._session.rigs or {}) do
        shiftTrack(rig.jointTrack)
        shiftTrack(rig.scaleTrack)
        shiftTrack(rig.rootTrack)
        shiftTrack(rig.easingTrack)
    end
    for _, prop in pairs(self._session.props or {}) do
        shiftTrack(prop.propTrack)
        shiftTrack(prop.easingTrack)
    end
    local cam = self._session.camera
    if cam then shiftTrack(cam.track) end
    for _, fx in pairs(self._session.effects or {}) do
        shiftTrack(fx.track)
    end
    for _, sfx in ipairs(self._session.spawnedEffects or {}) do
        if sfx.frame >= fromFrame then sfx.frame = sfx.frame + delta end
    end
    for _, ev in ipairs(self._session.subtitles or {}) do
        if ev.frame >= fromFrame then ev.frame = ev.frame + delta end
    end
end

-- Delete all track data at exactly `frame` across every track type.
function Recorder:deleteFrameAt(frame)
    for _, rig in pairs(self._session.rigs or {}) do
        rig.jointTrack[frame] = nil
        rig.scaleTrack[frame] = nil
        if rig.rootTrack then rig.rootTrack[frame] = nil end
        if rig.easingTrack then rig.easingTrack[frame] = nil end
    end
    for _, prop in pairs(self._session.props or {}) do
        if prop.propTrack then prop.propTrack[frame] = nil end
        if prop.easingTrack then prop.easingTrack[frame] = nil end
    end
    local cam = self._session.camera
    if cam and cam.track then cam.track[frame] = nil end
    for _, fx in pairs(self._session.effects or {}) do
        if fx.track then fx.track[frame] = nil end
    end
    local spawned = self._session.spawnedEffects or {}
    for i = #spawned, 1, -1 do
        if spawned[i].frame == frame then table.remove(spawned, i) end
    end
    self:removeSubtitleEvent(frame)
end

function Recorder:destroy()
    self._added:Destroy()
end

-- ── Subtitles ─────────────────────────────────────────────────────────────────

function Recorder:setSubtitlesEnabled(enabled)
    self._session.subtitlesEnabled = enabled == true
end

function Recorder:getSubtitlesEnabled()
    return self._session.subtitlesEnabled
end

function Recorder:setSubtitleStyle(style)
    for k, v in pairs(style) do
        self._session.subtitleStyle[k] = v
    end
end

function Recorder:getSubtitleStyle()
    return self._session.subtitleStyle
end

-- Add or update the subtitle event at `frame`. Keeps list sorted by frame.
function Recorder:setSubtitleEvent(frame, text)
    local subs = self._session.subtitles
    for i, ev in ipairs(subs) do
        if ev.frame == frame then
            ev.text = text
            return
        elseif ev.frame > frame then
            table.insert(subs, i, { frame = frame, text = text })
            return
        end
    end
    table.insert(subs, { frame = frame, text = text })
end

function Recorder:removeSubtitleEvent(frame)
    local subs = self._session.subtitles
    for i, ev in ipairs(subs) do
        if ev.frame == frame then
            table.remove(subs, i)
            return
        end
    end
end

-- Returns the event at exactly `frame`, or nil.
function Recorder:getSubtitleEventAt(frame)
    for _, ev in ipairs(self._session.subtitles) do
        if ev.frame == frame then return ev end
    end
    return nil
end

-- Returns the active subtitle text at `frame` (stepped: most recent event ≤ frame).
-- Returns nil if no subtitle is active. An empty-text event acts as a "clear"
-- marker — it hides the subtitle rather than showing an empty bar.
function Recorder:getActiveSubtitleAt(frame)
    local active = nil
    for _, ev in ipairs(self._session.subtitles) do
        if ev.frame <= frame then
            active = ev
        else
            break
        end
    end
    if active and active.text ~= "" then return active.text end
    return nil
end

function Recorder:getSubtitleEvents()
    return self._session.subtitles
end

function Recorder:renameRig(oldName, newName)
    if not self._session.rigs[oldName] then return end
    self._session.rigs[newName] = self._session.rigs[oldName]
    self._session.rigs[oldName] = nil
    if self._restPoses[oldName] then
        self._restPoses[newName] = self._restPoses[oldName]
        self._restPoses[oldName] = nil
    end
end

function Recorder:renameProp(oldName, newName)
    if not (self._session.props and self._session.props[oldName]) then return end
    self._session.props[newName] = self._session.props[oldName]
    self._session.props[oldName] = nil
end

return Recorder
