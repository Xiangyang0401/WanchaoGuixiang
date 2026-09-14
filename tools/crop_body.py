#!/usr/bin/env python3
"""把序列帧里的角色本体从横贯画面的道具（长枪）中切出来。

背景：AI 生成的角色背着一杆横向长枪，展开后宽度是身宽的 3 倍多。
问题不只是占地方——它在十帧里几乎纹丝不动，而腿在大幅摆动，
看起来像"枪浮在空中，人从旁边跑过"，视觉重心被完全带偏。

原理：按列统计不透明像素数。
    躯干/腿  → 每列上百个像素（密集）
    枪杆     → 每列个位数（一条细线）
    在两者之间划一刀，就能把本体框出来，不用写死坐标。
    换素材、换姿势都能自适应，这是不硬编码的意义。

用法：
    python tools/crop_body.py            # 覆盖 player_run_clean
    python tools/crop_body.py --dry      # 只报告切在哪，不写文件
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "assets" / "animation" / "player_run_clean"

# 判定"这一列属于角色本体"的最少不透明像素数。
# 实测躯干列 120~264，枪杆列 3~16，40 落在中间的空档里，两边都有充足余量。
BODY_MIN_PIXELS = 40

# 本体左右各留的余量（像素）。太小会削掉手肘和马尾。
PAD_X = 10


def body_columns(alpha: np.ndarray) -> np.ndarray:
    return (alpha > 64).sum(axis=0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true", help="只报告不写文件")
    args = ap.parse_args()

    paths = sorted(p for p in DIR.iterdir() if p.suffix.lower() == ".png")
    if not paths:
        print(f"没找到 PNG: {DIR}", file=sys.stderr)
        return 1

    imgs = [Image.open(p).convert("RGBA") for p in paths]

    # 十帧共用同一个裁剪框。逐帧各切各的会导致角色在原地左右抽搐——
    # 这是序列帧最常见的翻车点，跟脚底不对齐是同一类问题。
    x0, x1 = 10**9, -1
    for im in imgs:
        col = body_columns(np.asarray(im)[..., 3])
        hit = np.where(col >= BODY_MIN_PIXELS)[0]
        if hit.size == 0:
            print(f"警告: 有帧找不到本体，阈值可能太高", file=sys.stderr)
            continue
        x0, x1 = min(x0, hit.min()), max(x1, hit.max())

    if x1 < 0:
        print("所有帧都没找到本体，检查 BODY_MIN_PIXELS", file=sys.stderr)
        return 1

    w = imgs[0].width
    left = max(0, x0 - PAD_X)
    right = min(w, x1 + 1 + PAD_X)
    print(f"  本体列范围 {x0}~{x1}，裁剪框 x={left}~{right}"
          f"（原宽 {w} → {right - left}，省 {(1 - (right - left) / w) * 100:.0f}%）")

    if args.dry:
        return 0

    for p, im in zip(paths, imgs):
        out = im.crop((left, 0, right, im.height))
        out.save(p)
        print(f"  {p.name}: → {out.width}x{out.height}")

    print(f"完成 {len(paths)} 帧")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
