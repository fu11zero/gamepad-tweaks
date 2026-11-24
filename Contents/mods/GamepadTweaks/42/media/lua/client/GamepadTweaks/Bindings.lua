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
-- bindings: preset.<preset>.<layer>.bind.<action>=<button> in ~/Zomboid/GamepadTweaks.properties
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

require "GamepadTweaks/BindingEvents"

GamepadTweaks = GamepadTweaks or {}
local BindingEvents = GamepadTweaks.BindingEvents
require "GamepadTweaks/NativeBindings"
local Native = GamepadTweaks.NativeBindings
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
-- (also used to sort editor choices); label: translation key (default UI_GamepadTweaks_action_<id>).
-- layer: the action's default context (and its only context for special actions).
-- hold, uiHold and navigation use separate input phases from ordinary button presses.
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
	{ id = "cruiseFaster", category = "vehicle", layer = "vehicle", repeats = true, run = cruiseFaster },
	{ id = "cruiseSlower", category = "vehicle", layer = "vehicle", repeats = true, run = cruiseSlower },
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

Native.register(Bindings.add)

-- Settings ---------------------------------------------------------------------

local actionByButton = {} -- legacy button hooks
local layerBindings = {}
local contextCache = {}
local observedInputs = {}
local hasGestures = false

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

Bindings.layers = { "world", "onfoot", "vehicle", "aiming", "ui", "inventory" }

local EDITOR_LAYER = { hold = "world", uiHold = "ui", navigation = "ui" }

local function defaultLayer(action)
	return EDITOR_LAYER[action.layer] or action.layer
end

-- Preserve bindings and preset copies made before the editor filtered new assignments.
local function canStoreIn(action, layer)
	if action.steamOnly then return false end
	if action.native then return action.layers[layer] == true end
	if action.layer ~= "world" then return layer == defaultLayer(action) end
	return layer == "world" or layer == "onfoot" or layer == "vehicle" or layer == "aiming"
		or layer == "ui" or layer == "inventory"
end

-- Shared world actions are available in General and can be overridden on foot or in a
-- vehicle. The Steam action sections guide which actions are specific to those contexts.
local ON_FOOT = {
	firearmRadial = true, fireMode = true, sharpenWeapon = true, useTool = true,
	curtain = true, lightSource = true, grabCorpse = true, dropPrimary = true,
	dropSecondary = true, dropBothHands = true, dropBag = true, dropHandsAndBag = true,
	sitOnGround = true, searchMode = true, releaseRope = true, animalRadial = true,
	moveFurniture = true, rotateBuilding = true, buildingMenu = true,
}
local VEHICLE = { engine = true, headlights = true, heater = true, horn = true }
-- These actions can also be used next to a vehicle or from the passenger seat.
local ON_FOOT_OR_VEHICLE = { switchSeat = true, vehicleInfo = true, shout = true }
local AIMING = { fireMode = true, lightSource = true }

function Bindings.canBindIn(action, layer)
	if action.steamOnly then return false end
	if action.native then return action.layers[layer] == true end
	if action.layer ~= "world" then return layer == defaultLayer(action) end
	local id = action.id
	if layer == "aiming" then return AIMING[id] == true end
	if ON_FOOT[id] then return layer == "onfoot" end
	if VEHICLE[id] then return layer == "vehicle" end
	if ON_FOOT_OR_VEHICLE[id] then return layer == "onfoot" or layer == "vehicle" end
	return layer == "world" or layer == "onfoot" or layer == "vehicle"
end

function Bindings.defaultEvent(action)
	return EDITOR_LAYER[action.layer] and "native" or "press"
end

local function slot(binding)
	local key = BindingEvents.slot(binding)
	return binding.event == "native" and key .. "|" .. binding.action.layer or key
end

local function presetKey(name, id, layer)
	local encoded = string.gsub(name, "[^%w_%-]", function(c) return "%" .. string.byte(c) .. ";" end)
	return "preset." .. encoded .. (layer and "." .. layer or "") .. ".bind." .. id
end

local function bindingValue(preset, action, layer)
	local key = presetKey(preset, action.id, layer)
	local value = readSetting(key)
	if value == nil and layer == defaultLayer(action) then
		value = readSetting(presetKey(preset, action.id))
	end
	return value, key
end

-- An empty list explicitly unbinds the action. Old single assignments are a
-- one-item list on disk, so only actions with additional chords need a separator.
local function readBindings(preset, action, layer)
	local value, key = bindingValue(preset, action, layer)
	if not value then return nil end
	value = value:match("^%s*(.-)%s*$")
	if value == "none" or value == "" then return {} end
	local result = {}
	for item in value:gmatch("[^~]+") do
		local binding = BindingEvents.decode(item, Bindings.defaultEvent(action))
		if binding then
			table.insert(result, binding)
		else
			log("WARN: " .. key .. ": " .. item .. " is not a binding")
		end
	end
	return #result > 0 and result or nil
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
		if binding.getJoypadAxis1d then
			table.insert(parts, tostring(binding:getJoypadAxis1d() or binding:getJoypadAxis2d()))
			table.insert(parts, tostring(binding:getAxisMinThreshold()))
			table.insert(parts, tostring(binding:getAxisMaxThreshold()))
		end
	end
	return table.concat(parts, ",")
end

-- An action set to a button takes it from the action that has it by default in the same
-- layer (bind.commandWheel=DPadDown alone moves the emote wheel off the D-pad).
-- A regular binding on the button of a default world action takes it too: vanilla has none
-- on the D-pad, Back or Start, so one there was put by the player (Melee on D-pad left
-- would otherwise also open the weapon wheel).
local function actionOn(layer, button)
	local buttons = actionByButton[layer]
	return buttons and buttons[button] or nil
end

