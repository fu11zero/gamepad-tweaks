package dev.gamepadtweaks;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import zombie.GameTime;
import zombie.GameWindow;
import zombie.characters.IsoPlayer;
import zombie.gameStates.GameLoadingState;
import zombie.gameStates.IngameState;
import zombie.ui.UIManager;
import se.krka.kahlua.integration.annotations.LuaMethod;

// Controller vibration.
//
// Vanilla has no vibration at all: input goes through GLFW, which can't drive the motors. Steam
// Input can (ISteamInput::TriggerVibrationExtended), for any controller Steam handles, so the mod
// vibrates through it (SteamInput) when steamInput.enabled is on and the game runs under Steam.
// The game events are picked in Lua (Rumble.lua: shots, melee hits, damage) and sent
// here as short pulses; a pulse starts at full strength and fades out linearly over its
// duration. Overlapping pulses of a controller mix by taking the strongest value per motor.
// Heartbeat.java reads the current FMOD signal into the same mix.
// update() runs every frame from SteamInput.pollEvents, which knows the Steam controller handles.
public final class Rumble {
    private static final long RESEND_MS = 100;
    private static final float RESEND_DELTA = 0.02f;
    // Changes closer than this are held back (the end of a pulse, a stop, is never held).
    private static final long MIN_SEND_MS = 25;
    // Below this the motors barely turn: a fading tail is cut there. A motor left on such a low
    // speed (a lost stop, see STOP_REPEATS) stalls and spins up by itself, felt as growing.
    static final float MIN_SPEED = 0.04f;
    // The stop is sent again STOP_REPEATS times STOP_GAP_MS apart: a stop sent right after a
    // speed change was sometimes lost (the motors kept going after a shot or a short knock, until
    // the next pulse ended).
    private static final int STOP_REPEATS = 3;
    private static final long STOP_GAP_MS = 80;

    private static final class Pulse {
        int controller;
        float low, high, leftTrigger, trigger;
        long start;
        float ms;
        boolean cough;
    }

    private static final class Mix {
        final float[] motors = new float[4];
        boolean cough;
        boolean otherRumble;

        void add(Pulse pulse, float fade) {
            float low = pulse.low * fade, high = pulse.high * fade;
            float left = pulse.leftTrigger * fade, right = pulse.trigger * fade;
            motors[0] = Math.max(motors[0], low);
            motors[1] = Math.max(motors[1], high);
            motors[2] = Math.max(motors[2], left);
            motors[3] = Math.max(motors[3], right);
            if (low >= MIN_SPEED || high >= MIN_SPEED || left >= MIN_SPEED || right >= MIN_SPEED) {
                cough |= pulse.cough;
                otherRumble |= !pulse.cough;
            }
        }
    }

