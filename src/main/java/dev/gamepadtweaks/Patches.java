package dev.gamepadtweaks;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.CharacterJoypadAxis2dBinding;
import zombie.characters.CharacterJoypadButtonBinding;
import zombie.characters.IsoPlayer;
import zombie.characters.component.CharacterInputComponent;
import zombie.core.physics.CarController;
import zombie.input.JoypadManager;
import zombie.network.GameServer;

public final class Patches {
    private Patches() {}

    // Vanilla: clientControls.steering = JoypadManager.getMovementAxisX(joypad),
    // which applies the stick dead zone and stretches diagonals up to x1.41.
    // Replace it with the raw stick X, recentered (see StickCenter) and shaped by
    // speed (see Steering). steering.enabled=false keeps vanilla; steering.rawStick=false
    // keeps the game's stick value (dead zone) but still shapes it. The Steam "steer" action
    // is added to the stick either way (see AnalogInput).
    @Patch(className = "zombie.core.physics.CarController", methodName = "updateControls")
    public static class SteeringInput {
        @Patch.OnExit
        public static void exit(@Patch.This CarController car) {
            if (GameServer.server) {
                return;
            }
            int joypad = car.vehicleObject.getJoypad();
            HeldActions.brake(car, joypad);
            Settings.refresh();
            if (joypad == -1) {
                return;
            }
            if (!Settings.steeringEnabled) {
                car.clientControls.steering = AnalogInput.steer(joypad, car.clientControls.steering);
                return;
            }
            float raw;
            float stick;
            if (Settings.rawStick) {
                raw = RawStick.movementX(joypad, car.clientControls.steering);
                stick = StickCenter.apply(joypad, raw);
            } else {
                raw = Math.max(-1.0f, Math.min(1.0f, car.clientControls.steering));
                stick = raw;
            }
            stick = AnalogInput.steer(joypad, stick);
            car.clientControls.steering = Steering.shape(car, raw, stick, joypad);
        }
    }

    // Triggers without the game's dead zone (see Triggers). Also covers
    // isLTPressed/isRTPressed (value > 0.7), which call these.
    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getLTValue")
    public static class LeftTriggerValue {
        @Patch.OnExit
        public static void exit(@Patch.This JoypadManager.Joypad joypad,
                                @Patch.Return(readOnly = false) float value) {
            value = Triggers.value(joypad, true, value);
        }
    }

    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getRTValue")
    public static class RightTriggerValue {
        @Patch.OnExit
        public static void exit(@Patch.This JoypadManager.Joypad joypad,
                                @Patch.Return(readOnly = false) float value) {
            value = Triggers.value(joypad, false, value);
        }
    }

