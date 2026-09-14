#!/usr/bin/env python3
"""把待机序列帧裁剪到统一包围盒（横向 + 纵向），保证角色位置稳定。

为什么用统一框而不是逐帧各裁各的：
    序列帧若每帧各自切包围盒，角色会在原地左右/上下抽搐——
    这是序列帧最常见的翻车点，和"脚底不对齐"是同一类问题。
    所以先遍历所有帧找公共包围盒，再共用同一个框裁。

为什么单独从抠图结果裁，而不在抠图脚本里一起做：
    抠图关注「颜色/alpha 质量」，裁剪关注「几何对齐」，两者痛点不同，
    分开改不影响彼此。换素材或调阈值时，单独重跑某一环即可。

输入：player_idle_clean（chroma_alpha.py 抠图输出，含羽化/去边）
输出：player_idle_crop（统一包围盒裁剪，含 PAD）

用法：
    python tools/crop_idle_to_box.py            # 裁剪
    python tools/crop_idle_to_box.py --dry      # 只报告包围盒，不写文件
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
IN_DIR = ROOT / "assets" / "animation" / "player_idle_clean"
OUT_DIR = ROOT / "assets" / "animation" / "player_idle_crop"

# 判定"这个像素算角色"的最少 alpha。太低会把孤立噪声（alpha≈12）算进来
# 撑大包围盒，太高又会削掉发丝/剑尖这些细结构。30 是安全中间值。
ALPHA_MIN = 30
# 包围盒四周各留的余量（像素）。太小会削掉马尾和剑尖，太大浪费画布。
PAD = 6


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true", help="只报告不写文件")
    # 目录参数化：默认用 idle，传 --in-dir/--out-dir 可处理跑步/攻击等素材。
    ap.add_argument("--in-dir", default=None, help="输入目录子名（默认 player_idle_clean）")
    ap.add_argument("--out-dir", default=None, help="输出目录子名（默认 player_idle_crop）")
    args = ap.parse_args()

    in_dir = Path(args.in_dir) if args.in_dir else IN_DIR
    out_dir = Path(args.out_dir) if args.out_dir else OUT_DIR

    files = sorted(p for p in in_dir.iterdir() if p.suffix.lower() == ".png")
    if not files:
        print(f"输入目录没图: {in_dir}", file=sys.stderr)
        return 1

    imgs = [Image.open(p).convert("RGBA") for p in files]
    alphas = [np.asarray(im)[..., 3] for im in imgs]

    # 所有帧共用同一个包围盒。
    x0, x1, y0, y1 = 10**9, -1, 10**9, -1
    for a in alphas:
        ys, xs = np.where(a > ALPHA_MIN)
        if xs.size == 0:
            print(f"警告: 有帧找不到有效像素（alpha>{ALPHA_MIN}）", file=sys.stderr)
            continue
        x0, x1 = min(x0, xs.min()), max(x1, xs.max())
        y0, y1 = min(y0, ys.min()), max(y1, ys.max())

    if x1 < 0:
        print("所有帧都没找到有效像素，检查 ALPHA_MIN", file=sys.stderr)
        return 1

    w, h = imgs[0].size
    left = max(0, x0 - PAD)
    right = min(w, x1 + 1 + PAD)
    top = max(0, y0 - PAD)
    bottom = min(h, y1 + 1 + PAD)
    print(f"  公共包围盒 x{x0}~{x1} y{y0}~{y1}，加 PAD={PAD} 后裁 "
          f"x{left}~{right} y{top}~{bottom}")
    print(f"  裁剪尺寸 {right - left}x{bottom - top}（原 {w}x{h}）")

    if args.dry:
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    for p, im in zip(files, imgs):
        out = im.crop((left, top, right, bottom))
        out.save(out_dir / p.name)
        if p == files[0]:
            print(f"  样例 {p.name}: → {out.size}")
    print(f"完成 {len(files)} 帧 → {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
