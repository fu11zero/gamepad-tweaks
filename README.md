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

- **Keyboard-only actions on the gamepad** (`media/lua/client/GamepadTweaks/KeyActions.lua`,
  registered with `Bindings.add`, world layer, unbound by default). Vanilla handles these keys in
  `OnKeyPressed` handlers that act for `getSpecificPlayer(0)` / `getPlayer()` (and some return for
  a controller player), so with a gamepad they are unavailable or only in a wheel. Each action does
  what the key handler does, for the controller's player (splitscreen-safe):
  - `lightSource`: `ItemBindingHandler.toggleLight` (off hand, main hand, attached, else equip the
    strongest light);
  - `dropPrimary`, `dropSecondary`, `dropBothHands`, `dropBag`, `dropHandsAndBag`:
    `CFarming_Interact.FastDropItem` (favorites are kept);
  - `grabCorpse`: `ISGrabCorpseAction.OnKeyPressed` / `PerformGrabCorpse` (let go, or grab the closest);
  - `sharpenWeapon`: `ISFirearmRadialMenu.sharpenWeapon` for the main hand item.
  - `firearmRadial`: the firearm radial (magazine, rounds, rack). Vanilla opens it only by
    holding the ReloadWeapon button (`ISFirearmRadialMenu.onRepeatRBumper`, 500 ms); this opens
    it at once and it picks / closes on the release of the action's button (`hides`: the
    radial's hardcoded RB is retargeted).
  - `sitOnGround`: `ISSitOnGround` key handler; `searchMode`: `ISSearchManager.handleKeyPressed`;
    `shout`: `Callout` (on foot / as a passenger, the driver has the horn); `releaseRope`: `fallFromRope`;
  - vehicle (`ISVehicleMenu.onKeyPressed/onKeyStartPressed`): `engine` (start / shut off),
    `headlights` (driver), `heater`, `horn` (driver, sounds while held: `release` callback on the
    button release), `switchSeat` (seat UI, in or next to a vehicle), `vehicleInfo` (mechanics).
  - extra (`category = "extra"`, for the settings panel): `map` (`ISWorldMap.ToggleWorldMap`),
    `craftingMenu`, `buildingMenu`, `moveFurniture` (as the back button wheel commands do),
    `skills`, `health`, `protection`, `info` (character window tab, `toggleView`, the controller gets
    the focus), `survivalGuide`, `hotbar1`..`hotbar8` (`ISHotbar:activateSlot`; vanilla hotbar keys
    work only for player 0 and not with a controller), `timePause`, `timeNormal`, `timeFast1..3`
    (`SpeedControlsHandler`, not in MP, `whilePaused`: run while paused, other buttons don't),
    `toggleUI`, `screenshot` (`Core.TakeFullScreenshot`, as `GameWindow` does for the key),
    `pvp` (`ISEquippedItem` safety toggle for the controller's player).
  - not done: music toggle and push-to-talk are read from the keyboard in Java
    (`SoundManager.updateMusic`, `VoiceManager`).

- **Mod actions in Options -> Controller** (`media/lua/client/GamepadTweaks/ControllerEditor.lua`).
  The vanilla editor rows (`CharacterJoypadBindingUIRow`) list and offer only the Java enum
  `CharacterJoypadButtonBinding`; the rows and their lists are Lua, so the vanilla functions run first
  and the mod adds its actions: in each button row the actions on that button (mod colour, with the
  context: cruise held, hold, ...), in the edit row a list per action (another action instead, or
  `< Remove >`), and in `< Add New >` the actions not on the button yet ("[Category] Name", by
  category). `Bindings.set` writes `bind.<id>` at once through `GamepadTweaks_setSetting` (Java:
  replaces the line or adds it after its `#` example, keeps the rest of the file); an action of the
  same layer on that button is set to `none`. Mod actions are not part of the vanilla presets.
  Names: vanilla key binding names, mod strings in `media/lua/shared/Translate/{EN,RU}/UI.json`.

- **Mod actions as Steam Input game actions** (`SteamInput.java`, `Bindings.lua` Steam Input
  section, `media/steam_input/`). Vanilla doesn't use the Steam Input API: Steam only emulates a
  gamepad, so a Steam configuration can map buttons, keys and the mouse, but not the mod's
  actions, and extra buttons (back paddles) or Steam activators (long/double press, chords) can't
  reach them. The mod calls `ISteamInput::Init` and `SetInputActionManifestFilePath` (flat C API of
  the game's own `libsteam_api`, through the Foreign Function API) with `manifest.vdf`: one action
  set `game` with a button action per mod action (titles in English and Russian). In the Steam
  configurator they show up as game actions next to gamepad/keyboard/mouse bindings.
  - the manifest replaces the game's official layout in Steam's "Recommended" list, so it brings
    two per controller type, both with the set added (sticks, buttons and triggers stay the
    emulated gamepad until an action is bound): first Steam's plain "Gamepad" template under its
    own title (the default, as before), then the same bindings as "Gamepad Tweaks". Layout title tokens are looked up
    in the manifest's localization (not the layout's own), so the plain layout's title is there in
    every template language. Steam shows the
    game's developer as the author of both (`creator`, the mod author's SteamID64, is ignored so far); a layout can't
    point to a Steam template (paths are files next to the manifest), so the template is copied;
  - action set layers follow the player's situation (`Bindings.lua` picks them every frame,
    `GamepadTweaks_steamInputSetLayers`, Java activates them per Steam controller when they change),
    bottom to top: `onfoot` or `vehicle` (passengers: `steamInput.passengerLayer`), `aiming`, `ui`
    (a panel or radial has the joypad focus), `inventory` (the inventory or loot window), `map`; `menu` on every controller in the main menu and
    the pause menu. A layer overrides only what is bound in it, so one paddle can be the light on
    foot and the horn in a car, the gyro can be a mouse only in panels or only while aiming.
    Situational actions are declared in their layer (hands and character: `onfoot`, vehicle:
    `vehicle`, except switch seat), the rest in the set; a layer's actions fire only while it's active
    (leaving the car releases the horn);
  - Steam lists the set's actions and then the active layer's, in manifest order: the set's
    actions of a category that continues in a layer (switch seat) go last, titles start with an icon
    per action ("🚘📯 Horn", `ICONS` in the script; color emoji only, text-style symbols render small
    and monochrome unless followed by U+FE0F; hotbar slots get keycap numbers, since what a slot
    holds depends on the worn belt / back / webbing);
  - `GamepadTweaks_steamInputPoll` (Lua, every frame) reads the digital actions of every Steam
    controller and returns press/release edges; the controller is matched to the game's joypad by
    `GetGamepadIndexForController` and the "... pad N" joystick name, else the only joypad player;
  - a press runs the action as its button would (in the world, also with a UI focused; while
    paused only actions that work then); a wheel closes and picks the slice on release;
  - `steamInput.enabled=false` turns it off (restart), `steamInput.debugLog=true` logs events;
  - the files are generated by `tools/steam_input.py` from the Lua action lists, translations and
    the local Steam templates; rerun it after adding actions.

