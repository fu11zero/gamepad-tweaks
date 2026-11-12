package dev.gamepadtweaks;

import java.lang.reflect.Field;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import zombie.core.physics.CarController;
import zombie.input.JoypadManager;
import zombie.network.GameServer;
import zombie.scripting.objects.VehicleScript;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.TransmissionNumber;
import zombie.vehicles.VehicleEngineRPM;

// Analog gas and brake pedals on the triggers.
//
// Vanilla (CarController.updateControls) turns the triggers into on/off pedals: gas at
// RT > 0.7, reverse / brake at LT > 0.7. control_ForwardNew / control_Reverse then push with
// the full engine force and control_Braking brakes with the full vehicle braking force.
//
// Scaling the engine force by the pedal alone only scales the acceleration: the game has
// almost no resistance (control_ForwardNew takes off speed/200, cuts the force past the max
// speed), so any force, however small, still takes the car to its top speed. A real car on a
// light pedal settles at a speed where the push equals air and rolling drag. Here:
//   r = (speed / maxSpeed) ^ dragExponent   resistance at this speed, share of full power
//   f = (p - r) / (1 - r)                    share of the vanilla engine force
// Standing still f = p; as the car speeds up the push fades out and is gone at
// maxSpeed * p ^ (1 / dragExponent): every pedal position has its own cruising speed. Full
// pedal (f = 1) is vanilla. Below that speed's pedal (p < r) the engine brakes, up to the
// vanilla force of a released pedal (control_NoControl: 10), so easing off slows the car
// down to the new pedal's speed without a jolt. The vanilla multipliers (traits, towing,
// offroad, the MP speed limit) stay on top.
//
// A pedal against the motion (LT going forward, RT rolling back) brakes between that engine
// braking and the vehicle braking force. The B brake (handbrake, x13) stays vanilla.
//
// Engine RPM: the engine speed is its own number in vanilla, not tied to the wheels.
// control_ForwardNew raises it at a fixed rate towards the gearChange RPM of the gear for the
// speed, on any pedal, and shifts up once both the RPM and the speed reach the gear's top
// (gear = speed / (maxSpeed / gearRatioCount)); after a shift it drops to the new gear's
// afterGearChange. There is no downshift in gear: a released pedal or the brake
// (control_NoControl / control_Braking) put the gearbox in N and let the RPM fall to idle, the
// next press picks the gear for the speed. So on a light pedal the engine revs while the car
// crawls. The engine force (x (0.3 + rpm / 30000)), the shifts and the released-pedal braking
// (15 above 1000 RPM, else 10) depend on that number, the tachometer and the sound show it.
//
// Here vanilla keeps its own number and does everything with it: CarController.update runs with
// the vanilla RPM (put back on entry), and only after it the engine shows an RPM from the speed
// (kept until the next update: tachometer, sound, the RPM sent to other players). In a forward
// gear: across the gear's band, from its start (idle in 1st, afterGearChange) to gearChange at
// the gear's top speed; below the band (vanilla stays in a high gear while the car slows on a
// partly released pedal) and past it in proportion to the speed, not below idle; never above
// vanilla's (on a full pedal vanilla's lags behind the speed: it shifts only once its own RPM
// reaches gearChange, a quick start outruns it and then it skips gears, 1 -> 3; that is shown
// as without the mod). In N the shown RPM falls by vanilla's
// steps from where it was (vanilla's is usually higher), to vanilla's or idle. R, engine off:
// the vanilla RPM.
// If something outside the update changed the RPM (engine stalled, started), that is vanilla's.
//
// Brake hold (throttle.brakeHold, also with the vanilla on/off pedals): vanilla turns a pedal
// against the motion into a brake while the car moves (updateControls -> update: LT with the
// velocity along the car's forward > 0 is isBreak) and into the opposite gear the moment it
// stops, so a brake held a moment too long backs the car up (with the reverse beeper). Here the
// LT that started braking going forward (above HOLD_SPEED) keeps braking: near a stop it becomes
// the brake (clientControls.brake, as B) and holds the car until LT is released; pressed again it
// reverses. Only LT: after backing up the next move is almost always forward, so RT while rolling
// back still brakes and then drives forward, as vanilla. Experimental, off by default.
//
// Tsuki's AnalogThrottle patches the same methods: while it is active (ForeignThrottle) the
// analog pedals here are off.
//
// Sound: the "VehicleLoad" parameter is on/off (isGasPedalPressed); it gets the smoothed share
// of the engine force instead.
public final class Throttle {
    private static final float RELEASED_PEDAL_BRAKE = 10.0f; // control_NoControl
    private static final long STALE_MS = 500;
    private static final float MAX_SHOWN_RPM = 7000.0f; // ParameterVehicleRPM clamps to it
    private static final float HOLD_SPEED = 1.0f; // km/h: a pedal pressed slower than this drives the other way at once

