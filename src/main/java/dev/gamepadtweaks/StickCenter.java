package dev.gamepadtweaks;

// Drifting stick center for steering.
//
// A released stick doesn't return to exactly 0: the spring leaves it somewhere
// near the center, a different spot after every move (measured -0.01..-0.05 on a
// Vader 5 Pro, up to +-0.077 on a Vader 3). Steering takes the raw stick without a
// dead zone, and at highway speed even a 0.0003 wheel angle (stick -0.03) drives
// the car in a long arc; the player has to hold the stick slightly off to go straight.
// A plain dead zone fixes that but kills fine steering.
//
// Instead: while the stick stands still near zero (thumb off, or resting on it -
// the two are indistinguishable and it doesn't matter), the center glides towards
// the current value at a constant rate, so the resting offset steers 0 after a
// fraction of a second. Steering moves the stick far more than the jitter, so
// the center doesn't follow it. Output = distance from the center, minus a tiny
// noise dead zone, rescaled so full deflection still gives +-1.
public final class StickCenter {
    private static final int MAX_JOYPADS = 16;
    private static final int CAPACITY = 256; // samples kept for the stillness window

    private static final State[] STATES = new State[MAX_JOYPADS];

    private StickCenter() {}

    private static final class State {
        final long[] times = new long[CAPACITY];
        final float[] values = new float[CAPACITY];
        int head;   // next write index
        int count;
        long lastNanos;
        float center;
    }

    /** Raw stick X -> corrected stick X. Call once per frame per driven vehicle. */
    public static float apply(int joypad, float raw) {
        if (!Settings.recenter || joypad < 0 || joypad >= MAX_JOYPADS) {
            return raw;
        }
        State s = STATES[joypad];
        if (s == null) {
            s = STATES[joypad] = new State();
        }
        long now = System.nanoTime();
        float dt = (now - s.lastNanos) / 1e9f;
        if (s.lastNanos == 0 || dt > 0.5f) {
            // first call or not driving for a while: the old window is stale
            s.count = 0;
            dt = 0;
        }
        s.lastNanos = now;
        push(s, now, raw);

        if (isStill(s, now) && Math.abs(raw) < Settings.recenterZone) {
            float delta = raw - s.center;
            float step = Settings.recenterRate * dt;
            s.center = Math.abs(delta) <= step ? raw : s.center + Math.copySign(step, delta);
        }
        return output(raw, s.center, Settings.noiseDeadZone);
    }

    public static float center(int joypad) {
        State s = joypad >= 0 && joypad < MAX_JOYPADS ? STATES[joypad] : null;
        return s == null ? 0f : s.center;
    }

    private static void push(State s, long now, float v) {
        s.times[s.head] = now;
        s.values[s.head] = v;
        s.head = (s.head + 1) % CAPACITY;
        s.count = Math.min(s.count + 1, CAPACITY);
    }

    /** True if the samples of the last stillMs span less than stillRange. */
    private static boolean isStill(State s, long now) {
        long window = (long) (Settings.recenterStillMs * 1e6f);
        float min = Float.MAX_VALUE;
        float max = -Float.MAX_VALUE;
        boolean covered = false;
        for (int n = 0; n < s.count; n++) {
            int i = (s.head - 1 - n + CAPACITY) % CAPACITY;
            if (now - s.times[i] > window) {
                covered = true;
                break;
            }
            min = Math.min(min, s.values[i]);
            max = Math.max(max, s.values[i]);
        }
        return covered && max - min < Settings.recenterStillRange;
    }

    private static float output(float raw, float center, float noise) {
        float d = raw - center;
        float mag = Math.abs(d) - noise;
        if (mag <= 0) {
            return 0f;
        }
        // remaining travel on this side of the center
        float travel = (d > 0 ? 1f - center : 1f + center) - noise;
        return Math.copySign(Math.min(mag / travel, 1f), d);
    }
}
