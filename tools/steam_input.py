#!/usr/bin/env python3
"""Generates the Steam Input action manifest and default configurations.

Output: Contents/mods/GamepadTweaks/42/media/steam_input/
- manifest.vdf: one action set "game" and its layers (LAYERS) with a button action per mod
  action (Bindings.lua, KeyActions.lua, InventoryActions.lua) and per vanilla binding
  (VanillaActions.lua, "vanilla<Binding>": runs the binding's game function). Where each
  action is declared (the set or a layer), its order, icon and English / Russian title come
  from tools/steam_actions.txt (see its header);
- gamepad_<controller type>.vdf: Steam's "Gamepad" template for that controller (sticks,
  buttons, triggers -> the virtual gamepad, as without the manifest) under its own title,
  first in the list, so the plain layout stays the default;
- gamepadtweaks_<controller type>.vdf: the same bindings titled "Gamepad Tweaks".
  Both have the actions, so nothing changes until the player binds one.

Run after editing steam_actions.txt or adding actions to the Lua code (then list them there).
Needs a local Steam install (templates in controller_base/templates).
"""

import json
from collections import Counter
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "Contents/mods/GamepadTweaks/42"
LUA = MOD / "media/lua/client/GamepadTweaks"
MOD_TRANSLATE = MOD / "media/lua/shared/Translate"
OUT = MOD / "media/steam_input"
PZ_DIR = Path(os.environ.get("PZ_DIR", "/mnt/data/SteamLibrary/steamapps/common/ProjectZomboid/projectzomboid"))
STEAM_DIR = Path(os.environ.get("STEAM_DIR", Path.home() / ".local/share/Steam"))
TEMPLATES = STEAM_DIR / "controller_base/templates"

ACTIONS_FILE = ROOT / "tools/steam_actions.txt"
# SteamID64 of the mod author, the "creator" of the "Gamepad Tweaks" layout (same format as in
# Steam's own saved layouts). Steam currently shows the game's developer for bundled layouts.
CREATOR = "76561198084489589"
SET = "game"

# Action set layers. The mod picks them every frame from the player's situation and
# SteamInput.java activates them in that order, bottom to top (Bindings.lua playerLayers:
# onfoot/vehicle, aiming, ui, inventory, map; menu alone). A layer changes only the inputs
# bound in it; the rest falls through to the set (the plain gamepad). New layers go last:
# the position is the layer's preset id in the players' saved layouts.
LAYERS = ["onfoot", "vehicle", "aiming", "ui", "map", "menu", "inventory"]

# Steam controller type -> "Gamepad" template.
CONTROLLERS = {
    "controller_xbox360": "controller_xbox360_gamepad_joystick.vdf",
    "controller_xboxone": "controller_xboxone_gamepad_joystick.vdf",
    "controller_xboxelite": "controller_xboxone_gamepad_joystick.vdf",
    "controller_ps3": "controller_ps3_gamepad_joystick.vdf",
    "controller_ps4": "controller_ps4_gamepad_joystick.vdf",
    "controller_ps5": "controller_ps5_gamepad_joystick.vdf",
    "controller_ps5_edge": "controller_ps5_gamepad_joystick.vdf",
    "controller_switch_pro": "controller_switch_pro_gamepad_joystick.vdf",
    "controller_neptune": "controller_neptune_gamepad_joystick.vdf",
    "controller_steamcontroller_gordon": "gamepad_joystick.vdf",
    "controller_generic": "controller_generic_gamepad_joystick.vdf",
}

# Analog actions (StickPadGyro): id -> input mode. An analog line in steam_actions.txt (an id
# from here) is declared in its section like a button: "aim" in the aiming layer, where the
# player puts the gyro. Steam does everything about the source (gyro activation, sensitivity,
# dead zones, smoothing); the mod only adds the value to the game's own: "absolute_mouse" sends
# per-frame deltas, "joystick_move" a -1..1 position. Ids and modes must match SteamInput.java
# (Analog). Titles: "#analog_<id>", not "#act_", so SteamInput.readActionNames doesn't take
# them for buttons. "steer" and "move" ("joystick_move") are meant for a stick: Steam drops
# gyro-to-joystick output after any action set layer change until the game window loses and
# regains focus.
ANALOG_MODES = {"aim": "absolute_mouse", "steer": "joystick_move", "move": "joystick_move"}

