---@param timeStr string?
---@return number
local function parseTimeMinutes(timeStr)
    if type(timeStr) ~= 'string' then return 0 end

    local hours, minutes = timeStr:match('^(%d%d?):(%d%d)$')
    if not hours or not minutes then return 0 end

    return tonumber(hours) * 60 + tonumber(minutes)
end

---@return number
local function getNowMinutes()
    return tonumber(os.date('%H')) * 60 + tonumber(os.date('%M'))
end

---@param shop table
---@return boolean
local function isShopOpen(shop)
    local hours = shop.operatingHours
    if not hours or not hours.enabled then
        return true
    end

    local now = getNowMinutes()
    local open = parseTimeMinutes(hours.open or '00:00')
    local close = parseTimeMinutes(hours.close or '23:59')

    if open <= close then
        return now >= open and now <= close
    end

    return now >= open or now <= close
end

return {
    isShopOpen = isShopOpen,
}
