local Shops = {}

RegisterNetEvent('w-shops:client:setShops', function(shops)
    Shops = shops or {}
end)

local function requestShops()
    local data = lib.callback.await('w-shops:server:getShops', false)
    Shops = data or {}
    return Shops
end

local function getShops()
    if not next(Shops) then
        requestShops()
    end
    return Shops
end

local function getShop(shopId)
    return getShops()[shopId]
end

return {
    getShops = getShops,
    getShop = getShop,
    requestShops = requestShops,
    setShops = function(shops) Shops = shops or {} end,
}
