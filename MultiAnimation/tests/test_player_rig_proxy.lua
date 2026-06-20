-- test_player_rig_proxy.lua
-- Tests for PlayerRigProxy (game/PlayerRigProxy.lua).
-- Runs headless in Studio edit mode via execute_luau.
-- Returns "ALL TESTS PASSED (N)" or a FAIL line.

local PASS, FAIL = 0, 0
local function ok(cond, name)
    if cond then PASS += 1
    else FAIL += 1; warn("FAIL: " .. tostring(name)) end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Inline the module (cannot require game/ from plugin context)
-- ──────────────────────────────────────────────────────────────────────────────

local PlayerRigProxy = {}
local Players = game:GetService("Players")

local function isR6(character)
    return character:FindFirstChild("Torso") ~= nil
        and character:FindFirstChild("UpperTorso") == nil
end

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

function PlayerRigProxy.resolve(entry, anchorCF)
    if typeof(entry) == "Instance" then
        return entry, function() end
    end
    if type(entry) ~= "table" then
        warn("[PlayerRigProxy] Unknown entry type: " .. tostring(entry))
        return nil, function() end
    end
    local mode = entry.mode or "clone"
    local player
    if entry.player then
        player = entry.player
    elseif entry.userId then
        player = findPlayerByUserId(entry.userId)
        if not player then
            warn("[PlayerRigProxy] No player with UserId " .. tostring(entry.userId))
            return nil, function() end
        end
    end
    if not player then
        warn("[PlayerRigProxy] Entry has no player or userId")
        return nil, function() end
    end
    local character = player.Character
    if not character then
        warn("[PlayerRigProxy] Player has no character yet")
        return nil, function() end
    end
    if mode == "clone" then
        local clone = character:Clone()
        clone.Name  = character.Name .. "_MultiAnimClone"
        for _, s in ipairs(clone:GetDescendants()) do
            if s:IsA("BaseScript") or s:IsA("ModuleScript") then s:Destroy() end
        end
        local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
        if cloneHumanoid then cloneHumanoid:Destroy() end
        local hrp = clone:FindFirstChild("HumanoidRootPart")
        if hrp and anchorCF then hrp.CFrame = anchorCF end
        clone.Parent = workspace
        local saved = savePartStates(character)
        hideCharacter(character)
        return clone, function()
            if clone and clone.Parent then clone:Destroy() end
            if character and character.Parent then
                restoreCharacter(character, saved)
            end
        end
    elseif mode == "direct" then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local wasStand = humanoid and humanoid.PlatformStand or false
        if humanoid then humanoid.PlatformStand = true end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp and anchorCF then hrp.CFrame = anchorCF end
        return character, function()
            if humanoid and humanoid.Parent then
                humanoid.PlatformStand = wasStand
            end
        end
    else
        warn("[PlayerRigProxy] Unknown mode '" .. tostring(mode) .. "'")
        return nil, function() end
    end
end

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

-- ──────────────────────────────────────────────────────────────────────────────
-- Build a minimal fake R6 character model for testing
-- ──────────────────────────────────────────────────────────────────────────────

local function makeR6Character(name)
    local char = Instance.new("Model")
    char.Name = name or "FakeR6"
    local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.Parent = char
    local torso = Instance.new("Part"); torso.Name = "Torso"; torso.Parent = char
    local head = Instance.new("Part"); head.Name = "Head"; head.Parent = char
    local hum = Instance.new("Humanoid"); hum.Parent = char
    char.Parent = workspace
    return char
end

local function makeR15Character(name)
    local char = Instance.new("Model")
    char.Name = name or "FakeR15"
    local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.Parent = char
    local torso = Instance.new("Part"); torso.Name = "Torso"; torso.Parent = char
    local upper = Instance.new("Part"); upper.Name = "UpperTorso"; upper.Parent = char
    local hum = Instance.new("Humanoid"); hum.Parent = char
    char.Parent = workspace
    return char
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Tests
-- ──────────────────────────────────────────────────────────────────────────────

-- 1. Module loads (table with resolve + resolveAll)
ok(type(PlayerRigProxy) == "table", "module is a table")
ok(type(PlayerRigProxy.resolve) == "function", "has resolve()")
ok(type(PlayerRigProxy.resolveAll) == "function", "has resolveAll()")

-- 2. Fixed rig (Instance pass-through)
local fakeRig = Instance.new("Model")
fakeRig.Name = "FixedRig"; fakeRig.Parent = workspace
local resolved, teardown = PlayerRigProxy.resolve(fakeRig, nil)
ok(resolved == fakeRig, "fixed rig pass-through returns same instance")
ok(type(teardown) == "function", "fixed rig teardown is a function")
teardown()  -- no-op; rig should still exist
ok(fakeRig.Parent == workspace, "fixed rig still in workspace after teardown")
fakeRig:Destroy()

