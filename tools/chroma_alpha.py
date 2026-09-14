#!/usr/bin/env python3
"""墨绿背景透明抠图（针对带细节的黑色剪影素材）。

背景：AI 生成的剪影序列，背景为均匀墨绿色 RGB(68,116,91)，
人物是带细节的深墨/近黑剪影（有发丝、衣褶、剑身高光等内部细节）。

为什么用「与背景色距离」而不是色度键或亮度键：
    色度键（g-max(r,b)）：墨绿背景绿度仅 20，会落入原脚本 KEY_HIGH=40
        的角色区间，整片背景会被误判成角色。
    亮度键（lum<X）：人物有发丝/剑身高光亮度可达 200，会被误判成背景抠掉。
    与背景色距离：背景全局均匀，人物无论黑还是亮，色相都偏离墨绿，
        取 RGB 欧氏距离最稳健，发丝和金属高光都能保留。

难点（绿 spill）：发丝极细又泛着背景的墨绿，到背景色距离仅 0.7~4.5，
    与背景难以区分。适当拉低距离阈值分离主体，再对保留的边缘做去spill。

用法：
    python tools/chroma_alpha.py --only 1          # 只抠第1帧调参
    python tools/chroma_alpha.py --only 1 --tune    # 多阈值并排对比
    python tools/chroma_alpha.py                   # 批量全部帧
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
IN_DIR = ROOT / "assets" / "animation" / "player_idle"
OUT_DIR = ROOT / "assets" / "animation" / "player_idle_clean"

# 通过边缘采样自动测得的背景色（避免写死，换素材可自适应）。
# 实际用 --cal 重新测，这里留默认值兜底。
BG = np.array([68.0, 116.0, 91.0])
# 背景采样边距（避开人物）
MARGIN = 40
# 与背景色距离 >= 为纯角色，<= 为纯背景，中间线性过渡。
# 实测本素材：背景墨绿到背景色距离 0~10，人物暗部 >117，发丝spill 0.7~4.5。
# 阈值经校准（45/15 ~ 80/30 边缘残留全为0），取 55/20 平衡：
#   下限 20 吃掉发丝/边缘的泛绿 spill，上限 55 保住主体与发丝细节。
DIST_HIGH = 55.0
DIST_LOW = 20.0
# 去spill强度：把保留下来的绿色压掉，让边缘发丝不发绿。1.0 = 完全压到max(R,B)。
DESPILL = 1.0
# 边缘去边：把半透明边缘的灰蓝/灰绿残留压回角色本体色（近黑）。
# 原理：边缘像素 = 本体色×alpha + 背景色×(1-alpha)。主角是黑剪影，
# 本体色≈纯黑，越透明（alpha 越小）越接近背景色，导致边缘发灰蓝。
# 这里按「1-alpha」做权重往黑里压：alpha 低→压得狠，alpha 高(本体)→不动。
# 0 = 不去边，1 = 边缘完全压黑。0.85 能压掉脏边又不至于把发丝染成纯黑糊成一块。
EDGE_DARKEN = 0.85
# 主体涂黑：把剪影主体核心（alpha ≥ 该阈值）内部的所有像素强制设为纯黑。
# 剪影素材常带衣褶高光、剑身反光、金属饰品等亮面细节，抠图后主体内会
# 残留一片片白点/灰点，在纯黑剪影上高对比非常刺眼（用户视觉反馈）。
# 设 0 关闭。阈值取 210：主体核心（alpha≈250）全部涂黑，边缘羽化带
# （alpha<210）保留渐变，避免涂黑后又回到硬边锯齿。
FLATTEN_THRESH = 210.0
# 边缘羽化：对 alpha 做 1px 半径的高斯模糊，软化锯齿硬边。
# 0 = 不羽化，1 = 轻度羽化（推荐）。再大（≥2）会把发丝/细刺都糊掉。
FEATHER = 1.0
# 水印区域（若有），左,上,右,下。无水印则设全 0。
WATERMARK = (0, 0, 0, 0)


def measure_bg(img: np.ndarray) -> np.ndarray:
    """取四角边缘像素平均当背景色。"""
    h, w, _ = img.shape
    m = MARGIN
    c = np.concatenate([
        img[:m, :m].reshape(-1, 3), img[:m, -m:].reshape(-1, 3),
        img[-m:, :m].reshape(-1, 3), img[-m:, -m:].reshape(-1, 3),
    ])
    return c.mean(axis=0)


def key_alpha(dist: np.ndarray, hi: float, lo: float) -> np.ndarray:
    """把到背景色的距离转成 alpha。

    dist 越大 = 越不像背景 = 越像角色，alpha 应越高。
    dist < lo = 纯背景 → 0；dist > hi = 纯角色 → 1；之间线性过渡。
    注意别把分子写成 (hi - dist)：那会让纯背景(dist=0)得到 alpha≈1。
    """
    alpha = (dist - lo) / max(hi - lo, 1e-4)
    return np.clip(alpha, 0.0, 1.0)


def despill(img: np.ndarray) -> np.ndarray:
    """把泛绿像素的 G 压回 max(R,B)，消除发丝/边缘的绿边。"""
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    spill = np.clip(g - np.maximum(r, b), 0.0, None) * DESPILL
    g = g - spill
    return np.stack([r, g, b], axis=-1)


def feather_alpha(alpha: np.ndarray, strength: float = FEATHER) -> np.ndarray:
    """对 alpha 做 1px 半径的高斯模糊，软化硬边锯齿。

    只在 strength>0 时生效。用 scipy.ndimage.gaussian_filter 对 alpha
    通道做轻微平滑，让「透明→不透明」的跳变更柔和。太强会把发丝、
    剑尖等细结构都糊掉，所以默认只给 1px 半径。
    """
    if strength <= 0.0 or alpha.max() <= 0.0:
        return alpha
    from scipy import ndimage
    return ndimage.gaussian_filter(alpha, sigma=strength)


def edge_darken(rgb: np.ndarray, alpha: np.ndarray,
                strength: float = EDGE_DARKEN) -> np.ndarray:
    """把半透明边缘的灰蓝/灰绿残留压回角色本体色。

    剪影主角本体≈纯黑。边缘像素 = 本体色×alpha + 背景×(1-alpha)，
    alpha 越低混的背景越多、颜色越泛灰蓝。按 (1-alpha) 做权重往黑里压：
    全透明→压成黑；本体(alpha≈255)→基本不动，保住内部细节。

    注意：rgb 需与 alpha 同尺寸；返回新的 rgb，不就地改。
    """
    if strength <= 0.0:
        return rgb
    w = (1.0 - alpha / 255.0)[..., None] * strength
    return np.clip(rgb * (1.0 - w), 0.0, 255.0)


def flatten_black(rgb: np.ndarray, alpha: np.ndarray,
                  thresh: float = FLATTEN_THRESH) -> np.ndarray:
    """把剪影主体核心内的所有像素强制涂成纯黑，消除内部白点/灰点/缝隙。

    剪影素材的主体内部常有衣褶高光、剑身反光等亮面细节，抠图后残留成
    一片片白点（实测主体内亮度>90的像素每帧约900个，最亮达纯白255）。
    在纯黑剪影上这些高对比白点非常刺眼，用户要求"全部涂黑"。

    只处理 alpha ≥ thresh 的主体核心像素（全部压成 RGB 0），alpha 低于
    阈值的是边缘羽化带，保持渐变——否则涂黑后又会出现一圈硬边。

    注意：rgb 会被就地修改（返回同一数组），性能友好。
    """
    if thresh <= 0.0:
        return rgb
    body = alpha >= thresh
    if body.any():
        rgb[body] = 0.0
    return rgb


def keep_largest_region(alpha: np.ndarray, min_frac: float = 0.5) -> np.ndarray:
    """只保留面积最大的连通域，清掉边缘残留的零星半透明噪声。

    背景轻微不均匀会让个别角落像素漏成半透明，它们远离人物主体，
    是面积很小的孤立连通域。人物主体是最大的那块。按连通域面积
    过滤是最稳的清理方式（不依赖固定坐标）。用 scipy.ndimage。
    """
    from scipy import ndimage
    mask = alpha > 8
    if not mask.any():
        return alpha
    lab, n = ndimage.label(mask)
    if n <= 1:
        return alpha
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    # 最大连通域的面积如果低于阈值，说明可能是全图残留而非人物，
    # 保守起见不清理（宁残留不误删）。
    if sizes.max() < mask.sum() * min_frac:
        return alpha
    keep = lab == (int(np.argmax(sizes)) + 1)
    alpha = np.where(keep, alpha, 0.0)
    return alpha


def process(img: np.ndarray, bg: np.ndarray,
            hi: float = DIST_HIGH, lo: float = DIST_LOW) -> np.ndarray:
    dist = np.sqrt(((img[:, :, :3] - bg) ** 2).sum(axis=2))
    # 统一把 alpha 转到 0~255 值域：后面对 255 做各种阈值/权重更直观，
    # 也能让 keep_largest_region 里的 alpha>8 阈值真正生效（0~1 域永远不满足）。
    alpha = key_alpha(dist, hi, lo) * 255.0

    x0, y0, x1, y1 = WATERMARK
    if x1 > x0 and y1 > y0:
        alpha[y0:y1, x0:x1] = 0.0

    clean = despill(img[:, :, :3])
    alpha = keep_largest_region(alpha)

    # 半透明边缘颜色还原：边缘像素混了背景灰蓝，按透明度压回本体黑。
    # 必须在 keep_largest_region 之后做，此时 alpha 才是干净的主体轮廓。
    clean = edge_darken(clean, alpha)

    # 羽化 alpha：软化「透明→不透明」的硬边锯齿，让边缘柔和。
    # 注意要放在 flatten_black 之前：flatten 需用羽化后的 alpha 判断主体，
    # 否则边缘带被羽化抬进主体阈值后，这一圈没涂黑会残留灰点。
    alpha = feather_alpha(alpha)

    # 主体内部涂黑：把主体核心（alpha≥阈值）内的白点/灰点/缝隙全压成纯黑。
    # 剪影素材自带衣褶高光、剑身反光，抠图后残留成刺眼白点，用户要求全涂黑。
    # 放在最后，用最终（羽化后）alpha 判断主体，保证任一≥阈值像素都被涂黑。
    clean = flatten_black(clean, alpha)

    return np.stack([clean[..., 0], clean[..., 1], clean[..., 2], alpha], axis=-1)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", type=int, default=0)
    ap.add_argument("--tune", action="store_true", help="多阈值并排对比")
    ap.add_argument("--cal", action="store_true", help="只测背景色")
    # 目录参数化：默认用 idle，传 --in-dir/--out-dir 可处理跑步/攻击/跳跃等素材。
    # 这样同一套抠图逻辑（测色/去边/羽化/涂黑）能复用到所有墨绿背景序列帧。
    ap.add_argument("--in-dir", default=None, help="输入目录子名（默认 player_idle）")
    ap.add_argument("--out-dir", default=None, help="输出目录子名（默认 player_idle_clean）")
    args = ap.parse_args()

    in_dir = Path(args.in_dir) if args.in_dir else IN_DIR
    out_dir = Path(args.out_dir) if args.out_dir else OUT_DIR

    files = sorted(p for p in in_dir.iterdir() if p.suffix.lower() == ".png")
    if not files:
        print(f"输入目录没图: {in_dir}", file=sys.stderr)
        return 1

    probe = files[0]
    img = np.asarray(Image.open(probe).convert("RGB")).astype(np.float32)
    bg = measure_bg(img)
    print(f"  实测背景色: ({bg[0]:.1f},{bg[1]:.1f},{bg[2]:.1f})")

    if args.cal:
        return 0

    if args.tune:
        print("\n  多阈值并排（存到 .preview/tune）：")
        out_img = np.zeros((img.shape[0] * 3, img.shape[1] * 3, 3), np.uint8)
        combos = [
            (25, 8), (40, 12), (60, 20), (80, 30),
            (100, 40), (120, 50),
        ]
        for ci, (hi, lo) in enumerate(combos):
            out = process(img, bg, hi, lo)
            alpha = out[..., 3]
            tint = (out[..., :3] * (alpha[..., None] / 255.0)
                    + 255 * (1 - alpha[..., None] / 255.0))
            r = ci // 3
            c = ci % 3
            out_img[r * img.shape[0]: (r + 1) * img.shape[0],
                    c * img.shape[1]: (c + 1) * img.shape[1]] = tint.astype(np.uint8)
            print(f"    dist {hi:3.0f}/{lo:4.0f}")
        Image.fromarray(out_img).save(
            ROOT / ".preview" / "tune_alpha.png")
        print("  并存 .preview/tune_alpha.png")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    sel = files[args.only - 1:args.only] if args.only else files
    for p in sel:
        im = np.asarray(Image.open(p).convert("RGB")).astype(np.float32)
        out = process(im, bg)
        rgba = np.clip(out, 0, 255).astype(np.uint8)
        Image.fromarray(rgba, "RGBA").save(out_dir / p.name)
        a = rgba[..., 3]
        print(f"  {p.name}: 不透明 {(a > 128).mean() * 100:5.2f}%  "
              f"半透明 {((a > 8) & (a <= 128)).mean() * 100:5.2f}%")
    print(f"完成 {len(sel)} 帧 → {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
