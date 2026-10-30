package dev.gamepadtweaks;

import java.lang.reflect.Field;

import zombie.characters.CharacterInputMode;
import zombie.characters.CharacterJoypadAxis2dBinding;
import zombie.characters.IsoPlayer;
import zombie.input.AimingMode;
import zombie.input.AimingReticle;
import zombie.input.JoypadAxis2d;
import zombie.iso.IsoCamera;
import zombie.iso.Vector2;

// Steam Input analog actions (SteamInput.Analog) added to the game's own gamepad input.
// Steam does everything about the source (gyro activation, sensitivity, dead zones, smoothing),
// so the values are added as they come; the stick keeps working as before.
//
// Aim: the gamepad reticle (AimingReticle) aims at center + half screen * stick
// (getAimingScreenX/Y), then AimingMode.lerpAiming moves it there (precise firearm aim) or
// keeps only the direction at a fixed distance (melee, unarmed, plain aim). The player's
// facing (IsoPlayer.calculateAimVector) is taken from the reticle. The "aim" deltas (mouse
// pixels) move that target: an offset per player, added while the player aims and dropped
// when aiming ends, so it starts from the stick (or from the player with the stick released).
// In precise aim lerpAiming eases the reticle towards the target (6-9% of the way per frame),
// smoothing meant for the stick; the reticle itself (aimingPositions) is moved by the same
// delta too, so the gyro part comes at once and only the stick part is eased.
// Steer: added to the steering stick before the mod's shaping (Patches.SteeringInput).
// Move: added to the Movement axis binding (CharacterJoypadAxis2dBinding), which the walking
// code reads; it counts as applied while non-zero. Length bindings on that stick (Run at full
// deflection) see it too (Patches.MoveAxisDown).
public final class AnalogInput {
    private static final int MAX_PLAYERS = 4;
    // screen pixels, per player index
    private static final float[][] aimOffset = new float[MAX_PLAYERS][2];
    // the stick target of the last getAimingScreenX/Y, to keep the offset on screen beforehand
    private static final float[][] aimBase = new float[MAX_PLAYERS][2];
    private static final float[] tmp = new float[2];
    private static final Vector2[] aimingPositions = aimingPositions();

    private static Vector2[] aimingPositions() {
        try {
            Field f = AimingReticle.class.getDeclaredField("aimingPositions");
            f.setAccessible(true);
            return (Vector2[]) f.get(null);
        } catch (Throwable t) {
            Log.error("AimingReticle.aimingPositions not found, gyro aim is eased like the stick", t);
            return null;
        }
    }

    private AnalogInput() {}

    /** Before AimingReticle.update (Mouse.update, every frame): reads Steam, takes the aim deltas. */
    public static void updateAim() {
        SteamInput.updateAnalog();
        for (int i = 0; i < MAX_PLAYERS; i++) {
            IsoPlayer player = IsoPlayer.getPlayer(i);
            float[] off = aimOffset[i];
            if (player == null || player.getInputMode() != CharacterInputMode.GAMEPAD) {
                off[0] = 0;
                off[1] = 0;
                continue;
            }
            SteamInput.takeDelta(player.getJoypadBind(), SteamInput.Analog.AIM, tmp);
            if (!player.isAiming()) {
                off[0] = 0;
                off[1] = 0;
                continue;
            }
            if (tmp[0] == 0 && tmp[1] == 0) {
                continue;
            }
            float shiftX = move(off, 0, tmp[0], IsoCamera.getScreenWidth(i), aimBase[i][0]);
            float shiftY = move(off, 1, tmp[1], IsoCamera.getScreenHeight(i), aimBase[i][1]);
            if (aimingPositions != null && eased(player)) {
                Vector2 pos = aimingPositions[i];
                pos.x += shiftX;
                pos.y += shiftY;
            }
        }
    }

    // Adds the delta to the offset, keeping base + offset on the screen; returns the change.
    private static float move(float[] off, int axis, float delta, float size, float base) {
        float before = off[axis];
        off[axis] = Math.max(0, Math.min(size, base + before + delta)) - base;
        return off[axis] - before;
    }

    // As AimingMode.lerpAiming: not snapped in front of the player, not at a fixed distance.
    private static boolean eased(IsoPlayer player) {
        AimingMode mode = player.getAimingMode();
        if (mode == null || mode.fixedAtMinDistance) {
            return false;
        }
        return player.isAimKeyDown() || !player.isAiming();
    }

    /** After AimingReticle.getAimingScreenX/Y: the stick target plus the offset, kept on the player's screen. */
    public static float aimTarget(IsoPlayer player, float target, boolean y) {
        int i = player.getIndex();
        if (i < 0 || i >= MAX_PLAYERS) {
            return target;
        }
        float[] off = aimOffset[i];
        int axis = y ? 1 : 0;
        aimBase[i][axis] = target;
        if (off[axis] == 0) {
            return target;
        }
        float size = y ? IsoCamera.getScreenHeight(i) : IsoCamera.getScreenWidth(i);
        float result = Math.max(0, Math.min(size, target + off[axis]));
        // past the edge: the offset stops there, so turning back moves the reticle at once
        off[axis] = result - target;
        return result;
    }

    /** Steering stick plus the "steer" action, -1..1. */
    public static float steer(int controllerId, float stick) {
        SteamInput.value(controllerId, SteamInput.Analog.STEER, tmp);
        return tmp[0] == 0 ? stick : Math.max(-1, Math.min(1, stick + tmp[0]));
    }

    /** Movement axis plus the "move" action, -1..1. */
    public static float move(int controllerId, float value, boolean y) {
        SteamInput.value(controllerId, SteamInput.Analog.MOVE, tmp);
        float add = y ? tmp[1] : tmp[0];
        return add == 0 ? value : Math.max(-1, Math.min(1, value + add));
    }

    /** A min..max length binding on the movement stick's axis, with the "move" action added. */
    public static boolean moveAxisDown(int controllerId, JoypadAxis2d axis, float min, float max) {
        if (axis == null || axis != CharacterJoypadAxis2dBinding.Movement.getBinding() || !moveApplied(controllerId)) {
            return false;
        }
        float length = CharacterJoypadAxis2dBinding.Movement.getLength(controllerId);
        return length >= min && length <= max;
    }

    public static boolean moveApplied(int controllerId) {
        SteamInput.value(controllerId, SteamInput.Analog.MOVE, tmp);
        return tmp[0] != 0 || tmp[1] != 0;
    }
}
