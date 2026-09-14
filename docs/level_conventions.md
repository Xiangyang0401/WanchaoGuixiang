# 关卡空间约定（所有地图必须遵守）

> 这些约定的目的：让所有关卡共享同一套"空间参照系"——
> 基准地面永远在第 9 行、入口永远在 (96, 224)、出口永远贴 x=32 / x=1280。
> 跨关卡对齐靠约定，不靠肉眼。

## 坐标系与网格

- 一格 = 32px（`GameConfig.TILE_SIZE`）
- 关卡场景根节点在原点 (0,0)，**不要移动关卡根节点**
- 第 N 行 = y ∈ [N×32, (N+1)×32)；第 N 列同理

## 主地面基准线：第 9 行

全项目的主地面顶面统一在**第 9 行**（顶面 y=288px），源自 Battlefield01
的主地面（x -13~91、第 9 行顶面、往下填实到 17 行）。

- 画新地形时从第 9 行往上搭平台、往下填实
- 关卡可以有局部高台/低洼，但**"主通行地面"必须在第 9 行**，
  这样跨关卡的高度感、跳跃节奏完全一致
- 模板 `TemplateLevel.tscn` 预铺了第 9 行的一行 solid 作为起画参照，
  开工后按需增删，但至少保留一段与入口/出口衔接

## 标准点位（模板已预置）

| 节点 | 坐标 | 用途 |
|---|---|---|
| `Entry_default` | (96, 224) | 默认入口 / 复活点（兼 `is_default_respawn`） |
| `Entry_from_prev` | (64, 224) | 从上一关（更小的图）进入的落点 |
| `Entry_from_next` | (1280, 224) | 从下一关（更大的图）进入的落点 |
| `ExitLeft` | (32, 128) | 左边界切图触发器，`direction=-1` |
| `ExitRight` | (1280, 128) | 右边界切图触发器，`direction=1` |

说明：

- 入口 y=224 在第 7 行，站在第 9 行地面上方 1 格——玩家从入口落下正好踩地
- 1280 是模板默认关宽（40 格）；**关卡加宽后 `Entry_from_next`/`ExitRight`
  跟着挪到右端，但 y 不变**；`Entry_from_prev`/`ExitLeft` 永远贴左端
- Exit 的 `target_level` 留空时编辑器里显示红色警告，填对注册表里的 id 变青色
- 建议对 Exit 右键 → Lock Children，防止拖动时误选 CollisionShape2D

## 背景图

`Background`（`LevelBackground.tscn` 实例）用默认 `fill=LEVEL` 模式时
**自动按本关边界缩放铺满，不需要也不应该手动对坐标**。
换关只换 texture，不调位置缩放。

## 编辑器辅助工具（模板已预置，运行时自隐藏）

- `LevelBoundsGuide`：红区=玩家会离开镜头的范围，绿线=传送点建议位置，
  蓝线=相机中心可移动范围。铺地形时照着绿线摆 Exit
- `DesignRuler`：假主角标尺（原点=脚底），站在基准地面上。
  摆平台时看它身上的跳跃高度线/冲刺距离线，回答"这跳得上去吗"

## 新关卡 Checklist

- [ ] 复制 `TemplateLevel.tscn` 改名
- [ ] 根节点改 `level_id`（必须与 `LevelRegistry` 键一致）和 `display_name`
- [ ] 地形：主地面顶面对齐第 9 行
- [ ] 关卡加宽后把 `Entry_from_next` / `ExitRight` 挪到右端（y 不变）
- [ ] 每个 Exit 填 `target_level`（+ 对侧关卡加对应的 Entry/Exit）
- [ ] Background 拖入本关 texture
- [ ] `SelfTest.tscn` 全过
