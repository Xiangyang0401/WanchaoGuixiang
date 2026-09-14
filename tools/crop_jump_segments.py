#!/usr/bin/env python3
"""跳跃三段动画（jump/fall/double_jump）锚定裁剪。

为什么用「底部中心」锚定而不是公共包围盒：
    跳跃素材是「角色在白画布里真的上下移动」的抽帧。若按公共包围盒裁剪，
    每帧角色在画布里的垂直位移会原样保留——但 AnimatedSprite2D.centered=true
    会把每帧纹理中心对齐到节点原点，导致 Sprite 内部角色上下抖（等于把物理
    位移又叠了一遍，跳升会"双倍"）。所以必须锚定底部中心，消除帧内位移，
    只保留姿态。跳跃高度交给物理（CharacterBody2D.velocity.y）。

为什么三段共用一个画布/锚点：
    三段是独立动画，但切换时角色位置必须一致，否则一换动画角色就跳位。
    所以统一锚点 (ANCHOR)，统一的画布尺寸，保证三段任意切换零跳变。

输入：player_jump_{jump,fall,dj}（已抠图的 clean 分帧）
输出：player_jump_{jump,fall,dj}_crop（锚定对齐）
"""

import os
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
AS = ROOT / "assets" / "animation"

SEGS = {"jump": "player_jump_jump", "fall": "player_jump_fall", "dj": "player_jump_dj"}

# 统一锚点 = 三段底部中心的平均（保证切换时角色位置一致）。
ANCHOR = (598.0, 686.0)
PAD = 8


def bottom_center(img: np.ndarray):
    a = img[..., 3]
    ys, xs = np.where(a > 30)
    if xs.size == 0:
        return None
    return (xs.min(), xs.max(), ys.min(), ys.max())


def main() -> int:
    # 收集三段全部帧的锚定后外接范围，定统一画布
    all_x, all_y = [], []
    meta = {}
    for seg, d in SEGS.items():
        files = sorted((AS / d).glob("*.png"))
        meta[seg] = files
        for f in files:
            im = np.asarray(Image.open(f).convert("RGBA"))
            bb = bottom_center(im)
            if bb is None:
                continue
            x0, x1, y0, y1 = bb
            bcx = (x0 + x1) / 2.0
            dx = ANCHOR[0] - bcx
            dy = ANCHOR[1] - y1
            all_x.append(x0 + dx)
            all_x.append(x1 + dx)
            all_y.append(y0 + dy)
            all_y.append(y1 + dy)

    minx, maxx = min(all_x), max(all_x)
    miny, maxy = min(all_y), max(all_y)
    cw = int(maxx - minx + 1 + 2 * PAD)
    ch = int(maxy - miny + 1 + 2 * PAD)
    print(f"统一画布: {cw}x{ch}  锚点={ANCHOR}")

    # 逐段生成
    for seg, d in SEGS.items():
        outdir = AS / f"player_jump_{seg}_crop"
        outdir.mkdir(exist_ok=True)
        n = 0
        for f in meta[seg]:
            im = Image.open(f).convert("RGBA")
            arr = np.asarray(im)
            bb = bottom_center(arr)
            if bb is None:
                print(f"  {f.name}: 空帧跳过")
                n += 1
                continue
            x0, x1, y0, y1 = bb
            bcx = (x0 + x1) / 2.0
            shiftx = ANCHOR[0] - bcx
            shifty = ANCHOR[1] - y1

            # 该帧角色像素，平移到锚定后画布
            a = arr[..., 3]
            ysm, xsm = np.where(a > 0)
            out = np.zeros((ch, cw, 4), np.uint8)
            if ysm.size:
                nx = np.clip((xsm + shiftx - minx + PAD).astype(int), 0, cw - 1)
                ny = np.clip((ysm + shifty - miny + PAD).astype(int), 0, ch - 1)
                out[ny, nx] = arr[ysm, xsm]
            n += 1
            Image.fromarray(out).save(outdir / f"{n:03d}.png")
        print(f"  {seg}: {n} 帧 -> {outdir}")
    print("完成")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
