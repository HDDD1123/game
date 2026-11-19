# 任务4 交付说明（返工版：3 个引擎测试已真跑）

分支意图：`dsh/task4-typing-v05`。本目录是"实际做出来的"与"没做出来的"清单，不含"应该可以"的推断。

## 0. 本轮变化（2026-11-18 返工）

中控在 Godot 4.6.3 上实测出 6 项失败，已修完并**真跑**：

| 问题 | 根因 | 修法 | 结果 |
|---|---|---|---|
| startup 版本判定（3 项失败） | `JSON.parse_string` 把数字解析成 float，代码只认 `TYPE_INT`，真实存档被判成"缺整数版本" | `startup_service.gd` 改为接受"整数值的 float"，非整值才判损坏 | 3 项转绿 |
| 空事实下结论（1 项失败） | `ending_exited_midway` 只要求 `fact_absent ending`，空输入也命中 | `history_renderer.gd` 增加 `has_evidence`：无事实且无计数时直接走中性兜底 | 1 项转绿 |
| 测试期望自相矛盾（2 项失败） | 断言"所有 fixture 的预览模式都带出 preview_only"，但两个 fixture 有 ending 事实，永不可能满足 | 测试改为按证据条件断言（无 ending 事实 **且** `months_played >= 1`），没有放宽数据 | 2 项转绿 |
| （额外发现）`settings_store.set_value` 类型推断 | `var current := load_preferences().preferences` 推断失败 → 整个 settings 分节编译失败，测试静默少跑 14 项 | 显式标注 `Dictionary` | 引擎测试从 34 项变 48 项 |
| （额外发现）偏好范围用 `Vector2` | 分量是 32 位浮点，1.6 存成 1.60000002，读回不等于 1.6 | 改成 `[min, max]` 数组 + `float()` | 精度项转绿 |

真实结果（Godot `4.6.3.stable.official.7d41c59c4`，日志在 `evidence/godot-*.log`）：

```
test_platform_services.gd  -> 48 checks, 0 failures, exit 0
test_narrative_render.gd   -> 66 checks, 0 failures, exit 0
test_onboarding_model.gd   -> 12 checks, 0 failures, exit 0
原有 8 组回归              -> 263 checks, 0 failures, exit 0
（test_core 42 / test_ui 8 / test_building_modules 59 / test_v04_regressions 63 /
  verify_004b 17 / verify_005 27 / test_decision_preview 23 / test_street_workflow 24）
```

平台测试是 48 项而不是中控看到的 34 项：那 34 项是 `settings_store.gd` 编译失败、`_test_settings` 提前中止后的残缺计数；修好后补回 14 项。日志里仍会出现两类 **预期内的** `ERROR: Parse JSON failed`（负向测试故意喂坏 JSON），`SCRIPT ERROR` 为 0。

## 1. 环境

1. **Godot 4.6.3 已装**：`.tools/godot-4.6.3/Godot_v4.6.3-stable_win64.exe`（官方 release 包，`--version` 与中控一致）。已 `--headless --import` 生成 `.godot/` 缓存。
2. **仍无 git**：仓库仍是 tarball 取件（HEAD `631df2c1b7efcd95dda8ccd629bbf66775f6ae04`），没有 `.git`，不能每包提交、不能 bundle。改用 `content-manifest.json` 的**内容哈希**核对。
3. **DSH 会话是低完整性级别**：`SendInput` 被 UIPI 拒绝，后台输入的"真实打字"仍未验证（需要普通权限会话跑 `verify-live.ps1`）。

## 2. 交付状态（按 T4 工作包）

| 编号 | 内容 | 状态 | 证据 / 缺口 |
|---|---|---|---|
| T4-01 | 启动/运行基线与参考 | 研究完成，**计时未做** | `创意候选.md`（2 深入 + 1 补充，9 条带来源观察，6 建筑/4 单位/12 技能） |
| T4-02 | 启动服务与故障反馈 | **通过引擎测试** | `startup_service.gd`；`test_platform_services.gd` 覆盖损坏/版本不符/缺 state/可读/太大/权限分支 |
| T4-03 | 设置与桌面生命周期 | **通过引擎测试** | `settings_store.gd`（原子写、`.bak`、范围截断、拒存自动运行）+ `window_metrics.gd` 纯几何 |
| T4-04 | Windows 输入计数助手 | 构建+自检+协议测试通过，**真实后台输入未验** | `tools/windows-typing/`；`--self-test` PASS；协议测试 2 通过 6 跳过 |
| T4-05 | Godot 输入桥与故障隔离 | 协议/会话清理通过引擎测试，**真实进程 spawn/kill 未测** | `typing_bridge.gd`；`start()` 用文件传输（4.6.3 无子进程管道 API） |
| T4-06 | 生命周期联调 | **未做** | 需要任务1 主UI 开关 + 任务2 SessionController |
| T4-07 | 性能采样与优化 | **未做** | 需要实机长时间采样；不报没有证据的数字 |
| T4-08 | 可重复导出与资源诊断 | 工具可运行，**未导出** | `tools/desktop-delivery/`；未装导出模板，未执行 `--export-release` |
| T4-09 | 宰相向导与反馈组件 | **模型+数据通过引擎测试** | `ui/onboarding/onboarding_model.gd` + `data/narrative/onboarding.json`；无 Control 布局（界面归任务1） |
| T4-10 | 史书事实与结局模板 | **渲染器+数据通过引擎测试** | `platform/narrative/history_renderer.gd` + `data/narrative/`；数据静态校验 OK=32 FAIL=0 |
| T4-11 | 启动与长期实机回归 | **未做** | 需要 10 次热启动 + 2 小时在线观察 |
| T4-12 | 阶段包与交付工具 | 工具+内容清单完成，**阶段包未建** | `content_manifest.py` / `finalize_delivery.py`；无 24/48/72 包 |

