-- Controller vibration: picks the game events and sends pulses to Java (Rumble.java), which
-- mixes them and drives the motors through Steam Input. Vanilla has no vibration.
-- Events Lua can't see (vehicle crashes, action states like falls and bumps, windows, zombies
-- banging) are in RumbleEvents.java.
--
-- GamepadTweaks_rumble(controller, event, low, high, trigger, ms): controller = the player's
-- joypad (player:getJoypadBind()), event = the rumble.<event> strength setting, low / high = the
-- big / small motor, trigger = the right trigger motor, 0..1 each; the pulse fades out over ms.

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISChopTreeAction"
require "TimedActions/ISUnbarricadeAction"
require "TimedActions/ISForceOpen"

local Rumble = {}
GamepadTweaks = GamepadTweaks or {}
GamepadTweaks.Rumble = Rumble

local function clamp(v)
	if v < 0 then return 0 end
	if v > 1 then return 1 end
	return v
end

-- The joypad of a local player controlled by one, or nil.
local function joypadOf(player)
	if not player or not instanceof(player, "IsoPlayer") or not player:isLocalPlayer() then return nil end
	local id = player:getJoypadBind()
	if id == nil or id < 0 then return nil end
	return id
end

local function pulse(player, event, low, high, trigger, ms)
	local id = joypadOf(player)
	if id then
		GamepadTweaks_rumble(id, event, clamp(low), clamp(high), clamp(trigger), ms)
	end
end

local function available()
	return GamepadTweaks_rumbleAvailable ~= nil and GamepadTweaks_rumbleAvailable()
end

-- Firing a gun: the moment the shot goes off (CombatManager.attackCollisionCheck, which also
-- runs for melee swings). A dry fire (no round) goes through the same swing with
-- isRangedWeaponEmpty set by ISReloadWeaponAction.attackHook. The kick comes from the gun's
-- sound radius: cap gun 30, pistols 60-120, rifles 150-170, shotguns 200.
local function onSwingHitPoint(player, weapon)
	if not weapon or not weapon:isRanged() or not joypadOf(player) or not available() then return end
	if player:isRangedWeaponEmpty() then return end
	local k = clamp((weapon:getSoundRadius() - 30) / 170)
	pulse(player, "shot", 0.25 + 0.75 * k, 0.6 + 0.4 * k, 0.5 + 0.5 * k, 80 + 140 * k)
end

-- Melee hit on a character (IsoGameCharacter.Hit): stronger with damage (about 0.2..3).
-- Shots are felt on firing already.
local function onWeaponHitCharacter(attacker, target, weapon, damage)
	if not weapon or weapon:isRanged() or not joypadOf(attacker) or not available() then return end
	local k = clamp((damage or 0) / 2)
	pulse(attacker, "hit", 0.2 + 0.5 * k, 0.5 + 0.4 * k, 0, 70 + 80 * k)
end

-- Health and panic, per local player: health lost in one tick (zombie bite or scratch, fall,
-- car crash, fire...; bleeding and hunger take far less than the threshold per tick), and a
-- heartbeat while panicked.
local DAMAGE_MIN = 0.5
local state = {} -- [playerNum] = { player, health, nextBeat }

local function heartbeat(player, s, now)
	local level = player:getMoodles():getMoodleLevel(MoodleType.PANIC)
	if level < 2 then
		s.nextBeat = nil
		return
	end
	if s.nextBeat and now < s.nextBeat then return end
	-- panic 2..4: 70..110 bpm feel, stronger with the level
	local period = ({ [2] = 850, [3] = 680, [4] = 540 })[level] or 540
	local k = 0.35 + 0.2 * (level - 2)
	if s.nextBeat == nil then s.nextBeat = now end
	s.nextBeat = s.nextBeat + period
	if s.nextBeat < now then s.nextBeat = now + period end
	-- "lub" now, "dub" 150 ms later
	pulse(player, "heartbeat", k, 0, 0, 110)
	s.dub = now + 150
	s.dubK = k * 0.7
end

-- Thunder: OnThunderEvent(x, y, strike, lightning, rumble) comes with the flash, the sound
-- dist / 300 s later (ThunderStorm.enqueueThunderEvent: soundDelay = dist / 300 * 60 frames),
-- and the vibration with the sound. strike = a crack, rumble = a long low roll; indoors half.
-- None at fast forward, where vanilla plays no thunder either.
local thunder = {} -- { at, player, low, high, ms }

local function onThunder(x, y, strike, light, roll)
	if not available() then return end
	local speed = UIManager.getSpeedControls() and UIManager.getSpeedControls():getCurrentGameSpeed() or 1
	if speed > 1 then return end
	local now = getTimestampMs()
	for i = 0, getMaxActivePlayers() - 1 do
		local player = getSpecificPlayer(i)
		if player and joypadOf(player) and not player:isDead() then
			local dx, dy = player:getX() - x, player:getY() - y
			local dist = math.sqrt(dx * dx + dy * dy)
			local indoor = player:getCurrentSquare() and not player:getCurrentSquare():isOutside()
			local m = indoor and 0.5 or 1
			local at = now + dist / 300 * 1000
			if strike then
				local k = clamp(1 - dist / 2500) * m
				if k > 0.05 then
					table.insert(thunder, { at = at, player = player, low = 0.4 + 0.6 * k, high = 0.6 * k, ms = 300 + 500 * k })
				end
			end
			if roll then
				local k = clamp(1 - dist / 5000) * m
				if k > 0.05 then
					table.insert(thunder, { at = at, player = player, low = 0.15 + 0.35 * k, high = 0, ms = 1200 + 1300 * k })
				end
			end
		end
	end
