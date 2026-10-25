package dev.gamepadtweaks;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.physics.CarController;
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
}
