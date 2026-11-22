package dev.gamepadtweaks;

import zombie.characters.IsoPlayer;
import zombie.iso.IsoCamera;
import zombie.iso.PlayerCamera;
import zombie.iso.Vector2;

// Aiming with PrecisionAim alone (half RT or the Steam Aim action, without the Aim stick) slowly
// turns the character towards the top of the screen with a melee weapon or unarmed (towards the
// bottom with a firearm).
//
// Vanilla: without the Aim stick the reticle snaps in front of the player
// (AimingMode.snapAimInFrontOfPlayer): the point one tile ahead along the animated facing, at the
// height 0.57 (melee) / 0.468 (firearm), to the screen. The facing is then taken back from the
// reticle (IsoPlayer.calculateAimVector, used by updateMovementFromInput and the aiming facing)
// by unprojecting it at a different height, the chest (getAimOriginPosZ = z + 0.495). A point
// drawn higher than the height it is read at lands further up the screen, so the facing gets a
// bias towards screen-up, the next frame's snap starts from that facing, and the character keeps
// turning until it faces straight up (or down for 0.468).
// Here: the snapped point is put at the height it is read at, so it reads back as the facing.
public final class AimSnap {
    private static final Vector2 forward = new Vector2();

    private AimSnap() {}

    /** After AimingMode.snapAimInFrontOfPlayer. */
    public static void fix(IsoPlayer player, float zoom, Vector2 out) {
        if (player == null || out == null || zoom <= 0f || !Settings.aimSnapFix) {
            return;
        }
        int index = player.getIndex();
        if (index < 0 || index >= IsoCamera.cameras.length) {
            return;
        }
        PlayerCamera camera = IsoCamera.cameras[index];
        if (camera == null) {
            return;
        }
        Vector2 f = player.getAnimForwardDirection(forward);
        float x = player.getX() + f.x;
        float y = player.getY() + f.y;
        float z = player.getAimOriginPosZ();
        out.x = camera.XToScreenExact(x, y, z, 0) / zoom;
        out.y = camera.YToScreenExact(x, y, z, 0) / zoom;
    }
}
