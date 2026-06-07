#!/usr/bin/env python3
"""
Generate the DroidDock app icon set.

Draws a friendly Android-robot-on-a-dock mark on a mint→teal macOS "squircle"
and renders every size the macOS asset catalog needs. Reproducible: re-run with

    python3 scripts/generate-icon.py

Requires Pillow (`python3 -m pip install Pillow`).
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter

BASE = 1024          # logical icon size
SS = 4               # supersample factor for antialiasing
S = BASE * SS

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "DroidDock", "Resources", "Assets.xcassets", "AppIcon.appiconset")

# Palette
TOP = (74, 230, 184)      # mint
BOTTOM = (10, 124, 122)   # deep teal
EYE = (9, 96, 105)        # dark teal (reads on white)
WHITE = (255, 255, 255, 255)


def sc(v: float) -> int:
    """Scale a logical (1024-space) coordinate into the supersampled canvas."""
    return int(round(v * SS))


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        # ease-in-out for a softer transition
        te = t * t * (3 - 2 * t)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * te) for i in range(3)))
    return grad.resize((size, size))


def build_master() -> Image.Image:
    margin = sc(92)
    radius = sc(208)
    box = [margin, margin, S - margin, S - margin]

    # Rounded-square body filled with the gradient.
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body.paste(vertical_gradient(S, TOP, BOTTOM), (0, 0), mask)

    # Soft top gloss.
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse(
        [margin, margin - sc(120), S - margin, sc(560)], fill=(255, 255, 255, 38)
    )
    gloss.putalpha(Image.composite(gloss.getchannel("A"), Image.new("L", (S, S), 0), mask))
    body = Image.alpha_composite(body, gloss)

    # Foreground robot mark.
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    cx = 512

    # Antennae (drawn first so the head overlaps their base).
    for x0, x1 in ((470, 430), (554, 594)):
        d.line([(sc(x0), sc(322)), (sc(x1), sc(247))], fill=WHITE, width=sc(26))
        d.ellipse([sc(x1) - sc(13), sc(247) - sc(13), sc(x1) + sc(13), sc(247) + sc(13)], fill=WHITE)

    # Legs connecting the head to the dock.
    for lx in (cx - 57, cx + 57):
        d.rounded_rectangle([sc(lx - 19), sc(628), sc(lx + 19), sc(708)], radius=sc(19), fill=WHITE)

    # Head: rounded top (semicircle), flat bottom — the classic Android silhouette.
    d.rounded_rectangle([sc(332), sc(300), sc(692), sc(648)],
                        radius=sc(180), corners=(True, True, False, False), fill=WHITE)

    # Eyes.
    for ex in (cx - 57, cx + 57):
        d.ellipse([sc(ex) - sc(25), sc(398) - sc(25), sc(ex) + sc(25), sc(398) + sc(25)], fill=EYE)

    # Dock shelf.
    d.rounded_rectangle([sc(300), sc(704), sc(724), sc(748)], radius=sc(22), fill=(255, 255, 255, 240))

    icon = Image.alpha_composite(body, fg)

    # Drop shadow for the floating-squircle look.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [margin, margin + sc(14), S - margin, S - margin + sc(14)], radius=radius, fill=(0, 0, 0, 95)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(sc(20)))

    composed = Image.alpha_composite(shadow, icon)
    return composed.resize((BASE, BASE), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    master = build_master()

    entries = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
               (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    images = []
    for size, scale in entries:
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
        images.append({"size": f"{size}x{size}", "idiom": "mac",
                       "filename": name, "scale": f"{scale}x"})

    with open(os.path.join(OUT, "Contents.json"), "w") as fh:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, fh, indent=2)

    # A 1024 master for docs / README.
    master.save(os.path.join(HERE, "..", "DroidDock", "Resources", "AppIcon-1024.png"))
    print(f"wrote {len(entries)} icons + Contents.json to {os.path.relpath(OUT)}")


if __name__ == "__main__":
    main()