-- 3. Nil entry returns nil, function
local nilResult, nilTd = PlayerRigProxy.resolve(nil, nil)
ok(nilResult == nil, "nil entry returns nil")
ok(type(nilTd) == "function", "nil entry teardown is function")

-- 4. Unknown-type entry returns nil, function
local badResult, badTd = PlayerRigProxy.resolve(42, nil)
ok(badResult == nil, "number entry returns nil")
ok(type(badTd) == "function", "number entry teardown is function")

-- 5. Missing player field returns nil
local missingPlayer, _ = PlayerRigProxy.resolve({ mode = "clone" }, nil)
ok(missingPlayer == nil, "table with no player/userId returns nil")

-- 6. Missing userId (non-existent) returns nil
local noUserId, _ = PlayerRigProxy.resolve({ userId = 999999999, mode = "clone" }, nil)
ok(noUserId == nil, "non-existent userId returns nil")

-- 7. isR6 detection — genuine R6 char
local r6char = makeR6Character("TestR6A")
ok(isR6(r6char) == true, "R6 detection: Torso present, no UpperTorso → true")
r6char:Destroy()

-- 8. isR6 detection — R15-like char (has UpperTorso)
local r15char = makeR15Character("TestR15A")
ok(isR6(r15char) == false, "R6 detection: UpperTorso present → false")
r15char:Destroy()

-- 9. savePartStates + restoreCharacter round-trip
local charForSave = makeR6Character("CharSaveTest")
local hrpSave = charForSave:FindFirstChild("HumanoidRootPart")
hrpSave.Transparency = 0.5
hrpSave.Anchored     = false
local saved = savePartStates(charForSave)
ok(saved[hrpSave] ~= nil, "savePartStates records HRP")
ok(saved[hrpSave].transparency == 0.5, "savePartStates records transparency")
hideCharacter(charForSave)
ok(hrpSave.Transparency == 1, "hideCharacter sets Transparency=1")
ok(hrpSave.Anchored == true, "hideCharacter sets Anchored=true")
restoreCharacter(charForSave, saved)
ok(hrpSave.Transparency == 0.5, "restoreCharacter restores transparency")
ok(hrpSave.Anchored == false, "restoreCharacter restores anchored")
charForSave:Destroy()

-- 10. Clone mode: fake Player object via a synthetic table (no real player needed)
-- We create a real R6 character Model parented to workspace and a fake player struct.
local cloneChar = makeR6Character("CloneCharSrc")
local fakePlayer = { Character = cloneChar }  -- minimal duck-type

-- Monkey-patch resolve to accept a duck-typed "player" (same code path)
local cloneRig, cloneTd = PlayerRigProxy.resolve({ player = fakePlayer, mode = "clone" },
    CFrame.new(0, 50, 0))
ok(cloneRig ~= nil, "clone mode returns non-nil rig")
ok(cloneRig ~= cloneChar, "clone mode returns a different model (the clone)")
ok(cloneRig.Name == "CloneCharSrc_MultiAnimClone", "clone has correct Name")
ok(cloneRig.Parent == workspace, "clone is parented to workspace")
-- Humanoid should have been removed
ok(cloneRig:FindFirstChildOfClass("Humanoid") == nil, "clone has no Humanoid")
-- Original should be hidden
local srcHRP = cloneChar:FindFirstChild("HumanoidRootPart")
ok(srcHRP and srcHRP.Transparency == 1, "original HRP is hidden after clone")
-- HRP of clone should be positioned at anchorCF
local cloneHRP = cloneRig:FindFirstChild("HumanoidRootPart")
ok(cloneHRP ~= nil, "clone has HumanoidRootPart")
ok(math.abs(cloneHRP.CFrame.Y - 50) < 0.1, "clone HRP positioned at anchorCF Y=50")
-- Teardown: clone destroyed, original restored
cloneTd()
ok(cloneRig.Parent == nil, "teardown destroys the clone")
ok(srcHRP.Transparency == 0, "teardown restores original HRP transparency")
cloneChar:Destroy()

-- 11. Direct mode: PlatformStand set, restored on teardown
local directChar = makeR6Character("DirectCharSrc")
local directHum  = directChar:FindFirstChildOfClass("Humanoid")
directHum.PlatformStand = false
local fakePlayerDirect = { Character = directChar }
local directRig, directTd = PlayerRigProxy.resolve({ player = fakePlayerDirect, mode = "direct" }, nil)
ok(directRig == directChar, "direct mode returns original character")
ok(directHum.PlatformStand == true, "direct mode sets PlatformStand=true")
directTd()
ok(directHum.PlatformStand == false, "direct teardown restores PlatformStand=false")
directChar:Destroy()

