---@param restriction string | table<string, number | number[]> | nil
---@return table<string, number | number[]> | nil
local function normalizeJobRestriction(restriction)
    if not restriction then return nil end

    if type(restriction) == 'string' then
        return { [restriction] = 0 }
    end

    return restriction
end

---@param shop table
---@param location? table
---@return table<string, number | number[]> | nil
local function getJobRestriction(shop, location)
    local restriction

    if location then
        restriction = location.jobRestriction or location.groups or location.jobs
    end

    if not restriction then
        restriction = shop.jobRestriction or shop.groups or shop.jobs
    end

    return normalizeJobRestriction(restriction)
end

---@param location table
---@return 'zone' | 'ped' | 'model'
local function getLocationType(location)
    if location.type then
        return location.type
    end

    if location.ped or (location.model and location.coords and not location.loc) then
        return 'ped'
    end

    if location.models or (location.model and not location.coords) then
        return 'model'
    end

    return 'zone'
end

---@param location table
---@return table
local function normalizeLocation(location)
    local normalized = lib.table.clone(location)
    normalized.type = getLocationType(normalized)

    if normalized.type == 'ped' and normalized.ped and not normalized.model then
        normalized.model = normalized.ped
    end

    if normalized.type == 'model' and normalized.model and not normalized.models then
        normalized.models = { normalized.model }
    end

    if normalized.type == 'zone' and normalized.coords and not normalized.loc then
        normalized.loc = normalized.coords
    end

    if normalized.type == 'ped' and normalized.loc and not normalized.coords then
        local loc = normalized.loc
        normalized.coords = vec4(loc.x, loc.y, loc.z, normalized.heading or 0.0)
    end

    if normalized.type == 'model' and normalized.coords and normalized.heading and not normalized.coords.w then
        normalized.coords = vec4(
            normalized.coords.x,
            normalized.coords.y,
            normalized.coords.z,
            normalized.heading
        )
    end

    if normalized.type == 'model' and normalized.loc and not normalized.coords then
        local loc = normalized.loc
        normalized.coords = vec4(loc.x, loc.y, loc.z, normalized.heading or 0.0)
    end

    return normalized
end

---@param shop table
---@return table[]
local function getShopLocations(shop)
    local raw = shop.locations or shop.targets or {}
    local locations = {}

    for i = 1, #raw do
        locations[i] = normalizeLocation(raw[i])
    end

    return locations
end

---@param shop table
---@param locationIndex number
---@return table?
local function getShopLocation(shop, locationIndex)
    local locations = getShopLocations(shop)
    return locations[locationIndex]
end

---@param location table
---@return vector3?
local function getLocationCoords(location)
    if location.type == 'ped' then
        if location.coords then
            return vec3(location.coords.x, location.coords.y, location.coords.z)
        end

        if location.loc then
            return location.loc
        end
    end

    if location.type == 'zone' then
        return location.loc or location.coords
    end

    if location.type == 'model' then
        if location.coords then
            return vec3(location.coords.x, location.coords.y, location.coords.z)
        end

        if location.loc then
            return location.loc
        end
    end
end

---@param model string | number
---@return number
local function hashModel(model)
    if type(model) == 'string' then
        return joaat(model)
    end

    return model
end

---@param location table
---@return number[]
local function getLocationModels(location)
    local models = location.models or {}
    local hashed = {}

    for i = 1, #models do
        hashed[i] = hashModel(models[i])
    end

    return hashed
end

return {
    normalizeJobRestriction = normalizeJobRestriction,
    getJobRestriction = getJobRestriction,
    getLocationType = getLocationType,
    normalizeLocation = normalizeLocation,
    getShopLocations = getShopLocations,
    getShopLocation = getShopLocation,
    getLocationCoords = getLocationCoords,
    hashModel = hashModel,
    getLocationModels = getLocationModels,
}
