local sharedConfig = require 'config.shared'
local locations = require 'shared.locations'
local hours = require 'shared.hours'

local oxItems = exports.ox_inventory

---@param source number
---@return table?
local function getPlayer(source)
    return exports.qbx_core:GetPlayer(source)
end

---@param source number
---@param group string | table<string, number | number[]>
---@return string? groupName
---@return number? groupRank
local function hasGroup(source, group)
    if not group then return end

    local groups = exports.qbx_core:GetGroups(source)

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

---@param source number
---@param license string
---@return boolean
local function hasLicense(source, license)
    local player = getPlayer(source)
    if not player then return false end

    local licences = player.PlayerData.metadata.licences
    return licences and licences[license] == true
end

---@param source number
---@param license string | string[]
---@return boolean
local function hasAnyLicense(source, license)
    if type(license) == 'table' then
        for i = 1, #license do
            if hasLicense(source, license[i]) then
                return true
            end
        end
        return false
    end

    return hasLicense(source, license)
end

---@param source number
---@param currency string
---@return number
local function getBalance(source, currency)
    return oxItems:GetItemCount(source, currency) or 0
end

---@param itemName string
---@return table?
local function getOxItem(itemName)
    return oxItems:Items(itemName)
end

---@param value string
---@return string
local function formatJobName(value)
    if type(value) ~= 'string' then return 'authorized job' end
    return value:sub(1, 1):upper() .. value:sub(2):gsub('_', ' ')
end

---@param license string
---@return string
local function formatLicenseLabel(license)
    return ('Requires %s license'):format(license:gsub('_', ' '))
end

---@param jobName string
---@param grade number
---@return string
local function getGradeLabel(jobName, grade)
    local ok, jobs = pcall(function()
        return exports.qbx_core:GetJobs()
    end)

    if ok and type(jobs) == 'table' and type(jobs[jobName]) == 'table' then
        local grades = jobs[jobName].grades
        if type(grades) == 'table' then
            local gradeData = grades[tostring(grade)] or grades[grade]
            if type(gradeData) == 'table' and gradeData.name then
                return gradeData.name .. '+ Required'
            end
        end
    end

    return ('%s rank %d+ Required'):format(formatJobName(jobName), grade)
end

---@param source number
---@param shopItem table
---@param shop table
---@param location? table
---@return table
local function getItemAvailability(source, shopItem, shop, location)
    local restrictions = {}

    if not getOxItem(shopItem.name) then
        return {
            canPurchase = false,
            outOfStock = false,
            restricted = true,
            restrictions = {
                { type = 'unknown', label = 'Unavailable' },
            },
            restrictionLabel = 'Unavailable',
        }
    end

    if shopItem.license then
        local licenses = type(shopItem.license) == 'table' and shopItem.license or { shopItem.license }
        if not hasAnyLicense(source, shopItem.license) then
            for i = 1, #licenses do
                restrictions[#restrictions + 1] = {
                    type = 'license',
                    label = formatLicenseLabel(licenses[i]),
                }
            end
        end
    end

    if shopItem.jobRestriction then
        local jobName, rank = hasGroup(source, shopItem.jobRestriction)
        if not jobName then
            restrictions[#restrictions + 1] = {
                type = 'job',
                label = ('Requires %s'):format(formatJobName(shopItem.jobRestriction)),
            }
        elseif shopItem.grade and not isRequiredGrade(shopItem.grade, rank) then
            restrictions[#restrictions + 1] = {
                type = 'grade',
                label = getGradeLabel(shopItem.jobRestriction, shopItem.grade),
            }
        end
    elseif shopItem.grade then
        local restriction = locations.getJobRestriction(shop, location)
        local jobName, rank = hasGroup(source, restriction)
        if not jobName then
            if restriction and type(restriction) == 'string' then
                restrictions[#restrictions + 1] = {
                    type = 'job',
                    label = ('Requires %s'):format(formatJobName(restriction)),
                }
            end
        elseif not isRequiredGrade(shopItem.grade, rank) then
            local labelJob = type(restriction) == 'string' and restriction or jobName
            restrictions[#restrictions + 1] = {
                type = 'grade',
                label = getGradeLabel(labelJob, shopItem.grade),
            }
        end
    end

    local outOfStock = shopItem.count ~= nil and shopItem.count <= 0
    local restricted = #restrictions > 0
    local canPurchase = not outOfStock and not restricted

    return {
        canPurchase = canPurchase,
        outOfStock = outOfStock,
        restricted = restricted,
        restrictions = restrictions,
        restrictionLabel = restrictions[1] and restrictions[1].label or nil,
    }
