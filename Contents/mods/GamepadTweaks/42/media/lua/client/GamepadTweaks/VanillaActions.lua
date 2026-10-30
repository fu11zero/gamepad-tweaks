-- The vanilla gamepad bindings (Options -> Controller) as Steam Input game actions.
--
-- Steam lists only the game actions of the manifest, so "Crouch" or "Interact" can't be found
-- there, and vanilla ties each binding to its physical button: the Java character input asks
-- CharacterJoypadButtonBinding.X.isDown, the Lua button prompts (ISButtonPrompt) put the
-- binding's handler on its button, the panels and the build cursor take hardcoded buttons.
-- Each action here runs the game function behind the binding directly, as the keyboard does
-- (IsoPlayer.updateSneakKey -> setSneaking, BeginAutomaticReload, doZoomScroll, the prompt's
-- handler...). No button is pressed: nothing else on any button fires, and it works whether
-- the binding is on a button, shares it with others, or has none.
-- Held ones (sprint, floor attack, brake, the Java half of interact, aim, attack, melee, run) set a held state that the game's own query sees
-- (HeldActions.java). Steam only (steamOnly): the in-game editor already has the bindings.
-- "Walk To" (needs a cursor) and "Loot" (no code uses it) are left out. Aim is held and works
-- as the keyboard Aim key (aim + precision aim, no stick needed): for gyro aiming (Steam "aim"
-- analog action), so Precision Aim has no action of its own. Attack, Melee and Run, vanilla
-- trigger / stick thresholds, are held actions too (attack needs aiming, as with the mouse).

require "GamepadTweaks/Bindings"
require "ISUI/ISButtonPrompt"
require "ISUI/ISFirearmRadialMenu"

local Bindings = GamepadTweaks.Bindings

local function player(jd)
	local playerObj = jd.player and getSpecificPlayer(jd.player)
	if not playerObj or playerObj:isDead() or isGamePaused() then return nil end
	return playerObj
end

-- Button prompts ----------------------------------------------------------------------------
-- In the world (no UI focus) JoyPadSetup updateJoypadFocus clears the prompts every frame
-- (clearButtonBindings) and evaluates every binding (getBestButtonBindingAction); the handler of
-- a binding goes to its button's slot, the last one evaluated wins. Here each binding's handler
-- is also kept by binding name, so its action can run it.

local vanillaSetBindingPrompt = ISButtonPrompt.setButtonBindingPrompt
function ISButtonPrompt:setButtonBindingPrompt(binding, str, func, p1, p2, p3, p4)
	self.gtByBinding = self.gtByBinding or {}
	self.gtByBinding[tostring(binding)] = func and { func = func, p1, p2, p3, p4 } or nil
	return vanillaSetBindingPrompt(self, binding, str, func, p1, p2, p3, p4)
end

local vanillaClearButtonBindings = ISButtonPrompt.clearButtonBindings
function ISButtonPrompt:clearButtonBindings()
	if self.gtByBinding then table.wipe(self.gtByBinding) end
	return vanillaClearButtonBindings(self)
end

local SLOTS = { "a", "b", "x", "y", "lb", "rb" }

-- Vanilla evaluates some bindings only for the button they are on (getBestXButtonAction:
-- InteractOptions; getBestYButtonAction: Inventory), so with the binding elsewhere or nowhere
-- they are not there; evaluate it now, keeping the button slots as they were.
local function evaluate(buts, method, playerObj)
	local saved = {}
	for _, s in ipairs(SLOTS) do
		saved[s] = { buts[s .. "Prompt"], buts[s .. "Func"], buts[s .. "Params"] }
	end
	local ok, err = pcall(buts[method], buts, playerObj:getDir())
	for _, s in ipairs(SLOTS) do
		buts[s .. "Prompt"], buts[s .. "Func"], buts[s .. "Params"] = saved[s][1], saved[s][2], saved[s][3]
	end
	if not ok then print("[GamepadTweaks] ERROR: " .. method .. ": " .. tostring(err)) end
end

-- Runs the binding's prompt handler, as its button would (ISButtonPrompt:onAPress...).
local function runPrompt(jd, name, method)
	local playerObj = player(jd)
	if not playerObj or jd.focus ~= nil then return end
	local buts = getButtonPrompts(jd.player)
	if not buts then return end
	if method then evaluate(buts, method, playerObj) end
	local entry = buts.gtByBinding and buts.gtByBinding[name]
	if entry then
		entry.func(buts, entry[1], entry[2], entry[3], entry[4])
	end
