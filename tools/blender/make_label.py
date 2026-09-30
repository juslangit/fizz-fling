#!/usr/bin/python3
"""Draws the bottle label texture (assets/textures/label.png) with PIL.
The label wraps once round the bottle: u = angle, v = height."""
from PIL import Image, ImageDraw, ImageFont
import os
W, H = 1024, 256
img = Image.new("RGB", (W, H), (226, 38, 44))
d = ImageDraw.Draw(img)
# white wave band through the middle
import math
pts_top = [(x, 150 + 18 * math.sin(x / W * 4 * math.pi)) for x in range(0, W + 1, 8)]
pts_bot = [(x, 196 + 18 * math.sin(x / W * 4 * math.pi + 0.6)) for x in range(W, -1, -8)]
d.polygon(pts_top + pts_bot, fill=(255, 246, 230))
# thin yellow trims top and bottom
d.rectangle([0, 0, W, 14], fill=(255, 196, 40))
d.rectangle([0, H - 14, W, H], fill=(255, 196, 40))
font = None
for f in ["/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
          "/System/Library/Fonts/Supplemental/Arial Black.ttf",
          "/System/Library/Fonts/Supplemental/Impact.ttf"]:
    if os.path.exists(f):
        font = ImageFont.truetype(f, 118); break
# the word twice, so it shows whichever side faces the camera
for cx in (W * 0.25, W * 0.75):
    for dx, dy, col in ((6, 6, (120, 10, 20)), (0, 0, (255, 255, 255))):
        d.text((cx + dx, 78 + dy), "FIZZ", font=font, fill=col, anchor="mm")
out = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures", "label.png")
img.save(out); print(os.path.abspath(out))
