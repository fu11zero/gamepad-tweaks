-- Keyboard-only actions made available to the gamepad (Bindings.lua, world layer).
--
-- Vanilla handles these keys in OnKeyPressed/OnKeyStartPressed handlers that act for
-- getSpecificPlayer(0) / getPlayer() and know nothing about the gamepad, so a controller
-- player can't use them at all (or only through a wheel). Each action here does what the
-- key handler does, for the player of the controller. All of them are unbound by default
-- (bind.<id>=<button> in ~/Zomboid/GamepadTweaks.properties), except the camera pan: RB while
-- aiming, the button vanilla hardcodes for it (PlayerCamera.update, see CameraPan.java).
-- Also the Shift variants of Interact / Rack and the tool use of the context key, below.
-- label: the vanilla key binding name (UI_optionscreen_binding_*, or a full IGUI_ key),
-- category and group (main / extra), for the settings panel; layer: world unless set.

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

-- Held, in Java (HeldActions): the game asks each frame whether it is held.
local function held(name)
	local function set(jd, down)
		if GamepadTweaks_setActionHeld then GamepadTweaks_setActionHeld(jd.id, name, down) end
	end
	return function(c, jd) set(jd, true) end, function(c, jd) set(jd, false) end
end

-- Camera pan while aiming ("look far"): vanilla pans a gamepad player's camera only with RB
-- held (PlayerCamera.update, hardcoded); CameraPan.java, towards the reticle.
local panRun, panRelease = held("panCamera")

-- AnimalContextMenu.showRadialMenu (ANIMAL_RADIAL_MENU key, ISUIHandler: player 0 only);
-- again closes it.
local function animalRadial(c, jd)
	local playerObj = actor(jd)
	if not playerObj or playerObj:getVehicle() or not AnimalContextMenu then return end
	local menu = getPlayerRadialMenu(jd.player)
	if menu and menu:isReallyVisible() then
		menu:undisplay()
		setJoypadFocus(jd.player, nil)
		return
	end
	AnimalContextMenu.showRadialMenu(playerObj)
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