    public static final class State {
        volatile float gas;      // shaped RT, 0..1
        volatile float brake;    // shaped LT, 0..1
        volatile float force;    // share of the engine force (kept between frames: the sound may read it any time)
        volatile float load;     // smoothed force, for the sound
        volatile long updated;
        volatile float soundLoad = Float.NaN; // last value given to the sound, for the log
        long lastSmooth;
        long lastLog;
        double vanillaRpm = Double.NaN; // vanilla's own RPM between updates
        double shownRpm = Double.NaN;   // what the engine shows between updates
    }

    private static final Map<BaseVehicle, State> states = new ConcurrentHashMap<>();
    // Brake hold: vehicles whose LT braked forward motion and is still pressed.
    private static final Map<BaseVehicle, Boolean> holds = new ConcurrentHashMap<>();
    private static final Map<Class<?>, Field> vehicleFields = new ConcurrentHashMap<>();

    private Throttle() {}

    /** After CarController.updateControls: analog pedals for a gamepad driver. */
    public static void controls(CarController car, int joypad) {
        BaseVehicle vehicle = car.vehicleObject;
        if (joypad == -1) {
            states.remove(vehicle);
            holds.remove(vehicle);
            return;
        }
        if (analog()) {
            pedals(car, joypad);
        } else {
            states.remove(vehicle);
        }
        hold(car);
    }

    private static boolean analog() {
        return Settings.throttleAnalog && !ForeignThrottle.active();
    }

    private static void pedals(CarController car, int joypad) {
        BaseVehicle vehicle = car.vehicleObject;
        State s = states.computeIfAbsent(vehicle, v -> new State());
        float rt = travel(JoypadManager.instance.getRTValue(joypad));
        float lt = travel(JoypadManager.instance.getLTValue(joypad));
        s.gas = shape(rt, Settings.throttleCurve);
        s.brake = shape(lt, Settings.throttleBrakeCurve);
        s.updated = System.currentTimeMillis();
        CarController.ClientControls controls = car.clientControls;
        controls.forward = s.gas > 0.0f;
        controls.backward = s.brake > 0.0f;
        prune(s.updated);
    }

    /** Brake hold: LT that braked the car going forward holds it at the stop until released. */
    private static void hold(CarController car) {
        BaseVehicle vehicle = car.vehicleObject;
        CarController.ClientControls controls = car.clientControls;
        if (!Settings.throttleBrakeHold || !controls.backward) {
            holds.remove(vehicle); // LT released: the next press may reverse
            return;
        }
        if (controls.forward) {
            return; // both pedals: vanilla brakes; the hold stays for LT if it is left pressed
        }
        float speed = vehicle.getCurrentSpeedKmHour(); // < 0 rolling back
        if (holds.get(vehicle) == null) {
            if (speed <= HOLD_SPEED) {
                return; // pressed at a stop or rolling back: reverse, as vanilla
            }
            holds.put(vehicle, Boolean.TRUE);
        }
        if (speed > HOLD_SPEED) {
            return; // still moving: vanilla brakes with LT (analog in braking())
        }
        controls.backward = false;
        controls.brake = true;
    }

