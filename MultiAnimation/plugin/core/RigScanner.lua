-- RigScanner — finds R6 character rigs in Workspace.FIGURES.
--
-- R6 criterion:
--   Model that contains a Humanoid, a Part named "Torso",
--   and at least one Motor6D inside that Torso.
--   (R15 uses "UpperTorso", so Torso presence is the R6 discriminator.)

local RigScanner = {}

local function hasMotor6D(torso)
    for _, child in ipairs(torso:GetChildren()) do
        if child:IsA("Motor6D") then
            return true
        end
    end
    return false
end

local function isR6Rig(instance)
    if not instance:IsA("Model") then return false end
    if not instance:FindFirstChildOfClass("Humanoid") then return false end
    local torso = instance:FindFirstChild("Torso")
    if not torso or not torso:IsA("BasePart") then return false end
    return hasMotor6D(torso)
end

-- Returns { [rigName] = ModelInstance } for every R6 rig found in
-- Workspace.FIGURES. Returns an empty table (not nil) if the folder is
-- absent or empty, to keep callers simple.
function RigScanner.scan()
    local rigs = {}

    local figures = workspace:FindFirstChild("FIGURES")
    if not figures then
        warn("[MultiAnimation] Workspace.FIGURES not found — no rigs available")
        return rigs
    end

    for _, child in ipairs(figures:GetChildren()) do
        if isR6Rig(child) then
            rigs[child.Name] = child
        end
    end

    local count = 0
    for _ in pairs(rigs) do count += 1 end
    print(string.format("[MultiAnimation] Found %d R6 rig(s) in Workspace.FIGURES", count))

    return rigs
end

return RigScanner
