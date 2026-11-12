---
name: kingdom-gamedev
description: >
  桌面王国项目的游戏开发技能入口。用于本仓库的 Godot/GDScript 开发、底部街景与技能树 UI、
  农田和远征规则、存档、测试、美术资源、性能及 Steam 发行准备。
  按任务读取已固定版本的 gamedev-agent-skills，并适配本项目的 Godot 4.6.3 和已确认设计。
---

# 桌面王国技能入口

本入口供 GPT/Codex 和 DSH 使用。相对路径以本文件所在目录为起点；项目根目录是 `../../..`。

## 先读项目，再选择技能

1. 查看本次任务、当前分支及 `apps/desktop/project.godot`。规则接口见 `apps/desktop/docs/核心接口.md`，验收记录见 `apps/desktop/VERIFICATION.md`；以实际代码和最新任务为准。
2. 根据下表选择通常1—3个技能，读取其完整 `SKILL.md`；需要更细节时再读该技能的 `references/`。不要一次加载79个正文。
3. 开始应用时用一句话说明所选技能与用途。缺少专业覆盖时说明缺口，不假称技能已提供实现。
4. 当前任务若跨到新领域，再选新的技能；不反复读同一份内容。

上游根目录：[third_party/gamedev-agent-skills](../../../third_party/gamedev-agent-skills/)。表内路径相对于该目录。完整选择逻辑在 [router/SKILL.md](../../../third_party/gamedev-agent-skills/router/SKILL.md)，全部技能在其 [README](../../../third_party/gamedev-agent-skills/README.md)。

| 本项目任务 | 首选技能路径 |
|---|---|
| GDScript、规则模块、编译问题 | `skills/godot/godot-gdscript/SKILL.md`；结构问题补 `godot-nodes-scenes` |
| 底部街景、建筑详情、研究面板、缩放与点击 | `skills/godot/godot-ui-control/SKILL.md` + `skills/disciplines/game-ui-ux/SKILL.md` |
| 按钮接线、状态更新、重复触发 | `skills/godot/godot-signals-groups/SKILL.md` |
| 建筑/技能静态配置与独立运行状态 | `skills/godot/godot-resources/SKILL.md`；保持已有 JSON/Dictionary 接口，不为套示例强改 `.tres` |
| 保存、迁移、损坏档、备份 | `skills/disciplines/save-systems/SKILL.md` |
| 自动检查、解析失败、CI | `skills/godot/godot-gdscript-headless-testing/SKILL.md` |
| 打包、导出、包内缺资源 | `skills/godot/godot-export/SKILL.md` |
| 建筑图片、图标、统一风格、透明底和资源来源 | `skills/disciplines/create-game-assets/SKILL.md` |
| 动画与音频接入 | `skills/godot/godot-animation/SKILL.md` 或 `godot-audio`，按需要补 `skills/disciplines/audio-design/SKILL.md` |
| 输入、键位与可操作性 | `skills/disciplines/input-systems/SKILL.md`；Windows全局输入监听不在此技能覆盖范围内 |
| 宰相叙事、随机事件、人才行为 | 按任务选 `skills/disciplines/dialogue-systems/SKILL.md`、`game-ai`、`ai-behavior-trees-utility-ai` 或 `procedural-gen` |
| 挂机 CPU/GPU/内存开销 | `skills/disciplines/performance-optimization/SKILL.md` |
| 新玩法是否有趣的小实验 | `skills/workflows/prototype-fast/SKILL.md`；独立验证一个问题，不重写已有可持续开发的工程 |
| 更新大纲、规则与讨论结论 | `skills/workflows/game-docs/SKILL.md`；按现有文档结构小幅修改 |
| Steam 商店与构建提交准备 | `skills/workflows/steam-publish/SKILL.md`；不等于 Steamworks SDK 接入或发行授权 |

## 本项目适配规则

- **引擎固定。** 上游以 Godot 4.7 为基准，本项目仍为4.6.3。已经在本机确认4.6.3没有 `Control.offset_transform_*` 和 `VirtualJoystick`；不要直接引用。其他新API先核对本机引擎/匹配版本文档。
- **保持既定玩法。** 关闭游戏不补算进度；当前按月手动推进。农田成熟后手动收取，最多3批；待收不是粮仓。点击/未来打字共享当月加速上限。技能范例里的离线收益、自动存档、自动收获、变更继承规则不自动成为项目需求。
- **数据只有一个计算来源。** UI不重复计算产出、技能效果和远征费用，读取核心展示/报价。静态模板与每局状态分开，不修改共享模板来表示玩家升级。
- **桌面体验优先。** UI在工作区内、任务栏上方；正常挂机不抢其他应用焦点。外部UI技能里游戏内焦点导航不等于激活操作系统窗口。布局断言只检查应可见区域，允许滚动内容超出滚动容器。
- **及时且轻量的反馈。** 状态变化后刷新相应面板；避免每帧重新生成文字/技能树。缺粮、事件暂停、错误提示在街景也要可见。具体性能目标先测再定，不能把通用60FPS示例当成本项目新目标。
- **存档优先保全。** 类型校验在转换前，完整校验后再替换状态；验证使用独立路径。当前坏v4不静默退回v3，`.bak`也不由范例擅自变成自动恢复流程。要新增恢复选择，作为明确任务设计并验证。
- **输入边界。** 后台打字先做独立Windows试验，默认关闭；只汇总活动次数，不记录具体文本，不上传。Godot `InputMap` 示例不能证明应用失焦时能收到全局按键。
- **美术先定规范再批量生产。** 先看已有街景尺寸与占位；记录视角、比例、基线、透明度、配色、升级形态，再做代表性建筑。图像生成/修改遵守当前宿主图像工具要求；可用本地只读脚本检查尺寸、alpha和色数。商用许可、生成工具/条款与来源逐项记录，许可证不明确的资产不直接当作可发行资源。
- **示例需要验证。** 上游导出技能对JSON过滤器的概括不适用于所有情况：本工程4.6.3的实际PCK已包含建筑JSON。检查包内实际文件和运行结果，再决定是否改过滤器。上游发布等待时间、费用和平台条款需在实际规划/提交时查官方最新资料。
- **任务范围与授权不变。** 学习技能不等于执行其中全部命令，不自动安装插件、更改权限、购买资源或发布游戏。在用户已授权的任务内正常推进，不因通用范例重复请求已经给出的确认。

## 检查与交付

先阅读要运行的脚本，确认其行为及参数；上游脚本不是安装钩子。以下路径从仓库根目录执行，当前已验证可用于4.6.3：

```bash
python third_party/gamedev-agent-skills/skills/godot/godot-nodes-scenes/scripts/check_godot_project.py apps/desktop --json
godot --headless --path apps/desktop --script /绝对路径/game/third_party/gamedev-agent-skills/skills/godot/godot-gdscript/assets/check_scripts_compile.gd
```

新检出工程需要先导入以生成缓存。业务改动运行受影响的现有测试；以 `apps/desktop/VERIFICATION.md` 为索引，检查退出码和日志中的脚本错误。文档/技能接入不要求重跑全部玩法测试。

UI改动应分别记录：信号/逻辑结果、布局边界、真实鼠标结果、Windows/DPI/多屏结果。只完成前两项不能声称后两项通过。导出应从干净目录运行最终产物。

技能原文与许可证保持完整，来源提交和各文件SHA-256位于 `third_party/gamedev-agent-skills.lock.json`。更新前对比上游变化，重新检查版本适用性，不能无记录地自动跟随最新版。