-- ROTATE_BUILDING key: the build cursor (getCell():getDrag) turns on it in rotateKey (keyboard
-- key, player 0's OnKeyPressed) or on RB in its onJoypadPressButton; the 3D item placement
-- (ISPlace3DItemCursor) turns while RB is held (checkRotateJoypad -> handleRotate: a tap is a
-- step, holding spins). Here the cursor of the controller's player; ISMoveableCursor takes the
-- second argument as "from the gamepad" (no key check), the others ignore it.
local rotateHeld = {}

local function rotateBuilding(c, jd)
	local playerObj = actor(jd)
	local drag = playerObj and getCell():getDrag(jd.player)
	if not drag then return end
	if drag.handleRotate then
		rotateHeld[jd.player] = true
	elseif drag.rotateKey then
		drag:rotateKey(getCore():getKey(KeybindId.ROTATE_BUILDING), true)
	end
end

local function rotateBuildingRelease(c, jd)
	rotateHeld[jd.player] = nil
end

-- server/ Lua (ISPlace3DItemCursor) loads after client/.
Events.OnGameStart.Add(function()
	if not ISPlace3DItemCursor or ISPlace3DItemCursor.GamepadTweaksRotate then return end
	ISPlace3DItemCursor.GamepadTweaksRotate = true
	local checkRotateJoypad = ISPlace3DItemCursor.checkRotateJoypad
	ISPlace3DItemCursor.checkRotateJoypad = function(self, ...)
		if rotateHeld[self.chr:getPlayerNum()] and not self.joypadPositionActive then
			return self:handleRotate(true, false)
		end
		return checkRotateJoypad(self, ...)
	end
end)

-- VoiceManager sends while ENABLE_VOICE_TRANSMIT is held (push-to-talk mode), in Java.
local voiceRun, voiceRelease = held("voice")

-- SoundManager.updateMusic (TOGGLE_MUSIC), IngameState (DISPLAY_FPS): Java, KeyToggles.
local function toggleMusic(c, jd)
	if GamepadTweaks_toggleMusic then GamepadTweaks_toggleMusic() end
end

local function displayFps(c, jd)
	if GamepadTweaks_toggleFps then GamepadTweaks_toggleFps() end
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

-- Shift variants and context actions --------------------------------------------------
-- The keyboard gets more out of Interact (E) with Shift held (IsoPlayer.doContext*: the
-- Java check is CharacterInputComponent.isShiftKeyDown, keyboard only) and from the context
-- key event (OnContextKey); a gamepad player has no Shift and only some of it. Each action
-- here does one of them directly, so the character does exactly that.

-- E near a car seats the player by the nearest door (VehicleUtils.OnUseVehicle ->
-- ISVehicleMenu.onEnter with BaseVehicle.getBestSeat); with Shift it is the driver's seat,
-- through that door and over (ISVehicleMenu.processShiftEnter). Here: that, or for a
-- passenger the switch to the driver's seat.
local function drive(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	local vehicle = playerObj:getVehicle()
	if vehicle then
		local seat = vehicle:getSeat(playerObj)
		if seat > 0 and not vehicle:isSeatOccupied(0) and vehicle:canSwitchSeat(seat, 0) then
			ISVehicleMenu.onSwitchSeat(playerObj, 0)
		end
		return
	end
	vehicle = ISVehicleMenu.getVehicleToInteractWith(playerObj)
	if not vehicle or not vehicle:getScript() or vehicle:getScript():getWheelCount() == 0 then return end
	if vehicle:isSeatOccupied(0) then
		-- "someone is in the seat", or the items on it are moved first (as vanilla)
		return ISVehicleMenu.onEnter(playerObj, vehicle, 0)
	end
	local seat = vehicle:getBestSeat(playerObj)
	if seat == -1 or vehicle:isSeatOccupied(seat) then seat = 0 end
	ISTimedActionQueue.clear(playerObj)
	ISVehicleMenu.processShiftEnter(playerObj, vehicle, seat)
end

-- The object whose curtain this is (what ISWorldObjectContextMenu.onOpenCloseCurtain takes:
-- a door holds its sheet itself), or nil.
local function curtainOf(obj, playerObj)
	local curtain = nil
	if instanceof(obj, "IsoDoor") then
		return obj:HasCurtains() and obj or nil
	elseif instanceof(obj, "IsoCurtain") then
		curtain = obj
	elseif instanceof(obj, "IsoWindow") or instanceof(obj, "IsoThumpable") then
		curtain = obj:HasCurtains()
	elseif instanceof(obj, "IsoWindowFrame") then
		curtain = obj:getCurtain()
	end
	if curtain and instanceof(curtain, "IsoCurtain") and curtain:canInteractWith(playerObj) then
		return curtain
	end
	return nil
end

-- Shift + E at a window, door or window frame toggles its curtain (IsoPlayer.doContextWindow,
-- doContextDoor, doContextWindowFrame; Shift + click: ISObjectClickHandler.doClickWindow);
-- on a gamepad only the context menu has it. Here: the curtain nearest to the player on their
-- square and around it, the one they face first.
local function curtain(c, jd)
	local playerObj = actor(jd)
	local square = playerObj and playerObj:getCurrentSquare()
	if not square then return end
	local facing = square:getAdjacentSquare(playerObj:getDir())
	local best, bestDist = nil, nil
	for dx = -1, 1 do
		for dy = -1, 1 do
			local sq = getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
			local objects = sq and sq:getObjects()
			for i = 0, (objects and objects:size() or 0) - 1 do
				local found = curtainOf(objects:get(i), playerObj)
				if found and found:getSquare() then
					local dist = found:getSquare():DistToProper(playerObj)
					if sq == facing or sq == square then dist = dist - 1 end
					if not bestDist or dist < bestDist then
						best, bestDist = found, dist
					end
				end
			end
		end
	end
	if best then
		ISWorldObjectContextMenu.onOpenCloseCurtain(nil, best, playerObj:getPlayerNum())
	end
end

-- Shift + Rack cycles the fire mode of a select-fire gun (OnPressRackButton with shift ->
-- ISReloadWeaponAction.OnPressRackButton); the gamepad's Rack never has the Shift.
local function fireMode(c, jd)
	local playerObj = actor(jd)
	if not playerObj then return end
	local gun = playerObj:getPrimaryHandItem()
	if not gun or not instanceof(gun, "HandWeapon") or not gun:isRanged() or not gun:isSelectFire() then return end
	triggerEvent("OnPressRackButton", playerObj, gun, true)
	local mode = gun:getFireMode()
	if mode then
		HaloTextHelper.addText(playerObj, getText("ContextMenu_FireMode_" .. mode))
	end
end

-- E while aiming with a tool in hand works the square in front (CFarming_Interact.onContextKey,
-- from OnContextKey when Interact finds no door / window / ...): chop a tree, cut a bush, remove
-- a stump, mine ore, dig a furrow, sow, scythe, water, fertilize, cure a plant, clean blood /
-- graffiti. It runs once per key press: SawOnContextKeyEvent is reset only by a keyboard
-- Interact press (onKeyStartPressed), so with a gamepad it works once per session. Here the
-- flag is reset per joypad press (below), and the action does it without aiming: the check
-- is satisfied for the call only.
local function useTool(c, jd)
	local playerObj = actor(jd)
	if not playerObj or not CFarming_Interact or playerObj:getVehicle() then return end
	local aiming = playerObj:isAiming()
	CFarming_Interact.SawOnContextKeyEvent = false
	if not aiming then playerObj:setIsAiming(true) end
	local ok, err = pcall(CFarming_Interact.onContextKey, playerObj, 0)
	if not aiming then playerObj:setIsAiming(false) end
	if not ok then error(err, 0) end
end

-- A joypad player's Interact press: the flag is per press, released while the Interact
-- button of the binding is up (OnContextKey fires every frame while it is held long).
local toolPressSeen = {}

Events.OnGameStart.Add(function()
	if not CFarming_Interact or CFarming_Interact.GamepadTweaksWrapped then return end
	CFarming_Interact.GamepadTweaksWrapped = true
	local vanillaOnContextKey = CFarming_Interact.onContextKey
	-- vanilla registers it in its own OnGameStart, by reference
	Events.OnContextKey.Remove(vanillaOnContextKey)
	CFarming_Interact.onContextKey = function(playerObj, ms)
		if playerObj:getJoypadBind() ~= -1 then
			local n = playerObj:getPlayerNum()
			if toolPressSeen[n] then return end
			toolPressSeen[n] = true
			CFarming_Interact.SawOnContextKeyEvent = false
		end
		return vanillaOnContextKey(playerObj, ms)
	end
	Events.OnContextKey.Add(CFarming_Interact.onContextKey)
end)

Events.OnPlayerUpdate.Add(function(playerObj)
	local n = playerObj:getPlayerNum()
	if not toolPressSeen[n] then return end
	local interact = CharacterJoypadButtonBinding.Interact:getJoypadButton()
	if not interact or not interact:isDown(playerObj:getJoypadBind()) then
		toolPressSeen[n] = nil
	end
end)

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
	{ id = "fireMode", label = "UI_GamepadTweaks_action_fireMode", run = fireMode },
	{ id = "useTool", label = "UI_GamepadTweaks_action_useTool", run = useTool },
	{ id = "panCamera", label = "PanCamera", run = panRun, release = panRelease,
		layer = "aiming", button = Joypad.RBumper },
	{ id = "sitOnGround", label = "SitOnGround", run = sitOnGround },
	{ id = "searchMode", label = "Toggle Search Mode", run = searchMode },
	{ id = "shout", label = "Shout", run = shout },
	{ id = "releaseRope", label = "ReleaseRope", run = releaseRope },
	{ id = "animalRadial", label = "AnimalRadialMenu", run = animalRadial },
	{ id = "curtain", label = "UI_GamepadTweaks_action_curtain", run = curtain },
	{ id = "drive", label = "UI_GamepadTweaks_action_drive", run = drive },
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
	{ id = "rotateBuilding", label = "Rotate building", run = rotateBuilding, release = rotateBuildingRelease,
		category = "extra" },
	{ id = "voice", label = "Enable voice transmit", run = voiceRun, release = voiceRelease, category = "extra" },
	{ id = "toggleMusic", label = "Toggle Music", run = toggleMusic, whilePaused = true, category = "extra" },
	{ id = "displayFps", label = "Display FPS", run = displayFps, whilePaused = true, category = "extra" },
}

-- Section in the settings panel (UI_GamepadTweaks_cat_*); group: main / extra.
local CATEGORY = {
	lightSource = "hands", dropPrimary = "hands", dropSecondary = "hands", dropBothHands = "hands",
	dropBag = "hands", dropHandsAndBag = "hands", grabCorpse = "hands", sharpenWeapon = "hands",
	firearmRadial = "hands", fireMode = "hands", useTool = "hands",
	panCamera = "character", sitOnGround = "character", searchMode = "character", shout = "character",
	releaseRope = "character", animalRadial = "character", curtain = "character",
	drive = "vehicle", engine = "vehicle", headlights = "vehicle", heater = "vehicle", horn = "vehicle",
	switchSeat = "vehicle", vehicleInfo = "vehicle",
	map = "windows", craftingMenu = "windows", buildingMenu = "windows", skills = "windows",
	health = "windows", protection = "windows", info = "windows", survivalGuide = "windows",
	timePause = "time", timeNormal = "time", timeFast1 = "time", timeFast2 = "time", timeFast3 = "time",
}

for slot = 1, 8 do
	table.insert(ACTIONS, { id = "hotbar" .. slot, label = "Hotbar " .. slot, run = hotbar(slot), category = "extra" })
end

for _, action in ipairs(ACTIONS) do
	action.layer = action.layer or "world"
	action.group = action.category == "extra" and "extra" or "main"
	action.category = CATEGORY[action.id] or (action.id:match("^hotbar") and "hotbar") or "misc"
	if not action.label:match("^IGUI_") and not action.label:match("^UI_GamepadTweaks_") then
		action.label = "UI_optionscreen_binding_" .. action.label
	end
	Bindings.add(action)
end