> 诚实结论：按"实现+引擎测试都通过"计 **4 个包 = 24 点**（T4-02、T4-03、T4-09、T4-10），其余 4 个包有代码未验证、4 个包未开始。

## 3. 与《四机接口约定》的差异

| 项 | 约定 | 实际 | 原因 |
|---|---|---|---|
| 输入桥读取 | 非阻塞管道读 stdout | 助手 `--out` 写会话文件，桥接 250ms 增量读 | Godot 4.6.3 没有读子进程 stdout 的 API；协议内容/校验/序号语义不变 |
| 关闭方式 | stdin shutdown + 断管道 | `OS.kill(pid)` + 删会话文件 | `create_process` 不连 stdin；助手仍支持 stdin/EOF 退出（已测） |
| 向导/史书 UI | 独立 UI 组件 | 只有模型/渲染器与数据 | 没有 Control 布局；界面装配归任务1 |
| 导出过滤 | 未规定 | `include_filter="*.json"` | 防"编辑器能读、导出后缺 JSON"；实际包内是否已含仍需导出后核对 |

## 4. 现在能复现的验证

```powershell
# 1) 三个任务4 测试 + 8 组回归（真实调用 Godot，日志写到 evidence/）
python apps/desktop/tests/task4/run_task4_checks.py
#   -> 11 条全 PASS；3 个任务4 测试 48/66/12，回归 263

# 2) C# 助手
powershell -ExecutionPolicy Bypass -File tools\windows-typing\build.ps1
tools\windows-typing\bin\TypingCounter.exe --self-test
#   -> exit 0；selftest PASS

# 3) Python 工具
python tests\task4\test_typing_helper.py            # 2 passed, 6 skipped（低完整性无法注入）
python apps\desktop\tests\task4\validate_narrative.py --root .   # OK=32 FAIL=0
python -m unittest discover -s tools\desktop-delivery\tests      # 13 项 OK

# 4) 内容清单与交付清单（无 git，用内容哈希核对）
python tools\desktop-delivery\content_manifest.py --root .
python tools\desktop-delivery\build_manifest.py --root . --json
python tools\desktop-delivery\delivery.py --root . --claims apps\desktop\docs\交付\任务4\claims.json --out apps\desktop\docs\交付\任务4\delivery_detail.json --stamp
python tools\desktop-delivery\finalize_delivery.py --root . --detail apps\desktop\docs\交付\任务4\delivery_detail.json --out apps\desktop\docs\交付\任务4\delivery.json
```

## 5. 仍未做（下一步）

1. **启动基线（T4-01）**：冷/热启动各 10 次，记录进程启动到首个可操作界面的时间，写明硬件/DPI/渲染模式。
2. **性能（T4-07）**：前台/失焦/最小化/事件暂停/输入开启各采一段，给出中位数与峰值。
3. **真实后台输入（T4-04/T4-06）**：在普通权限 PowerShell 跑 `verify-live.ps1`；再把桥接接进主UI 验证"只消耗一次额度"。
4. **导出（T4-08/T4-12）**：装 4.6.3 导出模板 → 干净目录 `--export-release` → 核对包内 JSON 与助手 exe → 阶段包。
5. **长跑（T4-11）**：10 次热启动 + 2 小时在线观察，记录内存趋势与残留进程。

## 6. 明确没做的事

- 没有改 `project.godot`、`ui/main.gd`、`core/`、`runtime/`；没有删任何人的文件。
- 没有做跨局继承、没有接入运行时 LLM、没有购买/上传任何东西、没有碰 Steam。
- 没有删除或迁移任何真实存档；`inspect_saves()` 只读，测试只用临时文件。
