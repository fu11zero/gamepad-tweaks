-- The mod's button actions in Options -> Controller (the vanilla bindings editor).
--
-- Each button row (CharacterJoypadBindingUIRow) lists the regular bindings on that button,
-- and its "< Add New >" list offers them; both come from the Java enum
-- CharacterJoypadButtonBinding, which can't get new values. The row and its lists are Lua,
-- so here the vanilla functions run first and the mod's actions (Bindings.lua, KeyActions.lua,
-- InventoryActions.lua)
-- are added after them:
-- - populateWithReadOnlyLabels: the actions on the button, in the mod colour;
-- - populateWithEditableElements: a list per action (another action instead, or "< Remove >");
-- - createJoypadButtonBindingCBox ("< Add New >"): the actions not on the button yet,
--   "[Category] Name", sorted by category.
-- Changes are written to ~/Zomboid/GamepadTweaks.properties at once (Bindings.set); they are
-- not part of the vanilla presets. If the vanilla editor changes, the wrappers only log.

require "ISUI/Gamepad/CharacterJoypadBindingUIRow"
require "GamepadTweaks/Bindings"
require "GamepadTweaks/KeyActions"
require "GamepadTweaks/InventoryActions"

local Bindings = GamepadTweaks.Bindings

local MOD_COLOR = { r = 0.45, g = 0.72, b = 0.95, a = 1 }
local REMOVE = "!RemoveEntry!"
local ADD_NEW = "!AddNewEntry!"
local PREFIX = "gt:"

local CATEGORY_ORDER = { "wheels", "controls", "vehicle", "hands", "character", "inventory", "windows", "hotbar", "time", "misc" }
local categoryRank = {}
for i, c in ipairs(CATEGORY_ORDER) do
	categoryRank[c] = i
end

local function log(msg)
	print("[GamepadTweaks] " .. msg)
end

local function isButtonRow(row)
	return instanceof(row.bindingKey, "JoypadButton")
end

-- All actions by category, then registration order.
local function sortedActions()
	local list = {}
	for i, action in ipairs(Bindings.actions) do
		if not action.steamOnly then
			table.insert(list, { action = action, index = i })
		end
	end
	table.sort(list, function(a, b)
		local ra = categoryRank[a.action.category] or #CATEGORY_ORDER + 1
		local rb = categoryRank[b.action.category] or #CATEGORY_ORDER + 1
		if ra ~= rb then return ra < rb end
		return a.index < b.index
	end)
	local result = {}
	for _, item in ipairs(list) do
		table.insert(result, item.action)
	end
	return result
end

-- Repopulates every row: an action moved here may have been on another button.
local function refreshAll(row)
	local ui = row.uiBinding and row.uiBinding.characterJoypadBindingUI
	local panel = ui and ui.controllerBindingsEditorPanel
	if panel and panel.populateAllBindingBoxes then
		panel:populateAllBindingBoxes()
	else
		row:rePopulate()
	end
end

local function comboWidth(box, style)
	local font = style:getFont("Medium")
	local width = 0
	for _, option in ipairs(box.options) do
		width = math.max(width, getTextManager():MeasureStringX(font, option.text))
	end
	return width + style.borderSpacing * 2 + style.buttonHeight
end

-- Read-only row ----------------------------------------------------------------------

