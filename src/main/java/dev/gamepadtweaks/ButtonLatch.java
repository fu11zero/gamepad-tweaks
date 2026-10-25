package dev.gamepadtweaks;

import zombie.input.JoypadButton;

// Keeps a button press that belonged to the UI away from the character.
//
// While a UI element has joypad focus, the Lua side (JoyPadSetup.lua updateJoypadFocus)
// turns the character's buttons off every frame: setPlayerButtonsActive(player, false).
// The UI reacts on press, e.g. B closes a menu, the focus goes away and in the same
// frame the buttons are turned back on, with B still held. The character then sees
// a fresh B press, and its release within 400 ms counts as a "click"
// (TimedInputHandler), so closing a menu also toggles crouch, cancels the action, etc.
//
// Here: buttons held at the moment the character's buttons get turned on don't count
// for the character until they are released.
public final class ButtonLatch {
    private static final JoypadButton[] BUTTONS = JoypadButton.values();
    private static final int MAX_JOYPADS = 16;

    // [joypadBind][button]
    private static final boolean[][] latched = new boolean[MAX_JOYPADS][BUTTONS.length];

    private ButtonLatch() {}

    /** CharacterInputComponent.setJoypadButtonsActive, called every frame from Lua. */
    public static void onButtonsActive(int joypadBind, boolean wasActive, boolean active) {
        if (joypadBind < 0 || joypadBind >= MAX_JOYPADS) {
            return;
        }
        boolean[] held = latched[joypadBind];
        boolean turnedOn = active && !wasActive;
        for (int i = 0; i < BUTTONS.length; i++) {
            boolean down = BUTTONS[i].isDown(joypadBind);
            if (turnedOn && down) {
                held[i] = true;
            } else if (!down) {
                held[i] = false;
            }
        }
    }

    /** CharacterJoypadButtonBinding.JoypadButtonBinding.isDown: the value the character sees. */
    public static boolean isDown(JoypadButton button, int joypadBind, boolean down) {
        if (!down || button == null || joypadBind < 0 || joypadBind >= MAX_JOYPADS) {
            return down;
        }
        return !latched[joypadBind][button.ordinal()];
    }
}
