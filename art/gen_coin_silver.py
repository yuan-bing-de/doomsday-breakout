from PIL import Image
import os

here = os.path.dirname(os.path.abspath(__file__))
src = Image.open(os.path.join(here, "coin_gold.png")).convert("RGBA")
out = Image.new("RGBA", src.size, (0, 0, 0, 0))

sp = src.load()
op = out.load()
w, h = src.size
for y in range(h):
    for x in range(w):
        r, g, b, a = sp[x, y]
        if a == 0:
            continue
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        lum = min(255.0, lum * 1.12)
        nr = int(lum * 0.93)
        ng = int(lum * 0.96)
        nb = min(255, int(lum * 1.05))
        op[x, y] = (nr, ng, nb, a)

dst = os.path.join(here, "coin_silver.png")
out.save(dst)
print("wrote", dst, out.size)
