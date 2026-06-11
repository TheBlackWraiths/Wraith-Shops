local sharedConfig = require 'config.shared'
local locations = require 'shared.locations'
local hours = require 'shared.hours'

---@param group string | table<string, number | number[]>
---@return string? groupName
---@return number? groupRank
local function hasGroup(group)
    if not group then return end

    local groups = exports.qbx_core:GetGroups()

    if type(group) == 'table' then
        for name, requiredRank in pairs(group) do
            local groupRank = groups[name]
            if groupRank then
                if type(requiredRank) == 'table' then
                    if lib.table.contains(requiredRank, groupRank) then
                        return name, groupRank
                    end
                elseif groupRank >= (requiredRank or 0) then
                    return name, groupRank
                end
            end
        end
    else
        local groupRank = groups[group]
        if groupRank then
            return group, groupRank
        end
    end
end

---@param grade number | number[]
---@param rank number?
---@return boolean
local function isRequiredGrade(grade, rank)
    if not rank then return false end

    if type(grade) == 'table' then
        return lib.table.contains(grade, rank)
    end

    return rank >= grade
end

---@param shop table
---@param location? table
---@return boolean
local function canAccessShop(shop, location)
    if not hours.isShopOpen(shop) then
        return false
    end

    local restriction = locations.getJobRestriction(shop, location)
    if not restriction then return true end

    return hasGroup(restriction) ~= nil
end

---@param shop table
---@return boolean
local function isShopOpen(shop)
    return hours.isShopOpen(shop)
end

---@param shop table
---@param location? table
---@return boolean
local function hasJobAccess(shop, location)
    local restriction = locations.getJobRestriction(shop, location)
    if not restriction then return true end

    return hasGroup(restriction) ~= nil
end

---@param inventory table
---@param shop table
---@param location? table
---@return table
local function filterInventory(inventory, shop, location)
    local restriction = locations.getJobRestriction(shop, location)
    local _, rank = hasGroup(restriction)
    local items = {}

    for i = 1, #inventory do
        local entry = inventory[i]
        if not entry.grade or isRequiredGrade(entry.grade, rank) then
            items[#items + 1] = entry
        end
    end

    return items
end

---@param itemName string
---@return string
local function getItemLabel(itemName)
    local item = exports.ox_inventory:Items(itemName)
    return item and item.label or itemName
end

---@param itemName string
---@return string
local function getItemImage(itemName)
    return sharedConfig.imagePath:format(itemName)
end

---@param currency string
---@return string
local function getCurrencyLabel(currency)
    return sharedConfig.currencyLabels[currency] or currency
end

return {
    hasGroup = hasGroup,
    isShopOpen = isShopOpen,
    hasJobAccess = hasJobAccess,
    canAccessShop = canAccessShop,
    filterInventory = filterInventory,
    getItemLabel = getItemLabel,
    getItemImage = getItemImage,
    getCurrencyLabel = getCurrencyLabel,
    getJobRestriction = locations.getJobRestriction,
}
