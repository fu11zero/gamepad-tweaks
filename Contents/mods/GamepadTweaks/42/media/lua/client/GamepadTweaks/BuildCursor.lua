-- A confirms world cursors again (42.22 regression).
--
-- Cursors derived from ISBuildingObject (chop tree, disassemble, extinguish, paint, rake dung,
-- scythe grass, place item, crafting build, traps, campfire, farm plot...) are confirmed in
-- DoTileBuilding (server/BuildingObjects/ISBuildingObject.lua) once draggingItem.build is set.
-- In 42.21 it was set by playerObj:isBuildButtonReleased() for every input, the gamepad
-- included (Interact released). 42.22 put that under "not a joypad player" and gave the joypad
-- nothing instead: DoTileBuildingJoyPad only renders, ISBuildingObject:onJoypadPressButton
-- handles B/Y/LB/RB but not A, and the cursors pass A straight to it. So the cursor shows
-- "A: Chop Tree" and A does nothing. ISMoveableCursor handles A itself and is not affected.
-- Here: A on such a cursor sets build when the square is valid; the next DoTileBuilding pass
-- (rendered every frame for the joypad cursor) calls tryBuild at the cursor's square.

local function install()
	if not ISBuildingObject or ISBuildingObject.gtBuildConfirm then return end
	local vanilla = ISBuildingObject.onJoypadPressButton
	ISBuildingObject.gtBuildConfirm = true
	ISBuildingObject.onJoypadPressButton = function(self, joypadIndex, joypadData, button, ...)
		if button == Joypad.AButton and self.canBeBuild and not self.build then
			self.build = true
		end
		return vanilla(self, joypadIndex, joypadData, button, ...)
	end
end

-- ISBuildingObject is in media/lua/server, loaded after the client files.
Events.OnGameStart.Add(install)
