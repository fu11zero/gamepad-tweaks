-- Controller vibration: picks the game events and sends pulses to Java (Rumble.java), which
-- mixes them and drives the motors through Steam Input. Vanilla has no vibration.
--
-- GamepadTweaks_rumble(controller, event, low, high, trigger, ms): controller = the player's
-- joypad (player:getJoypadBind()), event = the rumble.<event> strength setting, low / high = the
-- big / small motor, trigger = the right trigger motor, 0..1 each; the pulse fades out over ms.

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

local function onTick()
	if not available() then return end
	local now = getTimestampMs()
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

Events.OnWeaponSwingHitPoint.Add(onSwingHitPoint)
Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.OnTick.Add(onTick)

return Rumble
