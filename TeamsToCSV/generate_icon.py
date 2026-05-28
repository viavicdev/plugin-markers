#!/usr/bin/env python3
"""Generate TeamsToCSV.app icon (1024px master + macOS iconset + .icns).

macOS dock sizing: artwork must sit on a 832×832 «plate» centered in 1024×1024
with transparent margin (~96px per side). Do not pre-apply the system squircle;
macOS masks at runtime. See Apple HIG / 13:16 safe area.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
ICONSET = ROOT / "AppIcon.iconset"
MASTER = ROOT / "AppIcon-1024.png"
ICNS = ROOT / "AppIcon.icns"

CANVAS = 1024
# Apple template: art plate is 13/16 of 1024
PLATE = int(CANVAS * 13 / 16)  # 832
INSET = (CANVAS - PLATE) // 2  # 96

BG_TOP = (35, 35, 42)     # #23232A dark slate
BG_BOT = (15, 15, 20)     # #0F0F14 near-black
ACCENT = (255, 255, 255)  # white shapes
GRID = (255, 255, 255, 180)
RED_ACCENT = (219, 26, 26, 255)  # #DB1A1A — brand red
# Corner radius for plate background: (22/100) * plate per Apple template
PLATE_RADIUS = int(PLATE * 22 / 100)


def _s(cx: float, cy: float, x: float, y: float, scale: float) -> tuple[float, float]:
    return cx + (x - cx) * scale, cy + (y - cy) * scale


def draw_plate(*, graphic_scale: float = 0.82) -> Image.Image:
    """Draw icon art on the 832×832 plate (opaque), not full canvas."""
    img = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Purple gradient clipped to plate squircle
    grad = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(PLATE):
        t = y / (PLATE - 1)
        r = int(BG_TOP[0] * (1 - t) + BG_BOT[0] * t)
        g = int(BG_TOP[1] * (1 - t) + BG_BOT[1] * t)
        b = int(BG_TOP[2] * (1 - t) + BG_BOT[2] * t)
        gdraw.line([(0, y), (PLATE, y)], fill=(r, g, b, 255))
    plate_mask = Image.new("L", (PLATE, PLATE), 0)
    ImageDraw.Draw(plate_mask).rounded_rectangle(
        (0, 0, PLATE - 1, PLATE - 1), radius=PLATE_RADIUS, fill=255
    )
    img.paste(grad, (0, 0), plate_mask)
    draw = ImageDraw.Draw(img)

    cx, cy = PLATE / 2, PLATE / 2
    s = graphic_scale

    def pt(x: float, y: float) -> tuple[float, float]:
        return _s(cx, cy, x, y, s)

    bx0, by0 = pt(cx - 290, cy - 120)
    bx1, by1 = pt(cx - 70, cy + 80)
    draw.rounded_rectangle((bx0, by0, bx1, by1), radius=int(48 * s), fill=ACCENT)
    draw.polygon(
        [pt(cx - 235, cy + 72), pt(cx - 260, cy + 135), pt(cx - 175, cy + 55)],
        fill=ACCENT,
    )
    for i, base_y in enumerate([cy - 68, cy - 18, cy + 32]):
        ly = pt(cx - 290, base_y)[1]
        w = (140 - i * 18) * s
        lx = pt(cx - 246, base_y)[0]
        draw.rounded_rectangle(
            (lx, ly, lx + w, ly + 22 * s),
            radius=int(11 * s),
            fill=(100, 100, 110),  # gray lines on document
        )

    draw.polygon(
        [pt(cx - 35, cy - 28), pt(cx + 60, cy), pt(cx - 35, cy + 28), pt(cx, cy)],
        fill=RED_ACCENT,
    )

    tx0, ty0 = pt(cx + 55, cy - 130)
    tx1, ty1 = pt(cx + 285, cy + 130)
    draw.rounded_rectangle(
        (tx0, ty0, tx1, ty1),
        radius=int(36 * s),
        fill=(255, 255, 255, 38),
        outline=ACCENT,
        width=max(2, int(6 * s)),
    )
    row_h = 44 * s
    pad = 28 * s
    for row in range(4):
        y = ty0 + 36 * s + row * row_h
        draw.line([(tx0 + pad, y), (tx1 - pad, y)], fill=GRID, width=max(2, int(4 * s)))
        if row < 3:
            draw.line(
                [(tx0 + pad, y + row_h), (tx1 - pad, y + row_h)],
                fill=(255, 255, 255, 90),
                width=max(1, int(2 * s)),
            )
    col_x = tx0 + (tx1 - tx0) * 0.38
    draw.line(
        [(col_x, ty0 + 28 * s), (col_x, ty1 - 28 * s)],
        fill=(255, 255, 255, 120),
        width=max(2, int(4 * s)),
    )
    draw.rounded_rectangle(
        (tx0 + 36 * s, ty0 + 44 * s, col_x - 16 * s, ty0 + 44 * s + 32 * s),
        radius=int(8 * s),
        fill=(255, 255, 255, 70),
    )
    return img


def draw_icon() -> Image.Image:
    """1024×1024 with transparent margin — matches other Dock icons."""
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    plate = draw_plate()
    canvas.paste(plate, (INSET, INSET), plate)
    return canvas


def write_iconset(master: Image.Image) -> None:
    ICONSET.mkdir(exist_ok=True)
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, px in sizes:
        master.resize((px, px), Image.Resampling.LANCZOS).save(ICONSET / name, "PNG")


def build_icns() -> None:
    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)],
        check=True,
    )


def main() -> int:
    master = draw_icon()
    master.save(MASTER, "PNG")
    write_iconset(master)
    build_icns()
    print(f"✓ {MASTER.name} (plate {PLATE}px + {INSET}px margin)")
    print(f"✓ {ICNS.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
