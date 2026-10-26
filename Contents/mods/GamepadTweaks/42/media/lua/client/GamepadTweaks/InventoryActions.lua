-- Inventory and loot window actions for the gamepad (Bindings.lua, inventory layer).
--
-- With a mouse these are one click: the buttons above the item list (Transfer All, Loot All,
-- same type, to nearby containers, Move to Floor; ISInventoryWindowContainerControls,
-- ISLootWindowContainerControls), Drop by dragging to the floor, the double-click action
-- (ISInventoryPane:doContextualDblClick), Unpack. With a gamepad vanilla has
-- A -> context menu -> scroll, and the button handlers above add no context menu option
-- (handleJoypadContextMenu is empty in all but Remove All and the appliance toggles), so
-- "same type", "nearby containers" and "move to floor" can't be done at all; Drop and Unpack
-- are left out of the gamepad menu (getJoypadBind() == -1 checks; Move To -> Floor /
-- Inventory instead).
-- Each action here does what the mouse does, on the window that has the joypad focus and
-- its selected row (header = the whole stack, item row = that item, as vanilla X does).
-- All unbound by default: bind.<id>=<button> (Options -> Controller or Steam Input). A bound
-- button does the action instead of what vanilla does with it in the window.

require "GamepadTweaks/Bindings"
require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/InventoryWindow/ISInventoryWindowContainerControls"
require "ISUI/LootWindow/ISLootWindowContainerControls"

local Bindings = GamepadTweaks.Bindings

-- The focused inventory/loot window and its player, when it can act.
local function focusedPage(jd)
	local page = jd.focus
	if type(page) ~= "table" or page.Type ~= "ISInventoryPage" or not page.inventoryPane then return nil end
	local playerObj = jd.player and getSpecificPlayer(jd.player)
	if not playerObj or playerObj:isDead() or playerObj:isAsleep() or isGamePaused() then return nil end
	if JoypadState.disableInvInteraction or getCore():getGameMode() == "Tutorial" then return nil end
	return page, playerObj
end

local function pageAction(fn)
	return function(c, jd)
		local page, playerObj = focusedPage(jd)
		if page then
			fn(page, playerObj, page.player)
		end
	end
end

-- Selected row --------------------------------------------------------------------------
-- ISInventoryPane.items: stack headers ({ name, items = { dummy, item1, ... } }) and, under
-- an expanded header, its InventoryItems.

local function selectedRow(pane)
	if not pane.doController or not pane.joyselection or not pane.items then return nil end
	return pane.items[pane.joyselection + 1], pane.joyselection + 1
end

-- The stack header of a row (itself, or the header above an item row).
local function headerOf(pane, index)
	for i = index, 1, -1 do
		local row = pane.items[i]
		if not instanceof(row, "InventoryItem") then return row end
	end
	return nil
end

-- mode: nil = as vanilla X (header: the stack, item row: the item), "stack", "one".
local function selectedItems(pane, mode)
	local row, index = selectedRow(pane)
	if not row then return {} end
	if mode == "stack" then
		row = headerOf(pane, index) or row
	elseif mode == "one" and not instanceof(row, "InventoryItem") then
		row = row.items[2]
		if not row then return {} end
	end
	return ISInventoryPane.getActualItems({ row })
end

-- Items -----------------------------------------------------------------------------------

-- X in the window, for the given items: inventory -> the loot container, loot -> inventory.
local function transfer(page, items, playerNum)
	if #items == 0 then return end
	if page.onCharacter then
		ISInventoryPaneContextMenu.onPutItems(items, playerNum)
	else
		ISInventoryPaneContextMenu.onGrabItems(items, playerNum)
	end
end

local function isFloor(container)
	return container and container:getType() == "floor"
end

-- Same filter as ISInventoryPane:transferAll: not equipped or worn, not in the hotbar, not a
-- favorite, not a key ring of the main inventory.
local function canLeave(item, playerObj, playerNum, pane)
	if item:isEquipped() or item:isFavorite() then return false end
	local hotbar = getPlayerHotbar(playerNum)
	if hotbar and hotbar:isInHotbar(item) then return false end
	if pane.inventory == playerObj:getInventory()
			and (item:isItemType(ItemType.KEY_RING) or item:hasTag(ItemTag.KEY_RING)) then
		return false
	end
	return true
end

-- Container button handlers -------------------------------------------------------------

-- The window's button handler of that class, if its button would be shown now.
local function lootHandler(page, objectClass, floorClass)
	local controls = page.controlsUI
	if not controls or not controls.getDisplayedContainer then return nil end
	local container = controls:getDisplayedContainer()
	if not container then return nil end
	local object = controls:getDisplayedObject()
	local class = object and objectClass or (isFloor(container) and floorClass) or nil
	if not class then return nil end
	local handler = controls:checkHandler(class, object, container)
	return handler:shouldBeVisible() and handler or nil
end

local function inventoryHandler(playerNum, class)
	local page = getPlayerInventory(playerNum)
	local controls = page and page.controlsUI
	if not controls or not controls.getDisplayedContainer then return nil end
	local container = controls:getDisplayedContainer()
	if not container then return nil end
	local handler = controls:checkHandler(class, container)
	return handler:shouldBeVisible() and handler or nil
end

-- Actions ---------------------------------------------------------------------------------

