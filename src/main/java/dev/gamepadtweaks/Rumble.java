package dev.gamepadtweaks;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import se.krka.kahlua.integration.annotations.LuaMethod;

// Controller vibration.
//
// Vanilla has no vibration at all: input goes through GLFW, which can't drive the motors. Steam
// Input can (ISteamInput::TriggerVibrationExtended), for any controller Steam handles, so the mod
// vibrates through it (SteamInput) when steamInput.enabled is on and the game runs under Steam.
// The game events are picked in Lua (Rumble.lua: shots, melee hits, damage, heartbeat) and sent
// here as short pulses; a pulse starts at full strength and fades out linearly over its
// duration. Overlapping pulses of a controller mix by taking the strongest value per motor.
// update() runs every frame from SteamInput.pollEvents, which knows the Steam controller handles.
public final class Rumble {
    private static final long RESEND_MS = 100;
    private static final float RESEND_DELTA = 0.02f;

    private static final class Pulse {
        int controller;
        float low, high, leftTrigger, trigger;
        long start;
        float ms;
    }

    private static final List<Pulse> pulses = new ArrayList<>();
    // Steam controller handle -> {low, high, left trigger, right trigger} as last sent
    private static final Map<Long, float[]> sent = new HashMap<>();
    private static final Map<Long, Long> sentTime = new HashMap<>();

    private Rumble() {}

    /**
     * Adds a pulse on a game controller (JoypadState.controllers index, as player:getJoypadBind()).
     * low = the big (left) motor, high = the small (right) motor, trigger = the right trigger
     * motor (Xbox One / Series controllers), each 0..1, scaled by rumble.strength and
     * rumble.&lt;event&gt;. ms = fade-out time.
     */
    @LuaMethod(name = "GamepadTweaks_rumble", global = true)
    public static void pulse(double controller, String event, double low, double high, double trigger, double ms) {
        pulse(controller, event, low, high, 0, trigger, ms);
    }

    /** As above with both trigger motors (left / right side of a vehicle, see VehicleRumble). */
    public static void pulse(double controller, String event, double low, double high, double leftTrigger,
                             double trigger, double ms) {
        Settings.refresh();
        if (!Settings.rumble || controller < 0 || ms <= 0 || !SteamInput.isReady()) {
            return;
        }
        float k = Settings.rumbleStrength * Settings.rumbleEvent(event);
        if (k <= 0) {
            return;
        }
        Pulse p = new Pulse();
        p.controller = (int) controller;
        p.low = clamp((float) low * k);
        p.high = clamp((float) high * k);
        p.leftTrigger = clamp((float) leftTrigger * k);
        p.trigger = clamp((float) trigger * k);
        p.start = System.currentTimeMillis();
        p.ms = (float) ms;
        synchronized (pulses) {
            pulses.add(p);
        }
        if (Settings.rumbleDebugLog && !"road".equals(event)) { // road: a grain every ~50 ms
            Log.info("rumble: " + event + " controller " + p.controller + " low=" + p.low + " high=" + p.high
                    + " triggers=" + p.leftTrigger + "/" + p.trigger + " " + Math.round(ms) + "ms");
        }
    }

    // Motor test (options button): each motor alone in turn, TEST_ON ms on, then a gap.
    private static final long TEST_ON = 900, TEST_STEP = 1300;
    private static final String[] TEST_NAMES = {"left grip (low)", "right grip (high)", "left trigger", "right trigger"};
    private static long testStart;

    /** Runs each motor alone in turn on every Steam controller: left grip, right grip, left trigger, right trigger. */
    @LuaMethod(name = "GamepadTweaks_rumbleTest", global = true)
    public static boolean test() {
        if (!SteamInput.isReady()) {
            Log.info("rumble test: Steam Input is not ready (steamInput.enabled, game started from Steam?)");
            return false;
        }
        testStart = System.currentTimeMillis();
        Log.info("rumble test: " + String.join(", ", TEST_NAMES));
        return true;
    }

