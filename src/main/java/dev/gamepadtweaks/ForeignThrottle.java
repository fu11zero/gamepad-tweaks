package dev.gamepadtweaks;

import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;

// Tsuki's AnalogThrottle (Workshop 3808553730, dev.tsuki.analogthrottle) patches the same
// CarController methods as Throttle: both would scale the engine force (twice), both set the
// gas / reverse flags, and its RPM changes inside CarController.update would become "vanilla"
// RPM for Throttle (shifts, force). While it is active our analog pedals step aside, everything
// else in GamepadTweaks stays. "Active" = its ATBridge.enabled: its own option is on and it
// supports this game build (0.1.3 supports only 42.21 and switches itself off elsewhere).
public final class ForeignThrottle {
    private static final String BRIDGE = "dev.tsuki.analogthrottle.ATBridge";

    private static volatile boolean looked;
    private static volatile Field enabled;
    private static volatile boolean lastActive;

    private ForeignThrottle() {}

    /** True while Tsuki's AnalogThrottle drives the pedals. */
    public static boolean active() {
        if (!looked) {
            lookUp();
        }
        Field f = enabled;
        boolean active;
        try {
            active = f != null && f.getBoolean(null);
        } catch (IllegalAccessException | RuntimeException e) {
            active = false;
        }
        if (active != lastActive) {
            lastActive = active;
            Log.info(active
                    ? "Tsuki's AnalogThrottle is active: GamepadTweaks analog gas and brake are off"
                    : "Tsuki's AnalogThrottle is not active: GamepadTweaks analog gas and brake follow throttle.analog");
        }
        return active;
    }

    // ZB loads every Java mod at startup, before the first car is driven; its classes may sit in
    // another class loader, so look among all loaded classes if ours can't see it.
    private static synchronized void lookUp() {
        if (looked) {
            return;
        }
        looked = true;
        Class<?> bridge = null;
        try {
            bridge = Class.forName(BRIDGE, false, ForeignThrottle.class.getClassLoader());
        } catch (ClassNotFoundException | LinkageError e) {
            Instrumentation inst = instrumentation();
            if (inst != null) {
                for (Class<?> c : inst.getAllLoadedClasses()) {
                    if (BRIDGE.equals(c.getName())) {
                        bridge = c;
                        break;
                    }
                }
            }
        }
        if (bridge == null) {
            return;
        }
        try {
            Field f = bridge.getDeclaredField("enabled");
            f.setAccessible(true);
            enabled = f;
            Log.info("found Tsuki's AnalogThrottle (" + bridge.getClassLoader() + ")");
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.error("Tsuki's AnalogThrottle found, but not its ATBridge.enabled", e);
        }
    }

    private static Instrumentation instrumentation() {
        try {
            Field f = Class.forName("me.zed_0xff.zombie_buddy.Loader").getDeclaredField("g_instrumentation");
            f.setAccessible(true);
            return (Instrumentation) f.get(null);
        } catch (ReflectiveOperationException | RuntimeException e) {
            return null;
        }
    }
}
