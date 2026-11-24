-- Digital events derived from a button or from an axis crossing a threshold.
local BindingEvents = {
	order = { "press", "double", "hold", "modifier" },
	delay = { double = 190, hold = 300 },
	threshold = 90,
	inputs = {},
}

local names, inputsByName, axes = {}, {}, {}
local function addInput(input, prefix, axis)
	local name = prefix .. tostring(input)
	names[input], inputsByName[name], axes[input] = name, input, axis
	table.insert(BindingEvents.inputs, input)
end

for _, button in ipairs(JoypadButton.getButtons()) do addInput(button, "") end
addInput(JoypadAxis1d.LeftTrigger, "axis:", "trigger")
addInput(JoypadAxis1d.RightTrigger, "axis:", "trigger")
addInput(JoypadAxis2d.LeftStick, "axis:", "stick")
addInput(JoypadAxis2d.RightStick, "axis:", "stick")

function BindingEvents.hasInput(input)
	return names[input] ~= nil
end

function BindingEvents.number(value, minimum, maximum, default)
	local number = tonumber(value)
	if not number or number ~= number then return default end
	return math.max(minimum, math.min(maximum, math.floor(number + 0.5)))
end

function BindingEvents.assignment(input, options, defaultEvent)
	options = options or {}
	local event = options.event or defaultEvent
	if event == "native" and axes[input] then event = "hold" end
	local binding = { input = input, event = event }
	if axes[input] then
		binding.threshold = BindingEvents.number(options.threshold, 1, 100, BindingEvents.threshold)
	end
	if BindingEvents.delay[event] then
		binding.delay = BindingEvents.number(options.delay, 1, 9999, BindingEvents.delay[event])
	elseif event == "modifier" then
		local modifier = options.modifier
		if not names[modifier] or modifier == input then return nil end
		binding.modifier = modifier
		if axes[modifier] then
			binding.modifierThreshold = BindingEvents.number(options.modifierThreshold, 1, 100, BindingEvents.threshold)
		end
	elseif event ~= "press" and event ~= defaultEvent then
		return nil
	end
	return binding
end

function BindingEvents.decode(value, defaultEvent)
	local name, event, threshold, delay, modifier, modifierThreshold =
		value:match("^([^|]+)|([^|]+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
	local input = inputsByName[name or value]
	if not input then return nil end
	return BindingEvents.assignment(input, {
		event = event, threshold = threshold, delay = delay,
		modifier = inputsByName[modifier], modifierThreshold = modifierThreshold,
	}, defaultEvent)
end

function BindingEvents.encode(binding, defaultEvent)
	if binding.event == defaultEvent and not binding.threshold then return names[binding.input] end
	return table.concat({
		names[binding.input], binding.event, binding.threshold or "", binding.delay or "",
		names[binding.modifier] or "", binding.modifierThreshold or "",
	}, "|")
end

function BindingEvents.inputKey(input, threshold)
	return names[input] .. "|" .. (threshold or "")
end

-- At a given threshold the event is a slot. Chords with different modifiers can coexist.
function BindingEvents.slot(binding)
	local modifier = binding.modifier
	return BindingEvents.inputKey(binding.input, binding.threshold) .. "|" .. binding.event
		.. (modifier and "|" .. BindingEvents.inputKey(modifier, binding.modifierThreshold) or "")
end

function BindingEvents.magnitude(input, id)
	if axes[input] == "trigger" then
		return (input:getValue(id) + 1) / 2
	end
	if axes[input] == "stick" then return input:getLength(id) end
	return input:isDown(id) and 1 or 0
end

function BindingEvents.isDown(magnitude, threshold, wasDown)
	if not threshold then return magnitude > 0 end
	local point = threshold / 100
	-- Hysteresis stays below the set point and leaves room near zero for release.
	local release = point - math.min(0.02, point / 2)
	return magnitude + 0.000001 >= (wasDown and release or point)
end

-- A cycle can span two physical presses. The first press owns the double-click deadline
-- even if the second press lasts longer. Once a competing event fires it owns the cycle.
local Gesture = {}
BindingEvents.Gesture = Gesture

function Gesture.press(state, group, now, chord, modifierUsed, emit)
	if state.down then return end
	state.down = true
	state.pressedAt = now
	if chord then
		state.consumed = true
		emit(chord)
	elseif state.firstAt and now - state.firstAt <= group.double.delay then
		state.consumed = true
		emit(group.double)
	end
	state.firstAt = nil
	if not state.consumed then
		state.firstAt = group.double and now or nil
	end
	state.deferRelease = group.hold ~= nil or group.isModifier
	state.suppressPress = modifierUsed
	if group.press and not state.firstAt and not state.deferRelease and not state.consumed then
		state.singleFired = true
		emit(group.press)
	end
end

function Gesture.advance(state, group, now, emit)
	if state.down and group.hold and not state.consumed and now - state.pressedAt >= group.hold.delay then
		state.consumed = true
		state.firstAt = nil
		emit(group.hold)
	end
	-- A second down exactly at the deadline still counts. Expire on the following sample.
	if state.firstAt and now - state.firstAt > group.double.delay then
		state.firstAt = nil
	end
	if group.press and not state.firstAt and not state.consumed and not state.suppressPress
			and not state.singleFired and (not state.down or not state.deferRelease) then
		state.singleFired = true
		emit(group.press)
	end
end

function Gesture.release(state, group, now, emit)
	if not state.down then return end
	Gesture.advance(state, group, now, emit)
	state.down = false
	Gesture.advance(state, group, now, emit)
end

GamepadTweaks = GamepadTweaks or {}
GamepadTweaks.BindingEvents = BindingEvents
