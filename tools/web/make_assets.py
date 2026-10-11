#!/usr/bin/env python3
"""Regenerate the web shell's static assets (run from anywhere; needs Pillow + fontTools).

    python tools/web/make_assets.py

Writes into tools/web/:
  favicon-32.png, icon-192.png, icon-512.png   the game icon (icon.svg redrawn with Pillow)
  og-image.png                                 1200x630 social card (menu screenshot + wordmark)
and refreshes the inline @font-face block in shell.html (Chakra Petch subset, ASCII only, WOFF),
so the loading screen paints in the game's own font on the very first frame with no extra request.
build_web.sh copies the PNGs next to index.html after the Godot export.
"""
from __future__ import annotations

import base64
import io
import os
import re

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
TITLE_TTF = os.path.join(ROOT, "assets", "fonts", "title.ttf")   # Chakra Petch Bold (OFL)
UI_TTF = os.path.join(ROOT, "assets", "fonts", "ui.ttf")         # Chakra Petch SemiBold (OFL)
SHOT = os.path.join(ROOT, "docs", "screenshots", "menu.jpg")

NAVY = (8, 10, 18)
CYAN = (57, 225, 255)
PINK = (255, 61, 129)


def icon(size: int) -> Image.Image:
    """icon.svg (128x128 viewBox) drawn at 4x and downsampled for clean anti-aliasing."""
    ss = 4
    s = size * ss / 128.0
    im = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, size * ss - 1, size * ss - 1], radius=24 * s, fill=(11, 16, 32, 255))
    pts = [(28, 92), (64, 20), (100, 92), (80, 92), (64, 58), (48, 92)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=CYAN + (255,))
    d.ellipse([(64 - 10) * s, (82 - 10) * s, (64 + 10) * s, (82 + 10) * s], fill=PINK + (255,))
    return im.resize((size, size), Image.LANCZOS)


def glow_text(base: Image.Image, xy, text: str, font, fill, glow, radius: int, stroke=0, stroke_fill=None):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(xy, text, font=font, fill=glow + (255,), stroke_width=stroke + 6, stroke_fill=glow + (255,))
    blur = layer.filter(ImageFilter.GaussianBlur(radius))
    base.alpha_composite(blur)
    base.alpha_composite(blur)
    ImageDraw.Draw(base).text(xy, text, font=font, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)


def og_image() -> Image.Image:
    W, H = 1200, 630
    shot = Image.open(SHOT).convert("RGB")
    # Cover-fit, anchored right so the live bots stay in frame; the menu column falls under the gradient.
    scale = max(W / shot.width, H / shot.height) * 1.08
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    left = shot.width - W
    top = (shot.height - H) // 2 + 30
    im = shot.crop((left, top, left + W, top + H)).convert("RGBA")
    # Left-to-right navy gradient so the wordmark reads cleanly.
    grad = Image.new("L", (W, 1))
    for x in range(W):
        t = min(1.0, max(0.0, (x - 400) / 650))
        t = t * t * (3 - 2 * t)                       # smoothstep: solid over the menu column, clear over the bots
        grad.putpixel((x, 0), int(255 * (1.0 - 0.72 * t)))
    shade = Image.new("RGBA", (W, H), NAVY + (255,))
    shade.putalpha(grad.resize((W, H)))
    im.alpha_composite(shade)
    # Thin cyan rule along the bottom.
    d = ImageDraw.Draw(im)
    d.rectangle([0, H - 6, W, H], fill=CYAN + (255,))

    title = ImageFont.truetype(TITLE_TTF, 150)
    ui = ImageFont.truetype(UI_TTF, 38)
    small = ImageFont.truetype(UI_TTF, 28)
    glow_text(im, (72, 150), "FRAGLINE", title, (255, 255, 255, 255), CYAN, 18, stroke=5, stroke_fill=CYAN + (255,))
    d = ImageDraw.Draw(im)
    # Two-tone like the in-game menu logo: "LINE" in cyan.
    d.text((72 + d.textlength("FRAG", font=title), 150), "LINE", font=title, fill=CYAN + (255,), stroke_width=5,
           stroke_fill=(185, 243, 255, 255))
    d.text((78, 345), "Neon 2D arena combat in your browser", font=ui, fill=(232, 240, 255, 255))
    d.text((78, 400), "Bots  ·  LAN multiplayer  ·  9 weapons  ·  6 arenas", font=small, fill=(232, 240, 255, 165))
    # Play badge.
    bx, by = 78, 480
    label = "PLAY IN BROWSER"
    tw = d.textlength(label, font=small)
    badge = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(badge).rounded_rectangle([bx, by, bx + tw + 56, by + 60], radius=8, fill=(57, 225, 255, 38),
                                            outline=CYAN + (255,), width=3)
    im.alpha_composite(badge)
    d = ImageDraw.Draw(im)
    d.text((bx + 28, by + 12), label, font=small, fill=CYAN + (255,))
    ic = icon(96)
    im.alpha_composite(ic, (W - 96 - 48, 48))
    return im.convert("RGB")


def font_face(family: str, ttf: str, weight: int) -> str:
    from fontTools import subset
    opts = subset.Options()
    opts.flavor = "woff"            # zlib; WOFF2 would need the brotli module
    opts.layout_features = ["kern", "liga"]
    opts.name_IDs = []
    opts.notdef_outline = True
    opts.hinting = False
    f = subset.load_font(ttf, opts)
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=list(range(0x20, 0x7F)) + [0xB7, 0x2013, 0x2014, 0x2026, 0x2192])
    sub.subset(f)
    buf = io.BytesIO()
    subset.save_font(f, buf, opts)
    data = base64.b64encode(buf.getvalue()).decode()
    print(f"  {family} {weight}: {len(buf.getvalue())} bytes woff")
    return (f"@font-face{{font-family:'{family}';font-weight:{weight};font-style:normal;font-display:block;"
            f"src:url(data:font/woff;base64,{data}) format('woff');}}")


def main() -> None:
    for size, name in [(32, "favicon-32.png"), (192, "icon-192.png"), (512, "icon-512.png")]:
        icon(size).save(os.path.join(HERE, name), optimize=True)
    og_image().save(os.path.join(HERE, "og-image.png"), optimize=True)
    print("  wrote favicon-32.png, icon-192.png, icon-512.png, og-image.png")

    shell = os.path.join(HERE, "shell.html")
    block = "\n".join([font_face("Fragline Title", TITLE_TTF, 700), font_face("Fragline UI", UI_TTF, 600)])
    with open(shell, encoding="utf-8") as fh:
        html = fh.read()
    html, n = re.subn(r"/\*FONTS-BEGIN\*/.*?/\*FONTS-END\*/", lambda _m: "/*FONTS-BEGIN*/\n" + block + "\n/*FONTS-END*/",
                      html, flags=re.S)
    if n != 1:
        raise SystemExit("shell.html: FONTS-BEGIN/FONTS-END markers not found")
    # Inline the 32px favicon so the tab icon never depends on an extra file being deployed.
    with open(os.path.join(HERE, "favicon-32.png"), "rb") as fh:
        fav = base64.b64encode(fh.read()).decode()
    html, n = re.subn(r'(<link id="fl-favicon"[^>]*?href=")[^"]*(")',
                      lambda m: m.group(1) + "data:image/png;base64," + fav + m.group(2), html)
    if n != 1:
        raise SystemExit("shell.html: fl-favicon link not found")
    with open(shell, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(html)
    print("  refreshed inline fonts + favicon in shell.html")


if __name__ == "__main__":
    main()
