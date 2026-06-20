-- RigScanner — finds R6 character rigs in the workspace.
--
-- R6 criterion:
--   Model that contains a Humanoid, a Part named "Torso",
--   and at least one Motor6D inside that Torso.
--   (R15 uses "UpperTorso", so Torso presence is the R6 discriminator.)
--
-- scan()            — legacy: all R6 rigs in Workspace.FIGURES
-- scanByTag(scene)  — tag-based: rigs tagged "MAnim:<scene>" anywhere in workspace
-- isR6(instance)    — public predicate used by tagging logic

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

-- Public: lets tagging / prop-detection code classify an instance.
RigScanner.isR6 = isR6Rig

-- Legacy scan: all R6 rigs in Workspace.FIGURES. Used when no scene name is set.
function RigScanner.scan()
    local rigs = {}
    local figures = workspace:FindFirstChild("FIGURES")
    if not figures then
        warn("[MultiAnimation] Workspace.FIGURES not found — no rigs available")
        return rigs
    end
    for _, child in ipairs(figures:GetChildren()) do
        if isR6Rig(child) then rigs[child.Name] = child end
    end
    local count = 0
    for _ in pairs(rigs) do count += 1 end
    print(string.format("[MultiAnimation] Found %d R6 rig(s) in Workspace.FIGURES", count))
    return rigs
end

-- Tag-based scan: R6 rigs tagged "MAnim:<sceneName>" anywhere in the workspace.
function RigScanner.scanByTag(sceneName)
    local tag  = "MAnim:" .. sceneName
    local rigs = {}
    for _, inst in ipairs(CollectionService:GetTagged(tag)) do
        if isR6Rig(inst) then
            rigs[inst.Name] = inst
        end
    end
    local count = 0
    for _ in pairs(rigs) do count += 1 end
    print(string.format("[MultiAnimation] Found %d R6 rig(s) tagged MAnim:%s", count, sceneName))
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
