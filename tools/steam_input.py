#!/usr/bin/env python3
"""Generates the Steam Input action manifest and default configurations.

Output: Contents/mods/GamepadTweaks/42/media/steam_input/
- manifest.vdf: one action set "game" and its layers (LAYERS) with a button action per mod
  action (Bindings.lua, KeyActions.lua, InventoryActions.lua) and per vanilla binding
  (VanillaActions.lua, "vanilla<Binding>": runs the binding's game function): general
  actions in the set, situational ones in their layer (CATEGORY_LAYER); titles in English
  and Russian (vanilla + mod translations);
- gamepad_<controller type>.vdf: Steam's "Gamepad" template for that controller (sticks,
  buttons, triggers -> the virtual gamepad, as without the manifest) under its own title,
  first in the list, so the plain layout stays the default;
- gamepadtweaks_<controller type>.vdf: the same bindings titled "Gamepad Tweaks".
  Both have the actions, so nothing changes until the player binds one.

Run after adding or renaming actions; bump MINOR_REVISION on changes, MAJOR_REVISION only
if a binding id changed (Steam then updates the players' configurations).
Needs a local Steam install (templates in controller_base/templates).
"""

import json
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

MAJOR_REVISION = "2"
MINOR_REVISION = "7"
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
# Category -> layer its actions are declared in (bindable only there); others: the set.
CATEGORY_LAYER = {"hands": "onfoot", "character": "onfoot", "vehicle": "vehicle", "inventory": "inventory"}
# Actions that stay in the set whatever their category (switch seat also works next to a car).
IN_SET = {"switchSeat"}
# Steam lists the set's actions, then the active layer's, in manifest order (no sorting, no
# groups). So in the set the categories that continue in a layer go last, in layer order, and
# the layer's list goes on with the same category.
# Icon per action in front of its title: the list is long, a picture is found faster than a
# word. Color emoji only: text-presentation symbols (gear, stopwatch) render small and
# monochrome in Steam, unless followed by U+FE0F (emoji presentation) as the map here.
# Hotbar slots get their number: what a slot holds depends on the worn belt / back / webbing,
# and Steam reads the titles once per session.
ICONS = {
    # vanilla bindings
    "vanillaInteract": "👆",
    "vanillaInteractOptions": "💬",
    "vanillaCancelAction": "🚫",
    "vanillaCrouch": "🧎",
    "vanillaSprint": "🏃",
    "vanillaClimbThrough": "🤸",
    "vanillaSmashWindow": "🪟",
    "vanillaReloadWeapon": "🔫🔄",
    "vanillaRackFirearm": "🔫",
    "vanillaManualFloorAtk": "🦶",
    "vanillaInventory": "🎒",
    "vanillaClosePanel": "❌",
    "vanillaTransferItem": "↔️",
    "vanillaCycleInventory": "🎒🔁",
    "vanillaCycleLoot": "📦🔁",
    "vanillaCycleTabsLeft": "◀️",
    "vanillaCycleTabsRight": "▶️",
    "vanillaBrakes": "🚘🛑",
    "vanillaCruiseControl": "🚘⏱️",
    "vanillaZoomIn": "🔎➕",
    "vanillaZoomOut": "🔎➖",
    # inventory window
    "invTransferAll": "📦⏬",
    "invTransferSameType": "📦🔀",
    "invTransferSameTypeNearby": "📦🗄️",
    "invAllToFloor": "📦⬇️",
    "invDropSelected": "🫳",
    "invTransferStack": "↔️📚",
    "invTransferOne": "↔️1️⃣",
    "invUse": "👆👆",
    "invUnpack": "🎒📤",
    # mod actions
    "vehicleWheel": "🚙",
    "emoteWheel": "😀",
    "equipWheel": "🗡️",
    "extraWheel": "🏡",
    "commandWheel": "🎮",
    "pause": "🏠",
    "map": "🗺️",
    "craftingMenu": "🔨",
    "buildingMenu": "🧱",
    "skills": "📈",
    "health": "💊",
    "protection": "🦺",
    "info": "👤",
    "survivalGuide": "📖",
    "timePause": "🕐⏸️",
    "timeNormal": "🕐▶️",
    "timeFast1": "🕐⏩",
    "timeFast2": "🕐⏩⏩",
    "timeFast3": "🕐⏩⏩⏩",
    "moveFurniture": "🪑",
    "toggleUI": "👀",
    "screenshot": "📸",
    "pvp": "⚔️",
    "lightSource": "🔦",
    "dropPrimary": "🫳",
    "dropSecondary": "🫳",
    "dropBothHands": "🫳",
    "dropBag": "🫳🎒",
    "dropHandsAndBag": "🫳🎒",
    "grabCorpse": "🧟",
    "sharpenWeapon": "🔪",
    "firearmRadial": "🔫🔄",
    "sitOnGround": "🧘",
    "searchMode": "🔍",
    "shout": "📢",
    "releaseRope": "🧗",
    "switchSeat": "🚘💺",
    "cruiseFaster": "🚘🔼",
    "cruiseSlower": "🚘🔽",
    "engine": "🚘🔑",
    "headlights": "🚘🔆",
    "heater": "🚘🌡️",
    "horn": "🚘📯",
    "vehicleInfo": "🚘🔧",
    "hotbar1": "1️⃣",
    "hotbar2": "2️⃣",
    "hotbar3": "3️⃣",
    "hotbar4": "4️⃣",
    "hotbar5": "5️⃣",
    "hotbar6": "6️⃣",
    "hotbar7": "7️⃣",
    "hotbar8": "8️⃣",
}

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


