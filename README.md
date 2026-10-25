# Gamepad Tweaks

Java mod for Project Zomboid B42 (ZombieBuddy) that fixes gamepad handling.

## Features

- **Steering without dead zones.** In a vehicle the steering takes the raw stick X:
  - `Patches.SteeringInput`: `CarController.updateControls` uses the raw axis instead of
    `JoypadManager.getMovementAxisX` (no stick dead zone, no diagonal x1.41 stretch);
  - the wheel angle is computed by the mod (below), so the `Math.abs(steering) > 0.1F`
    dead zone in `CarController.update` no longer matters.

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

Settings live in `~/Zomboid/GamepadTweaks.properties` (created with defaults on first
launch, re-read while the game runs).

Stick axis indices and inversion come from `~/Zomboid/joypads/<guid>.config`
(`MovementAxisX`, `MovementAxisXFlipped`): the game loads them into `JoypadManager.Joypad`.

## Layout

```
src/main/java/dev/gamepadtweaks/   mod source
Contents/mods/GamepadTweaks/       the mod itself (Workshop layout; the game loads it from ~/Zomboid/Workshop)
  42/mod.info
  42/media/java/client/GamepadTweaks.jar   <- build.sh output
build.sh                           build
tools/decompile.sh                 decompile game classes into decompiled/ (not in git)
```

## Build

Requires JDK 25 (game classes are Java 25):

```sh
sudo pacman -S jdk25-openjdk
./build.sh
```

## Reading game code

```sh
tools/decompile.sh zombie/core/physics/CarController zombie/input/JoypadManager
```

## Requirements

- ZombieBuddy 2.3.4+ installed as a Java agent (`-javaagent:ZombieBuddy.jar --` in launch options).
- On first launch ZombieBuddy asks to approve the new jar; it asks again after every rebuild.
