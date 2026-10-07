# -*- coding: utf-8 -*-
# Draw labeled horizontal gridlines every 100px so head/body ratios can be
# measured visually. Output: grid_<name>.png
from PIL import Image, ImageDraw

FILES = ["driver.png", "zombie_male.png", "zombie_female.png", "zombie_fat.png"]
BASE = "G:/末日突围/art/"

for f in FILES:
    im = Image.open(BASE + f).convert("RGBA")
    bg = Image.new("RGBA", im.size, (40, 40, 48, 255))
    bg.paste(im, (0, 0), im)
    d = ImageDraw.Draw(bg)
    for y in range(0, im.height, 100):
        d.line([(0, y), (im.width, y)], fill=(255, 60, 60, 160), width=2)
        d.text((4, y + 2), str(y), fill=(255, 255, 0, 255))
    # 50px minor lines
    for y in range(50, im.height, 100):
        d.line([(0, y), (im.width, y)], fill=(255, 255, 255, 70), width=1)
    out = BASE + "grid_" + f
    bg.convert("RGB").save(out)
    print(out)
