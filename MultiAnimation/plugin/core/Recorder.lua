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
        fps        = 24,
        frameCount = 120,
        rigs       = {},
        props      = {},
        camera     = { track = {} },   -- [frame] = {cf=CFrame, fov=number, mode="move"|"cut"}
        effects    = {},               -- [name] = {kind, action, path, track={[frame]={action,count}}}
    }

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
            self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {} }
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

-- Remove all data for a specific frame across all rigs.
function Recorder:deleteKeyframe(frame)
    for _, rig in pairs(self._session.rigs) do
        rig.jointTrack[frame] = nil
        rig.scaleTrack[frame] = nil
    end
end

-- Remove the keyframe at `frame` for a single rig only.
function Recorder:deleteRigKeyframe(rigName, frame)
    local rig = self._session.rigs[rigName]
    if rig then
        rig.jointTrack[frame] = nil
        rig.scaleTrack[frame] = nil
        if rig.rootTrack then rig.rootTrack[frame] = nil end
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
        self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {} }
    end
    local rig = self._session.rigs[rigName]
    rig.rootTrack = rig.rootTrack or {}
    rig.rootTrack[frame] = cf
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
    if prop then prop.propTrack[frame] = nil end
end

-- Camera track accessors. One track for the whole session;
-- each keyframe = {cf, fov, mode} where mode is "move" (interpolate from the
-- previous keyframe) or "cut" (hard jump at this frame).
function Recorder:addCameraKeyframe(frame, cf, fov, mode)
    self._session.camera = self._session.camera or { track = {} }
    self._session.camera.track[frame] = {
        cf   = cf,
        fov  = fov or 70,
        mode = mode or "move",
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
    self._session.rigs    = {}
    self._session.props   = {}
    self._session.camera  = { track = {} }
    self._session.effects = {}
    self._restPoses       = {}
end

function Recorder:setJointData(rigName, frame, jointData)
    if not self._session.rigs[rigName] then
        self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {} }
    end
    self._session.rigs[rigName].jointTrack[frame] = jointData
end

function Recorder:setScaleData(rigName, frame, scaleData)
    if not self._session.rigs[rigName] then
        self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {}, rootTrack = {} }
    end
    self._session.rigs[rigName].scaleTrack[frame] = scaleData
end

function Recorder:destroy()
    self._added:Destroy()
end

return Recorder
