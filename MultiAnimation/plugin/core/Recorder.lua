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

-- Record current pose of all activeRigs at the given frame.
-- Overwrites existing data for that frame (idempotent per rig).
function Recorder:addKeyframe(frame, activeRigs)
    for rigName, model in pairs(activeRigs) do
        if not self._session.rigs[rigName] then
            self._session.rigs[rigName] = { jointTrack = {}, scaleTrack = {} }
        end

        local rig = self._session.rigs[rigName]
        rig.jointTrack[frame] = JointCapture.capture(model)
        rig.scaleTrack[frame] = ScaleCapture.capture(model)

        self._added:Fire(rigName, frame)
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

function Recorder:destroy()
    self._added:Destroy()
end

return Recorder
