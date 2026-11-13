package dev.gamepadtweaks;

import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Random;
import java.util.Set;

import me.zed_0xff.zombie_buddy.Patch;
import org.joml.Vector3f;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.IsoZombie;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.network.GameServer;
import zombie.scripting.objects.VehicleScript;
import zombie.vehicles.BaseVehicle;

// Vehicle vibration, felt by every controller player in the vehicle (see Rumble).
//
// The grip motors carry the vehicle by side: left wheels (front and rear) = left grip, right =
// right grip; impacts are panned by where they come from. The trigger motors (Xbox One / Series)
// differ in frequency and power, so they don't stand for the rear / front: they only add a
// short accent to knocks at the front (front wheel knocks, impacts and bodies ahead), never the
// continuous surface texture. rumble.triggers turns that off, rumble.triggerGain sets it; on pads
// Steam drives no trigger motors for, Rumble drops the accent into the grip of that side.
// Vehicle local space (script offsets, BaseVehicle.getLocalPos, the columns of
// jniTransform.basis) has +x to the left, +z to the front: wheel FrontLeft is at +0.36 x, +0.85 z.
//
// Patch bodies are inlined into the game classes, so they only call public static methods here
// (a private one compiles but throws IllegalAccessError in game).
//
// - crash: BaseVehicle.crash (velocity change on a physics contact), by the impact, from where
//   the velocity change comes;
// - running someone over: BaseVehicle.playSoundVehicleHitCharacter (once per body), by speed,
//   where the body is;
// - a zombie banging on the vehicle or its window: AttackVehicleState ThumpFrame plays
//   ZombieThumpVehicle / ZombieThumpVehicleWindow on the zombie with the vehicle as the proxy,
//   where the zombie is;
// - wheels (update, every frame): suspension of each wheel (wheelInfo.suspensionLength, rest
//   length and travel from the script; Bullet clamps at rest - travel cm): a quick compression
//   or drop is a knock on that wheel, reaching the end of the travel is a hard hit; a body under
//   a wheel (testCollisionWithProneCharacter sets an upward impulse per wheel) is a knock;
// - road surface under each wheel (the floor sprite, as vanilla's ParameterVehicleRoadMaterial
//   picks the tyre sound, plus plowed land): off the asphalt each wheel gets the texture of its
//   surface (grass, dirt road, gravel, sand, snow, furrows, railway sleepers), stronger and
//   denser with speed; a knock on the wheel that leaves or gets back on the road. The texture
//   fades to a third over a few seconds of continuous off-road driving, so a long dirt road
//   stays bearable, and comes back after some time on asphalt.
public final class VehicleRumble {
    private VehicleRumble() {}

    /** Same pulse for everyone in the vehicle: grip motors low / high, trigger motors lt / rt. */
    public static void all(BaseVehicle vehicle, String event, float low, float high, float lt, float rt, float ms) {
        if (vehicle == null) {
            return;
        }
        for (int seat = 0; seat < vehicle.getMaxPassengers(); seat++) {
            if (vehicle.getCharacter(seat) instanceof IsoPlayer p && p.isLocalPlayer() && p.getJoypadBind() >= 0) {
                Rumble.pulse(p.getJoypadBind(), event, low, high, lt, rt, ms);
            }
        }
    }

    /**
     * A pulse of strength k at a point of the vehicle: front, left = 0..1 (0.5 = middle).
     * floor = how much the far grip gets anyway (impacts shake the whole vehicle). accent = also
     * a trigger kick when it's at the front (knocks and impacts, not the texture).
     */
    public static void corner(BaseVehicle vehicle, String event, float k, float front, float left, float floor,
                              boolean accent, float ms) {
        float l = Math.min(1, 2 * left), r = Math.min(1, 2 * (1 - left));
        float low = k * (floor + (1 - floor) * l);
        float high = k * (floor + (1 - floor) * r);
        float lt = 0, rt = 0;
        if (accent && Settings.rumbleTriggers && front > 0.5f) {
            float t = k * Settings.rumbleTriggerGain * (2 * front - 1);
            lt = t * l;
            rt = t * r;
        }
        all(vehicle, event, low, high, lt, rt, ms);
    }

