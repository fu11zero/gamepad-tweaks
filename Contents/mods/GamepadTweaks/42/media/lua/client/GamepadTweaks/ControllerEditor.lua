-- Context tabs and the mod's button actions in Options -> Controller.
-- The shared tab also uses vanilla's CharacterJoypadButtonBinding and axis editors.

require "ISUI/Gamepad/CharacterJoypadBindingUIRow"
require "ISUI/Gamepad/GameOptionControllerTab"
require "ISUI/ISComboBox"
require "GamepadTweaks/Bindings"
require "GamepadTweaks/KeyActions"
require "GamepadTweaks/InventoryActions"

local Bindings = GamepadTweaks.Bindings

local MOD_COLOR = { r = 0.45, g = 0.72, b = 0.95, a = 1 }
local REMOVE = "!RemoveEntry!"
local ADD_NEW = "!AddNewEntry!"
local PREFIX = "gt:"
local ICON_PATH = "media/textures/GamepadTweaks/actions/"
local actionIcons = {}

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

local function editorPanel(row)
	return row.uiBinding.characterJoypadBindingUI.controllerBindingsEditorPanel
end

local function selectedLayer(row)
	return editorPanel(row).gtLayer or "world"
end

-- Keep the current assignment in the list even if it predates context filtering.
local function sortedActions(layer, current)
	local list = {}
	for i, action in ipairs(Bindings.actions) do
		if action == current or Bindings.canBindIn(action, layer) then
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
	local panel = editorPanel(row)
	if panel and panel.populateAllBindingBoxes then
		panel:populateAllBindingBoxes()
	else
		row:rePopulate()
	end
end

local function actionIcon(id)
	if actionIcons[id] == nil then
		actionIcons[id] = getTexture(ICON_PATH .. id .. ".png") or false
	end
	return actionIcons[id]
end

local function iconWidth(texture, height)
	return math.floor(height * texture:getWidthOrig() / texture:getHeightOrig())
end

local function iconGap(height)
	return math.max(3, math.floor(height / 4))
end

local function drawOptionIcon(ui, option, x, y, font)
	if type(option) ~= "table" or not option.gtIcon then return x end
	local height = getTextManager():getFontHeight(font)
	local width = iconWidth(option.gtIcon, height)
	ui:drawTextureScaled(option.gtIcon, x, y, width, height, 1, 1, 1, 1)
	return x + width + iconGap(height)
end

-- Use vanilla's text draw call so icons share its clipping and scroll position.
-- The popup is shared by all combos. Only options with our texture get an icon.
local popupDrawItem = ISComboBoxPopup.doDrawItem
function ISComboBoxPopup:doDrawItem(y, item, ...)
	self.gtDrawingItem = item
	local bottom = popupDrawItem(self, y, item, ...)
	self.gtDrawingItem = nil
	return bottom
end

local popupDrawText = ISComboBoxPopup.drawText
function ISComboBoxPopup:drawText(str, x, y, r, g, b, a, font)
	local item = self.gtDrawingItem or self.tooWide
	if item then
		x = drawOptionIcon(self, self.parentCombo.options[item.index], x, y, font)
	end
	popupDrawText(self, str, x, y, r, g, b, a, font)
end

