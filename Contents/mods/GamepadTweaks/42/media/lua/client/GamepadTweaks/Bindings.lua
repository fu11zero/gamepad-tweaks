-- Rebindable gamepad actions for what vanilla hardcodes to buttons.
--
-- Vanilla JoyPadSetup.lua calls these directly, past the binding system
-- (CharacterJoypadButtonBinding, Options -> Controller):
-- - JoypadControllerData:onPressUp/Down/Left/Right -> ISDPadWheels.onDisplayUp/Down/Left/Right
--   (vehicle/animal, emote, weapon/light, zones/rooms editor/survival guide wheels);
-- - JoypadControllerData:onPressButtonNoFocus: Back -> command wheel, Start -> pause.
-- So these buttons can't be used for anything else, and the wheels can't be moved.
-- The vanilla binding list is a Java enum (fixed when the class loads, saved by name in
-- InputBindings/*.xml), so the actions live here instead: bind.<action>=<button> in
-- ~/Zomboid/GamepadTweaks.properties (re-read on the fly). By default every action is on
-- its vanilla button, so nothing changes until the player rebinds it. "none" frees the button.
-- Without the Java part (jar not approved) the defaults are used.

require "ISUI/Gamepad/JoyPadSetup"
require "ISUI/ISDPadWheels"

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

-- Vanilla handlers, called by the actions on their own buttons.
local vanilla = {
	onDisplayUp = ISDPadWheels.onDisplayUp,
	onDisplayDown = ISDPadWheels.onDisplayDown,
	onDisplayLeft = ISDPadWheels.onDisplayLeft,
	onDisplayRight = ISDPadWheels.onDisplayRight,
	onPressButtonNoFocus = JoypadControllerData.onPressButtonNoFocus,
}

-- id: key in the settings file; button: the vanilla button (default and what the vanilla
-- code assumes, e.g. for setHideWhenButtonReleased); run(controller, joypadData).
Bindings.actions = {
	{ id = "vehicleWheel", button = Joypad.DPadUp,
		run = function(c, jd) vanilla.onDisplayUp(jd) end },
	{ id = "emoteWheel", button = Joypad.DPadDown,
		run = function(c, jd) vanilla.onDisplayDown(jd) end },
	{ id = "equipWheel", button = Joypad.DPadLeft,
		run = function(c, jd) vanilla.onDisplayLeft(jd) end },
	{ id = "extraWheel", button = Joypad.DPadRight,
		run = function(c, jd) vanilla.onDisplayRight(jd) end },
	{ id = "commandWheel", button = Joypad.Back,
		run = function(c, jd) vanilla.onPressButtonNoFocus(c, Joypad.Back) end },
	{ id = "pause", button = Joypad.Start,
		run = function(c, jd) vanilla.onPressButtonNoFocus(c, Joypad.Start) end },
}

-- Settings ---------------------------------------------------------------------

local buttonByName = {}
for _, b in ipairs(JoypadButton.getButtons()) do
	buttonByName[tostring(b)] = b
end

local actionByButton = {}
local loadedVersion = nil

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

-- Returns the button set for the action (false = none), or nil when it isn't set.
local function readBinding(action)
	local value = readSetting("bind." .. action.id)
	if not value then return nil end
	value = value:match("^%s*(.-)%s*$")
	if value == "none" or value == "" then return false end
	if buttonByName[value] then return buttonByName[value] end
	log("WARN: bind." .. action.id .. "=" .. value .. " is not a button, using " .. tostring(action.button))
	return nil
end

-- An action set to a button takes it from the action that has it by default
-- (bind.commandWheel=DPadDown alone moves the emote wheel off the D-pad).
function Bindings.reload()
	actionByButton = {}
	local changed = {}
	local function assign(action, button, explicit)
		action.bound = nil
		if button then
			local other = actionByButton[button]
			if other then
				if explicit then
					log("WARN: " .. action.id .. " and " .. other.id .. " are both set to " .. tostring(button) .. ", using " .. other.id)
				else
					table.insert(changed, action.id .. "=none (" .. tostring(button) .. " taken by " .. other.id .. ")")
				end
				return
			end
			actionByButton[button] = action
			action.bound = button
		end
		if button ~= action.button then
			table.insert(changed, action.id .. "=" .. tostring(button or "none"))
		end
	end
	local defaults = {}
	for _, action in ipairs(Bindings.actions) do
		local button = readBinding(action)
		if button == nil then
			table.insert(defaults, action)
		else
			assign(action, button, true)
		end
	end
	for _, action in ipairs(defaults) do
		assign(action, action.button, false)
	end
	log("button actions: " .. (#changed > 0 and table.concat(changed, " ") or "vanilla"))
end

local function refresh()
	local v = settingsVersion()
	if v ~= loadedVersion then
		loadedVersion = v
		Bindings.reload()
	end
end

function Bindings.getAction(button)
	refresh()
	return actionByButton[button]
end

-- Dispatch ---------------------------------------------------------------------

-- D-pad presses repeat while held (JoypadControllerData:update); an action fires once
-- per press. The wheels take the focus, so vanilla never saw the repeats.
local held = {}

local function heldKey(jd, button)
	return tostring(jd.id) .. ":" .. tostring(button)
end

local function run(action, jd, button)
	local ok, err = pcall(action.run, jd.controller, jd)
	if not ok then
		log("ERROR: " .. action.id .. " failed: " .. tostring(err))
		return
	end
	-- Vanilla wheels close and pick the slice when their own button is released
	-- (ISRadialMenu:setHideWhenButtonReleased); make that the button that opened it.
	-- The back button wheel is created once (getPlayerBackButtonWheel) and sets it only
	-- in new(), so gtVanillaHide remembers the vanilla button for the next opening.
	local focus = jd.focus
	if type(focus) == "table" and (focus.hideWhenButtonReleased == action.button
			or focus.gtVanillaHide == action.button) then
		focus.gtVanillaHide = action.button
		focus.hideWhenButtonReleased = button
	end
end

-- Runs the action bound to button. Returns false when there is none.
local function dispatch(jd, button)
	local action = Bindings.getAction(button)
	if not action then return false end
	local key = heldKey(jd, button)
	if held[key] then return true end
	if DPAD[button] then held[key] = true end
	run(action, jd, button)
	return true
end

-- D-pad: vanilla calls ISDPadWheels.onDisplay* only in the world (no UI focus, no drag,
-- cruise control speed X + up/down didn't take it), so those calls are the hook points.
-- Other callers of onDisplay* (none in vanilla) still get the vanilla wheel.
local pressedDir = nil

local function wrapDir(press, release, display, button)
	local vanillaPress = JoypadControllerData[press]
	JoypadControllerData[press] = function(self, ...)
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

-- Same checks as vanilla onPressButtonNoFocus before it gets to Back/Start:
-- a player in the world, no main menu / terms of service, nothing dragged.
local function isInWorld(jd)
	if not jd or not jd.player or not getSpecificPlayer(jd.player) then return false end
	if ISTermsOfServiceUI and ISTermsOfServiceUI.instance and ISTermsOfServiceUI.instance:isReallyVisible() then return false end
	if MainScreen.instance and MainScreen.instance:isReallyVisible() then return false end
	if getCell() and getCell():getDrag(jd.player) then return false end
	return true
end

-- Buttons: the world (no UI focus) part of vanilla onPressButton. Back and Start open the
-- wheel / pause only through their actions, so a freed Back/Start does nothing here and
-- is left to the regular bindings. Other buttons keep vanilla (button prompts, L3/R3 radial)
-- unless an action is bound to them. The D-pad comes through onPressUp/... above.
function JoypadControllerData:onPressButtonNoFocus(button)
	local jd = self.joypad
	if DPAD[button] or not isInWorld(jd) then
		return vanilla.onPressButtonNoFocus(self, button)
	end
	local always = button == Joypad.Back or button == Joypad.Start
	-- vanilla ignores other buttons while paused
	if not always and isGamePaused() and not jd.activeWhilePaused then
		return vanilla.onPressButtonNoFocus(self, button)
	end
	if dispatch(jd, button) or always then
		return
	end
	return vanilla.onPressButtonNoFocus(self, button)
end

Events.OnGameStart.Add(refresh)
