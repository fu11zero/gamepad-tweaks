-- A press that closed a context menu must not reach the window underneath it a second time.
--
-- Steam Input delays a button's plain press by the double-click timeout when hold / double
-- activators are bound on the same button. The game closes the menu on the first press, focus
-- goes back to its origin (ISContextMenu:closeAll -> setJoypadFocus), and Steam then sends the
-- same button again. The inventory sees that press as a fresh one: A opens another menu, B does
-- its panel action, Y closes the window.
--
-- Hold / double actions don't produce a duplicate gamepad press (Steam runs the game action
-- directly), so only the plain press needs handling. Its delay is about one double-click window
-- (190 ms by default), counted from the release of the button that closed the menu.
--
-- Here: only a press that actually closed a context menu arms the suppression. The joypad
-- handler also opens submenus with A (displaySubMenu() even hides the parent menu), so arming on
-- every A/B press in it drops half the presses while navigating a multi-level menu. The close
-- itself is the signal: remember the A/B press while it is being dispatched and arm the
-- suppression in ISContextMenu:closeAll(). On release, drop the next press of the same button
-- before it reaches any UI (JoypadControllerData:onPressButton is the common point of all gamepad
-- presses). One shot: a later deliberate press works normally.

require "ISUI/ISContextMenu"
require "ISUI/Gamepad/JoyPadSetup"

local ECHO_MS = 250
local STALE_MS = 2000

-- [controller id] = { button = button, time = ms } while a menu-closing press is held.
local pending = {}
-- [controller id][button] = ms until which the next press is dropped.
local suppressed = {}
-- The A/B press currently being dispatched to a context menu, if any.
local closingPress = nil

local vanillaContextDown = ISContextMenu.onJoypadDown
ISContextMenu.onJoypadDown = function(self, button, ...)
	local jd = self.player and JoypadState.players[self.player + 1]
	if not jd or not jd.id or (button ~= Joypad.AButton and button ~= Joypad.BButton) then
		return vanillaContextDown(self, button, ...)
	end
	local previous = closingPress
	closingPress = { id = jd.id, button = button, time = getTimestampMs() }
	local result = vanillaContextDown(self, button, ...)
	closingPress = previous
	return result
end

local vanillaCloseAll = ISContextMenu.closeAll
ISContextMenu.closeAll = function(self, ...)
	if closingPress then
		pending[closingPress.id] = { button = closingPress.button, time = closingPress.time }
	end
	return vanillaCloseAll(self, ...)
end

local vanillaRelease = JoypadControllerData.onReleaseButton
JoypadControllerData.onReleaseButton = function(self, button)
	local jd = self.joypad
	if jd and jd.id then
		local armed = pending[jd.id]
		if armed and armed.button == button and getTimestampMs() - armed.time < STALE_MS then
			pending[jd.id] = nil
			local byButton = suppressed[jd.id]
			if not byButton then
				byButton = {}
				suppressed[jd.id] = byButton
			end
			byButton[button] = getTimestampMs() + ECHO_MS
		end
	end
	return vanillaRelease(self, button)
end

local vanillaPress = JoypadControllerData.onPressButton
JoypadControllerData.onPressButton = function(self, button)
	local jd = self.joypad
	if jd and jd.id then
		local byButton = suppressed[jd.id]
		local untilMs = byButton and byButton[button]
		if untilMs then
			byButton[button] = nil
			if getTimestampMs() < untilMs then
				return -- Steam's delayed copy of the press that just closed the menu
			end
		end
	end
	return vanillaPress(self, button)
end
