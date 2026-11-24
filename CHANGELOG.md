# Changelog

Player-facing change notes, newest first. Each section is copied as is into the Steam Workshop
change notes when the mod is updated. Keep it in English, short, one line per change.

## Unreleased

- Fixed: controller action lists offer new bindings by context and use plain action names beside their icons.
- Added: action icons on controller binding rows and in action lists, matching their Steam Input symbols.
- Added: context layers in Options -> Controller, so a button can use different mod actions on foot, in a vehicle, while aiming or in a panel.

- Added: two knocks on the active controller when the loading screen is ready and asks you to press A.
- Added: hitting curbs and parking stops kicks the controller per wheel, with longer and stronger kicks at higher speeds.
- Added: shivering from hypothermia, from occasional reminders to a gentle sustained tremor at the highest level.
- Added: distinct vibration synced to cough and sneeze sounds, softer when muffled, with shivering continuing between symptoms.
- Added: a deep, fading rumble with the blast when the power grid shuts down.
- Fixed: heartbeat vibration follows the game's live heartbeat audio, including its rhythm and volume.
- Changed: the lingering throb after a scratch, cut or bite follows the damage vibration setting.

## Update: 23 Nov @ 1:58am

- Fixed: A and B no longer get swallowed when navigating submenus — the delayed-press suppression is now armed only when a context menu actually closes.
- Fixed: the Steam Aim action now puts the reticle in front of the character with the stick released, like a light RT press, instead of at the character's center and turning him towards it.

## Update: 21 Nov @ 9:25am

- Fixed: closing a context menu with A or B no longer sends that button into the inventory again on Steam's delayed press (hold / double-click bindings on the same button).
- Fixed: Transfer All / Loot All works with a controller again.

## Update: 16 Nov @ 11:58pm

- Changed: easy driving now only steers: the stick points where to go, the triggers stay the gas and the brake (dosing the gas with a stick was hard at low speed). Backing up (LT at a stop) the wheel points the rear at the stick. The old stick gas is an option: "Easy driving: the stick is the gas too".

## Update: 16 Nov @ 11:39pm

- Fixed: A no longer opens a door or window behind the character (vanilla preferred a window behind over the sofa in front, and opened it when nothing was in front). Behind, A only closes an open door: when nothing is in front, or first thing for 3 s after walking through it (A to open, A to close behind you).
- Changed: facing diagonally, A uses the side the character faces more, not a door or window on the other side.
- Fixed: A on a cursor (place or pick up furniture, chop, disassemble, build) no longer also sits on the sofa or opens the window next to the character.
- Fixed: a light switch or lamp next to a door (EXIT sign) no longer toggles together with the door: one press does what the prompt says, and a door ahead comes before the lamp.
- Changed: the loot window (Y) opens on the container the character faces, not the first one around (the cabinet up-left on the screen). Re-picked when you turn or step; LB/RB still cycle.
- Fixed: half RT without the aim stick no longer slowly turns the character towards the top of the screen (melee, unarmed).

## Update: 16 Nov @ 6:08pm

