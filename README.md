# Gamepad Tweaks

Java mod for Project Zomboid B42 (ZombieBuddy) that fixes gamepad handling.

## Features

- **Steering without dead zones.** In a vehicle the steering takes the raw stick X:
  - `Patches.SteeringInput`: `CarController.updateControls` uses the raw axis instead of
    `JoypadManager.getMovementAxisX` (no stick dead zone, no diagonal x1.41 stretch);
  - the wheel angle is computed by the mod (below), so the `Math.abs(steering) > 0.1F`
    dead zone in `CarController.update` no longer matters.

- **Drifting stick center** (`StickCenter`, applied to the raw X in `Patches.SteeringInput`).
  A released stick doesn't return to exactly 0: the spring leaves it a bit off, a different
  spot after every move (measured -0.01..-0.05 on a Vader 5 Pro, up to +-0.077 on a Vader 3).
  Without a dead zone that offset steers, and at highway speed even a 0.0003 wheel angle
  (stick -0.03) drives the car in a long arc, so the player has to hold the stick slightly
  off to go straight. A plain dead zone fixes it but kills fine steering. Instead:
  - while the stick stands still (range < `recenterStillRange` over `recenterStillMs`)
    within `recenterZone` of zero, its center glides to the current value at
    `recenterRate` per second. Thumb resting on the stick or not doesn't matter;
    steering moves the stick far more than the jitter, so it isn't eaten;
  - output = distance from the center minus a tiny `noiseDeadZone` (stick jitter),
    rescaled so it starts from 0 and full deflection is still +-1.

- **Speed-sensitive steering** (`Steering.shape`). Vanilla clamps the wheel angle at speed
  (`VehicleScript.getSteeringClamp`: 0.9 standing still, ~0.4 at max speed) but maps the
  stick 1:1, so at speed the outer stick travel does nothing and small deflections are too
  sharp. Instead:
  - response curve `|x|^exponent`, the exponent grows with speed (soft center at speed);
  - full stick = the clamp at the current speed.

- **Wheel without lag** (`Steering.wheel`, hooked into `CarController.update` by
  `SteeringHookTransformer`). Vanilla moves the wheel exponentially towards the stick, slower
  with speed (down to a ~3 s lag at top speed), and returns it quickly only when the stick is
  inside the 0.1 dead zone. Instead the wheel moves towards the stick at a constant rate,
  faster back to center. Only for gamepad drivers; keyboard steering stays vanilla.

- **Triggers without dead zone** (`Triggers`, `Patches.*TriggerValue`). Vanilla
  `Joypad.getLTValue/getRTValue` apply the per-axis dead zone that the options screen
  dead zone buttons set for all axes at once (default 0.2 = first 10% of the travel).
  Triggers rest at zero and don't need it: the raw axis is used instead, the options
  screen shows no trigger dead zone, the buttons still work for the sticks.
  `triggers.debugLog=true` logs every raw value change.

- **UI presses don't leak to the character** (`ButtonLatch`). The UI reacts on press:
  B closes a menu, the focus goes away, the character's buttons are turned back on with
  B still held, and its release counts as a "click" (crouch toggle etc.). Buttons held
  when the character's buttons get turned on are ignored by the character until released.

- **Actions on press, not click** (`PressActions`). Vanilla toggles some gamepad actions on
  a "click" (release within 400 ms), so they lag and don't work with long-press binds:
  - crouch toggle: on press, unless the left stick radial menu is enabled;
  - toggle-to-sprint: on press;
  - enter/exit vehicle: vanilla also does it on an Interact click for any nearby vehicle,
    on top of the A prompt (on press); for the gamepad only the prompt is left.

- **Smooth map controls** (`MapControls.java`, called from the Lua override of
  `ISWorldMap:updateJoypad` / `ISMap:updateJoypad` in `media/lua/client/GamepadTweaks/MapControls.lua`).
  Vanilla treats the stick and triggers as buttons: stick below 0.5 per axis is ignored (on top
  of the game's dead zone), the map then waits 150 ms, the center snaps to whole squares (jumps
  at high zoom), isometric view drops diagonals; LT/RT (> 0.7) zoom one level per press, holding
  repeats only after the zoom animation ends; the paper map ignores the stick. Instead:
  - past the game's radial stick dead zone, pan speed = `map.panSpeed` map heights per second
    x deflection^`map.panExponent`, in screen directions (screen offset converted to world through
    the map projection, so isometric works too); D-pad = deflection `map.dpadDeflection`;
  - zoom speed = `map.zoomSpeed` levels per second x trigger^`map.zoomExponent` (RT in, LT out),
    `setZoom` around the map center, no step animation;
  - while rotating an annotation the stick keeps rotating it (no panning);
  - without the jar (`GamepadTweaks_updateMap` missing) vanilla runs.

Settings live in `~/Zomboid/GamepadTweaks.properties` (created with defaults on first
launch, re-read while the game runs).

Stick axis indices and inversion come from `~/Zomboid/joypads/<guid>.config`
(`MovementAxisX`, `MovementAxisXFlipped`): the game loads them into `JoypadManager.Joypad`.

## Layout

```
src/main/java/dev/gamepadtweaks/   mod source
Contents/mods/GamepadTweaks/       the mod itself (Workshop layout; the game loads it from ~/Zomboid/Workshop)
  42/mod.info
  42/poster.png                    mod list poster (512x512)
  42/media/java/client/GamepadTweaks.jar   <- build.sh output
build.sh                           build
preview.png                        Workshop preview (256x256 or 512x512, <= 1 MB)
workshop.txt                       Workshop title, description (BBCode), tags, visibility
tools/decompile.sh                 decompile game classes into decompiled/ (not in git)
```

## Build

Requires JDK 25 (game classes are Java 25):

```sh
sudo pacman -S jdk25-openjdk
./build.sh
```

## Publishing

Build first (the jar is not in git), then in the game: main menu -> Workshop -> upload,
pick GamepadTweaks. The game uploads only `Contents/` plus `preview.png` and checks
(`SteamWorkshopItem.validateContents`): preview present and square 256/512 px, no
`*.sh *.so *.dll *.exe *.zip ...` inside `Contents/`, a `mod.info` with `id=` in a version
folder. Allowed tags: `media/WorkshopTags.txt` in the game folder. After the first upload the
game writes the item id into `workshop.txt`.

## Reading game code

```sh
tools/decompile.sh zombie/core/physics/CarController zombie/input/JoypadManager
```

## Requirements

- ZombieBuddy 2.3.4+ installed as a Java agent (`-javaagent:ZombieBuddy.jar --` in launch options).
- On first launch ZombieBuddy asks to approve the new jar; it asks again after every rebuild.
