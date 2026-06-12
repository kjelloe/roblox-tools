-- CameraCapture — reads/writes the Studio viewport camera (workspace.CurrentCamera).
--
-- Used for two things:
--   capture()  — snapshot the current viewport as a camera keyframe ({cf, fov})
--   apply()    — drive the viewport along the camera track (Camera Preview mode)
--
-- saveState/restoreState bracket Camera Preview so toggling it off puts the
-- user's viewport back exactly where it was.

local CameraCapture = {}

function CameraCapture.capture()
    local cam = workspace.CurrentCamera
    return { cf = cam.CFrame, fov = cam.FieldOfView }
end

function CameraCapture.apply(cf, fov)
    local cam = workspace.CurrentCamera
    cam.CFrame = cf
    if fov then
        cam.FieldOfView = fov
    end
end

function CameraCapture.saveState()
    local cam = workspace.CurrentCamera
    return {
        cf      = cam.CFrame,
        fov     = cam.FieldOfView,
        focus   = cam.Focus,
        camType = cam.CameraType,
    }
end

function CameraCapture.restoreState(state)
    if not state then return end
    local cam = workspace.CurrentCamera
    cam.CFrame      = state.cf
    cam.FieldOfView = state.fov
    cam.Focus       = state.focus
    cam.CameraType  = state.camType
end

return CameraCapture