local function addActionOption(box, action)
	box:addOptionWithData(Bindings.getLabel(action), PREFIX .. action.id)
	box.options[#box.options].gtIcon = actionIcon(action.id)
end

local function comboWidth(box, style)
	local font = style:getFont("Medium")
	local iconHeight = getTextManager():getFontHeight(box.font)
	local width = 0
	for _, option in ipairs(box.options) do
		local textWidth = getTextManager():MeasureStringX(font, option.text)
		if option.gtIcon then
			textWidth = textWidth + iconWidth(option.gtIcon, iconHeight) + iconGap(iconHeight)
		end
		width = math.max(width, textWidth)
	end
	-- The popup has its own left padding and may have a vertical scrollbar.
	return width + math.max(10 + 13 + 8, style.borderSpacing * 2 + style.buttonHeight)
end

-- Read-only row ----------------------------------------------------------------------

local function addReadOnly(row)
	local actions = Bindings.getActionsOn(selectedLayer(row), row.bindingKey)
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
		local texture = actionIcon(action.id)
		if texture then
			local height = math.floor(fontHgt)
			local iconW = iconWidth(texture, height)
			local inset = iconW + iconGap(height)
			local labelDrawText = label.drawText
			function label:drawText(str, textX, textY, r, g, b, a, textFont)
				self:drawTextureScaled(texture, textX, (self:getHeight() - height) / 2, iconW, height, 1, 1, 1, 1)
				labelDrawText(self, str, textX + inset, textY, r, g, b, a, textFont)
			end
			label:setWidth(label:getWidth() + inset)
		end
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

-- On a context tab the physical controls keep their positions and only mod bindings
-- for that context appear. Vanilla button and axis bindings are edited on the shared tab.
local function populateLayerRow(row)
	row:clearChildren()
	local style = row:getStyle()
	local font = style:getFont("Small")
	local height = style:getFontHeight("Small") * 0.8
	local border = style.borderSpacing
	local label = ISLabel:new(border, 0, height, getText(row.bindingKey:getNameTranslationKey()),
		1, 1, 1, 1, font, true)
	label:initialise()
	row:addChild(label)
	row.bindingLabel = label
	row.entries = {}
	row.borderSpacing = border
	row.indentWidth = height / 2
	row:setWidth(label:getRight() + border)
	row:setHeight(label:getBottom() + border)
end

local vanillaReadOnly = CharacterJoypadBindingUIRow.populateWithReadOnlyLabels
function CharacterJoypadBindingUIRow:populateWithReadOnlyLabels(...)
	if selectedLayer(self) == "world" then
		vanillaReadOnly(self, ...)
	else
		populateLayerRow(self)
		if isButtonRow(self) then self:addChild(self.selectButton) end
	end
	if isButtonRow(self) then
		local ok, err = pcall(addReadOnly, self)
		if not ok then log("ERROR: controller editor (read-only row): " .. tostring(err)) end
	end
end

-- Vanilla makes a new preset from a built-in one on the first change
-- (GameOptionControllerTab:onJoypadButtonBindingEdited); the mod's changes go the same way.
local function editablePreset(row)
	if Bindings.isPresetEditable() then return true end
	local ui = row.uiBinding
	if ui and ui.onJoypadButtonBindingEdited then
		ui:onJoypadButtonBindingEdited()
	end
	return Bindings.isPresetEditable()
end

-- Editable row ---------------------------------------------------------------------

-- Options: the action itself, the actions not on this button, "< Remove >".
local function fillActionBox(box, layer, button, current, style)
	box:clear()
	for _, action in ipairs(sortedActions(layer, current)) do
		if action == current or Bindings.canReplace(layer, current, action, button) then
			addActionOption(box, action)
		end
	end
	box:addOptionWithData("< Remove >", REMOVE, "Remove this entry")
	box:setWidth(comboWidth(box, style))
	box:setSelectedData(PREFIX .. current.id)
end

function CharacterJoypadBindingUIRow:onGamepadTweaksActionChanged(box, currentId)
	local data = box:getSelectedData()
	local layer = selectedLayer(self)
	if data == REMOVE and editablePreset(self) then
		Bindings.set(layer, currentId, false)
	elseif type(data) == "string" and data:sub(1, #PREFIX) == PREFIX then
		local id = data:sub(#PREFIX + 1)
		if id ~= currentId and editablePreset(self) then
			Bindings.set(layer, id, self.bindingKey)
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
	local actions = Bindings.getActionsOn(selectedLayer(row), row.bindingKey)
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
		local comboDrawText = box.drawText
		function box:drawText(str, textX, textY, r, g, b, a, font)
			textX = drawOptionIcon(self, self.options[self.selected], textX, textY, font)
			comboDrawText(self, str, textX, textY, r, g, b, a, font)
		end
		box:initialise()
		row:addChild(box)
		if Bindings.canEdit() then
			fillActionBox(box, selectedLayer(row), row.bindingKey, action, style)
			box:setOnChange(row, row.onGamepadTweaksActionChanged, action.id)
		else
			addActionOption(box, action)
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
	if selectedLayer(self) == "world" then
		vanillaEditable(self, ...)
	else
		populateLayerRow(self)
		if not isButtonRow(self) then return end
		local label = self.bindingLabel
		local style = self:getStyle()
		local spacing = style:getFontHeight("Small") * 0.6 / 15
		local height = label:getHeight() * 1.1
		local box = self:createJoypadButtonBindingCBox(self.bindingKey, ADD_NEW, {},
			label:getLeft() + self.indentWidth, label:getBottom() + spacing * 3, height, height)
		self:addChild(box)
		box:populate()
		box:setOnChange(self, self.onAddNewJoypadBindingChanged, self.bindingKey)
		self:setWidth(math.max(self:getWidth(), box:getRight() + style.borderSpacing))
		self:setHeight(box:getBottom() + style.borderSpacing * 2)
	end
	if isButtonRow(self) then
		local ok, err = pcall(addEditable, self)
		if not ok then log("ERROR: controller editor (edit row): " .. tostring(err)) end
	end
end

-- "< Add New >" ----------------------------------------------------------------------

local function appendToAddNew(box, layer, button)
	local addEntry = table.remove(box.options)
	if Bindings.canEdit() then
		for _, action in ipairs(sortedActions(layer)) do
			if Bindings.getActionButton(action, layer) ~= button then
				addActionOption(box, action)
			end
		end
	end
	table.insert(box.options, addEntry)
	box:setWidth(comboWidth(box, box:getStyle()))
	box:setSelectedData(ADD_NEW)
	if #box.options == 1 then box:setEnabled(false) end
end

local vanillaCreateBox = CharacterJoypadBindingUIRow.createJoypadButtonBindingCBox
function CharacterJoypadBindingUIRow:createJoypadButtonBindingCBox(bindingKey, selected, ...)
	local box = vanillaCreateBox(self, bindingKey, selected, ...)
	if selected == ADD_NEW and instanceof(bindingKey, "JoypadButton") then
		local layer = selectedLayer(self)
		local vanillaPopulate = box.populate
		function box:populate()
			if layer == "world" then
				vanillaPopulate(self)
			else
				self:clear()
				self:addOptionWithData("< Add New >", ADD_NEW, "Add new entry")
			end
			appendToAddNew(self, layer, bindingKey)
		end
	end
	return box
end

local vanillaAddNewChanged = CharacterJoypadBindingUIRow.onAddNewJoypadBindingChanged
function CharacterJoypadBindingUIRow:onAddNewJoypadBindingChanged(senderBox, bindingKey, ...)
	local data = senderBox:getSelectedData()
	if type(data) == "string" and data:sub(1, #PREFIX) == PREFIX then
		if editablePreset(self) then
			Bindings.set(selectedLayer(self), data:sub(#PREFIX + 1), bindingKey)
		end
		refreshAll(self)
		return
	end
	return vanillaAddNewChanged(self, senderBox, bindingKey, ...)
end

-- Layer tabs sit in the vanilla preset header, above the scrollable controller diagram.
local function selectLayer(panel, button)
	if panel.gtLayer == button.gtLayer then return end
	panel.gtLayer = button.gtLayer
	for _, tab in ipairs(panel.gtLayerTabs) do
		if tab == button then
			tab:setBackgroundRGBA(0.18, 0.32, 0.46, 1)
		else
			tab:setBackgroundRGBA(0, 0, 0, 1)
		end
	end
	panel:setYScroll(0)
	if panel.editedUIBinding then
		panel:setActiveEditingBindingUI(nil)
	else
		panel:populateAllBindingBoxes()
	end
end

local vanillaCustomization = GameOptionControllerTab.initControllerCustomizationPanel
function GameOptionControllerTab:initControllerCustomizationPanel(...)
	local container = vanillaCustomization(self, ...)
	local top = container.topPanel
	local panel = container.controllerBindingsEditorPanel
	local style = self:getStyle()
	local spacing = style.borderSpacing
	local height = style.buttonHeight
	local firstY = top:getHeight()
	panel.gtLayerTabs = {}
	local font = style:getFont("Small")
	for _, layer in ipairs(Bindings.layers) do
		local title = getText("UI_GamepadTweaks_tab_" .. layer)
		local width = getTextManager():MeasureStringX(font, title) + spacing * 4
		local button = ISButton:new(0, firstY, width, height, title, panel, selectLayer)
		button.gtLayer = layer
		button:setFont(font)
		button:setTooltip(getText("UI_GamepadTweaks_tab_help_" .. layer))
		button:initialise()
		top:addChild(button)
		table.insert(panel.gtLayerTabs, button)
	end
	local vanillaLayout = container.onDoLayout
	function container:onDoLayout()
		local x, y = spacing * 2, firstY
		top:setWidth(self:getWidth())
		for _, tab in ipairs(panel.gtLayerTabs) do
			if x > spacing * 2 and x + tab:getWidth() > top:getWidth() - spacing then
				x, y = spacing * 2, y + height + spacing
			end
			tab:setX(x)
			tab:setY(y)
			x = tab:getRight() + spacing
		end
		top:setHeight(y + height + spacing)
		vanillaLayout(self)
	end
	panel.gtLayer = "world"
	panel.gtLayerTabs[1]:setBackgroundRGBA(0.18, 0.32, 0.46, 1)
	return container
end

-- New presets ------------------------------------------------------------------------

-- Editing a built-in preset (Default, Original) spawns a new one named
-- getText("IGUI_Custom") (gamepadBinding:createNewFromCurrent ->
-- CharacterInputBindingSet.getUniqueSetName), saved as InputBindings/<name>.xml. Steam runs
-- the game with LC_ALL=C, where Java can't create a file with a non-ASCII name
-- ("Пользовательский.xml": Invalid argument), so the preset is lost on Apply. Such names
-- become "Custom" (made unique by getUniqueSetName).
require "gamepadBinding"

local function isAscii(s)
	return not s:find("[\128-\255]")
end

if gamepadBinding and gamepadBinding.createNewFromCurrent and CharacterInputBindingSet then
	local vanillaCreateNew = gamepadBinding.createNewFromCurrent
	function gamepadBinding:createNewFromCurrent(...)
		local from = Bindings.currentPreset()
		local entry
		if isAscii(getText("IGUI_Custom")) then
			entry = vanillaCreateNew(self, ...)
		else
			entry = self:addInputSet(CharacterInputBindingSet.createNewFromCurrent("Custom"))
		end
		if entry and entry.key then
			Bindings.copyPreset(from, entry.key)
		end
		return entry
	end
else
	log("WARN: gamepadBinding.createNewFromCurrent not found, new presets keep the translated name")
end