LANGS = {"english": "EN", "russian": "RU"}


# --- VDF (KeyValues) ---------------------------------------------------------------

def vdf_parse(text):
    """Parses KeyValues into a list of (key, value) pairs, value = str or list."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])|//[^\n]*', text)
    pos = 0

    def block():
        nonlocal pos
        items = []
        while pos < len(tokens):
            s, brace = tokens[pos]
            if brace == "}":
                pos += 1
                return items
            if not s and not brace:  # comment
                pos += 1
                continue
            key = s
            pos += 1
            while not tokens[pos][0] and not tokens[pos][1]:
                pos += 1
            s2, b2 = tokens[pos]
            pos += 1
            items.append((key, block() if b2 == "{" else s2))
        return items

    return block()


def vdf_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def vdf_dump(items, depth=0):
    out = []
    pad = "\t" * depth
    for key, value in items:
        if isinstance(value, list):
            out.append(f"{pad}{vdf_quote(key)}\n{pad}{{\n{vdf_dump(value, depth + 1)}{pad}}}\n")
        else:
            out.append(f"{pad}{vdf_quote(key)}\t\t{vdf_quote(value)}\n")
    return "".join(out)


# --- Actions ----------------------------------------------------------------------

def read_actions_file():
    """steam_actions.txt -> (revision (major, minor), {section: (en, ru) layer title},
    [(id, section, icon, en, ru)] in file order; section "set" or a layer)."""
    revision = None
    titles = {}
    entries = []
    section = None
    errors = []
    for n, line in enumerate(ACTIONS_FILE.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if m := re.fullmatch(r"revision\s+(\d+)\.(\d+)", line):
            revision = (m[1], m[2])
        elif m := re.fullmatch(r"\[(\w+)\]\s*(.*)", line):
            section = m[1]
            if section not in ("set", *LAYERS):
                errors.append(f"line {n}: unknown section [{section}] (set, {', '.join(LAYERS)})")
            elif section in LAYERS:
                en, _, ru = m[2].partition("|")
                titles[section] = (en.strip() or section, ru.strip() or en.strip() or section)
        elif m := re.fullmatch(r"(\w+)\s+(\S+)\s+(.+?)\s*\|\s*(.+)", line):
            if section is None:
                errors.append(f"line {n}: action before any [section]")
            icon = "" if m[2] == "-" else m[2]
            entries.append((m[1], section, icon, m[3], m[4]))
        else:
            errors.append(f"line {n}: expected '<id>  <icon>  <English> | <Russian>': {line}")
    if revision is None:
        errors.append("no 'revision <major>.<minor>' line")
    if errors:
        sys.exit(f"{ACTIONS_FILE}:\n  " + "\n  ".join(errors))
    return revision, titles, entries


def check_actions(lua, entries):
    """Every Lua action listed once, nothing unknown; analog ones are optional."""
    known = {a[0] for a in lua} | set(ANALOG_MODES)
    listed = Counter(id_ for id_, *_ in entries)
    errors = [f"listed {n} times: {id_}" for id_, n in listed.items() if n > 1]
    errors += [f"not an action of the mod: {id_}" for id_ in listed if id_ not in known]
    errors += [f"missing (add it to a section): {a[0]}" for a in lua if a[0] not in listed]
    if errors:
        sys.exit(f"{ACTIONS_FILE}:\n  " + "\n  ".join(errors))


def lua_actions():
    """[(id, category, label key, layer)]: the vanilla bindings, then the settings panel order."""
    actions = []
    text = (LUA / "Bindings.lua").read_text()
    vanilla = (LUA / "VanillaActions.lua").read_text()
    vanilla = vanilla[vanilla.index("local ACTIONS = {"):]
    vanilla = vanilla[:vanilla.index("\n}\n")]
    for id_ in re.findall(r'\{ id = "vanilla(\w+)"', vanilla):
        actions.append(("vanilla" + id_, "vanilla",
                        "UI_optionscreen_gamepad_CharacterJoypadButtonBinding_name_" + id_, "world"))

    block = text[text.index("Bindings.actions = {"):]
    block = block[:block.index("\n}\n")]
    entries = re.split(r"\n\t\{ ", block)[1:]
    for e in entries:
        m = re.match(r'id = "(\w+)", category = "(\w+)".*?layer = "(\w+)"', e, re.S)
        if not m or "run =" not in e:
            continue  # hold / UI layers: no run, nothing to trigger
        actions.append((m[1], m[2], "UI_GamepadTweaks_action_" + m[1], m[3]))

    text = (LUA / "KeyActions.lua").read_text()
    cat_block = text[text.index("local CATEGORY = {"):]
    category = dict(re.findall(r'(\w+) = "(\w+)"', cat_block[:cat_block.index("\n}\n")]))
    acts_block = text[text.index("local ACTIONS = {"):]
    acts_block = acts_block[:acts_block.index("\n}\n")]
    found = re.findall(r'\{ id = "(\w+)", label = "([^"]+)"', acts_block)
    found += [(f"hotbar{n}", f"Hotbar {n}") for n in range(1, 9)]
    for id_, label in found:
        cat = category.get(id_) or ("hotbar" if id_.startswith("hotbar") else "misc")
        key = label if label.startswith(("IGUI_", "UI_GamepadTweaks_")) else "UI_optionscreen_binding_" + label
        actions.append((id_, cat, key, "world"))

    text = (LUA / "InventoryActions.lua").read_text()
    acts_block = text[text.index("local ACTIONS = {"):]
    acts_block = acts_block[:acts_block.index("\n}\n")]
    for id_ in re.findall(r'\{ id = "(\w+)"', acts_block):
        actions.append((id_, "inventory", "UI_GamepadTweaks_action_" + id_, "inventory"))
    return actions


def translations(lang_dir):
    texts = {}
    for path in sorted((PZ_DIR / "media/lua/shared/Translate" / lang_dir).glob("*.json")):
        try:
            texts.update(json.loads(path.read_text(encoding="utf-8")))
        except (ValueError, UnicodeDecodeError):
            pass
    texts.update(json.loads((MOD_TRANSLATE / lang_dir / "UI.json").read_text(encoding="utf-8")))
    return texts


def localization(actions, layer_titles):
    """Titles from steam_actions.txt (icon + text); layout title and description from the
    mod's translations."""
    result = []
    en = translations("EN")
    for i, (lang, lang_dir) in enumerate(LANGS.items()):
        texts = translations(lang_dir)

        def t(key):
            return texts.get(key) or en.get(key) or key

        items = [
            ("set_" + SET, "Project Zomboid"),
            *[("layer_" + l, layer_titles.get(l, (l, l))[i]) for l in LAYERS],
            ("config_title", t("UI_GamepadTweaks_steam_configTitle")),
            ("config_description", t("UI_GamepadTweaks_steam_configDescription")),
        ]
        for id_, _, icon, *names in actions:
            prefix = "analog_" if id_ in ANALOG_MODES else "act_"
            items.append((prefix + id_, f"{icon} {names[i]}".strip()))
        result.append((lang, items))
    return result


