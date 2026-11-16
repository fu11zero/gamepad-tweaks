package dev.gamepadtweaks;

import java.util.ArrayList;

import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.characters.ContextualAction;
import zombie.characters.IsoPlayer;
import zombie.iso.IsoDirections;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.objects.IsoDoor;
import zombie.iso.objects.IsoThumpable;

// What the Interact button (A) picks in the world, for gamepad players.
//
// Vanilla: IsoPlayer.updateUseKey polls Interact and on release (or after 0.5 s held) calls
// doContext. doContext collects contextual actions in the facing direction (doContextNSWE,
// for a diagonal facing both cardinal sides, ordered by where the player stands in the tile),
// then doors / windows / window frames on the opposite sides ("behind"), and
// pickBestContextualAction takes the highest priority. Doors and windows are 100, furniture,
// animals and hutches 90, and a behind action wins over a front one with a lower priority.
// So a window behind the player opens instead of the sofa in front, and with nothing in
// front the window behind opens anyway. The Lua prompt (ISButtonPrompt
// getBestInteractButtonAction / getBestClimbThroughButtonAction) also offers it.
// The behind check exists for closing a door after walking through it (A to open it, A again
// to close it behind, e.g. running from zombies).
//
// - behind: getContextDoorOrWindowOrWindowFrame returns nothing for a side the player faces
//   away from, except an open door, so behind only closes a door. That door is used when
//   nothing is in front, or before anything in front when the player came through it less than
//   RECENT_MS ago (the door it just opened while running).
// - facing: among the front actions the one on the side closest to the facing wins,
//   priority only breaks ties (for a diagonal facing, vanilla takes the window on one side
//   over the sofa on the side the player actually faces more).
// - cursor: a press of Interact that started while the player has a world cursor (place /
//   pick up furniture, chop, disassemble, build: IsoCell.getDrag) belongs to the cursor.
//   The cursor takes it on press (JoyPadSetup onPressButtonNoFocus -> drag), but the
//   character still runs doContext on release and sits on the sofa or opens the window
//   next to the cursor.
// - prompt: the Lua prompt runs its own handlers on press (light switch, stove, radio, crafting
//   entity), the Java poll its contextual action on release, so a lamp next to a door toggled
//   and the door opened. A press the prompt handled skips doContext (InteractPrompt.lua).
public final class InteractTarget {
    private static final int MAX_PLAYERS = 4;
    private static final long RECENT_MS = 3000;
    private static final boolean[] pressConsumed = new boolean[MAX_PLAYERS];
    private static final IsoGridSquare[] lastSquare = new IsoGridSquare[MAX_PLAYERS];
    private static final IsoGridSquare[] prevSquare = new IsoGridSquare[MAX_PLAYERS];
    private static final long[] squareChangedAt = new long[MAX_PLAYERS];

    private InteractTarget() {}

    private static boolean gamepad(IsoPlayer player) {
        return player != null && player.getJoypadBind() != -1;
    }

    private static int slot(IsoPlayer player) {
        int n = player == null ? -1 : player.getPlayerNum();
        return n >= 0 && n < MAX_PLAYERS ? n : -1;
    }

    private static boolean hasCursor(IsoPlayer player) {
        try {
            KahluaTable drag = IsoWorld.instance.currentCell.getDrag(player.getPlayerNum());
            return drag != null;
        } catch (RuntimeException e) {
            return false;
        }
    }

    private static boolean isOpenDoor(IsoObject obj) {
        if (obj instanceof IsoDoor door) {
            return door.IsOpen() && !door.isDestroyed();
        }
        return obj instanceof IsoThumpable t && t.isDoor() && t.IsOpen();
    }

    private static boolean behind(IsoPlayer player, IsoDirections side) {
        IsoDirections facing = player.getForwardIsoDirection();
        return facing != null && side != null && side.dx() * facing.dx() + side.dy() * facing.dy() < 0;
    }

    /** The player stepped onto its square from the side {@code side} less than RECENT_MS ago. */
    private static boolean cameFrom(IsoPlayer player, IsoDirections side) {
        int n = slot(player);
        if (n < 0 || side == null || System.currentTimeMillis() - squareChangedAt[n] > RECENT_MS) {
            return false;
        }
        IsoGridSquare cur = player.getCurrentSquare();
        IsoGridSquare prev = prevSquare[n];
        return cur != null && prev != null && cur == lastSquare[n] && prev.getZ() == cur.getZ()
                && prev.getX() - cur.getX() == side.dx() && prev.getY() - cur.getY() == side.dy();
    }

