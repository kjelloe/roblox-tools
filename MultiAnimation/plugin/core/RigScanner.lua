-- RigScanner — finds animatable character rigs in the workspace.
--
-- R6 criterion:  Model with Humanoid + BasePart "Torso" (no UpperTorso).
-- R15 criterion: Model with Humanoid + BasePart "UpperTorso".
-- Animatable rig: R6 or R15 (any rig with at least one qualifying Motor6D).
--
-- scan()               — legacy: all animatable rigs in Workspace.FIGURES
-- scanByTag(scene)     — tag-based: rigs tagged "MAnim:<scene>" anywhere in workspace
-- isR6(instance)       — R6 predicate (public, used by tagging logic)
-- isR15(instance)      — R15 predicate (public)
-- isAnimatableRig(inst)— true for R6 or R15 (used for scan/tag logic)

local RigScanner = {}

local CollectionService = game:GetService("CollectionService")

local function hasMotor6D(torso)
    for _, child in ipairs(torso:GetChildren()) do
        if child:IsA("Motor6D") then return true end
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

local function isR15Rig(instance)
    if not instance:IsA("Model") then return false end
    if not instance:FindFirstChildOfClass("Humanoid") then return false end
    local upperTorso = instance:FindFirstChild("UpperTorso")
    if not upperTorso or not upperTorso:IsA("BasePart") then return false end
    -- Also require at least one qualifying Motor6D (direct-child-to-direct-child)
    for _, inst in ipairs(instance:GetDescendants()) do
        if inst:IsA("Motor6D") then
            local container = inst.Parent
            local p1        = inst.Part1
            if container and container.Parent == instance
               and p1 and p1.Parent == instance then
                return true
            end
        end
    end
    return false
end

local function isAnimatableRig(instance)
    return isR6Rig(instance) or isR15Rig(instance)
end

-- Public predicates
RigScanner.isR6           = isR6Rig
RigScanner.isR15          = isR15Rig
RigScanner.isAnimatableRig = isAnimatableRig

-- Legacy scan: all animatable rigs in Workspace.FIGURES. Used when no scene name is set.
function RigScanner.scan()
    local rigs = {}
    local figures = workspace:FindFirstChild("FIGURES")
    if not figures then
        warn("[MultiAnimation] Workspace.FIGURES not found — no rigs available")
        return rigs
    end
    for _, child in ipairs(figures:GetChildren()) do
        if isAnimatableRig(child) then rigs[child.Name] = child end
    end
    local count = 0
    for _ in pairs(rigs) do count += 1 end
    print(string.format("[MultiAnimation] Found %d rig(s) in Workspace.FIGURES", count))
    return rigs
end

-- Tag-based scan: animatable rigs tagged "MAnim:<sceneName>" anywhere in the workspace.
function RigScanner.scanByTag(sceneName)
    local tag  = "MAnim:" .. sceneName
    local rigs = {}
    for _, inst in ipairs(CollectionService:GetTagged(tag)) do
        if isAnimatableRig(inst) then
            rigs[inst.Name] = inst
        end
    end
    local count = 0
    for _ in pairs(rigs) do count += 1 end
    print(string.format("[MultiAnimation] Found %d rig(s) tagged MAnim:%s", count, sceneName))
    return rigs
end

-- Returns a sorted list of first-level workspace folders (Folder or Model).
-- Used to populate the "Tag all in" dropdown in Simple Mode.
function RigScanner.getWorkspaceFolders()
    local folders = {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") then
            table.insert(folders, child.Name)
        end
    end
    table.sort(folders)
    return folders
end

return RigScanner
