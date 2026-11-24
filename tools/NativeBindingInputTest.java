import dev.gamepadtweaks.NativeBindingInput;

import zombie.characters.CharacterJoypadButtonBinding;
import zombie.characters.TimedInputHandler;

/** Exercises the native bridge with the engine's actual click handler. */
public class NativeBindingInputTest {
    private static final CharacterJoypadButtonBinding CROUCH = CharacterJoypadButtonBinding.Crouch;
    private static final CharacterJoypadButtonBinding ATTACK = CharacterJoypadButtonBinding.Attack;

    public static void main(String[] args) {
        var crouch = new TimedInputHandler(() -> NativeBindingInput.isDown(CROUCH, 0, false), null, null);
        NativeBindingInput.publish(0, "Crouch=1,Attack=0");
        crouch.updateState();
        check(crouch.isKeyPressed() && crouch.isKeyDown(), "press");
        check(!NativeBindingInput.isDown(ATTACK, 0, true), "suppress the original binding");
        check(NativeBindingInput.isDown(ATTACK, 1, true), "leave player two's input unchanged");
        check(!NativeBindingInput.isDown(CROUCH, 1, false), "keep player two's crouch up");

        NativeBindingInput.publish(0, "Crouch=0,Attack=1");
        crouch.updateState();
        check(crouch.isKeyReleased() && crouch.isKeyClicked(), "vanilla click after the synthetic press");
        check(NativeBindingInput.isDown(ATTACK, 0, false), "hold Attack");

        NativeBindingInput.publish(0, "");
        check(NativeBindingInput.isDown(CROUCH, 0, true), "fall back to the original binding");
        check(!NativeBindingInput.isDown(ATTACK, 0, false), "clear Attack");
        System.out.println("native binding bridge passed");
    }

    private static void check(boolean expected, String message) {
        if (!expected) {
            throw new AssertionError(message);
        }
    }
}