-- 12. R15 character is accepted (dynamic rig support)
local r15src = makeR15Character("R15Src")
local fakeR15Player = { Character = r15src }
local r15Result, r15Td = PlayerRigProxy.resolve({ player = fakeR15Player, mode = "clone" }, nil)
ok(r15Result ~= nil, "R15 character clone accepted (R15 now supported)")
if r15Result then r15Td() end
r15src:Destroy()

-- 13. resolveAll with a mix of fixed + clone entries
local mixRig1 = Instance.new("Model"); mixRig1.Name = "MixRig1"; mixRig1.Parent = workspace
local mixChar2 = makeR6Character("MixChar2")
local fakePlayer2 = { Character = mixChar2 }
local resolved2, teardown2 = PlayerRigProxy.resolveAll({
    Rig1 = mixRig1,
    Rig2 = { player = fakePlayer2, mode = "clone" },
}, {})
ok(resolved2.Rig1 == mixRig1, "resolveAll: Rig1 fixed pass-through")
ok(resolved2.Rig2 ~= nil, "resolveAll: Rig2 clone resolved")
ok(resolved2.Rig2 ~= mixChar2, "resolveAll: Rig2 is clone, not original")
teardown2()
ok(resolved2.Rig2.Parent == nil, "resolveAll teardown destroys Rig2 clone")
mixRig1:Destroy()
mixChar2:Destroy()

-- 14. resolveAll with empty map returns empty table
local emptyResolved, emptyTd = PlayerRigProxy.resolveAll({}, {})
ok(type(emptyResolved) == "table", "resolveAll empty map returns table")
ok(next(emptyResolved) == nil, "resolveAll empty map: no entries")
ok(type(emptyTd) == "function", "resolveAll empty map returns teardown fn")
emptyTd()   -- no-op

-- 15. resolve unknown mode returns nil
local badModeResult, _ = PlayerRigProxy.resolve(
    { player = { Character = makeR6Character("BadModeChar") }, mode = "teleport" }, nil)
ok(badModeResult == nil, "unknown mode returns nil")
-- clean up the character created inline
local bmChar = workspace:FindFirstChild("BadModeChar"); if bmChar then bmChar:Destroy() end

-- 16. Clone teardown is idempotent (double-call doesn't error)
local idemChar = makeR6Character("IdemClone")
local fakeIdem = { Character = idemChar }
local _, idemTd = PlayerRigProxy.resolve({ player = fakeIdem, mode = "clone" }, nil)
local ok1 = pcall(idemTd)
local ok2 = pcall(idemTd)
ok(ok1 and ok2, "clone teardown is safe to call twice")
idemChar:Destroy()

-- 17. Direct teardown after character destroyed doesn't error
local dtChar = makeR6Character("DirectTearChar")
local fakeDT  = { Character = dtChar }
local _, dtTd = PlayerRigProxy.resolve({ player = fakeDT, mode = "direct" }, nil)
dtChar:Destroy()
local dtOk = pcall(dtTd)
ok(dtOk, "direct teardown after character destroyed doesn't error")

-- 18. anchorCF nil is handled gracefully in clone mode (HRP keeps original CFrame)
local noAnchorChar = makeR6Character("NoAnchorChar")
local noAnchorHRP  = noAnchorChar:FindFirstChild("HumanoidRootPart")
noAnchorHRP.CFrame = CFrame.new(10, 20, 30)
local fakeNoAnchor = { Character = noAnchorChar }
local naClone, naTd = PlayerRigProxy.resolve({ player = fakeNoAnchor, mode = "clone" }, nil)
ok(naClone ~= nil, "clone with nil anchorCF still creates clone")
naTd()
noAnchorChar:Destroy()

-- 19. resolveAll anchor CFs passed per-rig
local ancChar = makeR6Character("AnchorTestChar")
local fakeAnc = { Character = ancChar }
local ancResolved, ancTd = PlayerRigProxy.resolveAll(
    { AncRig = { player = fakeAnc, mode = "clone" } },
    { AncRig = CFrame.new(0, 100, 0) })
local ancClone = ancResolved.AncRig
ok(ancClone ~= nil, "resolveAll with anchor: clone created")
local ancCloneHRP = ancClone and ancClone:FindFirstChild("HumanoidRootPart")
ok(ancCloneHRP and math.abs(ancCloneHRP.CFrame.Y - 100) < 0.1, "resolveAll anchor positions clone correctly")
ancTd()
ancChar:Destroy()

-- 20. findPlayerByUserId returns nil when no player has that id (headless edit mode)
ok(findPlayerByUserId(1) == nil, "findPlayerByUserId returns nil in edit mode (no players)")

-- ──────────────────────────────────────────────────────────────────────────────
-- Result
-- ──────────────────────────────────────────────────────────────────────────────

local summary = string.format("\n=== %d passed, %d failed ===", PASS, FAIL)
return summary .. "\n" .. (FAIL == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
