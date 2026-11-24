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

- **Analog gas and brake** (`Throttle`, `Patches.Throttle*`, `throttle.*` settings). Vanilla
  `CarController.updateControls` makes the triggers on/off pedals (RT/LT > 0.7), and
  `control_ForwardNew` / `control_Reverse` / `control_Braking` push or brake with full force. Scaling
  the force by the pedal (as other mods do) only scales the acceleration: the game has almost no drag,
  so a light pedal still takes the car to top speed, slowly. Instead:
  - pedals count from the first bit of travel (`throttle.deadZone`), pedal = travel^`throttle.pedalCurve` (0.7: a car at a stop needs ~10% of the force to start rolling, that is ~5% of the travel; the old `throttle.curve` 1.5 needed ~20% and is migrated);
  - resistance share `r = (speed / maxSpeed)^dragExponent`, engine force x `(pedal - r) / (1 - r)`:
    at a standstill the push = pedal, it fades with speed and is gone at `maxSpeed * pedal^(1/dragExponent)`,
    so every pedal position holds its own speed; full pedal = vanilla, traits / towing / offroad /
    MP speed limit stay on top; under the cruise control speed vanilla;
  - above that speed (`pedal < r`) the engine brakes, up to the vanilla released-pedal 10
    (x `throttle.engineBraking`), so easing off has no jolt;
  - a pedal against the motion (LT forward, RT rolling back) brakes from that up to the vehicle braking
    force by the pedal; B (x13), both pedals, unloaded chunk ahead stay vanilla;
  - RPM shown by the speed (`Patches.ThrottleRpm` on `CarController.update`): in vanilla the engine
    speed is a number of its own, not tied to the wheels. `control_ForwardNew` revs it at a fixed rate
    towards the gear change RPM on any pedal and shifts up once both the RPM and the speed reach the
    gear's top; released pedal / brake put the gearbox in N and the RPM falls to idle; no downshift in
    gear. The tachometer and the sound show it, so on a light pedal the engine revs while the car
    crawls. Vanilla keeps its number and does everything with it (force, shifts, N, released-pedal
    braking): the update runs with the vanilla RPM, and after it the engine shows an RPM from the speed
    across the current vanilla gear's band (idle or `afterGearChange` to `gearChange` at the gear's top
    speed), in proportion to the speed below and past the band (not below idle), never above vanilla's
    (on a full pedal vanilla's lags behind the speed: it shifts only once its own RPM reaches `gearChange`,
    a quick start outruns it and it then skips gears, 1 -> 3; that lag is shown as without the mod). In N the shown RPM falls by vanilla's steps from where it was (vanilla's is
    usually higher, it would jump up on release), down to vanilla's or idle. R, engine off: vanilla;
  - sound: the `VehicleLoad` parameter (vanilla 0/1, `isGasPedalPressed`) gets the smoothed share of
    the engine force (`ParameterVehicleLoad`, both the `audio` and `vehicleSound` ones);
  - off while Tsuki's AnalogThrottle is active (`ForeignThrottle`: its `ATBridge.enabled`; 0.1.3 runs
    only on 42.21). Both patch the same `CarController` methods: the force would be scaled twice and its
    RPM changes inside `update` would drive vanilla's shifts here;
  - blocked driver (`Patches.BlockedDriver`, `Throttle.release`): with the world map open
    (`IsoPlayer.isBlockMovement`) `BaseVehicle.updateControls` skips `CarController.updateControls`, so
    the pedals kept their state from the moment the map opened (vanilla: RT held past 0.7 drove on).
    With the analog gas any press is a pressed pedal, and once the analog state went stale vanilla
    full gas took over: revs at the limit while rolling. Now the pedals are released, the analog
    state and the brake hold dropped while the driver is blocked.

- **Brake hold**, experimental, off by default (`Throttle.hold`, `throttle.brakeHold`, also with the vanilla on/off pedals). Vanilla
  `CarController.update` turns LT into a brake while the car moves forward and into reverse the moment it
  stops (`velocity . forward <= 0`), so a brake held a moment too long backs the car up, reverse beeper
  and all. Here LT that started braking (above 1 km/h) holds the car near the stop as the brake
  (`clientControls.brake`, as B) until it is released; the next press reverses. RT while backing up
  stays vanilla (brakes, then drives forward): after reversing the next move is almost always forward.