    /** A knock (accent) or texture grain on one wheel's side. */
    public static void wheel(BaseVehicle vehicle, String event, float k, VehicleScript.Wheel w, boolean accent, float ms) {
        corner(vehicle, event, k, w.offset.z > 0 ? 1 : 0, w.offset.x > 0 ? 1 : 0, 0, accent, ms);
    }

    /** {front, left} 0..1 of a world point. */
    static float[] where(BaseVehicle vehicle, float x, float y, float z) {
        Vector3f local = vehicle.getLocalPos(x, y, z, new Vector3f());
        Vector3f ext = vehicle.getScript().getExtents();
        float halfW = Math.max(0.3f, ext.x / 2), halfL = Math.max(0.5f, ext.z / 2);
        return new float[] {clamp(0.5f + 0.5f * local.z / halfL), clamp(0.5f + 0.5f * local.x / halfW)};
    }

    private static float clamp(float v) {
        return Math.max(0, Math.min(1, v));
    }

    public static boolean feels(BaseVehicle vehicle) {
        if (vehicle == null || GameServer.server || !Settings.rumble) {
            return false;
        }
        for (int seat = 0; seat < vehicle.getMaxPassengers(); seat++) {
            if (vehicle.getCharacter(seat) instanceof IsoPlayer p && p.isLocalPlayer() && p.getJoypadBind() >= 0) {
                return true;
            }
        }
        return false;
    }

    // --- Crash ----------------------------------------------------------------------------

    private static final Field LAST_VELOCITY = field(BaseVehicle.class, "lastLinearVelocity");

    // delta is 3..18 and more (BaseVehicle.update: velocity change * 3), called before the damage
    // is applied. The side: the velocity change points away from the hit (lastLinearVelocity is
    // still the velocity before the contact here).
    @Patch(className = "zombie.vehicles.BaseVehicle", methodName = "crash")
    public static class Crash {
        @Patch.OnEnter
        public static void enter(@Patch.This BaseVehicle vehicle, @Patch.Argument(0) float delta) {
            VehicleRumble.crash(vehicle, delta);
        }
    }

    public static void crash(BaseVehicle vehicle, float delta) {
        if (!feels(vehicle)) {
            return;
        }
        float k = clamp((Math.abs(delta) - 3) / 20);
        float left = 0.5f, front = 0.5f;
        try {
            Vector3f last = LAST_VELOCITY == null ? null : (Vector3f) LAST_VELOCITY.get(vehicle);
            if (last != null) {
                Vector3f dv = new Vector3f(vehicle.jniLinearVelocity).sub(last);
                dv.y = 0;
                float lx = vehicle.jniTransform.basis.getColumn(0, new Vector3f()).dot(dv);
                float lz = vehicle.jniTransform.basis.getColumn(2, new Vector3f()).dot(dv);
                float len = dv.length();
                if (len > 0.01f) {
                    // the velocity changes away from the hit: pushed right = hit on the left
                    left = clamp(0.5f - 0.5f * lx / len);
                    front = clamp(0.5f - 0.5f * lz / len);
                }
            }
        } catch (ReflectiveOperationException | RuntimeException e) {
            // the middle
        }
        corner(vehicle, "vehicle", 0.55f + 0.45f * k, front, left, 0.35f, true, 200 + 400 * k);
        if (Settings.rumbleDebugLog) {
            Log.info("rumble: crash delta=" + delta + " front=" + front + " left=" + left);
        }
    }

    // --- Running over, zombies on the vehicle ---------------------------------------------

    @Patch(className = "zombie.vehicles.BaseVehicle", methodName = "playSoundVehicleHitCharacter")
    public static class HitCharacter {
        @Patch.OnEnter
        public static void enter(@Patch.This BaseVehicle vehicle, @Patch.Argument(0) IsoGameCharacter chr) {
            VehicleRumble.hitCharacter(vehicle, chr);
        }
    }

