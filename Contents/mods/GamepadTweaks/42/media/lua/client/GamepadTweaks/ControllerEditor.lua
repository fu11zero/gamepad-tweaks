-- Context tabs and button events in Options -> Controller.
-- The shared tab also uses vanilla's CharacterJoypadButtonBinding and axis editors.

require "ISUI/Gamepad/CharacterJoypadBindingUIRow"
require "ISUI/Gamepad/GameOptionControllerTab"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "GamepadTweaks/Bindings"
require "GamepadTweaks/KeyActions"
require "GamepadTweaks/InventoryActions"

local Bindings = GamepadTweaks.Bindings
local BindingEvents = GamepadTweaks.BindingEvents

local MOD_COLOR = { r = 0.45, g = 0.72, b = 0.95, a = 1 }
local REMOVE = "!RemoveEntry!"
local ADD_NEW = "!AddNewEntry!"
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

local function supportsEvents(row)
	return BindingEvents.hasInput(row.bindingKey)
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
	box:addOptionWithData(Bindings.getLabel(action), action)
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

local function eventLabel(event)
	return getText("UI_GamepadTweaks_event_" .. event)
end

local function inputLabel(input)
	if input == JoypadButton.Guide then return getText("UI_GamepadTweaks_buttonGuide") end
	return getText(input:getNameTranslationKey())
end

local function describe(binding)
	if binding.event == "native" or (binding.event == "press" and not binding.threshold) then
		return Bindings.getLabel(binding.action)
	end
	local parts = { eventLabel(binding.event) }
	if binding.threshold then table.insert(parts, binding.threshold .. "%") end
	if binding.delay then table.insert(parts, binding.delay .. " " .. getText("UI_GamepadTweaks_ms")) end
	if binding.modifier then
		local label = inputLabel(binding.modifier)
		if binding.modifierThreshold then label = label .. " " .. binding.modifierThreshold .. "%" end
		table.insert(parts, label)
	end
	return Bindings.getLabel(binding.action) .. " · " .. table.concat(parts, " ")
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
	for _, binding in ipairs(actions) do
		local label = ISLabel:new(x, y, fontHgt, describe(binding), MOD_COLOR.r, MOD_COLOR.g, MOD_COLOR.b, 1, font, true)
		local texture = actionIcon(binding.action.id)
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