- **Inventory and loot window actions** (`InventoryActions.lua`, layer `inventory` in
  `Bindings.lua`). With a mouse the buttons above the item list are one click (Transfer All /
  Loot All, same type, same type to nearby containers, Move to Floor:
  `ISInventoryWindowContainerControls`, `ISLootWindowContainerControls` handlers), Drop is a drag
  to the floor, a double click equips / wears / eats (`ISInventoryPane:doContextualDblClick`).
  With a gamepad it's A -> context menu -> scroll, and most of the handlers add nothing to the
  gamepad menu (`handleJoypadContextMenu` is empty except Remove All and the appliance toggles), so
  same type, nearby containers and Move to Floor can't be done at all; Drop and Unpack are mouse-only
  menu options (`getJoypadBind() == -1`). The mod adds actions for the focused window and its
  selected row (header = the stack, item row = that item, as vanilla X): `invTransferAll`,
  `invTransferSameType`, `invTransferSameTypeNearby`, `invAllToFloor` (loot: the Move to Floor
  button; inventory: the shown bag / main inventory with the `ISInventoryPane:transferAll` filter,
  so worn, equipped, hotbar, favorite items and key rings stay), `invDropSelected`,
  `invTransferStack` / `invTransferOne` (X for the whole stack / one item whatever the row: e.g.
  Steam: X on a tap, `invTransferStack` on a long press), `invUse`, `invUnpack`. They call the
  vanilla handlers / context menu functions. Unbound by default; a bound button runs the action
  instead of what vanilla does with it in the window (`ISInventoryPage:onJoypadDown`,
  `onJoypadDir*` wrapped). Not done: selecting several rows. In joypad mode
  `ISInventoryPane` clears the selection every frame, so vanilla works with one row only.