    // A press that closed a UI element must not reach the character (see ButtonLatch).
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "setJoypadButtonsActive")
    public static class ButtonsActive {
        @Patch.OnEnter
        public static void enter(@Patch.This CharacterInputComponent input, @Patch.Argument(0) boolean active) {
            ButtonLatch.onButtonsActive(input.getJoypadBind(), input.isJoypadButtonsActive(), active);
        }
    }

    @Patch(className = "zombie.characters.CharacterJoypadButtonBinding$JoypadButtonBinding", methodName = "isDown")
    public static class CharacterButtonDown {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterJoypadButtonBinding.JoypadButtonBinding binding,
                                @Patch.Argument(0) int joypadBind,
                                @Patch.Return(readOnly = false) boolean down) {
            down = ButtonLatch.isDown(binding.getButton(), joypadBind, down);
        }
    }

    // Gamepad actions on press instead of click (see PressActions).
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isCrouchButtonPressed")
    public static class CrouchOnPress {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean pressed) {
            pressed = PressActions.crouchPressed(input, pressed);
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "updateToggleToSprint")
    public static class SprintToggleOnPress {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input) {
            PressActions.afterToggleToSprint(input);
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isInteractButtonClicked")
    public static class NoVehicleClick {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean clicked) {
            clicked = PressActions.interactClicked(input, clicked);
        }
    }

    // Held actions from the mod (Steam Input), straight to the game's queries (see HeldActions).
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isSprintButtonDown")
    public static class SprintHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.SPRINT) && input.isAllowSprint();
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isManualFloorAtkButtonDown")
    public static class FloorAttackHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.FLOOR_ATTACK);
        }
    }

    // Aim without the stick: vanilla aims only while the Aim binding (right stick by default)
    // is down AND the aiming stick is out of its dead zone, and aims a firearm precisely only
    // with PrecisionAim (right trigger half pressed). The held action is the keyboard Aim key:
    // both at once, stick released or not; the reticle starts at the player (see AnalogInput).
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isAimKeyDownInternal")
    public static class AimHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.AIM)
                    && !input.isJoypadIgnoreAim() && !input.isJoypadIgnoreAimUntilCentered();
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isPrecisionAimKeyDownInternal")
    public static class PrecisionAimHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.AIM)
                    && !input.isJoypadIgnoreAim() && !input.isJoypadIgnoreAimUntilCentered();
        }
    }

    // Attack, melee (shove) and run as held actions. Vanilla takes them from trigger / stick
    // thresholds (Attack: RT 0.93, Melee: LT, Run: movement stick 0.975); these game queries
    // also return true while the action is held. Attack still needs aiming, as with the mouse.
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isAttackButtonDown")
    public static class AttackHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.ATTACK);
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isMeleeButtonDownInternal")
    public static class MeleeHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.MELEE);
        }
    }

    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isRunButtonDown")
    public static class RunHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.RUN) && input.isAllowRun();
        }
    }

    // Steam "aim" (gyro, trackpad as mouse) moves the gamepad reticle target (see AnalogInput).
    @Patch(className = "zombie.input.AimingReticle", methodName = "update")
    public static class AimDeltas {
        @Patch.OnEnter
        public static void enter() {
            AnalogInput.updateAim();
        }
    }

    @Patch(className = "zombie.input.AimingReticle", methodName = "getAimingScreenX")
    public static class AimTargetX {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) IsoPlayer player,
                                @Patch.Return(readOnly = false) float x) {
            x = AnalogInput.aimTarget(player, x, false);
        }
    }

    @Patch(className = "zombie.input.AimingReticle", methodName = "getAimingScreenY")
    public static class AimTargetY {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) IsoPlayer player,
                                @Patch.Return(readOnly = false) float y) {
            y = AnalogInput.aimTarget(player, y, true);
        }
    }

    // Steam "move" added to the walking stick (see AnalogInput).
    @Patch(className = "zombie.characters.CharacterJoypadAxis2dBinding", methodName = "getValueX")
    public static class MoveX {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterJoypadAxis2dBinding binding, @Patch.Argument(0) int joypadBind,
                                @Patch.Return(readOnly = false) float x) {
            if (binding == CharacterJoypadAxis2dBinding.Movement) {
                x = AnalogInput.move(joypadBind, x, false);
            }
        }
    }

    @Patch(className = "zombie.characters.CharacterJoypadAxis2dBinding", methodName = "getValueY")
    public static class MoveY {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterJoypadAxis2dBinding binding, @Patch.Argument(0) int joypadBind,
                                @Patch.Return(readOnly = false) float y) {
            if (binding == CharacterJoypadAxis2dBinding.Movement) {
                y = AnalogInput.move(joypadBind, y, true);
            }
        }
    }

    // Bindings on the walking stick's length (Run: LeftStick at 0.975 and more) read the stick
    // axis itself, not the Movement binding, so they miss the Steam "move" action.
    @Patch(className = "zombie.characters.CharacterJoypadButtonBinding$Axis2dMinMaxBinding", methodName = "isDown")
    public static class MoveAxisDown {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterJoypadButtonBinding.Axis2dMinMaxBinding binding,
                                @Patch.Argument(0) int joypadBind,
                                @Patch.Return(readOnly = false) boolean down) {
            if (!down) {
                down = AnalogInput.moveAxisDown(joypadBind, binding.getAxis2d(), binding.getMin(), binding.getMax());
            }
        }
    }

    @Patch(className = "zombie.characters.CharacterJoypadAxis2dBinding", methodName = "isApplied")
    public static class MoveApplied {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterJoypadAxis2dBinding binding, @Patch.Argument(0) int joypadBind,
                                @Patch.Return(readOnly = false) boolean applied) {
            if (!applied && binding == CharacterJoypadAxis2dBinding.Movement) {
                applied = AnalogInput.moveApplied(joypadBind);
            }
        }
    }

    // Doors, windows, grapple and the vehicle use (IsoPlayer.updateUseKey -> doContext,
    // enterExitVehicle) poll the Interact binding here; the Lua prompts do the rest.
    @Patch(className = "zombie.characters.component.CharacterInputComponent", methodName = "isInteractButtonDownInternal")
    public static class InteractHeld {
        @Patch.OnExit
        public static void exit(@Patch.This CharacterInputComponent input,
                                @Patch.Return(readOnly = false) boolean down) {
            down = down || HeldActions.characterHeld(input, HeldActions.INTERACT);
        }
    }

    // The options screen draws the trigger dead zone from these; it no longer applies.
    // The dead zone buttons there still change it for the sticks.
    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getLTDeadZone")
    public static class LeftTriggerDeadZone {
        @Patch.OnExit
        public static void exit(@Patch.Return(readOnly = false) float value) {
            value = Triggers.deadZone(value);
        }
    }

    @Patch(className = "zombie.input.JoypadManager$Joypad", methodName = "getRTDeadZone")
    public static class RightTriggerDeadZone {
        @Patch.OnExit
        public static void exit(@Patch.Return(readOnly = false) float value) {
            value = Triggers.deadZone(value);
        }
    }
}
