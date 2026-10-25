-- Keyboard-only actions made available to the gamepad (Bindings.lua, world layer).
--
-- Vanilla handles these keys in OnKeyPressed/OnKeyStartPressed handlers that act for
-- getSpecificPlayer(0) / getPlayer() and know nothing about the gamepad, so a controller
-- player can't use them at all (or only through a wheel). Each action here does what the
-- key handler does, for the player of the controller. All of them are unbound by default:
-- bind.<id>=<button> in ~/Zomboid/GamepadTweaks.properties.
-- label: the vanilla key binding name (UI_optionscreen_binding_*), for the settings panel.

require "GamepadTweaks/Bindings"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISFirearmRadialMenu"
require "TimedActions/ISGrabCorpseAction"
require "Foraging/ISSearchManager"
require "Vehicles/ISUI/ISVehicleMenu"

local Bindings = GamepadTweaks.Bindings

-- The controller's player when it can act: alive, game not paused.
local function actor(jd)
	local playerObj = jd.player and getSpecificPlayer(jd.player)
	if not playerObj or playerObj:isDead() or isGamePaused() then return nil end
	return playerObj
end

-- Hands and items -----------------------------------------------------------------

local function isBusy(playerObj)
	local queue = ISTimedActionQueue.queues[playerObj]
	return (queue and #queue.queue > 0) or getCell():getDrag(playerObj:getPlayerNum()) ~= nil
end

local function predicateLightSource(item)
	return item:canEmitLight() and item:getLightStrength() > 0
end

local function compareLightStrength(a, b)
	return a:getLightStrength() - b:getLightStrength()
end

local function isToggleableLight(item)
	return item ~= nil and item:canEmitLight() and item:getType() ~= "CandleLit"
		and item:getType() ~= "Lantern_HurricaneLit"
end

local function toggle(playerObj, item)
	if item:canBeActivated() then
		item:setActivated(not item:isActivated())
		syncItemActivated(playerObj, item)
		item:playActivateDeactivateSound()
	end
end

-- ItemBindingHandler.toggleLight (LIGHT_SOURCE key tap, ISLightSourceRadialMenu.onKeyReleased):
-- the light in the off hand, else in the main hand, else an attached one, else equip the
-- strongest light from the inventory.
local function lightSource(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	if playerObj:isCurrentlyBusy() and isBusy(playerObj) then return end
	local secondary = playerObj:getSecondaryHandItem()
	if isToggleableLight(secondary) then return toggle(playerObj, secondary) end
	local primary = playerObj:getPrimaryHandItem()
	if isToggleableLight(primary) then return toggle(playerObj, primary) end
	local attached = playerObj:getAttachedItems()
	for i = 1, attached:size() do
		local item = attached:getItemByIndex(i - 1)
		if isToggleableLight(item) and not instanceof(item, "HandWeapon") then
			return toggle(playerObj, item)
		end
	end
	if playerObj:isAiming() then return end
	local light = playerObj:getInventory():getBestEvalRecurse(predicateLightSource, compareLightStrength)
	if light then
		ISInventoryPaneContextMenu.transferIfNeeded(playerObj, light)
		ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, light, 50, instanceof(light, "HandWeapon"), false))
	end
end

-- CFarming_Interact.FastDropItem (DROP_* keys): favorites are kept.
local function dropper(bag, secondary, primary)
	return function(c, jd)
		local playerObj = actor(jd)
		if not playerObj then return end
		local playerNum = playerObj:getPlayerNum()
		local function drop(item)
			if item and not item:isFavorite() then
				ISInventoryPaneContextMenu.dropItem(item, playerNum)
			end
		end
		if bag then drop(playerObj:getClothingItem_Back()) end
		if secondary then drop(playerObj:getSecondaryHandItem()) end
		if primary then drop(playerObj:getPrimaryHandItem()) end
	end
end

