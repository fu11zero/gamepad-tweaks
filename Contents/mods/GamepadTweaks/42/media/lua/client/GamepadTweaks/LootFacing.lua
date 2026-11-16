-- Loot window on the gamepad: select the container the character faces.
--
-- Vanilla (ISInventoryPage:refreshBackpacks): with a gamepad the selected container is just an
-- index, backpackChoice (1 when the window goes from the floor alone to several containers, else
-- what LB/RB last chose). The buttons come square by square from the north-west corner of the
-- 3x3 around the player, so the first one is whatever stands up-left on the screen, e.g. the wall
-- cabinet above the player, while the counter in front is further down the list. The look
-- direction is only used for the mouse, and even there the index wins afterwards.
-- Here: when the loot window opens (Y) or the player turns / steps to another square, the
-- container whose square is closest to the facing direction is selected (containers on the
-- player's own square rank between the front ones and the side ones). LB/RB still cycle, and the
-- choice stays until the player turns or moves again.

require "ISUI/ISInventoryPage"
require "ISUI/ISButtonPrompt"

local OWN_SQUARE_SCORE = 0.3

local function settingOn()
	if not GamepadTweaks_getSetting then return true end
	local ok, v = pcall(GamepadTweaks_getSetting, "interact.lootFacing")
	return not (ok and v and tostring(v):lower() == "false")
end

local function containerSquare(page, inv)
	local parent = page:getContainerParent(inv)
	if parent and parent.getSquare then
		return parent:getSquare(), parent
	end
	return nil, parent
end

local function pickFacing(page)
	local playerObj = getSpecificPlayer(page.player)
	if not playerObj or playerObj:getJoypadBind() == -1 or playerObj:getVehicle() then return end
	if page.forceSelectedContainer then return end
	local fx, fy = playerObj:getForwardDirectionX(), playerObj:getForwardDirectionY()
	local flen = math.sqrt(fx * fx + fy * fy)
	if flen < 0.0001 then return end
	fx, fy = fx / flen, fy / flen
	local px, py = playerObj:getX(), playerObj:getY()
	local own = playerObj:getCurrentSquare()

	local best, bestIndex, bestScore
	for index, button in ipairs(page.backpacks) do
		local inv = button.inventory
		if inv and inv:getType() ~= "floor" then
			local sq, parent = containerSquare(page, inv)
			local locked = instanceof(parent, "IsoThumpable") and parent:isLockedToCharacter(playerObj)
			if sq and not locked then
				local score
				if sq == own then
					score = OWN_SQUARE_SCORE
				else
					local dx, dy = sq:getX() + 0.5 - px, sq:getY() + 0.5 - py
					local len = math.sqrt(dx * dx + dy * dy)
					score = len > 0.0001 and (dx * fx + dy * fy) / len or OWN_SQUARE_SCORE
				end
				-- Several containers on one square (counter and the cabinet above it) keep vanilla order.
				if not bestScore or score > bestScore + 0.001 then
					best, bestIndex, bestScore = button, index, score
				end
			end
		end
	end
	if best and best.inventory ~= page.inventoryPane.inventory then
		page.backpackChoice = bestIndex
		page:selectContainer(best)
	elseif best then
		page.backpackChoice = bestIndex
	end
end

local function install()
	if ISInventoryPage.gtLootFacing then return end
	ISInventoryPage.gtLootFacing = true

	local vanillaRefresh = ISInventoryPage.refreshBackpacks
	ISInventoryPage.refreshBackpacks = function(self, ...)
		local result = vanillaRefresh(self, ...)
		if self.onCharacter or self.gtPicking then return result end
		local playerObj = getSpecificPlayer(self.player)
		if not playerObj or playerObj:getJoypadBind() == -1 or not settingOn() then return result end
		local dir, sq = playerObj:getDir(), playerObj:getCurrentSquare()
		if self.gtPickNow or dir ~= self.gtPickDir or sq ~= self.gtPickSquare then
			self.gtPickNow = nil
			self.gtPickDir, self.gtPickSquare = dir, sq
			self.gtPicking = true
			local ok, err = pcall(pickFacing, self)
			self.gtPicking = nil
			if not ok then print("[GamepadTweaks] loot facing: " .. tostring(err)) end
		end
		return result
	end

	local vanillaShowLoot = ISButtonPrompt.cmdShowLoot
	ISButtonPrompt.cmdShowLoot = function(self, ...)
		local ui = getPlayerLoot(self.player)
		if ui then
			ui.gtPickNow = true
			ui:refreshBackpacks()
		end
		return vanillaShowLoot(self, ...)
	end
end

Events.OnGameStart.Add(install)
