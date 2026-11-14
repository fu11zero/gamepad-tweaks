package dev.gamepadtweaks;

import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;

// Tunables in ~/Zomboid/GamepadTweaks.properties.
// The file is re-read when it changes (checked once a second), so values can be
// tuned while the game is running. Missing file is created with defaults.
public final class Settings {
    private static final String FILE_NAME = "GamepadTweaks.properties";
    private static final long CHECK_INTERVAL_MS = 1000;

    private static final String DEFAULTS = """
            # Gamepad Tweaks settings. Re-read automatically while the game runs.
            # Delete the file to restore defaults.
            # The main settings are also in the game: Options -> Mods -> Gamepad Tweaks.

            # --- Steering ---------------------------------------------------------
            # false = vanilla gamepad steering (everything below is off).
            steering.enabled=true
            # Steer with the raw stick X: no stick dead zone, no diagonal x1.41 stretch
            # (false = the game's stick value, with its dead zone).
            steering.rawStick=true

            # Full stick deflection = the vehicle's max steering angle at the current
            # speed (vanilla clamps the angle instead, so at speed the outer part of
            # the stick travel does nothing and small deflections are too sharp).
            steering.scaleToSpeedClamp=true

            # Response curve: output = input ^ exponent (1 = linear, 2 = soft center).
            # The exponent grows from lowSpeedExponent at 0 km/h
            # to highSpeedExponent at highSpeedKmh and above.
            steering.lowSpeedExponent=1.0
            steering.highSpeedExponent=2.0
            steering.highSpeedKmh=80

            # The wheels turn at a constant rate towards the stick (false = vanilla: a lag
            # that grows with speed, fast return only from inside the stick dead zone).
            steering.constantRateWheel=true
            # How fast the wheels turn, angle units per frame at 60 fps
            # (full lock is ~0.9 standing still, ~0.4-0.6 at speed).
            # turnRate at 0 km/h, highSpeedTurnRate at highSpeedKmh and above;
            # returnRate when going back to (or through) center.
            # Vanilla returns at 0.04 and turns with a lag that grows with speed.
            steering.turnRate=0.05
            steering.highSpeedTurnRate=0.03
            steering.returnRate=0.06

            # Log stick and wheel angle once a second (for tuning).
            steering.debugLog=false

            # Drifting center: a released stick rests slightly off zero and the car
            # drives in an arc. The steering gets the distance from a learned center,
            # without any dead zone. While the stick stands still (range below
            # recenterStillRange over recenterStillMs: the jitter zone, used only to
            # see that the stick stopped) within recenterZone of zero, the center glides
            # to the mean of that window at recenterRate per second.
            steering.recenter=true
            steering.recenterZone=0.08
            steering.recenterStillRange=0.012
            steering.recenterStillMs=250
            steering.recenterRate=0.1
            # Learning is armed only after a release: the stick was further than
            # releaseFrom from the center and got back within recenterZone in less than
            # releaseMaxMs (direction doesn't matter, the spring can overshoot).
            # Moving the stick slowly further than disarmDistance from where it rested
            # disarms it, so holding the stick slightly off on purpose isn't eaten;
            # not checked for releaseSettleMs after a release (overshoot swings).
            steering.releaseFrom=0.2
            steering.releaseMaxMs=200
            steering.releaseSettleMs=500
            steering.disarmDistance=0.025
            # Distance from the center cut out as a dead zone (output is rescaled).
            # 0 = none: jitter averages out, the curve squashes it at speed.
            steering.noiseDeadZone=0

            # --- Throttle ---------------------------------------------------------
            # Analog gas (RT) and brake / reverse (LT) for a gamepad driver (vanilla: on/off
            # at 70% of the travel). Every pedal position has its own cruising speed: the
            # push fades as the car speeds up and is gone at maxSpeed * pedal ^ (1/dragExponent),
            # easing off brakes with the engine down to the new speed. Full pedal = vanilla.
            # false = vanilla pedals (everything below is off).
            throttle.analog=true
            # Trigger travel (0..1) ignored as noise (a drifting trigger would creep the car and
            # start the engine), and travel that counts as fully pressed. 0 is fine for triggers
            # that rest exactly at zero.
            throttle.deadZone=0.02
            throttle.fullAt=0.98
            # Pedal = travel ^ pedalCurve (1 = linear, less = more push at the start of the
            # travel, like a real car's pedal, more = finer at a light press but laggy).
            # A car at a stop needs ~10% of the full force to start rolling: with 0.7 that is
            # ~5% of the travel, with 1.5 ~20%. Cruising speeds with dragExponent 2 (flat road):
            # 10% travel ~ 45% of the top speed, 30% ~ 65%, 50% ~ 80%.
            throttle.pedalCurve=0.7
            # How fast the drag grows with speed: 2 = like air drag, 1 = linear
            # (cruising speed = maxSpeed * pedal).
            throttle.dragExponent=2.0
            # Engine braking above the pedal's speed, x the vanilla released-pedal braking.
            throttle.engineBraking=1.0
            # Brake pedal (LT going forward, RT rolling back) = travel ^ brakeCurve.
            throttle.brakeCurve=1.0
            # Experimental: LT that brakes the car going forward holds it at the stop until
            # released; pressed again it reverses (vanilla: reverses at once). RT while backing
            # up stays vanilla. Works with the vanilla on/off pedals too.
            throttle.brakeHold=false
            # With analog pedals the tachometer and the engine sound show an RPM from the speed
            # (vanilla revs up at a fixed rate on any pedal); gears and physics stay vanilla.
            # How fast the engine load sound parameter follows the pedal, share per second.
            throttle.soundRate=4.0
            # Log pedals, forces and RPM once a second.
            throttle.debugLog=false

            # --- Triggers ---------------------------------------------------------
            # The game's dead zone is not applied to the triggers (they rest at zero
            # and need none). false = vanilla (the options screen stick dead zone).
            triggers.noDeadZone=true
            # Log every change of the raw trigger value (what the controller driver
            # reports, before any game code), to find jumps.
            triggers.debugLog=false

            # --- Buttons ----------------------------------------------------------
            # Crouch toggle on press, not on release (only without the left stick radial menu).
            actions.crouchOnPress=true
            # Toggle-to-sprint on press, not on release.
            actions.sprintOnPress=true
            # Enter/exit a vehicle only with the A button prompt; vanilla also does it on
            # an Interact click for any vehicle nearby.
            actions.vehicleOnlyByPrompt=true

            # --- Map --------------------------------------------------------------
            # World map and paper maps: past the game's stick dead zone the map pans
            # at a speed that follows the stick deflection, the triggers zoom at a
            # speed that follows how far they are pressed (vanilla: on/off steps).
            # false = vanilla map controls.
            map.smooth=true
            # Pan speed at full deflection, map heights per second.
            map.panSpeed=1.0
            # Pan speed = deflection ^ exponent (1 = linear, 2 = finer at small deflections).
            map.panExponent=2.0
            # D-pad = this stick deflection.
            map.dpadDeflection=0.5
            # Zoom speed with a trigger fully pressed, zoom levels per second
            # (one vanilla trigger click = 1 level, each level = x2).
            map.zoomSpeed=3.0
            map.zoomExponent=1.5
            # Trigger travel (0..1) ignored as noise.
            map.triggerDeadZone=0.05

            # --- Steam Input ------------------------------------------------------
            # Show the mod's actions (horn, lights, drop items, wheels...) in the Steam
            # controller configurator as game actions, so they can go on any button,
            # back paddle, long/double press or chord. Sticks and buttons stay a gamepad.
            # Needs a game restart.
            steamInput.enabled=true
            # Steam action set layer for vehicle passengers: vehicle (as the driver) or
            # onfoot. Layers follow the situation (on foot, vehicle, aiming, panel, map,
            # main/pause menu), so one button can do different things in each.
            steamInput.passengerLayer=vehicle
            # Log every Steam action press/release and controller mapping.
            steamInput.debugLog=false

            # --- Vibration --------------------------------------------------------
            # Controller vibration (vanilla has none). Works through Steam Input, so
            # it needs steamInput.enabled=true and the game started from Steam.
            rumble.enabled=true
            # Overall strength, 0..2 (motor speed is capped at full).
            rumble.strength=1.0
            # Strength per event, 0 = off:
            # shot - firing a gun (by the gun); hit - melee hit on a target (by damage);
            # damage - getting hurt (by health lost), hit reactions, burns; bump - pushed,
            # running into a wall; fall - knocked down, falling, landing, vaulting;
            # vehicle - crash (by impact and side), running someone over (by speed);
            # suspension - bumps under each wheel, bodies, bottoming out; road - leaving
            # the asphalt and the feel of each surface (fades on long off-road drives);
            # window - smashing glass nearby, a window opening; tool - axe on doors and
            # trees, prying boards, forcing doors with a crowbar; thump - zombies banging
            # on doors, windows and your vehicle nearby; thunder - by distance, with the
            # sound; scare - the jump scare sting
            # (a zombie suddenly right next to you, follows the game's jump scare volume);
            # heartbeat - while panicked.
            rumble.shot=1.0
            rumble.hit=1.0
            rumble.damage=1.0
            rumble.bump=1.0
            rumble.fall=1.0
            rumble.vehicle=1.0
            rumble.suspension=1.0
            rumble.road=1.0
            rumble.window=1.0
            rumble.tool=1.0
            rumble.thump=1.0
            rumble.thunder=1.0
            rumble.scare=1.0
            rumble.heartbeat=1.0
            # Trigger motors (Xbox One / Series): in a vehicle a short accent on knocks at
            # the front (front wheels, impacts ahead), never the surface texture; the grips
            # carry the vehicle by side. false = grips only.
            rumble.triggers=true
            # Strength of that trigger accent.
            rumble.triggerGain=0.6
            # Log every pulse and the player's action states.
            rumble.debugLog=false

            # --- Button actions ---------------------------------------------------
            # Actions that vanilla hardcodes to buttons (media/lua/client/GamepadTweaks/Bindings.lua).
            # Per controller preset (Options -> Controller), like the regular bindings:
            # preset.<preset>.bind.<action>=<button>: A B X Y LeftBump RightBump LeftStick
            # RightStick Back Start Guide DPadUp DPadDown DPadLeft DPadRight, or none to free
            # the button for the regular bindings. Characters other than letters, digits, _ and -
            # in the preset name are written as %<code>; (a space: %32;).
            # A missing line = the vanilla button. An action set to a button takes it from
            # the action that has it by default. The built-in presets (Default, Original)
            # always have the defaults.
            #preset.Custom.bind.vehicleWheel=DPadUp
            #preset.Custom.bind.emoteWheel=DPadDown
            #preset.Custom.bind.equipWheel=DPadLeft
            #preset.Custom.bind.extraWheel=DPadRight
            #preset.Custom.bind.commandWheel=Back
            #preset.Custom.bind.pause=Start
            # cruiseFaster/cruiseSlower: while driving with the CruiseControl button held.
            # stickRadial: held in the world (crouch/sit/auto-walk radial, if enabled in options).
            # uiNavigation: held in a UI (panel navigation); uiNavigateParent: released while navigating.
            #preset.Custom.bind.cruiseFaster=DPadUp
            #preset.Custom.bind.cruiseSlower=DPadDown
            #preset.Custom.bind.stickRadial=LeftStick
            #preset.Custom.bind.uiNavigation=RightBump
            #preset.Custom.bind.uiNavigateParent=LeftBump
            # panCamera: camera pan ("look far") while aiming, the button vanilla hardcodes for it.
            #preset.Custom.bind.panCamera=RightBump
            # Keyboard-only actions, unbound by default (media/lua/client/GamepadTweaks/KeyActions.lua).
            # Main:
            #preset.Custom.bind.lightSource=
            #preset.Custom.bind.dropPrimary=
            #preset.Custom.bind.dropSecondary=
            #preset.Custom.bind.dropBothHands=
            #preset.Custom.bind.dropBag=
            #preset.Custom.bind.dropHandsAndBag=
            #preset.Custom.bind.grabCorpse=
            #preset.Custom.bind.sharpenWeapon=
            #preset.Custom.bind.sitOnGround=
            #preset.Custom.bind.searchMode=
            #preset.Custom.bind.shout=
            #preset.Custom.bind.releaseRope=
            #preset.Custom.bind.engine=
            #preset.Custom.bind.headlights=
            #preset.Custom.bind.heater=
            #preset.Custom.bind.horn=
            #preset.Custom.bind.switchSeat=
            #preset.Custom.bind.vehicleInfo=
            # Extra:
            #preset.Custom.bind.map=
            #preset.Custom.bind.craftingMenu=
            #preset.Custom.bind.buildingMenu=
            #preset.Custom.bind.skills=
            #preset.Custom.bind.health=
            #preset.Custom.bind.protection=
            #preset.Custom.bind.info=
            #preset.Custom.bind.survivalGuide=
            #preset.Custom.bind.hotbar1=
            #preset.Custom.bind.hotbar2=
            #preset.Custom.bind.hotbar3=
            #preset.Custom.bind.hotbar4=
            #preset.Custom.bind.hotbar5=
            #preset.Custom.bind.hotbar6=
            #preset.Custom.bind.hotbar7=
            #preset.Custom.bind.hotbar8=
            #preset.Custom.bind.timePause=
            #preset.Custom.bind.timeNormal=
            #preset.Custom.bind.timeFast1=
            #preset.Custom.bind.timeFast2=
            #preset.Custom.bind.timeFast3=
            #preset.Custom.bind.moveFurniture=
            #preset.Custom.bind.toggleUI=
            #preset.Custom.bind.screenshot=
            #preset.Custom.bind.pvp=
            # Inventory, unbound by default: pressed while the inventory or loot window has the
            # focus, instead of what vanilla does with that button there (InventoryActions.lua).
            #preset.Custom.bind.invTransferAll=
            #preset.Custom.bind.invTransferSameType=
            #preset.Custom.bind.invTransferSameTypeNearby=
            #preset.Custom.bind.invAllToFloor=
            #preset.Custom.bind.invDropSelected=
            #preset.Custom.bind.invTransferStack=
            #preset.Custom.bind.invTransferOne=
            #preset.Custom.bind.invUse=
            #preset.Custom.bind.invUnpack=
            """;

