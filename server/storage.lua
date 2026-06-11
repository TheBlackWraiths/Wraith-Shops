local resourcePath = GetResourcePath(GetCurrentResourceName())
local filePath = ('%s/data/shops.json'):format(resourcePath)

---@param value any
---@return boolean
local function isVectorValue(value)
    local valueType = type(value)

    if valueType == 'vector3' or valueType == 'vector4' then
        return true
    end

    return valueType == 'userdata' and value.x ~= nil and value.y ~= nil and value.z ~= nil
end

---@param value vector3 | vector4 | userdata
---@return table
local function vectorToTable(value)
    if value.w ~= nil then
        return { x = value.x + 0.0, y = value.y + 0.0, z = value.z + 0.0, w = value.w + 0.0 }
    end

    return { x = value.x + 0.0, y = value.y + 0.0, z = value.z + 0.0 }
end

---@param value any
---@return any
local function serializeValue(value)
    if isVectorValue(value) then
        return vectorToTable(value)
    end

    if type(value) ~= 'table' then return value end

    if value.x and value.y and value.z and not value[1] then
        if value.w ~= nil then
            return { x = value.x, y = value.y, z = value.z, w = value.w }
        end
        return { x = value.x, y = value.y, z = value.z }
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = serializeValue(v)
    end
    return copy
end

---@param value any
---@return any
local function deserializeValue(value)
    if type(value) ~= 'table' then return value end

    if value.x and value.y and value.z and not value[1] then
        if value.w then
            return vec4(value.x, value.y, value.z, value.w)
        end
        return vec3(value.x, value.y, value.z)
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deserializeValue(v)
    end
    return copy
end

---@return table<string, table>
local function loadDynamicShops()
    local raw = LoadResourceFile(GetCurrentResourceName(), 'data/shops.json')
    if not raw or raw == '' then return {} end

    local decoded = json.decode(raw)
    if type(decoded) ~= 'table' then return {} end

    local shops = {}
    for shopId, shop in pairs(decoded) do
        shops[shopId] = deserializeValue(shop)
    end

    return shops
end

---@param shops table<string, table>
---@return boolean
local function saveDynamicShops(shops)
    local payload = {}

    for shopId, shop in pairs(shops) do
        payload[shopId] = serializeValue(shop)
    end

    local encoded = json.encode(payload, { indent = true })
    return SaveResourceFile(GetCurrentResourceName(), 'data/shops.json', encoded, -1)
end

return {
    loadDynamicShops = loadDynamicShops,
    saveDynamicShops = saveDynamicShops,
    serializeValue = serializeValue,
    deserializeValue = deserializeValue,
}
