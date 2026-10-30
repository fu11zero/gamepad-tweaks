-- Keyboard-only actions made available to the gamepad (Bindings.lua, world layer).
--
-- Vanilla handles these keys in OnKeyPressed/OnKeyStartPressed handlers that act for
-- getSpecificPlayer(0) / getPlayer() and know nothing about the gamepad, so a controller
-- player can't use them at all (or only through a wheel). Each action here does what the
-- key handler does, for the player of the controller. All of them are unbound by default:
-- bind.<id>=<button> in ~/Zomboid/GamepadTweaks.properties.
-- label: the vanilla key binding name (UI_optionscreen_binding_*, or a full IGUI_ key),
-- category and group (main / extra), for the settings panel.

require "GamepadTweaks/Bindings"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISFirearmRadialMenu"
require "TimedActions/ISGrabCorpseAction"
require "Foraging/ISSearchManager"
require "Vehicles/ISUI/ISVehicleMenu"
require "ISUI/ISDPadWheels"
require "ISUI/ISUIHandler"
require "ISUI/Maps/ISWorldMap"
require "ISUI/SpeedControlsHandler"

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

-- The firearm radial (eject / insert magazine, load / unload rounds, rack). Vanilla opens it
-- only by holding the ReloadWeapon button (ISFirearmRadialMenu.onRepeatRBumper, after 500 ms
-- unless "instant reload radial"), so a tap / hold split is needed on that one button; here
-- it is its own action and opens at once. It closes and picks the slice on the release of
-- the button that opened it (hides: the vanilla RB, retargeted).
local function firearmRadial(c, jd)
	local playerObj = actor(jd)
	if not playerObj or JoypadState.disableReload then return end
	if playerObj:isAiming() or playerObj:isLookingWhileInVehicle() then return end
	if not ISFirearmRadialMenu.checkWeapon(playerObj) then return end
	if getPlayerRadialMenu(jd.player):isReallyVisible() then return end
	local menu = ISFirearmRadialMenu:new(playerObj)
	menu:fillMenu()
	menu:display()
	setPlayerButtonsActive(jd.player, false)
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

-- Extra: windows ---------------------------------------------------------------------
-- XpUpdate.displayCharacterInfo, ISWorldMap.onKeyReleased, SurvivalGuide.onKeyPressed act for
-- player 0 and don't give a controller the focus; the gamepad versions are the back button
-- wheel commands (ISBackButtonWheel:onCommand), used here.

-- Character info window on a tab (skills, health, protection, info); again closes it.
local function infoView(view)
	return function(c, jd)
		local playerObj = actor(jd)
		local playerNum = jd.player
		if not playerObj or not getPlayerData(playerNum) then return end
		local window = getPlayerInfoPanel(playerNum)
		window:toggleView(xpSystemText[view])
		if view == "health" and window.healthView then
			window.healthView.doctorLevel = playerObj:getPerkLevel(Perks.Doctor)
		end
		if window:getIsVisible() then
			setJoypadFocus(playerNum, window.panel:getActiveView())
		else
			setJoypadFocus(playerNum, nil)
		end
	end
end

local function entityWindow(name, open)
	return function(c, jd)
		local playerObj = actor(jd)
		if not playerObj then return end
		local window = ISEntityUI.GetWindowInstance(jd.player, name)
		if window then
			window:close()
		else
			open(playerObj, nil, "*")
		end
	end
end

local function map(c, jd)
	local playerObj = jd.player and getSpecificPlayer(jd.player)
	if not playerObj or playerObj:isDead() then return end
	if not ISWorldMap.IsAllowed() or Bindings.isTutorial() then return end
	if isGamePaused() and not (ISWorldMap_instance and ISWorldMap_instance:isVisible()) then return end
	ISWorldMap.ToggleWorldMap(jd.player)
end

local function survivalGuide(c, jd)
	if actor(jd) then
		ISDPadWheels.showSurvGuide(jd.player)
	end
end

-- Extra: hotbar ------------------------------------------------------------------------
-- ISHotbar.onKeyPressed: player 0 only, and not when that player uses a controller.

local function hotbar(slot)
	return function(c, jd)
		local playerObj = actor(jd)
		if not playerObj or playerObj:isAttacking() then return end
		local bar = getPlayerHotbar(jd.player)
		if not bar then return end
		local queue = ISTimedActionQueue.queues[playerObj]
		if queue and #queue.queue > 0 then return end
		bar:activateSlot(slot)
	end
end

-- Extra: game speed ----------------------------------------------------------------------
-- SpeedControlsHandler.onKeyPressed (keys only); not in multiplayer.

local function canChangeSpeed()
	return not isClient() and MainScreen.instance and MainScreen.instance.inGame
		and not MainScreen.instance:getIsVisible()
end

local function timePause(c, jd)
	if not canChangeSpeed() then return end
	if getGameSpeed() > 0 then
		SpeedControlsHandler.previousSpeed = getGameTime():getTrueMultiplier()
		setGameSpeed(0)
	else
		setGameSpeed(1)
		getGameTime():setMultiplier(SpeedControlsHandler.previousSpeed or 1)
		SpeedControlsHandler.previousSpeed = nil
	end
end