    public static volatile boolean steeringEnabled = true;
    public static volatile boolean rawStick = true;
    public static volatile boolean constantRateWheel = true;
    public static volatile boolean scaleToSpeedClamp = true;
    public static volatile float lowSpeedExponent = 1.0f;
    public static volatile float highSpeedExponent = 2.0f;
    public static volatile float highSpeedKmh = 80f;
    public static volatile float turnRate = 0.05f;
    public static volatile float highSpeedTurnRate = 0.03f;
    public static volatile float returnRate = 0.06f;
    public static volatile boolean debugLog = false;
    public static volatile boolean recenter = true;
    public static volatile float recenterZone = 0.08f;
    public static volatile float recenterStillRange = 0.012f;
    public static volatile float recenterStillMs = 250f;
    public static volatile float recenterRate = 0.1f;
    public static volatile float noiseDeadZone = 0f;
    public static volatile float releaseFrom = 0.2f;
    public static volatile float releaseMaxMs = 200f;
    public static volatile float releaseSettleMs = 500f;
    public static volatile float disarmDistance = 0.025f;
    public static volatile boolean throttleAnalog = true;
    public static volatile float throttleDeadZone = 0.02f;
    public static volatile float throttleFullAt = 0.98f;
    public static volatile float throttleCurve = 0.7f;
    public static volatile float throttleDragExponent = 2.0f;
    public static volatile float throttleEngineBraking = 1.0f;
    public static volatile float throttleBrakeCurve = 1.0f;
    public static volatile boolean throttleBrakeHold = false;
    public static volatile float throttleSoundRate = 4.0f;
    public static volatile boolean throttleDebugLog = false;
    public static volatile boolean triggersNoDeadZone = true;
    public static volatile boolean triggersDebugLog = false;
    public static volatile boolean crouchOnPress = true;
    public static volatile boolean sprintOnPress = true;
    public static volatile boolean vehicleOnlyByPrompt = true;
    public static volatile boolean mapSmooth = true;
    public static volatile float mapPanSpeed = 1.0f;
    public static volatile float mapPanExponent = 2.0f;
    public static volatile float mapDpadDeflection = 0.5f;
    public static volatile float mapZoomSpeed = 3.0f;
    public static volatile float mapZoomExponent = 1.5f;
    public static volatile float mapTriggerDeadZone = 0.05f;
    public static volatile boolean steamInput = true;
    public static volatile boolean steamInputDebugLog = false;
    public static volatile boolean rumble = true;
    public static volatile float rumbleStrength = 1.0f;
    public static volatile boolean rumbleDebugLog = false;
    public static volatile boolean rumbleTriggers = true;
    public static volatile float rumbleTriggerGain = 0.6f;

