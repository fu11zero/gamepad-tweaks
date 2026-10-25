package dev.gamepadtweaks;

import zombie.GameTime;
import zombie.core.physics.CarController;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;

// Gamepad steering, two stages:
//
// shape(): stick -> desired wheel angle. Vanilla clamps the wheel angle at speed
// (VehicleScript.getSteeringClamp: 0.9 standing still, ~0.4 at max speed) but maps
// the stick 1:1, so at speed the outer stick travel does nothing and small
// deflections are too sharp. Here:
//   1. response curve whose exponent grows with speed (soft center at speed);
//   2. full stick = the clamp, so the whole stick travel is used at any speed.
//
// wheel(): desired angle -> actual wheel angle, called from CarController.update()
// (see SteeringHookTransformer). Vanilla moves the wheel exponentially towards the
// stick, 0.06 * (1 - speed/maxSpeed) of the remaining distance per frame (down to
// 0.006 at top speed, a ~3 s lag), and only snaps back quickly (0.04/frame) when
// the stick is inside the 0.1 dead zone. Without the dead zone a released stick
// never takes the fast path, so the car keeps turning. Here the wheel moves
// towards the target at a constant rate, faster when going back to center.
public final class Steering {
    private static long lastDebugLog;
    private static float lastRaw;
    private static float lastStick;
    private static int lastJoypad;

    // Wheel angle at the start of the current CarController.update() call.
    private static CarController updating;
    private static float angleBefore;

    private Steering() {}

    /** raw: stick X as read, for the debug log; stick: after StickCenter. */
    public static float shape(CarController car, float raw, float stick, int joypad) {
        Settings.refresh();
        lastRaw = raw;
        lastStick = stick;
        lastJoypad = joypad;
        if (stick == 0.0f) {
            return 0.0f;
        }
        BaseVehicle vehicle = car.vehicleObject;
        float speed = Math.abs(vehicle.getCurrentSpeedKmHour());

        float exponent = lerp(Settings.lowSpeedExponent, Settings.highSpeedExponent, speedFactor(speed));
        float out = Math.copySign((float) Math.pow(Math.abs(stick), exponent), stick);

        if (Settings.scaleToSpeedClamp && vehicle.getScript() != null) {
            out *= vehicle.getScript().getSteeringClamp(speed);
        }
        return out;
    }

    /** Called at the start of CarController.update(). */
    public static void beginUpdate(CarController car) {
        updating = car;
        angleBefore = car.getVehicleSteering();
    }

    /** Called in CarController.update() after vanilla moved the wheel; returns the angle to use. */
    public static float wheel(CarController car) {
        float vanilla = car.getVehicleSteering();
        if (GameServer.server || car != updating || car.vehicleObject.getJoypad() == -1) {
            return vanilla;
        }
        float speed = Math.abs(car.vehicleObject.getCurrentSpeedKmHour());
        float fpsMod = GameTime.getInstance().getMultiplier() / 0.8f;

        // vanilla convention: the wheel angle is the negated control value
        float target = -car.clientControls.steering;
        float current = angleBefore;
        float delta = target - current;
        boolean towardsCenter = current != 0.0f && Math.signum(delta) != Math.signum(current);
        float rate = towardsCenter
                ? Settings.returnRate
                : lerp(Settings.turnRate, Settings.highSpeedTurnRate, speedFactor(speed));
        float step = rate * fpsMod;
        float angle = Math.abs(delta) <= step ? target : current + Math.copySign(step, delta);

        if (Settings.debugLog) {
            long now = System.currentTimeMillis();
            if (now - lastDebugLog >= 1000) {
                lastDebugLog = now;
                Log.info(String.format("steering: speed=%.0fkm/h raw=%.4f center=%.4f stick=%.4f control=%.5f wheel=%.5f (vanilla %.5f)",
                        speed, lastRaw, StickCenter.center(lastJoypad), lastStick,
                        car.clientControls.steering, angle, vanilla));
            }
        }
        return angle;
    }

    private static float speedFactor(float speedKmh) {
        return Math.min(speedKmh / Settings.highSpeedKmh, 1.0f);
    }

    private static float lerp(float a, float b, float t) {
        return a + (b - a) * t;
    }
}
