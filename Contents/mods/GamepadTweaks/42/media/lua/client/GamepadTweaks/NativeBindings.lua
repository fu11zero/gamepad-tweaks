-- The stock XML bindings remain the base preset. Overrides are keyed by action and
-- context in GamepadTweaks.properties and never mutate the enum or the XML.
require "ISUI/ISButtonPrompt"

GamepadTweaks = GamepadTweaks or {}
local Native = {}
GamepadTweaks.NativeBindings = Native

local function layers(...)
	local set = {}
	for _, layer in ipairs({ ... }) do set[layer] = true end
	return set
end

local foot = layers("world", "onfoot", "aiming")
local combat = layers("world", "onfoot", "vehicle", "aiming")
local general = layers("world", "onfoot", "vehicle")
local vehicle = layers("world", "vehicle")
local panels = layers("ui", "inventory")
local inventory = layers("inventory")

-- A pulse lets vanilla's TimedInputHandler detect both the press and the ensuing
-- click, even for gestures whose physical button was held longer than 400 ms.
local descriptions = {
	Aim = { combat, "character" }, PrecisionAim = { combat, "character" },
	Attack = { combat, "character" }, Melee = { foot, "character" },
	ManualFloorAtk = { foot, "character" }, Run = { foot, "character" },
	Crouch = { foot, "character", pulse = true }, Sprint = { foot, "character", prompt = true },
	CancelAction = { general, "character", prompt = true },
	Interact = { general, "character", prompt = true },
	ClimbThrough = { foot, "character", prompt = true },
	SmashWindow = { foot, "character", prompt = true },
	InteractOptions = { foot, "character", prompt = true },
	Inventory = { general, "inventory", prompt = true },
	ReloadWeapon = { combat, "hands", prompt = true },
	RackFirearm = { combat, "hands", pulse = true },
	ZoomIn = { general, "windows" }, ZoomOut = { general, "windows" },
	Brakes = { vehicle, "vehicle", prompt = true },
	CruiseControl = { vehicle, "vehicle", prompt = true },
	ClosePanel = { panels, "windows", ui = Joypad.BButton },
	CycleTabsLeft = { layers("ui"), "windows", ui = Joypad.LBumper },
	CycleTabsRight = { layers("ui"), "windows", ui = Joypad.RBumper },
	CycleInventory = { inventory, "inventory", ui = Joypad.LBumper },
	CycleLoot = { inventory, "inventory", ui = Joypad.RBumper },
	TransferItem = { inventory, "inventory", ui = Joypad.XButton },
}

function Native.register(add)
	if not GamepadTweaks_publishNativeBindings then return end
	for _, binding in ipairs(CharacterJoypadButtonBinding.allBindings()) do
		local name = tostring(binding)
		local data = descriptions[name]
		if data then
			add({
				id = "native_" .. name, native = binding, name = name, layer = "world",
				label = "UI_optionscreen_gamepad_CharacterJoypadButtonBinding_name_" .. name,
				category = data[2], layers = data[1], pulse = data.pulse, prompt = data.prompt,
				uiButton = data.ui,
			})
		end
	end
end

function Native.rawInput(action, layer)
	if action.name == "ClosePanel" and layer == "inventory" then return Joypad.YButton end
	local button = action.uiButton or action.native:getJoypadButton()
	if button then return button end
	local trigger = action.native:getJoypadAxis1d()
	local stick = action.native:getJoypadAxis2d()
	local minimum = action.native:getAxisMinThreshold()
	if trigger then return trigger, (minimum + 1) * 50 end
	if stick then return stick, minimum * 100 end
end

function Native.isPulse(action)
	local core = getCore()
	return action.pulse or (action.name == "Sprint" and core:isToggleToSprint())
		or (action.name == "Run" and core:isToggleToRun())
end

-- Focused panels receive their own stock command, without sending a physical
-- button press back through the gameplay dispatcher.
function Native.runUI(action, jd)
	local focus = jd.focus
	if action.name == "ClosePanel" and focus.Type == "ISInventoryPage" then
		focus:onJoypadDown(Joypad.YButton, jd)
	else
		focus:onJoypadDown(action.uiButton, jd)
	end
end

local setter = ISButtonPrompt.setButtonBindingPrompt
local clear = ISButtonPrompt.clearButtonBindings

function ISButtonPrompt:setButtonBindingPrompt(binding, label, func, ...)
	self.gtByBinding = self.gtByBinding or {}
	local value = { label = label, run = func, args = { ... } }
	self.gtByBinding[tostring(binding)] = value
	if func and binding == CharacterJoypadButtonBinding.ReloadWeapon then
		-- Only the prompt that actually handled this press can arm the stock timer.
		value.stock = function()
			local jd = self.player and JoypadState.players[self.player + 1]
			local button = binding:getJoypadButton()
			local player = getSpecificPlayer(self.player)
			if jd and button and player and ISFirearmRadialMenu.checkWeapon(player) then
				jd.gtStockReload = { button = button, weapon = player:getPrimaryHandItem() }
				func(self)
			end
		end
	end
	return setter(self, binding, label, value.stock or func, ...)
