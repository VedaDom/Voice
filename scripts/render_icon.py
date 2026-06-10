#!/usr/bin/env python3
"""Render the Voice app icon — a faithful port of voice-icon.js from voice.pen.

Recipe (see voice-icon.js):
  * base: rounded rect, corner 0.2237·size, linear ember gradient rotated 118°
    (#F7B267 → #EF7B4E @0.48 → #E5483A)
  * sheen: radial white highlight, center (0.28, −0.05), size (1.05, 0.85)
  * 5 white bars: heights [.28,.50,.74,.44,.24], width .082·size, gap .05·size,
    outer bars at alpha 0xE6
  * edge: inner stroke #FFFFFF45, width max(1, .008·size)

Renders every macOS iconset size (supersampled 4×) into Voice.iconset/ and
builds app/AppIcon.icns via iconutil.
"""
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "build" / "Voice.iconset"
ICNS = ROOT / "app" / "AppIcon.icns"
SS = 4  # supersampling factor


def lerp_stops(t, stops):
    """t in [0,1] -> RGB from gradient stops [(pos, (r,g,b)), ...]."""
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if t <= p0:
            return c0
        if t <= p1:
            k = (t - p0) / (p1 - p0)
            return tuple(c0[i] + (c1[i] - c0[i]) * k for i in range(3))
    return stops[-1][1]


def render(size):
    s = size * SS
    r = s  # square
    rad = r * 0.2237

    yy, xx = np.mgrid[0:s, 0:s].astype(np.float64) + 0.5

    # --- base linear gradient, Pencil semantics: rotation CCW, 0°=up,
    # length = bbox height, centered.
    theta = math.radians(118)
    d = (-math.sin(theta), -math.cos(theta))  # screen coords, y down
    proj = ((xx - s / 2) * d[0] + (yy - s / 2) * d[1]) / s + 0.5
    t = np.clip(proj, 0, 1)

    stops = [(0.0, (0xF7, 0xB2, 0x67)),
             (0.48, (0xEF, 0x7B, 0x4E)),
             (1.0, (0xE5, 0x48, 0x3A))]
    img = np.zeros((s, s, 3), np.float64)
    # piecewise interpolation, vectorized per segment
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = np.where(m, (t - p0) / (p1 - p0), 0)
        for ch in range(3):
            img[..., ch] = np.where(m, c0[ch] + (c1[ch] - c0[ch]) * k, img[..., ch])
    img[t < stops[0][0]] = stops[0][1]
    img[t > stops[-1][0]] = stops[-1][1]

    # --- sheen: radial white, center (0.28, -0.05), ellipse diam (1.05, 0.85)
    cx, cy = 0.28 * s, -0.05 * s
    rx, ry = 1.05 * s / 2, 0.85 * s / 2
    dist = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    a = np.clip(1 - dist, 0, 1) * (0x4D / 255)
    for ch in range(3):
        img[..., ch] = img[..., ch] * (1 - a) + 255 * a

    base = Image.fromarray(img.astype(np.uint8), "RGB").convert("RGBA")

    # --- bars
    overlay = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    heights = [0.28, 0.50, 0.74, 0.44, 0.24]
    alphas = [0xE6, 0xFF, 0xFF, 0xFF, 0xE6]
    bw = r * 0.082
    gap = r * 0.05
    total = len(heights) * bw + (len(heights) - 1) * gap
    x = (s - total) / 2
    for h, al in zip(heights, alphas):
        bh = s * h
        od.rounded_rectangle([x, (s - bh) / 2, x + bw, (s + bh) / 2],
                             radius=bw / 2, fill=(255, 255, 255, al))
        x += bw + gap

    # --- inner edge stroke
    ew = max(1 * SS, r * 0.008)
    od.rounded_rectangle([ew / 2, ew / 2, s - ew / 2, s - ew / 2],
                         radius=rad - ew / 2, outline=(255, 255, 255, 0x45),
                         width=max(1, round(ew)))

    base.alpha_composite(overlay)

    # --- squircle mask
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s, s], radius=rad, fill=255)
    base.putalpha(mask)

    return base.resize((size, size), Image.LANCZOS)


def main():
    ICONSET.mkdir(parents=True, exist_ok=True)
    spec = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
    }
    cache = {}
    for name, px in spec.items():
        if px not in cache:
            cache[px] = render(px)
        cache[px].save(ICONSET / name)
    ICNS.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"wrote {ICNS} ({ICNS.stat().st_size // 1024} KB)")
    # a 512 preview for visual comparison against the design
    cache[512].save(ROOT / "build" / "icon-preview-512.png")


if __name__ == "__main__":
    main()
