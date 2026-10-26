package dev.gamepadtweaks;

import java.lang.reflect.Field;

import org.lwjglx.input.Controller;
import zombie.GameWindow;
import zombie.input.JoypadManager;

// Trigger values without the game's dead zone.
//
// Vanilla JoypadManager.Joypad.getLTValue/getRTValue apply Controller.getDeadZone(axis),
// the same per-axis value the options "dead zone" buttons change for the sticks
// (default 0.2, i.e. the first 10% of the trigger travel is ignored). Triggers rest at
// -1 and need no dead zone; the controller's own hardware dead zone is enough.
// Here: the raw axis in [-1, 1], same convention as vanilla (-1 released, 1 fully pressed).
public final class Triggers {
    private static final Field TRIGGER_LEFT = field("triggerLeft");
    private static final Field TRIGGER_RIGHT = field("triggerRight");
    private static final Field TRIGGERS_FLIPPED = field("triggersFlipped");

    private static final float[] lastLogged = {Float.NaN, Float.NaN};

    private Triggers() {}

    private static Field field(String name) {
        try {
            Field f = JoypadManager.Joypad.class.getDeclaredField(name);
            f.setAccessible(true);
            return f;
        } catch (ReflectiveOperationException e) {
            Log.error("Joypad." + name + " not found", e);
            return null;
        }
    }

    /**
     * Raw trigger value, or {@code vanilla} if it can't be read (or the trigger is a button,
     * or triggers.noDeadZone is off).
     */
    public static float value(JoypadManager.Joypad joypad, boolean left, float vanilla) {
        Settings.refresh();
        if (!Settings.triggersNoDeadZone) {
            return vanilla;
        }
        Field triggerField = left ? TRIGGER_LEFT : TRIGGER_RIGHT;
        if (triggerField == null || TRIGGERS_FLIPPED == null) {
            return vanilla;
        }
        try {
            int id = joypad.getID();
            int axis = triggerField.getInt(joypad);
            // vanilla treats a missing axis as a button trigger (LB/RB): keep that
            if (axis < 0 || axis >= GameWindow.GameInput.getAxisCount(id)) {
                return vanilla;
            }
            Controller controller = GameWindow.GameInput.getController(id);
            if (controller == null) {
                return vanilla;
            }
            float raw = controller.getAxisValue(axis);
            float value = TRIGGERS_FLIPPED.getBoolean(joypad) ? -raw : raw;
            value = Math.max(-1.0f, Math.min(1.0f, value));
            if (Settings.triggersDebugLog) {
                debugLog(left, raw, value, vanilla);
            }
            return value;
        } catch (IllegalAccessException e) {
            return vanilla;
        }
    }

    /** Trigger dead zone shown on the options screen: none while the raw value is used. */
    public static float deadZone(float vanilla) {
        return Settings.triggersNoDeadZone ? 0.0f : vanilla;
    }

    // Every change of the raw axis, to see where a jump comes from:
    // raw is what GLFW reports, before any game code.
    private static void debugLog(boolean left, float raw, float value, float vanilla) {
        int i = left ? 0 : 1;
        if (raw == lastLogged[i]) {
            return;
        }
        lastLogged[i] = raw;
        Log.info(String.format("trigger %s: raw=%.4f (%.1f%%) value=%.4f vanilla=%.4f",
                left ? "LT" : "RT", raw, (raw + 1.0f) * 50.0f, value, vanilla));
    }
}
