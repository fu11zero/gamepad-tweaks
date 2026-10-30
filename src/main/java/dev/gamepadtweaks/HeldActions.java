package dev.gamepadtweaks;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.characters.CharacterInputMode;
import zombie.characters.CharacterJoypadButtonBinding;
import zombie.characters.IsoPlayer;
import zombie.characters.component.CharacterInputComponent;
import zombie.core.physics.CarController;

// Game actions that last while held: sprint, floor attack (stomp), vehicle brake, the
// Java half of Interact (doors, windows: IsoPlayer.updateUseKey acts on press + release),
// aim (as the keyboard Aim key: aim and precision aim), attack, melee (shove), run, camera
// pan while aiming (CameraPan), voice push-to-talk.
//
// The game has no call for these: each frame it asks whether the action is held
// (CharacterInputComponent.isSprintButtonDown / isManualFloorAtkButtonDown /
// isInteractButtonDownInternal, isAimKeyDownInternal, isPrecisionAimKeyDownInternal,
// isAttackButtonDown, isMeleeButtonDownInternal, isRunButtonDown, the brake in
// CarController.updateControls, GameKeyboard.isKeyDown(ENABLE_VOICE_TRANSMIT) in VoiceManager)
// and acts on it, with its own rules (toggle-to-sprint, sprint
// allowed, ...). The mod's actions (Steam Input, VanillaActions.lua) set the held state per
// controller and these queries also return true for it. No button is involved, so nothing
// else on any button fires.
//
// The vehicle brake on a gamepad is hardcoded to B in vanilla (updateControls: brake =
// JoypadManager.isBPressed), past the Brakes binding of Options -> Controller; here it is
// the Brakes binding (B by default, so nothing changes), or the held action.
public final class HeldActions {
    public static final int SPRINT = 0;
    public static final int FLOOR_ATTACK = 1;
    public static final int BRAKE = 2;
    public static final int INTERACT = 3;
    public static final int AIM = 4;
    public static final int ATTACK = 5;
    public static final int MELEE = 6;
    public static final int RUN = 7;
    public static final int PAN = 8;
    public static final int VOICE = 9;
    private static final String[] NAMES = {
        "sprint", "floorAttack", "brake", "interact", "aim", "attack", "melee", "run", "panCamera", "voice",
    };
    private static final int MAX_CONTROLLERS = 16;

    // [controller id][action]
    private static final boolean[][] held = new boolean[MAX_CONTROLLERS][NAMES.length];

    private HeldActions() {}

    /** Holds (down=true) or releases the action for controller id (JoypadState.controllers index). */
    @LuaMethod(name = "GamepadTweaks_setActionHeld", global = true)
    public static boolean set(double controllerId, String action, boolean down) {
        int id = (int) controllerId;
        if (id < 0 || id >= MAX_CONTROLLERS) {
            return false;
        }
        for (int i = 0; i < NAMES.length; i++) {
            if (NAMES[i].equals(action)) {
                held[id][i] = down;
                return true;
            }
        }
        return false;
    }

    private static boolean isHeld(int id, int action) {
        return id >= 0 && id < MAX_CONTROLLERS && held[id][action];
    }

    /** The action held for the character's controller, while the character takes gamepad input. */
    public static boolean characterHeld(CharacterInputComponent input, int action) {
        return input.getInputMode() == CharacterInputMode.GAMEPAD && input.isJoypadButtonsActive()
                && isHeld(input.getJoypadBind(), action);
    }

    /** The action held for the player's controller, while the player takes gamepad input. */
    public static boolean playerHeld(IsoPlayer player, int action) {
        return player != null && player.getInputMode() == CharacterInputMode.GAMEPAD
                && isHeld(player.getJoypadBind(), action);
    }

    /** The action held on any controller (the voice transmit key is one for the whole client). */
    public static boolean anyHeld(int action) {
        for (boolean[] c : held) {
            if (c[action]) {
                return true;
            }
        }
        return false;
    }

    /** After CarController.updateControls (gamepad driver): brake = Brakes binding or the held action. */
    public static void brake(CarController car, int joypad) {
        if (joypad == -1) {
            return;
        }
        CarController.ClientControls controls = car.clientControls;
        long forced = controls.forceBrake == 0L ? -1L : System.currentTimeMillis() - controls.forceBrake;
        if (forced > 0L && forced < 1000L) {
            return; // vanilla's forced brake (updateControls) stays
        }
        controls.brake = CharacterJoypadButtonBinding.Brakes.isDown(joypad) || isHeld(joypad, BRAKE);
    }
}