    // All values as read, for the Lua side (button actions).
    private static volatile Properties raw = new Properties();
    private static volatile int version;

    private static Path path;
    private static long lastCheck;
    private static long lastModified = Long.MIN_VALUE;

    private Settings() {}

    /** Raw value of {@code key} or nil. */
    @LuaMethod(name = "GamepadTweaks_getSetting", global = true)
    public static String luaGet(String key) {
        refresh();
        return key == null ? null : raw.getProperty(key);
    }

    /** Changes every time the file is re-read, so Lua knows when to re-read its values. */
    @LuaMethod(name = "GamepadTweaks_settingsVersion", global = true)
    public static double luaVersion() {
        refresh();
        return version;
    }

    /**
     * Sets {@code key=value} in the file and re-reads it (the settings panel); null removes the
     * line. The rest of the file stays as it is: the line is replaced in place, or added after
     * its commented-out example ({@code #key=...}), or at the end.
     */
    @LuaMethod(name = "GamepadTweaks_setSetting", global = true)
    public static boolean luaSet(String key, String value) {
        if (key == null || key.isBlank() || key.contains("=") || key.contains("\n")
                || (value != null && value.contains("\n"))) {
            return false;
        }
        try {
            lastCheck = 0;
            refresh(); // creates the file if it's missing
            List<String> lines = new ArrayList<>(Files.readAllLines(path, StandardCharsets.UTF_8));
            String line = value == null ? null : key + "=" + value;
            int set = -1;
            int example = -1;
            for (int i = 0; i < lines.size(); i++) {
                String t = lines.get(i).trim();
                if (isKeyLine(t, key)) {
                    set = i;
                } else if (example < 0 && t.startsWith("#") && isKeyLine(t.substring(1).trim(), key)) {
                    example = i;
                }
            }
            if (set >= 0) {
                if (line == null) {
                    lines.remove(set);
                } else {
                    lines.set(set, line);
                }
            } else if (line != null) {
                if (example >= 0) {
                    lines.add(example + 1, line);
                } else {
                    lines.add(line);
                }
            } else {
                return true;
            }
            Files.write(path, lines, StandardCharsets.UTF_8);
            lastModified = Files.getLastModifiedTime(path).toMillis();
            load();
            return true;
        } catch (IOException | RuntimeException e) {
            Log.error("can't write " + key, e);
            return false;
        }
    }

