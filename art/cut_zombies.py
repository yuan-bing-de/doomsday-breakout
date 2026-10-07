# -*- coding: utf-8 -*-
# 把三只丧尸角色表切成三张独立贴图（v3）：
#   背景是带素描纹理的米色（与角色浅色区距离很近），纯色阶抠图不可靠。
#   改用：
#     1) 洪泛法去背景：dist<210 且与图边缘连通的区域 = 背景（角色被深色轮廓包围，不会漏进去）
#     2) 形态学竖向开运算：消除角色脚下的横向阴影笔触（2~5px 高的横线），保住身体
#     3) 列投影间隙 x=540/875 切三块（男/女/胖）
#     4) 水平翻转（表面朝左 → 朝右，游戏 zombie.gd 用 flip_h 朝左走）
#     5) 统一缩放系数：男=1000px 高，女/胖同系数 → 三者比例与角色表一致
from PIL import Image, ImageFilter
import numpy as np
from scipy import ndimage

SRC = "G:/末日突围/art/Edit_this_sprite_sheet__make_e_2026-09-24T12-57-39.png"
CUTS = None  # None = 自动按列投影间隙切三块；也可手动写 [x1, x2]
FLIP = False  # 角色表本身朝右时 False；朝左时 True 翻成朝右（zombie.gd 约定朝右）
MALE_TARGET_H = 1000
MARGIN = 3
OUT = ["zombie_male.png", "zombie_female.png", "zombie_fat.png"]

img = Image.open(SRC).convert("RGBA")
a = np.array(img, dtype=np.float64)
H, W = a.shape[:2]

corners = np.concatenate([a[:8, :8, :3].reshape(-1, 3), a[:8, -8:, :3].reshape(-1, 3),
                          a[-8:, :8, :3].reshape(-1, 3), a[-8:, -8:, :3].reshape(-1, 3)])
bg = corners.mean(axis=0)
dist = np.abs(a[:, :, :3] - bg).sum(axis=2)

# ---- 1) 洪泛法找背景 ----
near_bg = dist < 210
lab, n = ndimage.label(near_bg)
border_labels = np.unique(np.concatenate([lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]]))
border_labels = border_labels[border_labels > 0]
bg_mask = np.isin(lab, border_labels)
content = ~bg_mask
print("bg labels:", len(border_labels), "content px:", int(content.sum()))

# ---- 2) 竖向开运算去横向阴影笔触 ----
opened = ndimage.binary_opening(content, structure=np.ones((9, 3)))
# 只影响底部 150 行（阴影在脚下），上半身保持原样
cleaned = content.copy()
cleaned[H - 150:, :] = opened[H - 150:, :]

# ---- 2b) 内部背景口袋去除 ----
# 洪泛法只去掉与图边缘连通的背景；两腿之间/腋下等被身体围住的米色口袋漏网。
# 处理：内部 near_bg 连通域中，median(dist) < 65 的整块按背景删掉。
# 阈值 65 远低于胖丧尸黄 T 恤的 dist（~106），不会误伤衣服。
pockets = near_bg & (~bg_mask)
plab, pn = ndimage.label(pockets)
removed = 0
for i in range(1, pn + 1):
    m = plab == i
    if m.sum() < 30:
        cleaned[m] = False
        removed += 1
        continue
    if np.median(dist[m]) < 65:
        cleaned[m] = False
        removed += 1
print("interior pockets removed:", removed)

# ---- 3) 切三块 ----
if CUTS is None:
    # 自动切线：找列投影的"低谷"（间隙），取最宽的 2 个内部间隙，切线 = 间隙中点。
    # （不能反过来合并内容簇——人物间隙可能比腿间缝隙还小，会误并）
    colsum = cleaned.sum(axis=0)
    thresh = max(3.0, colsum.max() * 0.03)
    low = colsum <= thresh
    gaps = []
    x = 0
    while x < W:
        if low[x]:
            x0 = x
            while x < W and low[x]:
                x += 1
            gaps.append([x0, x - 1])
        else:
            x += 1
    # 排除贴图左右边缘的空白边距，只留两侧都有内容的内部间隙
    inner = [g for g in gaps if g[0] > 30 and g[1] < W - 30]
    inner.sort(key=lambda g: g[1] - g[0], reverse=True)
    two = sorted(inner[:2], key=lambda g: g[0])
    cuts = [(g[0] + g[1]) // 2 for g in two]
    print("auto cuts:", cuts, "gaps:", two)
else:
    cuts = CUTS
# 切线附近的残留阴影清零
for c in cuts:
    cleaned[:, max(0, c - 10):min(W, c + 10)] = False

bounds = [(0, cuts[0]), (cuts[0], cuts[1]), (cuts[1], W)]
parts = []
for (x0, x1) in bounds:
    sub = cleaned[:, x0:x1]
    # 只保留大连通域：与身体分离的阴影条/碎点（<最大域 10%）整片丢掉
    clab, cn = ndimage.label(sub)
    if cn > 1:
        sizes = ndimage.sum_labels(sub, clab, range(1, cn + 1))
        keep = sizes.max() * 0.10
        drop = np.isin(clab, [i + 1 for i, s in enumerate(sizes) if s < keep])
        sub = sub & (~drop)
    # 底部 80 行做"纯竖向"开运算：竖直连续 <17px 的内容（独立阴影条）整片消除；
    # 腿脚（竖直连续远 >17px）和贴着脚底的影子（与脚连成一条长竖 run）完整保留
    b0 = sub.shape[0] - 80
    sub[b0:, :] = ndimage.binary_opening(sub[b0:, :], structure=np.ones((17, 1)))
    ys = np.where(sub.sum(axis=1) > 0)[0]
    xs = np.where(sub.sum(axis=0) > 0)[0]
    y0, y1 = ys.min(), ys.max()
    xa, xb = xs.min(), xs.max()
    m = np.zeros_like(sub)
    m[y0:y1 + 1, xa:xb + 1] = sub[y0:y1 + 1, xa:xb + 1]
    crop_rgb = a[:, x0:x1, :3][y0:y1 + 1, xa:xb + 1]
    crop_a = m[y0:y1 + 1, xa:xb + 1] * 255.0
    crop = np.dstack([crop_rgb, crop_a])
    # 四周留白
    pad = np.zeros((crop.shape[0] + MARGIN * 2, crop.shape[1] + MARGIN * 2, 4))
    pad[MARGIN:MARGIN + crop.shape[0], MARGIN:MARGIN + crop.shape[1]] = crop
    parts.append(pad)
    print("part content: w=%d h=%d" % (crop.shape[1], crop.shape[0]))

# ---- 4) alpha 边缘轻微羽化 + 翻转 + 统一缩放 ----
k = MALE_TARGET_H / float(parts[0].shape[0])
for name, crop in zip(OUT, parts):
    im = Image.fromarray(crop.astype(np.uint8), "RGBA")
    r, g, b, al = im.split()
    al = al.filter(ImageFilter.GaussianBlur(0.8))
    im = Image.merge("RGBA", (r, g, b, al))
    if FLIP:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    nh = int(round(im.size[1] * k))
    nw = int(round(im.size[0] * k))
    im = im.resize((nw, nh), Image.LANCZOS)
    im.save("G:/末日突围/art/" + name)
    print("saved", name, im.size)
print("scale k=%.4f (male content h=%d)" % (k, parts[0].shape[0]))