end

---@param source number
---@param shop table
---@param location? table
---@return boolean
local function canAccessShop(source, shop, location)
    if not hours.isShopOpen(shop) then
        return false
    end

    local restriction = locations.getJobRestriction(shop, location)
    if not restriction then return true end

    return hasGroup(source, restriction) ~= nil
end

---@param source number
---@param shopItem table
---@param shop table
---@param location? table
---@return boolean, string?
local function canPurchaseItem(source, shopItem, shop, location)
    local availability = getItemAvailability(source, shopItem, shop, location)

    if availability.canPurchase then
        return true
    end

    if availability.outOfStock then
        return false, 'This item is out of stock.'
    end

    local reason = availability.restrictions[1] and availability.restrictions[1].label
    return false, reason or 'You cannot purchase this item.'
end

---@param source number
---@param itemName string
---@param quantity number
---@param metadata table?
---@return boolean
local function canCarry(source, itemName, quantity, metadata)
    return oxItems:CanCarryItem(source, itemName, quantity, metadata)
end

---@param currency string
---@return string
local function getCurrencyLabel(currency)
    return sharedConfig.currencyLabels[currency] or currency
end

---@param source number
---@return number cash
---@return number bank
local function getMoneyBalances(source)
    local cash = getBalance(source, 'money')
    local player = getPlayer(source)
    local bank = player and player.PlayerData.money.bank or 0
    return cash, bank
end

---@param source number
---@param paymentMethod string
---@param amount number
---@param currency string
---@return boolean
local function canAffordPayment(source, paymentMethod, amount, currency)
    if currency ~= 'money' then
        return getBalance(source, currency) >= amount
    end

    if paymentMethod == 'bank' then
        local player = getPlayer(source)
        return player and player.PlayerData.money.bank >= amount
    end

    return getBalance(source, 'money') >= amount
end

---@param source number
---@param paymentMethod string
---@param amount number
---@param currency string
---@return boolean
local function removePayment(source, paymentMethod, amount, currency)
    if currency ~= 'money' then
        return oxItems:RemoveItem(source, currency, amount)
    end

    if paymentMethod == 'bank' then
        local player = getPlayer(source)
        if not player then return false end
        return player.Functions.RemoveMoney('bank', amount, 'w-shops purchase')
    end

    return oxItems:RemoveItem(source, 'money', amount)
end

---@param source number
---@param paymentMethod string
---@param amount number
---@param currency string
---@return boolean
local function refundPayment(source, paymentMethod, amount, currency)
    if currency ~= 'money' then
        return oxItems:AddItem(source, currency, amount)
    end

    if paymentMethod == 'bank' then
        local player = getPlayer(source)
        if not player then return false end
        return player.Functions.AddMoney('bank', amount, 'w-shops refund')
    end

    return oxItems:AddItem(source, 'money', amount)
end

return {
    getPlayer = getPlayer,
    hasGroup = hasGroup,
    isRequiredGrade = isRequiredGrade,
    hasLicense = hasLicense,
    getBalance = getBalance,
    getOxItem = getOxItem,
    canAccessShop = canAccessShop,
    getItemAvailability = getItemAvailability,
    canPurchaseItem = canPurchaseItem,
    canCarry = canCarry,
    getCurrencyLabel = getCurrencyLabel,
    getJobRestriction = locations.getJobRestriction,
    getMoneyBalances = getMoneyBalances,
    canAffordPayment = canAffordPayment,
    removePayment = removePayment,
    refundPayment = refundPayment,
    oxItems = oxItems,
}
