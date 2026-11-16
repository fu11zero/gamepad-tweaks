package dev.gamepadtweaks;

import org.joml.Vector3f;
import zombie.SandboxOptions;
import zombie.characters.IsoPlayer;
import zombie.config.BooleanConfigOption;
import zombie.core.physics.CarController;
import zombie.input.JoypadManager;
import zombie.vehicles.BaseVehicle;

// Easy driving: the left stick points where to go on the screen, its deflection is the gas.
//
// Vanilla steers with the stick X relative to the car (left / right of the driver), so a car
// heading south (down the screen) steers mirrored, and reversing needs LT plus a mirrored
// wheel: hard for a novice in splitscreen. Here, per splitscreen player (easyDriving.player<n>):
//   - the stick direction becomes a world direction the way walking does it
//     (IsoPlayer.updateMovementFromInput: world = (y + x, y - x));
//   - the angle between it and the car's heading (BaseVehicle.getForwardVector: physics x, z =
//     world x, y) turns the wheel: full lock at FULL_LOCK, times the vanilla clamp for the speed
//     (VehicleScript.getSteeringClamp), as Steering.shape does for the stick;
//   - the deflection is the gas pedal, less when the target is off to the side (MIN_PUSH at 90
//     degrees and more), so the car slows down for a sharp turn instead of sliding into it;
//   - a target behind the car (past REVERSE_ANGLE) switches to reverse: the deflection goes on
//     the brake pedal (vanilla: brakes, then reverses at the stop) and the wheel points the rear
//     at the target (mirrored); back to forward under FORWARD_ANGLE (hysteresis, no flapping);
//   - while the car still rolls the other way, the wheel stays straight (braking in a line).
// The pedals go through the regular gas and brake as stick pedals (AnalogInput.pedals, Throttle:
// throttle.stickCurve), so the analog gas and the triggers still work; the brake hold (throttle.brakeHold) is off for this driver.
// A released stick: no gas, wheel back to center (the mod's wheel rate).
//
// Servers can forbid it: sandbox option GamepadTweaks.EasyDriving (media/sandbox-options.txt),
// sent to the clients with the other sandbox options. A client-side check: a modified client
// can bypass it, as any client mod.
public final class EasyDriving {
    private static final int MAX_CONTROLLERS = 16;
    private static final String SANDBOX_OPTION = "GamepadTweaks.EasyDriving";
    private static final double FULL_LOCK = Math.toRadians(40);
    private static final double REVERSE_ANGLE = Math.toRadians(120);
    private static final double FORWARD_ANGLE = Math.toRadians(70);
    private static final float MIN_PUSH = 0.35f;
    private static final float ROLLING_KMH = 3.0f;

    private static final boolean[] active = new boolean[MAX_CONTROLLERS];
    private static final boolean[] reverse = new boolean[MAX_CONTROLLERS];
    private static final float[] gas = new float[MAX_CONTROLLERS];
    private static final float[] brake = new float[MAX_CONTROLLERS];
    private static final float[] steering = new float[MAX_CONTROLLERS];
    private static final Vector3f forward = new Vector3f();
    private static long lastLog;

    private EasyDriving() {}

    /** The server (sandbox) allows it; true without the option (not loaded yet, old save). */
    public static boolean allowed() {
        SandboxOptions.SandboxOption option = SandboxOptions.instance.getOptionByName(SANDBOX_OPTION);
        return !(option instanceof BooleanConfigOption b) || b.getValue();
    }

    /** After CarController.updateControls, before the pedals: true if this driver drives the easy way. */
    public static boolean update(CarController car, int joypad) {
        if (joypad < 0 || joypad >= MAX_CONTROLLERS) {
            return false;
        }
        active[joypad] = false;
        gas[joypad] = 0;
        brake[joypad] = 0;
        steering[joypad] = 0;
        BaseVehicle vehicle = car.vehicleObject;
        if (!(vehicle.getDriver() instanceof IsoPlayer player) || !Settings.easyDriving(player.getPlayerNum())
                || !allowed()) {
            reverse[joypad] = false;
            return false;
        }
        JoypadManager.Joypad pad = JoypadManager.instance.getFromControllerID(joypad);
        if (pad == null) {
            return false;
        }
        active[joypad] = true;
        // the game's radial stick dead zone, rescaled (as the map)
        float sx = pad.getMovementAxisXRaw();
        float sy = pad.getMovementAxisYRaw();
        float push = (float) Math.min(1.0, Math.hypot(sx, sy));
        if (push <= 0) {
            return true;
        }
        float tx = sy + sx;
        float ty = sy - sx;
        vehicle.getForwardVector(forward);
        float fx = forward.x;
        float fy = forward.z;
        // > 0: the target is clockwise on the screen, to the driver's right (steering +1 = right)
        double angle = Math.atan2(fx * ty - fy * tx, fx * tx + fy * ty);
        double off = Math.abs(angle);
        if (reverse[joypad] ? off < FORWARD_ANGLE : off > REVERSE_ANGLE) {
            reverse[joypad] = !reverse[joypad];
        }
        float speed = vehicle.getCurrentSpeedKmHour(); // < 0 rolling back
        float clamp = vehicle.getScript() == null ? 1.0f : vehicle.getScript().getSteeringClamp(Math.abs(speed));
        if (reverse[joypad]) {
            double rear = angle > 0 ? angle - Math.PI : angle + Math.PI; // from the rear to the target
            brake[joypad] = pedal(push, rear);
            // reversing, the wheel to the left turns the rear to the right (clockwise)
            steering[joypad] = speed > ROLLING_KMH ? 0 : -lock(rear) * clamp;
        } else {
            gas[joypad] = pedal(push, angle);
            steering[joypad] = speed < -ROLLING_KMH ? 0 : lock(angle) * clamp;
        }
        if (Settings.debugLog) {
            long now = System.currentTimeMillis();
            if (now - lastLog >= 1000) {
                lastLog = now;
                Log.info(String.format("easy driving: stick=%.2f,%.2f angle=%.0f %s speed=%.1f gas=%.2f brake=%.2f steering=%.3f",
                        sx, sy, Math.toDegrees(angle), reverse[joypad] ? "reverse" : "forward", speed,
                        gas[joypad], brake[joypad], steering[joypad]));
            }
        }
        return true;
    }

    private static float pedal(float push, double angle) {
        return push * (MIN_PUSH + (1 - MIN_PUSH) * (float) Math.max(0, Math.cos(angle)));
    }

    private static float lock(double angle) {
        return (float) Math.max(-1, Math.min(1, angle / FULL_LOCK));
    }

    public static boolean active(int joypad) {
        return joypad >= 0 && joypad < MAX_CONTROLLERS && active[joypad];
    }

    public static float steering(int joypad) {
        return active(joypad) ? steering[joypad] : 0;
    }

    /** Adds the easy gas and brake to the stick pedals (AnalogInput.pedals: out[2], out[3]). */
    public static void pedals(int joypad, float[] out) {
        if (active(joypad)) {
            out[2] = Math.max(out[2], gas[joypad]);
            out[3] = Math.max(out[3], brake[joypad]);
        }
    }
}
