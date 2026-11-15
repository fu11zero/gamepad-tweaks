-- X (InteractOptions) context menu sees fences and walls on the south and east edges.
--
-- The joypad world menu takes its objects from ISButtonPrompt:getInteractOptionsButtonObjects
-- (client/ISUI/ISButtonPrompt.lua): the player's square plus the three squares in front, minus
-- every square behind a non-hoppable wall ("stop grabbing thru walls"). Wall-like objects only
-- live on the north and west edges of a square, so a fence north or west of the player belongs
-- to the player's own square and is in the menu, while the same fence south or east belongs to
-- the square in front, which that check throws away whole. Tall chain-link and metal fences,
-- walls and the like there could not be disassembled (or anything else) from the X menu.
--
-- Here: after the vanilla pass, objects standing on the shared edge of such a square are added
-- back, and only them. The menu code expands any object to its whole square in three places
-- (Java ISWorldObjectContextMenuLogic.fetch via ISWorldObjectContextMenu.fetchSquares, its
-- getAllObjects for the Disassemble and Radio/TV submenus, Lua ISMenuContextWorld
-- getObjectsSquare); while the X menu is built those squares are kept unexpanded, so the room
-- behind a wall stays out of the menu as before.

GamepadTweaks = GamepadTweaks or {}
local WallEdge = {}
GamepadTweaks.WallEdge = WallEdge

-- [playerNum] = { squares = {[square] = true}, objects = {[object] = true} } from the last X pass
local edges = {}
-- [playerNum] = true while that player's X menu (or its test pass) is being built
local armed = {}

local NORTH_FLAGS = { "collideN", "WallN", "WindowN", "windowN", "doorN", "DoorWallN", "HoppableN", "TallHoppableN", "cutN", "WallNW" }
local WEST_FLAGS = { "collideW", "WallW", "WindowW", "windowW", "doorW", "DoorWallW", "HoppableW", "TallHoppableW", "cutW", "WallNW" }

local function onEdge(obj, north)
	-- Furniture standing against the far side of the wall is not part of the edge.
	if obj:getContainer() then return false end
	local props = obj:getProperties()
	if props then
		for _, name in ipairs(north and NORTH_FLAGS or WEST_FLAGS) do
			local flag = IsoFlagType[name]
			if flag and props:has(flag) then return true end
		end
	end
	-- Player-built fences and walls, doors and windows carry their side themselves.
	if (instanceof(obj, "IsoThumpable") or instanceof(obj, "IsoDoor") or instanceof(obj, "IsoWindow"))
			and obj:isNorth() == north then
		return true
	end
	return false
end

local function frontSquares(square, dir)
	local cell, x, y, z = getCell(), square:getX(), square:getY(), square:getZ()
	local d = {
		[IsoDirections.N] = { -1, -1, 0, -1, 1, -1 },
		[IsoDirections.NE] = { 0, -1, 1, -1, 1, 0 },
		[IsoDirections.E] = { 1, -1, 1, 0, 1, 1 },
		[IsoDirections.SE] = { 1, 0, 1, 1, 0, 1 },
		[IsoDirections.S] = { 1, 1, 0, 1, -1, 1 },
		[IsoDirections.SW] = { 0, 1, -1, 1, -1, 0 },
		[IsoDirections.W] = { -1, 1, -1, 0, -1, -1 },
		[IsoDirections.NW] = { -1, 0, -1, -1, 0, -1 },
	}
	local o = d[dir]
	if not o then return {} end
	return {
		cell:getGridSquare(x + o[1], y + o[2], z),
		cell:getGridSquare(x + o[3], y + o[4], z),
		cell:getGridSquare(x + o[5], y + o[6], z),
	}
end

-- Edge objects of the squares south/east of the player that the vanilla wall check dropped.
local function collect(playerObj, dir)
	local square = playerObj:getCurrentSquare()
	if not square then return nil end
	dir = dir or playerObj:getDir()
	local found
	for _, gs in ipairs(frontSquares(square, dir)) do
		if gs and square:isWallTo(gs) and not square:isHoppableTo(gs) then
			local dx, dy = gs:getX() - square:getX(), gs:getY() - square:getY()
			-- Only a square directly south (its north edge) or directly east (its west edge)
			-- owns the edge between it and the player.
			local north = dx == 0 and dy == 1
			local west = dx == 1 and dy == 0
			if north or west then
				local objs = gs:getObjects()
				for i = 0, objs:size() - 1 do
					local obj = objs:get(i)
					if onEdge(obj, north) then
						found = found or { squares = {}, objects = {}, list = {} }
						found.squares[gs] = true
						found.objects[obj] = true
						table.insert(found.list, obj)
					end
				end
			end
		end
	end
	return found