    /** After control_ForwardNew. */
    public static void forward(CarController car, float speed) {
        State s = active(car);
        if (s == null) {
            return;
        }
        if (!car.clientControls.forward) {
            s.force = 1.0f; // the cruise control drives (no pedal): vanilla force
            return;
        }
        BaseVehicle vehicle = car.vehicleObject;
        if (vehicle.isRegulator() && speed < vehicle.getRegulatorSpeed()) {
            s.force = 1.0f; // under the cruise speed vanilla pushes with full force anyway
            log(car, s, speed, 0.0f);
            return;
        }
        push(car, s, s.gas, Math.max(speed, 0.0f) / vehicle.getMaxSpeed(), speed);
    }

    /** After control_Reverse; vanilla limits reverse at -speed * 1.5 > maxSpeedReverse. */
    public static void reverse(CarController car, float speed) {
        State s = active(car);
        if (s == null) {
            return;
        }
        if (!car.clientControls.backward) {
            return;
        }
        push(car, s, s.brake, reverseShare(car.vehicleObject, speed), speed);
    }

    /** After control_NoControl (pedals released): no load for the sound. */
    public static void coasting(CarController car) {
        State s = active(car);
        if (s != null) {
            s.force = 0.0f;
        }
    }

    /** After control_Braking: a pedal against the motion brakes as far as it is pressed. */
    public static void braking(CarController car) {
        State s = active(car);
        if (s == null) {
            return;
        }
        s.force = 0.0f;
        CarController.ClientControls controls = car.clientControls;
        BaseVehicle vehicle = car.vehicleObject;
        if (controls.brake || controls.forward == controls.backward
                || vehicle.isInvalidChunkAhead() || vehicle.isInvalidChunkBehind()) {
            return; // B, both pedals, unloaded chunk ahead: vanilla full brake
        }
        float pedal = controls.forward ? s.gas : s.brake;
        float full = car.brakingForce;
        float min = Math.min(full, RELEASED_PEDAL_BRAKE * Settings.throttleEngineBraking);
        car.brakingForce = min + (full - min) * pedal;
        log(car, s, car.speed, -1.0f);
    }

    private static void push(CarController car, State s, float pedal, float speedShare, float speed) {
        float r = (float) Math.pow(Math.min(speedShare, 1.0f), Settings.throttleDragExponent);
        float f;
        if (pedal >= 1.0f) {
            f = 1.0f;
        } else if (r >= 1.0f) {
            f = 0.0f;
        } else {
            f = Math.max(0.0f, (pedal - r) / (1.0f - r));
        }
        s.force = f;
        car.engineForce *= f;
        if (pedal < r && r > 0.0f) {
            float engineBrake = RELEASED_PEDAL_BRAKE * Settings.throttleEngineBraking * Math.min(1.0f, (r - pedal) / r);
            car.brakingForce = Math.max(car.brakingForce, engineBrake);
        }
        log(car, s, speed, r);
    }

    private static float reverseShare(BaseVehicle vehicle, float speed) {
        float max = vehicle.getScript().maxSpeedReverse;
        return max > 0.0f ? Math.max(-speed * 1.5f, 0.0f) / max : 1.0f;
    }

    /** Start of CarController.update: vanilla's own RPM back for its calculations. */
    public static void beginUpdate(CarController car) {
        State s = active(car);
        if (s == null || Double.isNaN(s.vanillaRpm)) {
            return;
        }
        BaseVehicle vehicle = car.vehicleObject;
        if (Math.abs(vehicle.getEngineSpeed() - s.shownRpm) < 0.5) {
            vehicle.setEngineSpeed(s.vanillaRpm);
        } // else changed outside the update (stalled, started): that is vanilla's now
    }

