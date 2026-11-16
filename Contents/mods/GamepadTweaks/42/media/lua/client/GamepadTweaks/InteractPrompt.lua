-- One Interact press does one thing (see InteractTarget.java).
--
-- Vanilla runs two pickers on the same press: the Lua prompt (ISButtonPrompt
-- getBestInteractButtonAction / testInteractButtonAction) acts on press for light switches,
-- stoves, radios and crafting entities, and the Java poll (IsoPlayer.doContext) acts on release
-- for doors, windows, furniture. Facing diagonally the prompt walks the two sides in a fixed
-- order and stops at the first thing it finds, so a light switch on the player's square (an
-- EXIT lamp above the door) won over the door on the other side, while Java opened the door:
-- the lamp toggled and the door opened.
-- Here:
-- - an open door the player came through just now (behind it) is offered first, as
--   InteractTarget.pick closes it before anything ahead;
-- - the prompt looks for a door / window on every facing side (the side faced more first)
--   before anything else, as doContext does, so with a door ahead it says the door;
-- - when one of the prompt's own handlers runs, the press is marked handled and the Java side
--   skips doContext on its release (GamepadTweaks_interactHandled).

require "ISUI/ISButtonPrompt"

local function settingOn(key)
	if not GamepadTweaks_getSetting then return true end
	local ok, v = pcall(GamepadTweaks_getSetting, key)
	return not (ok and v and tostring(v):lower() == "false")
end

local SIDES = {
	[IsoDirections.NE] = { IsoDirections.N, IsoDirections.E },
	[IsoDirections.SE] = { IsoDirections.S, IsoDirections.E },
	[IsoDirections.SW] = { IsoDirections.S, IsoDirections.W },
	[IsoDirections.NW] = { IsoDirections.N, IsoDirections.W },
}

local function sidesByFacing(playerObj, dir)
	local sides = SIDES[dir]
	if not sides then return { dir } end
	local a, b = sides[1], sides[2]
	local fx, fy = playerObj:getForwardDirectionX(), playerObj:getForwardDirectionY()
	local da = a:dx() * fx + a:dy() * fy
	local db = b:dx() * fx + b:dy() * fy
	if db > da then return { b, a } end
	return { a, b }
end

local function install()
	if ISButtonPrompt.gtInteractPrompt then return end
	ISButtonPrompt.gtInteractPrompt = true

	local vanillaBest = ISButtonPrompt.getBestInteractButtonAction
	ISButtonPrompt.getBestInteractButtonAction = function(self, dir, ...)
		local playerObj = getSpecificPlayer(self.player)
		if playerObj and dir and not self.aPrompt and playerObj:getJoypadBind() ~= -1
				and not playerObj:getVehicle() and not playerObj:getIgnoreMovement()
				and not playerObj:isAsleep() then
			-- The door just walked through is closed before anything ahead (InteractTarget.pick).
			if GamepadTweaks_interactRecentDoor then
				local ok, side = pcall(GamepadTweaks_interactRecentDoor, playerObj)
				local obj = ok and side and playerObj:getContextDoorOrWindowOrWindowFrame(side)
				if obj then
					self:doInteractButtonDoorOrWindowOrWindowFrame(side, obj)
					if self.aPrompt then return end
				end
			end
		end
		if playerObj and dir and not self.aPrompt and playerObj:getJoypadBind() ~= -1
				and not playerObj:getVehicle() and not playerObj:getIgnoreMovement()
				and not playerObj:isAsleep() and settingOn("interact.facing") then
			for _, side in ipairs(sidesByFacing(playerObj, dir)) do
				local obj = playerObj:getContextDoorOrWindowOrWindowFrame(side)
				if obj then
					self:doInteractButtonDoorOrWindowOrWindowFrame(side, obj)
					if self.aPrompt then return end
				end
			end
		end
		return vanillaBest(self, dir, ...)
	end

	-- The prompt's own handlers (doors and windows have none: Java does them).
	for _, name in ipairs({ "cmdToggleLight", "cmdToggleStove", "openDeviceOptions", "openEntityUI" }) do
		local vanilla = ISButtonPrompt[name]
		if vanilla then
			ISButtonPrompt[name] = function(self, ...)
				if GamepadTweaks_interactHandled and type(self) == "table" and self.player then
					pcall(GamepadTweaks_interactHandled, self.player)
				end
				return vanilla(self, ...)
			end
		end
	end
end

Events.OnGameStart.Add(install)