- **Easy driving**, per splitscreen player, off by default (`EasyDriving`, `easyDriving.player<n>`).
  Vanilla steers with the stick X relative to the car, so a car heading down the screen steers
  mirrored, and reversing takes a mirrored wheel: too hard for a player new to driving. Here the
  left stick points where to go on the screen and the wheel turns the car there:
  - the stick becomes a world direction as walking does it (`IsoPlayer.updateMovementFromInput`),
    with the game's radial stick dead zone (`getMovementAxisXRaw/YRaw`);
  - the angle to the car's heading (`BaseVehicle.getForwardVector`) turns the wheel, full lock at
    40 degrees, times the vanilla clamp for the speed (`VehicleScript.getSteeringClamp`);
  - the triggers stay the pedals (a stick's short travel doses the gas poorly at low speed);
    backing up (rolling back, or LT alone at a stop) the wheel turns mirrored to point the rear at
    the stick.
  `easyDriving.stickPedals=true` (off by default) takes the pedals from the stick too:
  - the deflection is the gas, down to 35% with the target 90 degrees or more off, so sharp turns
    are slower; a target behind the car (past 120 degrees, back under 70) reverses: the deflection
    goes on the brake pedal (brakes, then reverses at the stop); while the car still rolls the
    other way the wheel stays straight;
  - the pedals go through `AnalogInput.pedals` and `Throttle` as stick pedals, with their own curve
    (`throttle.stickCurve`, default 2), so the analog gas and the triggers still work; the brake
    hold is off for that driver.
  Servers can forbid it: sandbox option `GamepadTweaks.EasyDriving` (`media/sandbox-options.txt`,
  page "Gamepad Tweaks", allowed by default), which the server sends to its clients. It is a client
  check, a modified client can bypass it. `steering.debugLog` logs it once a second.

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
  The same applies to a context menu closed by A or B (`ContextMenuPress.lua`): Steam delays a
  plain press by the double-click timeout when hold / double activators share the button, so the
  game closed the menu on the first press and the delayed copy arrived in the window underneath
  (opened another menu, closed the inventory). The next press of that button within 250 ms after
  its release is dropped. Only a press that actually closes the menu arms this: navigating into
  a submenu with A or B leaves both presses working. Hold / double actions themselves are Steam
  game actions, not gamepad presses, so they aren't affected.

- **Actions on press, not click** (`PressActions`). Vanilla toggles some gamepad actions on
  a "click" (release within 400 ms), so they lag and don't work with long-press binds:
  - crouch toggle: on press, unless the left stick radial menu is enabled;
  - toggle-to-sprint: on press;
  - enter/exit vehicle: vanilla also does it on an Interact click for any nearby vehicle,
    on top of the A prompt (on press); for the gamepad only the prompt is left.

- **Interact (A) picks what the character faces** (`InteractTarget`, `interact.*` settings,
  gamepad players only). Vanilla `IsoPlayer.updateUseKey` runs `doContext` on release (or after
  0.5 s held): it collects contextual actions on the facing side (`doContextNSWE`; for a diagonal
  facing both cardinal sides, ordered by the position inside the tile), then doors / windows /
  frames on the opposite sides marked `behind`, and `pickBestContextualAction` takes the highest
  priority, behind or not. Doors and windows are 100, furniture, animals, hutches 90
  (`ContextualAction.Action`), so the window behind beats the sofa in front, and with nothing in
  front the window behind opens anyway; the Lua prompts (`ISButtonPrompt`
  `getBestInteractButtonAction` / `getBestClimbThroughButtonAction`) offer it too.
  - `interact.notBehind`: `getContextDoorOrWindowOrWindowFrame` returns nothing for a side
    opposite to `getForwardIsoDirection` except an open door, so behind A only closes a door
    (what vanilla's behind check is for: A to open, A to close it after you, running from
    zombies). It is used when nothing is in front, or before anything in front when the player
    stepped onto its square through that edge less than 3 s ago (square history per player,
    updated every frame from `updateUseKey`); the prompt shows it first too
    (`GamepadTweaks_interactRecentDoor`, `InteractPrompt.lua`).
  - `interact.facing`: `pickBestContextualAction` takes the action whose side is closest to the
    continuous facing vector; priority only breaks ties.
  - `interact.cursor`: with a world cursor (`IsoCell.getDrag`: place / pick up furniture, chop,
    disassemble, build) A goes to the cursor (`JoyPadSetup onPressButtonNoFocus`), but the Java
    poll still ran `doContext` on release and sat on the sofa or opened the window next to the
    cursor. A press that started on a cursor, or a release with a cursor up, skips `doContext`.
    Same for the prompt's own handlers (`InteractPrompt.lua`): light switches, stoves, radios and
    crafting entities act on press in Lua while `doContext` acts on release, so an EXIT lamp by a
    door toggled and the door opened. A handled press (`GamepadTweaks_interactHandled`) skips
    `doContext`; facing diagonally the prompt also checks doors / windows on both sides before
    lights (vanilla took the first side's lamp, Java opened the other side's door).
  - `interact.lootFacing` (`LootFacing.lua`): vanilla `ISInventoryPage:refreshBackpacks` selects
    the gamepad's container by index (`backpackChoice`, 1 by default), and the buttons are built
    square by square from the north-west corner, so the loot window opened on the container up-left
    on the screen (the wall cabinet "above" the player). On Y (`ISButtonPrompt.cmdShowLoot`) and
    whenever the player turns or changes square, the container whose square is closest to the
    facing is selected (own square ranks between front and side); LB/RB still cycle.
- **Aiming without the stick doesn't turn the character** (`AimSnap`, `aim.snapFix`). With half RT
  or the Steam Aim action and no Aim stick, the reticle snaps one tile ahead of the animated facing
  (`AimingMode.snapAimInFrontOfPlayer`) at height 0.57 (melee, unarmed) / 0.468 (firearm), but the
  facing is read back from it
  (`IsoPlayer.calculateAimVector`) at the chest, `getAimOriginPosZ` = z + 0.495. A point drawn
  higher than it's read lands further up the screen: each frame the facing gets a bias towards
  screen-up (down for 0.468) and the character turns until it faces straight up. The snapped
  point is now put at the read height.
- **Smooth map controls** (`MapControls.java`, called from the Lua override of
  `ISWorldMap:updateJoypad` / `ISMap:updateJoypad` in `media/lua/client/GamepadTweaks/MapControls.lua`).
  Vanilla treats the stick and triggers as buttons: stick below 0.5 per axis is ignored (on top
  of the game's dead zone), the map then waits 150 ms, the center snaps to whole squares (jumps
  at high zoom), isometric view drops diagonals; LT/RT (> 0.7) zoom one level per press, holding
  repeats only after the zoom animation ends; the paper map ignores the stick. Instead:
  - past the game's radial stick dead zone, pan speed = `map.panSpeed` map heights per second
    x deflection^`map.panExponent` (default 1, linear: with 2 small deflections barely moved and
    new players clicked the stick instead), in screen directions (screen offset converted to world through
    the map projection, so isometric works too); D-pad = deflection `map.dpadDeflection`;
  - zoom speed = `map.zoomSpeed` levels per second x trigger^`map.zoomExponent` (RT in, LT out),
    `setZoom` around the map center, no step animation;
  - while rotating an annotation the stick keeps rotating it (no panning);
  - fliers and stash maps under the cross: vanilla `renderPrintMedia` / `renderStashMaps` pick the
    icon under the map center but then also require `isPointOver(getMouseX(), getMouseY())`, the real
    mouse cursor over the map (in splitscreen it is usually on another screen), so the icon never
    highlighted and A did nothing (streets have no such check). While they run in gamepad mode
    `isPointOver` tests the cross (Lua only, works without the jar);
  - without the jar (`GamepadTweaks_updateMap` missing) vanilla runs.

- **Fliers work with a controller** (`media/lua/client/GamepadTweaks/PrintMedia.lua`).
  Vanilla `ISReadABook:displayPrintMedia` calls `setJoypadFocus(playerNum, win)`, which evaluates
  `uiToString(win)` for a log line before assigning the focus; `ISAtomUIJoypad:toString` then does
  `self._ATOM_UI_CLASS.class:getSimpleName()`, which throws in Kahlua ("getSimpleName of non-table").
  The focus stays on the inventory: B/X/Y do nothing, the window closes only with Esc. Instead:
  `ISAtomUIJoypad.toString` that doesn't throw (Apply copies it into every PZAPI window); `close()`
  doesn't leave the focus on a hidden element; a B prompt in the bottom bar. Splitscreen issues
  of this window (shared `worldMapFlier`, `getPlayer()`) are fixed in SplitscreenFixes.

- **A confirms world cursors again (42.22)** (`media/lua/client/GamepadTweaks/BuildCursor.lua`).
  Cursors derived from `ISBuildingObject` (chop tree, disassemble, extinguish, paint, rake dung,
  scythe grass, place item, crafting build, traps...) build once `draggingItem.build` is set in
  `DoTileBuilding`. 42.21 set it from `isBuildButtonReleased()` for every input; 42.22 skips that
  for joypad players and nothing replaces it (`ISBuildingObject:onJoypadPressButton` has no A),
  so the prompt says "A: Chop Tree" and A does nothing. The mod wraps
  `ISBuildingObject.onJoypadPressButton` (on `OnGameStart`, the file is in `server/`): A sets
  `build` when `canBeBuild`. `ISMoveableCursor` handles A itself and is untouched.

- **X menu sees fences and walls to the south and east** (`media/lua/client/GamepadTweaks/WallEdge.lua`).
  `ISButtonPrompt:getInteractOptionsButtonObjects` takes the player's square and the three in front,
  but drops every square behind a non-hoppable wall. Walls and fences live only on the north/west
  edges of a square, so the ones south/east of the player belong to the square in front and vanish
  with it: a tall chain-link or metal fence there can't be disassembled from X, while the same fence
  north/west can. The mod adds back only the objects on that shared edge (wall/fence/door/window
  flags, `isNorth()` of thumpables, doors, windows; no containers) and, while that X menu is built,
  keeps their squares from being expanded into the whole room behind: `fetchSquares` pre-marked
  (Java `ISWorldObjectContextMenuLogic.fetch`), `ISMenuContextWorld.getObjectsSquare` skipped,
  `ISDisassembleMenu` / `ISRadioAndTvMenu` (fed by Java `getAllObjects`) filtered.

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
  `preset.<preset>.<layer>.bind.<action>=<button>`. Set a binding to `none` to remove it from
  that layer. Each saved preset has its own layers. Editing Default or Original creates a new
  preset, and copying a preset copies all its layers. Older `preset.<preset>.bind.<action>`
  and global `bind.<action>` entries migrate to the action's original context. Hold actions
  (stick radial, panel navigation) and release actions (parent panel) have their own slots.
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
    `pvp` (`ISEquippedItem` safety toggle for the controller's player), `rotateBuilding` (the
    build cursor of the controller's player: `rotateKey`, as the ROTATE_BUILDING key; the 3D item
    placement spins while held, `ISPlace3DItemCursor.checkRotateJoypad` is wrapped), `voice`
    (push-to-talk, held: `Patches.VoiceHeld` makes `GameKeyboard.isKeyDown(ENABLE_VOICE_TRANSMIT)`,
    read by `VoiceManager`, true while held), `toggleMusic` (`SoundManager.allowMusic`, as
    `updateMusic` on TOGGLE_MUSIC) and `displayFps` (`FPSGraph`, as `IngameState` on DISPLAY_FPS),
    both in `KeyToggles.java`.
  - `panCamera` ("look far", held): vanilla pans a gamepad player's camera while aiming only with
    RB held (`PlayerCamera.update`, hardcoded, not in Options -> Controller), towards the aiming
    stick. `Patches.CameraRB` makes `JoypadManager.isRBPressed` false inside `PlayerCamera.update`,
    so the pan follows the action alone; it is on RB by default in the `aiming` layer of
    `Bindings.lua` (pressed while aiming or looking out of a vehicle, before the world layer;
    vanilla gives RB nothing else then: `getBestRBButtonAction`), and can be moved like any other.
    `CameraPan` (after `PlayerCamera.update`): while the action is held and the player aims
    (or looks out of a vehicle), the camera eases at vanilla's rate towards the reticle, so it
    follows the gyro too.
  - Shift variants and the context key. Interact (E) does more with Shift held, checked only on
    the keyboard (`CharacterInputComponent.isShiftKeyDown`), so a gamepad player can't do them:
    `drive` (Shift when getting in: the driver's seat through the nearest door,
    `ISVehicleMenu.processShiftEnter`, instead of the seat by that door; a passenger switches to
    it), `curtain` (Shift + E at a window / door / window frame: `IsoPlayer.doContextWindow` & co.;
    here the nearest curtain the player can reach, the one faced first,
    `ISWorldObjectContextMenu.onOpenCloseCurtain`), `fireMode` (Shift + Rack:
    `OnPressRackButton(player, gun, true)` cycles a select-fire gun). `useTool`: E while aiming
    with a tool works the square ahead (`CFarming_Interact.onContextKey`: chop, cut a bush, stump,
    ore, dig, sow, scythe, water, fertilize, cure, clean); the action does it without aiming.
    Vanilla runs that once per key press with a flag (`SawOnContextKeyEvent`) that only a keyboard
    Interact press resets, so with a gamepad it worked once per session; the mod wraps
    `onContextKey` to reset it per press of the Interact button for joypad players.
  - `animalRadial`: `AnimalContextMenu.showRadialMenu` (ANIMAL_RADIAL_MENU key, player 0 only in
    `ISUIHandler`); again closes it.

- **In-game layers in Options -> Controller** (`ControllerEditor.lua`, `Bindings.lua`).
  Use the tabs above the controller diagram to assign mod actions by context. Select a button and
  choose an action from `< Add New >`. For example, set D-pad Left to Flashlight under On foot
  and to Horn under Vehicle. The game chooses the active layers for each splitscreen player.
  - Mod actions show icons on the diagram and in the action lists. After changing their Steam
    symbols, regenerate the bundled PNGs with `python3 tools/controller_icons.py /path/to/NotoColorEmoji.ttf`
    (requires Pillow).
  - In the world, the order is Cruise (driver holding the Cruise Control button), Aiming
    (aiming or looking out of a vehicle), On foot or Vehicle, then General. Vehicle includes
    passengers. Each button uses the first assignment it finds.
  - When a panel has controller focus, Inventory (inventory or loot window) takes priority over
    Panels. An empty button uses the normal panel controls.
  - Standard button and axis bindings are edited on General and apply across contexts.
    Layers work with the game's controller input and require the mod's jar.

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
    bottom to top: `onfoot` or `vehicle` (passengers: `steamInput.passengerLayer`), `aiming` (firearm
    in hand only: vanilla's aiming is any combat stance, melee too), `ui`
    (a panel or radial has the joypad focus), `inventory` (the inventory or loot window), `map`; `menu` on every controller in the main menu and
    the pause menu. A layer overrides only what is bound in it, so one paddle can be the light on
    foot and the horn in a car, the gyro can be a mouse only in panels or only while aiming.
    Situational actions are declared in their layer (combat, movement, hands: `onfoot`; car:
    `vehicle`; close / tabs: `ui`; item moves: `inventory`), general ones in the set; a layer's
    actions fire only while it's active (leaving the car releases the horn);
  - Steam lists the set's actions and then the active layer's, in manifest order, with no
    groups, so titles are one or two short words that differ as whole words ("Brake", "Horn",
    "Take all") and start with an icon (color emoji; text-style symbols render small and
    monochrome unless followed by U+FE0F; hotbar slots get keycap numbers, since what a slot
    holds depends on the worn belt / back / webbing);
  - `GamepadTweaks_steamInputPoll` (Lua, every frame) reads the digital actions of every Steam
    controller and returns press/release edges; the controller is matched to the game's joypad by
    `GetGamepadIndexForController` and the "... pad N" joystick name, else the only joypad player;
  - a press runs the action as its button would (in the world, also with a UI focused; while
    paused only actions that work then); a wheel closes and picks the slice on release;
  - `steamInput.enabled=false` turns it off (restart), `steamInput.debugLog=true` logs events;
  - the files are generated by `tools/steam_input.py` from `tools/steam_actions.txt` (section =
    the set or a layer, order, icon, English / Russian title, revision; its header says how to
    edit it), checked against the Lua action lists, and the local Steam templates. A new action
    in the Lua code has to be added there, the script names the missing ones.

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
  - held: Sprint, Manual Floor Attack, Brakes, the Java half of Interact, Aim, Attack, Melee and
    Run set a held state per controller that the game's query also returns (`isSprintButtonDown`,
    `isManualFloorAtkButtonDown`, `isInteractButtonDownInternal`: doors, windows, grapple via
    `IsoPlayer.updateUseKey` -> `doContext`; `isPrecisionAimKeyDownInternal` on foot and
    `isAimKeyDownInternal` in a vehicle, `isAttackButtonDown`, `isMeleeButtonDownInternal`,
    `isRunButtonDown`; the brake in `CarController.updateControls`), so toggle-to-sprint and the
    rest of vanilla still apply. On a gamepad vanilla takes Aim from the right stick (turn, the
    reticle at a fixed distance), Precision Aim from a half-pressed RT (the free firearm reticle),
    Attack from RT past 0.93, Melee from LT, Run from the movement stick past 0.975. The Aim action
    is Precision Aim on foot: with the stick released the reticle snaps in front of the player, and
    the gyro can take it from there; in a vehicle it is the keyboard Aim key for looking. Precision
    Aim has no separate action. Attack needs aiming, as with the mouse;
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
  Left out: Walk To (needs a cursor), Loot (unused), Precision Aim (the Aim action on foot). Not in the in-game
  editor, which already has them (`steamOnly`).

- **Gyro / trackpad aiming** (`AnalogInput.java`, `SteamInput.Analog`, Steam analog action `aim`,
  `absolute_mouse`). The gamepad reticle (`AimingReticle`) aims at the screen center + half screen *
  stick (`getAimingScreenX/Y`), then `AimingMode.lerpAiming` moves it there: eased in precise
  firearm aim, only the direction at a fixed distance in melee / plain aim. Steam's mouse deltas
  (gyro, trackpad; Steam does activation, sensitivity, smoothing) are an offset per player added to
  that target (`Patches.AimTargetX/Y`), kept on the player's screen and dropped when aiming ends, so
  the gyro starts from the stick (or from the player with the stick released). In precise aim the
  reticle itself is moved by the same delta too (`aimingPositions`), so vanilla's easing (meant for
  the stick) doesn't lag the gyro. Steam is read right before `AimingReticle.update` (`Mouse.update`,
  `SteamInput.updateAnalog`), after `SteamAPI_RunCallbacks` ran Steam's frame. `aim` is declared
  in the `aiming` layer (only there it means anything), so the gyro is bound there. With the held
  Aim action, the stick isn't needed at all: on foot it is Precision Aim, so the reticle starts in
  front of the player and the gyro moves it from there.
  Firearms only (`isRangedWeaponEquipped`; the `aiming` layer too): vanilla's "aiming" is also the
  melee / unarmed combat stance, where there's no reticle, so the offset turned the player unseen
  (a shift of the body and the character faced away, the stick no longer matching the facing).
  Melee and unarmed aim with the stick alone; the offset is dropped as when aiming ends.
  Aiming without the Aim binding (half RT or the held Aim action, stick released) snaps the reticle in
  front of the player (`AimingMode.shouldSnapAimInFrontOfPlayer`: no stick, nothing to aim with). The first gyro
  delta then takes the reticle from where it stands (offset = reticle - stick target) and the player
  counts as aimed until aiming ends (`AnalogInput.gyroAiming`, `Patches.GyroAimNoSnap`); modes that
  always snap (melee, unarmed: `fixedAtMinDistance`, `minDistanceAmount == -1`) still do.
  Steering and movement analog actions (`steer` in the `vehicle` layer, `move` in `onfoot`,
  `joystick_move`) are added to the steering stick (`Patches.SteeringInput`, before the mod's
  shaping) and to the Movement axis binding (`Patches.MoveX/Y`, `MoveApplied`; Run at full
  deflection sees it via `Patches.MoveAxisDown`). They are meant for a stick or trackpad, not the
  gyro: Steam drops gyro-to-joystick output after any action set layer change until the game
  window loses and regains focus.
  Pedal actions in the `vehicle` layer (`AnalogInput.pedals`, read by `Throttle`): `gasPedal` /
  `brakePedal` (`AnalogTrigger`, 0..1: the pedals on other triggers, e.g. swapped for the left hand)
  and `steerPedals` (`joystick_move`: X added to the steering, stick up = gas, down = brake /
  reverse: a whole car on one stick). Steam can't split one stick into several analog actions (a
  stick's directions give only digital commands), hence the combined one. The vanilla `Brakes`
  binding (B) is titled "Handbrake" in Steam: it brakes x13, as a handbrake. Each pedal is the larger of its trigger
  (RT / LT) and these, so the analog gas, the brake hold and everything else work the same; with the
  analog gas off they press the vanilla on/off pedals past 0.7. The `steerPedals` Y (up > 0 in
  Steam) gets the game's stick dead zone (controller options, the movement Y axis), rescaled: a
  stick resting slightly off center or pushed sideways to steer held a light pedal, and the analog
  gas keeps a slow speed on any press. The steering part gets none.
  The map (`ISWorldMap`, `ISMap` focused) drops the world layers (`onfoot` / `vehicle` / `aiming`,
  `Bindings.lua playerLayers`): the map pans with the plain gamepad stick, and a stick bound in the
  vehicle layer to `steer` kept steering instead. Other windows keep them (Steam world actions work
  with a window open).
  Layers are switched by difference (`DeactivateActionSetLayer` / `ActivateActionSetLayer` of the
  changed ones only).

