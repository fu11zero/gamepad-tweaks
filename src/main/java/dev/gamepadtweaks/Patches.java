package dev.gamepadtweaks;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.CharacterJoypadButtonBinding;
import zombie.characters.component.CharacterInputComponent;
import zombie.core.physics.CarController;
import zombie.input.JoypadManager;
import zombie.network.GameServer;

public final class Patches {
    private Patches() {}

    // Vanilla: clientControls.steering = JoypadManager.getMovementAxisX(joypad),
    // which applies the stick dead zone and stretches diagonals up to x1.41.
    // Replace it with the raw stick X, shaped by speed (see Steering).
    @Patch(className = "zombie.core.physics.CarController", methodName = "updateControls")
    public static class SteeringInput {
        @Patch.OnExit
        public static void exit(@Patch.This CarController car) {
            if (GameServer.server) {
                return;
            }
            int joypad = car.vehicleObject.getJoypad();
            if (joypad == -1) {
                return;
            }
            float stick = RawStick.movementX(joypad, car.clientControls.steering);
            car.clientControls.steering = Steering.shape(car, stick);
        }
    }

    // Triggers without the game's dead zone (see Triggers). Also covers
    // isLTPressed/isRTPressed (value > 0.7), which call these.
    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getLTValue")
    public static class LeftTriggerValue {
        @Patch.OnExit
        public static void exit(@Patch.This JoypadManager.Joypad joypad,
                                @Patch.Return(readOnly = false) float value) {
            value = Triggers.value(joypad, true, value);
        }
    }

    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getRTValue")
    public static class RightTriggerValue {
        @Patch.OnExit
        public static void exit(@Patch.This JoypadManager.Joypad joypad,
                                @Patch.Return(readOnly = false) float value) {
            value = Triggers.value(joypad, false, value);
        }
    }

    // A press that closed a UI element must not reach the character (see ButtonLatch).
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "setJoypadButtonsActive")
    public static class ButtonsActive {
        @Patch.OnEnter
        public static void enter(@Patch.This CharacterInputComponent input, @Patch.Argument(0) boolean active) {
            ButtonLatch.onButtonsActive(input.getJoypadBind(), input.isJoypadButtonsActive(), active);
        }
    }

    @Patch(className = "zombie.characters.CharacterJoypadButtonBinding$JoypadButtonBinding", methodName = "isDown")
    public static class CharacterButtonDown {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterJoypadButtonBinding.JoypadButtonBinding binding,
                                @Patch.Argument(0) int joypadBind,
                                @Patch.Return(readOnly = false) boolean down) {
            down = ButtonLatch.isDown(binding.getButton(), joypadBind, down);
        }
    }

    // Gamepad actions on press instead of click (see PressActions).
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isCrouchButtonPressed")
    public static class CrouchOnPress {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean pressed) {
            pressed = PressActions.crouchPressed(input, pressed);
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "updateToggleToSprint")
    public static class SprintToggleOnPress {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input) {
            PressActions.afterToggleToSprint(input);
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isInteractButtonClicked")
    public static class NoVehicleClick {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean clicked) {
            clicked = PressActions.interactClicked(input, clicked);
        }
    }

    // The options screen draws the trigger dead zone from these; it no longer applies.
    // The dead zone buttons there still change it for the sticks.
    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getLTDeadZone")
    public static class LeftTriggerDeadZone {
        @Patch.OnExit
        public static void exit(@Patch.Return(readOnly = false) float value) {
            value = 0.0f;
        }
    }

    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getRTDeadZone")
    public static class RightTriggerDeadZone {
        @Patch.OnExit
        public static void exit(@Patch.Return(readOnly = false) float value) {
            value = 0.0f;
        }
    }
}
