package dev.gamepadtweaks;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.GameSounds;
import zombie.characters.BaseCharacterSoundEmitter;
import zombie.characters.CharacterSoundEmitter;
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
    // hit reactions (also hits that clothing stopped, so no health is lost). Watched every frame
    // instead of patching each place that starts them. Names are compared in lower case.
    // Vaulting and climbing are felt by their animation sounds instead (CharacterSound below):
    // leaving the climb state comes well after the landing, so the kick read as an unrelated event.

    private record Kick(String event, float low, float high, float ms) {}

    private static final Map<String, Kick> ON_ENTER = new HashMap<>();
    private static final Kick LANDING = new Kick("fall", 0.55f, 0.35f, 250);

    static {
        ON_ENTER.put("collide", new Kick("bump", 0.75f, 0.5f, 300));
        ON_ENTER.put("bumped", new Kick("bump", 0.45f, 0.35f, 200));
        ON_ENTER.put("bumped-bump", new Kick("bump", 0.45f, 0.35f, 200));
        // the start of a fall; the body hitting the ground is its sound (FALL_SOUNDS)
        ON_ENTER.put("knockeddown", new Kick("fall", 0.6f, 0.4f, 250));
        ON_ENTER.put("falldown", new Kick("fall", 0.5f, 0.35f, 220));
        ON_ENTER.put("hitreaction", new Kick("damage", 0.45f, 0.4f, 180));
        ON_ENTER.put("hitreaction-hit", new Kick("damage", 0.45f, 0.4f, 180));
        ON_ENTER.put("hitreaction-shot", new Kick("damage", 0.6f, 0.5f, 220));
        ON_ENTER.put("hitreactionpvp", new Kick("damage", 0.45f, 0.4f, 180));
        ON_ENTER.put("hitreaction-bite", new Kick("damage", 0.8f, 0.6f, 350));
        ON_ENTER.put("hitreaction-bitegeneric", new Kick("damage", 0.8f, 0.6f, 350));
        ON_ENTER.put("hitreaction-crawlerbite", new Kick("damage", 0.8f, 0.6f, 350));
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
                pendingVoice[i] = null;
                lastStates.remove(i);
                continue;
            }
            updateRespiratorySound(i, player);
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

    // A zombie banging on a door, window, barricade, wall or fence near the player:
    // ThumpState.execute bumps the zombie's thump counter once per hit (and resets it to 0 on
    // other occasions). Only the first knocks are felt, the surprise: a crowd banging on a fence
    // the player already sees and fights shook the controller for no reason. Felt again after
    // THUMP_QUIET_MS without any knock near that player.
    @Patch(className = "zombie.characters.IsoGameCharacter", methodName = "setTimeThumping")
    public static class Thump {
        @Patch.OnEnter
        public static void enter(@Patch.This IsoGameCharacter chr, @Patch.Argument(0) int count) {
            if (count == 0 || GameServer.server || !Settings.rumble || !(chr instanceof IsoZombie)) {
                return;
            }
            if (chr.getThumpTarget() instanceof IsoObject target) {
                RumbleEvents.thump(target.getSquare());
            }
        }
    }

    private static final long THUMP_QUIET_MS = 15000;
    private static final int THUMP_FELT = 2;
    // per player: the last knock heard and how many of the current series were felt
    private static final long[] thumpLast = new long[4];
    private static final int[] thumpCount = new int[4];

    public static void thump(IsoGridSquare sq) {
        if (sq == null) {
            return;
        }
        long now = System.currentTimeMillis();
        for (int i = 0; i < IsoPlayer.players.length && i < 4; i++) {
            IsoPlayer p = IsoPlayer.players[i];
            if (p == null || !p.isLocalPlayer() || p.getJoypadBind() < 0 || p.isDead() || p.getZ() != sq.getZ()) {
                continue;
            }
            float dx = p.getX() - (sq.getX() + 0.5f);
            float dy = p.getY() - (sq.getY() + 0.5f);
            float d = (float) Math.sqrt(dx * dx + dy * dy);
            if (d >= 4) {
                continue;
            }
            if (now - thumpLast[i] > THUMP_QUIET_MS) {
                thumpCount[i] = 0;
            }
            thumpLast[i] = now;
            if (thumpCount[i] >= THUMP_FELT) {
                continue;
            }
            float k = (1 - 0.7f * d / 4) * (thumpCount[i] == 0 ? 1 : 0.6f);
            thumpCount[i]++;
            Rumble.pulse(p.getJoypadBind(), "thump", 0.45f * k, 0.2f * k, 0, 170);
        }
    }

    // --- Jump scare ---------------------------------------------------------------------

    // The sting when a zombie shows up right next to the player out of nowhere: IsoPlayer.updateLOS
    // plays "ZombieSurprisedPlayer" (very close zombie, none seen before, not within 600 ticks of the
    // last one) at the "jump scare volume" option, so the kick follows that option too (0 = none).
    // Also the player's animation sounds (anim events PlaySound, PlayFenceSound, PlayTripSound
    // all end in playSoundImpl), which fall exactly on the moment in the animation: hands on the
    // fence or window frame, the landing on the other side, tripping, the body hitting the ground.
    @Patch(className = "zombie.characters.CharacterSoundEmitter", methodName = "playSoundImpl")
    public static class CharacterSound {
        @Patch.OnEnter
        public static void enter(@Patch.This BaseCharacterSoundEmitter emitter, @Patch.Argument(0) String sound) {
            if (sound == null || GameServer.server || !Settings.rumble) {
                return;
            }
            if ("ZombieSurprisedPlayer".equals(sound)) {
                RumbleEvents.scare(emitter);
            } else {
                RumbleEvents.bodySound(emitter, sound);
            }
        }
    }

    // media/AnimSets/player: climbfence, climbwindow, climbwall, falldown, knockeddown
    private static final Map<String, Kick> BODY_SOUNDS = new HashMap<>();

    static {
        // hands on the fence / window frame / wall: a light kick that announces the landing
        BODY_SOUNDS.put("ClimbOverFenceLow", new Kick("fall", 0.22f, 0.2f, 90));
        BODY_SOUNDS.put("ClimbThroughWindow", new Kick("fall", 0.22f, 0.2f, 90));
        BODY_SOUNDS.put("ClimbOverFenceHighStart", new Kick("fall", 0.25f, 0.2f, 100));
        BODY_SOUNDS.put("ClimbOverFenceHighStruggle", new Kick("fall", 0.2f, 0.15f, 90));
        BODY_SOUNDS.put("ClimbOverFenceHighSuccess", new Kick("fall", 0.25f, 0.2f, 100));
        BODY_SOUNDS.put("ClimbOverFenceHighFail", new Kick("fall", 0.45f, 0.3f, 200));
        // feet on the ground
        BODY_SOUNDS.put("LandLight", new Kick("fall", 0.5f, 0.3f, 170));
        BODY_SOUNDS.put("LandHeavy", new Kick("fall", 0.7f, 0.4f, 230));
        // tripping over the fence while vaulting, then the fall
        BODY_SOUNDS.put("TripOverObstacle", new Kick("fall", 0.75f, 0.55f, 220));
        BODY_SOUNDS.put("FallLight", new Kick("fall", 0.8f, 0.5f, 300));
        BODY_SOUNDS.put("FallHeavy", new Kick("fall", 1.0f, 0.6f, 400));
        BODY_SOUNDS.put("BodyHitGround", new Kick("fall", 0.9f, 0.55f, 350));
    }

    public static void bodySound(BaseCharacterSoundEmitter emitter, String sound) {
        Kick k = BODY_SOUNDS.get(sound);
        if (k == null) {
            return;
        }
        for (IsoPlayer p : IsoPlayer.players) {
            if (p != null && p.isLocalPlayer() && p.getJoypadBind() >= 0 && p.getEmitter() == emitter) {
                if (Settings.rumbleDebugLog) {
                    Log.info("rumble: player sound " + sound);
                }
                kick(p, k);
            }
        }
    }

    // --- Wounds ---------------------------------------------------------------------------

    // A zombie's scratch, laceration or bite that got through the clothes:
    // BodyDamage.AddRandomDamageFromZombie plays the pain voice right then (also on an MP client,
    // before it sends the hit). A sharp kick plus a high, slowly fading sting (the two pulses mix
    // by maximum). Health loss alone was easy to miss: the moodles were the only sign. The pain
    // pulsations that follow (Rumble.lua, GamepadTweaks_rumbleSinceWound) are not a heartbeat:
    // they keep the wound felt after the sting, with no vanilla sound to follow.
    @Patch(className = "zombie.characters.IsoPlayer", methodName = "playerVoiceSound")
    public static class PlayerVoice {
        @Patch.OnEnter
        public static void enter(@Patch.This IsoPlayer player, @Patch.Argument(0) String sound) {
            if (sound != null && sound.startsWith("PainFrom") && !GameServer.server && Settings.rumble) {
                RumbleEvents.wound(player, sound);
            }
        }

        @Patch.OnExit
        public static void exit(@Patch.This IsoPlayer player, @Patch.Argument(0) String sound,
                                @Patch.Return long instance) {
            if (instance != 0 && !GameServer.server && Settings.rumble) {
                RumbleEvents.queueRespiratorySound(player, sound, instance);
            }
        }
    }

    private record PendingVoice(IsoPlayer player, long instance, Kick kick, String sound, long queuedAt) {}

    private static final PendingVoice[] pendingVoice = new PendingVoice[IsoPlayer.players.length];
    // The bank starts the four vocal events with 0.29–0.40 s of silence, depending on the voice.
    private static final float VOICE_ONSET_PEAK = 0.001f;
    private static FmodEventMeter voiceMeter;
    private static boolean voiceMeterFailed;

    public static void queueRespiratorySound(IsoPlayer player, String sound, long instance) {
        if (sound == null || voiceMeterFailed || !player.isLocalPlayer() || player.getJoypadBind() < 0) {
            return;
        }
        Kick kick = switch (sound) {
            case "SneezeHeavy" -> new Kick("cough", 0.30f, 0.60f, 150);
            case "SneezeLight" -> new Kick("cough", 0.14f, 0.32f, 110);
            case "Cough" -> new Kick("cough", 0.52f, 0.30f, 220);
            case "MuffledCough" -> new Kick("cough", 0.27f, 0.15f, 150);
            default -> null;
        };
        if (kick != null && player.getEmitter() instanceof CharacterSoundEmitter) {
            int slot = Rumble.playerOf(player.getJoypadBind());
            if (slot >= 0) {
                pendingVoice[slot] = new PendingVoice(player, instance, kick, sound, System.currentTimeMillis());
            }
        }
    }

    private static void updateRespiratorySound(int slot, IsoPlayer player) {
        PendingVoice voice = pendingVoice[slot];
        if (voice == null) {
            return;
        }
        if (voiceMeterFailed || voice.player() != player || !player.getEmitter().isPlaying(voice.instance())) {
            pendingVoice[slot] = null;
            return;
        }
        if (GameSounds.soundIsPaused) {
            return;
        }
        try {
            if (voiceMeter == null) voiceMeter = new FmodEventMeter(pendingVoice.length);
            if (voiceMeter.peak(voice.instance(), slot) < VOICE_ONSET_PEAK) {
                return;
            }
        } catch (Throwable e) {
            pendingVoice[slot] = null;
            voiceMeterFailed = true;
            Log.error("rumble: cough and sneeze meter unavailable", e);
            return;
        }
        pendingVoice[slot] = null;
        if (Settings.rumbleDebugLog) {
            Log.info("rumble: " + voice.sound() + " onset after " + (System.currentTimeMillis() - voice.queuedAt()) + "ms");
        }
        kick(player, voice.kick());
    }

    // player index -> time and kind of the last wound (1 scratch / cut, 2 bite)
    private static final long[] woundTime = new long[4];
    private static final int[] woundKind = new int[4];

    public static void wound(IsoPlayer player, String sound) {
        if (!player.isLocalPlayer() || player.getJoypadBind() < 0) {
            return;
        }
        int c = player.getJoypadBind();
        int kind;
        switch (sound) {
            case "PainFromScratch" -> {
                Rumble.pulse(c, "damage", 0.55f, 0.85f, 0, 110);
                Rumble.pulse(c, "damage", 0, 0.35f, 0, 650);
                kind = 1;
            }
            case "PainFromLacerate", "PainFromGlassCut" -> {
                Rumble.pulse(c, "damage", 0.7f, 0.95f, 0, 150);
                Rumble.pulse(c, "damage", 0.1f, 0.45f, 0, 1000);
                kind = 1;
            }
            case "PainFromBite" -> {
                Rumble.pulse(c, "damage", 1.0f, 0.9f, 0, 260);
                Rumble.pulse(c, "damage", 0.3f, 0.6f, 0, 1500);
                kind = 2;
            }
            default -> {
                return; // falls: their own kicks
            }
        }
        int i = Rumble.playerOf(c);
        if (i >= 0 && i < 4) {
            woundTime[i] = System.currentTimeMillis();
            woundKind[i] = kind;
        }
        if (Settings.rumbleDebugLog) {
            Log.info("rumble: wound " + sound + " player " + i);
        }
    }

    /** Milliseconds since the last wound of a local player (0..3), negative = a bite, 0 = none. */
    @se.krka.kahlua.integration.annotations.LuaMethod(name = "GamepadTweaks_rumbleSinceWound", global = true)
    public static double sinceWound(double player) {
        int i = (int) player;
        if (i < 0 || i >= 4 || woundTime[i] == 0) {
            return 0;
        }
        double ms = Math.max(1, System.currentTimeMillis() - woundTime[i]);
        return woundKind[i] == 2 ? -ms : ms;
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
