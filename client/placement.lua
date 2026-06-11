local debugMode = require 'client.debug'

local placement = {}

local isPlacing = false

local DEFAULT_RADIUS = 1.5
local MIN_RADIUS = 0.1
local MAX_RADIUS = 15.0
local RAYCAST_INTERVAL_MS = 50

local PRESETS = {
	{ control = 157, label = "Small", radius = 1.0 },
	{ control = 158, label = "Normal", radius = 1.5 },
	{ control = 160, label = "Large", radius = 2.5 },
}

---@return number
local function getRadiusStep()
	if IsDisabledControlPressed(0, 21) then
		return 0.5
	end

	return 0.1
end

---@param radius number
---@return string
local function getZoneInstructionText(radius)
	return table.concat({
		"------ Zone Placement ------  \n",
		("Radius: %.1fm  \n"):format(radius),
		"Aim at the ground where the zone should go.  \n",
		"[Scroll] Resize zone  \n",
		"[Shift + Scroll] Resize faster  \n",
		"[1] Small (1.0m)  \n",
		"[2] Normal (1.5m)  \n",
		"[3] Large (2.5m)  \n",
		"[E] Confirm  \n",
		"[ESC] Cancel",
	})
end

---@param heading number
---@return string
local function getModelInstructionText(heading)
	return table.concat({
		"------ Prop Placement ------  \n",
		"Aim at the surface where the prop should go.  \n",
		("Heading: %.0f°  \n"):format(heading),
		"[Scroll] Rotate  \n",
		"[E] Confirm  \n",
		"[ESC] Cancel",
	})
end

---@param coords vector3
---@param radius number
local function drawSpherePreview(coords, radius)
	DrawMarker(
		28,
		coords.x,
		coords.y,
		coords.z,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
		radius,
		radius,
		radius,
		255,
		42,
		24,
		100,
		false,
		false,
		0,
		false,
		false,
		false,
		false
	)
end

---@param modelName string
---@return number?
local function createPreviewObject(modelName)
	local hash = joaat(modelName)

	if not IsModelInCdimage(hash) or not IsModelValid(hash) then
		return nil
	end

	if not lib.requestModel(hash, 5000) then
		return nil
	end

	local ped = PlayerPedId()
	local coords = GetEntityCoords(ped)
	local object = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)

	SetEntityAsMissionEntity(object, true, true)
	SetEntityCollision(object, false, false)
	FreezeEntityPosition(object, true)
	SetEntityAlpha(object, 160, false)
	SetEntityInvincible(object, true)

	if SetEntityDrawOutline then
		SetEntityDrawOutline(object, true)
		SetEntityDrawOutlineColor(91, 141, 239, 255)
	end

	SetModelAsNoLongerNeeded(hash)
	return object
end

---@param preview number?
local function cleanupPreview(preview)
	if preview and DoesEntityExist(preview) then
		if SetEntityDrawOutline then
			SetEntityDrawOutline(preview, false)
		end
		DeleteEntity(preview)
	end
end

---@param radius number
---@return number
local function clampRadius(radius)
	return math.min(MAX_RADIUS, math.max(MIN_RADIUS, radius))
end

---@param options { type: 'zone' | 'model', model?: string, radius?: number }
---@return table?
function placement.start(options)
	if isPlacing then
		return nil
	end

	local placementType = options.type
	if placementType ~= "zone" and placementType ~= "model" then
		return nil
	end

	debugMode.log('Placement started', options)

	isPlacing = true
	local heading = GetEntityHeading(PlayerPedId())
	local preview = nil
	local result = nil
	local radius = clampRadius(options.radius or DEFAULT_RADIUS)
	local lastHitCoords = nil
	local lastRaycastAt = 0
	local lastInstructionText = nil

	if placementType == "model" then
		local modelName = options.model or "prop_vend_soda_02"
		preview = createPreviewObject(modelName)

		if not preview then
			isPlacing = false
			lib.notify({
				type = "error",
				description = ("Unable to load model preview: %s"):format(modelName),
			})
			return { success = false }
		end
	end

	local function updateInstructionText()
		local text = placementType == "zone" and getZoneInstructionText(radius) or getModelInstructionText(heading)

		if text ~= lastInstructionText then
			lastInstructionText = text
			lib.showTextUI(text, { position = "right-center" })
		end
	end

	updateInstructionText()

	while isPlacing and result == nil do
		Wait(1)

		DisableControlAction(0, 24, true)
		DisableControlAction(0, 25, true)
		DisableControlAction(0, 47, true)
		DisableControlAction(0, 58, true)
		DisableControlAction(0, 140, true)
		DisableControlAction(0, 141, true)
		DisableControlAction(0, 142, true)
		DisableControlAction(0, 143, true)
		DisableControlAction(0, 257, true)
		DisableControlAction(0, 263, true)
		DisableControlAction(0, 264, true)

		local instructionChanged = false

		if placementType == "zone" then
			local step = getRadiusStep()

			if IsDisabledControlJustPressed(0, 241) then
				radius = clampRadius(radius + step)
				instructionChanged = true
			elseif IsDisabledControlJustPressed(0, 242) then
				radius = clampRadius(radius - step)
				instructionChanged = true
			end

			for i = 1, #PRESETS do
				local preset = PRESETS[i]
				if IsDisabledControlJustPressed(0, preset.control) then
					radius = preset.radius
					instructionChanged = true
					break
				end
			end
		else
			if IsDisabledControlJustPressed(0, 241) then
				heading = (heading + 5.0) % 360.0
				instructionChanged = true
			elseif IsDisabledControlJustPressed(0, 242) then
				heading = (heading - 5.0) % 360.0
				instructionChanged = true
			end
		end

		if instructionChanged then
			updateInstructionText()
		end

		local now = GetGameTimer()
		if now - lastRaycastAt >= RAYCAST_INTERVAL_MS then
			lastRaycastAt = now
			local hit, _, endCoords = lib.raycast.fromCamera(511, 4, 100.0)

			if hit and endCoords then
				lastHitCoords = endCoords

				if preview then
					SetEntityCoords(preview, endCoords.x, endCoords.y, endCoords.z, false, false, false, false)
					PlaceObjectOnGroundProperly(preview)
					SetEntityHeading(preview, heading)
				end
			end
		end

		if placementType == "zone" and lastHitCoords then
			drawSpherePreview(lastHitCoords, radius)
		end

		if lastHitCoords and IsControlJustPressed(0, 38) then
			local finalCoords = lastHitCoords

			if preview then
				finalCoords = GetEntityCoords(preview)
				heading = GetEntityHeading(preview)
			end

			result = {
				success = true,
				x = finalCoords.x + 0.0,
				y = finalCoords.y + 0.0,
				z = finalCoords.z + 0.0,
				w = heading + 0.0,
			}

			if placementType == "zone" then
				result.radius = radius + 0.0
			end
		end

		if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 200) then
			result = { success = false }
		end
	end

	lib.hideTextUI()
	cleanupPreview(preview)
	isPlacing = false

	debugMode.log('Placement finished', result)
	return result
end

exports("StartLocationPlacement", placement.start)
