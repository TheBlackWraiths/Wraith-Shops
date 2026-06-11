local shops = require 'client.shops'
local bridge = require 'client.bridge'
local debugMode = require 'client.debug'
local locations = require 'shared.locations'

require 'client.targets'

local function enrichShopItems(inventory, defaultCurrency)
    local items = {}

    for i = 1, #inventory do
        local entry = inventory[i]
        local currency = entry.currency or defaultCurrency

        items[#items + 1] = {
            name = entry.name,
            label = entry.label or bridge.getItemLabel(entry.name),
            description = entry.description,
            price = entry.price,
            count = entry.count,
            currency = currency,
            currencyLabel = bridge.getCurrencyLabel(currency),
            image = entry.image or bridge.getItemImage(entry.name),
            category = entry.category,
            canPurchase = entry.canPurchase,
            outOfStock = entry.outOfStock,
            restricted = entry.restricted,
            restrictions = entry.restrictions,
            restrictionLabel = entry.restrictionLabel,
        }
    end

    return items
end

RegisterNetEvent('w-shops:client:openShop', function(shopId, locationIndex)
    debugMode.log('Opening shop', { shopId = shopId, locationIndex = locationIndex })

    local shop = shops.getShop(shopId)
    if not shop then
        debugMode.log('Shop not found', shopId)
        return
    end

    local location = locations.getShopLocation(shop, locationIndex)

    if not bridge.isShopOpen(shop) then
        debugMode.log('Shop closed', shopId)
        lib.notify({ type = 'error', description = 'This shop is currently closed.' })
        return
    end

    if not bridge.hasJobAccess(shop, location) then
        debugMode.log('Job access denied', { shopId = shopId, locationIndex = locationIndex })
        lib.notify({ type = 'error', description = 'You do not have the required job for this shop.' })
        return
    end

    local shopData = lib.callback.await('w-shops:server:getShopData', false, shopId, locationIndex)
    if not shopData then
        debugMode.log('Failed to load shop data', { shopId = shopId, locationIndex = locationIndex })
        lib.notify({ type = 'error', description = 'Unable to open shop.' })
        return
    end

    shopData.items = enrichShopItems(shopData.items, shopData.currency)
    debugMode.log('Shop data loaded', { shopId = shopId, items = #shopData.items })
    TriggerEvent('w-shops:client:openShopResult', shopData)
end)

CreateThread(function()
    shops.requestShops()
end)
