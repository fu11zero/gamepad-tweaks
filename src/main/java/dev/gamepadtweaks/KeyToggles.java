package dev.gamepadtweaks;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.BaseSoundManager;
import zombie.SoundManager;
import zombie.ui.FPSGraph;

// Keyboard toggles handled in Java with no Lua equivalent, for the mod's actions (KeyActions.lua):
// - music: SoundManager.updateMusic on TOGGLE_MUSIC flips allowMusic and stops the music;
// - FPS graph: IngameState.renderframeui on DISPLAY_FPS shows / hides FPSGraph.instance.
public final class KeyToggles {
    private KeyToggles() {}

    @LuaMethod(name = "GamepadTweaks_toggleMusic", global = true)
    public static void toggleMusic() {
        BaseSoundManager sound = SoundManager.instance;
        if (sound == null) {
            return;
        }
        sound.allowMusic = !sound.allowMusic;
        if (!sound.allowMusic) {
            sound.StopMusic();
        }
    }

    @LuaMethod(name = "GamepadTweaks_toggleFps", global = true)
    public static void toggleFps() {
        if (FPSGraph.instance == null) {
            FPSGraph.instance = new FPSGraph();
        }
        FPSGraph.instance.setVisible(!FPSGraph.instance.isVisible());
    }
}