-- Transfer All (inventory) / Loot All (loot).
local function transferAll(page)
	if page.onCharacter then
		page:transferAll()
	else
		page:lootAll()
	end
end

-- The "same type" button: items of a type that is on both sides go to the other side.
local function transferSameType(page, playerObj, playerNum)
	local handler
	if page.onCharacter then
		handler = inventoryHandler(playerNum, ISInventoryWindowControlHandler_TransferSameType)
	else
		handler = lootHandler(page, ISLootWindowObjectControlHandler_TakeSameType, ISLootWindowFloorControlHandler_TakeSameType)
	end
	if handler then handler:perform() end
end

-- The inventory's "same type to nearby containers" button, from either window.
local function transferSameTypeNearby(page, playerObj, playerNum)
	local handler = inventoryHandler(playerNum, ISInventoryWindowControlHandler_TransferSameTypeMultiContainer)
	if handler then handler:perform() end
end

-- Loot: the Move to Floor button. Inventory: the shown bag / main inventory, what Transfer
-- All would move.
local function allToFloor(page, playerObj, playerNum)
	if not page.onCharacter then
		local handler = lootHandler(page, ISLootWindowObjectControlHandler_MoveToFloor, nil)
		if handler then handler:perform() end
		return
	end
	local pane = page.inventoryPane
	local items = {}
	local list = pane.inventory:getItems()
	for i = 0, list:size() - 1 do
		local item = list:get(i)
		if canLeave(item, playerObj, playerNum, pane) then
			table.insert(items, item)
		end
	end
	if #items > 0 then
		ISInventoryPaneContextMenu.onDropItems(items, playerNum)
	end
end

-- Drop (inventory) / Move To -> Floor (loot), for the selected row; favorites stay.
local function dropSelected(page, playerObj, playerNum)
	if isFloor(page.inventoryPane.inventory) then return end
	local items = selectedItems(page.inventoryPane)
	if #items > 0 then
		ISInventoryPaneContextMenu.onDropItems(items, playerNum)
	end
end

-- X for the whole stack, also on an item row of an expanded stack.
local function transferStack(page, playerObj, playerNum)
	transfer(page, selectedItems(page.inventoryPane, "stack"), playerNum)
end

-- X for one item, also on the header of a collapsed stack.
local function transferOne(page, playerObj, playerNum)
	transfer(page, selectedItems(page.inventoryPane, "one"), playerNum)
end

-- The double click: inventory -> equip / wear / eat... (doContextualDblClick), loot -> take.
local function use(page, playerObj, playerNum)
	local pane = page.inventoryPane
	local items = selectedItems(pane, "one")
	if #items == 0 then return end
	if page.onCharacter then
		pane:doContextualDblClick(items[1])
	else
		transfer(page, items, playerNum)
	end
end

-- Unpack: the selected items from a bag to the main inventory (mouse menu; gamepad: Move To ->
-- Inventory).
local function unpack(page, playerObj, playerNum)
	if not page.onCharacter then return end
	local items = selectedItems(page.inventoryPane)
	if #items > 0 and ISInventoryPaneContextMenu.canUnpack(items, playerNum) then
		ISInventoryPaneContextMenu.onMoveItemsTo(items, playerObj:getInventory(), playerNum)
	end
end

local ACTIONS = {
	{ id = "invTransferAll", run = pageAction(transferAll) },
	{ id = "invTransferSameType", run = pageAction(transferSameType) },
	{ id = "invTransferSameTypeNearby", run = pageAction(transferSameTypeNearby) },
	{ id = "invAllToFloor", run = pageAction(allToFloor) },
	{ id = "invDropSelected", run = pageAction(dropSelected) },
	{ id = "invTransferStack", run = pageAction(transferStack) },
	{ id = "invTransferOne", run = pageAction(transferOne) },
	{ id = "invUse", run = pageAction(use) },
	{ id = "invUnpack", run = pageAction(unpack) },
}

for _, action in ipairs(ACTIONS) do
	action.layer = "inventory"
	action.category = "inventory"
	action.group = "main"
	Bindings.add(action)
end

-- Dispatch ----------------------------------------------------------------------------------
-- Vanilla gives the focused window its presses as onJoypadDown(button) and the D-pad as
-- onJoypadDir*; a button with an inventory action runs it instead.

local function wrapPress(name)
	local vanillaFn = ISInventoryPage[name]
	ISInventoryPage[name] = function(self, button, jd, ...)
		jd = type(jd) == "table" and jd or JoypadState.players[self.player + 1]
		if jd and Bindings.press(jd, button, "inventory") then return end
		return vanillaFn(self, button, jd, ...)
	end
end

wrapPress("onJoypadDown")

local function wrapDir(name, button)
	local vanillaFn = ISInventoryPage[name]
	ISInventoryPage[name] = function(self, jd, ...)
		if type(jd) == "table" and Bindings.press(jd, button, "inventory") then return end
		return vanillaFn(self, jd, ...)
	end
end

wrapDir("onJoypadDirUp", Joypad.DPadUp)
wrapDir("onJoypadDirDown", Joypad.DPadDown)
wrapDir("onJoypadDirLeft", Joypad.DPadLeft)
wrapDir("onJoypadDirRight", Joypad.DPadRight)
