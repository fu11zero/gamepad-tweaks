package dev.gamepadtweaks;

import fmod.fmod.FMODSoundEmitter;
import me.zed_0xff.zombie_buddy.Patch;

/** Start the grid shutdown haptic envelope when the explosion reaches the FMOD mix. */
public final class BlackoutRumble {
    private static final long START_FALLBACK_MS = 100;
    private static final long TAIL_MS = 4000;
    // In the installed bank the event fader is near 0.002 when the blast first reaches
    // the master output, then rises above 0.02 in about 25 ms.
    private static final float BLAST_PEAK = 0.002f;

    private static FMODSoundEmitter source;
    private static long event;
    private static long queued;
    private static long start;
    private static FmodEventMeter meter;
    private static boolean meterFailed;

    private BlackoutRumble() {}

    // Both 42.21 and 42.22 use this sound for the grid outage. The Lua electricity event
    // is also fired by generators in 42.22 and is absent in 42.21.
    @Patch(className = "fmod.fmod.FMODSoundEmitter", methodName = "playSound")
    public static class Sound {
        @Patch.OnExit
        public static void exit(@Patch.This FMODSoundEmitter emitter, @Patch.Argument(0) String sound,
                                @Patch.Return long instance) {
            if (instance != 0 && "WorldEventElectricityShutdown".equals(sound)) {
                BlackoutRumble.queued(emitter, instance);
            }
        }
    }

    public static void queued(FMODSoundEmitter emitter, long instance) {
        source = emitter;
        event = instance;
        queued = System.currentTimeMillis();
        start = 0;
    }

    static void reset() {
        source = null;
        event = 0;
    }

    static float strength(long now) {
        if (source == null) {
            return 0;
        }
        if (!source.isPlaying(event)) {
            reset();
            return 0;
        }
        if (start == 0) {
            if (!heardBlast() && now - queued < START_FALLBACK_MS) {
                return 0;
            }
            start = now;
            if (Settings.rumbleDebugLog) {
                Log.info("rumble: power grid blast after " + (now - queued) + "ms");
            }
        }
        long age = now - start;
        if (age >= TAIL_MS) {
            reset();
            return 0;
        }
        float impact = 0.85f * Math.max(0, 1 - age / 400f);
        float roll = 0.56f * (1 - age / (float) TAIL_MS);
        return Math.max(impact, roll);
    }

    private static boolean heardBlast() {
        if (meterFailed) {
            return false;
        }
        try {
            if (meter == null) meter = new FmodEventMeter(1);
            return meter.peak(event, 0) >= BLAST_PEAK;
        } catch (Throwable e) {
            meterFailed = true;
            Log.error("rumble: blackout meter unavailable", e);
            return false;
        }
    }
}
