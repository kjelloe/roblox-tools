-- test_platform_canary.lua
-- Platform-change detector: asserts every Roblox API behaviour the plugin and
-- players depend on. When a Studio update shifts the platform (it has: Pose
-- .Transform→.CFrame rename, AnimationClipProvider removal, execute_luau
-- datamodel_type, screen_capture capture_id, Script.Source capability, remote
-- sparse-dict drops…), this file fails FIRST with a named assertion instead of
-- mysterious downstream breakage.

local out = {}
local passed, failed = 0, 0

local function ok(label, cond, extra)
    if cond then
        passed += 1
        table.insert(out, "PASS  " .. label)
    else
        failed += 1
        table.insert(out, "FAIL  " .. label .. (extra and ("  >> " .. tostring(extra)) or ""))
    end
end

-- ── Pose / KeyframeSequence (export format) ───────────────────────────────────

local pose = Instance.new("Pose")
ok("Pose.CFrame property exists (renamed from .Transform once already)",
    pcall(function() pose.CFrame = CFrame.new(1, 2, 3) end))
ok("Pose easing enums exist (Linear/Cubic/Constant/Bounce/Elastic)",
    pcall(function()
        pose.EasingStyle = Enum.PoseEasingStyle.Elastic
        pose.EasingStyle = Enum.PoseEasingStyle.Bounce
        pose.EasingStyle = Enum.PoseEasingStyle.Cubic
        pose.EasingStyle = Enum.PoseEasingStyle.Constant
        pose.EasingDirection = Enum.PoseEasingDirection.InOut
    end))
pose:Destroy()

local kfs = Instance.new("KeyframeSequence")
ok("KeyframeSequence GetKeyframes + AuthoredHipHeight",
    pcall(function()
        kfs.AuthoredHipHeight = 0
        return kfs:GetKeyframes()
    end))
kfs:Destroy()

-- ── CFrame maths (interpolation + smooth mode) ────────────────────────────────

local lerped = CFrame.new(0, 0, 0):Lerp(CFrame.new(0, 1, 0), 2)
ok("CFrame:Lerp extrapolates beyond t=1 (smooth-mode tangents depend on it)",
    math.abs(lerped.Position.Y - 2) < 0.001, lerped.Position.Y)
ok("CFrame:Lerp slerps rotation",
    (CFrame.Angles(0, 0, 0):Lerp(CFrame.Angles(math.rad(90), 0, 0), 0.5)
        .UpVector - CFrame.Angles(math.rad(45), 0, 0).UpVector).Magnitude < 0.001)
ok("CFrame:GetComponents returns 12 values",
    select("#", CFrame.new():GetComponents()) == 12)

-- ── TweenService (editor-preview easing) ──────────────────────────────────────

local TS = game:GetService("TweenService")
ok("TweenService:GetValue with Elastic style",
    pcall(function() return TS:GetValue(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out) end))

-- ── Motor6D contract (posing + capture) ───────────────────────────────────────

local m = Instance.new("Motor6D")
ok("Motor6D Part0 nil-able + Transform/C0/C1 settable",
    pcall(function()
        m.Part0 = nil
        m.Transform = CFrame.new(0, 1, 0)
        m.C0 = CFrame.new()
        m.C1 = CFrame.new()
    end))
m:Destroy()

-- ── Services and signals the plugin wires into ────────────────────────────────

local CHS = game:GetService("ChangeHistoryService")
ok("ChangeHistoryService OnUndo/OnRedo signals exist (undo re-weld protection)",
    typeof(CHS.OnUndo) == "RBXScriptSignal" and typeof(CHS.OnRedo) == "RBXScriptSignal")

local CS = game:GetService("CollectionService")
local tagProbe = Instance.new("Folder")
tagProbe.Parent = game:GetService("ServerStorage")   -- GetTagged only sees DataModel members
CS:AddTag(tagProbe, "__CanaryTag")
ok("CollectionService AddTag/GetTagged round-trip",
    (function()
        for _, inst in ipairs(CS:GetTagged("__CanaryTag")) do
            if inst == tagProbe then return true end
        end
        return false
    end)())