end

-- The build / move furniture cursor takes hardcoded buttons (onPressButtonNoFocus ->
-- drag:onJoypadPressButton): A confirms, B cancels. Returns true when there is one.
local function toCursor(jd, button)
	local drag = jd.player and getCell() and getCell():getDrag(jd.player)
	if not drag then return false end
	drag:onJoypadPressButton(jd.id, jd, button)
	return true
end

-- Actions -------------------------------------------------------------------------------------

local function held(name)
	local function set(jd, down)
		if GamepadTweaks_setActionHeld then GamepadTweaks_setActionHeld(jd.id, name, down) end
	end
	return function(c, jd) set(jd, true) end, function(c, jd) set(jd, false) end
end

-- Interact is two halves, as on its button: the Lua prompt (switches, appliances, vehicle
-- parts...) on press, and the Java poll (IsoPlayer.updateUseKey -> doContext: doors and
-- windows, whose prompts have no handler; grapple; enterExitVehicle) that sees it held.
local interactHold, interactRelease = held("interact")

local function interact(c, jd)
	if toCursor(jd, Joypad.AButton) then return end
	runPrompt(jd, "Interact")
	if jd.focus == nil then interactHold(c, jd) end
end

local function cancelAction(c, jd)
	if toCursor(jd, Joypad.BButton) then return end
	runPrompt(jd, "CancelAction")
end

local function prompt(name, method)
	return function(c, jd) runPrompt(jd, name, method) end
end

-- IsoPlayer.updateSneakKey.
local function crouch(c, jd)
	local playerObj = player(jd)
	if playerObj and not playerObj:getVehicle() then
		playerObj:setSneaking(not playerObj:isSneaking())
	end
end

-- The firearm in the main hand, when it can be reloaded (IsoPlayer.checkReloading).
local function firearm(jd)
	local playerObj = player(jd)
	if not playerObj then return nil end
	local weapon = playerObj:getPrimaryHandItem()
	if not weapon or not instanceof(weapon, "HandWeapon") or not weapon:isReloadable(playerObj) then return nil end
	playerObj:setVariable("WeaponReloadType", tostring(weapon:getWeaponReloadType()))
	return playerObj, weapon
end

-- Java (checkReloading) only fires OnPressReloadButton, which just stops loading rounds and
-- racks; the reload itself is the gamepad prompt's (ISFirearmRadialMenu.getBestRBButtonAction):
-- an RB tap, timed on the release hardcoded to RB (onJoypadButtonReleased), starts
-- BeginAutomaticReload. Here: both, with the prompt's conditions.
local function reload(c, jd)
	local playerObj, weapon = firearm(jd)
	if not playerObj then return end
	local loading = playerObj:getVariableBoolean("isLoading")
	triggerEvent("OnPressReloadButton", playerObj, weapon)
	if loading or JoypadState.disableReload or ISReloadWeaponAction.disableReloading then return end
	local queue = ISTimedActionQueue.queues[playerObj]
	if queue and #queue.queue > 0 then return end
	if not ISFirearmRadialMenu.checkWeapon(playerObj) then return end
	ISReloadWeaponAction.BeginAutomaticReload(playerObj, weapon)
end

local function rack(c, jd)
	local playerObj, weapon = firearm(jd)
	if playerObj then
		triggerEvent("OnPressRackButton", playerObj, weapon, false)
	end
end

-- UIManager.handleZoomKeys.
local function zoom(delta)
	return function(c, jd)
		if player(jd) then
			getCore():doZoomScroll(jd.player, delta)
		end
	end
end

-- Panel bindings: vanilla has them in the editor but the panels never read them, they take
-- hardcoded buttons (ISPanelJoypad and the rest: B closes, LB/RB switch tabs). The action
-- gives the focused panel that button's command, only the panel gets it. The inventory and
-- loot windows are done directly: there Y closes, B cancels / collapses, LB/RB switch the
-- container, and their buttons can carry the mod's inventory actions (InventoryActions.lua).
local function inventoryFocus(jd)
	local focus = jd.focus
	return type(focus) == "table" and focus.Type == "ISInventoryPage" and focus or nil
end

local function toFocus(button, onInventory)
	return function(c, jd)
		local page = inventoryFocus(jd)
		if page then
			onInventory(page, jd)
			return
		end
		local focus = jd.focus
		if type(focus) == "table" and focus.onJoypadDown then
			focus:onJoypadDown(button, jd)
		end
	end
