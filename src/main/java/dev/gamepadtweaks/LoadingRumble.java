package dev.gamepadtweaks;

import java.lang.reflect.Field;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.GameWindow;
import zombie.core.skinnedmodel.ModelManager;
import zombie.gameStates.GameLoadingState;
import zombie.input.JoypadManager;
import zombie.iso.WorldStreamer;

/** Two knocks for the controller that can dismiss the loading screen. */
public final class LoadingRumble {
    private static final Field PROMPT_ALPHA = promptAlpha();
    private static GameLoadingState loading;
    private static long target;
    private static long started;

    private LoadingRumble() {}

    // Vanilla can disable OnRenderTick while loading, so the Lua Steam poll may not run here.
    @Patch(className = "zombie.gameStates.GameLoadingState", methodName = "render")
    public static class Render {
        @Patch.OnExit
        public static void exit() {
            SteamInput.pollLoading();
        }
    }

    @Patch(className = "zombie.gameStates.GameLoadingState", methodName = "exit")
    public static class Exit {
        @Patch.OnEnter
        public static void enter() {
            LoadingRumble.stop();
        }
    }

    public static void stop() {
        if (started != 0) {
            SteamInput.vibrate(target, 0, 0, 0, 0);
        }
        loading = null;
        started = 0;
    }

    static boolean update(long[] handles, int[] ids, long now, boolean enabled) {
        if (!(GameWindow.states.current instanceof GameLoadingState state)) {
            loading = null;
            started = 0;
            return false;
        }
        if (loading != state) {
            loading = state;
            started = 0;
        }
        if (!enabled || Settings.rumblePlayer(0) == 0 || Settings.rumbleEvent("ready") == 0
                || Settings.rumbleStrength == 0 || GameWindow.activatedJoyPad == null
                || GameWindow.activatedJoyPad.isDisabled() || GameWindow.serverDisconnected
                || GameLoadingState.playerWrongIP || GameLoadingState.worldVersionError) {
            return false;
        }
        if (started != 0) {
            return now - started < 275;
        }
        // Vanilla starts animating this alpha only once it actually draws "Press A to start".
        // The debug flag can set showedClickToSkip earlier and that flag survives a reload.
        if (!promptShown(state) || WorldStreamer.instance.isBusy() || ModelManager.instance.isLoadingAnimations()) {
            return false;
        }
        int active = GameWindow.activatedJoyPad.getID();
        for (int i = 0; i < handles.length; i++) {
            if (ids[i] == active || (handles.length == 1 && ids[i] < 0 && JoypadManager.instance.joypadList.size() == 1)) {
                target = handles[i];
                started = now;
                if (Settings.rumbleDebugLog) {
                    Log.info("rumble: ready on controller " + active);
                }
                return true;
            }
        }
        return false;
    }

    static void mix(long handle, long now, float[] motors) {
        if (handle != target) {
            return;
        }
        long age = now - started;
        float tap = tap(age);
        float gain = Settings.rumbleStrength * Settings.rumbleEvent("ready");
        motors[0] = Math.max(motors[0], Math.min(1, 0.45f * tap * gain));
        motors[1] = Math.max(motors[1], Math.min(1, 0.62f * tap * gain));
    }

    static float tap(long age) {
        if (age < 0 || age >= 275) {
            return 0;
        }
        if (age < 100) {
            return 0.85f * (1 - age / 100f);
        }
        return age >= 155 ? 1 - (age - 155) / 120f : 0;
    }

    private static boolean promptShown(GameLoadingState state) {
        try {
            return PROMPT_ALPHA != null && PROMPT_ALPHA.getFloat(state) < 1;
        } catch (IllegalAccessException e) {
            return false;
        }
    }

    private static Field promptAlpha() {
        try {
            Field field = GameLoadingState.class.getDeclaredField("clickToSkipAlpha");
            field.setAccessible(true);
            return field;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.warn("rumble: cannot detect the loading screen prompt");
            return null;
        }
    }
}
