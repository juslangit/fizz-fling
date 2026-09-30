#!/usr/bin/python3
"""Composes the app icon, boot splash and itch.io cover from the Blender render art/key_bottle.png
(made in Blender through the MCP: the game's own bottle model, mid-pop)."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os, random
R = os.path.join(os.path.dirname(__file__), "..")
F = os.path.join(R, "assets/fonts/LilitaOne-Regular.ttf")
bottle = Image.open(os.path.join(R, "art/key_bottle.png")).convert("RGBA")
bottle = bottle.crop(bottle.getbbox())
YEL, ORA, RED, DEEP = (255, 196, 40), (255, 138, 31), (227, 38, 44), (90, 13, 22)

def radial(w, h, c0, c1):
    im = Image.new("RGB", (w, h)); px = im.load()
    cx, cy, rmax = w * 0.5, h * 0.38, math.hypot(w, h) * 0.6
    for y in range(h):
        for x in range(w):
            t = min(1, math.hypot(x - cx, y - cy) / rmax)
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return im.convert("RGBA")

def bubbles(im, n, seed):
    random.seed(seed); d = ImageDraw.Draw(im)
    for _ in range(n):
        r = random.randint(6, 26); x = random.randint(0, im.width); y = random.randint(0, im.height)
        d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 255, 150), width=3)
        d.ellipse([x - r * 0.5, y - r * 0.6, x - r * 0.1, y - r * 0.2], fill=(255, 255, 255, 170))

def text(im, xy, s, size, fill, outline=10, anchor="mm", rot=0):
    f = ImageFont.truetype(F, size)
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    d.text((xy[0], xy[1] + size * 0.07), s, font=f, fill=DEEP, anchor=anchor, stroke_width=outline, stroke_fill=DEEP)
    d.text(xy, s, font=f, fill=fill, anchor=anchor, stroke_width=outline, stroke_fill=DEEP)
    if rot:
        layer = layer.rotate(rot, center=xy, resample=Image.BICUBIC)
    im.alpha_composite(layer)

def paste_bottle(im, height, center):
    b = bottle.resize((int(bottle.width * height / bottle.height), height), Image.LANCZOS)
    shadow = Image.new("RGBA", b.size, (0, 0, 0, 0)); shadow.putalpha(b.getchannel("A").point(lambda a: a * 0.35))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    x, y = int(center[0] - b.width / 2), int(center[1] - b.height / 2)
    im.alpha_composite(shadow, (x + 10, y + 14)); im.alpha_composite(b, (x, y))

# icon: bottle on the soda gradient, rounded square
icon = radial(512, 512, YEL, RED); bubbles(icon, 14, 1)
paste_bottle(icon, 470, (262, 262))
mask = Image.new("L", (512, 512), 0); ImageDraw.Draw(mask).rounded_rectangle([0, 0, 511, 511], 110, fill=255)
icon.putalpha(mask)
icon.save(os.path.join(R, "icon.png"))
# boot splash, the phone's portrait shape
sp = radial(720, 1280, YEL, RED); bubbles(sp, 40, 2)
paste_bottle(sp, 620, (360, 760))
text(sp, (360, 250), "FIZZ", 210, YEL, 16, rot=4); text(sp, (360, 420), "FLING", 160, (255, 255, 255), 14, rot=4)
sp.convert("RGB").save(os.path.join(R, "assets/ui/splash.png"))
# itch.io cover 630x500
cv = radial(630, 500, YEL, RED); bubbles(cv, 26, 3)
paste_bottle(cv, 470, (455, 255))
text(cv, (200, 140), "FIZZ", 150, YEL, 12, rot=6); text(cv, (205, 265), "FLING", 112, (255, 255, 255), 11, rot=6)
text(cv, (205, 400), "SHAKE. TILT. POP!", 40, (255, 246, 230), 6, rot=6)
os.makedirs(os.path.join(R, "art/store"), exist_ok=True)
cv.convert("RGB").save(os.path.join(R, "art/store/cover.png"))
print("ok")
