-- Options in Settings > Mods (PZAPI.ModOptions).
--
-- The mod's settings live in ~/Zomboid/GamepadTweaks.properties (Java Settings, re-read on
-- the fly), so this page is a view of that file, not of ModOptions.ini: the values are read
-- from the file every time vanilla loads the mod options (MainOptions builds its Mods page),
-- and "Apply" writes back only what the player changed (GamepadTweaks_setSetting), so
-- hand-tuned values outside a slider's range survive. Changes apply at once, no reload.
--
-- Only features can be turned off or tuned (steering, throttle, triggers, press actions, map,
-- Steam Input, vibration). Bug fixes always run: UI presses leaking to the character, fliers,
-- cruise control / reload following their bindings. Button rebinding is in
-- Options -> Controller (ControllerEditor.lua); advanced values only in the file.

require "PZAPI/ModOptions"

local MOD_ID = "GamepadTweaks"

-- key: settings key (also the option id); requires: keys of tick boxes that must be on.
local SPEC = {
	{ title = "steering" },
	{ key = "steering.enabled", tick = true },
	{ key = "steering.rawStick", tick = true, requires = { "steering.enabled" } },
	{ key = "steering.recenter", tick = true, requires = { "steering.enabled", "steering.rawStick" } },
	{ key = "steering.recenterZone", min = 0.02, max = 0.2, step = 0.01, default = 0.08,
		requires = { "steering.enabled", "steering.rawStick", "steering.recenter" } },
	{ key = "steering.noiseDeadZone", min = 0, max = 0.2, step = 0.005, default = 0,
		requires = { "steering.enabled", "steering.rawStick" } },
	{ key = "steering.scaleToSpeedClamp", tick = true, requires = { "steering.enabled" } },
	{ key = "steering.lowSpeedExponent", min = 0.5, max = 3, step = 0.1, default = 1.0, requires = { "steering.enabled" } },
	{ key = "steering.highSpeedExponent", min = 0.5, max = 4, step = 0.1, default = 2.0, requires = { "steering.enabled" } },
	{ key = "steering.highSpeedKmh", min = 10, max = 200, step = 5, default = 80, requires = { "steering.enabled" } },
	{ key = "steering.constantRateWheel", tick = true, requires = { "steering.enabled" } },
	{ key = "steering.turnRate", min = 0.005, max = 0.2, step = 0.005, default = 0.05,
		requires = { "steering.enabled", "steering.constantRateWheel" } },
	{ key = "steering.highSpeedTurnRate", min = 0.005, max = 0.2, step = 0.005, default = 0.03,
		requires = { "steering.enabled", "steering.constantRateWheel" } },
	{ key = "steering.returnRate", min = 0.005, max = 0.2, step = 0.005, default = 0.06,
		requires = { "steering.enabled", "steering.constantRateWheel" } },

	{ title = "throttle" },
	{ key = "throttle.analog", tick = true },
	{ key = "throttle.deadZone", min = 0, max = 0.1, step = 0.005, default = 0.02, requires = { "throttle.analog" } },
	{ key = "throttle.curve", min = 0.5, max = 3, step = 0.1, default = 1.5, requires = { "throttle.analog" } },
	{ key = "throttle.dragExponent", min = 1, max = 4, step = 0.1, default = 2.0, requires = { "throttle.analog" } },
	{ key = "throttle.engineBraking", min = 0, max = 3, step = 0.1, default = 1.0, requires = { "throttle.analog" } },
	{ key = "throttle.brakeHold", tick = true },

	{ title = "buttons" },
	{ key = "triggers.noDeadZone", tick = true },
	{ key = "actions.crouchOnPress", tick = true },
	{ key = "actions.sprintOnPress", tick = true },
	{ key = "actions.vehicleOnlyByPrompt", tick = true },

	{ title = "map" },
	{ key = "map.smooth", tick = true },
	{ key = "map.panSpeed", min = 0.1, max = 5, step = 0.1, default = 1.0, requires = { "map.smooth" } },
	{ key = "map.panExponent", min = 1, max = 3, step = 0.1, default = 2.0, requires = { "map.smooth" } },
	{ key = "map.zoomSpeed", min = 0.5, max = 10, step = 0.5, default = 3.0, requires = { "map.smooth" } },

	{ title = "steamInput" },
	{ key = "steamInput.enabled", tick = true },
	{ key = "steamInput.passengerLayer", combo = { "vehicle", "onfoot" }, requires = { "steamInput.enabled" } },

	{ title = "rumble" },
	{ key = "rumble.enabled", tick = true, requires = { "steamInput.enabled" } },
	{ key = "rumble.strength", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ button = "rumble_test", run = function()
		if GamepadTweaks_rumbleTest then GamepadTweaks_rumbleTest() end
	end },
	{ key = "rumble.triggers", tick = true, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.triggerGain", min = 0, max = 2, step = 0.1, default = 0.6, requires = { "steamInput.enabled", "rumble.enabled", "rumble.triggers" } },
	{ key = "rumble.shot", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.hit", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.damage", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.bump", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.fall", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.vehicle", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.suspension", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.road", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.window", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.tool", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.thump", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.thunder", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.scare", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
	{ key = "rumble.heartbeat", min = 0, max = 2, step = 0.1, default = 1.0, requires = { "steamInput.enabled", "rumble.enabled" } },
}

local function textKey(key)
	return "UI_GamepadTweaks_opt_" .. key:gsub("%.", "_")
end

local function readSetting(key)
	if not GamepadTweaks_getSetting then return nil end
	local ok, v = pcall(GamepadTweaks_getSetting, key)
	return ok and v or nil
end

-- Same parsing as Settings.java (Boolean.parseBoolean, Float.parseFloat).
local function fileValue(spec)
	local raw = readSetting(spec.key)
	if raw then raw = raw:match("^%s*(.-)%s*$") end
	if spec.tick then
		if raw == nil then return true end
		return raw:lower() == "true"
	elseif spec.combo then
		for i, v in ipairs(spec.combo) do
			if raw == v then return i end
		end
		return 1
	end
	return tonumber(raw) or spec.default
end

-- As the slider stores it (ISSliderPanel:setCurrentValue rounds to the step and clamps).
local function toSlider(spec, v)
	local stepmod = 1 / spec.step
	v = math.floor(v * stepmod + 0.5) / stepmod
	return math.max(spec.min, math.min(spec.max, v))
end

local function changed(spec, v, old)
	if spec.tick or spec.combo then return v ~= old end
	return math.abs(v - old) > spec.step / 2
end

local function format(spec, v)
	if spec.tick then return tostring(v) end
	if spec.combo then return spec.combo[v] end
	local s = string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

local options = PZAPI.ModOptions:create(MOD_ID, "UI_GamepadTweaks_Options")
options:addDescription("UI_GamepadTweaks_Options_desc")

local loaded = {} -- [key] = value read from the file, as the option holds it
local current = {} -- [key] = tick box state on the page (before Apply)

local function updateEnabled()
	for _, spec in ipairs(SPEC) do
		if spec.requires then
			local enabled = true
			for _, k in ipairs(spec.requires) do
				if current[k] == false then enabled = false end
			end
			spec.option:setEnabled(enabled)
		end
	end
end

for _, spec in ipairs(SPEC) do
	if spec.title then
		options:addTitle("UI_GamepadTweaks_opt_title_" .. spec.title)
	elseif spec.button then
		-- an action, not a setting (no key: not read or written)
		local name = "UI_GamepadTweaks_opt_" .. spec.button
		local tooltip = getTextOrNull(name .. "_tooltip") and name .. "_tooltip" or nil
		spec.option = options:addButton(spec.button, name, tooltip, spec.run)
	else
		local name = textKey(spec.key)
		local tooltip = getTextOrNull(name .. "_tooltip") and name .. "_tooltip" or nil
		if spec.tick then
			spec.option = options:addTickBox(spec.key, name, true, tooltip)
			spec.option.onChange = function(_, value)
				current[spec.key] = value
				updateEnabled()
			end
		elseif spec.combo then
			spec.option = options:addComboBox(spec.key, name, tooltip)
			for _, v in ipairs(spec.combo) do
				spec.option:addItem(name .. "_" .. v)
			end
		else
			spec.option = options:addSlider(spec.key, name, spec.min, spec.max, spec.step, spec.default, tooltip)
		end
	end
end

-- Puts the file's values into the options (their element, if the page exists, gets them
-- from MainOptions' toUI).
local function readFile()
	for _, spec in ipairs(SPEC) do
		if spec.key then
			local v = fileValue(spec)
			if not spec.tick and not spec.combo then v = toSlider(spec, v) end
			loaded[spec.key] = v
			if spec.tick then
				spec.option.value = v
				current[spec.key] = v
			elseif spec.combo then
				spec.option.selected = v
			else
				spec.option.value = v
			end
		end
	end
	updateEnabled()
end

-- Vanilla load() fills the options from ModOptions.ini (also our stale copies); the file wins.
local vanillaLoad = PZAPI.ModOptions.load
function PZAPI.ModOptions:load()
	vanillaLoad(self)
	readFile()
end

-- Called by MainOptions:apply after the options took the page's values.
function options:apply()
	if not GamepadTweaks_setSetting then return end
	for _, spec in ipairs(SPEC) do
		if spec.key then
			local v = spec.combo and spec.option.selected or spec.option.value
			if changed(spec, v, loaded[spec.key]) then
				if GamepadTweaks_setSetting(spec.key, format(spec, v)) then
					loaded[spec.key] = v
				end
			end
		end
	end
	for _, spec in ipairs(SPEC) do
		if spec.tick then current[spec.key] = spec.option.value end
	end
	updateEnabled()
end

readFile()
