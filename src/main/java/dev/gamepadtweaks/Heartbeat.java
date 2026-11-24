package dev.gamepadtweaks;

import java.lang.reflect.Field;

import zombie.GameSounds;
import zombie.GameTime;
import zombie.SoundManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

// IsoPlayer.updateHeartSound updates the gain of a persistent Studio event. The installed
// HeartBeat event sustains at 210 ms on the Studio timeline while its instruments keep
// playing. Read the event fader's output peak so each motor update uses the current audio.
final class Heartbeat {
    private static final Field EVENT = eventField();
    // The two main peaks at the event's fader in the 42.22 bank measure about 0.006 and 0.010.
    private static final float MOTOR_GAIN = 100f;
    private static boolean meterFailed;
    private static FmodEventMeter meter;
    private static final long[] lastLog = new long[IsoPlayer.players.length];

    private Heartbeat() {}

    private static Field eventField() {
        try {
            Field field = IsoPlayer.class.getDeclaredField("heartEventInstance");
            field.setAccessible(true);
            return field;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.error("rumble: cannot read IsoPlayer.heartEventInstance", e);
            return null;
        }
    }

    static float strength(int playerIndex, float gain) {
        if (EVENT == null || meterFailed || GameServer.server || GameSounds.soundIsPaused || GameTime.isGamePaused()) {
            return 0;
        }
        IsoPlayer player = IsoPlayer.players[playerIndex];
        if (player == null || !player.isLocalPlayer() || player.isDead() || player.isAsleep()) {
            return 0;
        }
        try {
            long id = EVENT.getLong(player);
            if (id == 0) return 0;
            // The game's Settings_Sfx VCA is downstream of the event fader.
            float soundVolume = SoundManager.instance.getSoundVolume();
            if (soundVolume <= 0) return 0;
            if (meter == null) meter = new FmodEventMeter(IsoPlayer.players.length);
            float peak = meter.peak(id, playerIndex);
            float strength = Math.min(1f, peak * MOTOR_GAIN * soundVolume * gain);
            if (Settings.rumbleDebugLog && strength >= Rumble.MIN_SPEED) {
                long now = System.nanoTime();
                long last = lastLog[playerIndex];
                long gap = (now - last) / 1_000_000;
                if (last == 0 || gap >= 120) {
                    lastLog[playerIndex] = now;
                    Log.info("rumble: heartbeat player " + playerIndex + " event=" + id
                            + " peak=" + peak + " motor=" + strength + " gapMs=" + (last == 0 ? "-" : gap));
                }
            }
            return strength;
        } catch (Throwable e) {
            // FMOD's C API may be unavailable in another game build. Keep Steam Input active.
            meterFailed = true;
            Log.error("rumble: heartbeat meter unavailable", e);
            return 0;
        }
    }
}
