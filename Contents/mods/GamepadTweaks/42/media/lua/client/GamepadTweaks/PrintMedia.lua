-- Gamepad control of the flier / brochure window (PZAPI.UI.PrintMedia).
--
-- Vanilla ISReadABook:displayPrintMedia (and ISWorldMap:onMouseUpPrintMedia) call
-- setJoypadFocus(playerNum, win), which first evaluates uiToString(win) for a noise() log
-- line (JoyPadSetup.lua:550) even with debug logging off. uiToString calls ISAtomUIJoypad:toString,
-- and for a window without a UI name that does self._ATOM_UI_CLASS.class:getSimpleName():
-- in Kahlua .class of a Java class is not a table, so it throws
-- "attempted index: getSimpleName of non-table: class zombie.ui.AtomUI". The focus is never
-- assigned (it stays on the inventory), so B/X/Y do nothing and the window closes only with
-- Esc; ISReadABook:perform is cut short too. There is also no prompt for B.
-- Here: a toString that doesn't throw, a B prompt in the bottom bar, and close() doesn't
-- leave the focus on an element that is gone by then.
-- Splitscreen issues of this window (shared worldMapFlier, getPlayer()) are fixed in SplitscreenFixes.

require "ISUI/ISAtomUIJoypad"
require "PZAPI/ui/organisms/PrintMedia"

local UI = PZAPI.UI

-- ISAtomUIJoypad.Apply copies the table's fields into the window when it is called,
-- so replacing the field here is enough for every window made later.
function ISAtomUIJoypad:toString()
	local ok, name = pcall(function() return self.javaObj and self.javaObj:getUIName() end)
	if ok and name and name ~= "" then return name end
	return tostring(self.Type or "AtomUI")
end

local function isShown(ui)
	if type(ui) ~= "table" or not ui.isVisible then return false end
	local ok, visible = pcall(ui.isVisible, ui)
	return ok and visible
end

-- Vanilla close() gives the focus back to whatever had it on open; if that UI was closed
-- meanwhile, the controller would be stuck on a hidden element.
local function wrapClose(win)
	if win.gtCloseWrapped or not win.close or win.playerNum == nil then return end
	win.gtCloseWrapped = true
	local vanillaClose = win.close
	win.close = function(self)
		vanillaClose(self)
		local joypadData = getJoypadData(self.playerNum)
		if joypadData and joypadData.focus ~= nil and not isShown(joypadData.focus) then
			setJoypadFocus(self.playerNum, nil)
		end
	end
end

local vanillaRenderUpdate = UI.PrintMedia.renderUpdate
UI.PrintMedia.renderUpdate = function(self)
	vanillaRenderUpdate(self)
	wrapClose(self)
end

-- B prompt, centered in the bottom bar (vanilla only has X and Y there).
local bottomButtons = UI.PrintMedia.children.bottomButtons
bottomButtons.children.joypadB = UI.Texture{
	texture = Joypad.Texture.BButton,
	y = (40 - Joypad.Texture.BButton:getHeight()) / 2,
	width = Joypad.Texture.BButton:getWidth(), height = Joypad.Texture.BButton:getHeight(),
	visible = false
}
local vanillaBottomRenderUpdate = bottomButtons.renderUpdate
bottomButtons.renderUpdate = function(self)
	vanillaBottomRenderUpdate(self)
	local b = self.children.joypadB
	if b and b.javaObj then
		b:setVisible(self.parent.playerNum ~= nil and getJoypadData(self.parent.playerNum) ~= nil)
		b:setX((self.javaObj:getWidth() - b.javaObj:getWidth()) / 2)
	end
end
