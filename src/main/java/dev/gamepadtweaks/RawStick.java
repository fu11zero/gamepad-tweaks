package dev.gamepadtweaks;

import java.lang.reflect.Field;

import org.lwjglx.input.Controller;
import zombie.GameWindow;
import zombie.input.JoypadManager;

// Reads stick axes straight from the controller, bypassing the game's
// dead zone and diagonal "squaring" (JoypadManager.Joypad.getMovementAxisX).
// Axis indices live in package-private fields of Joypad, hence reflection.
public final class RawStick {
    private static final Field MOVEMENT_AXIS_X = field("movementAxisX");
    private static final Field MOVEMENT_AXIS_X_FLIPPED = field("movementAxisXFlipped");

    private RawStick() {}

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
     * Raw movement stick X in [-1, 1] for the given controller id,
     * or {@code fallback} if it can't be read.
     */
    public static float movementX(int controllerId, float fallback) {
        if (MOVEMENT_AXIS_X == null || MOVEMENT_AXIS_X_FLIPPED == null) {
            return fallback;
        }
        JoypadManager.Joypad joypad = JoypadManager.instance.getFromControllerID(controllerId);
        Controller controller = GameWindow.GameInput.getController(controllerId);
        if (joypad == null || controller == null || controller.gamepadState == null || !controller.gamepadState.polled) {
            return fallback;
        }
        try {
            int axis = MOVEMENT_AXIS_X.getInt(joypad);
            if (axis < 0 || axis >= controller.getAxisCount()) {
                return fallback;
            }
            float value = controller.getAxisValue(axis);
            if (MOVEMENT_AXIS_X_FLIPPED.getBoolean(joypad)) {
                value = -value;
            }
            return Math.max(-1.0f, Math.min(1.0f, value));
        } catch (IllegalAccessException e) {
            return fallback;
        }
    }
}