def declared(actions, section):
    """Button and StickPadGyro groups of the actions declared in that section."""
    groups = []
    buttons = [(a[0], "#act_" + a[0]) for a in actions if a[1] == section and a[0] not in ANALOG_MODES]
    if buttons:
        groups.append(("Button", buttons))
    analog = [(a[0], [("title", "#analog_" + a[0]), ("input_mode", ANALOG_MODES[a[0]])])
              for a in actions if a[1] == section and a[0] in ANALOG_MODES]
    if analog:
        groups.append(("StickPadGyro", analog))
    return groups


def action_set(actions, with_legacy):
    items: list = [("title", "#set_" + SET)]
    if with_legacy:
        items.append(("legacy_set", "0"))
    items += declared(actions, "set")
    return [(SET, items)]


def action_layers(actions):
    result = []
    for layer in LAYERS:
        items: list = [
            ("title", "#layer_" + layer),
            ("legacy_set", "0"),
            ("set_layer", "1"),
            ("parent_set_name", SET),
        ]
        items += declared(actions, layer)
        result.append((layer, items))
    return result


# --- Output -----------------------------------------------------------------------

def template_localization(body, actions_loc):
    """Template's own title/description per language, plus the action titles."""
    ours = dict(actions_loc)
    result = []
    for key, value in body:
        if key != "localization":
            continue
        for lang, texts in value:
            # "title"/"description" keys don't resolve as tokens in a game's layout (Steam shows "#title")
            items = [("gamepad_" + k.lower(), v) for k, v in texts if k.lower() in ("title", "description")]
            items += [kv for kv in (ours.get(lang) or ours["english"]) if not kv[0].startswith("config_")]
            result.append((lang, items))
    return result