end

local function withArmed(playerNum, fn, ...)
	local prev = armed[playerNum]
	armed[playerNum] = true
	local ok, a = pcall(fn, ...)
	armed[playerNum] = prev
	if not ok then error(a) end
	return a
end

local function activeEdge(playerNum)
	if playerNum and armed[playerNum] then return edges[playerNum] end
	return nil
end

-- Drops objects of edge-only squares that are not the edge objects themselves.
local function filterObjects(worldObjects, edge)
	local out = {}
	for _, obj in ipairs(worldObjects) do
		local sq = obj:getSquare()
		if not (sq and edge.squares[sq]) or edge.objects[obj] then
			table.insert(out, obj)
		end
	end
	return out
end

local function wrapSubmenu(tbl)
	if not tbl or tbl.gtWallEdge then return end
	local vanilla = tbl.createMenu
	tbl.gtWallEdge = true
	tbl.createMenu = function(worldObjects, context, playerObj, ...)
		local edge = playerObj and activeEdge(playerObj:getPlayerNum())
		if edge and worldObjects then
			worldObjects = filterObjects(worldObjects, edge)
		end
		return vanilla(worldObjects, context, playerObj, ...)
	end
end

local currentMenuPlayer

local function install()
	if not ISButtonPrompt or ISButtonPrompt.gtWallEdge then return end
	ISButtonPrompt.gtWallEdge = true

	local vanillaObjects = ISButtonPrompt.getInteractOptionsButtonObjects
	ISButtonPrompt.getInteractOptionsButtonObjects = function(self, dir, ...)
		local playerNum = self.player
		edges[playerNum] = nil
		local result = vanillaObjects(self, dir, ...)
		local playerObj = playerNum and getSpecificPlayer(playerNum)
		if not playerObj or not self.list then return result end
		local ok, found = pcall(collect, playerObj, dir)
		if not ok then
			print("[GamepadTweaks] WallEdge: " .. tostring(found))
			return result
		end
		if not found then return result end
		edges[playerNum] = found
		-- self.list is the vanilla list; it is filled even when the vanilla test found nothing.
		for _, obj in ipairs(found.list) do
			self.list:add(obj)
		end
		local hit = withArmed(playerNum, ISContextManager.getInstance().createWorldMenu,
			playerNum, nil, self.list.items, 0, 0, true)
		if hit then return self.list end
		return result
	end

	local vanillaInteract = ISButtonPrompt.interact
	ISButtonPrompt.interact = function(self, ...)
		return withArmed(self.player, vanillaInteract, self, ...)
	end

	-- Java fetch expands a square once per menu, remembered in fetchSquares; mark ours as done.
	local vanillaCreate = ISWorldObjectContextMenu.createMenu
	ISWorldObjectContextMenu.createMenu = function(player, ...)
		local prev = currentMenuPlayer
		currentMenuPlayer = player
		local ok, a, b = pcall(vanillaCreate, player, ...)
		currentMenuPlayer = prev
		if not ok then error(a) end
		return a, b
	end
	local vanillaClear = ISWorldObjectContextMenu.clearFetch
	ISWorldObjectContextMenu.clearFetch = function(...)
		local r = vanillaClear(...)
		local edge = activeEdge(currentMenuPlayer)
		if edge then
			for sq in pairs(edge.squares) do
				ISWorldObjectContextMenu.fetchSquares[sq] = true
			end
		end
		return r
	end

	-- Lua side: ISMenuContextWorld.getAllObjects -> self.getObjectsSquare.
	local menuWorld = ISContextManager.getInstance().getWorldMenu()
	if menuWorld and menuWorld.getObjectsSquare and not menuWorld.gtWallEdge then
		menuWorld.gtWallEdge = true
		local vanillaSquare = menuWorld.getObjectsSquare
		menuWorld.getObjectsSquare = function(data, sq, ...)
			local edge = data and activeEdge(data.playerNum)
			if edge and sq and edge.squares[sq] then return end
			return vanillaSquare(data, sq, ...)
		end
	end

	-- Java getAllObjects feeds these two whole squares.
	wrapSubmenu(ISDisassembleMenu)
	wrapSubmenu(ISRadioAndTvMenu)
end

-- After vanilla's OnGameStart (ISContextManager init creates the world menu).
Events.OnGameStart.Add(install)
