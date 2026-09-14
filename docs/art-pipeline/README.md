# 美术处理过程记录

本目录是 [`docs/animation_pipeline.md`](../animation_pipeline.md) 所述工艺的**过程实证**：
每轮调参留下的比对截图，用来回答「当时为什么这么调、调到什么程度算收敛」。

源图来自开发期的 `.preview/` 目录（已由 `.gitignore` 排除，不入库）。
这里按工艺阶段归档了有回溯价值的 78 张。

> 调参调不准时，先翻对应阶段的图 —— 上一轮收敛到哪里，一眼能看到。

---

## 01-keying/ — 底色判别与抠像调参

对应工艺文档「一、素材要求与底色类型」「三、帧处理 · 去白底 / 去烟雾残影」。

| 文件 | 看什么 |
|---|---|
| `test5_magenta.png` `test5_white.png` `test5_black_white.png` `test5_black2_white.png` | 同一帧换洋红底 / 白底 / 黑底，比较哪条抠像路径边缘最干净 |
| `test001_magenta.png` `idle1_magenta.png` | 单帧洋红底试抠效果 |
| `compare_white_removal.png` `compare_white_removal_small.png` | 去白底前后同框对照（原图 vs `_bake_alpha` 产物） |
| `tune_alpha.png` `tune_small.png` | `FG_LUMA` / `BG_LUMA` 阈值扫参结果 |
| `flatblack_zoom.png` `player_idle_flatblack.png` | 纯黑底放大目检 —— 白晕与残留描边在这里最明显 |
| `player_idle_feathered.png` `player_idle_feathered_zoom.png` | 边缘羽化（`FEATHER=8`）效果 |
| `idle1_head.png` | 头发丝区域放大，确认形态学开运算（`ERODE_R=4`）没吃掉细结构 |
| `nospear.png` | 武器剔除版本对照 |

## 02-animation/ — 挑帧、帧处理与序列目检

对应工艺文档「二、挑帧：先看全貌再选帧」「三、帧处理 · 统一窗口与规格」「六、验证 · contact sheet 目检」。

| 文件 | 看什么 |
|---|---|
| `sheet.png` `sheet_bg.png` `sheet_cropped.png` `sheet_final.png` | 60 帧 contact sheet，逐轮处理后的全貌（挑帧阶段的原始依据） |
| `jump_3seg.png` | 跳跃三段（一段 / 二段 / 下落）速度设计对照 |
| `jump_up.png` `jump_phase1.png` `jump_phase2.png` `jump_transition.png` `jump_landing.png` `jump_fall_1.png` `jump_fall_2.png` `jump_grid.png` | 起跳→腾空→落地逐帧目检，查残影与构图统一性 |
| `dj_all.png` | 二段跳全套帧 |
| `run_strip.png` `player_run_strip.png` | 跑步序列条形图，看节奏与循环接缝 |
| `run_0.png` ~ `run_5.png`、`run_check_0.png` ~ `run_check_3.png` | 跑步逐帧检查 |
| `run_foot_fix.png` `run_tune_single.png` | 脚底对齐修正前后对照 |
| `player_idle_shot.png` `player_idle_zoom.png` `player_idle_zoom2.png` `idle10.png` `idle1b.png` `land_idle.png` | idle 基准帧与落地衔接 |
| `z1.0.png` `z2.0.png` `z3.0.png` `zoom1.5.png` `zoom2.0.png` `zoom2.5.png` `zoom08_check.png` | 缩放基准扫参，确认画布高度落在 645~702 区间 |
| `left_end_fixed.png` | 画布左侧边界修正 |
| `player.png` | 原始素材单帧 |

## 03-verify/ — 游戏内验证与 idle 清理快照

对应工艺文档「六、验证」。

| 文件 | 看什么 |
|---|---|
| `double_jump.png` `fall_down.png` | 实机截图 —— 二段跳、下落攻击的最终观感 |
| `check1.png` `check2.png` `check3.png` | 调试期检查截图 |
| `001.png` ~ `010.png` | `player_idle` 清理前的一版帧快照（源自 `.preview/clean_backup/`） |

---

## 复现方式

帧处理工具在 `src/tools/`（Godot 脚本），素材预处理的 Python 辅助脚本在 `tools/`。
命令行用法与参数说明见 [`docs/animation_pipeline.md`](../animation_pipeline.md)。
