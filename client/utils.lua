---@param action string
---@param data any
function SendReactMessage(action, data)
    SendNUIMessage({
        action = action,
        data = data,
    })
end

local currentResourceName = GetCurrentResourceName()
local debugIsEnabled = GetConvarInt(('%s-debugMode'):format(currentResourceName), 0) == 1

function debugPrint(...)
    local ok, debugMode = pcall(require, 'client.debug')
    local globalDebug = ok and debugMode.isEnabled()

    if not debugIsEnabled and not globalDebug then return end

    if globalDebug then
        debugMode.log(...)
        return
    end

    local args = { ... }
    local appendStr = ''
    for _, v in ipairs(args) do
        appendStr = appendStr .. ' ' .. tostring(v)
    end
    print(('^3[%s]^0%s'):format(currentResourceName, appendStr))
end
