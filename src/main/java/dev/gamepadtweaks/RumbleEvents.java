package dev.gamepadtweaks;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.BaseCharacterSoundEmitter;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.characters.action.ActionContext;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.objects.IsoWindow;
import zombie.core.Core;
import zombie.network.GameServer;

// Vibration events that Lua can't see (see Rumble for the output, Rumble.lua for the rest).
public final class RumbleEvents {
    private RumbleEvents() {}

    // --- Character states ---------------------------------------------------------------
    // The player's action states (media/actiongroups/player/<state>) tell what the body does:
    // running into a wall (collide), being pushed (bumped), knocked down, falling and landing,
    // hit reactions (also hits that clothing stopped, so no health is lost), landing after
    // vaulting a fence or climbing a wall or window (leaving the state). Watched every frame
    // instead of patching each place that starts them. Names are compared in lower case.

    private record Kick(String event, float low, float high, float ms) {}

    private static final Map<String, Kick> ON_ENTER = new HashMap<>();
    private static final Map<String, Kick> ON_EXIT = new HashMap<>();
    private static final Kick LANDING = new Kick("fall", 0.55f, 0.35f, 250);

    static {
        ON_ENTER.put("collide", new Kick("bump", 0.75f, 0.5f, 300));
        ON_ENTER.put("bumped", new Kick("bump", 0.45f, 0.35f, 200));
        ON_ENTER.put("bumped-bump", new Kick("bump", 0.45f, 0.35f, 200));
        ON_ENTER.put("knockeddown", new Kick("fall", 0.9f, 0.6f, 450));
        ON_ENTER.put("falldown", new Kick("fall", 0.7f, 0.45f, 350));
        ON_ENTER.put("hitreaction", new Kick("damage", 0.45f, 0.4f, 180));
        ON_ENTER.put("hitreaction-hit", new Kick("damage", 0.45f, 0.4f, 180));
        ON_ENTER.put("hitreaction-shot", new Kick("damage", 0.6f, 0.5f, 220));
        ON_ENTER.put("hitreactionpvp", new Kick("damage", 0.45f, 0.4f, 180));
        ON_ENTER.put("hitreaction-bite", new Kick("damage", 0.8f, 0.6f, 350));
        ON_ENTER.put("hitreaction-bitegeneric", new Kick("damage", 0.8f, 0.6f, 350));
        ON_ENTER.put("hitreaction-crawlerbite", new Kick("damage", 0.8f, 0.6f, 350));
        ON_EXIT.put("climbfence", new Kick("fall", 0.45f, 0.3f, 200));
        ON_EXIT.put("climbwall", new Kick("fall", 0.5f, 0.35f, 220));
        ON_EXIT.put("climbwindow", new Kick("fall", 0.35f, 0.25f, 180));
        // Window opening: IsoWindow.ToggleWindow below, when it actually opens (a stuck window
        // takes several tries in the forceopenwindow state).
    }

    // player index -> state names (root and sub-states) of the last frame
    private static final Map<Integer, Set<String>> lastStates = new HashMap<>();

    static void update() {
        VehicleRumble.update();
        for (int i = 0; i < IsoPlayer.players.length; i++) {
            IsoPlayer player = IsoPlayer.players[i];
            if (player == null || !player.isLocalPlayer() || player.getJoypadBind() < 0 || player.isDead()) {
                lastStates.remove(i);
                continue;
            }
            Set<String> now = states(player.getActionContext());
            Set<String> before = lastStates.put(i, now);
            if (before == null) {
                continue;
            }
            for (String s : now) {
                if (!before.contains(s)) {
                    if (Settings.rumbleDebugLog) {
                        Log.info("rumble: player " + i + " state " + s);
                    }
                    Kick k = ON_ENTER.get(s);
                    if (k != null) {
                        kick(player, k);
                    }
                }
            }
            for (String s : before) {
                if (!now.contains(s)) {
                    Kick k = ON_EXIT.get(s);
                    if (k != null && !now.contains("death") && !now.contains("falling")) {
                        kick(player, k);
                    }
                }
            }
            if (before.contains("falling") && !now.contains("falling") && !now.contains("death")) {
                kick(player, LANDING);
            }
        }
    }

    private static Set<String> states(ActionContext ctx) {
        Set<String> names = new HashSet<>();
        if (ctx == null) {
            return names;
        }
        String root = ctx.getCurrentStateName();
        if (root != null) {
            names.add(root.toLowerCase(java.util.Locale.ROOT));
        }
        int count = childCount(ctx);
        for (int i = 0; i < count; i++) {
            zombie.characters.action.ActionState child = ctx.getChildStateAt(i);
            if (child != null) {
                names.add(child.getName().toLowerCase(java.util.Locale.ROOT));
            }
        }
        return names;
    }

    // The number of sub-states: childStateCount() in 42.22, getChildStates().size() in 42.21
    // (getChildStateAt is in both and throws past the end).
    private static final java.lang.reflect.Method CHILD_COUNT = findChildCount();

    private static java.lang.reflect.Method findChildCount() {
        for (String name : new String[] {"childStateCount", "getChildStates"}) {
            try {
                return ActionContext.class.getMethod(name);
            } catch (NoSuchMethodException e) {
                // try the next one
            }
        }
        Log.warn("rumble: no sub-state count in ActionContext, sub-states not watched");
        return null;
    }

