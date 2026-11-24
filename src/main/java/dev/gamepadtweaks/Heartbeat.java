package dev.gamepadtweaks;

import java.io.File;
import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemoryLayout;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.invoke.MethodHandle;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;

import zombie.GameSounds;
import zombie.GameTime;
import zombie.SoundManager;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;

import static java.lang.foreign.ValueLayout.ADDRESS;
import static java.lang.foreign.ValueLayout.JAVA_FLOAT;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_SHORT;

// IsoPlayer.updateHeartSound updates the gain of a persistent Studio event. The installed
// HeartBeat event sustains at 210 ms on the Studio timeline while its instruments keep
// playing. Read the event fader's output peak so each motor update uses the current audio.
final class Heartbeat {
    private static final Field EVENT = eventField();
    // The two main peaks at the event's fader in the 42.22 bank measure about 0.006 and 0.010.
    private static final float MOTOR_GAIN = 100f;
    private static boolean meterFailed;
    private static Meter meter;

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
            if (meter == null) meter = new Meter();
            float peak = meter.peak(id, playerIndex);
            float strength = Math.min(1f, peak * MOTOR_GAIN * soundVolume * gain);
            if (Settings.rumbleDebugLog && strength >= Rumble.MIN_SPEED) {
                long now = System.nanoTime();
                long last = meter.lastLog[playerIndex];
                long gap = (now - last) / 1_000_000;
                if (last == 0 || gap >= 120) {
                    meter.lastLog[playerIndex] = now;
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

    static final class Meter {
        private static final int DSP_FADER = -2; // FMOD_CHANNELCONTROL_DSP_FADER
        private static final int PLAYBACK_STOPPED = 2;
        private static final int PLAYBACK_STARTING = 3;
        // FMOD_DSP_METERING_INFO: int samples, float peak[32], float rms[32], short channels.
        private static final int CHANNELS = 32;
        private static final int PEAK_OFFSET = 4;
        private static final int CHANNEL_COUNT_OFFSET = PEAK_OFFSET + 2 * CHANNELS * 4;
        private static final int INFO_SIZE = 264;

        private final MethodHandle playbackState, getGroup, getDsp, enableMeter, getMeter, isVirtual;
        private final MemorySegment pointer = Arena.global().allocate(ADDRESS);
        private final MemorySegment status = Arena.global().allocate(JAVA_INT);
        private final MemorySegment info = Arena.global().allocate(INFO_SIZE, JAVA_FLOAT.byteAlignment());
        private final long[] eventIds = new long[4];
        private final long[] enabledDsp = new long[4];
        private final long[] lastLog = new long[4];

        Meter() {
            SymbolLookup core = library("fmod");
            SymbolLookup studio = library("fmodstudio");
            playbackState = bind(studio, "FMOD_Studio_EventInstance_GetPlaybackState", ADDRESS, ADDRESS);
            getGroup = bind(studio, "FMOD_Studio_EventInstance_GetChannelGroup", ADDRESS, ADDRESS);
            isVirtual = bind(studio, "FMOD_Studio_EventInstance_IsVirtual", ADDRESS, ADDRESS);
            getDsp = bind(core, "FMOD_ChannelGroup_GetDSP", ADDRESS, JAVA_INT, ADDRESS);
            enableMeter = bind(core, "FMOD_DSP_SetMeteringEnabled", ADDRESS, JAVA_INT, JAVA_INT);
            getMeter = bind(core, "FMOD_DSP_GetMeteringInfo", ADDRESS, ADDRESS, ADDRESS);
        }

        float peak(long event, int slot) throws Throwable {
            MemorySegment instance = MemorySegment.ofAddress(event);
            if ((int) playbackState.invokeExact(instance, status) != 0) return 0;
            int state = status.get(JAVA_INT, 0);
            if (state == PLAYBACK_STOPPED || state == PLAYBACK_STARTING) return 0;
            if ((int) isVirtual.invokeExact(instance, status) != 0 || status.get(JAVA_INT, 0) != 0) return 0;

            if ((int) getGroup.invokeExact(instance, pointer) != 0) return 0;
            MemorySegment group = pointer.get(ADDRESS, 0);
            if (group.address() == 0 || (int) getDsp.invokeExact(group, DSP_FADER, pointer) != 0) return 0;
            MemorySegment dsp = pointer.get(ADDRESS, 0);
            long address = dsp.address();
            if (address == 0) return 0;
            if (eventIds[slot] != event || enabledDsp[slot] != address) {
                if ((int) enableMeter.invokeExact(dsp, 0, 1) != 0) return 0;
                eventIds[slot] = event;
                enabledDsp[slot] = address;
            }

            if ((int) getMeter.invokeExact(dsp, MemorySegment.NULL, info) != 0) return 0;
            int count = Math.min(CHANNELS, info.get(JAVA_SHORT, CHANNEL_COUNT_OFFSET));
            float peak = 0;
            for (int channel = 0; channel < count; channel++) {
                float value = info.getAtIndex(JAVA_FLOAT, 1L + channel);
                if (Float.isFinite(value)) peak = Math.max(peak, value);
            }
            return peak;
        }

        private static MethodHandle bind(SymbolLookup library, String name, MemoryLayout... args) {
            return Linker.nativeLinker().downcallHandle(library.findOrThrow(name), FunctionDescriptor.of(JAVA_INT, args));
        }

        // Open the same FMOD libraries the game loaded. The C accessors are absent from its JNI API.
        private static SymbolLookup library(String base) {
            String paths = System.getProperty("java.library.path", "");
            for (String dir : paths.split(File.pathSeparator)) {
                for (String name : new String[] {base, base + "64"}) {
                    Path p = Path.of(dir, System.mapLibraryName(name));
                    if (Files.isRegularFile(p)) return SymbolLookup.libraryLookup(p.toAbsolutePath(), Arena.global());
                }
            }
            return SymbolLookup.libraryLookup(System.mapLibraryName(base), Arena.global());
        }
    }
}
