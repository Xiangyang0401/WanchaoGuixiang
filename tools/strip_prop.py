#!/usr/bin/env python3
"""从序列帧里剥离横贯画面的道具（长枪），只保留角色本体。

背景：AI 生成的角色背着一杆横向长枪，穿身而过、两端各伸出一个身位。
它在十帧里几乎纹丝不动而腿在大幅摆动，看起来像"枪浮在空中，人从旁边跑过"。
更麻烦的是它穿过身体正中——单纯裁画布只能去掉两端，中间那截去不掉，
反而更像一根棍子插在身上。

原理：形态学开运算 + 连通域筛选。
    枪杆是一条几像素宽的细线，身体是一大坨。
    腐蚀若干次后细线先断掉，身体只是缩了一圈；
    此时取最大连通块就是身体，再膨胀回原尺寸并与原图求交，
    边缘细节（马尾、手指、鞋带）完整保留。

    关键是膨胀次数要略多于腐蚀次数：腐蚀会磨掉边缘，
    膨胀少了角色会瘦一圈，多了会把断开的枪头重新粘回来。
    实测 4 腐蚀 / 5 膨胀在这套素材上刚好。

用法：
    python tools/strip_prop.py                 # 处理 player_run_clean
    python tools/strip_prop.py --dry           # 只报告，不写文件
    python tools/strip_prop.py --erode 5       # 枪更粗时加大腐蚀
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "assets" / "animation" / "player_run_clean"

# 腐蚀次数：要大于道具半宽才能把它断开，又不能大到把手臂/小腿也断掉。
ERODE = 4
# 膨胀次数：略大于腐蚀，补回被磨掉的边缘。
DILATE = 5


def strip(img: Image.Image, erode: int, dilate: int) -> tuple[Image.Image, int]:
    a = np.asarray(img).copy()
    mask = a[..., 3] > 64

    eroded = ndimage.binary_erosion(mask, iterations=erode)
    lab, n = ndimage.label(eroded)
    if n == 0:
        # 腐蚀过头，整张图没了。宁可原样返回也不要输出空白帧。
        return img, 0

    sizes = ndimage.sum(eroded, lab, range(1, n + 1))
    body = lab == (int(np.argmax(sizes)) + 1)
    body = ndimage.binary_dilation(body, iterations=dilate) & mask

    removed = int(mask.sum() - body.sum())
    a[..., 3] = np.where(body, a[..., 3], 0)
    return Image.fromarray(a, "RGBA"), removed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--erode", type=int, default=ERODE)
    ap.add_argument("--dilate", type=int, default=DILATE)
    args = ap.parse_args()

    paths = sorted(p for p in DIR.iterdir() if p.suffix.lower() == ".png")
    if not paths:
        print(f"没找到 PNG: {DIR}", file=sys.stderr)
        return 1

    for p in paths:
        img = Image.open(p).convert("RGBA")
        out, removed = strip(img, args.erode, args.dilate)
        total = int((np.asarray(img)[..., 3] > 64).sum())
        pct = removed / max(total, 1) * 100

        # 剥离比例异常时提醒：正常在 5~20%。
        # 过低说明没断开（枪还在），过高说明把身体也切了。
        flag = ""
        if pct < 3.0:
            flag = "  ← 剥离过少，道具可能没断开，试试加大 --erode"
        elif pct > 30.0:
            flag = "  ← 剥离过多，可能切到身体了，试试减小 --erode"
        print(f"  {p.name}: 去掉 {removed:5d} px（{pct:4.1f}%）{flag}")

        if not args.dry:
            out.save(p)

    print(f"{'预览' if args.dry else '完成'} {len(paths)} 帧")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
