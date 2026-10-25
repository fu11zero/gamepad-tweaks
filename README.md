# Gamepad Tweaks

Java mod for Project Zomboid B42 (ZombieBuddy) that fixes gamepad handling.

## Layout

```
src/main/java/dev/gamepadtweaks/   mod source
Contents/mods/GamepadTweaks/       the mod itself (Workshop layout; the game loads it from ~/Zomboid/Workshop)
  42/mod.info
  42/media/java/client/GamepadTweaks.jar   <- build.sh output
build.sh                           build
tools/decompile.sh                 decompile game classes into decompiled/ (not in git)
```

## Build

Requires JDK 25 (game classes are Java 25):

```sh
sudo pacman -S jdk25-openjdk
./build.sh
```

## Reading game code

```sh
tools/decompile.sh zombie/core/physics/CarController zombie/input/JoypadManager
```

## Requirements

- ZombieBuddy 2.3.4+ installed as a Java agent (`-javaagent:ZombieBuddy.jar --` in launch options).
- On first launch ZombieBuddy asks to approve the new jar; it asks again after every rebuild.