    private static int childCount(ActionContext ctx) {
        if (CHILD_COUNT == null) {
            return 0;
        }
        try {
            Object r = CHILD_COUNT.invoke(ctx);
            return r instanceof Integer n ? n : r instanceof java.util.List<?> l ? l.size() : 0;
        } catch (ReflectiveOperationException e) {
            return 0;
        }
    }

    private static void kick(IsoPlayer player, Kick k) {
        Rumble.pulse(player.getJoypadBind(), k.event(), k.low(), k.high(), 0, k.ms());
    }

    // Vehicles: VehicleRumble.

    // --- Windows and doors --------------------------------------------------------------

    /** A pulse for local controller players within range tiles of a square, weaker further away. */
    public static void near(IsoGridSquare sq, float range, String event, float low, float high, float ms) {
        if (sq == null) {
            return;
        }
        for (IsoPlayer p : IsoPlayer.players) {
            if (p == null || !p.isLocalPlayer() || p.getJoypadBind() < 0 || p.isDead() || p.getZ() != sq.getZ()) {
                continue;
            }
            float dx = p.getX() - (sq.getX() + 0.5f);
            float dy = p.getY() - (sq.getY() + 0.5f);
            float d = (float) Math.sqrt(dx * dx + dy * dy);
            if (d < range) {
                float k = 1 - 0.7f * d / range;
                Rumble.pulse(p.getJoypadBind(), event, low * k, high * k, 0, ms);
            }
        }
    }

    // Glass breaking next to the player: their own smash, a zombie or a shot. smashWindow has 3
    // overloads calling each other, so this runs up to 3 times at once; pulses mix by maximum.
    @Patch(className = "zombie.iso.objects.IsoWindow", methodName = "smashWindow")
    public static class SmashWindow {
        @Patch.OnEnter
        public static void enter(@Patch.This IsoWindow window) {
            if (GameServer.server || !Settings.rumble || window.isDestroyed()) {
                return;
            }
            near(window.getSquare(), 3, "window", 0.35f, 0.85f, 200);
        }
    }

    // The window actually opens or closes (vanilla ToggleWindow, at the end of the open / close
    // animation; a stuck window only after the try that succeeds), for the player who did it.
    @Patch(className = "zombie.iso.objects.IsoWindow", methodName = "ToggleWindow")
    public static class ToggleWindow {
        // the state before the call (main thread only, ToggleWindow doesn't recurse)
        public static boolean wasOpen;

        @Patch.OnEnter
        public static void enter(@Patch.This IsoWindow window) {
            ToggleWindow.wasOpen = window.IsOpen();
        }

        @Patch.OnExit
        public static void exit(@Patch.This IsoWindow window, @Patch.Argument(0) IsoGameCharacter chr) {
            if (GameServer.server || !Settings.rumble || window.IsOpen() == ToggleWindow.wasOpen) {
                return;
            }
            if (chr instanceof IsoPlayer p && p.isLocalPlayer() && p.getJoypadBind() >= 0) {
                if (window.IsOpen()) {
                    Rumble.pulse(p.getJoypadBind(), "window", 0.3f, 0.35f, 0, 160);
                } else {
                    Rumble.pulse(p.getJoypadBind(), "window", 0.2f, 0.3f, 0, 120);
                }
            }
        }
    }

    // A zombie banging on a door, window, barricade or wall near the player: ThumpState.execute
    // bumps the zombie's thump counter once per hit (and resets it to 0 on other occasions).
    @Patch(className = "zombie.characters.IsoGameCharacter", methodName = "setTimeThumping")
    public static class Thump {
        @Patch.OnEnter
        public static void enter(@Patch.This IsoGameCharacter chr, @Patch.Argument(0) int count) {
            if (count == 0 || GameServer.server || !Settings.rumble || !(chr instanceof IsoZombie)) {
                return;
            }
            if (chr.getThumpTarget() instanceof IsoObject target) {
                near(target.getSquare(), 4, "thump", 0.35f, 0.15f, 150);
            }
        }
    }

    // --- Jump scare ---------------------------------------------------------------------

    // The sting when a zombie shows up right next to the player out of nowhere: IsoPlayer.updateLOS
    // plays "ZombieSurprisedPlayer" (very close zombie, none seen before, not within 600 ticks of the
    // last one) at the "jump scare volume" option, so the kick follows that option too (0 = none).
    @Patch(className = "zombie.characters.CharacterSoundEmitter", methodName = "playSoundImpl")
    public static class JumpScare {
        @Patch.OnEnter
        public static void enter(@Patch.This BaseCharacterSoundEmitter emitter, @Patch.Argument(0) String sound) {
            if (!"ZombieSurprisedPlayer".equals(sound) || GameServer.server || !Settings.rumble) {
                return;
            }
            scare(emitter);
        }
    }

    public static void scare(BaseCharacterSoundEmitter emitter) {
        float volume = Core.getInstance().getOptionJumpScareVolume() / 10.0f;
        if (volume <= 0) {
            return;
        }
        for (IsoPlayer p : IsoPlayer.players) {
            if (p != null && p.isLocalPlayer() && p.getJoypadBind() >= 0 && p.getEmitter() == emitter) {
                float k = Math.min(1, 0.5f + 0.5f * volume);
                Rumble.pulse(p.getJoypadBind(), "scare", k, 0.8f * k, 0, 500);
            }
        }
    }
}
