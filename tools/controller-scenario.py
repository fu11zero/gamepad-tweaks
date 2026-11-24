#!/usr/bin/env python3
"""Apply or clear controller scenarios in a saved test preset."""
import argparse
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


SCENARIOS = Path(__file__).with_name("controller-scenarios")
TEMPLATE_PREFIX = "preset.GTTest."
SCENARIO_NAMES = ("layers", "events", "aim-override")


def preset_prefix(name):
    # Kahlua's %w matches Java letters and decimal digits and string.byte returns a UTF-16 code unit.
    units = name.encode("utf-16-le")
    encoded = []
    for index in range(0, len(units), 2):
        char = chr(int.from_bytes(units[index:index + 2], "little"))
        encoded.append(char if char.isalpha() or char.isdecimal() or char in "_-" else f"%{ord(char)};")
    return "preset." + "".join(encoded) + "."


def read_scenario(name, prefix):
    source = SCENARIOS / f"{name}.properties"
    return [
        prefix + line.removeprefix(TEMPLATE_PREFIX)
        for line in source.read_text(encoding="utf-8").splitlines()
        if line.startswith(TEMPLATE_PREFIX)
    ]


def replace_file(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        staged = Path(temporary.name)
        try:
            temporary.write(content)
            temporary.flush()
            staged.chmod(stat.S_IMODE(path.stat().st_mode))
            os.replace(staged, path)
        finally:
            staged.unlink(missing_ok=True)


def warn_if_last_mod_load_was_empty(log):
    last_mod_count = None
    try:
        with log.open(encoding="utf-8", errors="replace") as lines:
            for line in lines:
                match = re.search(r"\[ZB\] ZomboidFileSystem\.loadMods\((\d+) mods?\)", line)
                if match:
                    last_mod_count = int(match[1])
    except OSError:
        return
    if last_mod_count == 0:
        print(
            "Scenario saved, but the last load in console.txt had 0 mods. "
            "Open a save with GamepadTweaks enabled to run it.",
            file=sys.stderr,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scenario", choices=(*SCENARIO_NAMES, "clear"))
    parser.add_argument("settings", type=Path, help="Path to the game's GamepadTweaks.properties")
    parser.add_argument("--preset", required=True, help="The saved test preset name shown in the game")
    args = parser.parse_args()
    path = args.settings.resolve()
    if not path.is_file():
        parser.error(f"settings file not found: {path}")
    if Path(args.preset).name != args.preset or args.preset.casefold() in {"default", "original"}:
        parser.error("choose the name of a custom test preset")
    if not (path.parent / "InputBindings" / f"{args.preset}.xml").is_file():
        parser.error(f"preset {args.preset!r} is not saved yet. Select it in Controller settings and click Apply")

    prefix = preset_prefix(args.preset)
    original = path.read_bytes()
    existing = original.splitlines(keepends=True)
    target_keys = {
        line.partition("=")[0].encode("utf-8")
        for name in SCENARIO_NAMES for line in read_scenario(name, prefix)
    }
    remaining = b"".join(
        line for line in existing if re.split(rb"[\s=:]", line.lstrip(), maxsplit=1)[0] not in target_keys
    )
    if args.scenario != "clear":
        if remaining and not remaining.endswith(b"\n"):
            remaining += b"\n"
        remaining += ("\n".join(read_scenario(args.scenario, prefix)) + "\n").encode("utf-8")
    if remaining != original:
        replace_file(path, remaining)
    print(f"{args.scenario}: {path} ({args.preset})", flush=True)
    if args.scenario != "clear":
        warn_if_last_mod_load_was_empty(path.with_name("console.txt"))


if __name__ == "__main__":
    main()