end

function ISButtonPrompt:clearButtonBindings()
	self.gtByBinding = nil
	return clear(self)
end

local SLOTS = { "a", "b", "x", "y", "lb", "rb" }

-- Some stock evaluators only run for a particular physical button. Invoke
-- them for the action while preserving the visible stock prompt slots.
function Native.evaluatePrompt(prompt, method, ...)
	local saved = {}
	for _, key in ipairs(SLOTS) do
		saved[key] = { prompt[key .. "Prompt"], prompt[key .. "Func"], prompt[key .. "Params"] }
	end
	local ok, err = pcall(method, prompt, ...)
	for _, key in ipairs(SLOTS) do
		prompt[key .. "Prompt"], prompt[key .. "Func"], prompt[key .. "Params"] = unpack(saved[key], 1, 3)
	end
	if not ok then print("[GamepadTweaks] ERROR: native prompt: " .. tostring(err)) end
end

-- Vanilla chooses the handler and its arguments based on the scene. Collect by
-- action before the physical-button slots can overwrite one another.
function Native.collect(jd, context, vanillaUpdate)
	local prompt = getButtonPrompts(jd.player)
	if not prompt then return vanillaUpdate(jd) end
	vanillaUpdate(jd)
	local player = getSpecificPlayer(jd.player)
	local dir = player:getDir()
	local function wants(name)
		return context.nativeActions[name] or context.promptChords[name]
	end
	if wants("InteractOptions") or wants("CruiseControl") then
		Native.evaluatePrompt(prompt, prompt.getBestXButtonAction, dir)
	end
	if wants("Inventory") then Native.evaluatePrompt(prompt, prompt.getBestYButtonAction, dir) end
	if wants("ReloadWeapon") then Native.evaluatePrompt(prompt, ISFirearmRadialMenu.getBestRBButtonAction) end
	local values = prompt.gtByBinding or {}
	jd.gtNativePrompts, jd.gtNativePromptContext = values, context

	-- Restore the slots touched during stock evaluation in a predictable order.
	-- Only move/suppress affected actions. Other stock prompts keep their result.
	for button in pairs(context.promptButtons) do
		prompt:setButtonPrompt(button, nil, nil)
	end
	for _, action in ipairs(context.catalog) do
		local name = action.name
		local value = action.prompt and values[name]
		local raw = action.prompt and action.native:getJoypadButton()
		if value and raw and context.promptButtons[raw] then
			local key = context.buttons[raw]
			local group = key and context.groups[key]
			local managed = context.nativeActions[name] ~= nil
			local inherited
			for _, binding in ipairs(group and group.fallback or {}) do
				if binding.action == action then inherited = true end
			end
			if not managed or inherited then
				local fire
				if not managed and value.run then
					fire = value.stock or function() value.run(prompt, unpack(value.args, 1, 4)) end
				end
				prompt:setButtonPrompt(raw, value.label, fire)
			end
		end
	end
	for button in pairs(context.promptButtons) do
		local key = context.buttons[button]
		local group = key and context.groups[key]
		for _, event in ipairs({ "press", "hold", "double" }) do
			local binding = group and group[event]
			local value = binding and not binding.inherited and values[binding.action.name]
			if value then
				prompt:setButtonPrompt(button, value.label, nil)
				break
			end
		end
	end
end

function Native.runPrompt(binding, jd, down, releaseReload)
	local action = binding.action
	local value = jd.gtNativePrompts and jd.gtNativePrompts[action.name]
	if not value or not value.run then return end
	local prompt = getButtonPrompts(jd.player)
	if action.name == "ReloadWeapon" then
		local player = getSpecificPlayer(jd.player)
		if not ISFirearmRadialMenu.checkWeapon(player) then return end
		value.run(prompt)
		if down and binding.event == "press" and not binding.threshold then
			local reload = { button = binding.input, weapon = player:getPrimaryHandItem() }
			jd.gtNativeReload = reload
			return function(cancel)
				if jd.gtNativeReload ~= reload then return end
				jd.gtNativeReload = nil
				if not cancel and player:getPrimaryHandItem() == reload.weapon then
					releaseReload(prompt, Joypad.RBumper, jd)
				end
			end
		end
		releaseReload(prompt, Joypad.RBumper, jd)
	elseif action.name == "CruiseControl" then
		value.run(prompt, jd)
		local function release(cancel)
			if cancel then
				ISVehicleRegulator.xPressed[jd.id] = nil
			else
				ISVehicleRegulator.onJoypadReleaseX(jd, true)
			end
		end
		if down then return release end
		release()
	else
		value.run(prompt, unpack(value.args, 1, 4))
	end
end

return Native
