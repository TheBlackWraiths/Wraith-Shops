local storage = require 'server.storage'

local DynamicShops = storage.loadDynamicShops()
local RuntimeShops = {}

local function rebuildRuntime()
    table.wipe(RuntimeShops)

    for shopId, shop in pairs(DynamicShops) do
        RuntimeShops[shopId] = lib.table.clone(shop)
    end
end

rebuildRuntime()

---@return table<string, table>
local function getAll()
    return RuntimeShops
end

---@param shopId string
---@return table?
local function get(shopId)
    return RuntimeShops[shopId]
end

---@param shopId string
---@param shopData table
---@return boolean
local function saveDynamic(shopId, shopData)
    DynamicShops[shopId] = lib.table.clone(shopData)
    rebuildRuntime()
    return storage.saveDynamicShops(DynamicShops)
end

---@param shopId string
---@return boolean, string?
local function deleteDynamic(shopId)
    if not DynamicShops[shopId] then
        return false, 'Shop not found.'
    end

    DynamicShops[shopId] = nil
    rebuildRuntime()
    return storage.saveDynamicShops(DynamicShops)
end

---@param shop table
---@return table
local function getSummary(shopId, shop)
    local locationCount = #(shop.locations or shop.targets or {})
    local itemCount = #(shop.inventory or {})
    local categoryCount = #(shop.categories or {})

    if categoryCount == 0 then
        local categories = {}

        for i = 1, itemCount do
            local item = shop.inventory[i]
            if item.category then
                categories[item.category] = true
            end
        end

        for _ in pairs(categories) do
            categoryCount += 1
        end
    end

    return {
        id = shopId,
        name = shop.name or shopId,
        subtitle = shop.subtitle,
        locationCount = locationCount,
        itemCount = itemCount,
        categoryCount = categoryCount,
    }
end

---@return table[]
local function getSummaries()
    local list = {}

    for shopId, shop in pairs(RuntimeShops) do
        list[#list + 1] = getSummary(shopId, shop)
    end

    table.sort(list, function(a, b)
        return a.name < b.name
    end)

    return list
end

---@param shopId string
---@return table?
local function getForEditor(shopId)
    local shop = RuntimeShops[shopId]
    if not shop then return nil end

    return storage.serializeValue(shop)
end

return {
    getAll = getAll,
    get = get,
    saveDynamic = saveDynamic,
    deleteDynamic = deleteDynamic,
    getSummaries = getSummaries,
    getForEditor = getForEditor,
    rebuildRuntime = rebuildRuntime,
}
