local shops = require 'client.shops'
local bridge = require 'client.bridge'
local debugMode = require 'client.debug'
local locations = require 'shared.locations'

local points = {}
local modelTargets = {}
local zoneNames = {}

local function createBlip(coords, blipConfig, label)
    if not coords or coords.x == nil or coords.y == nil or coords.z == nil then
        return nil
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, blipConfig.id)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, blipConfig.scale)
    SetBlipColour(blip, blipConfig.colour)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

---@param shopId string
---@param locationIndex number
---@param shop table
---@param location table
---@return table
local function buildTargetOption(shopId, locationIndex, shop, location)
    local restriction = locations.getJobRestriction(shop, location)

    return {
        name = ('w-shops:%s:%s'):format(shopId, locationIndex),
        icon = location.icon or shop.icon or 'fas fa-shopping-basket',
        label = location.label or shop.name,
        distance = location.distance or 2.0,
        groups = restriction,
        canInteract = function()
            return bridge.canAccessShop(shop, location)
        end,
        onSelect = function()
            debugMode.log(('Target selected %s:%s'):format(shopId, locationIndex))
            TriggerEvent('w-shops:client:openShop', shopId, locationIndex)
        end,
    }
end

---@param shopId string
---@param locationIndex number
---@param shop table
---@param location table
local function registerZoneTarget(shopId, locationIndex, shop, location)
    if not location.loc then
        print(('^3[w-shops]^0 Skipping zone %s:%s — missing coordinates. Re-add it in /shopmanager.'):format(shopId, locationIndex))
        return
    end

    local zoneName = ('w-shops-zone:%s:%s'):format(shopId, locationIndex)
    zoneNames[#zoneNames + 1] = zoneName
    local option = buildTargetOption(shopId, locationIndex, shop, location)
    local showDebug = debugMode.isEnabled() or location.debug

    if location.radius then
        debugMode.log(
            ('Registered sphere zone %s:%s'):format(shopId, locationIndex),
            {
                name = zoneName,
                coords = location.loc,
                radius = location.radius,
                debug = showDebug,
            }
        )

        exports.ox_target:addSphereZone({
            name = zoneName,
            coords = vec3(location.loc.x, location.loc.y, location.loc.z),
            radius = location.radius,
            debug = showDebug,
            options = { option },
        })
        return
    end

    local minZ = location.minZ or -1.0
    local maxZ = location.maxZ or 2.0
    local height = maxZ - minZ
    local centerZ = location.loc.z + (minZ + maxZ) / 2

    debugMode.log(
        ('Registered box zone %s:%s'):format(shopId, locationIndex),
        {
            name = zoneName,
            coords = vec3(location.loc.x, location.loc.y, centerZ),
            size = vec3(location.length or 1.5, location.width or 1.5, height),
            rotation = location.heading or 0.0,
            debug = showDebug,
        }
    )

    exports.ox_target:addBoxZone({
        name = zoneName,
        coords = vec3(location.loc.x, location.loc.y, centerZ),
        size = vec3(location.length or 1.5, location.width or 1.5, height),
        rotation = location.heading or 0.0,
        debug = showDebug,
        options = { option },
    })
end

local function onEnterPed(point)
    if point.pedHandle and DoesEntityExist(point.pedHandle) then return end

    local model = locations.hashModel(point.location.model or point.location.ped)
    if not lib.requestModel(model, 5000) then return end

    local spawnCoords = point.location.coords
    local x, y, z, heading

    if spawnCoords then
        x, y, z, heading = spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w
    else
        local loc = point.location.loc
        x, y, z = loc.x, loc.y, loc.z
        heading = point.location.heading or 0.0
    end

    local ped = CreatePed(0, model, x, y, z - 1.0, heading, false, false)
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if point.location.scenario then
        TaskStartScenarioInPlace(ped, point.location.scenario, 0, true)
    end

    exports.ox_target:addLocalEntity(ped, {
        buildTargetOption(point.shopId, point.locationIndex, point.shop, point.location),
    })

    point.pedHandle = ped
end

local function onExitPed(point)
    if point.pedHandle and DoesEntityExist(point.pedHandle) then
        exports.ox_target:removeLocalEntity(point.pedHandle)
        DeleteEntity(point.pedHandle)
    end

    point.pedHandle = nil
end

local function getSpawnTransform(location)
    local spawnCoords = location.coords

    if spawnCoords then
        return spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w or location.heading or 0.0
    end

    local loc = location.loc
    if loc then
        return loc.x, loc.y, loc.z, location.heading or 0.0
    end
end

local function onEnterProp(point)
    if point.propHandle and DoesEntityExist(point.propHandle) then return end

    local models = locations.getLocationModels(point.location)
    if #models == 0 then return end

    local model = models[1]
    if not lib.requestModel(model, 5000) then return end

    local x, y, z, heading = getSpawnTransform(point.location)
    if not x then return end

    local prop = CreateObject(model, x, y, z, false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityAsMissionEntity(prop, true, true)
    SetEntityHeading(prop, heading)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)
    SetEntityInvincible(prop, true)

    exports.ox_target:addLocalEntity(prop, {
        buildTargetOption(point.shopId, point.locationIndex, point.shop, point.location),
    })

    point.propHandle = prop
end

local function onExitProp(point)
    if point.propHandle and DoesEntityExist(point.propHandle) then
        exports.ox_target:removeLocalEntity(point.propHandle)
        DeleteEntity(point.propHandle)
    end

    point.propHandle = nil
end

---@param shopId string
---@param locationIndex number
---@param shop table
---@param location table
local function registerPedTarget(shopId, locationIndex, shop, location)
    local pointCoords = locations.getLocationCoords(location)

    if not pointCoords then
        print(('^3[w-shops]^0 Skipping ped %s:%s — missing coordinates. Re-add it in /shopmanager.'):format(shopId, locationIndex))
        return
    end

    if shop.blip and shop.blip.enabled ~= false and location.blip ~= false then
        createBlip(pointCoords, shop.blip, shop.name)
    end

    debugMode.log(
        ('Registered ped target %s:%s'):format(shopId, locationIndex),
        { coords = pointCoords, model = location.model or location.ped }
    )

    points[#points + 1] = lib.points.new({
        coords = pointCoords,
        distance = location.spawnDistance or 60.0,
        shopId = shopId,
        locationIndex = locationIndex,
        shop = shop,
        location = location,
        pedHandle = nil,
        onEnter = onEnterPed,
        onExit = onExitPed,
    })