    /** End of CarController.update: keep vanilla's RPM, show the one from the speed. */
    public static void endUpdate(CarController car) {
        State s = active(car);
        if (s == null) {
            logVanilla(car);
            return;
        }
        BaseVehicle vehicle = car.vehicleObject;
        double vanilla = vehicle.getEngineSpeed();
        double shown = shownRpm(vehicle, car.speed, vanilla);
        if (Double.isNaN(shown)) {
            shown = neutralRpm(vehicle, s, vanilla);
        }
        s.vanillaRpm = vanilla;
        s.shownRpm = shown;
        vehicle.setEngineSpeed(shown);
    }

    /**
     * In N (pedal released, brake) vanilla lets its RPM fall from where it was, usually higher
     * than the shown one: the shown RPM falls by the same steps from its own value, down to the
     * vanilla RPM or idle.
     */
    private static double neutralRpm(BaseVehicle vehicle, State s, double vanilla) {
        if (Double.isNaN(s.shownRpm) || Double.isNaN(s.vanillaRpm)) {
            return vanilla;
        }
        double fallen = s.shownRpm + Math.min(vanilla - s.vanillaRpm, 0.0);
        double idle = vehicle.getScript() == null ? 0.0 : vehicle.getScript().getEngineIdleSpeed();
        return Math.min(vanilla, Math.max(fallen, Math.min(vanilla, idle)));
    }

    private static double shownRpm(BaseVehicle vehicle, float speed, double vanilla) {
        VehicleScript script = vehicle.getScript();
        VehicleEngineRPM engine = vehicle.getVehicleEngineRPM();
        TransmissionNumber transmission = vehicle.transmissionNumber;
        int gear = transmission == null ? 0 : transmission.getIndex();
        if (!vehicle.isEngineRunning() || script == null || engine == null || engine.rpmData == null
                || gear < 1 || gear > engine.rpmData.length || script.gearRatioCount < 1) {
            return gear == 0 && vehicle.isEngineRunning() ? Double.NaN : vanilla; // N: neutralRpm; R, engine off: vanilla
        }
        float idle = script.getEngineIdleSpeed();
        float perGear = vehicle.getMaxSpeed() / script.gearRatioCount;
        if (perGear <= 0.0f) {
            return vanilla;
        }
        float v = Math.max(speed, 0.0f);
        float low = perGear * (gear - 1);
        float high = perGear * gear;
        float start = gear == 1 ? idle : engine.rpmData[gear - 1].afterGearChange;
        float end = engine.rpmData[gear - 1].gearChange;
        float rpm;
        if (v < low) {
            rpm = start * v / low;
        } else if (v > high) {
            rpm = Math.min(end * v / high, MAX_SHOWN_RPM);
        } else {
            rpm = start + (end - start) * (v - low) / perGear;
        }
        // Never above vanilla's: on a light pedal vanilla revs ahead of the speed (that's what
        // the speed's RPM fixes); on a full one its RPM lags behind the speed, vanilla shifts
        // only once it reaches gearChange (a quick start outruns it and then skips gears, 1 -> 3)
        // and that lagging number is shown, as without the mod. Also after N: vanilla climbs back.
        return Math.min(Math.max(rpm, idle), vanilla);
    }

    /** ParameterVehicleLoad.calculateCurrentValue: 0/1 in vanilla. */
    public static float soundLoad(Object parameter, float vanilla) {
        State s = soundState(parameter);
        if (s == null) {
            return vanilla;
        }
        s.soundLoad = s.load;
        return s.load;
    }