function Bindings.reload()
	actionByButton, layerBindings, contextCache, observedInputs = {}, {}, {}, {}
	hasGestures = false
	local preset = Bindings.currentPreset()
	local editable = Bindings.isPresetEditable(preset)
	local regular = regularWorldBindings()
	local changed = {}
	for _, layer in ipairs(Bindings.layers) do layerBindings[layer] = {} end

	local function assign(action, layer, binding, explicit)
		if binding then
			binding.action, binding.layer = action, layer
			local input = binding.input
			local legacyLayer = binding.event == "native" and action.layer or layer
			if not action.native and binding.event == "press" and layer == "world" and regular[input] then
				if not explicit then
					table.insert(changed, action.id .. "=none (" .. tostring(input) .. " used by " .. regular[input] .. ")")
					return
				end
				log("WARN: " .. action.id .. " shares " .. tostring(input) .. " with " .. regular[input])
			end
			local key = slot(binding)
			local other = layerBindings[layer][key]
			if other then
				if explicit then
					log("WARN: " .. layer .. ": " .. action.id .. " and " .. other.action.id .. " use " .. key)
				end
				return
			end
			layerBindings[layer][key] = binding
			table.insert(action.bindings[layer], binding)
			if not action.native and not binding.threshold and (binding.event == "press" or binding.event == "native") then
				actionByButton[legacyLayer] = actionByButton[legacyLayer] or {}
				actionByButton[legacyLayer][input] = action
			end
			if binding.threshold then
				observedInputs[BindingEvents.inputKey(input, binding.threshold)] = { input = input, threshold = binding.threshold }
			end
			if action.native or binding.threshold or binding.event ~= Bindings.defaultEvent(action) then hasGestures = true end
			local modifier = binding.modifier
			if modifier then
				local modifierKey = BindingEvents.inputKey(modifier, binding.modifierThreshold)
				observedInputs[modifierKey] = { input = modifier, threshold = binding.modifierThreshold }
			end
		end
		if explicit then
			local value = binding and BindingEvents.encode(binding, Bindings.defaultEvent(action)) or "none"
			table.insert(changed, layer .. "." .. action.id .. "=" .. value)
		end
	end

	local defaults = {}
	for _, action in ipairs(Bindings.actions) do
		action.bindings = {}
		if not action.steamOnly then
			local home = defaultLayer(action)
			for _, layer in ipairs(Bindings.layers) do
				if canStoreIn(action, layer) then
					action.bindings[layer] = {}
					local assignments = editable and readBindings(preset, action, layer)
					if assignments then
						if #assignments == 0 then assign(action, layer, nil, true) end
						for _, binding in ipairs(assignments) do assign(action, layer, binding, true) end
					elseif layer == home and action.button then
						table.insert(defaults, action)
					end
				end
			end
		end
	end
	for _, action in ipairs(defaults) do
		assign(action, defaultLayer(action), BindingEvents.assignment(action.button, nil, Bindings.defaultEvent(action)), false)
	end
	log("button actions (" .. preset .. "): " .. (#changed > 0 and table.concat(changed, " ") or "vanilla"))
end

-- Copies explicit bindings in all layers, including disabled default actions.
function Bindings.copyPreset(from, to)
	if not GamepadTweaks_setSetting or not Bindings.isPresetEditable(from) then return end
	for _, action in ipairs(Bindings.actions) do
		for _, layer in ipairs(Bindings.layers) do
			if canStoreIn(action, layer) then
				local value = bindingValue(from, action, layer)
				if value then
					GamepadTweaks_setSetting(presetKey(to, action.id, layer), value)
				end
			end
		end
	end
end

local function migrateLayers()
	for name, preset in pairs(gamepadBinding.presets) do
		if preset.loadedSet then
			for _, action in ipairs(Bindings.actions) do
				if not action.steamOnly then
					local oldKey = presetKey(name, action.id)
					local value = readSetting(oldKey)
					if value ~= nil then
						local key = presetKey(name, action.id, defaultLayer(action))
						if readSetting(key) ~= nil or GamepadTweaks_setSetting(key, value) then
							GamepadTweaks_setSetting(oldKey, nil)
						end
					end
				end
			end
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
		if value and not action.steamOnly then
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
	local copied = {}
	for name, preset in pairs(gamepadBinding and gamepadBinding.presets or {}) do
		if preset.loadedSet then
			table.insert(names, name)
			for id, value in pairs(legacy) do
				local existing, key = bindingValue(name, actionById[id], defaultLayer(actionById[id]))
				if existing == nil and not GamepadTweaks_setSetting(key, value) then
					copied[id] = false
				elseif copied[id] == nil then
					copied[id] = true
				end
			end
		end
	end
	for id, ok in pairs(copied) do
		if ok then GamepadTweaks_setSetting("bind." .. id, nil) end
	end
	log("bindings: global bind.* moved to the presets " .. table.concat(names, ", "))
end

local REGULAR_CHECK_MS = 500
local regularCheckedAt = 0
local loadedRegular = nil

local function refresh()
	if not migrated and GamepadTweaks_setSetting then
		migrateGlobal()
		migrateLayers()
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

local function getAction(layer, button)
	refresh()
	return actionOn(layer, button)
end

local function regularAssignment(action, layer)
	for _, binding in ipairs(action.bindings[layer] or {}) do
		if binding.event ~= "modifier" then return binding end
	end
end

function Bindings.getAssignments(action, layer)
	refresh()
	return action.bindings[layer] or {}
end

local function getButton(id)
	refresh()
	local action = actionById[id]
	local binding = regularAssignment(action, defaultLayer(action))
	return binding and binding.event == Bindings.defaultEvent(action) and not binding.threshold and binding.input or nil
end

-- Settings panel ---------------------------------------------------------------

local LAYER_NOTE = { hold = true, uiHold = true, navigation = true }

function Bindings.getLabel(action)
	local text = getText(action.label or ("UI_GamepadTweaks_action_" .. action.id))
	if LAYER_NOTE[action.layer] then
		text = text .. " " .. getText("UI_GamepadTweaks_layer_" .. action.layer)
	end
	return text
end

function Bindings.getActionById(id)
	return actionById[id]
end

-- Actions the button is on, in registration order.
function Bindings.getActionsOn(layer, button)
	refresh()
	local result = {}
	for _, action in ipairs(Bindings.actions) do
		for _, binding in ipairs(action.bindings[layer] or {}) do
			if binding.input == button then table.insert(result, binding) end
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

local function sameAssignment(a, b)
	return a and b and a.action == b.action and slot(a) == slot(b)
end

function Bindings.canUseEvent(layer, action, options, previous)
	local binding = BindingEvents.assignment(options.input, options, Bindings.defaultEvent(action))
	if not binding then return false end
	binding.action = action
	local occupied = layerBindings[layer][slot(binding)]
	if occupied and not sameAssignment(occupied, previous) then return false end
	local regular = binding.event ~= "modifier" and regularAssignment(action, layer)
	-- Editing a chord into an ordinary event must preserve the action's ordinary binding.
	return not regular or not previous or previous.action ~= action or sameAssignment(regular, previous)
end

-- One ordinary binding per action and layer, with independent additional chords.
-- An edit identifies the previous row by its event slot so other chords survive.
function Bindings.set(layer, id, input, options, previous)
	local action = actionById[id]
	if not action or not Bindings.canEdit() then return false end
	if input and not BindingEvents.hasInput(input) then return false end
	refresh()
	local preset = Bindings.currentPreset()
	if not Bindings.isPresetEditable(preset) or not canStoreIn(action, layer) then return false end
	if input and not Bindings.canBindIn(action, layer) then
		if not previous or previous.action ~= action or previous.input ~= input then return false end
	end
	local binding = input and BindingEvents.assignment(input, options, Bindings.defaultEvent(action))
	if input and not binding then return false end
	if binding and not Bindings.canUseEvent(layer, action, binding, previous) then return false end

	local function writeValue(owner, addition)
		local result = {}
		local regular = owner == action and ((addition and addition.event ~= "modifier") or (not addition and not previous))
			and regularAssignment(owner, layer)
		local remove = previous or regular
		local defaultEvent = Bindings.defaultEvent(owner)
		for _, existing in ipairs(owner.bindings[layer] or {}) do
			if not sameAssignment(existing, remove) and not sameAssignment(existing, regular) then
				table.insert(result, BindingEvents.encode(existing, defaultEvent))
			end
		end
		if addition then table.insert(result, BindingEvents.encode(addition, defaultEvent)) end
		return #result > 0 and table.concat(result, "~") or "none"
	end

	local key = presetKey(preset, id, layer)
	local originalValue = readSetting(key)
	local ok = GamepadTweaks_setSetting(key, writeValue(action, binding))
	if ok and previous and previous.action ~= action then
		local owner = previous.action
		ok = GamepadTweaks_setSetting(presetKey(preset, owner.id, layer), writeValue(owner))
		if not ok then GamepadTweaks_setSetting(key, originalValue) end
	end
	refresh()
	return ok
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

local function dispatchAction(jd, button, action)
	local key = heldKey(jd, button)
	if DPAD[button] then
		local previous = held[key]
		held[key] = previous or action
		if previous and (previous ~= action or not action.repeats) then return true end
	end
	if not action.followsButton then run(action, jd, button) end
	return true
end

-- Camera pan also works while looking out of a vehicle.
local function worldAction(jd, button)
	refresh()
	local playerObj = getSpecificPlayer(jd.player)
	if not playerObj then return nil end
	if playerObj:isAiming() or playerObj:isLookingWhileInVehicle() then
		local aiming = actionOn("aiming", button)
		if aiming then return aiming end
	end
	return actionOn(playerObj:getVehicle() and "vehicle" or "onfoot", button)
		or actionOn("world", button)
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

-- Compose the active context per event. A higher layer overrides the same event
-- while a double press, hold or chord in another active layer can share the input.
-- Distinct axis thresholds have independent press/release cycles.
local function gestureContext(jd, focused)
	local layers = {}
	if focused then
		if type(jd.focus) == "table" and jd.focus.Type == "ISInventoryPage" then
			table.insert(layers, "inventory")
		end
		table.insert(layers, "ui")
	else
		local player = getSpecificPlayer(jd.player)
		if player:isAiming() or player:isLookingWhileInVehicle() then table.insert(layers, "aiming") end
		table.insert(layers, player:getVehicle() and "vehicle" or "onfoot")
		table.insert(layers, "world")
	end
	local paused = isGamePaused() and not jd.activeWhilePaused
	local navigating = focused and jd.isDoingNavigation == true
	local key = table.concat(layers, "|") .. (paused and "|paused" or "") .. (navigating and "|nav" or "")
	if contextCache[key] then return contextCache[key] end

	local context = {
		groups = {}, buttons = {}, axes = {}, modifiers = {},
		nativeActions = {}, rawUI = {}, promptButtons = {}, promptChords = {}, catalog = {}, nativeCandidates = {},
	}
	local seen, overridden = {}, {}
	local function groupFor(input, threshold)
		local inputKey = BindingEvents.inputKey(input, threshold)
		local group = context.groups[inputKey]
		if not group then
			group = { input = input, threshold = threshold, chords = {} }
			context.groups[inputKey] = group
			if threshold then
				table.insert(context.axes, inputKey)
			else
				context.buttons[input] = inputKey
			end
		end
		return group
	end

	for _, layer in ipairs(layers) do
		for _, action in ipairs(Bindings.actions) do
			for _, binding in ipairs(action.bindings[layer] or {}) do
				if binding.event ~= "native" and (navigating == (action.id == "uiNavigateParent"))
						and (not paused or action.whilePaused or binding.input == Joypad.Back or binding.input == Joypad.Start) then
					local eventSlot = slot(binding)
					local name = action.name
					if not action.native or binding.modifier or not overridden[name] then
						if action.native then
							-- A higher layer can take the next press without interrupting
							-- an action already held by a lower layer that's still active.
							context.nativeCandidates[binding] = true
							if not binding.modifier then
								overridden[name] = true
								context.nativeActions[name] = action
								if action.prompt then
									context.hasPrompts = true
									if not binding.threshold and not seen[eventSlot] then
										context.promptButtons[binding.input] = true
									end
								end
							end
						end
						if not seen[eventSlot] then
							seen[eventSlot] = true
							local group = groupFor(binding.input, binding.threshold)
							if binding.modifier then
								table.insert(group.chords, binding)
								if action.prompt then
									context.promptChords[name], context.hasPrompts = true, true
								end
								context.modifiers[binding.modifier] = true
							else
								group[binding.event] = binding
							end
						end
					end
				end
			end
		end
	end

	-- An inherited vanilla button remains a normal press when the player adds a
	-- competing gesture or uses that button as a modifier.
	for _, action in ipairs(Bindings.actions) do
		if action.native and not paused and not navigating
				and (focused == (action.uiButton ~= nil)) and (not focused or action.layers[layers[1]]) then
			table.insert(context.catalog, action)
			local raw, threshold = Native.rawInput(action, focused and layers[1])
			local rawKey = raw and BindingEvents.inputKey(raw, threshold)
			local group = rawKey and context.groups[rawKey]
			local replace = context.nativeActions[action.name] ~= nil
			local modifier = raw and context.modifiers[raw]
			local competing = group and (group.hold or group.double or #group.chords > 0)
			local occupied = group and group.press and (group.press.action.native
				or group.press.layer ~= "world")
			if replace or modifier or competing or occupied then
				context.nativeActions[action.name] = action
				if raw and action.prompt then
					context.hasPrompts = true
					if not threshold then context.promptButtons[raw] = true end
				end
				if raw and action.uiButton and replace then context.rawUI[raw] = true end
				if not replace and not occupied then
					group = group or groupFor(raw, threshold)
					if threshold then observedInputs[rawKey] = { input = raw, threshold = threshold } end
					group.fallback = group.fallback or {}
					table.insert(group.fallback, { input = raw, threshold = threshold, event = "press", action = action, inherited = true })
				end
			end
		end
	end
	for _, group in pairs(context.groups) do
		group.isModifier = context.modifiers[group.input] == true
		if not group.press and group.fallback then group.press = group.fallback[1] end
		group.managed = group.threshold or group.hold or group.double or #group.chords > 0
			or group.isModifier or (group.press and (group.press.action.native
				or Bindings.defaultEvent(group.press.action) == "native"))
	end
	contextCache[key] = context
	return context
end

local joypadGestures = {}
local function gestures(jd)
	local state = joypadGestures[jd]
	if not state then
		state = { cycles = {}, down = {}, modifierUsed = {}, buttons = {}, pulses = {}, native = {} }
		joypadGestures[jd] = state
	end
	return state
end

local function nativeSignalActive(jd, context, signal)
	if not signal or not context or signal.focus ~= jd.focus then return false end
	local binding = signal.binding
	if context.nativeCandidates[binding] then return true end
	if not binding.inherited then return false end
	local key = BindingEvents.inputKey(binding.input, binding.threshold)
	return context.groups[key] == signal.key
end

local function publishNative(jd, state, context)
	if not GamepadTweaks_publishNativeBindings then return end
	local entries = {}
	if context then
		for name, action in pairs(context.nativeActions) do
			if not action.uiButton then
				local active = nativeSignalActive(jd, context, state.native[name])
				table.insert(entries, name .. (active and "=1" or "=0"))
			end
		end
		-- A chord can add an action without replacing its stock input.
		for name, signal in pairs(state.native) do
			if not context.nativeActions[name] and nativeSignalActive(jd, context, signal) then
				table.insert(entries, name .. "=1")
			end
		end
	end
	table.sort(entries)
	local spec = table.concat(entries, ",")
	if spec ~= state.nativeSpec then
		GamepadTweaks_publishNativeBindings(jd.id, spec)
		state.nativeSpec = spec
	end
end

local vanillaUpdateJoypadFocus = updateJoypadFocus
local function updateNativePrompts(jd, context)
	if not context.hasPrompts then
		jd.gtNativePrompts, jd.gtNativePromptContext = nil, nil
		return vanillaUpdateJoypadFocus(jd)
	end
	return Native.collect(jd, context, vanillaUpdateJoypadFocus)
end

if vanillaUpdateJoypadFocus then
	function updateJoypadFocus(jd)
		if jd and jd.focus == nil and isInWorld(jd) and not JoypadState.disableControllerPrompt then
			refresh()
			if hasGestures then return updateNativePrompts(jd, gestureContext(jd, false)) end
		end
		if jd then jd.gtNativePrompts, jd.gtNativePromptContext = nil, nil end
		return vanillaUpdateJoypadFocus(jd)
	end
end

local function finishRelease(release, cancel)
	local ok, err = pcall(release, cancel)
	if not ok then log("ERROR: controller release: " .. tostring(err)) end
end

local function stopGesture(jd, cycle, disconnected)
	if cycle.release then finishRelease(cycle.release) end
	cycle.release = nil
	for _, release in ipairs(cycle.nativeRelease or {}) do finishRelease(release, disconnected) end
	cycle.nativeRelease = nil
	local focus = cycle.radial
	cycle.radial = nil
	if focus and jd.focus == focus and focus.hideWhenButtonReleased == cycle.group.input then
		if disconnected and focus.undisplay then
			focus:undisplay()
		else
			focus:onJoypadButtonReleased(cycle.group.input, jd)
		end
	end
end

-- Give stateful actions a brief pulse if their input was already released when the
-- gesture resolved, so the game can observe the action independently of frame order.
local function emitGesture(jd, state, cycle, binding, now, physicallyDown)
	local action, input = binding.action, binding.input
	local oldFocus = jd.focus
	if action.native then
		if action.uiButton then
			Native.runUI(action, jd)
		else
			local context = gestureContext(jd, oldFocus ~= nil)
			local signal = { binding = binding, key = cycle.group, focus = oldFocus, started = now }
			if Native.isPulse(action) or not physicallyDown then signal.deadline = now + 50 end
			state.native[action.name] = signal
			publishNative(jd, state, context)
			if action.prompt and not JoypadState.disableControllerPrompt then
				local ok, release = pcall(function()
					if jd.gtNativePromptContext ~= context and vanillaUpdateJoypadFocus then updateNativePrompts(jd, context) end
					return Native.runPrompt(binding, jd, physicallyDown, vanilla.firearmReleased)
				end)
				if not ok then
					log("ERROR: " .. action.id .. ": " .. tostring(release))
				elseif release then
					cycle.nativeRelease = cycle.nativeRelease or {}
					table.insert(cycle.nativeRelease, release)
				end
			end
		end
		cycle.fired = binding
		return
	end
	for i = #state.pulses, 1, -1 do
		local pulse = state.pulses[i]
		if pulse.action == action then
			table.remove(state.pulses, i)
			finishRelease(pulse.release)
		end
	end
	local release
	if action.id == "stickRadial" then
		if getSpecificPlayer(jd.player):getVehicle() or not getCore():getOptionEnableLeftJoystickRadialMenu() then return end
		vanilla.stickDown(Joypad.LStickButton, jd)
		vanilla.stickDisplayLeft(jd)
		retargetHide(jd, Joypad.LStickButton, input)
		release = function() vanilla.stickReleased(Joypad.LStickButton, jd) end
	elseif action.id == "uiNavigation" then
		if not jd.focus or jd.focus.disableJoypadNavigation or jd.isDoingNavigation then return end
		jd:startNavigation()
		jd.gtNavigationButton = input
		release = function()
			if jd.gtNavigationButton == input then
				jd.gtNavigationButton = nil
				if jd.isDoingNavigation then jd:endNavigation() end
			end
		end
	elseif action.id == "uiNavigateParent" then
		if jd.isDoingNavigation and jd.currentNavigateUI then jd.currentNavigateUI:onJoypadNavigateParent(jd) end
	else
		local ok, err = pcall(action.run, jd.controller, jd)
		if not ok then
			log("ERROR: " .. action.id .. " failed: " .. tostring(err))
			return
		end
		retargetHide(jd, action.hides or action.button, input)
		if action.release then release = function() action.release(jd.controller, jd) end end
	end
	local focus = jd.focus
	if type(focus) == "table" and focus ~= oldFocus and focus.hideWhenButtonReleased == input then
		if physicallyDown then
			-- A physical button release is forwarded by vanilla. Axes have no such callback.
			if cycle.group.threshold then cycle.radial = focus end
		else
			-- Vanilla may still be delivering this same release. Arm A after
			-- its callback returns, even if A was the input that opened the wheel.
			focus.hideWhenButtonReleased = nil
			state.confirmRadial = focus
		end
	end
	if physicallyDown then
		cycle.release = release
	elseif release then
		table.insert(state.pulses, { action = action, at = now + 60, release = release })
	end
	cycle.fired = binding
end

local function emitResolved(jd, state, cycle, binding, now, down)
	emitGesture(jd, state, cycle, binding, now, down)
	if binding == cycle.group.press and cycle.group.fallback then
		for _, fallback in ipairs(cycle.group.fallback) do
			if fallback ~= binding and jd.focus == cycle.focus then
				emitGesture(jd, state, cycle, fallback, now, down)
			end
		end
	end
end

local function pressGesture(jd, state, key, group, now)
	local cycle = state.cycles[key]
	local function emit(binding)
		emitResolved(jd, state, cycle, binding, now, cycle.down)
	end
	if cycle and cycle.group == group and cycle.focus == jd.focus then
		BindingEvents.Gesture.advance(cycle, group, now, emit)
	end
	if not cycle or cycle.group ~= group or cycle.focus ~= jd.focus or (not cycle.down and not cycle.firstAt) then
		cycle = { group = group, focus = jd.focus }
		state.cycles[key] = cycle
	end
	local chord
	for _, candidate in ipairs(group.chords) do
		local modifier = candidate.modifier
		local modifierKey = BindingEvents.inputKey(modifier, candidate.modifierThreshold)
		-- For buttons, the game can deliver both presses before the next sample.
		-- Honor the callback order when that happens.
		if (state.down[modifierKey] or state.buttons[modifier]) and BindingEvents.isDown(
				BindingEvents.magnitude(modifier, jd.id), candidate.modifierThreshold, true) then
			chord = candidate
			state.modifierUsed[modifier] = true
			for _, modifierCycle in pairs(state.cycles) do
				if modifierCycle.group.input == modifier and modifierCycle.down then
					modifierCycle.suppressPress = true
					-- Its own hold remains eligible. Clear only a pending short press.
				end
			end
			break
		end
	end
	BindingEvents.Gesture.press(cycle, group, now, chord, state.modifierUsed[group.input], emit)
end

local function releaseGesture(jd, state, key, cycle, current, now)
	if cycle.group == current and cycle.focus == jd.focus then
		BindingEvents.Gesture.release(cycle, current, now, function(binding)
			emitResolved(jd, state, cycle, binding, now, false)
		end)
	else
		cycle.down, cycle.firstAt = false, nil
	end
	stopGesture(jd, cycle)
	for _, signal in pairs(state.native) do
		if signal.key == cycle.group and not signal.deadline then
			signal.deadline = math.max(signal.started + 30, now)
		end
	end
	if not cycle.firstAt then state.cycles[key] = nil end
end

local function gestureButtonPressed(jd, button, focused)
	if not hasGestures then return false end
	local context = gestureContext(jd, focused)
	local key = context.buttons[button]
	local group = key and context.groups[key]
	local state = gestures(jd)
	if not focused and context.promptButtons[button] and jd.gtNativePromptContext ~= context
			and vanillaUpdateJoypadFocus then
		updateNativePrompts(jd, context)
	end
	local repeated = DPAD[button] and state.buttons[button]
	state.buttons[button] = true
	if not group or not group.managed then
		publishNative(jd, state, context)
		return focused and context.rawUI[button] == true
	end
	publishNative(jd, state, context)
	local now = getTimestampMs()
	if not repeated then
		pressGesture(jd, state, key, group, now)
	else
		local cycle = state.cycles[key]
		if cycle and cycle.group == group and cycle.fired and cycle.fired.action.repeats then
			emitGesture(jd, state, cycle, cycle.fired, now, true)
		end
	end
	return true
end

local function gestureButtonReleased(jd, button)
	local state = joypadGestures[jd]
	if not state then return end
	state.buttons[button], state.modifierUsed[button] = nil, nil
	local key = BindingEvents.inputKey(button)
	local cycle = state.cycles[key]
	if not cycle or not cycle.down then return end
	local current = isInWorld(jd) and gestureContext(jd, jd.focus ~= nil).groups[key]
	releaseGesture(jd, state, key, cycle, current, getTimestampMs())
end

local function tickGestures()
	local now = getTimestampMs()
	local connected, ids = {}, {}
	for i = 1, getMaxActivePlayers() do
		local jd = JoypadState.players[i]
		if jd and jd.id and jd.isActive and jd:isConnected() then
			connected[jd], ids[jd.id] = true, true
			if hasGestures or joypadGestures[jd] then
				local state = gestures(jd)
				local context = isInWorld(jd) and gestureContext(jd, jd.focus ~= nil)
				local sampled = {}
				local stillDown = {}
				for key, spec in pairs(observedInputs) do
					local value = BindingEvents.magnitude(spec.input, jd.id)
					sampled[key] = BindingEvents.isDown(value, spec.threshold, state.down[key])
					if sampled[key] then stillDown[spec.input] = true end
				end
				for input in pairs(state.modifierUsed) do
					if not stillDown[input] then state.modifierUsed[input] = nil end
				end
				for key, cycle in pairs(state.cycles) do
					local group = cycle.group
					local current = context and context.groups[key]
					local down = group.threshold and sampled[key] or (not group.threshold and group.input:isDown(jd.id))
					if cycle.down and not down then
						releaseGesture(jd, state, key, cycle, current, now)
					elseif current == group and cycle.focus == jd.focus then
						BindingEvents.Gesture.advance(cycle, group, now, function(binding)
							emitResolved(jd, state, cycle, binding, now, cycle.down)
						end)
						if not cycle.down and not cycle.firstAt then state.cycles[key] = nil end
					elseif cycle.down then
						-- Keep cleanup for actions already started. A pending click cannot
						-- resume after leaving and re-entering its original context.
						cycle.consumed, cycle.firstAt = true, nil
						if cycle.fired and cycle.fired.action.followsButton then stopGesture(jd, cycle) end
					else
						state.cycles[key] = nil
					end
				end
				if context then
					local focus = jd.focus
					for _, key in ipairs(context.axes) do
						if jd.focus ~= focus then break end
						if sampled[key] and state.down[key] == false then
							pressGesture(jd, state, key, context.groups[key], now)
						end
					end
				end
				state.down = sampled
				for name, signal in pairs(state.native) do
					if not nativeSignalActive(jd, context, signal) or (signal.deadline and now >= signal.deadline) then
						state.native[name] = nil
					end
				end
				publishNative(jd, state, context)
				local radial = state.confirmRadial
				state.confirmRadial = nil
				if radial and jd.focus == radial and radial.hideWhenButtonReleased == nil then
					radial.hideWhenButtonReleased = Joypad.AButton
				end
				for index = #state.pulses, 1, -1 do
					local pulse = state.pulses[index]
					if now >= pulse.at then
						table.remove(state.pulses, index)
						finishRelease(pulse.release)
					end
				end
			end
		end
	end
	for jd, state in pairs(joypadGestures) do
		if not connected[jd] then
			for _, cycle in pairs(state.cycles) do stopGesture(jd, cycle, true) end
			for _, pulse in ipairs(state.pulses) do finishRelease(pulse.release) end
			if not ids[jd.id] then publishNative(jd, state, nil) end
			joypadGestures[jd] = nil
		end
	end
end

local function dispatchFocused(jd, button, directional)
	if not jd or not jd.focus or not isInWorld(jd) then return false end
	refresh()
	if (directional or not DPAD[button]) and gestureButtonPressed(jd, button, true) then return true end
	if jd.isDoingNavigation then return false end
	if isGamePaused() and not jd.activeWhilePaused then return false end
	if type(jd.focus) == "table" and jd.focus.Type == "ISInventoryPage" then
		local action = getAction("inventory", button)
		if action then return dispatchAction(jd, button, action) end
	end
	local action = getAction("ui", button)
	return action ~= nil and dispatchAction(jd, button, action)
end

local vanillaPressButton = JoypadControllerData.onPressButton
function JoypadControllerData:onPressButton(button)
	local jd = self.joypad
	if jd and jd.gtStockReload and jd.gtStockReload.button == button then jd.gtStockReload = nil end
	if dispatchFocused(jd, button) then return end
	return vanillaPressButton(self, button)
end

local function finishNavigation(jd, button)
	if not jd.isDoingNavigation then return false end
	if button == (jd.gtNavigationButton or getButton("uiNavigation")) then
		jd:endNavigation()
		jd.gtNavigationButton = nil
	elseif button == getButton("uiNavigateParent") and jd.currentNavigateUI then
		jd.currentNavigateUI:onJoypadNavigateParent(jd)
	end
	return true
end

local function startStickRadial(jd, button)
	if jd.gtStickButton or button ~= getButton("stickRadial") then return end
	if getSpecificPlayer(jd.player):getVehicle() then return end
	jd.gtStickButton = button
	vanilla.stickDown(Joypad.LStickButton, jd)
end

local function releaseStickRadial(jd, button)
	if not jd.gtStickButton or button ~= jd.gtStickButton then return false end
	jd.gtStickButton = nil
	if jd.player and getSpecificPlayer(jd.player) then
		vanilla.stickReleased(Joypad.LStickButton, jd)
	end
	return true
end

-- D-pad: vanilla calls ISVehicleRegulator.onJoypadPressUp/Down and then ISDPadWheels.onDisplay*
-- only in the world (no UI focus, no drag), so onDisplay* is the hook point for the world
-- layer. Other callers (none in vanilla) still get vanilla.
-- The cruise layer is dispatched before vanilla onPress*: mods that wrap onDisplay* (Smart
-- Radial Menu shows its own menu when the vehicle radial stays empty) must not see these presses.
local pressedDir = nil

local function wrapDir(press, release, display, button, elapsed)
	local vanillaPress = JoypadControllerData[press]
	JoypadControllerData[press] = function(self, ...)
		local jd = self.joypad
		if jd and jd.focus and jd.focus:isVisible() then
			local consumed = dispatchFocused(jd, button, true)
			self:onHoldButton(button, self[elapsed] or 0)
			if consumed then return end
		elseif jd and not jd.isDoingNavigation and jd.focus == nil and isInWorld(jd) then
			if not held[heldKey(jd, button)] and (not isGamePaused() or jd.activeWhilePaused) then
				startStickRadial(jd, button)
			end
			if (not isGamePaused() or jd.activeWhilePaused) and gestureButtonPressed(jd, button, false) then return end
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
		if not isInWorld(jd) then return vanilla[display](jd, ...) end
		local action = worldAction(jd, button)
		if action then dispatchAction(jd, button, action) end
	end

	local vanillaRelease = JoypadControllerData[release]
	JoypadControllerData[release] = function(self, ...)
		local jd = self.joypad
		if jd then
			held[heldKey(jd, button)] = nil
			gestureButtonReleased(jd, button)
			runRelease(jd, button)
			releaseStickRadial(jd, button)
			if finishNavigation(jd, button) then return end
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

wrapDir("onPressUp", "onReleaseUp", "onDisplayUp", Joypad.DPadUp, "dtup")
wrapDir("onPressDown", "onReleaseDown", "onDisplayDown", Joypad.DPadDown, "dtdown")
wrapDir("onPressLeft", "onReleaseLeft", "onDisplayLeft", Joypad.DPadLeft, "dtleft")
wrapDir("onPressRight", "onReleaseRight", "onDisplayRight", Joypad.DPadRight, "dtright")

-- Keep the native cruise shortcut and give a configured event first refusal.
local function adjustCruise(jd, dir, defaultAction, adjust, fallback)
	if pressedDir ~= dir then return fallback(jd) end
	if isPaused() or not drivenVehicle(jd) then return false end
	local context = hasGestures and gestureContext(jd, false)
	local state = joypadGestures[jd]
	local signal = state and state.native.CruiseControl
	if context and context.nativeActions.CruiseControl then
		if not signal or signal.deadline then return false end
	else
		local button = bindingButton(CharacterJoypadButtonBinding.CruiseControl)
		if not button or not button:isDown(jd.id) then return false end
	end
	local action = worldAction(jd, dir)
	if action and action.id ~= defaultAction then return false end
	adjust(jd.controller, jd)
	return true
end

function ISVehicleRegulator.onJoypadPressUp(jd)
	return adjustCruise(jd, Joypad.DPadUp, "vehicleWheel", cruiseFaster, vanilla.regulatorPressUp)
end

function ISVehicleRegulator.onJoypadPressDown(jd)
	return adjustCruise(jd, Joypad.DPadDown, "emoteWheel", cruiseSlower, vanilla.regulatorPressDown)
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
	local action = worldAction(jd, button)
	if gestureButtonPressed(jd, button, false) then
		startStickRadial(jd, button)
		return
	end
	-- Vanilla ignores ordinary buttons while paused; game-speed actions still work.
	if not always and isGamePaused() and not jd.activeWhilePaused then
		if action and action.whilePaused then return dispatchAction(jd, button, action) end
		return vanilla.onPressButtonNoFocus(self, button)
	end
	if action then
		dispatchAction(jd, button, action)
	elseif not always then
		vanilla.onPressButtonNoFocus(self, button)
	end
	startStickRadial(jd, button)
end

-- Stick radial ---------------------------------------------------------------------
-- Vanilla ISJoystickButtonRadialMenu tracks L3 only: onJoypadDown starts the timer,
-- ISButtonPrompt:update calls onRepeatLeftStickButton while L3 is down (displays the radial
-- after 250 ms), onJoypadButtonReleased stops it, the radial closes on L3 release.
-- Here all of it uses the stickRadial button; the press is started above.

function ISJoystickButtonRadialMenu.onJoypadDown(button, jd)
end

function ISJoystickButtonRadialMenu.onJoypadButtonReleased(button, jd)
	if releaseStickRadial(jd, button) then return end
	-- the rest of vanilla for any stick button: ignore aim until the stick is centered
	if button == Joypad.LStickButton or button == Joypad.RStickButton then
		return vanilla.stickReleased(Joypad.RStickButton, jd)
	end
end

function ISJoystickButtonRadialMenu.displayLeft(jd)
	vanilla.stickDisplayLeft(jd)
	if jd.gtStickButton then
		retargetHide(jd, Joypad.LStickButton, jd.gtStickButton)
	end
end

-- Reload (ReloadWeapon binding) ------------------------------------------------------

function ISFirearmRadialMenu.onJoypadButtonReleased(buttonPrompt, button, jd)
	local reload = jd.gtStockReload
	if not reload or reload.button ~= button then return end
	jd.gtStockReload = nil
	local player = getSpecificPlayer(jd.player)
	if player and player:getPrimaryHandItem() == reload.weapon then
		return vanilla.firearmReleased(buttonPrompt, Joypad.RBumper, jd)
	end
end

function ISFirearmRadialMenu:display()
	vanilla.firearmDisplay(self)
	local jd = JoypadState.players[self.playerNum + 1]
	local reload = jd and (jd.gtNativeReload or jd.gtStockReload)
	local button = reload and reload.button or bindingButton(CharacterJoypadButtonBinding.ReloadWeapon)
	if jd and button then retargetHide(jd, Joypad.RBumper, button) end
end

-- Advance only a reload started by this press, even if layers or aim state change.
function ISButtonPrompt:update()
	if not self.player then return end
	local jd = JoypadState.players[self.player + 1]
	if not jd or not jd.isActive then return end
	local reload = jd.gtNativeReload or jd.gtStockReload
	if reload and reload.button:isDown(jd.id) then
		local player = getSpecificPlayer(self.player)
		if player and player:getPrimaryHandItem() == reload.weapon then
			ISFirearmRadialMenu.onRepeatRBumper(self)
		elseif jd.gtNativeReload then
			jd.gtNativeReload = nil
		else
			jd.gtStockReload = nil
		end
	end
	local stick = jd.gtStickButton
	if stick and stick:isDown(jd.id) then
		ISJoystickButtonRadialMenu.onRepeatLeftStickButton(jd)
	end
end

-- UI navigation, cruise toggle ---------------------------------------------------------
-- Vanilla onHoldButton: RB held in a UI starts navigation (it handles nothing else);
-- onReleaseButton: RB release ends it, LB release goes to the parent panel, X release
-- toggles cruise control.

function JoypadControllerData:onHoldButton(button, time)
	if button == getButton("uiNavigation") then
		local jd = self.joypad
		if hasGestures and jd and jd.focus and isInWorld(jd) then
			local context = gestureContext(jd, true)
			local key = context.buttons[button]
			local group = key and context.groups[key]
			if group and group.hold then return end
		end
		local wasNavigating = jd and jd.isDoingNavigation
		vanilla.onHoldButton(self, Joypad.RBumper, time)
		if jd and jd.isDoingNavigation and not wasNavigating then
			jd.gtNavigationButton = button
		end
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

function ISVehicleRegulator.onJoypadReleaseX(jd, synthetic)
	if not synthetic and releasing ~= nil then
		local state = joypadGestures[jd]
		if releasing ~= bindingButton(CharacterJoypadButtonBinding.CruiseControl)
				or (state and state.native.CruiseControl) then return end
	end
	cruiseReleased = true
	return vanilla.regulatorReleaseX(jd)
end

function JoypadControllerData:onReleaseButton(button)
	local jd = self.joypad
	if jd and not DPAD[button] then
		gestureButtonReleased(jd, button)
		runRelease(jd, button)
	end
	if jd and jd.isDoingNavigation then
		-- Direction releases were handled by the D-pad callback.
		if not DPAD[button] then finishNavigation(jd, button) end
		releaseStickRadial(jd, button)
		return
	end

	releasing = button
	cruiseReleased = false
	local ok, err = pcall(vanilla.onReleaseButton, self, button)
	releasing = nil
	if not ok then error(err, 0) end

	if not jd or not jd.player then return end
	-- vanilla toggles cruise control only on X release
	local state = joypadGestures[jd]
	if not cruiseReleased and button == bindingButton(CharacterJoypadButtonBinding.CruiseControl)
			and not (state and state.native.CruiseControl) and ISVehicleRegulator.xPressed[jd.id] then
		vanilla.regulatorReleaseX(jd)
	end
	-- Vanilla forwards only L3/R3 releases to the stick radial.
	releaseStickRadial(jd, button)
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
	local focus = jd.focus
	-- The map takes the sticks (MapControls pans with the gamepad stick): without the world
	-- layers a stick bound there to an analog action (steer, move) falls back to the plain stick.
	-- With the vehicle layer on, the map didn't pan. Nothing to do in the world with the map open
	-- (movement is blocked, ISWorldMap.ShowWorldMap). Other windows keep the world layers: Steam
	-- world actions (horn, light...) work with them open.
	local onMap = type(focus) == "table" and MAP_UI[focus.Type]
	if not onMap then
		local vehicle = playerObj:getVehicle()
		if vehicle and (vehicle:isDriver(playerObj) or not onFootPassenger) then
			table.insert(layers, "vehicle")
		else
			table.insert(layers, "onfoot")
		end
		-- Vanilla "aiming" is any combat stance, melee and unarmed too. The layer (gyro aim) is for
		-- firearms only: in melee there is no reticle, so the gyro offset (AnalogInput) silently
		-- turned the player and the stick no longer matched the facing.
		if playerObj:isAiming() and playerObj:isRangedWeaponEquipped() then
			table.insert(layers, "aiming")
		end
	end
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
-- aiming pans too. The action stops when a higher layer takes its button or aiming ends.
local followed = {} -- ["<joypad>:<action>"] = true while the button holds the action

local function followButtons()
	for _, action in ipairs(Bindings.actions) do
		if action.followsButton and action.run and action.release then
			local button = getButton(action.id)
			for i = 1, getMaxActivePlayers() do
				local jd = JoypadState.players[i]
				if jd and jd.id then
					local key = tostring(jd.id) .. ":" .. action.id
					local down = button ~= nil and jd.focus == nil and button:isDown(jd.id) and isInWorld(jd)
						and (not isGamePaused() or jd.activeWhilePaused) and worldAction(jd, button) == action
					if down and hasGestures then
						local context = gestureContext(jd, false)
						local inputKey = BindingEvents.inputKey(button)
						local group = context.groups[inputKey]
						local state = joypadGestures[jd]
						local cycle = state and state.cycles[inputKey]
						local heldByNative = cycle and cycle.down and cycle.fired and cycle.fired.action.native
						down = not (heldByNative or (group and group.managed))
					end
					if (not not down) ~= (followed[key] == true) then
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
	refresh()
	local ok, err = pcall(tickGestures)
	if not ok then log("ERROR: controller events: " .. tostring(err)) end
	ok, err = pcall(followButtons)
	if not ok then log("ERROR: held buttons: " .. tostring(err)) end
	steamTick()
end

-- Every frame, also in the main menu (registers the manifest early) and while paused.
Events.OnRenderTick.Add(tick)

Events.OnGameStart.Add(refresh)