- Added: easy driving, per splitscreen player (off by default, Options -> Mods): the left stick points where to go on the screen, its deflection is the gas; pointing behind the car reverses. For players new to driving. Servers can forbid it with a sandbox option.
- Added: a separate gas curve for pedals on a stick (easy driving, Steam "Steer + pedals"), default 2: finer at small deflections than the trigger curve.
- Added: analog gas and brake as Steam Input actions in the vehicle layer: "Gas" and "Brake" (analog triggers, e.g. swapped for the left hand) and "Steer + pedals" (a whole car on one stick: up = gas, down = brake / reverse, with the game's stick dead zone on the pedals). The triggers keep working. The B brake is now "Handbrake" in Steam. Pick the "Gamepad Tweaks" layout in Steam again to see them.
- Changed: gyro aiming (and the Steam "Aiming" layer) works only with a firearm in hand. In melee and unarmed the gyro no longer turns the character unseen; aim with the stick.
- Fixed: opening the map while driving no longer leaves the gas pressed (the engine revved to the limit while the car rolled; in vanilla it drove on if RT was held).
- Fixed: vibration sometimes didn't stop (and grew) after a shot, a melee hit or a light knock in a vehicle, until the next one.
- Added: vibration for zombie scratches, lacerations and bites: a sharp kick and a fading sting, then a heartbeat for a while.
- Added: vibration when the vehicle hits cones, signs, bushes and small trees.
- Changed: vaulting and climbing through windows vibrate with the animation: a light kick when the hands touch the fence or frame, a firmer one on landing. Tripping and falling hit harder when the body hits the ground.
- Changed: zombies banging on doors and fences nearby vibrate only for the first knocks (again after 15 s of quiet).
- Changed: road surfaces feel more distinct: gravel roads nearly smooth, rutted dirt roads rougher, railway much harder.
- Changed: smooth map panning is linear by default (pan curve 1 instead of 2): small stick deflections move the map too. Existing settings are kept.
- Fixed: a stick bound to a Steam analog action in the vehicle or on-foot layer (Steer, Move) no longer stops the map from panning.
- Added: "Ambient vibration while aiming a gun" (default 0.3): heartbeat, thunder and the like are weaker while aiming a firearm, so they don't shake a gyro reticle.

## Update: 15 Nov @ 10:56am

- Fixed: the X (interact) menu now shows fences and walls south and east of the character, so chain-link and metal fences can be disassembled from any side.

## Update: 14 Nov @ 4:21pm

- Added: splitscreen vibration per player: Options -> Mods -> "Vibration for player 1..4" turns it off for one player only.
- Added: "Vehicle vibration for passengers" strength: passengers no longer have to feel every bump of the road the driver picks.
- Fixed: splitscreen with a controller Steam doesn't handle: the one Steam controller no longer vibrates for everyone's events.

## Update: 14 Nov @ 1:20pm

- Changed: analog gas responds from the start of the trigger travel, like a real pedal (curve 0.7 instead of 1.5; your old curve setting is reset once).

## Update: 14 Nov @ 12:58pm

- Fixed: A confirms world cursors again on 42.22 (chop tree, disassemble, extinguish, paint, rake, scythe, place item, crafting build): vanilla 42.22 ignored A on them.

## Update: 14 Nov @ 3:02am

- Added: more vibration: vehicle crashes and running over zombies, running into a wall, bumps, falls and landings, hits blocked by clothing, smashing windows, zombies banging on doors nearby, thunder (with the sound), jump scares.
- Added: vehicle vibration: suspension bumps, bottoming out, bodies under the wheels, leaving the asphalt, a feel of its own for grass, dirt roads, gravel, sand, snow, plowed fields and railway (fades on long off-road drives), zombies banging on the car and its windows. Left wheels in the left grip, right in the right; on Xbox One / Series pads a short accent in the trigger motors for knocks at the front.
- Added: motor test button in the vibration options.
- Added: vibration for vaulting fences, burns, axe on doors and trees, prying boards, forcing doors with a crowbar.
- Changed: window vibration comes when the window actually opens, not when you press the button.
- Added: vibration settings in Options -> Mods: on/off, overall strength, strength per event.

- Added: controller vibration (through Steam Input): gunshots by the gun, melee hits, getting hurt, heartbeat when panicked. Strength per event in GamepadTweaks.properties (rumble.*).

## Update: 12 Nov @ 10:24am

- Fixed: "invalid signature" in ZombieBuddy, the Java part blocked: the signature is removed again, ZombieBuddy asks to approve the mod as before.

## Update: 12 Nov @ 5:00am

- Added: analog gas and brake on the triggers (vanilla: on/off at 70% of the travel). Each pedal position
  has its own cruising speed: a light press rolls the car slowly and keeps that speed instead of slowly
  accelerating to top speed; easing off brakes with the engine; full pedal works as in vanilla. LT brakes
  as hard as it is pressed. The engine RPM shown (tachometer and sound) follows the speed in the current
  gear instead of revving up on its own; gears, neutral and the driving physics stay vanilla. Options -> Mods -> Gamepad Tweaks.
  Turns itself off while Tsuki's AnalogThrottle is active.
- Added (experimental, off by default): brake hold. LT that brakes the car stops and holds it instead of
  backing up at once; release and press again to reverse. Works with vanilla pedals too.
- Changed: the Java part is signed by the author (ZombieBuddy shows "FullZero"; trust the author once and mod updates no longer ask for approval).

## Update: 7 Nov @ 1:39pm

- Fixed: fliers and stash maps on the world map didn't react to the controller cross (they needed the
  mouse cursor over the map, in splitscreen it is on another screen); now A opens them like the mouse.
- Fixed: gyro aiming did nothing when aiming with the trigger alone (half RT, stick released): the
  reticle stayed in front of the player. Now the gyro moves it from there.
- Changed: mod button actions are saved per controller preset, like the regular bindings. Default and
  Original always have the mod's defaults (a change there makes a new preset, as in vanilla). Bindings
  made before move to your own presets.
- Fixed: Look far (camera pan while aiming) moved the camera only a little when aiming with the stick;
  it pans as far as in vanilla again (and still follows the gyro / free aiming).
- Fixed: Look far works in any order, as in vanilla: hold its button first and then aim (it worked only
  when pressed while already aiming).
- Fixed: Windows splitscreen with Steam Input: with a second controller the Steam game actions and
  context layers stopped working for both players (Steam controllers weren't matched to players on Windows).

## Update: 31 Oct @ 5:13pm

- Changed: the Java part is no longer signed for now. ZombieBuddy blocked the signed jar as "signature invalid"
  when it could not load the author's key from the Steam profile; now it just asks to allow the mod.
- Fixed: a controller preset made in a non-English game (e.g. Russian "Пользовательский") was not
  saved on Linux / Steam Deck (the game runs with an ASCII locale there); new presets are named "Custom".
- Fixed: an action set to none in the mod's bindings got its default button back after reloading.
- Added: gyro / trackpad aiming through Steam Input: bind the gyro to the "Aim" analog action, it
  moves the reticle on top of the stick, with no added lag.
- Added: "Move" and "Steer" analog actions in Steam Input: put a stick (or trackpad) straight on
  walking or steering instead of the game's left stick; running at full deflection works too.
- Added: Steam actions for Aim (held, as the keyboard key: no stick needed), Attack, Melee
  (shove) and Run, on any button instead of trigger and stick thresholds.
- Added: camera pan while aiming ("look far") as an action, also for Steam; vanilla pans only
  with a hardcoded RB. It follows the gyro too.
- Added: actions for what the keyboard does with Shift: get in the driver's seat (also from a
  passenger seat), open/close the nearest curtain, change fire mode; and "use tool" on the square
  ahead (chop, dig, water...) without aiming.
- Fixed: using a tool on the square ahead with Interact while aiming worked only once per session
  with a gamepad.
- Changed: camera pan while aiming is a regular action on RB by default (was hardcoded), so it can
  be moved in Options -> Controller.
- Added: actions for rotate building, animal radial menu, voice push-to-talk, music toggle and
  the FPS graph.
- Changed: Steam action set layers switch only the layers that change.
- Changed: Steam actions have short titles with icons and are grouped by situation: combat and
  movement on foot, brake and cruise in a vehicle, item moves with the inventory open. Restart
  Steam and pick the "Gamepad Tweaks" layout again after updating.
- Compatibility: works on 42.21 and the 42.22 beta.