    private static State soundState(Object parameter) {
        if (GameServer.server || !analog()) {
            return null;
        }
        Object vehicle = vehicleOf(parameter);
        if (!(vehicle instanceof BaseVehicle)) {
            return null;
        }
        State s = states.get(vehicle);
        long now = System.currentTimeMillis();
        if (s == null || now - s.updated > STALE_MS) {
            return null;
        }
        // the parameters are read once per sound update; smooth here, against frame time
        if (s.lastSmooth != 0L) {
            float dt = Math.min((now - s.lastSmooth) / 1000.0f, 0.25f);
            float k = Math.min(1.0f, dt * Settings.throttleSoundRate);
            s.load += (s.force - s.load) * k;
        } else {
            s.load = s.force;
        }
        s.lastSmooth = now;
        return s;
    }

    private static Object vehicleOf(Object parameter) {
        Field f = vehicleFields.computeIfAbsent(parameter.getClass(), c -> {
            try {
                Field field = c.getDeclaredField("vehicle");
                field.setAccessible(true);
                return field;
            } catch (ReflectiveOperationException | RuntimeException e) {
                Log.error(c.getName() + ".vehicle not found", e);
                return null;
            }
        });
        try {
            return f == null ? null : f.get(parameter);
        } catch (IllegalAccessException e) {
            return null;
        }
    }

    private static State active(CarController car) {
        if (GameServer.server || !analog()) {
            return null;
        }
        State s = states.get(car.vehicleObject);
        return s != null && System.currentTimeMillis() - s.updated <= STALE_MS ? s : null;
    }

    /** Trigger value (-1 released .. 1 pressed) to travel 0..1. */
    private static float travel(float value) {
        return Math.max(0.0f, Math.min(1.0f, (value + 1.0f) * 0.5f));
    }

    /** Travel past the dead zone, full at fullAt, then ^curve. */
    private static float shape(float travel, float curve) {
        float span = Settings.throttleFullAt - Settings.throttleDeadZone;
        if (span <= 0.0f) {
            return travel > Settings.throttleDeadZone ? 1.0f : 0.0f;
        }
        float t = (travel - Settings.throttleDeadZone) / span;
        if (t <= 0.0f) {
            return 0.0f;
        }
        return t >= 1.0f ? 1.0f : (float) Math.pow(t, curve);
    }

    private static void prune(long now) {
        if (states.size() > 4) {
            states.values().removeIf(s -> now - s.updated > STALE_MS);
        }
    }

    private static void log(CarController car, State s, float speed, float r) {
        if (!Settings.throttleDebugLog) {
            return;
        }
        long now = System.currentTimeMillis();
        if (now - s.lastLog < 1000) {
            return;
        }
        s.lastLog = now;
        Log.info(String.format("throttle: speed=%.1fkm/h max=%.0f gas=%.3f brake=%.3f r=%.3f force=%.3f load=%.3f"
                        + " soundLoad=%.3f engineForce=%.0f brakingForce=%.1f rpm=%.0f shown=%.0f gear=%s",
                speed, car.vehicleObject.getMaxSpeed(), s.gas, s.brake, r, s.force, s.load, s.soundLoad,
                car.engineForce, car.brakingForce, car.vehicleObject.getEngineSpeed(), s.shownRpm,
                car.vehicleObject.transmissionNumber));
    }

    private static long lastVanillaLog;

    // With the analog pedals off: the same line for a gamepad driver, to compare with vanilla.
    private static void logVanilla(CarController car) {
        if (!Settings.throttleDebugLog || GameServer.server || car.vehicleObject.getJoypad() == -1) {
            return;
        }
        long now = System.currentTimeMillis();
        if (now - lastVanillaLog < 1000) {
            return;
        }
        lastVanillaLog = now;
        Log.info(String.format("throttle (vanilla pedals): speed=%.1fkm/h forward=%b backward=%b brake=%b"
                        + " engineForce=%.0f brakingForce=%.1f rpm=%.0f gear=%s",
                car.speed, car.clientControls.forward, car.clientControls.backward, car.clientControls.brake,
                car.engineForce, car.brakingForce, car.vehicleObject.getEngineSpeed(),
                car.vehicleObject.transmissionNumber));
    }
}
