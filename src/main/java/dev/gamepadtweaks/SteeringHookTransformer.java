package dev.gamepadtweaks;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Field;
import java.security.ProtectionDomain;

import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;

// Hands the wheel angle in CarController.update() over to Steering:
//
//     update() {
//         Steering.beginUpdate(this);                 // inserted: remember last frame's angle
//         ...
//         vanilla: move vehicleSteering towards the stick
//         this.vehicleSteering = Steering.wheel(this); // inserted
//         float steeringClamp = script.getSteeringClamp(this.speed);
//         ...
//     }
//
// Steering.wheel() returns the vanilla value unless a gamepad drives the car.
// ZombieBuddy advice can't insert code in the middle of a method, so this is a
// plain ASM transformer on top of ZombieBuddy's Instrumentation.
public final class SteeringHookTransformer implements ClassFileTransformer {
    private static final String TARGET = "zombie/core/physics/CarController";
    private static final String TARGET_DOTTED = TARGET.replace('/', '.');
    private static final String HOOKS = "dev/gamepadtweaks/Steering";

    private SteeringHookTransformer() {}

    public static void install() {
        Instrumentation inst = zombieBuddyInstrumentation();
        if (inst == null) {
            return;
        }
        inst.addTransformer(new SteeringHookTransformer(), true);
        for (Class<?> c : inst.getAllLoadedClasses()) {
            if (c.getName().equals(TARGET_DOTTED)) {
                try {
                    inst.retransformClasses(c);
                } catch (Exception e) {
                    Log.error("retransform " + TARGET_DOTTED + " failed", e);
                }
            }
        }
    }

    // ZombieBuddy keeps the agent Instrumentation in a package-private static field.
    private static Instrumentation zombieBuddyInstrumentation() {
        try {
            Class<?> loader = Class.forName("me.zed_0xff.zombie_buddy.Loader");
            Field f = loader.getDeclaredField("g_instrumentation");
            f.setAccessible(true);
            Instrumentation inst = (Instrumentation) f.get(null);
            if (inst == null) {
                Log.warn("ZombieBuddy Instrumentation is null, steering stays vanilla");
            }
            return inst;
        } catch (ReflectiveOperationException e) {
            Log.error("can't get ZombieBuddy Instrumentation, steering stays vanilla", e);
            return null;
        }
    }

    @Override
    public byte[] transform(Module module, ClassLoader loader, String className, Class<?> redefined,
                            ProtectionDomain domain, byte[] bytes) {
        if (!TARGET.equals(className)) {
            return null;
        }
        try {
            ClassReader reader = new ClassReader(bytes);
            // COMPUTE_MAXS: the hook needs two more stack slots. Frames stay as they
            // are: the inserted code is straight-line and leaves the stack unchanged.
            ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
            int[] hooked = {0};
            reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
                @Override
                public MethodVisitor visitMethod(int access, String name, String desc, String sig, String[] ex) {
                    MethodVisitor mv = super.visitMethod(access, name, desc, sig, ex);
                    if (name.equals("update") && desc.equals("()V")) {
                        return new UpdateHooks(mv, hooked);
                    }
                    return mv;
                }
            }, 0);
            if (hooked[0] != 1) {
                Log.warn("expected 1 getSteeringClamp call in CarController.update, found "
                        + hooked[0] + " (game updated?). Steering stays vanilla");
                return null;
            }
            Log.info("steering hooked");
            return writer.toByteArray();
        } catch (Throwable t) {
            Log.error("transform " + TARGET_DOTTED + " failed", t);
            return null;
        }
    }

    private static final class UpdateHooks extends MethodVisitor {
        private final int[] hooked;

        UpdateHooks(MethodVisitor mv, int[] hooked) {
            super(Opcodes.ASM9, mv);
            this.hooked = hooked;
        }

        @Override
        public void visitCode() {
            super.visitCode();
            super.visitVarInsn(Opcodes.ALOAD, 0);
            super.visitMethodInsn(Opcodes.INVOKESTATIC, HOOKS, "beginUpdate",
                    "(L" + TARGET + ";)V", false);
        }

        // Before `script.getSteeringClamp(this.speed)` (operands already on the stack):
        //     this.vehicleSteering = Steering.wheel(this);
        @Override
        public void visitMethodInsn(int opcode, String owner, String name, String desc, boolean itf) {
            if (opcode == Opcodes.INVOKEVIRTUAL
                    && owner.equals("zombie/scripting/objects/VehicleScript")
                    && name.equals("getSteeringClamp") && desc.equals("(F)F")) {
                hooked[0]++;
                super.visitVarInsn(Opcodes.ALOAD, 0);
                super.visitInsn(Opcodes.DUP);
                super.visitMethodInsn(Opcodes.INVOKESTATIC, HOOKS, "wheel",
                        "(L" + TARGET + ";)F", false);
                super.visitFieldInsn(Opcodes.PUTFIELD, TARGET, "vehicleSteering", "F");
            }
            super.visitMethodInsn(opcode, owner, name, desc, itf);
        }
    }
}