tagProbe:Destroy()

-- ── GUI + persistence primitives ──────────────────────────────────────────────

ok("ScreenGui IgnoreGuiInset/DisplayOrder settable (fade/letterbox/subtitles)",
    pcall(function()
        local g = Instance.new("ScreenGui")
        g.IgnoreGuiInset = true
        g.DisplayOrder = 300
        g:Destroy()
    end))

local sv = Instance.new("StringValue")
ok("StringValue holds a 190k session mirror",
    pcall(function() sv.Value = string.rep("x", 190000) end)
    and #sv.Value == 190000)
sv:Destroy()

local HS = game:GetService("HttpService")
local blob = { rigs = { R = { joints = { ["1"] = { 1, 0, 0.5 } } } }, name = "å→é" }
local okJ, round = pcall(function() return HS:JSONDecode(HS:JSONEncode(blob)) end)
ok("HttpService JSON round-trip incl. unicode",
    okJ and round and round.name == blob.name and round.rigs.R.joints["1"][3] == 0.5)

-- ── Highlight / post-effects (effect lane classes) ────────────────────────────

ok("Highlight + ColorCorrectionEffect + Bloom + Blur classes exist with Enabled",
    pcall(function()
        for _, cls in ipairs({ "Highlight", "ColorCorrectionEffect", "BloomEffect", "BlurEffect" }) do
            local inst = Instance.new(cls)
            inst.Enabled = false
            inst:Destroy()
        end
    end))

-- ── WeldConstraint (attach-feature substrate) ─────────────────────────────────

ok("WeldConstraint class instantiable with Part0/Part1",
    pcall(function()
        local a, b = Instance.new("Part"), Instance.new("Part")
        local w = Instance.new("WeldConstraint")
        w.Part0 = a
        w.Part1 = b
        w:Destroy() a:Destroy() b:Destroy()
    end))

-- ── Edit-mode viewport camera (Camera View / Look Through substrate) ──────────
-- The camera-capture design assumes programmatic writes to the edit camera
-- round-trip essentially exactly: moved-detection uses small epsilons, and the
-- Look Through mirror copies Camera.CFrame back into the gizmo every frame.
-- If a Studio update makes the camera controller mutate written values, these
-- name the break before keyframes start drifting again.

do
    local cam = workspace.CurrentCamera
    local saved = { cf = cam.CFrame, fov = cam.FieldOfView, focus = cam.Focus }

    local target = CFrame.lookAt(Vector3.new(123.25, 45.5, -67.75), Vector3.new(0, 5, 0))
    cam.CFrame = target
    local got = cam.CFrame
    ok("edit camera CFrame write→read is exact (position)",
        (got.Position - target.Position).Magnitude < 1e-3,
        (got.Position - target.Position).Magnitude)
    ok("edit camera CFrame write→read is exact (orientation)",
        (got.LookVector - target.LookVector).Magnitude < 1e-3
        and (got.UpVector - target.UpVector).Magnitude < 1e-3)

    local focusTarget = CFrame.new(target.Position + target.LookVector * 10)
    cam.Focus = focusTarget
    ok("edit camera Focus write→read round-trips",
        (cam.Focus.Position - focusTarget.Position).Magnitude < 1e-3,
        (cam.Focus.Position - focusTarget.Position).Magnitude)

    cam.FieldOfView = 47.5
    ok("edit camera FieldOfView write→read round-trips",
        math.abs(cam.FieldOfView - 47.5) < 1e-3, cam.FieldOfView)

    cam.CFrame      = saved.cf
    cam.FieldOfView = saved.fov
    cam.Focus       = saved.focus
end

-- ── Summary ───────────────────────────────────────────────────────────────────

table.insert(out, string.format("\n=== %d passed, %d failed ===", passed, failed))
table.insert(out, failed == 0 and "ALL TESTS PASSED" or "FAILURES DETECTED")
return table.concat(out, "\n")