    private static boolean isKeyLine(String line, String key) {
        if (!line.startsWith(key)) {
            return false;
        }
        String rest = line.substring(key.length()).trim();
        return rest.startsWith("=") || rest.startsWith(":");
    }

    /** Cheap to call every frame. */
    public static void refresh() {
        long now = System.currentTimeMillis();
        if (now - lastCheck < CHECK_INTERVAL_MS) {
            return;
        }
        lastCheck = now;
        try {
            if (path == null) {
                path = Path.of(ZomboidFileSystem.instance.getCacheDir(), FILE_NAME);
            }
            if (!Files.exists(path)) {
                try (Writer w = Files.newBufferedWriter(path, StandardCharsets.UTF_8)) {
                    w.write(DEFAULTS);
                }
                Log.info("created " + path);
            }
            long modified = Files.getLastModifiedTime(path).toMillis();
            if (modified == lastModified) {
                return;
            }
            if (migrate()) {
                modified = Files.getLastModifiedTime(path).toMillis();
            }
            lastModified = modified;
            load();
        } catch (IOException | RuntimeException e) {
            Log.error("can't read settings", e);
        }
    }

    // Old throttle.curve (default 1.5) was written into every file from the template: a light
    // press barely moved the car (~20% of the travel before it starts rolling). It is replaced by
    // throttle.pedalCurve at the new default, comment included, so players get the new feel.
    private static final String OLD_CURVE_COMMENT = """
            # Pedal = travel ^ curve (1 = linear, more = finer at a light press).
            # With 1.5 and dragExponent 2: 10% travel ~ 18% of the top speed, 30% ~ 40%,
            # 50% ~ 60%, 75% ~ 80%.
            """;