end

local function closeInventory(page, jd)
	if not JoypadState.disableYInventory then setJoypadFocus(jd.player, nil) end
end

-- Inventory: the world prompt (show the inventory / loot), or close the focused window as Y does.
local function inventory(c, jd)
	local page = inventoryFocus(jd)
	if page then return closeInventory(page, jd) end
	runPrompt(jd, "Inventory", "getBestYButtonAction")
end

local function transferItem(c, jd)
	local page = inventoryFocus(jd)
	if page and not JoypadState.disableGrab then
		page.inventoryPane:doGrabOnJoypadSelected()
	end
end

local function cycle(getPage)
	return function(c, jd)
		if inventoryFocus(jd) then
			getPage(jd.player):selectNextContainer()
		end
	end
end

-- Cruise control on / off (ISVehicleRegulator.onJoypadReleaseX). Vanilla toggles on the
-- release, because while the button is held the D-pad sets the speed; the action has the
-- separate faster / slower actions for that, so it toggles on the press. With no speed set
-- yet, it takes the current one (as the first "faster" does).
local function cruiseToggle(c, jd)
	local playerObj = player(jd)
	local vehicle = playerObj and playerObj:getVehicle()
	if not vehicle or not vehicle:isDriver(playerObj) then return end
	if vehicle:getRegulatorSpeed() <= 0 then
		vehicle:setRegulatorSpeed(vehicle:getCurrentSpeedForRegulator())
		if vehicle:getRegulatorSpeed() <= 0 then return end
	end
	vehicle:setRegulator(not vehicle:isRegulator())
end

local sprintRun, sprintRelease = held("sprint")
local floorRun, floorRelease = held("floorAttack")
local brakeRun, brakeRelease = held("brake")
local aimRun, aimRelease = held("aim")
local attackRun, attackRelease = held("attack")
local meleeRun, meleeRelease = held("melee")
local runRun, runRelease = held("run")

-- id: "vanilla" .. binding name (Steam action id, the title is the vanilla binding name).
local ACTIONS = {
	{ id = "vanillaAim", run = aimRun, release = aimRelease },
	{ id = "vanillaAttack", run = attackRun, release = attackRelease },
	{ id = "vanillaMelee", run = meleeRun, release = meleeRelease },
	{ id = "vanillaRun", run = runRun, release = runRelease },
	{ id = "vanillaInteract", run = interact, release = interactRelease },
	{ id = "vanillaInteractOptions", run = prompt("InteractOptions", "getBestXButtonAction") },
	{ id = "vanillaCancelAction", run = cancelAction },
	{ id = "vanillaCrouch", run = crouch },
	{ id = "vanillaSprint", run = sprintRun, release = sprintRelease },
	{ id = "vanillaClimbThrough", run = prompt("ClimbThrough") },
	{ id = "vanillaSmashWindow", run = prompt("SmashWindow") },
	{ id = "vanillaReloadWeapon", run = reload },
	{ id = "vanillaRackFirearm", run = rack },
	{ id = "vanillaManualFloorAtk", run = floorRun, release = floorRelease },
	{ id = "vanillaInventory", run = inventory },
	{ id = "vanillaClosePanel", run = toFocus(Joypad.BButton, closeInventory) },
	{ id = "vanillaTransferItem", run = transferItem },
	{ id = "vanillaCycleInventory", run = cycle(getPlayerInventory) },
	{ id = "vanillaCycleLoot", run = cycle(getPlayerLoot) },
	{ id = "vanillaCycleTabsLeft", run = toFocus(Joypad.LBumper, function(page) page:selectPrevContainer() end) },
	{ id = "vanillaCycleTabsRight", run = toFocus(Joypad.RBumper, function(page) page:selectNextContainer() end) },
	{ id = "vanillaBrakes", run = brakeRun, release = brakeRelease },
	{ id = "vanillaCruiseControl", run = cruiseToggle },
	{ id = "vanillaZoomIn", run = zoom(-1) },
	{ id = "vanillaZoomOut", run = zoom(1) },
}

for _, action in ipairs(ACTIONS) do
	action.layer = "steam"
	action.category = "vanilla"
	action.group = "main"
	action.steamOnly = true
	action.label = "UI_optionscreen_gamepad_CharacterJoypadButtonBinding_name_" .. action.id:sub(#"vanilla" + 1)
	Bindings.add(action)
end
