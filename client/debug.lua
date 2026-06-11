local DEBUG_KVP = 'w-shops:globalDebug'
local resourceName = GetCurrentResourceName()

local enabled = GetResourceKvpInt(DEBUG_KVP) == 1

---@param value any
---@return string
local function formatValue(value)
    local valueType = type(value)

    if valueType == 'table' then
        return json.encode(value, { indent = true, sort_keys = true })
    end

    if valueType == 'vector3' or valueType == 'vector4' then
        return tostring(value)
    end

    return tostring(value)
end

---@param message string
---@vararg any
local function log(message, ...)
    if not enabled then return end

    local argc = select('#', ...)
    local parts = { message }

    for i = 1, argc do
        parts[#parts + 1] = formatValue(select(i, ...))
    end

    print(('^5[%s:debug]^0 %s'):format(resourceName, table.concat(parts, ' ')))
end

---@return boolean
local function isEnabled()
    return enabled
end

---@param value boolean
local function setEnabled(value)
    enabled = value and true or false
    SetResourceKvpInt(DEBUG_KVP, enabled and 1 or 0)

    if enabled then
        print(('^5[%s:debug]^0 Global debug mode ^2enabled^0 — zone visuals and verbose logging active.'):format(resourceName))
    else
        print(('^5[%s:debug]^0 Global debug mode ^1disabled^0.'):format(resourceName))
    end

    TriggerEvent('w-shops:client:debugModeChanged', enabled)
end

if enabled then
    print(('^5[%s:debug]^0 Global debug mode ^2enabled^0 — zone visuals and verbose logging active.'):format(resourceName))
end

return {
    isEnabled = isEnabled,
    setEnabled = setEnabled,
    log = log,
}
