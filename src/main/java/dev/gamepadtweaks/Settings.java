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

            # --- Steering ---------------------------------------------------------
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

            # --- Triggers ---------------------------------------------------------
            # The game's dead zone is not applied to the triggers (they rest at zero
            # and need none). Log every change of the raw trigger value (what the
            # controller driver reports, before any game code), to find jumps.
            triggers.debugLog=false

            # --- Map --------------------------------------------------------------
            # World map and paper maps: past the game's stick dead zone the map pans
            # at a speed that follows the stick deflection, the triggers zoom at a
            # speed that follows how far they are pressed (vanilla: on/off steps).
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

            # --- Button actions ---------------------------------------------------
            # Actions that vanilla hardcodes to buttons (media/lua/client/GamepadTweaks/Bindings.lua).
            # bind.<action>=<button>: A B X Y LeftBump RightBump LeftStick RightStick
            # Back Start Guide DPadUp DPadDown DPadLeft DPadRight, or none to free the
            # button for the regular bindings (Options -> Controller).
            # A missing line = the vanilla button. An action set to a button takes it from
            # the action that has it by default.
            #bind.vehicleWheel=DPadUp
            #bind.emoteWheel=DPadDown
            #bind.equipWheel=DPadLeft
            #bind.extraWheel=DPadRight
            #bind.commandWheel=Back
            #bind.pause=Start
            # cruiseFaster/cruiseSlower: while driving with the CruiseControl button held.
            # stickRadial: held in the world (crouch/sit/auto-walk radial, if enabled in options).
            # uiNavigation: held in a UI (panel navigation); uiNavigateParent: released while navigating.
            #bind.cruiseFaster=DPadUp
            #bind.cruiseSlower=DPadDown
            #bind.stickRadial=LeftStick
            #bind.uiNavigation=RightBump
            #bind.uiNavigateParent=LeftBump
            # Keyboard-only actions, unbound by default (media/lua/client/GamepadTweaks/KeyActions.lua).
            # Main:
            #bind.lightSource=
            #bind.dropPrimary=
            #bind.dropSecondary=
            #bind.dropBothHands=
            #bind.dropBag=
            #bind.dropHandsAndBag=
            #bind.grabCorpse=
            #bind.sharpenWeapon=
            #bind.sitOnGround=
            #bind.searchMode=
            #bind.shout=
            #bind.releaseRope=
            #bind.engine=
            #bind.headlights=
            #bind.heater=
            #bind.horn=
            #bind.switchSeat=
            #bind.vehicleInfo=
            # Extra:
            #bind.map=
            #bind.craftingMenu=
            #bind.buildingMenu=
            #bind.skills=
            #bind.health=
            #bind.protection=
            #bind.info=
            #bind.survivalGuide=
            #bind.hotbar1=
            #bind.hotbar2=
            #bind.hotbar3=
            #bind.hotbar4=
            #bind.hotbar5=
            #bind.hotbar6=
            #bind.hotbar7=
            #bind.hotbar8=
            #bind.timePause=
            #bind.timeNormal=
            #bind.timeFast1=
            #bind.timeFast2=
            #bind.timeFast3=
            #bind.moveFurniture=
            #bind.toggleUI=
            #bind.screenshot=
            #bind.pvp=
            """;

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
    public static volatile boolean triggersDebugLog = false;
    public static volatile float mapPanSpeed = 1.0f;
    public static volatile float mapPanExponent = 2.0f;
    public static volatile float mapDpadDeflection = 0.5f;
    public static volatile float mapZoomSpeed = 3.0f;
    public static volatile float mapZoomExponent = 1.5f;
    public static volatile float mapTriggerDeadZone = 0.05f;

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
            lastModified = modified;
            load();
        } catch (IOException | RuntimeException e) {
            Log.error("can't read settings", e);
        }
    }

    private static void load() throws IOException {
        Properties p = new Properties();
        try (Reader r = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            p.load(r);
        }
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
        triggersDebugLog = bool(p, "triggers.debugLog", false);
        mapPanSpeed = num(p, "map.panSpeed", 1.0f, 0.01f, 20f);
        mapPanExponent = num(p, "map.panExponent", 2.0f, 0.1f, 5f);
        mapDpadDeflection = num(p, "map.dpadDeflection", 0.5f, 0.01f, 1f);
        mapZoomSpeed = num(p, "map.zoomSpeed", 3.0f, 0.01f, 20f);
        mapZoomExponent = num(p, "map.zoomExponent", 1.5f, 0.1f, 5f);
        mapTriggerDeadZone = num(p, "map.triggerDeadZone", 0.05f, 0f, 0.5f);
        raw = p;
        version++;
        Log.info("settings loaded: scaleToSpeedClamp=" + scaleToSpeedClamp
                + " exponent=" + lowSpeedExponent + ".." + highSpeedExponent
                + " @" + highSpeedKmh + "km/h turnRate=" + turnRate + ".." + highSpeedTurnRate
                + " returnRate=" + returnRate + " debugLog=" + debugLog
                + " recenter=" + recenter + " zone=" + recenterZone
                + " still=" + recenterStillRange + "/" + recenterStillMs + "ms rate=" + recenterRate
                + " noiseDeadZone=" + noiseDeadZone
                + " release=" + releaseFrom + "/" + releaseMaxMs + "ms settle=" + releaseSettleMs
                + "ms disarm=" + disarmDistance
                + " triggers.debugLog=" + triggersDebugLog
                + " map: pan=" + mapPanSpeed + "^" + mapPanExponent + " dpad=" + mapDpadDeflection
                + " zoom=" + mapZoomSpeed + "^" + mapZoomExponent + " triggerDeadZone=" + mapTriggerDeadZone);
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