local function addReadOnly(row)
	local actions = Bindings.getActionsOn(row.bindingKey)
	if #actions == 0 then return end
	local style = row:getStyle()
	local font = style:getFont("Small")
	local fontHgt = style:getFontHeight("Small") * 0.8
	local spacing = style:getFontHeight("Small") * 0.6 / 20
	local border = style.borderSpacing
	row.entries = row.entries or {}
	local last = row.entries[#row.entries] or row.bindingLabel
	local x = row.bindingLabel:getLeft() + (row.indentWidth or 0)
	local y = last:getBottom() + spacing
	local width = row:getWidth() - border
	-- the select button covers the row and must stay on top
	row:removeChild(row.selectButton)
	for _, action in ipairs(actions) do
		local label = ISLabel:new(x, y, fontHgt, Bindings.getLabel(action), MOD_COLOR.r, MOD_COLOR.g, MOD_COLOR.b, 1, font, true)
		label:initialise()
		row:addChild(label)
		table.insert(row.entries, label)
		width = math.max(width, label:getRight())
		y = label:getBottom() + spacing
	end
	row:addChild(row.selectButton)
	row:setWidth(width + border)
	row:setHeight(y - spacing + border)
end

local vanillaReadOnly = CharacterJoypadBindingUIRow.populateWithReadOnlyLabels
function CharacterJoypadBindingUIRow:populateWithReadOnlyLabels(...)
	local result = vanillaReadOnly(self, ...)
	if isButtonRow(self) then
		local ok, err = pcall(addReadOnly, self)
		if not ok then log("ERROR: controller editor (read-only row): " .. tostring(err)) end
	end
	return result
end

-- Editable row ---------------------------------------------------------------------

-- Options: the action itself, the actions not on this button, "< Remove >".
local function fillActionBox(box, button, current, style)
	box:clear()
	for _, action in ipairs(sortedActions()) do
		if action == current or action.bound ~= button then
			box:addOptionWithData(Bindings.getLabel(action, true), PREFIX .. action.id)
		end
	end
	box:addOptionWithData("< Remove >", REMOVE, "Remove this entry")
	box:setWidth(comboWidth(box, style))
	box:setSelectedData(PREFIX .. current.id)
end

function CharacterJoypadBindingUIRow:onGamepadTweaksActionChanged(box, currentId)
	local data = box:getSelectedData()
	if data == REMOVE then
		Bindings.set(currentId, false)
	elseif type(data) == "string" and data:sub(1, #PREFIX) == PREFIX then
		local id = data:sub(#PREFIX + 1)
		if id ~= currentId then
			Bindings.set(id, self.bindingKey)
			Bindings.set(currentId, false)
		end
	end
	refreshAll(self)
end

local function addEditable(row)
	local addNew
	for _, child in pairs(row:getChildren()) do
		if child.selectedCharBinding == ADD_NEW then
			addNew = child
		end
	end
	if not addNew then return end
	local actions = Bindings.getActionsOn(row.bindingKey)
	if #actions == 0 then return end
	local style = row:getStyle()
	local spacing = style:getFontHeight("Small") * 0.6 / 15
	local border = style.borderSpacing
	local height = addNew:getHeight()
	local x = addNew:getX()
	-- vanilla puts "< Add New >" two spacings below the last entry
	local y = addNew:getY() - spacing * 2
	local width = addNew:getWidth()
	for _, action in ipairs(actions) do
		local box = ISComboBox:new(x, y, height, height)
		box.choicesColor = { r = 1, g = 1, b = 1, a = 1 }
		box.textColor = MOD_COLOR
		box:initialise()
		row:addChild(box)
		if Bindings.canEdit() then
			fillActionBox(box, row.bindingKey, action, style)
			box:setOnChange(row, row.onGamepadTweaksActionChanged, action.id)
		else
			box:addOptionWithData(Bindings.getLabel(action, true), PREFIX .. action.id)
			box:setWidth(comboWidth(box, style))
			box:setEnabled(false)
		end
		width = math.max(width, box:getWidth())
		y = box:getBottom() + spacing
	end
	addNew:setY(y + spacing * 2)
	-- same width for every list in the row, as vanilla does
	for _, child in pairs(row:getChildren()) do
		if child.Type == "ISComboBox" then
			child:setWidth(width)
		end
	end
	row:setWidth(math.max(row:getWidth(), x + width + border))
	row:setHeight(addNew:getBottom() + border * 2)
end

local vanillaEditable = CharacterJoypadBindingUIRow.populateWithEditableElements
function CharacterJoypadBindingUIRow:populateWithEditableElements(...)
	local result = vanillaEditable(self, ...)
	if isButtonRow(self) then
		local ok, err = pcall(addEditable, self)
		if not ok then log("ERROR: controller editor (edit row): " .. tostring(err)) end
	end
	return result
end

-- "< Add New >" ----------------------------------------------------------------------

local function appendToAddNew(box, button)
	if not Bindings.canEdit() then return end
	local addEntry = table.remove(box.options) -- vanilla's "< Add New >", put back last
	for _, action in ipairs(sortedActions()) do
		if action.bound ~= button then
			box:addOptionWithData(Bindings.getLabel(action, true), PREFIX .. action.id)
		end
	end
	if addEntry then
		table.insert(box.options, addEntry)
	end
	box:setWidth(math.max(box:getWidth(), comboWidth(box, box:getStyle())))
	box:setSelectedData(ADD_NEW)
end

local vanillaCreateBox = CharacterJoypadBindingUIRow.createJoypadButtonBindingCBox
function CharacterJoypadBindingUIRow:createJoypadButtonBindingCBox(bindingKey, selected, ...)
	local box = vanillaCreateBox(self, bindingKey, selected, ...)
	if selected == ADD_NEW and instanceof(bindingKey, "JoypadButton") and box and box.populate then
		local vanillaPopulate = box.populate
		function box:populate(...)
			local result = vanillaPopulate(self, ...)
			local ok, err = pcall(appendToAddNew, self, bindingKey)
			if not ok then log("ERROR: controller editor (add list): " .. tostring(err)) end
			return result
		end
	end
	return box
end

local vanillaAddNewChanged = CharacterJoypadBindingUIRow.onAddNewJoypadBindingChanged
function CharacterJoypadBindingUIRow:onAddNewJoypadBindingChanged(senderBox, bindingKey, ...)
	local data = senderBox:getSelectedData()
	if type(data) == "string" and data:sub(1, #PREFIX) == PREFIX then
		Bindings.set(data:sub(#PREFIX + 1), bindingKey)
		refreshAll(self)
		return
	end
	return vanillaAddNewChanged(self, senderBox, bindingKey, ...)
end
