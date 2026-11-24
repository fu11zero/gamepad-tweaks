package dev.gamepadtweaks;

import java.util.Arrays;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.CharacterJoypadButtonBinding;

/** The resolved digital input for each native action, independently for each player. */
public final class NativeBindingInput {
    private static final int CONTROLLERS = 16;
    private static final CharacterJoypadButtonBinding[] ACTIONS = CharacterJoypadButtonBinding.values();
    private static final byte[][] inputs = new byte[CONTROLLERS][];

    private NativeBindingInput() {}

    @LuaMethod(name = "GamepadTweaks_publishNativeBindings", global = true)
    public static void publish(double controller, String states) {
        int id = (int) controller;
        if (id < 0 || id >= inputs.length) {
            return;
        }
        if (states == null || states.isEmpty()) {
            inputs[id] = null;
            return;
        }
        byte[] next = new byte[ACTIONS.length];
        Arrays.fill(next, (byte) -1);
        for (String entry : states.split(",")) {
            int equals = entry.indexOf('=');
            if (equals <= 0 || equals + 2 != entry.length()) {
                continue;
            }
            CharacterJoypadButtonBinding action = CharacterJoypadButtonBinding.fromString(entry.substring(0, equals));
            if (action != null) {
                next[action.ordinal()] = (byte) (entry.charAt(equals + 1) == '1' ? 1 : 0);
            }
        }
        inputs[id] = next;
    }

    public static boolean isDown(CharacterJoypadButtonBinding action, int id, boolean vanilla) {
        byte[] controller = id >= 0 && id < inputs.length ? inputs[id] : null;
        if (controller == null || controller[action.ordinal()] < 0) {
            return vanilla;
        }
        return controller[action.ordinal()] == 1;
    }
}
