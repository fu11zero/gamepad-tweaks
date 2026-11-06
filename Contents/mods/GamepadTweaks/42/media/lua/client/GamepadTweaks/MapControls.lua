-- Analog gamepad panning and zooming for the world map and paper maps.
--
-- Vanilla ISWorldMap:updateJoypad / ISMap:updateJoypad treat the stick and the triggers
-- as buttons (stick > 0.5 per axis, 150 ms delay, center snapped to whole squares,
-- one zoom level per trigger press). Here the per-frame movement is done by the Java side
-- (GamepadTweaks_updateMap, dev.gamepadtweaks.MapControls): pan speed follows the stick
-- deflection past the game's dead zone, zoom speed follows the triggers.
-- If the jar isn't loaded (ZombieBuddy missing or jar not approved) vanilla runs as before.

require "ISUI/Maps/ISWorldMap"
require "ISUI/Maps/ISMap"

local vanillaWorldMapUpdateJoypad = ISWorldMap.updateJoypad
local vanillaMapUpdateJoypad = ISMap.updateJoypad

-- Same focus and frame time bookkeeping as vanilla, then the Java update.
-- Returns false to let the caller run vanilla instead.
local function update(self, allowPan)
	if not GamepadTweaks_updateMap then return false end

	if self.getJoypadFocus then
		self.getJoypadFocus = false
		if JoypadState.players[self.playerNum+1] then
			if self.Type == "ISWorldMap" then
				self.prevFocus = getJoypadFocus(self.playerNum)
			end
			setJoypadFocus(self.playerNum, self)
		end
	end

	local currentTimeMs = getTimestampMs()
	local prevMS = self.updateMS
	self.updateMS = self.updateMS or currentTimeMs
	local dt = currentTimeMs - self.updateMS
	self.updateMS = currentTimeMs

	if self.joyfocus == nil then return true end

	if GamepadTweaks_updateMap(self.mapAPI, self.joyfocus.id, dt, self.width, self.height, allowPan) then
		return true
	end
	-- unknown controller or map.smooth off: give vanilla this frame's time
	self.updateMS = prevMS
	return false
end

-- While rotating an annotation the stick sets its angle (ISWorldMapSymbolTool_RotateAnnotation:render).
local function isRotatingAnnotation(self)
	local symbolsUI = self.symbolsUI
	if not symbolsUI or not symbolsUI.currentTool or not symbolsUI.tools then return false end
	return symbolsUI.currentTool == symbolsUI.tools.RotateAnnotation and symbolsUI.currentTool.dragging ~= nil
end

function ISWorldMap:updateJoypad()
	if not update(self, not isRotatingAnnotation(self)) then
		vanillaWorldMapUpdateJoypad(self)
	end
end

function ISMap:updateJoypad()
	if not update(self, not isRotatingAnnotation(self)) then
		vanillaMapUpdateJoypad(self)
	end
end

-- Fliers and stash maps under the gamepad cross.
-- Vanilla ISWorldMap:renderPrintMedia / renderStashMaps look for the icon under the map center
-- when the gamepad is used, but then also require self:isPointOver(getMouseX(), getMouseY()):
-- the real mouse cursor must be over the map and not under another top-level UI. With a gamepad
-- the cursor is anywhere (in splitscreen usually on another player's screen), so the icon is never
-- highlighted and A does nothing; streets (pickMouseOverStreet) have no such check and work.
-- Patch: while these run in gamepad mode, isPointOver tests the cross instead of the cursor.
local function isJoypadMode(self)
	return self.playerNum ~= nil and (self.playerNum ~= 0
		or (getJoypadData(self.playerNum) ~= nil and not wasMouseActiveMoreRecentlyThanJoypad()))
end

local function crossIsPointOver(self)
	local jo = self.javaObject
	return jo:isPointOver(jo:getAbsoluteX() + self.width / 2, jo:getAbsoluteY() + self.height / 2)
end

local function underCross(vanilla)
	return function(self, ...)
		if not isJoypadMode(self) then return vanilla(self, ...) end
		self.isPointOver = crossIsPointOver
		local ok, err = pcall(vanilla, self, ...)
		self.isPointOver = nil
		if not ok then error(err, 0) end
	end
end

ISWorldMap.renderPrintMedia = underCross(ISWorldMap.renderPrintMedia)
ISWorldMap.renderStashMaps = underCross(ISWorldMap.renderStashMaps)
