local sharedConfig = require 'config.shared'
local registry = require 'server.registry'
local storage = require 'server.storage'
local locations = require 'shared.locations'

---@param source number
---@return boolean
local function canManage(source)
    if sharedConfig.manager.allowAll then
        return true
    end

    local ace = sharedConfig.manager.acePermission
    local group = sharedConfig.manager.groupPermission

    if ace and IsPlayerAceAllowed(source --[[@as string]], ace) then
        return true
    end

    if group and IsPlayerAceAllowed(source --[[@as string]], group) then
        return true
    end

    local player = exports.qbx_core:GetPlayer(source)
    if player then
        local perm = player.PlayerData.group
        if perm == 'admin' or perm == 'god' then
            return true
        end
    end

    return false
end

---@param shopId string
---@return boolean
local function isValidShopId(shopId)
    return type(shopId) == 'string' and shopId:match('^[%w_%-]+$') ~= nil and #shopId <= 48
end

---@param shopData table
---@return table?, string?
local function sanitizeShopData(shopData)
    if type(shopData) ~= 'table' then
        return nil, 'Invalid shop data.'
    end

    if type(shopData.name) ~= 'string' or shopData.name == '' then
        return nil, 'Shop name is required.'
    end

    local categories = {}
    local seenCategories = {}

    if type(shopData.categories) == 'table' then
        for i = 1, #shopData.categories do
            local category = shopData.categories[i]
            if type(category) == 'string' then
                category = category:match('^%s*(.-)%s*$')
                if category ~= '' and not seenCategories[category] then
                    seenCategories[category] = true
                    categories[#categories + 1] = category
                end
            end
        end
    end

    ---@param value string?
    ---@return string?
    local function trimString(value)
        if type(value) ~= 'string' then return nil end
        value = value:match('^%s*(.-)%s*$')
        if value == '' then return nil end
        return value
    end

    ---@param license any
    ---@return string|string[]|nil
    local function sanitizeLicense(license)
        if type(license) == 'string' then
            return trimString(license)
        end

        if type(license) ~= 'table' then
            return nil
        end

        local list = {}
        for i = 1, #license do
            local entry = trimString(license[i])
            if entry then
                list[#list + 1] = entry
            end
        end

        if #list == 0 then return nil end
        if #list == 1 then return list[1] end
        return list
    end

    ---@param metadata any
    ---@return table|nil
    local function sanitizeMetadata(metadata)
        if type(metadata) == 'string' then
            if metadata == '' then return nil end
            local ok, decoded = pcall(json.decode, metadata)
            if ok and type(decoded) == 'table' then
                return decoded
            end
            return nil
        end

        if type(metadata) == 'table' then
            return metadata
        end

        return nil
    end

    local inventory = {}
    if type(shopData.inventory) == 'table' then
        for i = 1, #shopData.inventory do
            local item = shopData.inventory[i]
            if type(item.name) == 'string' and type(item.price) == 'number' then
                local category = trimString(item.category)
                local count = item.count
                if count ~= nil then
                    count = math.max(0, math.floor(tonumber(count) or 0))
                end

                local grade = item.grade
                if grade ~= nil then
                    grade = math.max(0, math.floor(tonumber(grade) or 0))
                end

                inventory[#inventory + 1] = {
                    name = item.name,
                    price = math.floor(item.price),
                    count = count,
                    category = category,
                    label = trimString(item.label),
                    description = trimString(item.description),
                    image = trimString(item.image),
                    metadata = sanitizeMetadata(item.metadata),
                    license = sanitizeLicense(item.license),
                    grade = grade,
                    jobRestriction = trimString(item.jobRestriction),
                    currency = item.currency,
                }
            end
        end
    end

    local shopLocations = {}
    if type(shopData.locations) == 'table' then
        for i = 1, #shopData.locations do
            local normalized = locations.normalizeLocation(storage.deserializeValue(shopData.locations[i]))

            if normalized.type == 'ped' or normalized.type == 'zone' then
                if not locations.getLocationCoords(normalized) then
                    return nil, ('Location %d (%s) is missing coordinates.'):format(i, normalized.type)
                end
            elseif normalized.type == 'model' then
                local models = normalized.models or {}
                if #models == 0 then
                    return nil, ('Location %d (model) needs at least one model.'):format(i)
                end
            end

            if normalized.type == 'zone' then
                local hasSphere = normalized.radius ~= nil
                local hasBox = normalized.length and normalized.width and normalized.minZ ~= nil and normalized.maxZ ~= nil

                if not hasSphere and not hasBox then
                    return nil, ('Location %d (zone) is missing zone size settings.'):format(i)
                end
            end

            shopLocations[i] = normalized
        end
    end

    local jobRestriction = shopData.jobRestriction or shopData.groups or shopData.jobs

    local operatingHours = nil
    if type(shopData.operatingHours) == 'table' and shopData.operatingHours.enabled then
        operatingHours = {
            enabled = true,
            open = shopData.operatingHours.open or '00:00',
            close = shopData.operatingHours.close or '23:00',
        }
    end

    return {
        name = shopData.name,
        subtitle = shopData.subtitle or 'Your neighborhood convenience store',
        categories = categories,
        inventory = inventory,
        locations = shopLocations,
        jobRestriction = jobRestriction,
        groups = jobRestriction,
        operatingHours = operatingHours,
        currency = shopData.currency,
        blip = shopData.blip,
        randomPrices = type(shopData.randomPrices) == 'table' and shopData.randomPrices.enabled and {
            enabled = true,
            range = tonumber(shopData.randomPrices.range) or 20,
        } or nil,
    }
end

---@param shop table
---@return string?
local function validateCategories(shop)
    for i = 1, #shop.inventory do
        local category = shop.inventory[i].category
        if category then
            local found = false
            for j = 1, #shop.categories do
                if shop.categories[j] == category then
                    found = true
                    break
                end
            end

            if not found then
                return ('Item %d has an invalid category.'):format(i)
            end
        end
    end

    return nil
end

lib.callback.register('w-shops:manager:canOpen', function(source)
    return canManage(source)
end)

lib.callback.register('w-shops:manager:listShops', function(source)
    if not canManage(source) then return nil end
    return registry.getSummaries()
end)

lib.callback.register('w-shops:manager:getShop', function(source, shopId)
    if not canManage(source) or not isValidShopId(shopId) then return nil end

    local shop = registry.getForEditor(shopId)
    if not shop then return nil end

    shop.id = shopId
    return shop
end)

lib.callback.register('w-shops:manager:saveShop', function(source, shopId, shopData)
    if not canManage(source) then
        return { success = false, message = 'No permission.' }
    end

    if not isValidShopId(shopId) then
        return { success = false, message = 'Invalid shop id. Use letters, numbers, underscore, hyphen.' }
    end

    local existing = registry.get(shopId)

    local sanitized, err = sanitizeShopData(shopData)
    if not sanitized then
        return { success = false, message = err }
    end

    if #sanitized.locations == 0 then
        return { success = false, message = 'Add at least one location.' }
    end

    if #sanitized.inventory == 0 then
        return { success = false, message = 'Add at least one item.' }
    end

    local categoryErr = validateCategories(sanitized)
    if categoryErr then
        return { success = false, message = categoryErr }
    end

    local saved = registry.saveDynamic(shopId, sanitized)
    if not saved then
        return { success = false, message = 'Failed to save shop file.' }
    end

    TriggerClientEvent('w-shops:client:refreshShops', -1)

    return {
        success = true,
        message = existing and 'Shop updated.' or 'Shop created.',
        shopId = shopId,
    }
end)

lib.callback.register('w-shops:manager:deleteShop', function(source, shopId)
    if not canManage(source) then
        return { success = false, message = 'No permission.' }
    end

    if not isValidShopId(shopId) then
        return { success = false, message = 'Invalid shop id.' }
    end

    local ok, err = registry.deleteDynamic(shopId)
    if not ok then
        return { success = false, message = err }
    end

    TriggerClientEvent('w-shops:client:refreshShops', -1)

    return { success = true, message = 'Shop deleted.' }
end)

lib.callback.register('w-shops:server:getShops', function(_)
    local all = registry.getAll()
    local payload = {}

    for shopId, shop in pairs(all) do
        payload[shopId] = storage.serializeValue(shop)
    end

    return payload
end)

lib.callback.register('w-shops:manager:getItems', function(source)
    if not canManage(source) then return nil end

    local items = {}
    local oxItems = exports.ox_inventory:Items()

    for name, data in pairs(oxItems) do
        items[#items + 1] = {
            name = name,
            label = data.label or name,
            description = data.description,
        }
    end

    table.sort(items, function(a, b)
        return a.label < b.label
    end)

    return items
end)

lib.callback.register('w-shops:manager:getJobs', function(source)
    if not canManage(source) then return nil end

    local jobs = {}
    local ok, sharedJobs = pcall(function()
        return exports.qbx_core:GetJobs()
    end)

    if ok and type(sharedJobs) == 'table' then
        for name, data in pairs(sharedJobs) do
            local grades = {}

            if type(data) == 'table' and type(data.grades) == 'table' then
                for gradeLevel, gradeData in pairs(data.grades) do
                    local level = tonumber(gradeLevel) or 0
                    local label = name

                    if type(gradeData) == 'table' and gradeData.name then
                        label = gradeData.name
                    else
                        label = ('Grade %d'):format(level)
                    end

                    grades[#grades + 1] = {
                        value = level,
                        label = label,
                    }
                end

                table.sort(grades, function(a, b)
                    return a.value < b.value
                end)
            end

            jobs[#jobs + 1] = {
                value = name,
                label = (type(data) == 'table' and data.label) or name,
                grades = grades,
            }
        end
    end

    table.sort(jobs, function(a, b)
        return a.label < b.label
    end)

    return jobs
end)
