#!/usr/bin/env python3
"""Render controller action and layer icons using Pillow and Noto Color Emoji."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from steam_input import MOD, lua_actions, read_actions_file


OUTPUT = MOD / "media/textures/GamepadTweaks/actions"
SIZE = 32
# These modifier actions are only assignable in the in-game editor.
NATIVE_ONLY = {
    "stickRadial": "🕹️", "uiNavigation": "🧭", "uiNavigateParent": "↩️",
    "native_PrecisionAim": "🔍", "native_WalkTo": "📍", "native_Loot": "📦",
    "native_Movement": "🕹️", "native_Aiming": "🕹️🎯",
}
LAYER_ICONS = {
    "layer_world": "🎮",
    "layer_onfoot": "🚶",
    "layer_vehicle": "🚗",
    "layer_aiming": "🎯",
    "layer_ui": "🪟",
    "layer_inventory": "🎒",
}


def render(icon, font):
    # Keep keycap digits and variation selectors with their base character.
    glyphs = []
    for character in icon:
        if character in "\ufe0f\u20e3":
            glyphs[-1] += character
        else:
            glyphs.append(character)

    image = Image.new("RGBA", (SIZE * len(glyphs), SIZE))
    for index, glyph in enumerate(glyphs):
        left, top, right, bottom = font.getbbox(glyph)
        tile = Image.new("RGBA", (right - left, bottom - top))
        ImageDraw.Draw(tile).text((-left, -top), glyph, font=font, embedded_color=True)
        tile = tile.crop(tile.getbbox())
        tile.thumbnail((SIZE - 2, SIZE - 2), Image.Resampling.LANCZOS)
        image.alpha_composite(tile, (index * SIZE + (SIZE - tile.width) // 2, (SIZE - tile.height) // 2))
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("font", type=Path, help="path to NotoColorEmoji.ttf")
    args = parser.parse_args()
    font = ImageFont.truetype(args.font, 109)
    _, _, entries = read_actions_file()
    steam_icons = {action: icon for action, _, icon, _, _ in entries}
    icons = {action: steam_icons[action] for action, category, _, _ in lua_actions() if category != "vanilla"}
    icons.update({
        f"native_{action.removeprefix('vanilla')}": icon
        for action, icon in steam_icons.items() if action.startswith("vanilla")
    })
    icons.update(NATIVE_ONLY)
    icons.update(LAYER_ICONS)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for action, icon in icons.items():
        if icon:
            render(icon, font).save(OUTPUT / f"{action}.png", optimize=True)


if __name__ == "__main__":
    main()
