local debugMode = require 'client.debug'

local isShopOpen = false
local isAnyNuiOpen = false

local function closeAllNui()
    isShopOpen = false
    isAnyNuiOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendReactMessage('setVisible', false)
end

local function closeShop()
    closeAllNui()
end

local function openShopNui(shopData)
    debugMode.log('Opening shop NUI', { id = shopData.id, name = shopData.name, items = shopData.items and #shopData.items or 0 })
    isShopOpen = true
    isAnyNuiOpen = true
    SetNuiFocus(true, true)
    SendReactMessage('setVisible', true)
    SendReactMessage('openView', { type = 'shop', data = shopData })
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeAllNui()
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    closeAllNui()
end)

CreateThread(function()
    closeAllNui()
end)

RegisterNUICallback('hideFrame', function(_, cb)
    TriggerEvent('w-shops:client:closeManager')
    closeAllNui()
    cb({})
end)

RegisterNUICallback('purchase', function(data, cb)
    debugMode.log('purchase', data)

    if not isShopOpen then
        cb({ success = false, message = 'Shop is not open.' })
        return
    end

    local result = lib.callback.await('w-shops:server:purchase', false, data)
    debugMode.log('purchase result', result)

    lib.notify({
        type = result.success and 'success' or 'error',
        description = result.message,
    })

    cb(result)
end)

exports('OpenShop', function(shopId, locationIndex)
    TriggerEvent('w-shops:client:openShop', shopId, locationIndex)
end)

exports('CloseShop', closeShop)
exports('CloseAllNui', closeAllNui)

RegisterNetEvent('w-shops:client:openShopResult', function(shopData)
    if not shopData then
        lib.notify({ type = 'error', description = 'Unable to open shop.' })
        return
    end
    openShopNui(shopData)
end)

RegisterNetEvent('w-shops:client:closeNui', closeAllNui)
