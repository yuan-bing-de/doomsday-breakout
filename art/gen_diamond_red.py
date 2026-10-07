# -*- coding: utf-8 -*-
# 原创红色宝石（钻石）图标 v2 —— 带体积感的明式切工：竖向渐变 + 切面线 + 高光反射。
# 纯程序绘制，不含任何第三方素材，可安全用于竞赛提交。覆盖 art/diamond_red.png（128x128，4 倍超采样）。
from PIL import Image, ImageDraw


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


SS = 4           # 超采样倍数
OUT = 128        # 输出尺寸
W = OUT * SS

cx = W * 0.50
top_y = W * 0.16       # 台面顶边
table_bot = W * 0.30   # 台面下沿
girdle_y = W * 0.50    # 腰棱（最宽处）
bottom_y = W * 0.86    # 底尖
half_w = W * 0.36      # 腰棱半宽
table_w = W * 0.20     # 台面半宽

# 1) 竖向渐变底图（顶亮 -> 底暗，营造立体体积）
grad = Image.new("RGBA", (W, W), (0, 0, 0, 0))
gd = ImageDraw.Draw(grad)
top_col = (255, 140, 155, 255)
bot_col = (150, 12, 38, 255)
for y in range(W):
    t = (y - top_y) / (bottom_y - top_y)
    t = max(0.0, min(1.0, t))
    gd.line([(0, y), (W, y)], fill=lerp(top_col, bot_col, t))

# 2) 宝石轮廓遮罩（经典明式切工剪影）
mask = Image.new("L", (W, W), 0)
md = ImageDraw.Draw(mask)
sil = [(cx - table_w, top_y), (cx + table_w, top_y),
       (cx + half_w, girdle_y), (cx, bottom_y), (cx - half_w, girdle_y)]
md.polygon(sil, fill=255)

# 3) 合成：渐变 -> 宝石
gem = Image.new("RGBA", (W, W), (0, 0, 0, 0))
gem = Image.composite(grad, gem, mask)
g = ImageDraw.Draw(gem)

# 4) 切面线（暗红半透明）—— 台面边 / 冠部斜切 / 腰棱 / 亭部收束
line_col = (110, 8, 30, 150)
g.line([(cx - table_w, top_y), (cx + table_w, top_y)], fill=line_col, width=int(2.0 * SS))
g.line([(cx - table_w, top_y), (cx - half_w, girdle_y)], fill=line_col, width=int(2.0 * SS))
g.line([(cx + table_w, top_y), (cx + half_w, girdle_y)], fill=line_col, width=int(2.0 * SS))
g.line([(cx - table_w * 0.6, table_bot), (cx - half_w, girdle_y)], fill=line_col, width=int(1.5 * SS))
g.line([(cx + table_w * 0.6, table_bot), (cx + half_w, girdle_y)], fill=line_col, width=int(1.5 * SS))
g.line([(cx - table_w * 0.6, table_bot), (cx, bottom_y)], fill=line_col, width=int(1.5 * SS))
g.line([(cx + table_w * 0.6, table_bot), (cx, bottom_y)], fill=line_col, width=int(1.5 * SS))
g.line([(cx - half_w, girdle_y), (cx + half_w, girdle_y)], fill=line_col, width=int(2.5 * SS))  # 腰棱

# 5) 高光：台面左上方长条反射 + 顶边细高光线
g.ellipse([cx - table_w * 0.9, top_y + 0.02 * W, cx + 0.02 * W, top_y + 0.14 * W], fill=(255, 255, 255, 205))
g.line([(cx - table_w * 0.7, top_y + 0.01 * W), (cx + table_w * 0.5, top_y + 0.01 * W)],
       fill=(255, 255, 255, 165), width=int(1.5 * SS))

# 6) 深红外轮廓（超采样抗锯齿）
edge = (90, 6, 22, 255)
g.line(sil + [sil[0]], fill=edge, width=int(3.0 * SS), joint="curve")

# 7) 缩小输出
gem = gem.resize((OUT, OUT), Image.LANCZOS)
gem.save(r"G:\末日突围\art\diamond_red.png")
print("OK -> art/diamond_red.png (%dx%d)" % (OUT, OUT))
