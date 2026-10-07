# -*- coding: utf-8 -*-
# 生成腐肉掉落物贴图 art/item_rotten_meat.png
# 128x128 RGBA；3 倍超采样抗锯齿。
# 造型：一块别着骨头的腐肉 —— 暗红肉块 + 灰白脂肪纹理 + 绿色霉斑 + 露出的骨头。
import math
from PIL import Image, ImageDraw, ImageFilter

SIZE = 128
SS = 3                      # 超采样倍率
S = SIZE * SS

OUTLINE = (46, 24, 28, 255)
MEAT_D = (96, 38, 42, 255)      # 肉块暗部
MEAT_M = (126, 50, 50, 255)     # 肉块中间调
MEAT_L = (158, 74, 68, 255)     # 肉块亮部
FAT = (196, 168, 156, 255)      # 脂肪纹理
ROT_D = (66, 40, 48, 255)       # 腐坏暗斑
MOLD_D = (78, 102, 46, 255)     # 霉斑暗
MOLD_L = (122, 148, 66, 255)    # 霉斑亮
BONE = (234, 228, 208, 255)
BONE_D = (176, 166, 140, 255)


def blob_points(cx, cy, rx, ry, seed_phase, n=180):
    """不规则闭合轮廓点集（用几个不同频率的正弦叠加做出有机边缘）"""
    pts = []
    for i in range(n):
        th = 2.0 * math.pi * i / n
        k = (1.0
             + 0.085 * math.sin(3.0 * th + seed_phase)
             + 0.060 * math.sin(5.0 * th + 2.1 + seed_phase)
             + 0.038 * math.cos(7.0 * th + 0.6)
             + 0.024 * math.sin(11.0 * th + 1.4))
        pts.append((cx + math.cos(th) * rx * k, cy + math.sin(th) * ry * k))
    return pts


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # ---- 1. 骨头（先画，肉块盖住其右半，露出左端两个骨节）----
    bx0, bx1 = 8 * SS, 78 * SS
    by = 82 * SS
    bw = 9 * SS
    d.rounded_rectangle([bx0 + 10 * SS, by - bw, bx1, by + bw],
                        radius=bw, fill=BONE, outline=BONE_D, width=max(1, SS))
    # 左端两个骨节（典型的"骨头"造型：一大一小两个球）
    for (kx, ky, r) in [(20 * SS, by - 13 * SS, 13 * SS), (20 * SS, by + 13 * SS, 13 * SS)]:
        d.ellipse([kx - r, ky - r, kx + r, ky + r], fill=BONE,
                  outline=BONE_D, width=max(1, SS))
        d.ellipse([kx - r * 0.62, ky - r * 0.62, kx + r * 0.40, ky + r * 0.40],
                  fill=(250, 247, 234, 255))
    # 骨头右端骨节（会被肉块压住大半）
    for (kx, ky, r) in [(70 * SS, by - 10 * SS, 10 * SS), (70 * SS, by + 10 * SS, 10 * SS)]:
        d.ellipse([kx - r, ky - r, kx + r, ky + r], fill=BONE,
                  outline=BONE_D, width=max(1, SS))
    # 骨头上缘的暗面，做出圆柱感
    d.rounded_rectangle([bx0 + 14 * SS, by - bw, bx1 - 10 * SS, by + bw * 0.10],
                        radius=bw, fill=(250, 247, 234, 255))
    d.rounded_rectangle([bx0 + 14 * SS, by + bw * 0.45, bx1 - 10 * SS, by + bw],
                        radius=bw, fill=BONE_D)

    # ---- 2. 肉块主体（不规则 blob）----
    cx, cy, rx, ry = 70 * SS, 62 * SS, 44 * SS, 40 * SS
    meat = blob_points(cx, cy, rx, ry, 0.8)
    d.polygon(meat, fill=MEAT_M, outline=OUTLINE)
    # 加粗轮廓（多描几遍，模拟手绘粗边）
    for w in range(1, 3):
        d.line(meat + [meat[0]], fill=OUTLINE, width=w * SS, joint="curve")

    # ---- 3. 明暗体积（用裁剪过的椭圆做出高光与暗面）----
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(meat, fill=255)
    vol = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vol)
    # 右下暗面
    vd.ellipse([cx - rx * 0.35, cy - ry * 0.15, cx + rx * 1.25, cy + ry * 1.3], fill=MEAT_D)
    # 左上亮面
    vd.ellipse([cx - rx * 1.05, cy - ry * 1.05, cx + rx * 0.45, cy + ry * 0.45], fill=MEAT_L)
    vol = Image.composite(vol, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)
    img = Image.alpha_composite(img, vol)
    # 亮面做一点柔化，避免生硬边界
    img = img.filter(ImageFilter.GaussianBlur(SS * 0.7))

    # 重新描边（模糊后轮廓会变软）
    d = ImageDraw.Draw(img)
    for w in range(1, 3):
        d.line(meat + [meat[0]], fill=OUTLINE, width=w * SS, joint="curve")

    # ---- 4. 脂肪/筋膜纹理（贴着轮廓的小弧线）----
    tex = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(tex)
    td.arc([cx - 30 * SS, cy - 26 * SS, cx + 6 * SS, cy + 6 * SS],
           start=200, end=340, fill=FAT, width=max(1, int(1.6 * SS)))
    td.arc([cx - 10 * SS, cy - 8 * SS, cx + 30 * SS, cy + 26 * SS],
           start=170, end=300, fill=FAT, width=max(1, int(1.3 * SS)))
    td.arc([cx - 26 * SS, cy + 4 * SS, cx + 2 * SS, cy + 26 * SS],
           start=20, end=130, fill=FAT, width=max(1, int(1.1 * SS)))
    td.line([(cx - 26 * SS, cy - 20 * SS), (cx - 14 * SS, cy - 6 * SS)],
            fill=FAT, width=max(1, int(1.1 * SS)))
    img = Image.alpha_composite(img, Image.composite(
        tex, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # ---- 5. 霉斑（绿，不规则斑块而不是正圆）----
    mold = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    md = ImageDraw.Draw(mold)
    spots = [(98, 38, 11, 0.3), (88, 72, 10, 1.7), (56, 42, 9, 2.9),
             (106, 62, 8, 0.9), (60, 90, 7, 2.2), (74, 34, 6, 1.1)]
    for (sx, sy, sr, ph) in spots:
        sx, sy, sr = sx * SS, sy * SS, sr * SS
        outer = blob_points(sx, sy, sr, sr * 0.86, ph, n=90)
        inner = blob_points(sx, sy, sr * 0.70, sr * 0.60, ph + 0.5, n=80)
        core = blob_points(sx, sy, sr * 0.34, sr * 0.30, ph + 1.2, n=60)
        md.polygon(outer, fill=MOLD_D)
        md.polygon(inner, fill=MOLD_L)
        md.polygon(core, fill=(158, 180, 92, 255))
    # 霉斑只保留在肉块上
    img = Image.alpha_composite(img, Image.composite(
        mold, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # ---- 6. 腐坏暗斑 + 血点碎屑 ----
    dec = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dec)
    for (sx, sy, sr) in [(78, 58, 6), (94, 84, 5), (52, 66, 4), (70, 96, 4)]:
        sx, sy, sr = sx * SS, sy * SS, sr * SS
        dd.ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=ROT_D)
    img = Image.alpha_composite(img, Image.composite(
        dec, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # ---- 7. 缩回目标尺寸 ----
    img = img.resize((SIZE, SIZE), Image.LANCZOS)

    # ---- 8. 细黑描边（缩回后补一次，让轮廓更清晰）----
    d = ImageDraw.Draw(img)
    small = blob_points(cx / SS, cy / SS, rx / SS, ry / SS, 0.8, n=180)
    d.line(small + [small[0]], fill=(38, 20, 24, 255), width=2, joint="curve")

    img.save("G:/末日突围/art/item_rotten_meat.png")
    print("saved item_rotten_meat.png", img.size)


main()
