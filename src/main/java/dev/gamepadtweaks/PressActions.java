package dev.gamepadtweaks;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

import zombie.characters.CharacterInputMode;
import zombie.characters.TimedInputHandler;
import zombie.characters.component.CharacterInputComponent;
import zombie.core.Core;

// Gamepad actions on press instead of "click" (press + release within 400 ms,
// TimedInputHandler.isKeyClicked). A click reacts only on release and does nothing
// when the button is held longer (e.g. Steam Input long-press binds).
//
// - Crouch toggle: on press, unless the left stick radial menu is enabled (holding
//   the button opens it, so vanilla has to wait for the release to tell them apart).
// - Toggle-to-sprint: on press.
// - Enter/exit vehicle: vanilla does it twice, the A button prompt on press (Lua,
//   ISButtonPrompt.cmdEnterVehicle/cmdExitVehicle) and IsoPlayer.enterExitVehicle on
//   a click of Interact, for whatever vehicle is near, even when A did something
//   else. For the gamepad only the prompt is left.
//
// Toggle-to-run on the gamepad is a stick gesture (full deflection and back), not a
// button, so it stays a click. Each change can be turned off (actions.* settings).
public final class PressActions {
    private static final Field TOGGLE_CROUCH = field("toggleCrouch");
    private static final Field TOGGLE_SPRINT = field("toggleSprint");
    private static final Method SHOULD_ALLOW_FORCE_RUN_OR_SPRINT = method("shouldAllowForceRunOrSprint");

    private PressActions() {}

    private static Field field(String name) {
        try {
            Field f = CharacterInputComponent.class.getDeclaredField(name);
            f.setAccessible(true);
            return f;
        } catch (ReflectiveOperationException e) {
            Log.error("CharacterInputComponent." + name + " not found", e);
            return null;
        }
    }

    private static Method method(String name) {
        try {
            Method m = CharacterInputComponent.class.getDeclaredMethod(name);
            m.setAccessible(true);
            return m;
        } catch (ReflectiveOperationException e) {
            Log.error("CharacterInputComponent." + name + "() not found", e);
            return null;
        }
    }

    private static TimedInputHandler handler(Field f, CharacterInputComponent input) {
        try {
            return f == null ? null : (TimedInputHandler) f.get(input);
        } catch (IllegalAccessException e) {
            return null;
        }
    }

    private static boolean gamepad(CharacterInputComponent input) {
        return input.getInputMode() == CharacterInputMode.GAMEPAD;
    }

    /** CharacterInputComponent.isCrouchButtonPressed. */
    public static boolean crouchPressed(CharacterInputComponent input, boolean vanilla) {
        if (!Settings.crouchOnPress || !gamepad(input)
                || Core.getInstance().getOptionEnableLeftJoystickRadialMenu()) {
            return vanilla;
        }
        TimedInputHandler crouch = handler(TOGGLE_CROUCH, input);
        if (crouch == null) {
            return vanilla;
        }
        return input.isJoypadButtonsActive() && crouch.isKeyPressed();
    }

    /** After CharacterInputComponent.updateToggleToSprint: move its toggle from click to press. */
    public static void afterToggleToSprint(CharacterInputComponent input) {
        if (!Settings.sprintOnPress || !gamepad(input) || SHOULD_ALLOW_FORCE_RUN_OR_SPRINT == null) {
            return;
        }
        TimedInputHandler sprint = handler(TOGGLE_SPRINT, input);
        if (sprint == null || sprint.isMuted()) {
            return;
        }
        try {
            if (!(Boolean) SHOULD_ALLOW_FORCE_RUN_OR_SPRINT.invoke(input)) {
                return;
            }
        } catch (ReflectiveOperationException e) {
            return;
        }
        if (sprint.isKeyClicked()) {
            input.toggleForceSprint(); // undo vanilla's toggle on release
        }
        if (sprint.isKeyPressed()) {
            input.toggleForceSprint();
        }
    }

    /** CharacterInputComponent.isInteractButtonClicked. */
    public static boolean interactClicked(CharacterInputComponent input, boolean vanilla) {
        return vanilla && (!Settings.vehicleOnlyByPrompt || !gamepad(input));
    }
}
