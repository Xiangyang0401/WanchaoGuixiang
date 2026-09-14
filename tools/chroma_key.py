#!/usr/bin/env python3
"""AI 视频抽帧去绿幕 + 统一裁剪对齐 —— 输出可直接进 SpriteFrames 的序列帧。

工作流位置：AI 生成视频 → 抽帧(绿底) → 本脚本 → 透明序列帧 → AnimatedSprite2D

用法：
    python tools/chroma_key.py                 # 处理全部帧
    python tools/chroma_key.py --only 1        # 只处理第 1 帧（调参用）
    python tools/chroma_key.py --no-crop       # 保留原始 720x720 画布

为什么不用 Godot 的 EditorScript：
    Image.get_pixel 是逐像素的 GDScript 调用，720x720x10 帧 = 518 万次，
    实测要跑几十秒且没法快速迭代调参。numpy 整张图矢量化，一秒内出结果。

三步处理：
    1. 抹水印：AI 工具在右下角打了半透明 logo，各帧强度还不一样。
       角色本体从不进入该区域，直接整块判为背景。
    2. 抠像 + 去溢出：见 key_frame 注释。
    3. 统一裁剪：**十帧必须用同一个裁剪框**。
       若按每帧各自的包围盒裁，抬腿帧和落地帧的框高不同，
       导出后角色会在原地上下"抽搐"——这是序列帧最常见的翻车点。
       统一框自带对齐，进 Godot 后只需调一次 offset。
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
IN_DIR = ROOT / "assets" / "animation" / "player_run"
OUT_DIR = ROOT / "assets" / "animation" / "player_run_clean"

# --- 抠像阈值（基于"绿度" = G - max(R,B)，取值 0~255）---
# 实测绿幕色 (16,124,67) 的绿度 = 124 - 67 = 57。
# 角色身上最"偏绿"的像素远低于这个值，所以在中间划两刀：
#   绿度 >= KEY_HIGH  → 纯背景，全透明
#   绿度 <= KEY_LOW   → 纯角色，全不透明
#   两者之间          → 半透明过渡（抗锯齿边缘）
KEY_HIGH = 40
KEY_LOW = 12

# 去溢出强度。1.0 = 把泛绿像素的 G 完全压到 max(R,B)。
# 压太狠会让本该偏绿的部分（如果有）发灰，这套素材没有绿色元素，可以拉满。
DESPILL = 1.0

# 水印区域（左, 上, 右, 下），原始 720x720 画布坐标。
# 换素材来源时记得复查这个框——不同 AI 工具打水印的位置不一样。
WATERMARK_BOX = (590, 630, 720, 720)

# 裁剪框四周留白，避免抗锯齿边缘被切平。
CROP_PAD = 4

# 输出降采样比例。原图是视频抽帧，分辨率远超游戏所需（角色最终约 150px 高）。
# 留 50% 而不是直接缩到目标尺寸：以后想放大角色不用重跑一遍素材。
DOWNSCALE = 0.5


def _greenness(a: np.ndarray) -> np.ndarray:
    """绿通道比红蓝里较大的那个高出多少。

    用 max(r,b) 而不是均值：均值会把偏黄(r高b低)和偏青(b高r低)的像素
    误判成偏绿，角色的金属高光和暗部阴影正好落在这两类里。
    """
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return g - np.maximum(r, b)


def load_rgb(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32)


def key_frame(a: np.ndarray) -> np.ndarray:
    """返回抠好像、去过溢出的 RGBA 数组（float32, 0~255）。"""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    greenness = _greenness(a)

    alpha = (KEY_HIGH - greenness) / float(KEY_HIGH - KEY_LOW)
    alpha = np.clip(alpha, 0.0, 1.0)

    # 水印区整块清空。它是半透明叠加层，绿度介于中间，抠像抠不掉。
    x0, y0, x1, y1 = WATERMARK_BOX
    alpha[y0:y1, x0:x1] = 0.0

    # 去溢出：把 G 压到不超过 max(R,B)。
    # 不做这步的话，发丝和金属边缘会留一圈绿描边，在深色背景上极其明显。
    g_fixed = g - np.maximum(greenness, 0.0) * DESPILL
    return np.stack([r, g_fixed, b, alpha * 255.0], axis=-1)


def union_bbox(frames: list[np.ndarray]) -> tuple[int, int, int, int]:
    """所有帧不透明区域的联合包围盒 (left, top, right, bottom)，右下开区间。"""
    x0 = y0 = 10**9
    x1 = y1 = -1
    for f in frames:
        ys, xs = np.where(f[..., 3] > 8)
        if xs.size == 0:
            continue
        x0, x1 = min(x0, xs.min()), max(x1, xs.max())
        y0, y1 = min(y0, ys.min()), max(y1, ys.max())
    if x1 < 0:
        raise RuntimeError("所有帧都是空的，检查抠像阈值")

    h, w = frames[0].shape[:2]
    return (
        max(0, x0 - CROP_PAD),
        max(0, y0 - CROP_PAD),
        min(w, x1 + 1 + CROP_PAD),
        min(h, y1 + 1 + CROP_PAD),
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", type=int, default=0, help="只处理第 N 帧（1 起）")
    ap.add_argument("--no-crop", action="store_true", help="保留原始画布不裁剪")
    args = ap.parse_args()

    if not IN_DIR.is_dir():
        print(f"输入目录不存在: {IN_DIR}", file=sys.stderr)
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    paths = sorted(p for p in IN_DIR.iterdir() if p.suffix.lower() == ".png")
    if not paths:
        print(f"输入目录里没有 PNG: {IN_DIR}", file=sys.stderr)
        return 1

    # 先全部抠完再算联合包围盒——裁剪框必须由全部帧共同决定。
    # 用 --only 调参时跳过裁剪，否则单帧算出来的框跟批量的不一致，白看。
    frames = [key_frame(load_rgb(p)) for p in paths]

    box = None
    if not args.no_crop and not args.only:
        box = union_bbox(frames)
        print(f"  统一裁剪框: {box}  尺寸 {box[2] - box[0]}x{box[3] - box[1]}")

    sel = range(args.only - 1, args.only) if args.only else range(len(paths))
    for i in sel:
        img = Image.fromarray(np.clip(frames[i], 0, 255).astype(np.uint8), "RGBA")
        if box is not None:
            img = img.crop(box)
            if DOWNSCALE != 1.0:
                nw = max(1, int(round(img.width * DOWNSCALE)))
                nh = max(1, int(round(img.height * DOWNSCALE)))
                img = img.resize((nw, nh), Image.LANCZOS)

        dst = OUT_DIR / paths[i].name
        img.save(dst)
        a = np.asarray(img)[..., 3]
        print(f"  {paths[i].name}: {img.width}x{img.height}  不透明 "
              f"{(a > 128).mean() * 100:5.2f}%  → {dst.name}")

    print(f"完成 {len(list(sel))} 帧 → {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