    /** IsoPlayer.updateUseKey, on enter (every frame): square history, a press on a cursor. */
    public static void beforeUseKey(IsoPlayer player) {
        int n = slot(player);
        if (n < 0) {
            return;
        }
        IsoGridSquare sq = player.getCurrentSquare();
        if (sq != null && sq != lastSquare[n]) {
            prevSquare[n] = lastSquare[n];
            lastSquare[n] = sq;
            squareChangedAt[n] = System.currentTimeMillis();
        }
        if (gamepad(player) && Settings.interactCursor && player.isInteractButtonDown() && hasCursor(player)) {
            pressConsumed[n] = true;
        }
    }

    /** The Lua prompt handled this press of Interact: no contextual action on its release. */
    @LuaMethod(name = "GamepadTweaks_interactHandled", global = true)
    public static void luaHandled(double playerNum) {
        int n = (int) playerNum;
        if (Settings.interactCursor && n >= 0 && n < MAX_PLAYERS) {
            pressConsumed[n] = true;
        }
    }

    /**
     * The side of the open door behind the player that it came through just now, or nil:
     * the prompt shows closing it first, as doContext does (InteractPrompt.lua).
     */
    @LuaMethod(name = "GamepadTweaks_interactRecentDoor", global = true)
    public static IsoDirections luaRecentDoor(IsoPlayer player) {
        if (!gamepad(player) || !Settings.interactNotBehind) {
            return null;
        }
        for (IsoDirections side : new IsoDirections[] {IsoDirections.N, IsoDirections.S, IsoDirections.W, IsoDirections.E}) {
            if (behind(player, side) && cameFrom(player, side)
                    && isOpenDoor(player.getContextDoorOrWindowOrWindowFrame(side))) {
                return side;
            }
        }
        return null;
    }

    /** IsoPlayer.updateUseKey, on exit: the press is over once the button is up. */
    public static void afterUseKey(IsoPlayer player) {
        int n = slot(player);
        if (n >= 0 && !player.isInteractButtonDown()) {
            pressConsumed[n] = false;
        }
    }

    /** IsoPlayer.doContext, on enter: true skips it (the press belonged to the cursor). */
    public static boolean skipContext(IsoPlayer player) {
        if (!gamepad(player) || !Settings.interactCursor) {
            return false;
        }
        int n = slot(player);
        boolean skip = (n >= 0 && pressConsumed[n]) || hasCursor(player);
        if (skip && Settings.interactDebugLog) {
            Log.info("interact: press belonged to the cursor or the prompt, no contextual action");
        }
        return skip;
    }

    /** IsoPlayer.getContextDoorOrWindowOrWindowFrame, on exit: behind, only an open door. */
    public static IsoObject filterBehind(IsoPlayer player, IsoDirections side, IsoObject found) {
        if (found == null || !gamepad(player) || !Settings.interactNotBehind || !behind(player, side)) {
            return found;
        }
        return isOpenDoor(found) ? found : null;
    }

    /** IsoPlayer.pickBestContextualAction, on exit. */
    public static ContextualAction pick(IsoPlayer player, ArrayList<ContextualAction> actions,
                                        ContextualAction vanilla) {
        boolean notBehind = Settings.interactNotBehind;
        boolean facing = Settings.interactFacing;
        if (!gamepad(player) || actions == null || actions.isEmpty() || (!notBehind && !facing)) {
            return vanilla;
        }
        float fx = player.getForwardDirectionX();
        float fy = player.getForwardDirectionY();
        float len = (float) Math.sqrt(fx * fx + fy * fy);
        if (len < 1e-4f) {
            facing = false;
        } else {
            fx /= len;
            fy /= len;
        }
        ContextualAction front = null;
        ContextualAction back = null;
        float frontDot = 0f;
        for (ContextualAction ca : actions) {
            if (ca == null) {
                continue;
            }
            if (ca.behind) {
                if (back == null || ca.priority > back.priority) {
                    back = ca;
                }
                continue;
            }
            if (!facing) {
                if (front == null || ca.priority > front.priority) {
                    front = ca;
                }
                continue;
            }
            // No side (actions filled by a callback): count as straight ahead.
            float dot = ca.dir == null ? 1f : (ca.dir.dx() * fx + ca.dir.dy() * fy)
                    / (float) Math.sqrt(ca.dir.dx() * ca.dir.dx() + ca.dir.dy() * ca.dir.dy());
            if (front == null || dot > frontDot + 0.05f
                    || (dot > frontDot - 0.05f && ca.priority > front.priority)) {
                front = ca;
                frontDot = dot;
            }
        }
        ContextualAction best;
        if (!notBehind) {
            best = front == null || (back != null && back.priority > front.priority) ? back : front;
        } else if (back != null && (front == null || cameFrom(player, back.dir))) {
            best = back;
        } else {
            best = front;
        }
        if (best == null) {
            best = vanilla;
        }
        if (best != vanilla && Settings.interactDebugLog) {
            Log.info("interact: " + best.action + " " + best.dir + (best.behind ? " (behind)" : "")
                    + " instead of " + (vanilla == null ? "none" : vanilla.action + " " + vanilla.dir));
        }
        return best;
    }
}
