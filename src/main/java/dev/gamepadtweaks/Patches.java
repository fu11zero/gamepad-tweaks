package dev.gamepadtweaks;

import me.zed_0xff.zombie_buddy.Patch;
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
