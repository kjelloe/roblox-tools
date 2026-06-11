-- TestBridge — UI integration-test hook.
--
-- Exposes a BindableFunction in CoreGui that lets execute_luau (a different
-- Lua VM) drive the live plugin panel: select rigs, move the timeline, add
-- and delete keyframes, and read state back.  This is what makes the
-- tests/test_ui_*.lua files possible — without it the plugin VM is sealed.
--
-- Protocol: bridge:Invoke(command, argsJson) → resultJson
--   resultJson = { ok = true, result = ... } | { ok = false, err = "..." }
-- All payloads cross the VM boundary as JSON strings because BindableFunction
-- serialization drops functions/instances and copies tables.

local HttpService = game:GetService("HttpService")

local TestBridge = {}

local BRIDGE_NAME = "__MultiAnimTestBridge"

-- handlers: { [commandName] = function(argsTable) → serializable result }
-- Returns the BindableFunction (caller owns destruction on teardown/unload).
function TestBridge.start(handlers)
    local CoreGui = game:GetService("CoreGui")

    local old = CoreGui:FindFirstChild(BRIDGE_NAME)
    if old then old:Destroy() end

    local bridge = Instance.new("BindableFunction")
    bridge.Name = BRIDGE_NAME
    bridge.OnInvoke = function(command, argsJson)
        local handler = handlers[command]
        if not handler then
            return HttpService:JSONEncode({ ok = false, err = "unknown command: " .. tostring(command) })
        end
        local args = {}
        if argsJson and argsJson ~= "" then
            local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, argsJson)
            if not okDecode then
                return HttpService:JSONEncode({ ok = false, err = "bad args JSON" })
            end
            args = decoded
        end
        local ok, result = pcall(handler, args)
        if ok then
            return HttpService:JSONEncode({ ok = true, result = result })
        end
        return HttpService:JSONEncode({ ok = false, err = tostring(result) })
    end
    bridge.Parent = CoreGui
    return bridge
end

return TestBridge
