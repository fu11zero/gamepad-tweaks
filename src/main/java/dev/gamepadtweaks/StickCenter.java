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
// Instead the output is the distance from a learned center (no dead zone at all,
// rescaled so full deflection still gives +-1), and the center is learned only from drift:
// - "still": the samples of the last stillMs span less than stillRange (the jitter zone).
//   It only decides that the stick has stopped, it is never cut out of the input;
// - while still within recenterZone of zero, the center glides at recenterRate towards
//   the mean of that window (not the last sample, which jumps with the jitter);
// - drift and a deliberate small hold (thumb keeps the stick at 0.03 through a long
//   curve) look the same by position, so learning has to be "armed". A new resting spot
//   appears only after a release: the spring snaps the stick from far out back to the
//   center in a fraction of a second. Without hardware smoothing it overshoots and
//   oscillates, so the direction of the snap is unreliable; what is checked is that it
//   was further than releaseFrom from the center and got within recenterZone of it in
//   less than releaseMaxMs. That arms learning (also armed at start).
// - moving the stick slowly further than disarmDistance from where it last rested
//   (thumb steering, not a release) disarms it, so a deliberate hold isn't eaten.
//   Not checked for releaseSettleMs after a release: the overshoot swings that far.
public final class StickCenter {
    private static final int MAX_JOYPADS = 16;
    private static final int CAPACITY = 512; // samples kept: ~8 s at 60 fps

    private static final State[] STATES = new State[MAX_JOYPADS];

    private StickCenter() {}

    private static final class State {
        final long[] times = new long[CAPACITY];
        final float[] values = new float[CAPACITY];
        int head;   // next write index
        int count;
        long lastNanos;
        float center;
        boolean armed = true;
        float anchor = Float.NaN; // window mean when the stick last stood still
        long releaseNanos;        // when the last release was detected
        // per-frame results of scan()
        boolean still;
        float mean;
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
            s.anchor = Float.NaN;
            dt = 0;
        }
        s.lastNanos = now;
        push(s, now, raw);

        if (isRelease(s, now)) {
            if (!s.armed && Settings.debugLog) {
                Log.info(String.format("stick %d: release, center learning armed (center %.4f)", joypad, s.center));
            }
            s.armed = true;
            s.releaseNanos = now;
        }

        scan(s, now);
        if (s.still) {
            s.anchor = s.mean;
            if (s.armed && Math.abs(s.mean) < Settings.recenterZone) {
                float delta = s.mean - s.center;
                float step = Settings.recenterRate * dt;
                s.center = Math.abs(delta) <= step ? s.mean : s.center + Math.copySign(step, delta);
            }
        } else if (s.armed && !Float.isNaN(s.anchor)
                && now - s.releaseNanos > (long) (Settings.releaseSettleMs * 1e6f)
                && Math.abs(raw - s.anchor) > Settings.disarmDistance) {
            s.armed = false;
            if (Settings.debugLog) {
                Log.info(String.format("stick %d: moved off rest %.4f to %.4f, center learning disarmed (center %.4f)",
                        joypad, s.anchor, raw, s.center));
            }
        }
        return output(raw, s.center, Settings.noiseDeadZone);
    }

    public static float center(int joypad) {
        State s = joypad >= 0 && joypad < MAX_JOYPADS ? STATES[joypad] : null;
        return s == null ? 0f : s.center;
    }

    public static boolean armed(int joypad) {
        State s = joypad >= 0 && joypad < MAX_JOYPADS ? STATES[joypad] : null;
        return s == null || s.armed;
    }

    private static void push(State s, long now, float v) {
        s.times[s.head] = now;
        s.values[s.head] = v;
        s.head = (s.head + 1) % CAPACITY;
        s.count = Math.min(s.count + 1, CAPACITY);
    }

    private static int index(State s, int n) {
        return (s.head - 1 - n + CAPACITY) % CAPACITY;
    }

    /** still: the samples of the last stillMs span less than stillRange; mean: their average. */
    private static void scan(State s, long now) {
        long window = (long) (Settings.recenterStillMs * 1e6f);
        float min = Float.MAX_VALUE;
        float max = -Float.MAX_VALUE;
        double sum = 0;
        int k = 0;
        boolean covered = false;
        for (int n = 0; n < s.count; n++) {
            int i = index(s, n);
            if (now - s.times[i] > window) {
                covered = true;
                break;
            }
            float v = s.values[i];
            min = Math.min(min, v);
            max = Math.max(max, v);
            sum += v;
            k++;
        }
        s.still = covered && k > 0 && max - min < Settings.recenterStillRange;
        s.mean = k > 0 ? (float) (sum / k) : 0f;
    }

    /**
     * True on the frame the stick gets back near the center after a snap: within the last
     * releaseMaxMs it was further than releaseFrom from the center, and now it is within
     * recenterZone of it.
     */
    private static boolean isRelease(State s, long now) {
        if (Math.abs(s.values[index(s, 0)] - s.center) >= Settings.recenterZone) {
            return false;
        }
        // only the first sample back near the center counts, not every frame after it
        if (s.count > 1 && Math.abs(s.values[index(s, 1)] - s.center) < Settings.recenterZone) {
            return false;
        }
        long window = (long) (Settings.releaseMaxMs * 1e6f);
        for (int n = 1; n < s.count; n++) {
            int i = index(s, n);
            if (now - s.times[i] > window) {
                break;
            }
            if (Math.abs(s.values[i] - s.center) > Settings.releaseFrom) {
                return true;
            }
        }
        return false;
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
