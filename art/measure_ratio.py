# -*- coding: utf-8 -*-
# Measure head-to-body ratio of character sprites.
# Method: silhouette row widths; neck = narrowest row in upper 45% of body;
# head height = top -> neck; ratio = total_height / head_height ("heads tall").
import sys
from PIL import Image
import numpy as np

FILES = [
    "driver.png", "soldier.png", "doctor.png",
    "mechanic.png", "police.png", "programmer.png",
    "zombie_male.png", "zombie_female.png", "zombie_fat.png",
]

def measure(path):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    alpha = a[:, :, 3]
    mask = alpha > 40
    rows = np.where(mask.any(axis=1))[0]
    if len(rows) == 0:
        return None
    top, bottom = int(rows[0]), int(rows[-1])
    total = bottom - top + 1
    widths = mask.sum(axis=1).astype(float)
    # ignore rows with almost nothing (stray pixels)
    widths[widths < 3] = 1e9
    # search neck in upper 45% (but skip top 5% to avoid hair wisps)
    lo = top + int(total * 0.05)
    hi = top + int(total * 0.45)
    seg = widths[lo:hi + 1]
    neck = lo + int(np.argmin(seg))
    head_h = neck - top + 1
    # body max width (below neck)
    body_w = int(mask[neck:bottom + 1].sum(axis=1).max())
    head_w = int(mask[top:neck + 1].sum(axis=1).max())
    return dict(w=im.width, h=im.height, top=top, bottom=bottom, total=total,
                neck=neck, head_h=head_h, ratio=total / head_h,
                head_w=head_w, body_w=body_w, wb=head_w and (body_w / head_w))

print(f"{'file':<18}{'px(WxH)':<12}{'total':<7}{'headH':<7}{'heads-tall':<11}{'bodyW/headW':<7}")
for f in FILES:
    r = measure("G:/末日突围/art/" + f)
    if r:
        print(f"{f:<18}{str(r['w'])+'x'+str(r['h']):<12}{r['total']:<7}{r['head_h']:<7}{r['ratio']:<11.2f}{r['wb']:<7.2f}")