- **Controller vibration** (`Rumble.java`, `media/lua/client/GamepadTweaks/Rumble.lua`, `rumble.*`
  settings). Vanilla has no vibration at all: input goes through GLFW, which can't drive the
  motors. Steam Input can, for every controller Steam handles: `SteamInput.vibrate` calls
  `ISteamInput::TriggerVibrationExtended` (big and small motor, right trigger motor on Xbox
  One / Series pads), so it needs `steamInput.enabled` and the game started from Steam.
  Lua picks the events and sends pulses (start at full, fade out linearly). Java reads the live
  heartbeat signal from FMOD and mixes it with the pulses per controller (strongest value
  per motor) and sends the speeds every frame from `pollEvents`.
  Speeds under 0.04 are cut (a motor left that low stalls and spins up by itself, felt as a
  growing buzz), and the stop is sent 3 more times 80 ms apart: a stop right after a speed change
  was sometimes lost and the motors kept going after a shot or a short knock until the next
  pulse ended. While aiming a firearm, `rumble.aiming` (0.3 by default) scales heartbeat,
  thunder, thumps, glass, tools and the power outage blast to reduce gyro reticle shake. The events:
  - ready (`rumble.ready`): two short knocks, once when the loading screen is ready and displays
    "Press A to start", on the controller that can dismiss it;
  - shot: `OnWeaponSwingHitPoint` with a ranged weapon that isn't dry firing
    (`isRangedWeaponEmpty`), stronger and longer with the gun's sound radius (pistol < rifle < shotgun);
  - melee hit: `OnWeaponHitCharacter`, by damage;
  - zombie wounds (`RumbleEvents.wound`): `BodyDamage.AddRandomDamageFromZombie` plays the pain
    voice (`IsoPlayer.playerVoiceSound` "PainFromScratch / Lacerate / Bite", also "PainFromGlassCut")
    exactly when a scratch, laceration or bite gets through the clothes (also on an MP client,
    before it sends the hit): a sharp kick plus a high, slowly fading sting, longer and stronger
    for a bite, then pain pulsations (8 s for a scratch or cut, 20 s for a bite). The whole
    sequence uses `rumble.damage`;
  - getting hurt otherwise: health lost in one tick (falls, car crashes, hits in MP; bleeding and
    hunger stay under the threshold);
  - heartbeat (`Heartbeat.java`): reads the output peaks of the `HeartBeat` FMOD instance that
    `IsoPlayer.updateHeartSound` keeps for each local player. Its timeline sustains at 210 ms
    while the audio continues playing. The low motor follows the peaks, including each thump's
    strength and changes to the game's HeartBeat and sound effects volumes. `rumble.heartbeat`
    adjusts the motor gain;
  - cold (`rumble.cold`): a shiver builds and fades when hypothermia reaches level 2. The
    1.4-second reminders have 30-second gaps at level 2 and 10-second gaps at level 3. At level 4
    the shiver rises into a sustained, gentle tremor with slow swells. It's strongest when sitting,
    weaker when standing and much softer when walking. Running, combat, aiming, busy actions
    and other vibrations interrupt it, with 1.8 seconds of quiet before it can return.
    A cough or sneeze briefly covers the shiver for its own jolt, and the shiver resumes in phase;
  - coughs and sneezes (`rumble.cough`): a short jolt at the onset of the local player's voice
    signal from FMOD. The cough leans on the large motor and the sneeze on the small one. Muffled
    sounds feel softer;
  - thunder: `OnThunderEvent` comes with the flash, the pulse follows with the sound
    (`dist / 300` s, as `ThunderStorm.enqueueThunderEvent`), a crack for a strike, a long roll for
    rumble, by distance, half indoors;
  - blackout (`rumble.blackout`): follows the audio onset of the vanilla
    `WorldEventElectricityShutdown` blast, with a push on the low motor that fades over
    four seconds. A short timer covers FMOD events whose signal can't be read;
  - body (`RumbleEvents.update`): the player's action states (`media/actiongroups/player`) are
    watched every frame: `collide` (sprinting into a wall), `bumped`, the start of `knockeddown`
    and `falldown`, landing from a height (leaving `falling`), `hitreaction*` (also hits stopped
    by clothing);
  - vaulting, climbing, tripping (`RumbleEvents.bodySound`): the animation sounds of the player
    (anim events `PlaySound`, `PlayFenceSound`, `PlayTripSound` in `media/AnimSets/player`, all
    through `CharacterSoundEmitter.playSoundImpl`) fall on the exact frame: a light kick for the
    hands on the fence / window frame / wall (`ClimbOverFenceLow`, `ClimbThroughWindow`,
    `ClimbOverFenceHigh*`), a firmer one for the feet on the ground (`LandLight`, `LandHeavy`),
    a hard one for tripping and the body hitting the ground (`TripOverObstacle`, `FallLight`,
    `FallHeavy`, `BodyHitGround`). Leaving the climb state came well after the landing, so the
    kick read as an unrelated event;
  - burns: `OnPlayerGetDamage` `FIRE` (vanilla shows no reaction, and each step is too small for
    the health check), uneven bursts while burning;
  - window opening: `IsoWindow.ToggleWindow`, when it actually opens or closes (a stuck window
    only on the try that works), not when the action starts;
  - tools: weapon on a door / window / barricade (`OnWeaponHitThumpable`) by damage, axe in a tree
    (`OnWeaponHitTree` and `ISChopTreeAction` `ChopTree`, also on an MP client), prying boards
    (`ISUnbarricadeAction`: creaks while it goes, a pop when it comes off), forcing a lock with
    a crowbar (`ISForceOpen`: each `ForceOpenAttempt`, success);
  - vehicle (`VehicleRumble`, every controller player in it): the grip motors carry the vehicle
    by side (left wheels front and rear = left grip, right = right grip), impacts panned by where
    they come from with some on both grips. Trigger motors (Xbox One / Series, Steam's
    `TriggerVibrationExtended`) differ in frequency and power from the grips, so they don't
    stand for front vs rear: they add a short accent to knocks at the front (front wheel knocks,
    impacts and bodies ahead), never the surface texture (`rumble.triggers`,
    `rumble.triggerGain`). Steam drives trigger motors only on pads it sees as Xbox One
    (`GetInputTypeForHandle` = 3); on others the accent goes to the grip of that side. Crash
    (`BaseVehicle.crash`, before damage, so also without injuries) by impact, from the velocity
    change (`lastLinearVelocity` vs
    `jniLinearVelocity` in the body's axes); running someone over
    (`playSoundVehicleHitCharacter`) by speed, where the body is; zombies banging on the vehicle
    or its window (their `ZombieThumpVehicle(Window)` sound in `CharacterSoundEmitter.playSound`
    with the vehicle as proxy), where the zombie is; light objects that don't stop the vehicle,
    so no crash comes (a cone in front of a wall): cones, signs and such
    (`applyImpulseFromHitObject` below their break speed, `IsoObject.HitByVehicle` above it; not
    on an MP client, where `IsoObject.Collision` doesn't run), bushes and small trees
    (`applyImpulseFromHitPlant`), once per contact, by speed, where the object is;
  - suspension: per wheel `wheelInfo.suspensionLength` against the script's rest length and
    travel; a quick compression or drop is a knock on that wheel's side, reaching the end of
    the travel a hard hit; a body under a wheel (`testCollisionWithProneCharacter` per-wheel
    impulse) a knock on its side. Decorative curb and parking stop sprites are checked along
    each wheel's path, with a stronger and longer kick at higher speeds;
  - road surface per wheel (floor sprite, as `ParameterVehicleRoadMaterial`, plus plowed land
    `vegetation_farming_*`): a knock on the wheel that leaves or gets back on the asphalt, and
    each wheel's side gets the texture of its own surface (grips only); speed makes it stronger and denser
    (grain intervals are for 40 km/h, scaled by 40 / speed within x0.4..x3). Surfaces differ in
    strength and gaps, not only rhythm (dense grains of close strength make one even buzz, and a
    dirt road felt like grass): a gravel road (`blends_street_01_48/53/54/55`, the long country
    roads) is nearly smooth with a faint sparse crunch, a dirt road (brown rutted track) uneven with
    ruts now and then, grass soft swells, sand long waves, snow barely, furrows a firm beat per 0.7 tiles,
    railway sleepers the hardest clack per 0.65 tiles (with a trigger accent at the front).
    Grass and the like fade to a third over continuous off-road time and come back after 10 s on
    asphalt; furrows and rails don't fade. `rumble.debugLog` logs the floor sprite under wheel 0
    when its surface changes;
  - motor test (Options -> Mods button, `GamepadTweaks_rumbleTest`): each motor alone in turn,
    left grip, right grip, left trigger, right trigger, to see which is where on a given pad;
  - glass breaking within 3 tiles (`IsoWindow.smashWindow`), weaker further away;
  - zombies banging on doors, windows, barricades and fences within 4 tiles
    (`IsoGameCharacter.setTimeThumping`, bumped once per thump by `ThumpState.execute`): only the
    first 2 knocks, the surprise; a crowd banging on a fence the player sees and fights shook the
    controller for no reason. Felt again after 15 s without a knock near that player;
  - jump scare: the "ZombieSurprisedPlayer" sting of `IsoPlayer.updateLOS` (caught in
    `CharacterSoundEmitter.playSoundImpl`), a hard kick, by the game's jump scare volume (0 = none).
  Each event has its own strength (`rumble.<event>`), plus `rumble.strength`; also in
  Options -> Mods.
  Splitscreen: every pulse goes to one game controller (`player:getJoypadBind()`), and
  `SteamInput.controllerId` maps it to its Steam handle. Shared events reach several players on
  purpose (vehicle: everyone in it; thunder; glass and zombie thumps nearby), so a passenger feels
  the road the driver picks: `rumble.passenger` scales vehicle vibration for every seat but the
  driver's. `rumble.player1..4` turns vibration off for one splitscreen player (IsoPlayer index + 1).
  A single Steam controller the mod couldn't map takes the pulses of the only joypad player, and
  none when several players are on joypads (it used to take everyone's). `rumble.debugLog` logs
  each pulse with its player and which Steam controller starts vibrating for which player.

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
  - `interact.notBehind`, `interact.facing`, `interact.cursor`, `interact.lootFacing`: `InteractTarget`, `LootFacing.lua`;
  - `aim.snapFix`: `AimSnap`;
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

The jar is built against the installed game. When `~/Zomboid/tools/pz-versions.sh` is there,
the build also keeps the installed `projectzomboid.jar` in `~/Zomboid/jars/<version>/` and
compiles against every kept version (stable and beta branch); "does NOT compile against game X"
means the mod would break in X. After a test run, `~/Zomboid/tools/checklog.py GamepadTweaks`
summarizes `console.txt` (mod loads per save, errors, Steam Input per session).

## Source

https://github.com/fu11zero/gamepad-tweaks

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
