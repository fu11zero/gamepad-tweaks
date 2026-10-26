package dev.gamepadtweaks;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaManager;
import zombie.input.JoypadManager;
import zombie.worldMap.UIWorldMapV1;

// Analog map panning and zooming, called every frame from the Lua override of
// ISWorldMap:updateJoypad / ISMap:updateJoypad (media/lua/client/GamepadTweaks/MapControls.lua).
//
// Vanilla (ISWorldMap:updateJoypad):
// - the stick is treated as a button: anything below 0.5 per axis (on top of the game's
//   stick dead zone) is ignored, and after crossing it the map stays put for 150 ms;
// - the map center is snapped to whole squares (floor/ceil), so at high zoom it moves in jumps;
// - in isometric view diagonals are thrown away and the stick is rotated to the nearest axis;
// - LT/RT are buttons (value > 0.7): each press zooms one level, holding repeats a level
//   only after the previous step's animation has finished;
// - the paper map (ISMap) doesn't read the stick at all, only the D-pad.
// Here: past the game's stick dead zone the pan speed follows the stick deflection
// (in screen directions, also in isometric view), and the zoom speed follows how far
// the triggers are pressed.
public final class MapControls {
    private static final float MAX_DT_MS = 100f;

    private MapControls() {}

    /**
     * Pans and zooms {@code map} for one frame. Returns false when the controller is
     * unknown or map.smooth is off, so the Lua side falls back to vanilla.
     */
    @LuaMethod(name = "GamepadTweaks_updateMap", global = true)
    public static boolean update(UIWorldMapV1 map, double controllerId, double dtMs,
                                 double width, double height, boolean allowPan) {
        Settings.refresh();
        int id = (int) controllerId;
        JoypadManager.Joypad joypad = JoypadManager.instance.getFromControllerID(id);
        if (!Settings.mapSmooth || map == null || joypad == null) {
            return false;
        }
        float dt = (float) Math.max(0.0, Math.min(dtMs, MAX_DT_MS)) / 1000f;
        if (dt <= 0f) {
            return true;
        }
        try {
            zoom(map, joypad, dt);
            if (allowPan) {
                pan(map, joypad, id, dt, (float) width, (float) height);
            }
        } catch (RuntimeException e) {
            Log.error("map update failed", e);
            return false;
        }
        return true;
    }

    private static void zoom(UIWorldMapV1 map, JoypadManager.Joypad joypad, float dt) {
        // getLTValue/getRTValue: -1 released .. 1 pressed (no dead zone, see Triggers)
        float in = trigger(joypad.getRTValue());
        float out = trigger(joypad.getLTValue());
        float speed = Settings.mapZoomSpeed * (curve(in, Settings.mapZoomExponent) - curve(out, Settings.mapZoomExponent));
        if (speed != 0f) {
            // setZoom keeps the center and skips the zoom animation (both zoomF and displayZoomF)
            map.setZoom(map.getZoomF() + speed * dt);
        }
    }

    private static float trigger(float value) {
        float v = (value + 1f) / 2f;
        float dz = Settings.mapTriggerDeadZone;
        return v <= dz ? 0f : Math.min(1f, (v - dz) / (1f - dz));
    }

    private static void pan(UIWorldMapV1 map, JoypadManager.Joypad joypad, int id,
                            float dt, float width, float height) {
        // Raw* = the game's radial stick dead zone, rescaled to start from 0, without the
        // diagonal "squaring" of getMovementAxisX
        float x = joypad.getMovementAxisXRaw();
        float y = joypad.getMovementAxisYRaw();
        float povX = LuaManager.GlobalObject.getControllerPovX(id);
        float povY = LuaManager.GlobalObject.getControllerPovY(id);
        if (povX != 0f || povY != 0f) {
            x = Math.signum(povX) * Settings.mapDpadDeflection;
            y = Math.signum(povY) * Settings.mapDpadDeflection;
        }
        float len = (float) Math.sqrt(x * x + y * y);
        if (len <= 0f) {
            return;
        }
        // speed in screen pixels per second, relative to the map size so it doesn't
        // depend on the resolution; the curve gives fine control at small deflections
        float pixels = Settings.mapPanSpeed * Math.min(width, height)
                * curve(Math.min(1f, len), Settings.mapPanExponent) * dt;
        float dx = x / len * pixels;
        float dy = y / len * pixels;

        // screen offset -> world offset through the map's own projection (handles isometric)
        float zoom = map.getZoomF();
        float cx = map.getCenterWorldX();
        float cy = map.getCenterWorldY();
        float uiX = width / 2f;
        float uiY = height / 2f;
        float wx = map.uiToWorldX(uiX + dx, uiY + dy, zoom, cx, cy) - map.uiToWorldX(uiX, uiY, zoom, cx, cy);
        float wy = map.uiToWorldY(uiX + dx, uiY + dy, zoom, cx, cy) - map.uiToWorldY(uiX, uiY, zoom, cx, cy);
        if (Float.isFinite(wx) && Float.isFinite(wy)) {
            map.centerOn(cx + wx, cy + wy);
        }
    }

    private static float curve(float v, float exponent) {
        return v <= 0f ? 0f : (float) Math.pow(v, exponent);
    }
}
