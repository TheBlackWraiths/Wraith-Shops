local registry = require 'server.registry'
local sharedConfig = require 'config.shared'
local bridge = require 'server.bridge'
local locations = require 'shared.locations'

local function isNearShop(source, shopId, locationIndex)
    local shop = registry.get(shopId)
    local location = locations.getShopLocation(shop, locationIndex)
    if not location then return false end

    local coords = locations.getLocationCoords(location)
    if not coords then
        return location.type == 'model'
    end

    local ped = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(ped)
    local distance = #(playerCoords - coords)

    return distance <= (location.distance or 2.0) + 2.0
end

---@param shop table
---@return table<string, boolean>
local function getShopCurrencies(shop)
    local currencies = { [shop.currency or sharedConfig.defaultCurrency] = true }

    for i = 1, #shop.inventory do
        local item = shop.inventory[i]
        currencies[item.currency or shop.currency or sharedConfig.defaultCurrency] = true
    end

    return currencies
end

---@param source number
---@return table<string, number>
local function getPlayerBalances(source)
    local cash, bank = bridge.getMoneyBalances(source)
    local balances = {
        money = cash,
        bank = bank,
    }

    return balances
end

lib.callback.register('w-shops:server:getShopData', function(source, shopId, locationIndex)
    local shop = registry.get(shopId)
    local location = locations.getShopLocation(shop, locationIndex)

    if not shop or not isNearShop(source, shopId, locationIndex) then
        return nil
    end

    if not bridge.getPlayer(source) then
        return nil
    end

    if not bridge.canAccessShop(source, shop, location) then
        return nil
    end

    local defaultCurrency = shop.currency or sharedConfig.defaultCurrency
    local cash, bank = bridge.getMoneyBalances(source)
    local balances = getPlayerBalances(source)
    local inventory = {}

    for i = 1, #shop.inventory do
        local entry = shop.inventory[i]
        local oxItem = bridge.getOxItem(entry.name)

        if oxItem then
            local availability = bridge.getItemAvailability(source, entry, shop, location)
            local currency = entry.currency or defaultCurrency
            inventory[#inventory + 1] = {
                name = entry.name,
                label = entry.label or oxItem.label,
                description = entry.description,
                price = entry.price,
                count = entry.count,
                image = entry.image or sharedConfig.imagePath:format(entry.name),
                currency = currency,
                currencyLabel = bridge.getCurrencyLabel(currency),
                category = entry.category,
                canPurchase = availability.canPurchase,
                outOfStock = availability.outOfStock,
                restricted = availability.restricted,
                restrictions = availability.restrictions,
                restrictionLabel = availability.restrictionLabel,
            }
        end
    end

    return {
        id = shopId,
        name = shop.name,
        subtitle = shop.subtitle or 'Your neighborhood convenience store',
        categories = shop.categories or {},
        locationIndex = locationIndex,
        items = inventory,
        balance = cash,
        bank = bank,
        balances = balances,
        currency = defaultCurrency,
        currencyLabel = bridge.getCurrencyLabel(defaultCurrency),
    }
end)

lib.callback.register('w-shops:server:purchase', function(source, data)
    local shopId = data.shopId
    local locationIndex = data.locationIndex
    local cart = data.cart
    local paymentMethod = data.paymentMethod == 'bank' and 'bank' or 'cash'

    if type(shopId) ~= 'string' or type(locationIndex) ~= 'number' or type(cart) ~= 'table' then
        return { success = false, message = 'Invalid purchase request.' }
    end

    local shop = registry.get(shopId)
    local location = locations.getShopLocation(shop, locationIndex)

    if not shop or not isNearShop(source, shopId, locationIndex) then
        return { success = false, message = 'You are too far from the shop.' }
    end

    if not bridge.getPlayer(source) then
        return { success = false, message = 'Player not found.' }
    end

    if not bridge.canAccessShop(source, shop, location) then
        return { success = false, message = 'You do not have the required job for this shop.' }
    end

    if #cart == 0 then
        return { success = false, message = 'Your cart is empty.' }
    end

    local defaultCurrency = shop.currency or sharedConfig.defaultCurrency
    local priceIndex = {}

    for i = 1, #shop.inventory do
        local item = shop.inventory[i]
        priceIndex[item.name] = item
    end

    local charges = {}
    local validatedCart = {}

    for i = 1, #cart do
        local entry = cart[i]
        local itemName = entry.name
        local quantity = tonumber(entry.quantity)

        if type(itemName) ~= 'string' or not quantity or quantity < 1 or quantity > 100 then
            return { success = false, message = 'Invalid item in cart.' }
        end

        local shopItem = priceIndex[itemName]
        if not shopItem then
            return { success = false, message = ('%s is not sold here.'):format(itemName) }
        end

        local canBuy, reason = bridge.canPurchaseItem(source, shopItem, shop, location)
        if not canBuy then
            return { success = false, message = reason }
        end

        if shopItem.count and shopItem.count < quantity then
            return { success = false, message = ('Not enough stock for %s.'):format(itemName) }
        end

        if not bridge.canCarry(source, itemName, quantity, shopItem.metadata) then
            return { success = false, message = 'You cannot carry that much.' }
        end

        local currency = shopItem.currency or defaultCurrency
        local lineTotal = shopItem.price * quantity
        charges[currency] = (charges[currency] or 0) + lineTotal

        validatedCart[#validatedCart + 1] = {
            name = itemName,
            quantity = quantity,
            price = shopItem.price,
            currency = currency,
            metadata = shopItem.metadata,
        }
    end

    for currency, amount in pairs(charges) do
        if not bridge.canAffordPayment(source, paymentMethod, amount, currency) then
            local label = currency == 'money' and (paymentMethod == 'bank' and 'bank funds' or 'cash') or bridge.getCurrencyLabel(currency)
            return {
                success = false,
                message = ('Not enough %s.'):format(label),
            }
        end
    end

    local paid = {}

    for currency, amount in pairs(charges) do
        if not bridge.removePayment(source, paymentMethod, amount, currency) then
            for paidCurrency, paidAmount in pairs(paid) do
                bridge.refundPayment(source, paymentMethod, paidAmount, paidCurrency)
            end
            return { success = false, message = 'Payment failed.' }
        end

        paid[currency] = amount
    end

    local addedItems = {}

    for i = 1, #validatedCart do
        local entry = validatedCart[i]
        local added = bridge.oxItems:AddItem(source, entry.name, entry.quantity, entry.metadata)

        if not added then
            for j = 1, #addedItems do
                local rollback = addedItems[j]
                bridge.oxItems:RemoveItem(source, rollback.name, rollback.quantity, rollback.metadata)
            end

            for currency, amount in pairs(paid) do
                bridge.refundPayment(source, paymentMethod, amount, currency)
            end

            return { success = false, message = 'Purchase failed. Your payment was refunded.' }
        end

        addedItems[#addedItems + 1] = entry

        for j = 1, #shop.inventory do
            local shopStock = shop.inventory[j]
            if shopStock.name == entry.name and shopStock.count then
                shopStock.count -= entry.quantity
            end
        end
    end

    local balances = getPlayerBalances(source)

    return {
        success = true,
        message = ('Purchased %s item(s).'):format(#validatedCart),
        balance = balances.money,
        bank = balances.bank,
        balances = balances,
        total = charges[defaultCurrency] or 0,
    }
end)

---@param shopId string
---@param shopData table
exports('RegisterShop', function(shopId, shopData)
    registry.saveDynamic(shopId, shopData)
    TriggerClientEvent('w-shops:client:refreshShops', -1)
end)