local function timeSpeed(speed, multiplier)
	return function(c, jd)
		if not canChangeSpeed() then return end
		setGameSpeed(speed)
		getGameTime():setMultiplier(multiplier)
	end
end

-- Extra: misc ------------------------------------------------------------------------------

-- ISBackButtonWheel:onCommand("MoveFurniture").
local function moveFurniture(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	local cursor = ISMoveableCursor:new(playerObj)
	getCell():setDrag(cursor, cursor.player)
end

-- ISUIHandler.onKeyPressed (TOGGLE_UI key).
local function toggleUI(c, jd)
	if not Bindings.isTutorial() then
		ISUIHandler.toggleUI()
	end
end

-- GameWindow.logic: TAKE_SCREENSHOT key.
local function screenshot(c, jd)
	getCore():TakeFullScreenshot(nil)
end

-- ISEquippedItem.onKeyPressed / toggleSafety (TOGGLE_SAFETY key; toggleSafety uses getPlayer()).
local function pvp(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	if not isClient() then
		IsoPlayer.setCoopPVP(not IsoPlayer.getCoopPVP())
		return
	end
	if not getServerOptions():getBoolean("SafetySystem") then return end
	local safety = playerObj:getSafety()
	if safety:isToggleAllowed() then
		safety:toggleSafety()
		ISLogSystem.logAction({ character = playerObj, Type = "Safety",
			getExtraLogData = function() return safety:isCurrent() and "Safety On" or "Safety Off" end })
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
	{ id = "firearmRadial", label = "UI_GamepadTweaks_action_firearmRadial", run = firearmRadial, hides = Joypad.RBumper },
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

	{ id = "map", label = "Map", run = map, category = "extra" },
	{ id = "craftingMenu", label = "Crafting UI", category = "extra",
		run = entityWindow("HandcraftWindow", function(...) ISEntityUI.OpenHandcraftWindow(...) end) },
	{ id = "buildingMenu", label = "Building UI", category = "extra",
		run = entityWindow("BuildWindow", function(...) ISEntityUI.OpenBuildWindow(...) end) },
	{ id = "skills", label = "Toggle Skill Panel", run = infoView("skills"), category = "extra" },
	{ id = "health", label = "Toggle Health Panel", run = infoView("health"), category = "extra" },
	{ id = "protection", label = "Toggle Clothing Protection Panel", run = infoView("protection"), category = "extra" },
	{ id = "info", label = "Toggle Info Panel", run = infoView("info"), category = "extra" },
	{ id = "survivalGuide", label = "Toggle Survival Guide", run = survivalGuide, category = "extra" },
	{ id = "timePause", label = "Pause", run = timePause, whilePaused = true, category = "extra" },
	{ id = "timeNormal", label = "Normal Speed", run = timeSpeed(1, 1), whilePaused = true, category = "extra" },
	{ id = "timeFast1", label = "Fast Forward x1", run = timeSpeed(2, 5), whilePaused = true, category = "extra" },
	{ id = "timeFast2", label = "Fast Forward x2", run = timeSpeed(3, 20), whilePaused = true, category = "extra" },
	{ id = "timeFast3", label = "Fast Forward x3", run = timeSpeed(4, 40), whilePaused = true, category = "extra" },
	{ id = "moveFurniture", label = "IGUI_BackButton_Movable", run = moveFurniture, category = "extra" },
	{ id = "toggleUI", label = "Toggle UI", run = toggleUI, whilePaused = true, category = "extra" },
	{ id = "screenshot", label = "Take screenshot", run = screenshot, whilePaused = true, category = "extra" },
	{ id = "pvp", label = "Toggle Safety", run = pvp, category = "extra" },
}

-- Section in the settings panel (UI_GamepadTweaks_cat_*); group: main / extra.
local CATEGORY = {
	lightSource = "hands", dropPrimary = "hands", dropSecondary = "hands", dropBothHands = "hands",
	dropBag = "hands", dropHandsAndBag = "hands", grabCorpse = "hands", sharpenWeapon = "hands",
	firearmRadial = "hands",
	sitOnGround = "character", searchMode = "character", shout = "character", releaseRope = "character",
	engine = "vehicle", headlights = "vehicle", heater = "vehicle", horn = "vehicle",
	switchSeat = "vehicle", vehicleInfo = "vehicle",
	map = "windows", craftingMenu = "windows", buildingMenu = "windows", skills = "windows",
	health = "windows", protection = "windows", info = "windows", survivalGuide = "windows",
	timePause = "time", timeNormal = "time", timeFast1 = "time", timeFast2 = "time", timeFast3 = "time",
}

for slot = 1, 8 do
	table.insert(ACTIONS, { id = "hotbar" .. slot, label = "Hotbar " .. slot, run = hotbar(slot), category = "extra" })
end

for _, action in ipairs(ACTIONS) do
	action.layer = "world"
	action.group = action.category == "extra" and "extra" or "main"
	action.category = CATEGORY[action.id] or (action.id:match("^hotbar") and "hotbar") or "misc"
	if not action.label:match("^IGUI_") and not action.label:match("^UI_GamepadTweaks_") then
		action.label = "UI_optionscreen_binding_" .. action.label
	end
	Bindings.add(action)
end