    public static void hitCharacter(BaseVehicle vehicle, IsoGameCharacter chr) {
        if (!feels(vehicle) || chr == null) {
            return;
        }
        float k = clamp(vehicle.getCurrentAbsoluteSpeedKmHour() / 60);
        float[] at = where(vehicle, chr.getX(), chr.getY(), chr.getZ());
        corner(vehicle, "vehicle", 0.35f + 0.5f * k, at[0], at[1], 0.25f, true, 120 + 150 * k);
    }

    private static final Field EMITTER_CHARACTER = field(zombie.characters.BaseCharacterSoundEmitter.class, "character");

    // CharacterSoundEmitter.playSound has several overloads; the zombie's thump is
    // playSound(String, IsoObject proxy = the vehicle).
    @Patch(className = "zombie.characters.CharacterSoundEmitter", methodName = "playSound")
    public static class ZombieOnVehicle {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.characters.BaseCharacterSoundEmitter emitter,
                                 @Patch.AllArguments Object[] args) {
            if (args.length == 2 && args[1] instanceof BaseVehicle vehicle && args[0] instanceof String sound) {
                VehicleRumble.zombieThump(emitter, sound, vehicle);
            }
        }
    }

    public static void zombieThump(zombie.characters.BaseCharacterSoundEmitter emitter, String sound, BaseVehicle vehicle) {
        boolean window = "ZombieThumpVehicleWindow".equals(sound);
        if (!window && !"ZombieThumpVehicle".equals(sound) || !feels(vehicle)) {
            return;
        }
        float[] at = {0.5f, 0.5f};
        try {
            if (EMITTER_CHARACTER != null && EMITTER_CHARACTER.get(emitter) instanceof IsoGameCharacter chr) {
                at = where(vehicle, chr.getX(), chr.getY(), chr.getZ());
            }
        } catch (ReflectiveOperationException | RuntimeException e) {
            // the middle
        }
        corner(vehicle, "thump", window ? 0.5f : 0.4f, at[0], at[1], 0.15f, true, 160);
    }

    // --- Bodies under the wheels ------------------------------------------------------------

    private static final Field SQUISHED = field(BaseVehicle.class, "impulsesFromSquishedBodies");
    private static Field impulseEnable, impulseApplied;
    // vehicle id * 4 + wheel -> last time the wheel touched a body
    private static final Map<Long, Long> bodyContact = new HashMap<>();

    @Patch(className = "zombie.vehicles.BaseVehicle", methodName = "testCollisionWithProneCharacter")
    public static class BodyUnderWheel {
        @Patch.OnExit
        public static void exit(@Patch.This BaseVehicle vehicle, @Patch.Return int wheels) {
            if (wheels > 0) {
                VehicleRumble.bodyUnderWheel(vehicle);
            }
        }
    }

    // The wheels touching a body have a fresh impulse (enable, not applied yet). Called every
    // frame while a wheel is on the body: one bump when it gets on it.
    public static void bodyUnderWheel(BaseVehicle vehicle) {
        if (!feels(vehicle)) {
            return;
        }
        try {
            Object arr = SQUISHED == null ? null : SQUISHED.get(vehicle);
            if (arr == null) {
                return;
            }
            long now = System.currentTimeMillis();
            for (int i = 0; i < Array.getLength(arr) && i < vehicle.getScript().getWheelCount(); i++) {
                Object imp = Array.get(arr, i);
                if (imp == null) {
                    continue;
                }
                if (impulseEnable == null) {
                    impulseEnable = field(imp.getClass(), "enable");
                    impulseApplied = field(imp.getClass(), "applied");
                    if (impulseEnable == null || impulseApplied == null) {
                        return;
                    }
                }
                if (!impulseEnable.getBoolean(imp) || impulseApplied.getBoolean(imp)) {
                    continue;
                }
                long key = (long) vehicle.getId() * 4L + i;
                Long last = bodyContact.put(key, now);
                if (last == null || now - last > 300) {
                    float speed = vehicle.getCurrentAbsoluteSpeedKmHour();
                    float k = clamp(0.35f + speed / 50);
                    wheel(vehicle, "suspension", k, vehicle.getScript().getWheel(i), true, 160 + 100 * k);
                    if (Settings.rumbleDebugLog) {
                        Log.info("rumble: body under wheel " + i + " speed=" + speed);
                    }
                }
            }
        } catch (ReflectiveOperationException | RuntimeException e) {
            // ignore
        }
    }

    // --- Wheels: suspension and surface -------------------------------------------------------

    // How each surface feels. Random ones: a grain every minMs..maxMs (at 40 km/h, denser faster) of amp (x 0.5..1, sometimes a
    // rut of x rutGain), each lasting ms. Rhythmic ones (spacing > 0): a thump every spacing tiles
    // driven, so the beat follows the speed (furrows, sleepers). Each wheel on its own surface.
    private enum Surface {
        ROAD(0, 0, 0, 0, 0, 0, 0),
        // asphalt edge: grass, soft swells
        GRASS(1, 0.10f, 90, 160, 130, 0.05f, 0),
        // dirt road: uneven, now and then a rut
        DIRT(3, 0.15f, 60, 120, 100, 0.08f, 0),
        // gravel: fine fast crunch
        GRAVEL(4, 0.16f, 30, 55, 45, 0.02f, 0),
        // sand: soft drag, long smooth waves
        SAND(2, 0.09f, 160, 260, 260, 0, 0),
        // snow: barely there
        SNOW(0, 0.06f, 140, 240, 220, 0, 0),
        // plowed land, furrows across the way
        PLOWED(5, 0.30f, 0, 0, 140, 0, 0.7f),
        // railway: a clack per sleeper
        RAIL(6, 0.32f, 0, 0, 70, 0, 0.65f);

        final int priority;
        final float amp;
        final int minMs, maxMs;
        final float ms;
        final float rutChance;
        final float spacing;

        Surface(int priority, float amp, int minMs, int maxMs, float ms, float rutChance, float spacing) {
            this.priority = priority;
            this.amp = amp;
            this.minMs = minMs;
            this.maxMs = maxMs;
            this.ms = ms;
            this.rutChance = rutChance;
            this.spacing = spacing;
        }
    }

    private static final class WheelState {
        // texture timer / distance driven since the last beat
        long nextGrain;
        float distance;
        float compression = Float.NaN;
        long lastBump;
        IsoGridSquare square;
        Surface surface = Surface.ROAD;
    }

    private static final class State {
        final WheelState[] wheels = new WheelState[4];
        float offroadSeconds;
        float roadSeconds;
        long lastTime;
        // debug: per wheel min / max compression and max change per frame, logged once a second
        final float[][] stats = new float[4][3];
        long statsTime;
    }

    private static final Map<Integer, State> states = new HashMap<>();
    private static final Random random = new Random();
    private static final Vector3f tmp = new Vector3f();

    /** Every frame (Rumble.update). */
    static void update() {
        Set<Integer> seen = new HashSet<>();
        for (IsoPlayer p : IsoPlayer.players) {
            if (p == null || !p.isLocalPlayer() || p.getJoypadBind() < 0 || p.getVehicle() == null) {
                continue;
            }
            BaseVehicle vehicle = p.getVehicle();
            int id = vehicle.getId();
            if (seen.add(id)) {
                update(vehicle, states.computeIfAbsent(id, k -> new State()));
            }
        }
        states.keySet().retainAll(seen);
        if (bodyContact.size() > 64) {
            bodyContact.clear();
        }
    }

    private static void update(BaseVehicle vehicle, State st) {
        VehicleScript script = vehicle.getScript();
        if (script == null) {
            return;
        }
        long now = System.currentTimeMillis();
        float dt = st.lastTime == 0 ? 0 : Math.min(0.2f, (now - st.lastTime) / 1000f);
        st.lastTime = now;
        float speed = vehicle.getCurrentAbsoluteSpeedKmHour();
        float rest = script.getSuspensionRestLength();
        float travel = script.getSuspensionTravel() * 0.01f; // Bullet: max travel in cm
        int count = Math.min(4, script.getWheelCount());
        boolean anyOffroad = false;
        for (int i = 0; i < count; i++) {
            WheelState w = st.wheels[i] == null ? (st.wheels[i] = new WheelState()) : st.wheels[i];
            VehicleScript.Wheel sw = script.getWheel(i);

            // suspension
            float len = vehicle.wheelInfo[i].suspensionLength;
            if (len != 0 && travel > 0) {
                float c = (rest - len) / travel; // 0 = rest, 1 = end of travel, < 0 extended
                if (!Float.isNaN(w.compression)) {
                    float d = c - w.compression;
                    if (Settings.rumbleDebugLog) {
                        float[] s = st.stats[i];
                        s[0] = Math.min(s[0], c);
                        s[1] = Math.max(s[1], c);
                        s[2] = Math.max(s[2], Math.abs(d));
                    }
                    if (c >= 0.97f && w.compression < 0.97f && d > 0.1f && now - w.lastBump > 150) {
                        w.lastBump = now;
                        corner(vehicle, "suspension", 1.0f, sw.offset.z > 0 ? 1 : 0, sw.offset.x > 0 ? 1 : 0, 0.5f, true, 300);
                        if (Settings.rumbleDebugLog) {
                            Log.info("rumble: suspension bottomed out, wheel " + i + " d=" + d);
                        }
                    } else if (Math.abs(d) > BUMP_MIN && now - w.lastBump > 120) {
                        w.lastBump = now;
                        float k = clamp((Math.abs(d) - BUMP_MIN) / BUMP_RANGE) * (d > 0 ? 1 : 0.6f);
                        wheel(vehicle, "suspension", 0.2f + 0.7f * k, sw, true, 120 + 120 * k);
                    }
                }
                w.compression = c;
            }

            // surface
            vehicle.getWorldPos(sw.offset.x, sw.offset.y, sw.offset.z, tmp);
            IsoGridSquare sq = IsoWorld.instance.getCell().getGridSquare((int) Math.floor(tmp.x),
                    (int) Math.floor(tmp.y), (int) Math.floor(vehicle.getZ()));
            if (sq != w.square) {
                w.square = sq;
                Surface s = surface(sq);
                if (s != w.surface && speed > 8) {
                    boolean off = s != Surface.ROAD && w.surface == Surface.ROAD;
                    boolean on = s == Surface.ROAD && w.surface != Surface.ROAD;
                    if ((off && st.offroadSeconds < 1.5f) || on) {
                        float k = clamp(speed / 60);
                        wheel(vehicle, "road", (off ? 0.35f : 0.25f) + 0.35f * k, sw, true, 180);
                    }
                }
                w.surface = s;
            }
            if (w.surface != Surface.ROAD) {
                anyOffroad = true;
            }
        }

        // off-road texture, fading with continuous off-road time
        if (anyOffroad && speed > 5) {
            st.offroadSeconds += dt;
            st.roadSeconds = 0;
        } else if (speed > 5) {
            st.roadSeconds += dt;
            if (st.roadSeconds > 10) {
                st.offroadSeconds = 0;
            }
        }
        if (anyOffroad && speed > 5) {
            float habit = 0.33f + 0.67f * (float) Math.exp(-st.offroadSeconds / 8);
            float sp = (float) Math.pow(clamp(speed / 60), 0.7);
            for (int i = 0; i < count; i++) {
                texture(vehicle, st.wheels[i], script.getWheel(i), habit, sp, speed, dt, now);
            }
        }

        if (Settings.rumbleDebugLog && now - st.statsTime > 1000) {
            st.statsTime = now;
            StringBuilder sb = new StringBuilder("rumble: vehicle " + vehicle.getId() + " speed=" + Math.round(speed)
                    + " rest=" + rest + " travel=" + travel + " offroad=" + Math.round(st.offroadSeconds) + "s wheels:");
            for (int i = 0; i < count; i++) {
                float[] s = st.stats[i];
                WheelState w = st.wheels[i];
                sb.append(String.format(" %d[%s c=%.2f..%.2f maxd=%.3f]", i, w == null ? "?" : w.surface, s[0], s[1], s[2]));
                s[0] = Float.MAX_VALUE;
                s[1] = -Float.MAX_VALUE;
                s[2] = 0;
            }
            Log.info(sb.toString());
        }
    }

    private static final float REF_KMH = 40;

    private static void texture(BaseVehicle vehicle, WheelState side, VehicleScript.Wheel sw, float habit, float sp, float speed, float dt, long now) {
        Surface surface = side.surface;
        if (surface == Surface.ROAD) {
            side.distance = 0;
            return;
        }
        float a;
        if (surface.spacing > 0) {
            side.distance += speed / 3.6f * dt; // tiles are about a metre
            if (side.distance < surface.spacing) {
                return;
            }
            side.distance %= surface.spacing;
            a = surface.amp * habit * (0.5f + 0.5f * sp) * (0.85f + 0.15f * random.nextFloat());
        } else {
            if (now < side.nextGrain) {
                return;
            }
            // intervals are for REF_KMH: faster = denser grain (as if over the same bumps), within
            // x0.4 (fast) .. x3 (crawling) so it neither turns into a buzz nor stops
            float f = Math.max(0.4f, Math.min(3f, REF_KMH / Math.max(1, speed)));
            side.nextGrain = now + (long) (f * (surface.minMs + random.nextInt(Math.max(1, surface.maxMs - surface.minMs))));
            a = surface.amp * habit * sp * (0.5f + 0.5f * random.nextFloat());
            if (random.nextFloat() < surface.rutChance) {
                a *= 2.5f;
            }
        }
        float ms = surface.spacing > 0 ? surface.ms : surface.ms * Math.max(0.6f, Math.min(1.5f, REF_KMH / Math.max(1, speed)));
        wheel(vehicle, "road", a * 2, sw, false, ms); // texture: grips only
    }

    // A quick change of the compression (share of the travel) in one frame: smaller ones are
    // the normal ride, BUMP_MIN + BUMP_RANGE and more is a full-strength bump.
    private static final float BUMP_MIN = 0.12f;
    private static final float BUMP_RANGE = 0.5f;

    // The floor as vanilla's ParameterVehicleRoadMaterial.getMaterial sees it, for any square.
    private static Surface surface(IsoGridSquare sq) {
        if (sq == null) {
            return Surface.ROAD;
        }
        if (IsoWorld.instance.getCell().gridSquareIsSnow(sq.getX(), sq.getY(), sq.getZ())) {
            return Surface.SNOW;
        }
        IsoObject floor = sq.getFloor();
        for (int n = 0; n < sq.getObjects().size(); n++) {
            IsoObject obj = sq.getObjects().get(n);
            String name = obj == null || obj.getSprite() == null ? null : obj.getSprite().getName();
            if (name != null && name.startsWith("industry_railroad_")) {
                return Surface.RAIL;
            }
            if (name != null && name.startsWith("vegetation_farming_")) {
                return Surface.PLOWED; // furrows and crops (SPlantGlobalObject)
            }
        }
        String name = floor == null || floor.getSprite() == null ? null : floor.getSprite().getName();
        if (name == null) {
            return Surface.ROAD;
        }
        if (name.startsWith("blends_natural_01")) {
            if (name.endsWith("_5") || name.endsWith("_6") || name.endsWith("_7") || name.endsWith("_0")) {
                return Surface.SAND;
            }
            if (name.endsWith("_64") || name.endsWith("_69") || name.endsWith("_70") || name.endsWith("_71")) {
                return Surface.DIRT;
            }
            return Surface.GRASS;
        }
        if (name.endsWith("blends_street_01_48") || name.endsWith("blends_street_01_53")
                || name.endsWith("blends_street_01_54") || name.endsWith("blends_street_01_55")) {
            return Surface.GRAVEL;
        }
        return Surface.ROAD;
    }

    private static Field field(Class<?> c, String name) {
        try {
            Field f = c.getDeclaredField(name);
            f.setAccessible(true);
            return f;
        } catch (ReflectiveOperationException | RuntimeException e) {
            Log.warn("rumble: no field " + c.getSimpleName() + "." + name);
            return null;
        }
    }
}
