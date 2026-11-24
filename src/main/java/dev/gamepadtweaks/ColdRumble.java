package dev.gamepadtweaks;

import java.util.Arrays;

import zombie.characters.IsoPlayer;
import zombie.scripting.objects.MoodleType;

/** Shivering follows the hypothermia moodle and gives way to action and other haptics. */
final class ColdRumble {
    private static final long QUIET_MS = 1800;
    private static final long ONSET_MS = 2600;
    private static final long REMINDER_MS = 1400;
    private static final int COLD_LEVEL = 2;
    private static final int CRITICAL_LEVEL = 4;
    private static final State[] states = new State[IsoPlayer.players.length];

    private ColdRumble() {}

    static void reset() {
        Arrays.fill(states, null);
    }

    static float strength(int slot, int controller, long now, float gain, boolean otherRumble, boolean paused) {
        IsoPlayer p = IsoPlayer.players[slot];
        int level = p.getMoodles().getMoodleLevel(MoodleType.HYPOTHERMIA);
        if (gain <= 0 || p.isDead() || level < COLD_LEVEL) {
            states[slot] = null;
            return 0;
        }
        State state = states[slot];
        if (state == null || state.player != p || state.controller != controller) {
            state = new State(p, controller);
            states[slot] = state;
        }
        boolean busy = paused || otherRumble || p.getVehicle() != null || p.isAiming()
                || p.isRunning() || p.isSprinting() || p.isAttacking() || p.isDoingActionThatCanBeCancelled()
                || p.isPerformingAnAction() || p.isCurrentlyBusy() || p.isDraggingCorpse() || p.isClimbing()
                || p.isFalling() || p.isKnockedDown() || p.isGettingUp() || p.isBumped();
        float walking = level >= CRITICAL_LEVEL ? 0.46f : 0.62f;
        float motion = p.isSitting() ? 1f : p.isPlayerMoving() ? walking : 0.86f;
        return Math.min(1, gain * state.sample(now, busy, level) * motion);
    }

    private static final class State {
        final IsoPlayer player;
        final int controller;
        boolean onset = true;
        boolean resuming;
        long quietUntil;
        long started;
        long criticalStarted;
        long lastEnd;
        long lastReminder;

        State(IsoPlayer player, int controller) {
            this.player = player;
            this.controller = controller;
        }

        float sample(long now, boolean busy, int level) {
            if (busy) {
                if (started != 0 && now - started >= 950) {
                    onset = false;
                }
                started = 0;
                criticalStarted = 0;
                quietUntil = now + QUIET_MS;
                resuming = true;
                return 0;
            }
            if (now < quietUntil) {
                return 0;
            }
            if (level >= CRITICAL_LEVEL) {
                if (criticalStarted == 0) {
                    criticalStarted = now;
                }
                started = 0;
                onset = false;
                resuming = false;
                long age = now - criticalStarted;
                // Slow swells underneath the quicker tremor. Keep the peaks light even when seated.
                float swell = 0.115f + 0.035f * (float) Math.sin(age * (2 * Math.PI / 2300));
                return smooth(age / 1250f) * swell * tremor(age);
            }
            if (criticalStarted != 0) {
                criticalStarted = 0;
                lastEnd = now;
            }
            if (started == 0) {
                long gap = level > COLD_LEVEL ? 10_000 : 30_000;
                long minimum = level > COLD_LEVEL ? 10_000 : 12_000;
                long readyAt = resuming ? lastReminder + minimum : lastEnd + gap;
                if (!onset && now < readyAt) {
                    return 0;
                }
                resuming = false;
                started = now;
                if (!onset) {
                    lastReminder = now;
                }
            }
            long age = now - started;
            if (age >= (onset ? ONSET_MS : REMINDER_MS)) {
                started = 0;
                onset = false;
                lastEnd = now;
                return 0;
            }
            // Slow rise and release with a small, quicker fluctuation in the grip.
            float envelope = onset
                    ? 0.23f * smooth(age / 950f) * (1 - smooth((age - 1100) / 1500f))
                    : 0.15f * smooth(age / 420f) * (1 - smooth((age - 540) / 860f));
            return envelope * tremor(age);
        }
    }

    private static float tremor(long age) {
        return 0.86f + 0.14f * (float) Math.cos(age * (2 * Math.PI / 230));
    }

    private static float smooth(float value) {
        float t = Math.max(0, Math.min(1, value));
        return t * t * (3 - 2 * t);
    }
}