- **Vanilla bindings as Steam actions** (`VanillaActions.lua`, `HeldActions.java`). Steam lists
  only the mod's game actions, so a player looking for "Crouch" in the configurator doesn't find
  it, and vanilla ties each binding to its physical button. Each vanilla button binding is also a
  Steam action `vanilla<Binding>` (first in the list) that runs the game function behind it
  directly, as the keyboard does; no button is pressed, so nothing else on any button fires, and
  it works whether the binding is on a button, shares one, or has none:
  - character (Java `CharacterInputComponent` consumers): Crouch -> `setSneaking` (as
    `IsoPlayer.updateSneakKey`), Rack -> `OnPressRackButton` (`IsoPlayer.checkReloading`),
    Reload -> `OnPressReloadButton` (it only stops loading rounds) and
    `ISReloadWeaponAction.BeginAutomaticReload` (the gamepad reload is the RB prompt of
    `ISFirearmRadialMenu`, timed on the release hardcoded to RB), Zoom -> `Core.doZoomScroll` (`UIManager.handleZoomKeys`);
  - held: Sprint, Manual Floor Attack, Brakes and the Java half of Interact set a held state per
    controller that the game's query also returns (`isSprintButtonDown`,
    `isManualFloorAtkButtonDown`, `isInteractButtonDownInternal`: doors, windows, grapple via
    `IsoPlayer.updateUseKey` -> `doContext`; the brake in `CarController.updateControls`), so toggle-to-sprint and the rest of vanilla still apply;
  - button prompts: `ISButtonPrompt:setButtonBindingPrompt` is wrapped to keep each binding's
    handler by name (vanilla keeps one per button, the last evaluated); Interact, Cancel, Climb
    Through, Smash Window run it. Interact Options and Inventory are evaluated by vanilla only for
    the button they're on (`getBestXButtonAction` / `getBestYButtonAction`), so they are evaluated
    on the press, the button slots restored after. With a build cursor Interact / Cancel go to it
    (`drag:onJoypadPressButton` A / B, hardcoded in vanilla);
  - panels: Close Panel, Cycle Tabs, Transfer Item, Cycle Inventory / Loot are in the editor but
    no code reads them (panels take hardcoded buttons); the action gives the focused panel that
    command (`onJoypadDown(B)`, LB/RB), the inventory window directly (close = Y, containers,
    `doGrabOnJoypadSelected`);
  - Cruise Control: on / off on the press (`ISVehicleRegulator.onJoypadReleaseX` toggles on the
    release, because the held button + D-pad sets the speed; the action has the separate
    cruise faster / slower actions). With no speed set yet it takes the current one.
  Left out: Walk To (needs a cursor), Loot (unused); the analog bindings (Aim, Attack, Melee,
  PrecisionAim, Run) stay on the sticks and triggers. Not in the in-game editor, which already has
  them (`steamOnly`).

