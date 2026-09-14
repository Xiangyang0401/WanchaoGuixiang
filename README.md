# 万潮归乡 · 项目说明

## 在编辑器里怎么看、怎么改

### 关卡在哪编辑

**关卡场景文件在 `scenes/levels/`，双击打开就能画。**

- `Battlefield01~04.tscn` —— 古战场四张图，序章从 `battlefield_01` 开始
- `TemplateLevel.tscn` —— 新建关卡的模板，**不要直接改它**，复制一份开工

每张关卡场景的结构：

```
Battlefield01 (Level)
  ├── Ground      (TileMapLayer)  ← 实心地形，画这里
  ├── Platforms   (TileMapLayer)  ← 单向平台，可从下方跳上来
  ├── Decor       (TileMapLayer)  ← 纯装饰，无碰撞
  ├── Entry_*     (LevelEntry)    ← 入口点 / 复活点
  ├── Exit*       (LevelExit)     ← 边界切图触发器
  ├── Enemy_*     (Enemy)         ← 怪
  └── Bench_*     (Bench)         ← 长凳检查点
```

选中 `Ground`，底部会出现 TileMap 面板，从图集里选瓦片直接刷。
图集是 `assets/placeholder/tileset.tres`，5 种瓦片：

| 序号 | 名称 | 用途 |
|---|---|---|
| 0 | solid | 实心地形 |
| 1 | solid_alt | 实心地形（深色，做层次） |
| 2 | oneway | 单向平台（只有上边缘有碰撞） |
| 3 | hazard | 危险区外观（**无地形碰撞**，伤害靠单独的 Area2D） |
| 4 | deco | 纯装饰 |

### 为什么 Main.tscn 打开是空的

**这是设计如此，不是 bug。** `Main.tscn` 只有一个 `LevelManager`，
关卡是运行时按 `start_level` 加载进来的。所以编辑器里看不到任何地图。

想改运行时从哪张图开始：选中 Main 根节点，改 `start_level` 属性。

### 想试跑某张图，不用回 Main

**在关卡场景里直接按 F6**，会自动补上玩家、相机、HUD，从这张图开始玩。
这是 `Level._ensure_standalone_runnable()` 做的，正常流程下不会触发。

改完地形立刻 F6，不用切回 Main 改 `start_level` 再 F5。

---

## 坐标约定（很重要）

**`LevelEntry` 和长凳检查点存的是「玩家中心」坐标，不是地面坐标。**

主角高 4 格。如果把入口摆在地面格的中心，玩家下半身会陷进地板，
落地时被物理挤上来，复活位置就和你摆的位置对不上。

摆入口时：**让 Marker 的位置 ≈ 玩家站好时身体中心的高度**，
也就是脚下那格顶面往上 2 格。

代码里不要自己算这个偏移，用 `GameConfig.player_center_offset_y()`。
它按当前主角身高返回「格中心 → 玩家中心」的差值，改主角尺寸时全项目自动跟。
长凳也已经内置了这个补偿，`Bench.respawn_offset_tiles` 只填额外微调。

---

## 世界尺度（改之前先读这段）

`GameConfig.PLAYER_TILE_WIDTH / PLAYER_TILE_HEIGHT` 是**关卡设计的分辨率基准**，
当前 2×4 格。它决定的不只是主角多大，而是 1 格能表达多细的地形：
1 格 ≈ 主角半个身位，所以窄缝、单格台阶、齐胸矮墙都画得出来。

**改这两个常量的连锁反应：**

| 跟着变的东西 | 处理方式 |
|---|---|
| 碰撞体 / 受击框 / 攻击框 / 外观 | 自动（`Player._apply_body_size()`） |
| 交互探测半径 | 自动（`Interactor.radius_tiles = 0` 时按身高取） |
| 入口 / 检查点的落脚补偿 | 自动（`GameConfig.player_center_offset_y()`） |
| **跳跃高度 / 跑速 / 冲刺距离** | **手动**，改 `data/player/default_movement.tres` |
| **敌人 size_tiles / 移速** | **手动**，改 `data/enemies/*.tres` |
| **已画好的地图** | **手动**，通道净空和平台落差要重新审 |

手感参数不会自动跟，因为「距离」和「主角多大」是两个独立的设计决策。
但**必须一起改**：主角翻倍而跳跃不变，等于跳跃能力砍半。

