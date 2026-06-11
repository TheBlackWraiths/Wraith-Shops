local sharedConfig = require 'config.shared'
local debugMode = require 'client.debug'

local isManagerOpen = false

---@param event string
---@param data? table
local function managerLog(event, data)
    debugMode.log(('[manager] %s'):format(event), data)
end

local function closeManager()
    managerLog('close')
    isManagerOpen = false
    TriggerEvent('w-shops:client:closeNui')
end

local function openManager()
    managerLog('open')
    local allowed = lib.callback.await('w-shops:manager:canOpen', false)

    if not allowed then
        managerLog('open denied')
        lib.notify({
            type = 'error',
            description = 'No permission for /' .. sharedConfig.manager.command,
        })
        return
    end

    isManagerOpen = true
    SetNuiFocus(true, true)
    SendReactMessage('setVisible', true)
    SendReactMessage('openView', { type = 'manager' })
end

RegisterCommand(sharedConfig.manager.command, function()
    if isManagerOpen then
        closeManager()
        return
    end

    openManager()
end, false)

RegisterNUICallback('managerClose', function(_, cb)
    managerLog('managerClose')
    closeManager()
    cb({})
end)

RegisterNUICallback('managerListShops', function(_, cb)
    managerLog('managerListShops')
    local shops = lib.callback.await('w-shops:manager:listShops', false)
    managerLog('managerListShops result', { count = shops and #shops or 0 })
    cb(shops or {})
end)

RegisterNUICallback('managerGetShop', function(data, cb)
    managerLog('managerGetShop', data)
    local shop = lib.callback.await('w-shops:manager:getShop', false, data.shopId)
    cb(shop or {})
end)

RegisterNUICallback('managerSaveShop', function(data, cb)
    managerLog('managerSaveShop', { shopId = data.shopId, shop = data.shop })
    local result = lib.callback.await('w-shops:manager:saveShop', false, data.shopId, data.shop)
    if result.success then
        lib.notify({ type = 'success', description = result.message })
    else
        lib.notify({ type = 'error', description = result.message })
    end
    managerLog('managerSaveShop result', result)
    cb(result)
end)

RegisterNUICallback('managerDeleteShop', function(data, cb)
    managerLog('managerDeleteShop', data)
    local result = lib.callback.await('w-shops:manager:deleteShop', false, data.shopId)
    if result.success then
        lib.notify({ type = 'success', description = result.message })
    else
        lib.notify({ type = 'error', description = result.message })
    end
    managerLog('managerDeleteShop result', result)
    cb(result)
end)

RegisterNUICallback('managerGetItems', function(_, cb)
    managerLog('managerGetItems')
    local items = lib.callback.await('w-shops:manager:getItems', false)
    managerLog('managerGetItems result', { count = items and #items or 0 })
    cb(items or {})
end)

RegisterNUICallback('managerGetJobs', function(_, cb)
    managerLog('managerGetJobs')
    local jobs = lib.callback.await('w-shops:manager:getJobs', false)
    managerLog('managerGetJobs result', { count = jobs and #jobs or 0 })
    cb(jobs or {})
end)

RegisterNUICallback('managerGetDebugMode', function(_, cb)
    managerLog('managerGetDebugMode')
    cb({ enabled = debugMode.isEnabled() })
end)

RegisterNUICallback('managerSetDebugMode', function(data, cb)
    managerLog('managerSetDebugMode', data)
    debugMode.setEnabled(data.enabled == true)
    cb({ success = true, enabled = debugMode.isEnabled() })
end)

RegisterNUICallback('managerGetCoords', function(_, cb)
    managerLog('managerGetCoords')
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    cb({
        x = coords.x,
        y = coords.y,
        z = coords.z,
        w = heading,
    })
end)

local function hideUiForPlacement()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendReactMessage('setUiHidden', true)
end

local function restoreUiAfterPlacement()
    if not isManagerOpen then return end

    SendReactMessage('setUiHidden', false)
    SetNuiFocus(true, true)
end

RegisterNUICallback('managerPlaceLocation', function(data, cb)
    managerLog('managerPlaceLocation', data)

    if not isManagerOpen then
        cb({ success = false })
        return
    end

    local placementType = data.type
    if placementType ~= 'zone' and placementType ~= 'model' then
        cb({ success = false })
        return
    end

    hideUiForPlacement()

    local result = exports[GetCurrentResourceName()]:StartLocationPlacement({
        type = placementType,
        model = data.model,
        radius = data.radius,
    })

    restoreUiAfterPlacement()

    managerLog('managerPlaceLocation result', result)
    cb(result or { success = false })
end)

AddEventHandler('w-shops:client:closeManager', function()
    isManagerOpen = false
end)

exports('OpenShopManager', openManager)
exports('CloseShopManager', closeManager)