    private static boolean migrate() throws IOException {
        String text = Files.readString(path, StandardCharsets.UTF_8);
        if (!text.lines().anyMatch(l -> isKeyLine(l.trim(), "throttle.curve"))) {
            return false;
        }
        String block = DEFAULTS.substring(DEFAULTS.indexOf("# Pedal = travel ^ pedalCurve"));
        block = block.substring(0, block.indexOf('\n', block.indexOf("throttle.pedalCurve=")) + 1);
        String newline = text.contains("\r\n") ? "\r\n" : "\n";
        String oldComment = OLD_CURVE_COMMENT.replace("\n", newline);
        boolean hasNew = text.lines().anyMatch(l -> isKeyLine(l.trim(), "throttle.pedalCurve"));
        StringBuilder out = new StringBuilder();
        for (String line : text.split("\\R", -1)) {
            if (isKeyLine(line.trim(), "throttle.curve")) {
                if (!hasNew) {
                    out.append(block.replace("\n", newline));
                }
            } else {
                out.append(line).append(newline);
            }
        }
        String result = out.substring(0, out.length() - newline.length()).replace(oldComment, "");
        Files.writeString(path, result, StandardCharsets.UTF_8);
        Log.info("settings: throttle.curve replaced by throttle.pedalCurve");
        return true;
    }