衡量手感看**身位**而不是格数：

```
一段跳高 = jump_height_tiles / PLAYER_TILE_HEIGHT
参考值：空洞骑士 ≈ 2.4 身位，蔚蓝 ≈ 2.6 身位
当前值：1.6 身位（偏保守）
```

---

## 命令行工具

所有工具都以**场景**方式运行，不要用 `--script`。
原因：`--script` 模式下 autoload（GameConfig / EventBus / GameState）不加载，
凡是引用它们的脚本都会编译失败，且失败得很隐蔽（生成出没挂脚本的裸节点）。

```bash
GODOT="/e/Godot/Godot_v4.6.1-stable_win64_console.exe"

# 系统自检（改完核心系统必跑）
"$GODOT" --headless --path . res://scenes/SelfTest.tscn

# 生成占位美术 + TileSet（需要跑两趟，中间夹一次 --import）
"$GODOT" --headless --path . res://scenes/tools/GeneratePlaceholderAssets.tscn
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . res://scenes/tools/GeneratePlaceholderAssets.tscn

# 为 LevelRegistry 里缺文件的关卡生成模板（已存在的会跳过，不会冲掉你画的）
"$GODOT" --headless --path . res://scenes/tools/GenerateLevelStubs.tscn
```

---

## 新增一张地图

**新关卡一律复制 `scenes/levels/TemplateLevel.tscn` 开工**（不要用空白场景从零画）。
模板里已经固化了全项目统一的空间约定：

| 约定 | 值 |
|---|---|
| 主地面顶面（基准线） | **第 9 行**（y=288px），模板预铺了一行，画完可擦 |
| `Entry_default`（默认入口/复活点） | (96, 224) |
| `Entry_from_prev`（上一关进来） | (64, 224) |
| `Entry_from_next`（下一关进来） | (1280, 224) |
| `ExitLeft` / `ExitRight` | 已摆好（x=32 / x=1280），Inspector 里填 `target_level` 即用 |

模板还预置了：`Background`（texture 留空，拖图即用）、
`LevelBoundsGuide`（红/绿边界线）、`DesignRuler`（假主角标尺，站在基准地面上）。

步骤：

1. 复制 `TemplateLevel.tscn` 改名，**或**在 `src/world/LevelRegistry.gd` 加一行后
   跑 `GenerateLevelStubs.tscn` 生成模板
2. 改根节点的 `level_id` / `display_name`
3. 对着基准地面（第 9 行）和 DesignRuler 标尺画地形、摆平台
4. 给 Exit 填 `target_level`（填之前显示红色警告，填对变青色）
5. 跑一次 `SelfTest.tscn`——它会检查注册表里每个 id 的文件都真实存在、
   每个出口都指向已注册的关卡

空间约定的详细依据见 `docs/level_conventions.md`。

---

## 新增/重制角色动作动画

完整工艺流程见 **`docs/animation_pipeline.md`**（素材底色类型判别、
帧处理工具参数、去烟雾算法、SpriteFrames 注册、PlayerVisual 接入、
验证三件套、踩坑记录）。做动画之前先读它，不要凭感觉重踩一遍坑。

---

## 调试

游戏里按 **F1** 开调试面板：能力阶段下拉、相机 zoom 滑块、无敌开关、
回满血 / 自杀 / 回复活点、单个能力开关、实时状态。

相机 zoom 拖到舒服的值之后，写进 `src/core/GameConfig.gd` 的 `camera_zoom`。

### 相机偏移「不生效」时

`Camera2D` 在**限位框比视口还小**时会把相机钉死在限位框中央，
此时 offset / lookahead / 跟随全部失效。

`PlayerCamera._refresh_limits()` 已经处理了这种情况：
某个轴的关卡尺寸小于视口时自动放开该轴的限位。
代价是会露出关卡外的空白——这时候要么把图画大，要么把 zoom 调上去。

## 按键

| 键 | 功能 |
|---|---|
| A/D 或 ←/→ | 移动 |
| 空格 | 跳 / 二段跳 / 滑翔（成熟阶段） |
| Shift | 冲刺 |
| 鼠标左键 | 攻击 |
| F | 交互 |
| F1 | 调试面板 |
