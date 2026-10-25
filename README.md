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
  off to go straight. A plain dead zone fixes it but kills fine steering. Instead the steering
  gets the distance from a learned center, rescaled so full deflection is still +-1, with no
  dead zone (`noiseDeadZone`, 0 by default):
  - while the stick stands still (range < `recenterStillRange` over `recenterStillMs`: the
    jitter zone, used only to detect that the stick stopped) within `recenterZone` of zero,
    the center glides to the mean of that window at `recenterRate` per second;
  - drift and a deliberate small hold look the same by position, so learning is armed only
    by a release: the stick was further than `releaseFrom` from the center and got back within
    `recenterZone` in less than `releaseMaxMs` (the direction isn't checked: without hardware
    smoothing the spring overshoots). Armed at start too;
  - moving the stick further than `disarmDistance` from where it rested (thumb steering)
    disarms it, except during `releaseSettleMs` after a release (overshoot swings).
  `steering.debugLog=true` logs arming/disarming and marks a locked center.

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

- **Fliers work with a controller** (`media/lua/client/GamepadTweaks/PrintMedia.lua`).
  Vanilla `ISReadABook:displayPrintMedia` calls `setJoypadFocus(playerNum, win)`, which evaluates
  `uiToString(win)` for a log line before assigning the focus; `ISAtomUIJoypad:toString` then does
  `self._ATOM_UI_CLASS.class:getSimpleName()`, which throws in Kahlua ("getSimpleName of non-table").
  The focus stays on the inventory: B/X/Y do nothing, the window closes only with Esc. Instead:
  `ISAtomUIJoypad.toString` that doesn't throw (Apply copies it into every PZAPI window); `close()`
  doesn't leave the focus on a hidden element; a B prompt in the bottom bar. Splitscreen issues
  of this window (shared `worldMapFlier`, `getPlayer()`) are fixed in SplitscreenFixes.

- **Rebindable hardcoded buttons** (`media/lua/client/GamepadTweaks/Bindings.lua`, values via
  `Settings` globals `GamepadTweaks_getSetting` / `GamepadTweaks_settingsVersion`).
  Vanilla handles these directly, past the binding system, so the buttons can't be used for
  anything else and the actions can't be moved:
  - D-pad wheels: `JoypadControllerData:onPressUp/...` -> `ISDPadWheels.onDisplayUp/Down/Left/Right`;
  - Back command wheel and Start pause: `onPressButtonNoFocus`;
  - cruise control speed: X + D-pad up/down (`ISVehicleRegulator.onJoypadPressUp/Down`);
  - L3 held -> crouch/sit/auto-walk radial (`ISJoystickButtonRadialMenu`, timer from
    `ISButtonPrompt:update`);
  - RB held in a UI -> panel navigation, LB in it -> parent panel (`onHoldButton`, `onReleaseButton`).

  The vanilla binding list is a Java enum (`CharacterJoypadButtonBinding`, fixed at class load and
  saved by name in `InputBindings/*.xml`), so it isn't extended; the actions live in the mod:
  `bind.<action>=<button>`, `none` frees the button for the regular bindings. Actions are in layers
  (one button = one action per layer): `world` press (`vehicleWheel`, `emoteWheel`, `equipWheel`,
  `extraWheel`, `commandWheel`, `pause`), `cruise` press while driving with the CruiseControl
  button held, checked first (`cruiseFaster`, `cruiseSlower`, repeat while held), `hold`
  (`stickRadial`), `uiHold` (`uiNavigation`), `navigation` release (`uiNavigateParent`).
  Default = vanilla button, so nothing changes until rebound; an action set to a button takes it
  from the action that has it by default. A regular binding that acts in the world (not the UI-only
  ClosePanel/Cycle*/TransferItem) put on the button of a default world action takes it too: vanilla
  has none on the D-pad, Back or Start, so the player put it there (Melee on D-pad left no longer
  also opens the weapon wheel). Regular bindings are re-checked every 500 ms. Details:
  - the D-pad hooks are the `onDisplay*` calls made from `onPressUp/...` (so vanilla checks still
    apply: UI focus, drag); `ISVehicleRegulator.onJoypadPressUp/Down` return false there, the
    cruise layer is dispatched with the wheels. A world action fires once per press (vanilla D-pad
    repeats while held);
  - other buttons in the world: an action bound to them replaces vanilla (button prompts);
    a freed Back/Start does nothing;
  - wheels close on their vanilla button release (`hideWhenButtonReleased`), the mod switches it
    to the button that opened them; D-pad releases are also passed to the back button wheel;
  - without the jar the defaults are used.

- **Cruise control and reload follow their bindings** (`Bindings.lua`). Vanilla puts the prompts of
  `CruiseControl` and `ReloadWeapon` on their bound buttons but hardcodes the rest: the cruise
  toggle happens on X release (`onReleaseButton` -> `ISVehicleRegulator.onJoypadReleaseX`), the
  speed changes with X held; the firearm radial opens while RB is held (`ISButtonPrompt:update` ->
  `ISFirearmRadialMenu.onRepeatRBumper`), quick reload and closing the radial are on RB release.
  With either binding moved (e.g. CruiseControl on RB) they don't work. Also the cruise prompt
  (its press handler) is set only while JoyPadSetup evaluates the X button, and the evaluation of
  the CruiseControl button right after clears it (RB: `getBestRBButtonAction`, no firearm); the mod
  sets it again after every `ISButtonPrompt:getBestButtonBindingAction`. Here all of it uses the
  bound button; on the vanilla buttons nothing changes.
  The cruise layer is dispatched before vanilla `onPressUp/...`, so mods wrapping `onDisplayUp`
  (Smart Radial Menu opens its menu when the vehicle radial stays empty) don't see those presses.

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