def localization(actions):
    result = []
    en = translations("EN")
    for lang, lang_dir in LANGS.items():
        texts = translations(lang_dir)

        def t(key):
            return texts.get(key) or en.get(key) or key

        items = [
            ("set_" + SET, "Project Zomboid"),
            *[("layer_" + l, t("UI_GamepadTweaks_steam_layer_" + l)) for l in LAYERS],
            ("config_title", t("UI_GamepadTweaks_steam_configTitle")),
            ("config_description", t("UI_GamepadTweaks_steam_configDescription")),
        ]
        for id_, cat, key, layer in actions:
            text = t(key)  # no layer note: a Steam action runs directly (cruise +/- without X held)
            icon = ICONS.get(id_, "")
            items.append(("act_" + id_, f"{icon} {text}".strip()))
        result.append((lang, items))
    return result


def place(action):
    """Layer the action is declared in, or None for the set."""
    id_, cat, *_ = action
    return None if id_ in IN_SET else CATEGORY_LAYER.get(cat)


def ordered(actions):
    """Set actions without a layer first, then by layer (LAYERS order); stable otherwise."""
    def key(item):
        i, action = item
        layer = CATEGORY_LAYER.get(action[1])
        return (LAYERS.index(layer) + 1 if layer else 0, i)
    return [a for _, a in sorted(enumerate(actions), key=key)]


def action_set(actions, with_legacy):
    items: list = [("title", "#set_" + SET)]
    if with_legacy:
        items.append(("legacy_set", "0"))
    items.append(("Button", [(a[0], "#act_" + a[0]) for a in actions if place(a) is None]))
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
        buttons = [(a[0], "#act_" + a[0]) for a in actions if place(a) == layer]
        if buttons:
            items.append(("Button", buttons))
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


def config(controller_type, template, actions, loc, tweaks):
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
        ("major_revision", MAJOR_REVISION),
        ("minor_revision", MINOR_REVISION),
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
    actions = ordered(lua_actions())
    loc = localization(actions)
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.vdf"):
        old.unlink()

    configurations = []
    for controller_type, template in CONTROLLERS.items():
        short = controller_type.removeprefix("controller_")
        entries = []
        for i, (prefix, tweaks) in enumerate((("gamepad", False), ("gamepadtweaks", True))):
            name = f"{prefix}_{short}.vdf"
            (OUT / name).write_text(config(controller_type, template, actions, loc, tweaks), encoding="utf-8")
            entries.append((str(i), [("path", name)]))
        configurations.append((controller_type, entries))

    manifest = [("Action Manifest", [
        ("configurations", configurations),
        ("major_revision", MAJOR_REVISION),
        ("minor_revision", MINOR_REVISION),
        ("actions", action_set(actions, False)),
        ("action_layers", action_layers(actions)),
        ("localization", manifest_localization(loc)),
    ])]
    (OUT / "manifest.vdf").write_text(vdf_dump(manifest), encoding="utf-8")
    print(f"{len(actions)} actions, {len(LAYERS)} layers, {len(CONTROLLERS)} configurations -> {OUT}")


if __name__ == "__main__":
    main()
