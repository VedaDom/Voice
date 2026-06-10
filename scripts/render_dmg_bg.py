#!/usr/bin/env python3
"""Render the DMG installer background from the voice.pen design (I50s2):
warm paper, ember aura, "Install Voice" title, accent arrow, footer.
The app and Applications icons are real Finder icons placed by the DMG layout;
this image is everything behind them. Output @2x for Retina."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "app" / "Sources" / "VoiceApp" / "Fonts"
OUT = ROOT / "build" / "dmg-bg.png"

S = 2  # retina scale
W, H = 680 * S, 460 * S


def fraunces(size, weight=500):
    f = ImageFont.truetype(str(FONTS / "Fraunces.ttf"), size * S)
    try:
        f.set_variation_by_axes([0, 0, size, weight])  # SOFT, WONK, opsz, wght
    except Exception:
        pass
    return f


def inter(size, weight=400):
    f = ImageFont.truetype(str(FONTS / "Inter.ttf"), size * S)
    try:
        f.set_variation_by_axes([size, weight])  # opsz, wght
    except Exception:
        pass
    return f


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


img = Image.new("RGB", (W, H), hex_rgb("F6F3EC"))

# ember aura (design: 500×340 at (90,120), radial #EC6B4A2B → transparent)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
cx, cy = (90 + 250) * S, (120 + 170) * S
rx, ry = 250 * S * 0.8, 170 * S * 0.8
dist = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
alpha = np.clip(1 - dist, 0, 1) * (0x2B / 255)
base = np.array(img, dtype=np.float64)
aura = np.array(hex_rgb("EC6B4A"), dtype=np.float64)
img = Image.fromarray(
    (base * (1 - alpha[..., None]) + aura * alpha[..., None]).astype(np.uint8))

d = ImageDraw.Draw(img)
ink = hex_rgb("1E1E1C")
ink2 = hex_rgb("6C6C66")
ink3 = hex_rgb("A4A49C")
accent = hex_rgb("E5483A")

# title + subtitle (Content: titlebar 42 + padding-top 6)
title_f = fraunces(27, 500)
sub_f = inter(13.5, 400)
ty = 58 * S
tw = d.textlength("Install Voice", font=title_f)
d.text(((W - tw) / 2, ty), "Install Voice", font=title_f, fill=ink)
sub = "Drag Voice into your Applications folder to install."
sw = d.textlength(sub, font=sub_f)
d.text(((W - sw) / 2, ty + 40 * S), sub, font=sub_f, fill=ink2)

# arrow between the two icon positions (icons land at x≈181 and x≈465, y≈258)
ay = 258 * S
ax0, ax1 = 290 * S, 386 * S
lw = 5 * S
arrow = hex_rgb("E5483A") + ()
d.line([(ax0, ay), (ax1 - 14 * S, ay)], fill=accent, width=lw)
d.polygon([(ax1, ay), (ax1 - 22 * S, ay - 14 * S), (ax1 - 22 * S, ay + 14 * S)],
          fill=accent)

# footer
foot_f = inter(11.5, 400)
foot = "Built by Wistfare"
fw = d.textlength(foot, font=foot_f)
d.text(((W - fw) / 2, H - 44 * S), foot, font=foot_f, fill=ink3)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT, dpi=(144, 144))
print(f"wrote {OUT} ({W}x{H})")
