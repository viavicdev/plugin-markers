#!/usr/bin/env python3
"""TeamsToCSV app-ikon: glass-aktig bakgrunn + SVG-shape oppå.

Bruker icon-shape.png (rendret fra update.svg) som forgrunns-ikon.
Anvender et frosted-glass-bakgrunn med subtil rød accent og hvit highlight.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
ICONSET = ROOT / "AppIcon.iconset"
MASTER = ROOT / "AppIcon-1024.png"
ICNS = ROOT / "AppIcon.icns"
SHAPE = ROOT / "icon-shape.png"   # rendret fra update.svg via qlmanage

CANVAS = 1024
PLATE = int(CANVAS * 13 / 16)  # 832
INSET = (CANVAS - PLATE) // 2  # 96
PLATE_RADIUS = int(PLATE * 22 / 100)

# Solid svart med polert glass-finish, hvit ikon
GLASS_TOP    = (12, 12, 12)        # svart med bittelitt lys
GLASS_MID    = (4, 4, 4)
GLASS_BOT    = (0, 0, 0)           # pure black
HIGHLIGHT    = (255, 255, 255, 50)
RED_TINT     = (219, 26, 26, 35)
SHAPE_COLOR  = (245, 245, 248)     # hvit ikon


def draw_glass_plate() -> Image.Image:
    """Solid mørk bakgrunn med polert glass-finish (refleksjoner, ikke transparens)."""
    img = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))

    # Base gradient (top-lighter til bottom-mørkere)
    grad = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(PLATE):
        t = y / (PLATE - 1)
        if t < 0.5:
            tt = t * 2
            r = int(GLASS_TOP[0] * (1 - tt) + GLASS_MID[0] * tt)
            g = int(GLASS_TOP[1] * (1 - tt) + GLASS_MID[1] * tt)
            b = int(GLASS_TOP[2] * (1 - tt) + GLASS_MID[2] * tt)
        else:
            tt = (t - 0.5) * 2
            r = int(GLASS_MID[0] * (1 - tt) + GLASS_BOT[0] * tt)
            g = int(GLASS_MID[1] * (1 - tt) + GLASS_BOT[1] * tt)
            b = int(GLASS_MID[2] * (1 - tt) + GLASS_BOT[2] * tt)
        gdraw.line([(0, y), (PLATE, y)], fill=(r, g, b, 255))

    plate_mask = Image.new("L", (PLATE, PLATE), 0)
    ImageDraw.Draw(plate_mask).rounded_rectangle(
        (0, 0, PLATE - 1, PLATE - 1), radius=PLATE_RADIUS, fill=255
    )
    img.paste(grad, (0, 0), plate_mask)

    # Subtil topp-highlight — BLENDES OVER med alpha_composite (paste-with-mask
    # overskriver alpha, hvilket gjør plata transparent)
    topshine = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    td = ImageDraw.Draw(topshine)
    td.ellipse(
        (int(-PLATE * 0.10), int(-PLATE * 0.40),
         int(PLATE * 1.10), int(PLATE * 0.25)),
        fill=(255, 255, 255, 22)
    )
    topshine = topshine.filter(ImageFilter.GaussianBlur(radius=30))
    # Klipp topshine til squircle
    topshine_clipped = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    topshine_clipped.paste(topshine, (0, 0), plate_mask)
    img = Image.alpha_composite(img, topshine_clipped)

    # Subtil rim-light øverst
    rim = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    rmd = ImageDraw.Draw(rim)
    rmd.rounded_rectangle(
        (0, 0, PLATE - 1, PLATE - 1),
        radius=PLATE_RADIUS,
        outline=(255, 255, 255, 30),
        width=2
    )
    img = Image.alpha_composite(img, rim)

    return img


def overlay_shape(plate: Image.Image) -> Image.Image:
    """Legg SVG-shapen som mørkt forgrunns-ikon, sentrert."""
    if not SHAPE.exists():
        print(f"⚠ Mangler {SHAPE}.")
        return plate

    shape_src = Image.open(SHAPE).convert("RGBA")
    sw, sh = shape_src.size

    # qlmanage gjengir SVG med HVIT bakgrunn — bruk DARKNESS som mask
    # (svarte piksler = shape, hvite piksler = bakgrunn → transparent)
    gray = shape_src.convert("L")  # 0=svart, 255=hvit
    # Inverter så svarte piksler får full opacity
    mask = Image.eval(gray, lambda x: 255 - x)

    # Fyll med SHAPE_COLOR der mask sier "shape"
    colored = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    fill = Image.new("RGBA", (sw, sh), SHAPE_COLOR + (255,))
    colored = Image.composite(fill, colored, mask)

    # Skaler ned så shapen er ~62% av plata
    target = int(PLATE * 0.62)
    colored = colored.resize((target, target), Image.Resampling.LANCZOS)

    # Subtil skygge under ikonet
    shadow = Image.new("RGBA", (PLATE, PLATE), (0, 0, 0, 0))
    sh_alpha = colored.split()[-1]
    shadow_layer = Image.new("RGBA", colored.size, (0, 0, 0, 60))
    shadow_layer.putalpha(sh_alpha)
    offset_x = (PLATE - target) // 2
    offset_y = (PLATE - target) // 2 + 8
    shadow.paste(shadow_layer, (offset_x, offset_y), shadow_layer)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=10))

    out = plate.copy()
    out = Image.alpha_composite(out, shadow)
    out.paste(colored, ((PLATE - target) // 2, (PLATE - target) // 2), colored)
    return out


def draw_icon() -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    plate = draw_glass_plate()
    plate = overlay_shape(plate)
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
    print(f"✓ {MASTER.name} (glass + SVG-shape)")
    print(f"✓ {ICNS.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