    // the motor speeds of the test now, or null when no test runs
    private static float[] testValues(long now) {
        if (testStart == 0) {
            return null;
        }
        long t = now - testStart;
        int step = (int) (t / TEST_STEP);
        if (step >= TEST_NAMES.length) {
            testStart = 0;
            return new float[4]; // stop
        }
        float[] m = new float[4];
        if (t % TEST_STEP < TEST_ON) {
            m[step] = 0.7f;
        }
        return m;
    }

    /** True if vibration can reach the controllers (Lua skips the work otherwise). */
    @LuaMethod(name = "GamepadTweaks_rumbleAvailable", global = true)
    public static boolean available() {
        Settings.refresh();
        return Settings.rumble && SteamInput.isReady();
    }

    /**
     * Mixes the pulses and sends the motor speeds to the Steam controllers. ids[i] = the game
     * controller of handles[i], -1 if unknown (then a single controller takes every pulse, as
     * in Bindings.lua: it's the only player's).
     */
    static void update(long[] handles, int[] ids) {
        if (Settings.rumble) {
            try {
                RumbleEvents.update();
            } catch (RuntimeException e) {
                Log.error("rumble: state watch failed", e);
            }
        }
        long now = System.currentTimeMillis();
        boolean single = handles.length == 1 && ids[0] < 0;
        Map<Integer, float[]> mix = new HashMap<>();
        synchronized (pulses) {
            for (Iterator<Pulse> it = pulses.iterator(); it.hasNext(); ) {
                Pulse p = it.next();
                float t = (now - p.start) / p.ms;
                if (t >= 1) {
                    it.remove();
                    continue;
                }
                float fade = 1 - Math.max(0, t);
                float[] m = mix.computeIfAbsent(single ? ids[0] : p.controller, k -> new float[4]);
                m[0] = Math.max(m[0], p.low * fade);
                m[1] = Math.max(m[1], p.high * fade);
                m[2] = Math.max(m[2], p.leftTrigger * fade);
                m[3] = Math.max(m[3], p.trigger * fade);
            }
        }
        float[] test = testValues(now);
        for (int i = 0; i < handles.length; i++) {
            float[] m = test != null ? test : mix.getOrDefault(ids[i], new float[4]);
            if (test == null && (m[2] > 0 || m[3] > 0)
                    && (!Settings.rumbleTriggers || !SteamInput.hasTriggerMotors(handles[i]))) {
                // no trigger motors: the trigger side goes to the grip of that side
                m = new float[] {Math.max(m[0], m[2]), Math.max(m[1], m[3]), 0, 0};
            }
            float[] last = sent.get(handles[i]);
            boolean zero = m[0] == 0 && m[1] == 0 && m[2] == 0 && m[3] == 0;
            if (last == null) {
                if (zero) {
                    continue; // never vibrated: nothing to stop
                }
            } else {
                boolean lastZero = last[0] == 0 && last[1] == 0 && last[2] == 0 && last[3] == 0;
                if (zero && lastZero) {
                    continue;
                }
                // Steam keeps the motors at the last speed, so a fading pulse is re-sent when it
                // changed enough, and refreshed now and then in case Steam times it out.
                boolean changed = Math.abs(m[0] - last[0]) >= RESEND_DELTA || Math.abs(m[1] - last[1]) >= RESEND_DELTA
                        || Math.abs(m[2] - last[2]) >= RESEND_DELTA || Math.abs(m[3] - last[3]) >= RESEND_DELTA;
                Long time = sentTime.get(handles[i]);
                if (!zero && !changed && time != null && now - time < RESEND_MS) {
                    continue;
                }
            }
            if (SteamInput.vibrate(handles[i], m[0], m[1], m[2], m[3])) {
                sent.put(handles[i], m);
                sentTime.put(handles[i], now);
            }
        }
    }

    /** Disconnected controllers: forget what was sent to them. */
    static void retain(java.util.Set<Long> handles) {
        sent.keySet().retainAll(handles);
        sentTime.keySet().retainAll(handles);
    }

    private static float clamp(float v) {
        return Math.max(0, Math.min(1, v));
    }
}
