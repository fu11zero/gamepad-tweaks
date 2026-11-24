-- Run from the repository root: lua tools/test_controller_bindings.lua
-- Exercise the real resolver with a deterministic clock, physical input, and a prompt mock.
local root = "Contents/mods/GamepadTweaks/42/media/lua/client/"
package.path = root .. "?.lua;" .. package.path
unpack = unpack or table.unpack
local function noop() end
for _, dependency in ipairs({
	"ISUI/Gamepad/JoyPadSetup", "gamepadBinding", "ISUI/ISDPadWheels", "ISUI/ISButtonPrompt",
	"ISUI/ISFirearmRadialMenu", "ISUI/ISJoystickButtonRadialMenu", "Vehicles/ISUI/ISVehicleRegulator",
}) do package.preload[dependency] = noop end

local physical = {}
local function input(name)
	return setmetatable({
		isDown = function(self, id) return physical[id][self] == true end,
		getValue = function(self, id) return physical[id][self] or -1 end,
		getLength = function(self, id) return physical[id][self] or 0 end,
	}, { __tostring = function() return name end })
end

Joypad = {}
local buttons = {}
for _, pair in ipairs({
	{ "AButton", "A" }, { "BButton", "B" }, { "XButton", "X" }, { "YButton", "Y" },
	{ "LStickButton", "LeftStick" }, { "RStickButton", "RightStick" },
	{ "LBumper", "LeftBump" }, { "RBumper", "RightBump" }, { "Back", "Back" }, { "Start", "Start" },
	{ "DPadUp", "DPadUp" }, { "DPadDown", "DPadDown" }, { "DPadLeft", "DPadLeft" }, { "DPadRight", "DPadRight" },
}) do
	Joypad[pair[1]] = input(pair[2])
	table.insert(buttons, Joypad[pair[1]])
end
JoypadButton = { getButtons = function() return buttons end }
JoypadAxis1d = { LeftTrigger = input("LeftTrigger"), RightTrigger = input("RightTrigger") }
JoypadAxis2d = { LeftStick = input("LeftStick"), RightStick = input("RightStick") }

local clock, tick = 0
local settings, version, published = {}, 0, {}
function GamepadTweaks_getSetting(key) return settings[key] end
function GamepadTweaks_setSetting(key, value)
	settings[key], version = value, version + 1
	return true
end
function GamepadTweaks_settingsVersion() return version end
function GamepadTweaks_publishNativeBindings(id, spec)
	published[id] = {}
	for action, value in spec:gmatch("(%w+)=(%d)") do published[id][action] = value == "1" end
end

local bindingList = {}
CharacterJoypadButtonBinding = { allBindings = function() return bindingList end }
local function baseBinding(name, button, trigger, minimum)
	local binding = setmetatable({
		getJoypadButton = function() return button end,
		getJoypadAxis1d = function() return trigger end,
		getJoypadAxis2d = noop,
		getAxisMinThreshold = function() return minimum or 0 end,
		getAxisMaxThreshold = function() return 2 end,
	}, { __tostring = function() return name end })
	CharacterJoypadButtonBinding[name] = binding
	table.insert(bindingList, binding)
end
baseBinding("Interact", Joypad.AButton)
baseBinding("Crouch", Joypad.LStickButton)
baseBinding("CancelAction", Joypad.BButton)
baseBinding("Inventory", Joypad.YButton)
baseBinding("Aim")
baseBinding("ReloadWeapon", Joypad.RBumper)
baseBinding("Attack", nil, JoypadAxis1d.RightTrigger, 0.93)
baseBinding("Brakes", Joypad.BButton)
baseBinding("CruiseControl", Joypad.XButton)
baseBinding("TransferItem", Joypad.XButton)
baseBinding("CycleLoot", Joypad.RBumper)

local players, prompts, queue = {}, {}, {}
local reloadTimer = {}
local vehicle = { isDriver = function() return true end }
local function record(prompt, name) table.insert(queue, prompt.player .. ":" .. name) end

