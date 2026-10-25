package dev.gamepadtweaks;

import java.io.IOException;
import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

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

            # --- Triggers ---------------------------------------------------------
            # The game's dead zone is not applied to the triggers (they rest at zero
            # and need none). Log every change of the raw trigger value (what the
            # controller driver reports, before any game code), to find jumps.
            triggers.debugLog=false
            """;

    public static volatile boolean scaleToSpeedClamp = true;
    public static volatile float lowSpeedExponent = 1.0f;
    public static volatile float highSpeedExponent = 2.0f;
    public static volatile float highSpeedKmh = 80f;
    public static volatile float turnRate = 0.05f;
    public static volatile float highSpeedTurnRate = 0.03f;
    public static volatile float returnRate = 0.06f;
    public static volatile boolean debugLog = false;
    public static volatile boolean triggersDebugLog = false;

    private static Path path;
    private static long lastCheck;
    private static long lastModified = Long.MIN_VALUE;

    private Settings() {}

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
        triggersDebugLog = bool(p, "triggers.debugLog", false);
        Log.info("settings loaded: scaleToSpeedClamp=" + scaleToSpeedClamp
                + " exponent=" + lowSpeedExponent + ".." + highSpeedExponent
                + " @" + highSpeedKmh + "km/h turnRate=" + turnRate + ".." + highSpeedTurnRate
                + " returnRate=" + returnRate + " debugLog=" + debugLog
                + " triggers.debugLog=" + triggersDebugLog);
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
