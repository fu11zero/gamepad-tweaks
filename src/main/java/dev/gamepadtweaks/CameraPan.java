package dev.gamepadtweaks;

import java.lang.reflect.Field;

import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.input.AimingReticle;
import zombie.iso.IsoCamera;
import zombie.iso.PlayerCamera;
import zombie.vehicles.BaseVehicle;

// Camera pan while aiming ("look far"), as the held "panCamera" action.
//
// Vanilla PlayerCamera.update pans a gamepad player's camera only while RB is down
// (JoypadManager.isRBPressed, hardcoded, no binding in Options -> Controller) and the player
// aims (or looks out of a vehicle), towards the aiming stick * 1500. Otherwise it eases the
// camera back to the player (returnToCenter). The keyboard has its own key (PAN_CAMERA,
// player 0 and the mouse only).
//
// Here RB reads as released inside PlayerCamera.update (Patches.CameraRB), so the pan follows
// the action alone; its default button is RB while aiming (Bindings.lua "aiming" layer).
// While the action is held, the camera eases (vanilla rate) towards the reticle instead:
// it follows the stick as before, and the gyro too (the stick may be centered then). Applied
// after vanilla's update, from the pan values it had before, so vanilla's return to the center
// in that frame is undone.
public final class CameraPan {
    private static final int MAX_PLAYERS = 4;
    private static final Field XF = field("rightClickXf");
    private static final Field YF = field("rightClickYf");
    private static final Field PAN_TIME = field("panTime");
    private static final float[][] before = new float[MAX_PLAYERS][2];
    private static final long[] beforeTime = new long[MAX_PLAYERS];
    /** Inside PlayerCamera.update: RB reads as released (Patches.CameraRB). */
    private static boolean inUpdate;

    private CameraPan() {}

    /** Public: advice code is inlined into JoypadManager, another package. */
    public static boolean inUpdate() {
        return inUpdate;
    }

    private static Field field(String name) {
        try {
            Field f = PlayerCamera.class.getDeclaredField(name);
            f.setAccessible(true);
            return f;
        } catch (ReflectiveOperationException e) {
            Log.error("PlayerCamera." + name + " not found, no camera pan action", e);
            return null;
        }
    }

    /** Before PlayerCamera.update. */
    public static void before(PlayerCamera camera) {
        inUpdate = true;
        int i = camera.playerIndex;
        if (i < 0 || i >= MAX_PLAYERS || XF == null || YF == null || PAN_TIME == null) {
            return;
        }
        try {
            before[i][0] = XF.getFloat(camera);
            before[i][1] = YF.getFloat(camera);
            beforeTime[i] = PAN_TIME.getLong(camera);
        } catch (IllegalAccessException e) {
            beforeTime[i] = Long.MIN_VALUE;
        }
    }

    /** After PlayerCamera.update. */
    public static void after(PlayerCamera camera) {
        inUpdate = false;
        int i = camera.playerIndex;
        if (i < 0 || i >= MAX_PLAYERS || XF == null || beforeTime[i] == Long.MIN_VALUE) {
            return;
        }
        IsoPlayer player = IsoPlayer.players[i];
        if (!HeldActions.playerHeld(player, HeldActions.PAN)
                || !(player.isAiming() || player.isLookingWhileInVehicle())
                || player.isJoypadIgnoreAimUntilCentered()) {
            return;
        }
        BaseVehicle vehicle = player.getVehicle();
        if (Core.getInstance().getOptionPanCameraWhileDriving() && vehicle != null
                && vehicle.getCurrentSpeedKmHour() > 1.0F) {
            return; // vanilla's driving pan comes first
        }
        float centerX = IsoCamera.getScreenWidth(i) / 2.0F;
        float centerY = IsoCamera.getScreenHeight(i) / 2.0F;
        if (centerX <= 0 || centerY <= 0) {
            return;
        }
        float targetX = (AimingReticle.getXA(i) / centerX - 1.0F) * 1500.0F;
        float targetY = (AimingReticle.getYA(i) / centerY - 1.0F) * 1500.0F;
        // vanilla: step = (target - pos) / (80 * mult), mult = 1 / (seconds * 110) / (0.5 * zoom)
        float seconds = beforeTime[i] < 0 ? 1.0F / 110.0F
                : (System.currentTimeMillis() - beforeTime[i]) / 1000.0F;
        float rate = Math.min(1.0F, seconds * 110.0F * 0.5F * Core.getInstance().getZoom(i) / 80.0F);
        float x = before[i][0] + (targetX - before[i][0]) * rate;
        float y = before[i][1] + (targetY - before[i][1]) * rate;
        try {
            XF.setFloat(camera, x);
            YF.setFloat(camera, y);
        } catch (IllegalAccessException e) {
            return;
        }
        camera.rightClickTargetX = targetX;
        camera.rightClickTargetY = targetY;
        camera.rightClickX = (int) x;
        camera.rightClickY = (int) y;
        player.dirtyRecalcGridStackTime = 2.0F;
    }
}
