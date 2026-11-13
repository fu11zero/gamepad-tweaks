# Changelog

Player-facing change notes, newest first. Each section is copied as is into the Steam Workshop
change notes when the mod is updated. Keep it in English, short, one line per change.

## Unreleased

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
