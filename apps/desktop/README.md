# 桌面王国 v0.4.2：底部街景与经营决策原型

这是一份给 DSH 接手的源码工程，不是已经打包的 Windows 游戏。
当前源码分支为 `codex/kingdom-playability-v042`，工程位置是 `apps/desktop/`。保留原有工作，通过Git合入；Windows试玩包由DSH按 [任务006](docs/任务006_优化接入与美术准备.md) 导出验收。

## 已完成

- Godot 4 的独立经营规则内核：住房、农业、人口、流民、饥饿、远征、铁匠铺、成就与记录。
- 底部街景7个固定地块，普通管理视图、窗口记忆、置顶和关闭保存提示。
- 农田手动收获，最多暂存3批；点击助耕，每月共享20%加速上限；农田详情可升级。
- 三棵基础建筑技能树，解锁、点数和可用状态即时刷新。
- 小窗可直接接纳/拒绝流民；预览口粮、木材与床位代价，以及推进前的饥饿风险。
- 本地 JSON 存档：格式校验、临时文件替换、上一份备份；读取不补算离线时间。
- 流民在前期日程结束后继续到来：已过去23个月开始，每3个月6人。
- 农业改善成本暂改为18×当前等级，旱季暂改为每年7—9月。

新增数值属于试验方案。资源过剩尚未完全解决；没有加入新的建筑、魔王、自然衰老或自动推进。

## 在 Godot 中运行

使用 Godot 4.6.3 标准版（GDScript，不需要 .NET）。在项目管理器导入本目录的 project.godot，按 F5 运行。首次导入可能需要等待编辑器扫描脚本。

本次修订已通过Linux规则、接线和布局几何检查；Windows新版实机验收仍由DSH完成。建筑当前仍为文字占位。自动走时、后台打字、透明/鼠标穿透尚未接入。

## 命令行检查

在项目目录执行（Godot 程序不在 PATH 时，用其完整路径）：

```text
godot --headless --path . --script res://tests/test_core.gd
godot --headless --path . --script res://tests/test_ui.gd
godot --headless --path . --script res://tests/test_building_modules.gd
godot --headless --path . --script res://tests/test_v04_regressions.gd
godot --headless --path . --script res://tests/verify_004b.gd
godot --headless --path . --script res://tests/verify_005.gd
godot --headless --path . --script res://tests/test_decision_preview.gd
godot --headless --path . --script res://tests/test_street_workflow.gd
```

当前实测263项，0失败，详情见 [VERIFICATION.md](VERIFICATION.md)。测试使用独立临时存档/窗口配置。Windows标准版可使用随包的console程序查看日志，同时检查脚本错误，不能只看退出码。

## 交接顺序

1. 读取根目录AGENTS.md和本轮任务006，在工作分支合入源码。
2. 运行相关检查；规则接口见 [核心接口](docs/核心接口.md)。
3. 用真实鼠标验证小窗决策、研究、收粮和存档，再从干净目录运行导出的EXE+PCK。
4. 提供新的ZIP和实测记录，不合并main。

当前桌面存档格式4，可在v4文件不存在时迁移桌面v3旧档；旧文件保留，迁移后手动保存生成v4。网页格式2不支持导入。关闭与读取都不补算离线时间；启动后点击“读取”恢复上次手动存档。

## 目录

```text
core/balance.gd       集中数值与地点配置
core/kingdom.gd       无窗口依赖的经营规则
core/save_store.gd    本地文件存档桥接
core/farm_buffer.gd   成熟批次与助耕额度
core/building_skills.gd 建筑技能配置与效果
ui/main.tscn          主场景
ui/main.gd            街景、管理、详情和研究面板
tests/               规则和信号接线检查
docs/                分工、接口与设计记录
```

本包代码为本项目编写，未附第三方美术或音乐。Godot 引擎本身使用 MIT 许可；发行前在关于/许可证页面保留其要求的许可说明。
