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
    }

    self._restPoses = {}   -- { [rigName] = jointData } captured at session start

    return self
end

-- Call once per rig when recording begins to store the rest pose.
function Recorder:captureRestPose(rigName, model)
    self._restPoses[rigName] = JointCapture.captureRestPose(model)
end

function Recorder:getRestPose(rigName)
    return self._restPoses[rigName]
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

function Recorder:clearSession()
    self._session.rigs  = {}
    self._session.props = {}
    self._restPoses     = {}
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