    private static final List<Pulse> pulses = new ArrayList<>();
    // Steam controller handle -> {low, high, left trigger, right trigger} as last sent
    private static final Map<Long, float[]> sent = new HashMap<>();
    private static final Map<Long, Long> sentTime = new HashMap<>();
    // Steam controller handle -> stops sent since the motors last ran
    private static final Map<Long, Integer> stops = new HashMap<>();
    // Ambient events (not caused by the player's body) damped while aiming a firearm: the
    // shaking moves a gyro reticle. Hurt, falls and shots are never damped.
    private static final java.util.Set<String> AMBIENT = java.util.Set.of("heartbeat", "thunder", "thump", "window", "tool", "blackout");

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
        int player = playerOf((int) controller);
        float k = gain(event, player);
        if (k <= 0) {
            return;
        }
        Pulse p = new Pulse();
        p.controller = (int) controller;
        p.cough = "cough".equals(event);
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
            Log.info("rumble: " + event + " player " + player + " controller " + p.controller + " low=" + p.low + " high=" + p.high
                    + " triggers=" + p.leftTrigger + "/" + p.trigger + " " + Math.round(ms) + "ms");
        }
    }

    private static float gain(String event, int player) {
        float gain = Settings.rumbleStrength * Settings.rumbleEvent(event) * Settings.rumblePlayer(player);
        return AMBIENT.contains(event) && aimingFirearm(player) ? gain * Settings.rumbleAiming : gain;
    }

    /** True if the local player (0..3) is aiming a firearm (as the Steam "aiming" layer). */
    public static boolean aimingFirearm(int player) {
        IsoPlayer p = player >= 0 && player < IsoPlayer.players.length ? IsoPlayer.players[player] : null;
        return p != null && p.isAiming() && p.isRangedWeaponEquipped();
    }

    // The local player on a game controller (0..3), -1 if none.
    static int playerOf(int controller) {
        for (int i = 0; i < IsoPlayer.players.length; i++) {
            IsoPlayer p = IsoPlayer.players[i];
            if (p != null && p.isLocalPlayer() && p.getJoypadBind() == controller) {
                return i;
            }
        }
        return -1;
    }

    // The game controller of the only local player on a joypad, or -1 when there are none or several.
    private static int onlyJoypad() {
        int found = -1;
        for (IsoPlayer p : IsoPlayer.players) {
            if (p != null && p.isLocalPlayer() && p.getJoypadBind() >= 0) {
                if (found >= 0) {
                    return -1;
                }
                found = p.getJoypadBind();
            }
        }
        return found;
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
     * controller of handles[i], -1 if unknown. An unknown single Steam controller takes the pulses
     * of the only joypad player (as in Bindings.lua), but only when there is exactly one: with
     * several joypad players (one on a pad Steam doesn't handle) it used to take everyone's
     * pulses, so that player felt the others' events.
     */
    static void update(long[] handles, int[] ids) {
        boolean loading = GameWindow.states.current instanceof GameLoadingState;
        if (Settings.rumble && !loading) {
            try {
                RumbleEvents.update();
            } catch (RuntimeException e) {
                Log.error("rumble: state watch failed", e);
            }
        }
        long now = System.currentTimeMillis();
        int only = handles.length == 1 && ids[0] < 0 ? onlyJoypad() : -1;
        Map<Integer, Mix> mix = new HashMap<>();
        synchronized (pulses) {
            for (Iterator<Pulse> it = pulses.iterator(); it.hasNext(); ) {
                Pulse p = it.next();
                float t = (now - p.start) / p.ms;
                if (t >= 1) {
                    it.remove();
                    continue;
                }
                float fade = 1 - Math.max(0, t);
                if (loading || only >= 0 && p.controller != only) {
                    continue;
                }
                mix.computeIfAbsent(only >= 0 ? -1 : p.controller, k -> new Mix()).add(p, fade);
            }
        }
        float[] test = testValues(now);
        boolean playing = Settings.rumble && GameWindow.states.current instanceof IngameState;
        boolean paused = playing && (GameTime.isGamePaused()
                || UIManager.getSpeedControls() != null && UIManager.getSpeedControls().getCurrentGameSpeed() > 1);
        boolean loadingKnocks = LoadingRumble.update(handles, ids, now, test == null && Settings.rumble);
        float blast = playing ? BlackoutRumble.strength(now) : 0;
        if (!playing || test != null) {
            ColdRumble.reset();
        }
        if (!playing) {
            BlackoutRumble.reset();
        }
        for (int i = 0; i < handles.length; i++) {
            Mix combined = mix.get(ids[i]);
            float[] m = test != null ? test : combined == null ? new float[4] : combined.motors;
            if (test == null && Settings.rumble && !loading) {
                int controller = ids[i] >= 0 ? ids[i] : only;
                int player = controller >= 0 ? playerOf(controller) : -1;
                if (player >= 0) {
                    float heartbeatGain = gain("heartbeat", player);
                    float heartbeat = heartbeatGain > 0 ? Heartbeat.strength(player, heartbeatGain) : 0;
                    m[0] = Math.max(m[0], heartbeat);
                    if (playing) {
                        float blackout = blast > 0 && !IsoPlayer.players[player].isDead()
                                ? clamp(blast * gain("blackout", player)) : 0;
                        m[0] = Math.max(m[0], blackout);
                        boolean busy = heartbeat >= MIN_SPEED || blackout >= MIN_SPEED
                                || (combined != null && combined.otherRumble);
                        float cold = ColdRumble.strength(player, controller, now, gain("cold", player), busy, paused);
                        // Give the cough or sneeze its own short hit while the shiver keeps its phase.
                        if (combined == null || !combined.cough) {
                            m[1] = Math.max(m[1], cold);
                        }
                    }
                }
            }
            if (loadingKnocks) {
                LoadingRumble.mix(handles[i], now, m);
            }
            if (test == null && (m[2] > 0 || m[3] > 0)
                    && (!Settings.rumbleTriggers || !SteamInput.hasTriggerMotors(handles[i]))) {
                // no trigger motors: the trigger side goes to the grip of that side
                m = new float[] {Math.max(m[0], m[2]), Math.max(m[1], m[3]), 0, 0};
            }
            if (test == null) {
                m = new float[] {cut(m[0]), cut(m[1]), cut(m[2]), cut(m[3])};
            }
            float[] last = sent.get(handles[i]);
            boolean zero = m[0] == 0 && m[1] == 0 && m[2] == 0 && m[3] == 0;
            Long time = sentTime.get(handles[i]);
            if (last == null) {
                if (zero) {
                    continue; // never vibrated: nothing to stop
                }
            } else {
                boolean lastZero = last[0] == 0 && last[1] == 0 && last[2] == 0 && last[3] == 0;
                if (zero && lastZero) {
                    // repeat the stop a few times in case one was lost
                    int done = stops.getOrDefault(handles[i], STOP_REPEATS);
                    if (done >= STOP_REPEATS || time != null && now - time < STOP_GAP_MS) {
                        continue;
                    }
                    stops.put(handles[i], done + 1);
                } else if (zero) {
                    stops.put(handles[i], 0);
                } else {
                    // Steam keeps the motors at the last speed, so a fading pulse is re-sent when it
                    // changed enough, and refreshed now and then in case Steam times it out.
                    boolean changed = Math.abs(m[0] - last[0]) >= RESEND_DELTA || Math.abs(m[1] - last[1]) >= RESEND_DELTA
                            || Math.abs(m[2] - last[2]) >= RESEND_DELTA || Math.abs(m[3] - last[3]) >= RESEND_DELTA;
                    long age = time == null ? Long.MAX_VALUE : now - time;
                    // a new pulse (from a stop) goes at once, a change waits MIN_SEND_MS
                    if (!lastZero && (changed ? age < MIN_SEND_MS : age < RESEND_MS)) {
                        continue;
                    }
                }
            }
            if (Settings.rumbleDebugLog && !zero && (last == null || (last[0] == 0 && last[1] == 0 && last[2] == 0 && last[3] == 0))) {
                Log.info("rumble: motors on, steam controller " + Long.toUnsignedString(handles[i]) + " -> controller "
                        + ids[i] + " (player " + (ids[i] >= 0 ? playerOf(ids[i]) : only >= 0 ? playerOf(only) : -1) + ")");
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
        stops.keySet().retainAll(handles);
    }

    private static float cut(float v) {
        return v < MIN_SPEED ? 0 : v;
    }

    private static float clamp(float v) {
        return Math.max(0, Math.min(1, v));
    }
}