    private static void load() throws IOException {
        Properties p = new Properties();
        try (Reader r = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            p.load(r);
        }
        steeringEnabled = bool(p, "steering.enabled", true);
        rawStick = bool(p, "steering.rawStick", true);
        constantRateWheel = bool(p, "steering.constantRateWheel", true);
        scaleToSpeedClamp = bool(p, "steering.scaleToSpeedClamp", true);
        lowSpeedExponent = num(p, "steering.lowSpeedExponent", 1.0f, 0.1f, 5f);
        highSpeedExponent = num(p, "steering.highSpeedExponent", 2.0f, 0.1f, 5f);
        highSpeedKmh = num(p, "steering.highSpeedKmh", 80f, 1f, 1000f);
        turnRate = num(p, "steering.turnRate", 0.05f, 0.001f, 1f);
        highSpeedTurnRate = num(p, "steering.highSpeedTurnRate", 0.03f, 0.001f, 1f);
        returnRate = num(p, "steering.returnRate", 0.06f, 0.001f, 1f);
        debugLog = bool(p, "steering.debugLog", false);
        recenter = bool(p, "steering.recenter", true);
        recenterZone = num(p, "steering.recenterZone", 0.08f, 0f, 0.5f);
        recenterStillRange = num(p, "steering.recenterStillRange", 0.012f, 0f, 0.2f);
        recenterStillMs = num(p, "steering.recenterStillMs", 250f, 20f, 5000f);
        recenterRate = num(p, "steering.recenterRate", 0.1f, 0f, 10f);
        noiseDeadZone = num(p, "steering.noiseDeadZone", 0f, 0f, 0.2f);
        releaseFrom = num(p, "steering.releaseFrom", 0.2f, 0.05f, 1f);
        releaseMaxMs = num(p, "steering.releaseMaxMs", 200f, 10f, 2000f);
        releaseSettleMs = num(p, "steering.releaseSettleMs", 500f, 0f, 5000f);
        disarmDistance = num(p, "steering.disarmDistance", 0.025f, 0.001f, 0.5f);
        throttleAnalog = bool(p, "throttle.analog", true);
        throttleDeadZone = num(p, "throttle.deadZone", 0.02f, 0f, 0.5f);
        throttleFullAt = num(p, "throttle.fullAt", 0.98f, 0.5f, 1f);
        throttleCurve = num(p, "throttle.pedalCurve", 0.7f, 0.2f, 5f);
        throttleDragExponent = num(p, "throttle.dragExponent", 2.0f, 0.5f, 5f);
        throttleEngineBraking = num(p, "throttle.engineBraking", 1.0f, 0f, 10f);
        throttleBrakeCurve = num(p, "throttle.brakeCurve", 1.0f, 0.2f, 5f);
        throttleBrakeHold = bool(p, "throttle.brakeHold", false);
        throttleSoundRate = num(p, "throttle.soundRate", 4.0f, 0.1f, 100f);
        throttleDebugLog = bool(p, "throttle.debugLog", false);
        triggersNoDeadZone = bool(p, "triggers.noDeadZone", true);
        triggersDebugLog = bool(p, "triggers.debugLog", false);
        crouchOnPress = bool(p, "actions.crouchOnPress", true);
        sprintOnPress = bool(p, "actions.sprintOnPress", true);
        vehicleOnlyByPrompt = bool(p, "actions.vehicleOnlyByPrompt", true);
        mapSmooth = bool(p, "map.smooth", true);
        mapPanSpeed = num(p, "map.panSpeed", 1.0f, 0.01f, 20f);
        mapPanExponent = num(p, "map.panExponent", 2.0f, 0.1f, 5f);
        mapDpadDeflection = num(p, "map.dpadDeflection", 0.5f, 0.01f, 1f);
        mapZoomSpeed = num(p, "map.zoomSpeed", 3.0f, 0.01f, 20f);
        mapZoomExponent = num(p, "map.zoomExponent", 1.5f, 0.1f, 5f);
        mapTriggerDeadZone = num(p, "map.triggerDeadZone", 0.05f, 0f, 0.5f);
        steamInput = bool(p, "steamInput.enabled", true);
        steamInputDebugLog = bool(p, "steamInput.debugLog", false);
        rumble = bool(p, "rumble.enabled", true);
        rumbleStrength = num(p, "rumble.strength", 1.0f, 0f, 2f);
        rumbleDebugLog = bool(p, "rumble.debugLog", false);
        rumbleTriggers = bool(p, "rumble.triggers", true);
        rumbleTriggerGain = num(p, "rumble.triggerGain", 0.6f, 0f, 2f);
        raw = p;
        version++;
        Log.info("settings loaded: steering=" + steeringEnabled + " rawStick=" + rawStick
                + " constantRateWheel=" + constantRateWheel
                + " scaleToSpeedClamp=" + scaleToSpeedClamp
                + " exponent=" + lowSpeedExponent + ".." + highSpeedExponent
                + " @" + highSpeedKmh + "km/h turnRate=" + turnRate + ".." + highSpeedTurnRate
                + " returnRate=" + returnRate + " debugLog=" + debugLog
                + " recenter=" + recenter + " zone=" + recenterZone
                + " still=" + recenterStillRange + "/" + recenterStillMs + "ms rate=" + recenterRate
                + " noiseDeadZone=" + noiseDeadZone
                + " release=" + releaseFrom + "/" + releaseMaxMs + "ms settle=" + releaseSettleMs
                + "ms disarm=" + disarmDistance
                + " throttle: analog=" + throttleAnalog + " deadZone=" + throttleDeadZone + ".." + throttleFullAt
                + " curve=" + throttleCurve + " drag^" + throttleDragExponent + " engineBraking=" + throttleEngineBraking
                + " brakeCurve=" + throttleBrakeCurve + " brakeHold=" + throttleBrakeHold
                + " soundRate=" + throttleSoundRate + " debugLog=" + throttleDebugLog
                + " triggers.noDeadZone=" + triggersNoDeadZone + " triggers.debugLog=" + triggersDebugLog
                + " actions: crouchOnPress=" + crouchOnPress + " sprintOnPress=" + sprintOnPress
                + " vehicleOnlyByPrompt=" + vehicleOnlyByPrompt
                + " map: smooth=" + mapSmooth + " pan=" + mapPanSpeed + "^" + mapPanExponent + " dpad=" + mapDpadDeflection
                + " zoom=" + mapZoomSpeed + "^" + mapZoomExponent + " triggerDeadZone=" + mapTriggerDeadZone
                + " rumble=" + rumble + " strength=" + rumbleStrength);
    }

    /** rumble.&lt;event&gt; strength multiplier, 0..2 (1 if missing). */
    public static float rumbleEvent(String event) {
        return event == null ? 1f : num(raw, "rumble." + event, 1.0f, 0f, 2f);
    }

    private static boolean bool(Properties p, String key, boolean def) {
        String v = p.getProperty(key);
        return v == null ? def : Boolean.parseBoolean(v.trim());
    }

    private static float num(Properties p, String key, float def, float min, float max) {
        String v = p.getProperty(key);
        if (v == null) {
            return def;
        }
        try {
            return Math.max(min, Math.min(max, Float.parseFloat(v.trim())));
        } catch (NumberFormatException e) {
            Log.warn(key + "=" + v + " is not a number, using " + def);
            return def;
        }
    }
}