-- Context tabs show the explicit assignments for that context. The General tab also
-- shows the stock preset, including the continuous movement and aiming axes.
local function populateLayerRow(row)
	row:clearChildren()
	local style = row:getStyle()
	local font = style:getFont("Small")
	local height = style:getFontHeight("Small") * 0.8
	local border = style.borderSpacing
	local label = ISLabel:new(border, 0, height, inputLabel(row.bindingKey),
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
		if supportsEvents(self) then self:addChild(self.selectButton) end
	end
	if supportsEvents(self) then
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

local function eventOption(box, event)
	box:addOptionWithData(eventLabel(event), event, getText("UI_GamepadTweaks_event_help_" .. event))
end

local function eventBox(row, x, y, height, event, native, available)
	local box = ISComboBox:new(x, y, height, height)
	box:initialise()
	row:addChild(box)
	for _, option in ipairs(BindingEvents.order) do
		if not available or available[option] then eventOption(box, option) end
	end
	if native and (not available or available.native) then eventOption(box, "native") end
	box:setSelectedData(event)
	box:setWidth(comboWidth(box, row:getStyle()))
	return box
end

local function actionBox(row, x, y, height)
	local box = ISComboBox:new(x, y, height, height)
	box.choicesColor = { r = 1, g = 1, b = 1, a = 1 }
	box.textColor = MOD_COLOR
	local drawText = box.drawText
	function box:drawText(str, textX, textY, r, g, b, a, font)
		textX = drawOptionIcon(self, self.options[self.selected], textX, textY, font)
		drawText(self, str, textX, textY, r, g, b, a, font)
	end
	box:initialise()
	row:addChild(box)
	return box
end

local function saveAssignment(row, binding, options, action)
	local layer = selectedLayer(row)
	local id = action and action.id or binding.action.id
	if options and editablePreset(row) then
		Bindings.set(layer, id, row.bindingKey, options, binding)
	end
	refreshAll(row)
end

local function copyOptions(binding)
	local options = {}
	for key, value in pairs(binding) do options[key] = value end
	return options
end

local function modifierFor(input)
	for _, other in ipairs(BindingEvents.inputs) do
		if other ~= input then return other end
	end
end

local function optionsFor(input, options, defaultEvent)
	if options.event == "modifier" and not options.modifier then options.modifier = modifierFor(input) end
	return BindingEvents.assignment(input, options, defaultEvent)
end

local function availableEvents(layer, binding)
	local result = { [binding.event] = binding }
	local input, action = binding.input, binding.action
	for _, event in ipairs({ "press", "double", "hold", "native" }) do
		if not result[event] and (event ~= "native" or (Bindings.defaultEvent(action) == "native" and not binding.threshold)) then
			local options = { input = input, event = event, threshold = binding.threshold }
			if Bindings.canUseEvent(layer, action, options, binding) then result[event] = options end
		end
	end
	if not result.modifier then
		for _, modifier in ipairs(BindingEvents.inputs) do
			local options = { input = input, event = "modifier", threshold = binding.threshold, modifier = modifier }
			if Bindings.canUseEvent(layer, action, options, binding) then
				result.modifier = options
				break
			end
		end
	end
	return result
end

local function addNumber(row, x, y, height, key, value, minimum, maximum, update)
	local font = row:getStyle():getFont("Small")
	local label = ISLabel:new(x, y, height, getText(key), 1, 1, 1, 1, font, true)
	label:initialise()
	row:addChild(label)
	local width = getTextManager():MeasureStringX(font, "99999") + row:getStyle().borderSpacing
	local entry = ISTextEntryBox:new(tostring(value), label:getRight() + row:getStyle().borderSpacing, y, width, height)
	entry:setFont(font)
	entry:initialise()
	row:addChild(entry)
	entry:setOnlyNumbers(true)
	local function commit()
		local number = BindingEvents.number(entry:getText(), minimum, maximum, value)
		if number ~= value and update(number) then value = number end
		entry:setText(tostring(value))
	end
	function entry:onCommandEntered() commit() end
	function entry:onLostFocus() commit() end
	return entry
end

local function addParameters(row, x, y, height, spacing, binding, update)
	local right = x
	local function number(key, label, min, max)
		local entry = addNumber(row, x, y, height, label, binding[key], min, max, function(value)
			local options = copyOptions(binding)
			options[key] = value
			return update(options, false)
		end)
		right, y = math.max(right, entry:getRight()), entry:getBottom() + spacing
	end
	if binding.threshold then number("threshold", "UI_GamepadTweaks_threshold", 1, 100) end
	if binding.delay then number("delay", "UI_GamepadTweaks_delay", 1, 9999) end
	if binding.modifier then
		local box = ISComboBox:new(x, y, height, height)
		box:initialise()
		row:addChild(box)
		for _, input in ipairs(BindingEvents.inputs) do
			if input ~= row.bindingKey then box:addOptionWithData(inputLabel(input), input) end
		end
		box:setSelectedData(binding.modifier)
		box:setWidth(comboWidth(box, row:getStyle()))
		box:setOnChange(row, function(_, sender)
			local options = copyOptions(binding)
			options.modifier = sender:getSelectedData()
			update(options, true)
		end)
		right, y = math.max(right, box:getRight()), box:getBottom() + spacing
		if binding.modifierThreshold then number("modifierThreshold", "UI_GamepadTweaks_modifierThreshold", 1, 100) end
	end
	return right, y
end

local function hasRegularHere(action, layer, input)
	for _, binding in ipairs(Bindings.getAssignments(action, layer)) do
		if binding.event ~= "modifier" and binding.input == input then return true end
	end
	return false
end

local function addEditable(row)
	local layer, input = selectedLayer(row), row.bindingKey
	local style = row:getStyle()
	local border = style.borderSpacing
	local height = row.bindingLabel:getHeight() * 1.1
	local spacing = style:getFontHeight("Small") * 0.6 / 15
	local x = row.bindingLabel:getLeft() + row.bindingLabel:getHeight() / 2
	local y = row.bindingLabel:getBottom() + spacing
	if layer == "world" then
		for _, child in pairs(row:getChildren()) do
			if child.selectedCharBinding == ADD_NEW then y = child:getBottom() + border end
		end
	end

	local right = row:getWidth() - border
	for _, assignment in ipairs(Bindings.getActionsOn(layer, input)) do
		local binding = copyOptions(assignment)
		local current = binding.action
		local native = Bindings.defaultEvent(current) == "native" and not binding.threshold
		local choices = availableEvents(layer, binding)
		local event = eventBox(row, x, y, height, binding.event, native, choices)
		local box = actionBox(row, event:getRight() + border, y, height)
		if Bindings.canEdit() then
			for _, action in ipairs(sortedActions(layer, current)) do
				if action == current or ((binding.event == "modifier" or not hasRegularHere(action, layer, input))
						and Bindings.canUseEvent(layer, action, binding, binding)
						and (binding.event ~= "native" or action.layer == current.layer)) then
					addActionOption(box, action)
				end
			end
			box:addOptionWithData(getText("UI_GamepadTweaks_bindingRemove"), REMOVE)
			box:setOnChange(row, function(_, sender)
				local selected = sender:getSelectedData()
				if selected == REMOVE then
					if editablePreset(row) then Bindings.set(layer, current.id, false, nil, binding) end
					refreshAll(row)
				elseif selected ~= current then
					saveAssignment(row, binding, binding, selected)
				end
			end)
			event:setOnChange(row, function(_, sender)
				local options = availableEvents(layer, binding)[sender:getSelectedData()]
				saveAssignment(row, binding, options)
			end)
		else
			addActionOption(box, current)
			box:setEnabled(false)
			event:setEnabled(false)
		end
		box:setSelectedData(current)
		box:setWidth(comboWidth(box, style))
		right, y = math.max(right, box:getRight()), box:getBottom() + spacing
		if Bindings.canEdit() then
			local paramRight
			paramRight, y = addParameters(row, x, y, height, spacing, binding, function(options, reflow)
				local ok = editablePreset(row) and Bindings.set(layer, current.id, input, options, binding)
				if ok then
					for key, value in pairs(options) do binding[key] = value end
				end
				if reflow then refreshAll(row) end
				return ok
			end)
			right = math.max(right, paramRight)
		end
		y = y + spacing
	end
	if Bindings.canEdit() then
		local draft = row.gtEventDraft
		if not draft or draft.layer ~= layer then
			draft = { layer = layer, event = "press" }
			row.gtEventDraft = draft
		end
		local event = eventBox(row, x, y, height, draft.event, false)
		event:setOnChange(row, function(_, sender)
			draft.event, draft.delay = sender:getSelectedData(), nil
			row:rePopulate()
		end)
		local box = actionBox(row, event:getRight() + border, y, height)
		local options = optionsFor(input, draft, "press")
		local function populateChoices()
			box:clear()
			for _, action in ipairs(sortedActions(layer)) do
				if (options.event == "modifier" or not hasRegularHere(action, layer, input))
						and Bindings.canUseEvent(layer, action, options) then
					addActionOption(box, action)
				end
			end
			box:addOptionWithData(getText("UI_GamepadTweaks_bindingAdd"), ADD_NEW)
			box:setSelectedData(ADD_NEW)
			box:setWidth(comboWidth(box, style))
			box:setEnabled(#box.options > 1)
		end
		populateChoices()
		box:setOnChange(row, function(_, sender)
			local selected = sender:getSelectedData()
			if selected ~= ADD_NEW then saveAssignment(row, nil, options, selected) end
		end)
		right, y = math.max(right, box:getRight()), box:getBottom() + spacing
		local paramRight
		paramRight, y = addParameters(row, x, y, height, spacing, options, function(updated, reflow)
			updated.layer = layer
			row.gtEventDraft = updated
			for key, value in pairs(updated) do options[key] = value end
			if reflow then row:rePopulate() else populateChoices() end
			return true
		end)
		right = math.max(right, paramRight)
	end
	row:setWidth(right + border)
	row:setHeight(y + border)
end

-- Keep the XML assignment available as the base. Selecting an event here adds an
-- override for this action without changing the preset's original threshold.
local vanillaBindingCombo = CharacterJoypadBindingUIRow.createJoypadButtonBindingCBox
if vanillaBindingCombo then
	function CharacterJoypadBindingUIRow:createJoypadButtonBindingCBox(input, charBinding, excluded, x, y, width, height)
		local action = Bindings.getActionById("native_" .. tostring(charBinding))
		if action and Bindings.canEdit() and Bindings.canBindIn(action, "world") and BindingEvents.hasInput(input) then
			local hasOverride = false
			for _, binding in ipairs(Bindings.getAssignments(action, "world")) do
				if binding.event ~= "modifier" then hasOverride = true end
			end
			local choices = { native = true }
			if not hasOverride then
				local _, threshold = GamepadTweaks.NativeBindings.rawInput(action)
				for _, event in ipairs(BindingEvents.order) do
					local options = optionsFor(input, { event = event, threshold = threshold }, "press")
					if Bindings.canUseEvent("world", action, options) then choices[event] = options end
				end
			end
			local combo = eventBox(self, x, y, height, "native", true, choices)
			combo:setEnabled(not hasOverride)
			combo:setOnChange(self, function(_, sender)
				local event = sender:getSelectedData()
				if event ~= "native" then saveAssignment(self, nil, choices[event], action) end
			end)
			x = combo:getRight() + self:getStyle().borderSpacing
		end
		return vanillaBindingCombo(self, input, charBinding, excluded, x, y, width, height)
	end
end

local vanillaEditable = CharacterJoypadBindingUIRow.populateWithEditableElements
function CharacterJoypadBindingUIRow:populateWithEditableElements(...)
	if selectedLayer(self) == "world" then
		self.entries = {}
		vanillaEditable(self, ...)
	else
		populateLayerRow(self)
	end
	if supportsEvents(self) then
		local ok, err = pcall(addEditable, self)
		if not ok then log("ERROR: controller editor (edit row): " .. tostring(err)) end
	end
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