ISButtonPrompt = {}
function ISButtonPrompt:setButtonPrompt(button, label, run)
	if button then self.slots[button] = label and { label = label, run = run } or nil end
end
function ISButtonPrompt:setButtonBindingPrompt(action, label, run, name)
	self:setButtonPrompt(action:getJoypadButton(), label, run and function() run(self, name) end)
end
function ISButtonPrompt:clearButtonBindings() self.slots = {} end
function ISButtonPrompt:getBestButtonBindingAction(action)
	if action == CharacterJoypadButtonBinding.Interact then
		self:setButtonBindingPrompt(action, "Interact", record, "interact")
	end
	if action == CharacterJoypadButtonBinding.CancelAction then
		self:setButtonBindingPrompt(action, "Cancel", record, "cancel")
	end
end
function ISButtonPrompt:getBestYButtonAction()
	self:setButtonBindingPrompt(CharacterJoypadButtonBinding.Inventory, "Inventory", record, "inventory")
end
function ISButtonPrompt:getBestXButtonAction() end
function updateJoypadFocus(jd)
	local prompt = prompts[jd.player]
	prompt:clearButtonBindings()
	for _, action in ipairs(bindingList) do prompt:getBestButtonBindingAction(action) end
	prompt:getBestYButtonAction()
	ISFirearmRadialMenu.getBestRBButtonAction(prompt)
end

JoypadControllerData = {
	onPressButton = function(self, button)
		if self.joypad.focus then
			self.joypad.focus:onJoypadDown(button)
		else
			self:onPressButtonNoFocus(button)
		end
	end,
	onPressButtonNoFocus = function(self, button)
		local slot = prompts[self.joypad.player].slots[button]
		if slot and slot.run then slot.run() end
	end,
	onHoldButton = noop,
	onReleaseButton = function(self, button)
		local jd = self.joypad
		ISFirearmRadialMenu.onJoypadButtonReleased(prompts[jd.player], button, jd)
	end,
	onPressUp = noop, onPressDown = noop, onPressLeft = noop, onPressRight = noop,
	onReleaseUp = noop, onReleaseDown = noop, onReleaseLeft = noop, onReleaseRight = noop,
}
ISDPadWheels = { onDisplayUp = noop, onDisplayDown = noop, onDisplayLeft = noop, onDisplayRight = noop }
ISJoystickButtonRadialMenu = { onJoypadDown = noop, onJoypadButtonReleased = noop, displayLeft = noop }
ISFirearmRadialMenu = { display = noop }
function ISFirearmRadialMenu.checkWeapon(player) return player.weapon ~= nil end
function ISFirearmRadialMenu.getBestRBButtonAction(prompt)
	if not players[prompt.player].weapon or players[prompt.player].aiming then return end
	prompt:setButtonBindingPrompt(CharacterJoypadButtonBinding.ReloadWeapon, "Reload", function(self)
		reloadTimer[self.player] = clock
	end)
end
function ISFirearmRadialMenu.onRepeatRBumper(prompt)
	local start = reloadTimer[prompt.player]
	if start and clock - start >= 500 then record(prompt, "reload menu") end
end
function ISFirearmRadialMenu.onJoypadButtonReleased(prompt, button)
	local start = reloadTimer[prompt.player]
	reloadTimer[prompt.player] = nil
	if start and clock - start < 500 then record(prompt, "quick reload") end
end
ISVehicleRegulator = { onJoypadPressUp = noop, onJoypadPressDown = noop, onJoypadReleaseX = noop, xPressed = {} }
MainScreen, JoypadState = {}, { players = {} }
Events = { OnRenderTick = { Add = function(callback) tick = callback end }, OnGameStart = { Add = noop } }
for id = 0, 1 do
	local jd = { id = id, player = id, isActive = true, isConnected = function(self) return self.isActive end }
	jd.controller = setmetatable({ joypad = jd }, { __index = JoypadControllerData })
	JoypadState.players[id + 1] = jd
	physical[id] = {}
	players[id] = {
		getVehicle = function(self) return self.inCar and vehicle or nil end,
		isAiming = function(self) return self.aiming or false end,
		isLookingWhileInVehicle = noop, getDir = noop,
		getPrimaryHandItem = function(self) return self.weapon end,
	}
	prompts[id] = setmetatable({ player = id, slots = {} }, { __index = ISButtonPrompt })
