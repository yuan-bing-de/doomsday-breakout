import sys
from PIL import Image
import numpy as np
from collections import deque

def remove_bg(path, out, thresh=40):
    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    # 用四角平均估算背景色
    corners = arr[[0, 0, -1, -1], [0, -1, 0, -1], :3].reshape(-1, 3)
    bg = corners.mean(axis=0).astype(int)
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
        visited[y, x] = True
        r, g, b = arr[y, x, :3]
        if abs(int(r) - bg[0]) < thresh and abs(int(g) - bg[1]) < thresh and abs(int(b) - bg[2]) < thresh:
            arr[y, x, 3] = 0
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                    q.append((ny, nx))
    out_img = Image.fromarray(arr)
    out_img.save(out)
    # 报告非透明区域
    a = arr[:, :, 3]
    ys, xs = np.where(a > 10)
    if len(xs):
        print("saved %s  bbox x[%d-%d] y[%d-%d] transparent=%.1f%%" % (
            out, xs.min(), xs.max(), ys.min(), ys.max(), 100 * (a > 10).mean()))

if __name__ == "__main__":
    remove_bg(sys.argv[1], sys.argv[2])
