#!/usr/bin/env python3
"""完整重写 player_frames.tres，包含 idle/run/jump/fall/double_jump 五个动画。

- idle/run 的 ext_resource UID 从现有文件里解析保留（不动美术）。
- jump/fall/double_jump 从各 .import 读取新 UID。
- 用结构化方式构建全文，避免字符串插入出错。
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRES = ROOT / "data" / "player" / "player_frames.tres"

# 现有文件里已存在的动画及其 ext_resource 行，直接透传
PASS_ANIMS = ["idle", "run"]

# 新加的三段
NEW_SEGS = {
    "jump": ("player_jump_jump_crop", "jump", False, 14),
    "fall": ("player_jump_fall_crop", "fall", True, 14),
    "dj": ("player_jump_dj_crop", "double_jump", False, 14),
}


def uid_of(png: Path) -> str:
    imp = png.with_suffix(png.suffix + ".import")
    for line in imp.read_text(encoding="utf-8").splitlines():
        m = re.match(r'\s*uid="([^"]+)"', line)
        if m:
            return m.group(1)
    raise SystemExit(f"找不到 uid: {imp}")


def main() -> int:
    old = TRES.read_text(encoding="utf-8")

    # ---------- 1. 解析现有文件的 header 与 ext_resource/frames ----------
    # 收集 idle/run 的 ext_resource 行（保持原样）与动画字典
    ext_lines = re.findall(r'\[ext_resource[^\]]*\]', old)
    # 找到所有 animation 字典（顶层）——用正则匹配 "name": &"..." 到 下一个 "}" 顶层
    # 简化：按 "}, {" 或 "}]" 切，但内部 frames 无嵌套花括号除了 texture 对象。
    # 用固定拆分：从 "animations = [{" 到文件尾。

    anim_start = old.index("animations = [{")
    anim_block = old[anim_start:]
    # 把 {idle字典} {run字典} 从里面抠出来。顶层动画字典以 "\n}, {" 分隔，最后 "}]"
    # 直接按每个字典的 "name": &"..." 定位。

    # 用正则取出每个顶层的动画字典对象（简单平衡花括号）
    def split_anims(block):
        # block 以 "animations = [{" 开头，剥掉前缀
        body = block[block.index("[{"):]  # 从 [{
        # body = [{...},{...}]
        # 平衡匹配
        objs = []
        depth = 0
        buf = ""
        i = 1  # 跳过 '['
        started = False
        while i < len(body):
            c = body[i]
            if c == "{":
                depth += 1
                if depth == 1:
                    started = True
                    buf = ""
                buf += c
            elif c == "}":
                depth -= 1
                buf += c
                if depth == 0 and started:
                    objs.append(buf)
                    started = False
            else:
                if started:
                    buf += c
            i += 1
        return objs

    anim_objs = split_anims(anim_block)

    keep_ids = {}   # 现有 ext_resource 的 id -> 完整行文本
    for line in ext_lines:
        m = re.search(r'id="([^"]+)"', line)
        if m:
            keep_ids[m.group(1)] = line

    # idle/run 的动画字典，按名字筛选
    def obj_name(o):
        m = re.search(r'"name": &"([^"]+)"', o)
        return m.group(1) if m else None

    kept_anims = []
    for o in anim_objs:
        nm = obj_name(o)
        if nm in PASS_ANIMS:
            kept_anims.append(o)

    # ---------- 2. 生成三个新段 ----------
    new_ext = []     # ext_resource 行
    new_anims = []
    anim_counter = 0  # 保证 id 唯一

    for seg, (dirn, anim, loop, fps) in NEW_SEGS.items():
        d = ROOT / "assets" / "animation" / dirn
        pngs = sorted(d.glob("*.png"))
        ids = []
        for p in pngs:
            uid = uid_of(p)
            rel = f"res://assets/animation/{dirn}/{p.name}"
            id_ = f"{seg}{len(ids) + 1}"
            new_ext.append(
                f'[ext_resource type="Texture2D" uid="{uid}" path="{rel}" id="{id_}"]'
            )
            ids.append(id_)
        # frames
        fr = []
        for id_ in ids:
            fr.append('{\n"duration": 1.0,\n"texture": ExtResource("' + id_ + '")\n}')
        new_anims.append(
            '{\n"frames": [' + ", ".join(fr) + "],\n"
            + '"loop": ' + ("true" if loop else "false") + ',\n'
            + '"name": &"' + anim + '",\n'
            + '"speed": ' + str(fps) + '\n}'
        )

    # ---------- 3. 组装 ----------
    all_ext = list(ext_lines) + new_ext
    total_load = len(all_ext) + 1
    header = '[gd_resource type="SpriteFrames" load_steps=%d format=3 uid="uid://cq2playerframes1"]' % total_load

    all_anims = kept_anims + new_anims
    # anim_objs 里的字典对象已含 {..} 外括号，数组无需再包一层 {
    resource = "[resource]\nanimations = [" + ", ".join(all_anims) + "]"

    out = header + "\n\n" + "\n".join(all_ext) + "\n\n" + resource + "\n"
    TRES.write_text(out, encoding="utf-8")
    print(f"已写 {TRES}  ({len(all_ext)} ext_resource, {len(all_anims)} 动画)")
    print("动画:", [obj_name(a) for a in all_anims])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