end
function getSpecificPlayer(id) return players[id] end
function getButtonPrompts(id) return prompts[id] end
function getMaxActivePlayers() return 2 end
function getCell() return { getDrag = noop } end
function isGamePaused() return false end
function getTimestampMs() return clock end
function getCore() return { getOptionGamepadBindingPreset = function() return "GTTest" end } end
function getText(key) return key end
UIManager = { getSpeedControls = noop }
gamepadBinding = { presets = { GTTest = { loadedSet = {} }, Copy = { loadedSet = {} } } }

require "GamepadTweaks/Bindings"
local bindings = GamepadTweaks.Bindings
bindings.add({
	id = "panCamera", layer = "aiming", button = Joypad.RBumper, followsButton = true,
	run = function(_, pad) record(prompts[pad.player], "camera pan") end,
	release = noop,
})
local jd = JoypadState.players[1]
local function at(ms)
	clock = ms
	tick()
	for _, pad in ipairs(JoypadState.players) do
		if pad.isActive and not pad.focus then updateJoypadFocus(pad) end
	end
end
local function edge(button, down, id)
	id = id or 0
	physical[id][button] = down
	local controller = JoypadState.players[id + 1].controller
	if down then controller:onPressButton(button) else controller:onReleaseButton(button) end
end
local function state(name, wanted, id)
	id = id or 0
	local actual = (published[id] or {})[name]
	assert(actual == wanted, name .. ": expected " .. tostring(wanted) .. ", got " .. tostring(actual))
end
local function prompted(id, button, label)
	local slot = prompts[id].slots[button]
	assert((slot and slot.label or nil) == label)
end
local function triggered(expected)
	assert(table.concat(queue, ",") == expected, "expected " .. expected .. ", got " .. table.concat(queue, ","))
	queue = {}
end
local function loadScenario(name)
	settings = {}
	for line in io.lines("tools/controller-scenarios/" .. name .. ".properties") do
		local key, value = line:match("^(preset%.[^=]+)=(.*)$")
		if key then settings[key] = value end
	end
	version = version + 1
end

