# 角色动作动画制作工艺

> 本文档沉淀自一段跳/二段跳/下落三组动画的完整重制过程（2026-09）。
> 开新对话时让 AI 先读这份文档，可以按同样工艺直接开工，不重新踩坑。

## 流程总览

```
AI 视频抽帧（原始素材，1112×834）
   ↓  ① 挑帧：ffmpeg 拼触摸表（contact sheet）看全部姿态，选定帧号
   ↓  ② 帧处理：BuildJumpFrames.gd（去白底 / 去烟雾 / 统一窗口 / 脚底对齐）
   ↓  ③ 注册：BuildAnimations.gd 追加进 player_frames.tres
   ↓  ④ 映射：PlayerVisual.gd 的 _ANIM 表加一行（唯一要碰的代码）
   ↓  ⑤ 验证：白像素统计 + contact sheet 目检 + SelfTest 186 项
完成
```

各步骤输出目录约定：`assets/animation/<动作名>_crop/`（处理产物），
原始素材放 `assets/animation/<动作名>/`，两者永不混用。

## 一、素材要求与底色类型

素材全部来自 AI 视频抽帧，统一 1112×834。**先分清底色类型，处理方式完全不同**：

| 底色类型 | 判别方法（角落像素） | 处理方式 |
|---|---|---|
| 白底不透明 | A=255, R≈254 | 亮度法去白底（见 `_bake_alpha`） |
| 绿幕 | A=255, R70/G117/B97 偏绿 | `ChromaKeyFrames.gd` 按颜色距离抠像 |
| 已透明+烟雾残影 | A=0（背景），角色周围有半透明灰斑 | 直接走去烟雾管线 |

**重要认知：AI 素材的烟雾残影抠不掉亮度阈值**。烟雾是灰色的，与剑刃高光、
衣服灰细节亮度重叠——绿幕素材没事（色度抠像顺带带走偏绿烟雾），
白底/透明底素材必须走形态学去烟雾（见下文）。

## 二、挑帧：先看全貌再选帧

AI 生成视频的 60 帧姿态经常"蹲姿↔舒展"交替混排，**不要按帧号顺序想当然**。

```bash
# 拼触摸表一次看全部帧（Windows 的 ffmpeg 不支持 glob，必须用 %03d 序列模式）
ffmpeg -y -v error -start_number 1 -i 'assets/animation/player_jump/%03d.png' \
  -frames:v 60 -vf "scale=120:157,tile=10x6" /tmp/sheet.png
```

产出物的帧号命名**保持源帧号**（如 030.png），SpriteFrames 引用路径才不会变。

## 三、帧处理：BuildJumpFrames.gd

`src/tools/BuildJumpFrames.gd`（`extends SceneTree`，纯 Image 操作、不引用
autoload，所以可以用 `--script` 跑；引用 autoload 的工具必须走场景方式，
见 README「命令行工具」）：

```bash
GODOT="/e/Godot/Godot_v4.6.1-stable_win64_console.exe"
"$GODOT" --headless --path . --script res://src/tools/BuildJumpFrames.gd
```

改 `GROUPS` 常量配置新组：label / src / out / frames（1-based 帧号数组）。

四个统一处理，顺序固定：

1. **去白底转透明**（`_bake_alpha`）：按亮度把白背景转 alpha=0，
   `a = clamp((BG_LUMA - luma) / (BG_LUMA - FG_LUMA), 0, 1)`，
   rgb 同乘 a 压黑去白晕。对已是透明底的源无害（取 min 原则）。
   阈值：`FG_LUMA=0.70`（低于=角色）、`BG_LUMA=0.92`（高于=背景）。
2. **去烟雾残影**（`_remove_smoke`）：形态学开运算（腐蚀 ERODE_R=4）打碎
   细碎烟雾 → 最大连通域锁定角色主体 → 主体向外膨胀 KEEP_R=20 拉回
   头发丝/剑刃/衣带 → 边缘 FEATHER=8 羽化防硬截断。
   离角色远的大块烟雾全清除；贴体 20px 内的少量残留当氛围。
   烟雾严重就把 KEEP_R 调小。
3. **组内统一裁剪窗口**：该组所有帧角色包围盒（alpha>2）求并集再各扩 2px，
   一组一个窗口。逐帧独立裁剪会让角色帧间忽大忽小。
4. **统一规格**：514×672 画布、角色水平居中、脚底对齐画布底
   （`oy = TARGET_H - PAD_FOOT - dh`）。这个规格是 `_align_foot()` 对齐的
   前提，见第五节。

## 四、注册 SpriteFrames：BuildAnimations.gd

`src/tools/BuildAnimations.gd` 把 `_crop` 目录的帧追加进
`data/player/player_frames.tres`：

```bash
"$GODOT" --headless --path . --import   # 新帧先导入
"$GODOT" --headless --path . --script res://src/tools/BuildAnimations.gd
```

改脚本顶部常量：帧号数组、`speed`（fps，节奏快的动作给高一些）、loop
（循环动作 true，触发型 one-shot false）。

**输出帧号命名不变时无需重跑此步**（SpriteFrames 引用路径没变，重导入即生效）。

