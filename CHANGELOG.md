# Changelog

Player-facing change notes, newest first. Each section is copied as is into the Steam Workshop
change notes when the mod is updated. Keep it in English, short, one line per change.

## Unreleased

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