end

---@param shopId string
---@param locationIndex number
---@param shop table
---@param location table
local function registerModelTarget(shopId, locationIndex, shop, location)
    local models = locations.getLocationModels(location)
    if #models == 0 then return end

    local pointCoords = locations.getLocationCoords(location)

    if pointCoords then
        if shop.blip and shop.blip.enabled ~= false and location.blip ~= false then
            createBlip(pointCoords, shop.blip, shop.name)
        end

        points[#points + 1] = lib.points.new({
            coords = pointCoords,
            distance = location.spawnDistance or 60.0,
            shopId = shopId,
            locationIndex = locationIndex,
            shop = shop,
            location = location,
            propHandle = nil,
            onEnter = onEnterProp,
            onExit = onExitProp,
        })

        return
    end

    local targetName = ('w-shops:%s:%s'):format(shopId, locationIndex)

    debugMode.log(
        ('Registered model target %s:%s'):format(shopId, locationIndex),
        { models = models, name = targetName }
    )

    exports.ox_target:removeModel(models, targetName)
    exports.ox_target:addModel(models, {
        buildTargetOption(shopId, locationIndex, shop, location),
    })

    modelTargets[#modelTargets + 1] = {
        models = models,
        name = targetName,
    }
end

local function registerShopLocations(shopId, shop)
    local shopLocations = locations.getShopLocations(shop)
    if #shopLocations == 0 then return end

    for i = 1, #shopLocations do
        local location = shopLocations[i]

        if location.type == 'zone' then
            if shop.blip and shop.blip.enabled ~= false and i == 1 and location.blip ~= false then
                createBlip(location.loc, shop.blip, shop.name)
            end

            registerZoneTarget(shopId, i, shop, location)
        elseif location.type == 'ped' then
            registerPedTarget(shopId, i, shop, location)
        elseif location.type == 'model' then
            registerModelTarget(shopId, i, shop, location)
        end
    end
end

local function cleanupTargets()
    debugMode.log('Cleaning up shop targets', {
        points = #points,
        modelTargets = #modelTargets,
        zones = #zoneNames,
    })

    for i = 1, #points do
        local point = points[i]
        if point.pedHandle and DoesEntityExist(point.pedHandle) then
            exports.ox_target:removeLocalEntity(point.pedHandle)
            DeleteEntity(point.pedHandle)
        end
        if point.propHandle and DoesEntityExist(point.propHandle) then
            exports.ox_target:removeLocalEntity(point.propHandle)
            DeleteEntity(point.propHandle)
        end
        point:remove()
    end

    for i = 1, #modelTargets do
        local entry = modelTargets[i]
        exports.ox_target:removeModel(entry.models, entry.name)
    end

    for i = 1, #zoneNames do
        exports.ox_target:removeZone(zoneNames[i])
    end

    table.wipe(points)
    table.wipe(modelTargets)
    table.wipe(zoneNames)
end

local function refreshAllTargets()
    debugMode.log('Refreshing all shop targets')

    cleanupTargets()
    shops.requestShops()

    local shopCount = 0
    for shopId, shop in pairs(shops.getShops()) do
        shopCount += 1
        debugMode.log(('Registering shop locations for %s'):format(shopId), shop.name)
        registerShopLocations(shopId, shop)
    end

    debugMode.log('Target refresh complete', { shops = shopCount, zones = #zoneNames, points = #points })
end

RegisterNetEvent('w-shops:client:refreshShops', refreshAllTargets)

AddEventHandler('w-shops:client:debugModeChanged', function(enabled)
    debugMode.log('Debug mode changed', { enabled = enabled })
    refreshAllTargets()
end)

CreateThread(function()
    Wait(500)
    refreshAllTargets()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupTargets()
end)

return {
    registerShopLocations = registerShopLocations,
    cleanupTargets = cleanupTargets,
    refreshAllTargets = refreshAllTargets,
}