## 五、接入 PlayerVisual：只改 _ANIM 表

`src/actors/player/PlayerVisual.gd` 的 `_ANIM` 表是**唯一要碰代码的地方**：

```gdscript
const _ANIM := {
    ...
    Look.JUMP: &"jump_start",   # 逻辑状态 → 动画名
    ...
}
```

要点：

- **视觉状态比逻辑状态多**：逻辑 NORMAL 一个状态，视觉分 idle/run/jump/fall。
- `_FALLBACK` 表配降级链（没做的动作退而求其次播别的，角色不能消失）。
- "触发一瞬间"的动作（二段跳）用 `trigger_xxx()` + `_forced_look` 强制播完
  一次，否则会被速度算出的 jump/fall 一帧切走。
- **缩放基准是 idle 第一帧**（234×702 → `visual_height_tiles=4.6` 格）。
  新动画画布高度必须接近（645~702 区间），差太多会显得比例突兀。
- `_align_foot()` 按当前动画实际显示高度对齐脚底，前提是帧处理时
  脚底已贴画布底。

## 六、验证（三件套，缺一不可）

```bash
# 1. 白像素统计：白色不透明占比必须 ≈0%（对齐 idle 基准）
powershell -NoProfile -Command "
Add-Type -AssemblyName System.Drawing
\$bmp=[System.Drawing.Bitmap]::FromFile('E:/Godot/demo/assets/animation/<目录>/001.png')
\$w=0;\$t=0;\$n=0
for(\$y=0;\$y -lt \$bmp.Height;\$y+=4){for(\$x=0;\$x -lt \$bmp.Width;\$x+=4){
  \$c=\$bmp.GetPixel(\$x,\$y);\$n++
  if(\$c.A -eq 0){\$t++}elseif(\$c.A -gt 200 -and \$c.R -gt 240 -and \$c.G -gt 240 -and \$c.B -gt 240){\$w++}}}
Write-Output \"白=\$([Math]::Round(100*\$w/\$n,2))% 透明=\$([Math]::Round(100*\$t/\$n,2))%\")
"
# 2. contact sheet 目检（拼图命令见第二节），确认无残影/无白边/构图统一
# 3. SelfTest（改了 PlayerVisual/SelfTest 期望值后必跑）
"$GODOT" --headless --path . res://scenes/SelfTest.tscn
```

## 踩坑记录（按代价排序）

1. **去白底必须在缩放后对整张画布做**。先裁剪保留白底再想"后面再抠"，
   结果就是角色周围一圈白框（已踩：第一版白底帧 76% 白色不透明）。
2. **亮度法去不掉灰烟雾**。烟雾/角色灰细节/剑刃高光亮度重叠，必须形态学
   + 连通域按"结构"区分，不是按亮度。
3. **GDScript 语法坑**：`Image.set_data()` 要 5 参（用
   `Image.create_from_data` 返回新图代替）；`Image.create` 弃用改
   `Image.create_empty`；`SpriteFrames.add_frame()` 返回 void 不能接收；
   函数不能返回 null 却标注 `-> Array/PackedByteArray`（去掉标注或返回空数组）。
4. **EditorScript 不能 `--headless --script` 运行**，批量工具一律
   `extends SceneTree` + `_initialize()` + `quit(0)`。
5. **ffmpeg Windows 版不支持 glob**（`-pattern_type glob` 报
   Function not implemented），用 `-start_number N -i '%03d.png'` 序列模式。
6. **SelfTest 硬编码动画名**：换动画名（double_jump→jump_air）后要把
   SelfTest.gd 里的期望值同步改掉，否则 2 项失败。
7. **缩放基准不能随动画字典序漂移**：`_first_texture()` 固定用 idle 做
   基准，因为 `get_animation_names()` 返回排序数组，新加动画会改变
   "第一个"，scale 就漂了。
8. **素材目录里源和产物必须分目录**（`player_jump` vs
   `player_jump_jump_crop`），处理脚本清空输出目录重建，混目录会删源帧。

## 快速 Checklist：新增一个动作

- [ ] 源帧放 `assets/animation/<动作名>/`，确认底色类型
- [ ] ffmpeg 拼触摸表挑帧，记下帧号
- [ ] `BuildJumpFrames.gd` 的 GROUPS 加一组，跑脚本
- [ ] 白像素统计 ≈0% + contact sheet 目检无残影
- [ ] `--import` 重导入
- [ ] （帧路径是新的才需要）`BuildAnimations.gd` 注册动画
- [ ] `PlayerVisual.gd` 的 `_ANIM` 表加映射（+`_FALLBACK` 降级 + 视需要加 trigger）
- [ ] 画布高度不在 645~702 区间 → 回查帧处理规格
- [ ] SelfTest 全过，游戏里实测脚底对齐（不浮空不陷入）

## 过程记录

各阶段调参的比对截图（底色判别 / 去底抠像 / 挑帧 / 序列目检）归档在
[`docs/art-pipeline/`](art-pipeline/README.md)，按本文档的流程阶段分组。
参数调不准时先翻对应阶段的图，看上一轮收敛到哪里。