def manifest_localization(loc):
    """Layout titles are looked up in the manifest's localization, not the layout's own (a token
    only in the layout shows as "#gamepad_title"): add the plain layout's title and description
    in every language of the template."""
    body = vdf_parse((TEMPLATES / CONTROLLERS["controller_generic"]).read_text(encoding="utf-8"))[0][1]
    plain = {lang: [kv for kv in items if kv[0].startswith("gamepad_")]
             for lang, items in template_localization(body, loc)}
    result = [(lang, plain.get(lang, []) + items) for lang, items in loc]
    result += [(lang, items) for lang, items in plain.items() if lang not in dict(loc)]
    return result


def config(controller_type, template, actions, loc, tweaks, revision):
    """tweaks=False: Steam's plain "Gamepad" layout (template title), listed first;
    tweaks=True: the same bindings titled "Gamepad Tweaks", by CREATOR."""
    items = vdf_parse((TEMPLATES / template).read_text(encoding="utf-8"))
    (root_key, body), = items
    out = [
        ("version", "3"),
        ("revision", "1"),
        ("title", "#config_title" if tweaks else "#gamepad_title"),
        ("description", "#config_description" if tweaks else "#gamepad_description"),
        ("creator", CREATOR if tweaks else ""),
        ("progenitor", ""),
        ("export_type", "unknown"),
        ("controller_type", controller_type),
        ("major_revision", revision[0]),
        ("minor_revision", revision[1]),
        ("Timestamp", "0"),
        ("actions", action_set(actions, True)),
        ("action_layers", action_layers(actions)),
        ("localization", loc if tweaks else template_localization(body, loc)),
    ]
    for key, value in body:
        if key in ("group", "settings"):
            out.append((key, value))
        elif key == "preset":
            out.append((key, [(k, SET if k == "name" else v) for k, v in value]))
    # layers start empty: everything falls through to the set
    for i, layer in enumerate(LAYERS, 1):
        out.append(("preset", [("id", str(i)), ("name", layer), ("group_source_bindings", [])]))
    return vdf_dump([(root_key, out)])


def main():
    if not TEMPLATES.is_dir():
        sys.exit(f"Steam templates not found: {TEMPLATES} (set STEAM_DIR=...)")
    revision, layer_titles, entries = read_actions_file()
    check_actions(lua_actions(), entries)
    actions = list(entries)
    # set first, then the layers in LAYERS order (Steam lists the set, then the active layer)
    actions.sort(key=lambda a: 0 if a[1] == "set" else LAYERS.index(a[1]) + 1)
    loc = localization(actions, layer_titles)
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.vdf"):
        old.unlink()

    configurations = []
    for controller_type, template in CONTROLLERS.items():
        short = controller_type.removeprefix("controller_")
        entries = []
        for i, (prefix, tweaks) in enumerate((("gamepad", False), ("gamepadtweaks", True))):
            name = f"{prefix}_{short}.vdf"
            (OUT / name).write_text(config(controller_type, template, actions, loc, tweaks, revision), encoding="utf-8")
            entries.append((str(i), [("path", name)]))
        configurations.append((controller_type, entries))

    manifest = [("Action Manifest", [
        ("configurations", configurations),
        ("major_revision", revision[0]),
        ("minor_revision", revision[1]),
        ("actions", action_set(actions, False)),
        ("action_layers", action_layers(actions)),
        ("localization", manifest_localization(loc)),
    ])]
    (OUT / "manifest.vdf").write_text(vdf_dump(manifest), encoding="utf-8")
    analog = sum(a[0] in ANALOG_MODES for a in actions)
    print(f"{len(actions) - analog} actions, {analog} analog, {len(LAYERS)} layers, {len(CONTROLLERS)} configurations -> {OUT}")


if __name__ == "__main__":
    main()
