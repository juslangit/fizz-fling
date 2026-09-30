#!/usr/bin/python3
"""Draws the bottle labels with PIL: assets/textures/label_<drink>.png, plus label.png (the orange
one) which the Blender bottle model is built with. The label wraps once round the bottle:
u = angle, v = height. The word is drawn twice so it shows whichever side faces the camera."""
from PIL import Image, ImageDraw, ImageFont
import math, os, shutil

W, H = 1024, 256
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures")
FONTS = ["/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
         "/System/Library/Fonts/Supplemental/Arial Black.ttf"]
# id: (word, background, wave, trim, text, shadow, font size)
LABELS = {
    "orange":    ("FIZZ", (226, 38, 44), (255, 246, 230), (255, 196, 40), (255, 255, 255), (120, 10, 20), 118),
    "cola":      ("COLA", (200, 16, 30), (255, 255, 255), (40, 20, 18), (255, 255, 255), (90, 5, 10), 118),
    "bandung":   ("BANDUNG", (236, 92, 150), (255, 240, 246), (255, 255, 255), (255, 255, 255), (130, 30, 70), 84),
    "sparkling": ("SPARKLING", (30, 110, 220), (220, 240, 255), (180, 225, 255), (255, 255, 255), (10, 45, 110), 70),
}


def draw(word, bg, wave, trim, text, shadow, size):
    img = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(img)
    top = [(x, 150 + 18 * math.sin(x / W * 4 * math.pi)) for x in range(0, W + 1, 8)]
    bot = [(x, 196 + 18 * math.sin(x / W * 4 * math.pi + 0.6)) for x in range(W, -1, -8)]
    d.polygon(top + bot, fill=wave)
    d.rectangle([0, 0, W, 14], fill=trim)
    d.rectangle([0, H - 14, W, H], fill=trim)
    font = next(ImageFont.truetype(f, size) for f in FONTS if os.path.exists(f))
    for cx in (W * 0.25, W * 0.75):
        for dx, dy, col in ((6, 6, shadow), (0, 0, text)):
            d.text((cx + dx, 78 + dy), word, font=font, fill=col, anchor="mm")
    return img


for key, spec in LABELS.items():
    path = os.path.join(OUT, f"label_{key}.png")
    draw(*spec).save(path)
    print(os.path.abspath(path))
shutil.copy(os.path.join(OUT, "label_orange.png"), os.path.join(OUT, "label.png"))
