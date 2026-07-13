-- MultiAnimation Dev Loader — hot-reload stub plugin.
--
-- Built/installed by devsync.py (`python3 devsync.py install`) as
-- MultiAnimationDevLoader.rbxmx.  NOT part of the normal plugin build.
--
-- How it works:
--   devsync.py pushes the plugin source tree into CoreGui.__MultiAnimDevSrc
--   (fresh ModuleScript instances each push — busts the require cache) and
--   bumps the folder's "Version" attribute.  This loader watches that
--   attribute and re-runs the init source on every bump, with `script`
--   pointing at the dev tree and `plugin` provided via setfenv.
--   init.server.lua's _G.__MultiAnimTeardown handles dismantling the
--   previous instance.

if game:GetService("RunService"):IsRunning() then return end

local CoreGui = game:GetService("CoreGui")
local SRC_NAME = "__MultiAnimDevSrc"

local function boot(root)
    local initHolder = root:FindFirstChild("init")
    if not initHolder or not initHolder:IsA("StringValue") then
        warn("[DevLoader] no init StringValue in " .. SRC_NAME .. " — push with devsync.py first")
        return
    end

    local fn, err = loadstring(initHolder.Value)
    if not fn then
        warn("[DevLoader] init compile error: " .. tostring(err))
        return
    end

    -- script → the dev tree (has core/, ui/, game/ children like the real
    -- plugin root); plugin → this loader's plugin handle.  Everything else
    -- falls through to the loader's own environment.
    local env = setmetatable({ script = root, plugin = plugin }, { __index = getfenv() })
    setfenv(fn, env)

    local ok, runErr = pcall(fn)
    if ok then
        print(string.format("[DevLoader] booted MultiAnimation (version %s)",
            tostring(root:GetAttribute("Version"))))
    else
        warn("[DevLoader] init runtime error: " .. tostring(runErr))
    end
end

local root = CoreGui:FindFirstChild(SRC_NAME)
if not root then
    -- devsync.py creates the folder on first push; wait for it indefinitely —
    -- a timeout here permanently killed hot-reload in sessions where the place
    -- sat open longer than the timeout before the first push.
    print("[DevLoader] waiting for first devsync push (run: python3 devsync.py)")
    root = CoreGui:WaitForChild(SRC_NAME)
end

root:GetAttributeChangedSignal("Version"):Connect(function()
    boot(root)
end)

if root:GetAttribute("Version") then
    boot(root)
end

plugin.Unloading:Connect(function()
    if _G.__MultiAnimTeardown then
        pcall(_G.__MultiAnimTeardown)
        _G.__MultiAnimTeardown = nil
    end
end)
