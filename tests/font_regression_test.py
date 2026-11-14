"""Regression check for the Chinese glyph rasterization overflow in mobile builds.

The user-provided Balatro+ game copy contains GoNotoCJKCore.ttf and its cmap
covers U+60E0 (惠). The proprietary game font is intentionally not checked in.
This test checks that the mobile patch retains the safe font path and rendering
scale; it does not claim to test on-device FreeType rendering.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PATCH = (ROOT / "patches/portrait-mobile/game.lua.patch").read_text(encoding="utf-8")
FONT_RE = re.compile(r'^\+\s*\{file = "resources/fonts/([^"]+)", render_scale = self\.TILESIZE\*([^,]+),'
                     r' TEXT_HEIGHT_SCALE = 0\.7, TEXT_OFFSET = \{x=0,y=-13\},'
                     r' FONTSCALE = ([0-9.]+), squish = 1, DESCSCALE = 1\.1\},$', re.M)

matches = [(font, scale.strip(), factor) for font, scale, factor in FONT_RE.findall(PATCH)]
assert ("GoNotoCJKCore.ttf", "7/3", "0.36") in matches, matches
assert '+            {file = "resources/fonts/NotoSansSC-Bold.ttf", render_scale = self.TILESIZE*7,' not in PATCH
assert abs((7 / 3) * 0.36 - 7 * 0.12) < 1e-9
print("Simplified Chinese font regression check passed")