-- ISGrabCorpseAction.OnKeyPressed / PerformGrabCorpse (GRAB_CORPSE key, uses getPlayer()):
-- let go of a dragged corpse, or empty the hands and grab the closest one.
local function grabCorpse(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	if playerObj:isDraggingCorpse() then
		playerObj:setDoGrappleLetGo()
		return
	end
	local body = playerObj:findClosestCorpseOnGroundToPickup()
	if not body then return end
	if playerObj:isSitOnGround() then
		playerObj:setVariable("forceGetUp", true)
	end
	local primary = playerObj:getPrimaryHandItem()
	if primary then
		ISTimedActionQueue.add(ISUnequipAction:new(playerObj, primary, 50))
	end
	local secondary = playerObj:getSecondaryHandItem()
	if secondary and secondary ~= primary then
		ISTimedActionQueue.add(ISUnequipAction:new(playerObj, secondary, 50))
	end
	ISTimedActionQueue.add(ISGrabCorpseAction:new(playerObj, body))
end

-- ISFirearmRadialMenu.checkKey (SHARPEN_WEAPON key): sharpen the main hand weapon.
local function sharpenWeapon(c, jd)
	local playerObj = actor(jd)
	if not playerObj or isBusy(playerObj) then return end
	local item = playerObj:getPrimaryHandItem()
	if item and item:isSharpenable() then
		ISFirearmRadialMenu.sharpenWeapon(item, playerObj)
	end
end

-- Character -------------------------------------------------------------------------

-- ISSitOnGround onKeyPress (SIT_ON_GROUND key): sit down or get up, not in a vehicle.
local function sitOnGround(c, jd)
	local playerObj = actor(jd)
	if not playerObj or playerObj:getVehicle() then return end
	if playerObj:isSitting() then
		playerObj:StopAllActionQueue()
		playerObj:setVariable("forceGetUp", true)
	else
		playerObj:setAutoWalk(false)
		playerObj:reportEvent("EventSitOnGround")
	end
end

-- ISSearchManager.handleKeyPressed (TOGGLE_SEARCH_MODE key).
local function searchMode(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	local manager = ISSearchManager.getManager(playerObj)
	if manager then
		manager:toggleSearchMode()
		manager:bringToTop()
	end
end

-- SHOUT key: on foot ISEmoteRadialMenu.onKeyReleased (tap), as a passenger
-- ISVehicleMenu.onKeyPressed; the driver has the horn.
local function shout(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	local vehicle = playerObj:getVehicle()
	if not vehicle then
		playerObj:Callout(true)
	elseif not vehicle:isDriver(playerObj) then
		playerObj:Callout()
	end
end

-- CFarming_Interact.ChangeClimbDirection (RELEASE_ROPE key).
local function releaseRope(c, jd)
	local playerObj = actor(jd)
	if playerObj and playerObj:isClimbingRope() then
		playerObj:fallFromRope()
	end
end

-- Vehicle ---------------------------------------------------------------------------
-- ISVehicleMenu.onKeyPressed / onKeyStartPressed, ItemBindingHandler.toggleLight (headlights).

local function inVehicle(jd)
	local playerObj = actor(jd)
	local vehicle = playerObj and playerObj:getVehicle()
	return playerObj, vehicle
end

local function engine(c, jd)
	local playerObj, vehicle = inVehicle(jd)
	if not vehicle then return end
	if vehicle:isEngineRunning() then
		ISVehicleMenu.onShutOff(playerObj)
	else
		ISVehicleMenu.onStartEngine(playerObj)
	end
end

local function headlights(c, jd)
	local playerObj, vehicle = inVehicle(jd)
	if vehicle and vehicle:isDriver(playerObj) and not playerObj:isAiming() and vehicle:hasHeadlights() then
		ISVehicleMenu.onToggleHeadlights(playerObj)
	end
end

local function heater(c, jd)
	local playerObj, vehicle = inVehicle(jd)
	if vehicle then
		ISVehicleMenu.onToggleHeater(playerObj)
	end
end

-- Held: sounds while the button is down.
local function hornStart(c, jd)
	local playerObj, vehicle = inVehicle(jd)
	if vehicle and vehicle:isDriver(playerObj) then
		ISVehicleMenu.onHornStart(playerObj)
	end
end

local function hornStop(c, jd)
	local playerObj = jd.player and getSpecificPlayer(jd.player)
	local vehicle = playerObj and playerObj:getVehicle()
	if vehicle and vehicle:isDriver(playerObj) then
		ISVehicleMenu.onHornStop(playerObj)
	end
end

-- In a vehicle or next to one.
local function switchSeat(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	local vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)
	if vehicle and vehicle:getScript() and vehicle:getScript():getWheelCount() > 0 then
		ISVehicleMenu.onShowSeatUI(playerObj, vehicle)
	end
end

local function vehicleInfo(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	local vehicle = playerObj:getVehicle() or ISVehicleMenu.getVehicleToInteractWith(playerObj)
	if vehicle then
		ISVehicleMenu.onMechanic(playerObj, vehicle)
	end
end

local ACTIONS = {
	{ id = "lightSource", label = "Equip/Turn On/Off Light Source", run = lightSource },
	{ id = "dropPrimary", label = "DropPrimaryHeldItem", run = dropper(false, false, true) },
	{ id = "dropSecondary", label = "DropSecondaryHeldItem", run = dropper(false, true, false) },
	{ id = "dropBothHands", label = "DropBothHeldItems", run = dropper(false, true, true) },
	{ id = "dropBag", label = "DropWornBag", run = dropper(true, false, false) },
	{ id = "dropHandsAndBag", label = "DropBothHeldItemsAndWornBag", run = dropper(true, true, true) },
	{ id = "grabCorpse", label = "GrabCorpse", run = grabCorpse },
	{ id = "sharpenWeapon", label = "SharpenWeapon", run = sharpenWeapon },
	{ id = "sitOnGround", label = "SitOnGround", run = sitOnGround },
	{ id = "searchMode", label = "Toggle Search Mode", run = searchMode },
	{ id = "shout", label = "Shout", run = shout },
	{ id = "releaseRope", label = "ReleaseRope", run = releaseRope },
	{ id = "engine", label = "StartVehicleEngine", run = engine },
	{ id = "headlights", label = "ToggleVehicleHeadlights", run = headlights },
	{ id = "heater", label = "VehicleHeater", run = heater },
	{ id = "horn", label = "VehicleHorn", run = hornStart, release = hornStop },
	{ id = "switchSeat", label = "VehicleSwitchSeat", run = switchSeat },
	{ id = "vehicleInfo", label = "VehicleMechanics", run = vehicleInfo },
}

for _, action in ipairs(ACTIONS) do
	action.layer = "world"
	action.category = "main"
	action.label = "UI_optionscreen_binding_" .. action.label
	Bindings.add(action)
end
