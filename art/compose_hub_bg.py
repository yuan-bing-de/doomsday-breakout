"""
合成主界面背景：
  底图 = 09-21-18（废土街道 + 4只清晰远处丧尸 + 完整废弃车）
  人物 = 06-59-18 去棋盘格后只保留上半身（去掉它自带的抽象车顶）
  枪械 = 游戏内真实武器贴图 mg_ak47.png
  合成：人物蹲在底图的车后，枪架在车后备箱上，枪口朝右瞄准远处丧尸
输出：hub_background.png (1152x648)
"""
from PIL import Image, ImageDraw
import numpy as np
from collections import deque

ART = r"D:\末日突围（游戏开发中）\末日突围\art"


def remove_checkerboard_bg(input_path: str, output_path: str, thresh: int = 120):
    img = Image.open(input_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    visited = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        q.append((0, x)); q.append((h - 1, x))
    for y in range(h):
        q.append((y, 0)); q.append((y, w - 1))
    while q:
        y, x = q.popleft()
        if visited[y, x]:
            continue
        r, g, b, a = arr[y, x]
        if a == 0 or (r > thresh and g > thresh and b > thresh):
            visited[y, x] = True
            arr[y, x, 3] = 0
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                    q.append((ny, nx))
    Image.fromarray(arr).save(output_path, "PNG")


# ---- 1. 底图（含远处清晰丧尸 + 完整废弃车）----
bg = Image.open(ART + r"\Post_apocalyptic_game_main_men_2026-08-09T09-21-18.png").convert("RGBA")
bg = bg.resize((1152, 648), Image.LANCZOS)

# ---- 2. 处理人物：去棋盘格、只保留上半身（去掉自带车顶）----
char_raw = ART + r"\Side_view_of_a_man_crouching_b_2026-08-09T06-59-18.png"
char_clean = ART + r"\hub_char_temp.png"
remove_checkerboard_bg(char_raw, char_clean, thresh=120)

char = Image.open(char_clean).convert("RGBA")
# 只保留 y=0~650（人物上半身 + 手臂），去掉 y>650 的抽象车顶
char = char.crop((0, 0, char.width, 650))

# 缩放到高度约 300px（让人物比例和底图车辆协调）
char_h = 300
char_w = int(char.width * char_h / char.height)
char = char.resize((char_w, char_h), Image.LANCZOS)

# 人物位置：躲在底图左侧车后，底部对齐车后备箱高度（约 y=430）
char_x = 260
char_y = 430 - char_h
bg.paste(char, (char_x, char_y), char)

# ---- 3. 添加真实枪械：游戏内 AK-47 贴图 ----
gun = Image.open(ART + r"\weapons\mg_ak47.png").convert("RGBA")
# 缩放到宽度 160px
gun_scale = 160.0 / gun.width
gun_w = int(gun.width * gun_scale)
gun_h = int(gun.height * gun_scale)
gun = gun.resize((gun_w, gun_h), Image.LANCZOS)

# 枪口朝右，轻微上翘（-3度），架在车后备箱上
gun_angle = -3
gun = gun.rotate(gun_angle, expand=True, resample=Image.BICUBIC)

# 枪的位置：放在人物双手之间，枪口指向右侧丧尸
gun_x = char_x + int(char_w * 0.55)
gun_y = char_y + int(char_h * 0.78) - gun_h // 2
bg.paste(gun, (gun_x, gun_y), gun)

# ---- 4. 枪口火光（可选，静态画面可以不加或加很弱的）----
# 这里先不加，避免用户再次质疑火光含义

# ---- 5. 底部渐变暗化，让选项框区域更清晰 ----
gradient = Image.new("RGBA", (1152, 150), (0, 0, 0, 0))
gd = ImageDraw.Draw(gradient)
for y in range(150):
    alpha = int(180 * (y / 150))
    gd.line([(0, y), (1152, y)], fill=(0, 0, 0, alpha))
bg.paste(gradient, (0, 648 - 150), gradient)

# ---- 6. 保存 ----
output = ART + r"\hub_background.png"
bg.save(output, "PNG")
print(f"Done! Saved to {output}")
print(f"Size: {bg.size}")