- **Brakes follow their binding** (`HeldActions.brake`, after `CarController.updateControls`).
  Vanilla brakes a gamepad driver's car on B (`JoypadManager.isBPressed`), past the Brakes binding;
  now it is the binding (B by default), plus the Steam action. The forced brake stays.

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

- **Options -> Mods -> Gamepad Tweaks** (`media/lua/client/GamepadTweaks/Options.lua`,
  `PZAPI.ModOptions`). Not every player wants the features (steering without a dead zone etc.)
  or the default tuning for their controller, and the file is hard to find. The page shows the
  features and the values worth tuning; it is a view of the `.properties` file, not of
  `ModOptions.ini`: the values are read from the file whenever vanilla loads the mod options
  (`PZAPI.ModOptions:load`, wrapped; `MainOptions` calls it when it builds the Mods page), and
  Apply writes back only the changed ones (`GamepadTweaks_setSetting`), so hand-set values outside
  a slider's range survive. Dependent options are greyed out while their feature is off.
  Feature switches (all on by default, off = vanilla):
  - `steering.enabled`: all of the steering changes (`Patches.SteeringInput`, `Steering.wheel`);
  - `steering.rawStick`: raw stick X and `StickCenter`; off = the game's stick value, still shaped
    by `Steering.shape`; `steering.recenter`: center learning;
  - `steering.constantRateWheel`: `Steering.wheel` (off = vanilla wheel lag);
  - `steering.scaleToSpeedClamp`: full stick = the clamp;
  - `triggers.noDeadZone`: `Triggers.value` / `Triggers.deadZone`;
  - `actions.crouchOnPress`, `actions.sprintOnPress`, `actions.vehicleOnlyByPrompt`: `PressActions`;
  - `map.smooth`: `MapControls.update` returns false, Lua runs vanilla;
  - `steamInput.enabled` (restart), `steamInput.passengerLayer`.
  Sliders: steering dead zone, center drift zone, curve exponents and their speed, wheel rates,
  map pan speed / curve, zoom speed. Fixes (`ButtonLatch`, fliers, cruise/reload bindings) have
  no switch; debug logs and the center learning timings are file-only.

Stick axis indices and inversion come from `~/Zomboid/joypads/<guid>.config`
(`MovementAxisX`, `MovementAxisXFlipped`): the game loads them into `JoypadManager.Joypad`.

## Screenshots

`screenshots/` (also the Workshop gallery, see Publishing):

| | |
|---|---|
| ![Steam game actions](screenshots/1-steam-game-actions.png) | ![Back buttons](screenshots/2-steam-back-buttons.png) |
| ![Layers](screenshots/3-steam-layers.png) | ![On foot actions](screenshots/4-steam-game-actions-onfoot.png) |
| ![Controller bindings](screenshots/5-controller-bindings.png) | ![Mod options](screenshots/6-mod-options.png) |
| ![Recommended layouts](screenshots/7-steam-recommended-layouts.png) | |

## Layout

```
src/main/java/dev/gamepadtweaks/   mod source
Contents/mods/GamepadTweaks/       the mod itself (Workshop layout; the game loads it from ~/Zomboid/Workshop)
  42/mod.info
  42/poster.png                    mod list poster (512x512)
  42/media/java/client/GamepadTweaks.jar   <- build.sh output
build.sh                           build
preview.png                        Workshop preview (256x256 or 512x512, <= 1 MB)
screenshots/                       Workshop gallery images (uploaded by hand, not by the game)
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

The game uploads only `preview.png` as the item image (`SteamWorkshopItem` -> `SetItemPreview`).
The gallery (`screenshots/`, in file name order) is added on the item's Steam page: "Add/edit images
& videos" (owner only). The description's "Screenshots" list follows the same order.

## Reading game code

```sh
tools/decompile.sh zombie/core/physics/CarController zombie/input/JoypadManager
```

## Requirements

- ZombieBuddy 2.3.4+ installed as a Java agent (`-javaagent:ZombieBuddy.jar --` in launch options).
- On first launch ZombieBuddy asks to approve the new jar; it asks again after every rebuild.