end

local function thunderTick(now)
	for i = #thunder, 1, -1 do
		local t = thunder[i]
		if now >= t.at then
			table.remove(thunder, i)
			if not t.player:isDead() then
				pulse(t.player, "thunder", t.low, t.high, 0, t.ms)
			end
		elseif now < t.at - 60000 then
			table.remove(thunder, i) -- clock jumped
		end
	end
end

local function onTick()
	if not available() then
		thunder = {}
		return
	end
	local now = getTimestampMs()
	thunderTick(now)
	for i = 0, getMaxActivePlayers() - 1 do
		local player = getSpecificPlayer(i)
		if player and joypadOf(player) and not player:isDead() then
			local s = state[i]
			if not s or s.player ~= player then
				s = { player = player }
				state[i] = s
			end
			local health = player:getBodyDamage():getHealth()
			if s.health and s.health - health >= DAMAGE_MIN then
				local d = s.health - health
				pulse(player, "damage", 0.4 + d / 15, 0.3 + d / 20, 0, 150 + math.min(300, d * 20))
			end
			s.health = health
			if s.dub and now >= s.dub then
				pulse(player, "heartbeat", s.dubK, 0, 0, 90)
				s.dub = nil
			end
			heartbeat(player, s, now)
		else
			state[i] = nil
		end
	end
end


-- Burns: standing in fire takes health in small steps (under the per-tick damage threshold) and
-- vanilla shows no reaction at all, so OnPlayerGetDamage "FIRE" (IsoGameCharacter, every tick
-- while burning) shakes the controller in uneven bursts.
local lastBurn = {} -- [player] = time

local function onPlayerGetDamage(player, kind, amount)
	if kind ~= "FIRE" or not joypadOf(player) or not available() then return end
	local now = getTimestampMs()
	if lastBurn[player] and now - lastBurn[player] < 250 then return end
	lastBurn[player] = now
	local k = 0.6 + 0.4 * ZombRandFloat(0, 1)
	pulse(player, "damage", 0.45 * k, 0.55 * k, 0, 220)
end

-- Tools and blows on objects.
-- A weapon hitting a door, window, barricade or wall (OnWeaponHitThumpable from IsoDoor /
-- IsoThumpable / IsoWindow / IsoBarricade WeaponHit): by the weapon's damage (axe ~2..3).
local function onWeaponHitThumpable(character, weapon, object)
	if not joypadOf(character) or not available() then return end
	local k = clamp(((weapon and weapon:getMaxDamage()) or 0.5) / 3)
	pulse(character, "tool", 0.4 + 0.5 * k, 0.35 + 0.3 * k, 0, 140 + 80 * k)
end

-- An axe in a tree: OnWeaponHitTree (a hit while attacking) and ISChopTreeAction's ChopTree anim
-- event (chopping, also on an MP client, where the action doesn't fire the event).
local function treeHit(character)
	if not joypadOf(character) or not available() then return end
	pulse(character, "tool", 0.55, 0.45, 0, 180)
end

local function onWeaponHitTree(character, weapon)
	treeHit(character)
end

local chopAnimEvent = ISChopTreeAction.animEvent
function ISChopTreeAction:animEvent(event, parameter)
	if event == "ChopTree" and self.axe then treeHit(self.character) end
	return chopAnimEvent(self, event, parameter)
end

-- Prying boards / metal off a window or door (ISUnbarricadeAction): a creaking strain now and
-- then while it goes, a pop when it comes off.
local unbarricadeUpdate = ISUnbarricadeAction.update
function ISUnbarricadeAction:update()
	local now = getTimestampMs()
	if available() and joypadOf(self.character) and (not self.nextCreak or now >= self.nextCreak) then
		if self.nextCreak then
			local k = 0.6 + 0.4 * ZombRandFloat(0, 1)
			pulse(self.character, "tool", 0.25 * k, 0.2 * k, 0, 160)
		end
		self.nextCreak = now + 500 + ZombRand(500)
	end
	return unbarricadeUpdate(self)
end

local unbarricadePerform = ISUnbarricadeAction.perform
function ISUnbarricadeAction:perform()
	if available() then pulse(self.character, "tool", 0.65, 0.6, 0, 240) end
	return unbarricadePerform(self)
end

-- Forcing a locked door or window with a crowbar (ISForceOpen): each try (ForceOpenAttempt anim
-- event) strains, success (perform) gives way.
local forceAnimEvent = ISForceOpen.animEvent
function ISForceOpen:animEvent(event, parameter)
	if event == "ForceOpenAttempt" and available() then
		pulse(self.character, "tool", 0.45, 0.35, 0, 200)
	end
	return forceAnimEvent(self, event, parameter)
end

local forcePerform = ISForceOpen.perform
function ISForceOpen:perform()
	if available() then pulse(self.character, "tool", 0.75, 0.6, 0, 280) end
	return forcePerform(self)
end

Events.OnWeaponSwingHitPoint.Add(onSwingHitPoint)
Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.OnTick.Add(onTick)
Events.OnThunderEvent.Add(onThunder)
Events.OnPlayerGetDamage.Add(onPlayerGetDamage)
Events.OnWeaponHitThumpable.Add(onWeaponHitThumpable)
Events.OnWeaponHitTree.Add(onWeaponHitTree)

return Rumble
