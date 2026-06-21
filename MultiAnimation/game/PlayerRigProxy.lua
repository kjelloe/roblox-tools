-- PlayerRigProxy — resolves rigMap player entries into character Models for
-- local-only, client-side animation. Plain Instance entries pass through unchanged.
-- Supports R6 and R15 player characters.
--
-- Entry formats in the rigMap:
--   Instance (Model/BasePart)               → passed through, no teardown
--   { player = Player,  mode = "clone" }    → clone character locally at anchorCF
--   { player = Player,  mode = "direct" }   → animate player's own character
--   { userId = number,  mode = "clone"|"direct" }  → look up player by UserId first
--
-- Clone mode: original character is hidden + anchored; restored on teardown.
-- Direct mode: PlatformStand suppresses Humanoid physics during animation.

local PlayerRigProxy = {}

local Players = game:GetService("Players")

local function savePartStates(character)
    local saved = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            saved[part] = { transparency = part.Transparency, anchored = part.Anchored }
        end
    end
    return saved
end

local function hideCharacter(character)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Transparency = 1
            part.Anchored     = true
        end
    end
end

local function restoreCharacter(character, saved)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            local s = saved[part]
            if s then
                part.Transparency = s.transparency
                part.Anchored     = s.anchored
            end
        end
    end
end

local function findPlayerByUserId(userId)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.UserId == userId then return player end
    end
    return nil
end

-- Resolve a single rigMap entry.
--   entry:    an Instance (fixed) or a table {player/userId, mode}
--   anchorCF: CFrame where the resolved rig should start (for clone/direct mode)
-- Returns: resolvedModel | nil, teardownFn
function PlayerRigProxy.resolve(entry, anchorCF)
    -- Fixed rig: pass through unchanged
    if typeof(entry) == "Instance" then
        return entry, function() end
    end

    if type(entry) ~= "table" then
        warn("[PlayerRigProxy] Unknown entry type: " .. tostring(entry))
        return nil, function() end
    end

    local mode = entry.mode or "clone"

    -- Resolve the player object
    local player
    if entry.player then
        player = entry.player
    elseif entry.userId then
        player = findPlayerByUserId(entry.userId)
        if not player then
            warn("[PlayerRigProxy] No player with UserId " .. tostring(entry.userId)
                .. " — is that player in this server?")
            return nil, function() end
        end
    end

    if not player then
        warn("[PlayerRigProxy] Entry has no player or userId")
        return nil, function() end
    end

    local character = player.Character
    if not character then
        -- Character may still be loading — wait up to 10 s before giving up.
        local timer = 0
        repeat
            task.wait(0.05)
            timer += 0.05
            character = player.Character
        until character or timer >= 10
        if not character then
            warn("[PlayerRigProxy] Player '" .. player.Name .. "' has no character after 10s")
            return nil, function() end
        end
    end

    if mode == "clone" then
        local clone = character:Clone()
        clone.Name  = character.Name .. "_MultiAnimClone"
        -- Strip any scripts so they don't re-run
        for _, s in ipairs(clone:GetDescendants()) do
            if s:IsA("BaseScript") or s:IsA("ModuleScript") then s:Destroy() end
        end
        -- Remove the Humanoid so the clone has no physics/idle override
        local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
        if cloneHumanoid then cloneHumanoid:Destroy() end

        -- Position at scene anchor
        local hrp = clone:FindFirstChild("HumanoidRootPart")
        if hrp and anchorCF then hrp.CFrame = anchorCF end

        clone.Parent = workspace  -- local-only (not replicated in FilteringEnabled)

        -- Hide + anchor original character so it doesn't overlap the clone
        local saved = savePartStates(character)
        hideCharacter(character)

        return clone, function()
            if clone and clone.Parent then clone:Destroy() end
            if character and character.Parent then
                restoreCharacter(character, saved)
            end
        end

    elseif mode == "direct" then
        local humanoid    = character:FindFirstChildOfClass("Humanoid")
        local wasStand    = humanoid and humanoid.PlatformStand or false
        if humanoid then humanoid.PlatformStand = true end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp and anchorCF then hrp.CFrame = anchorCF end

        return character, function()
            if humanoid and humanoid.Parent then
                humanoid.PlatformStand = wasStand
            end
        end

    else
        warn("[PlayerRigProxy] Unknown mode '" .. tostring(mode) .. "' (expected 'clone' or 'direct')")
        return nil, function() end
    end
end

-- Batch-resolve a full rigMap.
--   rigMap:    { [rigName] = entry }  (entries as described above)
--   anchorCFs: { [rigName] = CFrame } (optional; used to position player rigs)
-- Returns: resolvedMap, teardownFn
function PlayerRigProxy.resolveAll(rigMap, anchorCFs)
    anchorCFs = anchorCFs or {}
    local resolved  = {}
    local teardowns = {}
    for rigName, entry in pairs(rigMap) do
        local rig, td = PlayerRigProxy.resolve(entry, anchorCFs[rigName])
        if rig then resolved[rigName] = rig end
        table.insert(teardowns, td)
    end
    return resolved, function()
        for _, td in ipairs(teardowns) do td() end
    end
end

return PlayerRigProxy