assert(#bindings.layers == 6 and not table.concat(bindings.layers):find("cruise"))
assert(bindings.canBindIn(bindings.getActionById("cruiseFaster"), "vehicle"))
loadScenario("layers")
at(0)
prompted(0, Joypad.AButton, nil)
prompted(0, Joypad.LBumper, "Interact")
edge(Joypad.LBumper, true)
triggered("0:interact")
edge(Joypad.LBumper, false)
edge(Joypad.RBumper, true)
state("Crouch", true)
state("Crouch", false, 1)
edge(Joypad.RBumper, false)
at(55)
state("Crouch", false)
players[0].inCar = true
at(60)
prompted(0, Joypad.RBumper, "Interact")
prompted(1, Joypad.LBumper, "Interact")
edge(Joypad.RBumper, true)
triggered("0:interact")
state("Crouch", nil)
edge(Joypad.RBumper, false)
edge(Joypad.LBumper, true)
state("Brakes", true)
edge(Joypad.LBumper, false)
at(100)
state("Brakes", false)
jd.focus = { Type = "ISInventoryPage", onJoypadDown = function(self, button) table.insert(queue, tostring(button)) end }
at(110)
edge(Joypad.RBumper, true)
edge(Joypad.RBumper, false)
triggered("X")
edge(Joypad.XButton, true)
edge(Joypad.XButton, false)
triggered("")
jd.focus = nil

loadScenario("events")
players[0].inCar = false
at(120)
-- Single waits for the double deadline and a release.
edge(Joypad.BButton, true)
at(140)
edge(Joypad.BButton, false)
at(310)
state("Crouch", false)
at(311)
state("Crouch", true)
triggered("")
at(365)
state("Crouch", false)
-- A double and a hold pick their own actions, with no extra Crouch or stock B action.
edge(Joypad.BButton, true)
edge(Joypad.BButton, false)
at(470)
edge(Joypad.BButton, true)
edge(Joypad.BButton, false)
triggered("0:inventory")
at(500)
state("Crouch", false)
edge(Joypad.BButton, true)
at(799)
triggered("")
at(800)
triggered("0:interact")
state("Interact", true)
edge(Joypad.BButton, false)
at(830)
state("Interact", false)
state("Crouch", false)

-- Runtime analog threshold, hysteresis, then the original preset fallback on deletion.
physical[0][JoypadAxis1d.RightTrigger] = 0.78
at(840)
state("Attack", false)
physical[0][JoypadAxis1d.RightTrigger] = 0.8
at(850)
state("Attack", true)
physical[0][JoypadAxis1d.RightTrigger] = 0.77
at(900)
state("Attack", true)
physical[0][JoypadAxis1d.RightTrigger] = 0.74
at(950)
state("Attack", false)
assert(bindings.set("onfoot", "native_Attack", false))
at(951)
state("Attack", nil)

-- The main events scenario keeps the stock Aim binding and camera pan.
state("Aim", nil)
players[0].aiming = true
edge(Joypad.RBumper, true)
at(952)
state("Aim", nil)
triggered("0:camera pan")
edge(Joypad.RBumper, false)
players[0].aiming = false
at(953)

loadScenario("aim-override")
at(954)
-- An Aim press cannot take over a stale stock reload timer, even when the
-- stick returns to neutral or a layer change makes Reload available again.
players[0].weapon = {}
reloadTimer[0] = 300
edge(Joypad.RBumper, true)
players[0].aiming = true
at(990)
state("Aim", true)
triggered("")
players[0].aiming = false
at(991)
prompts[0]:update()
state("Aim", true)
triggered("")
players[0].aiming = true
at(992)
state("Aim", true)
triggered("")
edge(Joypad.RBumper, false)
at(993)
state("Aim", false)
triggered("")
players[0].aiming = false
at(994)
edge(Joypad.RBumper, true)
jd.focus = { Type = "ISPanelJoypad" }
at(995)
prompts[0]:update()
triggered("")
state("Aim", nil)
edge(Joypad.RBumper, false)
jd.focus = nil
at(996)
state("Aim", false)
triggered("")

-- A pending press cannot be replayed after leaving its layer.
loadScenario("events")
at(1000)
edge(Joypad.BButton, true)
edge(Joypad.BButton, false)
players[0].inCar = true
at(1250)
triggered("")
state("Crouch", nil)
-- Both orders of a reciprocal chord drive the same native action.
for i, pair in ipairs({ { Joypad.LBumper, Joypad.RBumper }, { Joypad.RBumper, Joypad.LBumper } }) do
	edge(pair[1], true)
	state("Brakes", nil)
	edge(pair[2], true)
	state("Brakes", true)
	edge(pair[2], false)
	edge(pair[1], false)
	at(1250 + 50 * i)
	state("Brakes", nil)
end

bindings.copyPreset("GTTest", "Copy")
assert(settings["preset.Copy.vehicle.bind.native_Brakes"] == settings["preset.GTTest.vehicle.bind.native_Brakes"])
edge(Joypad.LBumper, true)
edge(Joypad.RBumper, true)
state("Brakes", true)
jd.isActive = false
at(1400)
state("Brakes", nil)

settings, version = {}, version + 1
players[1].weapon = {}
at(1500)
edge(Joypad.RBumper, true, 1)
at(1590)
edge(Joypad.RBumper, false, 1)
triggered("1:quick reload")
edge(Joypad.RBumper, true, 1)
at(2090)
prompts[1]:update()
triggered("1:reload menu")
edge(Joypad.RBumper, false, 1)
triggered("")
edge(Joypad.RBumper, true, 1)
players[1].weapon = nil
at(2590)
prompts[1]:update()
edge(Joypad.RBumper, false, 1)
triggered("")

print("controller binding scenarios passed")
