from PIL import Image, ImageDraw

SIZE = 128

PAL = {
    "wood": dict(base=(122, 74, 40), dark=(82, 48, 24), light=(158, 102, 56),
                band=(70, 72, 82), lock=(216, 178, 72), gem=None),
    "silver": dict(base=(150, 158, 172), dark=(104, 112, 128), light=(200, 207, 220),
                  band=(88, 94, 108), lock=(232, 237, 247), gem=None),
    "gold": dict(base=(228, 184, 60), dark=(168, 128, 36), light=(255, 218, 100),
                band=(150, 112, 32), lock=(255, 244, 160), gem=None),
    "legendary": dict(base=(124, 74, 184), dark=(80, 44, 130), light=(164, 114, 228),
                      band=(96, 62, 146), lock=(255, 228, 122), gem=(122, 232, 255)),
}


def rr(d, box, r, fill, outline=None, width=0):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def gen(name, out):
    p = PAL[name]
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 箱体（下宽上窄的圆角矩形）
    rr(d, [16, 56, 112, 120], 12, p["base"], outline=p["dark"], width=2)
    # 箱体底部暗带（立体感）
    rr(d, [16, 108, 112, 120], 12, p["dark"])
    rr(d, [16, 56, 112, 110], 12, p["base"])  # 盖回上方只留底部暗边
    # 竖向木板缝
    for x in (44, 68, 92):
        d.rectangle([x - 1, 60, x + 1, 110], fill=p["dark"])
    # 左侧高光
    d.rectangle([20, 60, 26, 110], fill=p["light"])

    # 箱盖（浅色，上半圆角）
    rr(d, [16, 24, 112, 60], 16, p["light"], outline=p["dark"], width=2)
    d.line([18, 56, 110, 56], fill=p["dark"], width=2)  # 盖与体接缝
    d.rectangle([20, 28, 26, 54], fill=p["base"])  # 盖左高光

    # 金属包边（竖两条 + 横一条）
    d.rectangle([30, 24, 42, 120], fill=p["band"])
    d.rectangle([86, 24, 98, 120], fill=p["band"])
    d.rectangle([16, 50, 112, 62], fill=p["band"])
    # 包边高光
    d.rectangle([32, 26, 35, 118], fill=(220, 220, 230, 120))
    d.rectangle([88, 26, 91, 118], fill=(220, 220, 230, 120))

    # 锁扣（板 + 锁孔）
    rr(d, [54, 66, 74, 94], 6, p["lock"], outline=p["dark"], width=2)
    d.ellipse([60, 74, 68, 82], fill=p["dark"])       # 锁孔圆
    d.rectangle([63, 80, 65, 90], fill=p["dark"])     # 锁孔竖槽

    # 传奇宝箱：盖中央发光宝石
    if p["gem"] is not None:
        g = p["gem"]
        d.polygon([(64, 30), (76, 42), (64, 54), (52, 42)], fill=g)
        d.polygon([(64, 34), (71, 42), (64, 50), (57, 42)], fill=(255, 255, 255, 180))

    img.save(out)
    print("wrote", out)


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    for name in ("wood", "silver", "gold", "legendary"):
        gen(name, os.path.join(here, "chest_%s.png" % name))
