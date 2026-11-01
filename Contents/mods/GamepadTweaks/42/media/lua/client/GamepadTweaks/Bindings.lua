-- Rebindable gamepad actions for what vanilla hardcodes to buttons.
--
-- Vanilla JoyPadSetup.lua and friends handle these directly, past the binding system
-- (CharacterJoypadButtonBinding, Options -> Controller):
-- - JoypadControllerData:onPressUp/Down/Left/Right -> ISDPadWheels.onDisplayUp/Down/Left/Right
--   (vehicle/animal, emote, weapon/light, zones/rooms editor/survival guide wheels);
-- - JoypadControllerData:onPressButtonNoFocus: Back -> command wheel, Start -> pause;
-- - cruise control speed: X + D-pad up/down (ISVehicleRegulator.onJoypadPressUp/Down);
-- - left stick button held -> crouch/sit/auto-walk radial (ISJoystickButtonRadialMenu);
-- - right bumper held in a UI -> panel navigation, left bumper in it -> parent panel
--   (JoypadControllerData:onHoldButton/onReleaseButton).
-- So these buttons can't be used for anything else, and the actions can't be moved.
-- The vanilla binding list is a Java enum (fixed when the class loads, saved by name in
-- InputBindings/*.xml), so the actions live here instead, per preset like the regular
-- bindings: preset.<preset>.bind.<action>=<button> in ~/Zomboid/GamepadTweaks.properties
-- (re-read on the fly). By default every action is on its vanilla button, so nothing changes
-- until the player rebinds it. "none" frees the button. The built-in presets (Default,
-- Original) can't be edited, so they always have the defaults; editing one makes a new preset,
-- as vanilla does for the regular bindings.
-- Without the Java part (jar not approved) the defaults are used.
--
-- Vanilla also hardcodes the buttons of two regular bindings in places (bugs when they
-- are rebound in Options -> Controller); here they follow the binding:
-- - CruiseControl: the prompt is on its button, but the toggle happens on X release
--   (onReleaseButton -> ISVehicleRegulator.onJoypadReleaseX) and the speed changes with X held;
-- - ReloadWeapon: the prompt is on its button, but the firearm radial opens while RB is held
--   (ISButtonPrompt:update -> ISFirearmRadialMenu.onRepeatRBumper), quick reload and closing
--   the radial happen on RB release.

require "ISUI/Gamepad/JoyPadSetup"
require "gamepadBinding"
require "ISUI/ISDPadWheels"
require "ISUI/ISButtonPrompt"
require "ISUI/ISFirearmRadialMenu"
require "ISUI/ISJoystickButtonRadialMenu"
require "Vehicles/ISUI/ISVehicleRegulator"

GamepadTweaks = GamepadTweaks or {}
local Bindings = {}
GamepadTweaks.Bindings = Bindings

local function log(msg)
	print("[GamepadTweaks] " .. msg)
end

local DPAD = {
	[Joypad.DPadUp] = true,
	[Joypad.DPadDown] = true,
	[Joypad.DPadLeft] = true,
	[Joypad.DPadRight] = true,
}

-- Vanilla functions, called by the actions and the wrappers below.
local vanilla = {
	onDisplayUp = ISDPadWheels.onDisplayUp,
	onDisplayDown = ISDPadWheels.onDisplayDown,
	onDisplayLeft = ISDPadWheels.onDisplayLeft,
	onDisplayRight = ISDPadWheels.onDisplayRight,
	onPressButtonNoFocus = JoypadControllerData.onPressButtonNoFocus,
	onHoldButton = JoypadControllerData.onHoldButton,
	onReleaseButton = JoypadControllerData.onReleaseButton,
	regulatorPressUp = ISVehicleRegulator.onJoypadPressUp,
	regulatorPressDown = ISVehicleRegulator.onJoypadPressDown,
	regulatorReleaseX = ISVehicleRegulator.onJoypadReleaseX,
	stickDown = ISJoystickButtonRadialMenu.onJoypadDown,
	stickReleased = ISJoystickButtonRadialMenu.onJoypadButtonReleased,
	stickDisplayLeft = ISJoystickButtonRadialMenu.displayLeft,
	firearmReleased = ISFirearmRadialMenu.onJoypadButtonReleased,
	firearmDisplay = ISFirearmRadialMenu.display,
}

local function isPaused()
	return UIManager.getSpeedControls() and UIManager.getSpeedControls():getCurrentGameSpeed() == 0
end

-- Button of a regular (Options -> Controller) binding, or nil.
local function bindingButton(binding)
	if not binding then return nil end
	return binding:getJoypadButton()
end

-- The driver's vehicle, or nil.
local function drivenVehicle(jd)
	local playerObj = jd.player and getSpecificPlayer(jd.player)
	local vehicle = playerObj and playerObj:getVehicle()
	if vehicle and vehicle:isDriver(playerObj) then return vehicle end
	return nil
end

-- Same as ISVehicleRegulator.onJoypadPressUp/Down without the X check.
local function cruiseFaster(c, jd)
	local vehicle = drivenVehicle(jd)
	if not vehicle or isPaused() then return end
	ISVehicleRegulator.changedSpeed[jd.id] = true
	if vehicle:getRegulatorSpeed() < vehicle:getMaxSpeed() + 20 then
		if vehicle:getRegulatorSpeed() == 0 and vehicle:getCurrentSpeedForRegulator() ~= vehicle:getRegulatorSpeed() then
			vehicle:setRegulatorSpeed(vehicle:getCurrentSpeedForRegulator())
		else
			vehicle:setRegulatorSpeed(vehicle:getRegulatorSpeed() + 5)
		end
	end
end

local function cruiseSlower(c, jd)
	local vehicle = drivenVehicle(jd)
	if not vehicle or isPaused() then return end
	ISVehicleRegulator.changedSpeed[jd.id] = true
	if vehicle:getRegulatorSpeed() >= 5 then
		vehicle:setRegulatorSpeed(vehicle:getRegulatorSpeed() - 5)
		if vehicle:getRegulatorSpeed() <= 0 then
			vehicle:setRegulatorSpeed(0)
			vehicle:setRegulator(false)
		end
	end
end

-- id: key in the settings file; button: the vanilla button (default, and what the vanilla
-- code assumes, e.g. for setHideWhenButtonReleased); category: section in the settings panel
-- (UI_GamepadTweaks_cat_*); label: name translation key (default UI_GamepadTweaks_action_<id>).
-- layer: when the action is looked up; actions in one layer can't share a button:
-- - world: pressed in the world (no UI focus);
-- - cruise: pressed in the world while driving with the CruiseControl button held (before world);
-- - aiming: pressed in the world while aiming or looking out of a vehicle (before world);
-- - hold: held in the world;
-- - uiHold: held while a UI has the focus;
-- - navigation: released during UI panel navigation;
-- - inventory: pressed while the inventory or loot window has the focus (InventoryActions.lua).
-- run(controller, joypadData) for press layers; repeat: also on D-pad auto-repeat;
-- release(controller, joypadData): when the button that ran it is released (horn);
-- hides: the vanilla button a radial it opens closes on (setHideWhenButtonReleased), when
-- that is not its default button;
-- whilePaused: also runs while the game is paused (other buttons are ignored then);
-- steamOnly: a Steam Input action only, not in the in-game editor (VanillaActions.lua: the
-- vanilla bindings, which the editor already has).
Bindings.actions = {
	{ id = "vehicleWheel", category = "wheels", button = Joypad.DPadUp, layer = "world",
		run = function(c, jd) vanilla.onDisplayUp(jd) end },
	{ id = "emoteWheel", category = "wheels", button = Joypad.DPadDown, layer = "world",
		run = function(c, jd) vanilla.onDisplayDown(jd) end },
	{ id = "equipWheel", category = "wheels", button = Joypad.DPadLeft, layer = "world",
		run = function(c, jd) vanilla.onDisplayLeft(jd) end },
	{ id = "extraWheel", category = "wheels", button = Joypad.DPadRight, layer = "world",
		run = function(c, jd) vanilla.onDisplayRight(jd) end },
	{ id = "commandWheel", category = "wheels", button = Joypad.Back, layer = "world",
		run = function(c, jd) vanilla.onPressButtonNoFocus(c, Joypad.Back) end },
	{ id = "pause", category = "wheels", button = Joypad.Start, layer = "world",
		run = function(c, jd) vanilla.onPressButtonNoFocus(c, Joypad.Start) end },
	{ id = "cruiseFaster", category = "vehicle", button = Joypad.DPadUp, layer = "cruise", repeats = true, run = cruiseFaster },
	{ id = "cruiseSlower", category = "vehicle", button = Joypad.DPadDown, layer = "cruise", repeats = true, run = cruiseSlower },
	{ id = "stickRadial", category = "controls", button = Joypad.LStickButton, layer = "hold" },
	{ id = "uiNavigation", category = "controls", button = Joypad.RBumper, layer = "uiHold" },
	{ id = "uiNavigateParent", category = "controls", button = Joypad.LBumper, layer = "navigation" },
}

local actionById = {}
for _, action in ipairs(Bindings.actions) do
	actionById[action.id] = action
end

local loadedVersion = nil

-- Registers an action (other files, e.g. KeyActions.lua). button = nil: unbound by default.
function Bindings.add(action)
	table.insert(Bindings.actions, action)
	actionById[action.id] = action
	loadedVersion = nil -- rebuild on the next lookup
end

-- Settings ---------------------------------------------------------------------

local buttonByName = {}
for _, b in ipairs(JoypadButton.getButtons()) do
	buttonByName[tostring(b)] = b
end

local actionByButton = {} -- [layer][button] = action

local function readSetting(key)
	if not GamepadTweaks_getSetting then return nil end
	local ok, v = pcall(GamepadTweaks_getSetting, key)
	return ok and v or nil
end

local function settingsVersion()
	if not GamepadTweaks_settingsVersion then return 0 end
	local ok, v = pcall(GamepadTweaks_settingsVersion)
	return ok and v or 0
end

-- Presets -----------------------------------------------------------------------

function Bindings.currentPreset()
	return getCore():getOptionGamepadBindingPreset() or ""
end

-- A preset saved in InputBindings/*.xml; the built-in ones (Default, Original) are Lua only
-- and vanilla doesn't edit them (gamepadBinding:isCurrentPresetEditable).
function Bindings.isPresetEditable(name)
	local preset = gamepadBinding and gamepadBinding.presets and gamepadBinding.presets[name or Bindings.currentPreset()]
	return preset ~= nil and preset.loadedSet ~= nil
end

-- preset.<name>.bind.<id>; the name may have any characters, the key only these.
local function presetKey(name, id)
	local encoded = string.gsub(name, "[^%w_%-]", function(c) return "%" .. string.byte(c) .. ";" end)
	return "preset." .. encoded .. ".bind." .. id
end

-- Returns the button set for the action (false = none), or nil when it isn't set.
local function readBinding(action)
	local preset = Bindings.currentPreset()
	if not Bindings.isPresetEditable(preset) then return nil end
	local value = readSetting(presetKey(preset, action.id))
	if not value then return nil end
	value = value:match("^%s*(.-)%s*$")
	if value == "none" or value == "" then return false end
	if buttonByName[value] then return buttonByName[value] end
	log("WARN: " .. presetKey(preset, action.id) .. "=" .. value .. " is not a button, using " .. tostring(action.button))
	return nil
end

-- Regular bindings that act only inside a UI panel, so they don't compete with world actions.
local UI_ONLY = {
	ClosePanel = true, CycleLoot = true, CycleInventory = true,
	CycleTabsLeft = true, CycleTabsRight = true, TransferItem = true,
}

-- [button] = name of a regular binding on it that acts in the world.
local function regularWorldBindings()
	local result = {}
	for _, binding in ipairs(CharacterJoypadButtonBinding.allBindings()) do
		local name = tostring(binding)
		local button = binding:getJoypadButton()
		if button and not UI_ONLY[name] and not result[button] then
			result[button] = name
		end
	end
	return result
end

-- Changes when a regular binding is moved or the preset changes (Options -> Controller).
local function regularSignature()
	local parts = { Bindings.currentPreset() }
	for _, binding in ipairs(CharacterJoypadButtonBinding.allBindings()) do
		table.insert(parts, tostring(binding:getJoypadButton()))
	end
	return table.concat(parts, ",")
end

-- An action set to a button takes it from the action that has it by default in the same
-- layer (bind.commandWheel=DPadDown alone moves the emote wheel off the D-pad).
-- A regular binding on the button of a default world action takes it too: vanilla has none
-- on the D-pad, Back or Start, so one there was put by the player (Melee on D-pad left
-- would otherwise also open the weapon wheel).
function Bindings.reload()
	actionByButton = {}
	local changed = {}
	local regular = regularWorldBindings()
	local function assign(action, button, explicit)
		action.bound = nil
		if button and action.layer == "world" and regular[button] then
			if not explicit then
				table.insert(changed, action.id .. "=none (" .. tostring(button) .. " used by " .. regular[button] .. ")")
				return
			end
			log("WARN: " .. action.id .. " is on " .. tostring(button) .. ", so is the regular binding " .. regular[button] .. "; both react")
		end
		if button then
			local layer = actionByButton[action.layer]
			if not layer then
				layer = {}
				actionByButton[action.layer] = layer
			end
			local other = layer[button]
			if other then
				if explicit then
					log("WARN: " .. action.id .. " and " .. other.id .. " are both set to " .. tostring(button) .. ", using " .. other.id)
				else
					table.insert(changed, action.id .. "=none (" .. tostring(button) .. " taken by " .. other.id .. ")")
				end
				return
			end
			layer[button] = action
			action.bound = button
		end
		if button ~= action.button then
			table.insert(changed, action.id .. "=" .. tostring(button or "none"))
		end
	end
	local defaults = {}
	for _, action in ipairs(Bindings.actions) do
		-- not "a and b or nil": readBinding's false (none) would become nil (default)
		local button = nil
		if not action.steamOnly then
			button = readBinding(action)
		end
		if button == nil then
			table.insert(defaults, action)
		else
			assign(action, button, true)
		end
	end
	for _, action in ipairs(defaults) do
		assign(action, action.button, false)
	end
	log("button actions (" .. Bindings.currentPreset() .. "): " .. (#changed > 0 and table.concat(changed, " ") or "vanilla"))
end

-- Copies the mod bindings of a preset to a new one (a preset made from the current one).
function Bindings.copyPreset(from, to)
	if not GamepadTweaks_setSetting or not Bindings.isPresetEditable(from) then return end
	for _, action in ipairs(Bindings.actions) do
		local value = readSetting(presetKey(from, action.id))
		if value then
			GamepadTweaks_setSetting(presetKey(to, action.id), value)
		end
	end
end

-- Earlier versions kept the bindings global (bind.<action>), so a change made in one preset showed up
-- in all of them, the built-in ones too. They go to every saved preset; with no saved preset
-- (the player changed them only in a built-in one), a new preset is made from the current one.
local migrated = false

local function migrateGlobal()
	migrated = true
	if not GamepadTweaks_setSetting then return end
	local legacy = {}
	local any = false
	for _, action in ipairs(Bindings.actions) do
		local value = readSetting("bind." .. action.id)
		if value then
			legacy[action.id] = value
			any = true
		end
	end
	if not any then return end
	local saved = false
	for _, preset in pairs(gamepadBinding and gamepadBinding.presets or {}) do
		if preset.loadedSet then saved = true end
	end
	if not saved and gamepadBinding and gamepadBinding.createNewFromCurrent then
		local entry = gamepadBinding:createNewFromCurrent()
		if entry and entry.key then
			gamepadBinding:set(entry.key)
			gamepadBinding:saveAll()
			getCore():saveOptions()
			log("bindings: new preset " .. entry.key .. " for the global bindings")
		end
	end
	local names = {}
	for name, preset in pairs(gamepadBinding and gamepadBinding.presets or {}) do
		if preset.loadedSet then
			table.insert(names, name)
			for id, value in pairs(legacy) do
				if readSetting(presetKey(name, id)) == nil then
					GamepadTweaks_setSetting(presetKey(name, id), value)
				end
			end
		end
	end
	for id in pairs(legacy) do
		GamepadTweaks_setSetting("bind." .. id, nil)
	end
	log("bindings: global bind.* moved to the presets " .. table.concat(names, ", "))
end

local REGULAR_CHECK_MS = 500
local regularCheckedAt = 0
local loadedRegular = nil

local function refresh()
	if not migrated then
		migrateGlobal()
	end
	local reload = false
	local v = settingsVersion()
	if v ~= loadedVersion then
		loadedVersion = v
		reload = true
	end
	local now = getTimestampMs()
	if reload or now - regularCheckedAt >= REGULAR_CHECK_MS then
		regularCheckedAt = now
		local sig = regularSignature()
		if sig ~= loadedRegular then
			loadedRegular = sig
			reload = true
		end
	end
	if reload then
		Bindings.reload()
	end
end

function Bindings.getAction(layer, button)
	refresh()
	local l = actionByButton[layer]
	return l and l[button] or nil
end

-- The button the action is on, or nil.
function Bindings.getButton(id)
	refresh()
	return actionById[id].bound
end

-- Settings panel ---------------------------------------------------------------

local LAYER_NOTE = { cruise = true, aiming = true, hold = true, uiHold = true, navigation = true, inventory = true }

-- "[Category] Name (context)" for lists.
function Bindings.getLabel(action, withCategory)
	local text = getText(action.label or ("UI_GamepadTweaks_action_" .. action.id))
	if LAYER_NOTE[action.layer] then
		text = text .. " " .. getText("UI_GamepadTweaks_layer_" .. action.layer)
	end
	if withCategory then
		text = "[" .. getText("UI_GamepadTweaks_cat_" .. (action.category or "misc")) .. "] " .. text
	end
	return text
end

function Bindings.getActionById(id)
	return actionById[id]
end

-- Actions the button is on, in registration order.
function Bindings.getActionsOn(button)
	refresh()
	local result = {}
	for _, action in ipairs(Bindings.actions) do
		if action.bound == button then
			table.insert(result, action)
		end
	end
	return result
end

function Bindings.canEdit()
	return GamepadTweaks_setSetting ~= nil
end

-- Up to 42.21 Core:getGameMode() returns a string ("Tutorial"); from 42.22 it returns a
-- GameMode object (vanilla checks Core:isTutorial()), and comparing it to the string is
-- always false. 42.21 has no GameMode.TUTORIAL.
function Bindings.isTutorial()
	local mode = getCore():getGameMode()
	if GameMode and GameMode.TUTORIAL then
		return mode == GameMode.TUTORIAL
	end
	return mode == "Tutorial"
end

-- Puts the action on button (false/nil: none) in the current preset and writes it to the
-- settings file. Another action of the same layer on that button is set to none, so a button
-- never ends up with two. A built-in preset can't be changed (ControllerEditor.lua makes a new
-- one first, as vanilla does).
function Bindings.set(id, button)
	local action = actionById[id]
	if not action or not GamepadTweaks_setSetting then return false end
	refresh()
	local preset = Bindings.currentPreset()
	if not Bindings.isPresetEditable(preset) then
		log("WARN: preset " .. preset .. " can't be edited, " .. id .. " not changed")
		return false
	end
	if button then
		for _, other in ipairs(Bindings.actions) do
			if other ~= action and other.layer == action.layer and other.bound == button then
				GamepadTweaks_setSetting(presetKey(preset, other.id), "none")
			end
		end
	end
	GamepadTweaks_setSetting(presetKey(preset, id), button and tostring(button) or "none")
	refresh()
	return true
end

-- Dispatch ---------------------------------------------------------------------

-- D-pad presses repeat while held (JoypadControllerData:update); an action fires once
-- per press unless it repeats. The wheels take the focus, so vanilla never saw the repeats.
local held = {}

local function heldKey(jd, button)
	return tostring(jd.id) .. ":" .. tostring(button)
end

-- Vanilla wheels close and pick the slice when their own button is released
-- (ISRadialMenu:setHideWhenButtonReleased); make that the button that opened it.
-- The back button wheel is created once (getPlayerBackButtonWheel) and sets it only
-- in new(), so gtVanillaHide remembers the vanilla button for the next opening.
local function retargetHide(jd, vanillaButton, button)
	if not vanillaButton then return end
	local focus = jd.focus
	if type(focus) == "table" and (focus.hideWhenButtonReleased == vanillaButton
			or focus.gtVanillaHide == vanillaButton) then
		focus.gtVanillaHide = vanillaButton
		focus.hideWhenButtonReleased = button
	end
end

-- [heldKey] = action whose release runs when that button goes up (the action found on
-- press, even if the binding changes meanwhile).
local pendingRelease = {}

local function run(action, jd, button)
	local ok, err = pcall(action.run, jd.controller, jd)
	if not ok then
		log("ERROR: " .. action.id .. " failed: " .. tostring(err))
		return
	end
	if action.release then
		pendingRelease[heldKey(jd, button)] = action
	end
	retargetHide(jd, action.hides or action.button, button)
end

local function runRelease(jd, button)
	local key = heldKey(jd, button)
	local action = pendingRelease[key]
	if not action then return end
	pendingRelease[key] = nil
	local ok, err = pcall(action.release, jd.controller, jd)
	if not ok then
		log("ERROR: " .. action.id .. " release failed: " .. tostring(err))
	end
end

local function dispatchLayer(jd, button, layer)
	local action = Bindings.getAction(layer, button)
	if not action then return false end
	local key = heldKey(jd, button)
	if held[key] and not action.repeats then return true end
	if DPAD[button] then held[key] = true end
	run(action, jd, button)
	return true
end

-- Runs the action of that layer bound to button (other files: the inventory window).
-- Returns false when there is none.
function Bindings.press(jd, button, layer)
	return dispatchLayer(jd, button, layer)
end

local function isCruiseHeld(jd)
	local cruise = bindingButton(CharacterJoypadButtonBinding.CruiseControl)
	return cruise ~= nil and cruise:isDown(jd.id) and not isPaused() and drivenVehicle(jd) ~= nil
end

-- Vanilla uses RB for the camera pan then and for nothing else (getBestRBButtonAction:
-- no reload prompt while aiming or looking out of a vehicle).
local function isAiming(jd)
	local playerObj = getSpecificPlayer(jd.player)
	return playerObj ~= nil and (playerObj:isAiming() or playerObj:isLookingWhileInVehicle())
end

-- Runs the world action bound to button. Returns false when there is none.
local function dispatch(jd, button)
	if isCruiseHeld(jd) and dispatchLayer(jd, button, "cruise") then
		return true
	end
	if isAiming(jd) and dispatchLayer(jd, button, "aiming") then
		return true
	end
	return dispatchLayer(jd, button, "world")
end

-- Same checks as vanilla onPressButtonNoFocus before it gets to Back/Start:
-- a player in the world, no main menu / terms of service, nothing dragged.
local function isInWorld(jd)
	if not jd or not jd.player or not getSpecificPlayer(jd.player) then return false end
	if ISTermsOfServiceUI and ISTermsOfServiceUI.instance and ISTermsOfServiceUI.instance:isReallyVisible() then return false end
	if MainScreen.instance and MainScreen.instance:isReallyVisible() then return false end
	if getCell() and getCell():getDrag(jd.player) then return false end
	return true
end

-- D-pad: vanilla calls ISVehicleRegulator.onJoypadPressUp/Down and then ISDPadWheels.onDisplay*
-- only in the world (no UI focus, no drag), so onDisplay* is the hook point for the world
-- layer. Other callers (none in vanilla) still get vanilla.
-- The cruise layer is dispatched before vanilla onPress*: mods that wrap onDisplay* (Smart
-- Radial Menu shows its own menu when the vehicle radial stays empty) must not see these presses.
local pressedDir = nil

local function wrapDir(press, release, display, button)
	local vanillaPress = JoypadControllerData[press]
	JoypadControllerData[press] = function(self, ...)
		local jd = self.joypad
		if jd and not jd.isDoingNavigation and jd.focus == nil and isInWorld(jd)
				and isCruiseHeld(jd) and dispatchLayer(jd, button, "cruise") then
			return
		end
		pressedDir = button
		local ok, err = pcall(vanillaPress, self, ...)
		pressedDir = nil
		if not ok then error(err, 0) end
	end

	ISDPadWheels[display] = function(jd, ...)
		if pressedDir ~= button then
			return vanilla[display](jd, ...)
		end
		dispatch(jd, button)
	end

	local vanillaRelease = JoypadControllerData[release]
	JoypadControllerData[release] = function(self, ...)
		local jd = self.joypad
		if jd then
			held[heldKey(jd, button)] = nil
			runRelease(jd, button)
		end
		vanillaRelease(self, ...)
		-- Vanilla passes D-pad releases only to the radial menu; the back button wheel
		-- moved to the D-pad needs it too.
		if jd and jd.player then
			local focus = jd.focus
			if type(focus) == "table" and focus ~= getPlayerRadialMenu(jd.player)
					and focus.hideWhenButtonReleased == button and focus.onJoypadButtonReleased then
				focus:onJoypadButtonReleased(button, jd)
			end
		end
	end
end

wrapDir("onPressUp", "onReleaseUp", "onDisplayUp", Joypad.DPadUp)
wrapDir("onPressDown", "onReleaseDown", "onDisplayDown", Joypad.DPadDown)
wrapDir("onPressLeft", "onReleaseLeft", "onDisplayLeft", Joypad.DPadLeft)
wrapDir("onPressRight", "onReleaseRight", "onDisplayRight", Joypad.DPadRight)

-- The cruise speed actions are dispatched above.
function ISVehicleRegulator.onJoypadPressUp(jd)
	if pressedDir then return false end
	return vanilla.regulatorPressUp(jd)
end

function ISVehicleRegulator.onJoypadPressDown(jd)
	if pressedDir then return false end
	return vanilla.regulatorPressDown(jd)
end

-- Buttons: the world (no UI focus) part of vanilla onPressButton. Back and Start open the
-- wheel / pause only through their actions, so a freed Back/Start does nothing here and
-- is left to the regular bindings. Other buttons keep vanilla (button prompts)
-- unless an action is bound to them. The D-pad comes through onPressUp/... above.
-- The stick radial starts its hold timer on its button (vanilla: on L3, at the end of this).
function JoypadControllerData:onPressButtonNoFocus(button)
	local jd = self.joypad
	if DPAD[button] or not isInWorld(jd) then
		return vanilla.onPressButtonNoFocus(self, button)
	end
	local always = button == Joypad.Back or button == Joypad.Start
	-- vanilla ignores other buttons while paused; actions that work then (game speed) still run
	if not always and isGamePaused() and not jd.activeWhilePaused then
		local action = Bindings.getAction("world", button)
		if action and action.whilePaused then
			dispatchLayer(jd, button, "world")
			return
		end
		return vanilla.onPressButtonNoFocus(self, button)
	end
	if not dispatch(jd, button) and not always then
		vanilla.onPressButtonNoFocus(self, button)
	end
	if button == Bindings.getButton("stickRadial") then
		vanilla.stickDown(Joypad.LStickButton, jd)
	end
end

-- Stick radial ---------------------------------------------------------------------
-- Vanilla ISJoystickButtonRadialMenu tracks L3 only: onJoypadDown starts the timer,
-- ISButtonPrompt:update calls onRepeatLeftStickButton while L3 is down (displays the radial
-- after 250 ms), onJoypadButtonReleased stops it, the radial closes on L3 release.
-- Here all of it uses the stickRadial button; the press is started above.

function ISJoystickButtonRadialMenu.onJoypadDown(button, jd)
end

function ISJoystickButtonRadialMenu.onJoypadButtonReleased(button, jd)
	if button == Bindings.getButton("stickRadial") then
		return vanilla.stickReleased(Joypad.LStickButton, jd)
	end
	-- the rest of vanilla for any stick button: ignore aim until the stick is centered
	if button == Joypad.LStickButton or button == Joypad.RStickButton then
		return vanilla.stickReleased(Joypad.RStickButton, jd)
	end
end

function ISJoystickButtonRadialMenu.displayLeft(jd)
	vanilla.stickDisplayLeft(jd)
	local button = Bindings.getButton("stickRadial")
	if button then
		retargetHide(jd, Joypad.LStickButton, button)
	end
end

-- Reload (ReloadWeapon binding) ------------------------------------------------------

function ISFirearmRadialMenu.onJoypadButtonReleased(buttonPrompt, button, jd)
	local reload = bindingButton(CharacterJoypadButtonBinding.ReloadWeapon)
	if button == reload then
		return vanilla.firearmReleased(buttonPrompt, Joypad.RBumper, jd)
	end
end

function ISFirearmRadialMenu:display()
	vanilla.firearmDisplay(self)
	local jd = JoypadState.players[self.playerNum + 1]
	local reload = bindingButton(CharacterJoypadButtonBinding.ReloadWeapon)
	if jd and reload then
		retargetHide(jd, Joypad.RBumper, reload)
	end
end

-- Vanilla: RB down -> firearm radial timer, L3 down -> stick radial timer.
function ISButtonPrompt:update()
	if not self.player then return end
	local jd = JoypadState.players[self.player + 1]
	if not jd or not jd.isActive then return end
	local reload = bindingButton(CharacterJoypadButtonBinding.ReloadWeapon)
	if reload and reload:isDown(jd.id) then
		ISFirearmRadialMenu.onRepeatRBumper(self)
	end
	local stick = Bindings.getButton("stickRadial")
	if stick and stick:isDown(jd.id) then
		ISJoystickButtonRadialMenu.onRepeatLeftStickButton(jd)
	end
end

-- UI navigation, cruise toggle ---------------------------------------------------------
-- Vanilla onHoldButton: RB held in a UI starts navigation (it handles nothing else);
-- onReleaseButton: RB release ends it, LB release goes to the parent panel, X release
-- toggles cruise control.

function JoypadControllerData:onHoldButton(button, time)
	if button == Bindings.getButton("uiNavigation") then
		return vanilla.onHoldButton(self, Joypad.RBumper, time)
	end
end

-- Vanilla sets the CruiseControl prompt (its press handler) only while evaluating the X button
-- (ISButtonPrompt:getBestXButtonAction), on the CruiseControl button. JoyPadSetup evaluates
-- every binding each frame (updateJoypadFocus) and the last one evaluated on a button sets its
-- prompt, so with CruiseControl off X the evaluation of that button clears it right after
-- (RB: getBestRBButtonAction, no firearm). Here it is set again after every evaluation.
local vanillaGetBestButtonBindingAction = ISButtonPrompt.getBestButtonBindingAction
function ISButtonPrompt:getBestButtonBindingAction(buttonBinding, dir)
	vanillaGetBestButtonBindingAction(self, buttonBinding, dir)
	local cruise = bindingButton(CharacterJoypadButtonBinding.CruiseControl)
	if not cruise or cruise == Joypad.XButton or isPaused() then return end
	local jd = self.player and JoypadState.players[self.player + 1]
	if jd and drivenVehicle(jd) and not getCell():getDrag(self.player) then
		self:setButtonBindingPrompt(CharacterJoypadButtonBinding.CruiseControl,
			getText("IGUI_Controller_CruiseControl"), ISVehicleRegulator.onJoypadPressX, jd)
	end
end

local releasing = nil
local cruiseReleased = false

function ISVehicleRegulator.onJoypadReleaseX(jd)
	if releasing ~= nil and releasing ~= bindingButton(CharacterJoypadButtonBinding.CruiseControl) then
		return
	end
	cruiseReleased = true
	return vanilla.regulatorReleaseX(jd)
end

function JoypadControllerData:onReleaseButton(button)
	local jd = self.joypad
	if jd and not DPAD[button] then
		runRelease(jd, button)
	end
	if jd and jd.isDoingNavigation then
		if button == Bindings.getButton("uiNavigation") then
			jd:endNavigation()
		elseif button == Bindings.getButton("uiNavigateParent") and jd.currentNavigateUI ~= nil then
			jd.currentNavigateUI:onJoypadNavigateParent(jd)
		end
		return
	end

	releasing = button
	cruiseReleased = false
	local ok, err = pcall(vanilla.onReleaseButton, self, button)
	releasing = nil
	if not ok then error(err, 0) end

	if not jd or not jd.player then return end
	-- vanilla toggles cruise control only on X release
	if not cruiseReleased and button == bindingButton(CharacterJoypadButtonBinding.CruiseControl)
			and ISVehicleRegulator.xPressed[jd.id] then
		vanilla.regulatorReleaseX(jd)
	end
	-- vanilla stops the stick radial timer only on L3/R3 release
	local stick = Bindings.getButton("stickRadial")
	if button == stick and button ~= Joypad.LStickButton and button ~= Joypad.RStickButton then
		vanilla.stickReleased(Joypad.LStickButton, jd)
	end
end

-- Steam Input -------------------------------------------------------------------
-- The actions are also Steam Input game actions (SteamInput.java registers the manifest,
-- media/steam_input/manifest.vdf), bound in the Steam controller configurator to any
-- button, paddle, long press or chord. They run like a press of their button, on top of
-- whatever is bound here: in the world, also with a UI focused (a dedicated input can't
-- clash with UI navigation), not while paused unless the action works then.
-- Wheels close and pick the slice when the Steam action is released, as with a button.
--
-- The situation of each player picks the Steam action set layers (bottom to top), so the
-- same input can do different things: on foot / in a vehicle, then aiming, a UI focused,
-- the inventory / loot window, the map; the main menu and the pause menu (Esc) get "menu" on every controller.
-- Situational actions are declared in their layer (tools/steam_actions.txt), so they can only
-- fire there; the rest of the controller falls through to the set (the plain gamepad).

local STEAM_ALWAYS = { commandWheel = true, pause = true }

-- The joypad of a Steam controller; unknown (-1): the only joypad player's.
local function steamJoypad(id)
	if id >= 0 then
		local c = JoypadState.controllers[id]
		return c and c.joypad
	end
	local found = nil
	for i = 1, getMaxActivePlayers() do
		local jd = JoypadState.players[i]
		if jd then
			if found then return nil end
			found = jd
		end
	end
	return found
end

local function steamPress(action, jd, key)
	if not isInWorld(jd) then return end
	if isGamePaused() and not action.whilePaused and not STEAM_ALWAYS[action.id] then return end
	run(action, jd, key)
end

local function steamRelease(jd, key)
	runRelease(jd, key)
	local focus = jd.focus
	if type(focus) == "table" and focus.hideWhenButtonReleased == key and focus.onJoypadButtonReleased then
		focus:onJoypadButtonReleased(key, jd)
	end
end

local MAP_UI = { ISWorldMap = true, ISMap = true }
local INVENTORY_UI = { ISInventoryPage = true }

local function isMenuVisible()
	return MainScreen.instance ~= nil and MainScreen.instance:isReallyVisible()
end

-- steamInput.passengerLayer: vehicle (default) or onfoot for passengers.
local function passengerOnFoot()
	return readSetting("steamInput.passengerLayer") == "onfoot"
end

local function playerLayers(jd, onFootPassenger)
	local playerObj = getSpecificPlayer(jd.player)
	if not playerObj or playerObj:isDead() then return "" end
	local layers = {}
	local vehicle = playerObj:getVehicle()
	if vehicle and (vehicle:isDriver(playerObj) or not onFootPassenger) then
		table.insert(layers, "vehicle")
	else
		table.insert(layers, "onfoot")
	end
	if playerObj:isAiming() then
		table.insert(layers, "aiming")
	end
	local focus = jd.focus
	if focus ~= nil then
		table.insert(layers, "ui")
		if type(focus) == "table" and INVENTORY_UI[focus.Type] then
			table.insert(layers, "inventory")
		end
		if type(focus) == "table" and MAP_UI[focus.Type] then
			table.insert(layers, "map")
		end
	end
	return table.concat(layers, ",")
end

local lastLayers = nil

local function updateSteamLayers()
	local spec
	if isMenuVisible() then
		spec = "*=menu"
	else
		local parts = {}
		local onFootPassenger = passengerOnFoot()
		for i = 1, getMaxActivePlayers() do
			local jd = JoypadState.players[i]
			if jd and jd.player and jd.id then
				table.insert(parts, tostring(jd.id) .. "=" .. playerLayers(jd, onFootPassenger))
			end
		end
		table.insert(parts, "*=")
		spec = table.concat(parts, ";")
	end
	if spec ~= lastLayers then
		lastLayers = spec
		GamepadTweaks_steamInputSetLayers(spec)
	end
end

local function steamTick()
	if not GamepadTweaks_steamInputPoll then return end
	if GamepadTweaks_steamInputSetLayers then
		local ok, err = pcall(updateSteamLayers)
		if not ok then log("ERROR: steam layers: " .. tostring(err)) end
	end
	local events = GamepadTweaks_steamInputPoll()
	if not events then return end
	for id, controller, down in events:gmatch("(%w+):(%-?%d+):(%d)") do
		local action = actionById[id]
		local jd = steamJoypad(tonumber(controller))
		if action and action.run and jd then
			local key = "steam:" .. id
			if down == "1" then
				steamPress(action, jd, key)
			else
				steamRelease(jd, key)
			end
		end
	end
end

-- Held actions with followsButton (camera pan) run while their button is down, whenever it was
-- pressed: vanilla reads RB every frame while aiming (PlayerCamera.update), so RB pressed before
-- aiming pans too, and the player can pick "look far" first and aim after. The press dispatch
-- (aiming layer) only catches presses made while aiming.
local followed = {} -- ["<joypad>:<action>"] = true while the button holds the action

local function followButtons()
	for _, action in ipairs(Bindings.actions) do
		if action.followsButton and action.run and action.release then
			local button = Bindings.getButton(action.id)
			for i = 1, getMaxActivePlayers() do
				local jd = JoypadState.players[i]
				if jd and jd.id then
					local key = tostring(jd.id) .. ":" .. action.id
					local down = button ~= nil and jd.focus == nil and button:isDown(jd.id) and isInWorld(jd)
					if down ~= (followed[key] == true) then
						followed[key] = down or nil
						local ok, err = pcall(down and action.run or action.release, jd.controller, jd)
						if not ok then log("ERROR: " .. action.id .. " failed: " .. tostring(err)) end
					end
				end
			end
		end
	end
end

local function tick()
	local ok, err = pcall(followButtons)
	if not ok then log("ERROR: held buttons: " .. tostring(err)) end
	steamTick()
end

-- Every frame, also in the main menu (registers the manifest early) and while paused.
Events.OnRenderTick.Add(tick)

Events.OnGameStart.Add(refresh)
