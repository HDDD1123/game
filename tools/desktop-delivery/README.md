# desktop-delivery：无引擎也能用的构建清单 / 导出检查 / 交付工具

本目录只做 **Godot 4.6.3 工程的静态核对与交付打包准备**。它不需要 Godot、git 或 .NET SDK；
也正因为如此，**它不会、也不能声称导出或运行成功**。

- 仓库根：`game-task/`
- 工程：`game-task/apps/desktop/`
- 只用 Python 标准库（3.10+）。
- 所有输出中的文件路径都相对于工程目录或仓库根，不写入本机绝对路径（`export_check.py` 的计划命令是例外：
  它必须给出可执行命令，属于本机诊断输出，不是游戏资源）。

## 快速开始

```powershell
python tools/desktop-delivery/build_manifest.py --root . --text
python tools/desktop-delivery/export_check.py --root . --dry-run
python tools/desktop-delivery/startup_notes.py --root . --stdout
python tools/desktop-delivery/delivery.py --root . --claims <claims.json>
python -m unittest discover -s tools/desktop-delivery/tests -v
```

## 脚本

### `build_manifest.py` — 静态构建清单

扫描 `apps/desktop/`，生成文件清单（相对路径、字节数、SHA-256）、扩展名/分组统计，
并做以下静态检查：

- 必需资源类别：`project.godot`、`export_presets.cfg`、`data/*.json`、`ui/*.tscn`；
  字体/`assets/` 属于可选类别，缺失只记 INFO。
- 主场景存在、Windows 导出预设存在、预设输出目录状态。
- 引擎版本线索：`project.godot` 的 `config/features` 必须为 **4.6 系**；
  `export_presets.cfg` 有版本线索时交叉核对（通常没有，只记 INFO，精确 4.6.3 需实机 `godot --version`）。
- 绝对路径泄漏：扫描 `.json/.tscn/.cfg/.gd` 中的 Windows 盘符、UNC、`/home|/Users|/mnt|/opt|/var`、
  `file:///`；命中即 FAIL，并给出 `文件:行`。
- `res://` 引用：静态提取并核对工程内文件是否存在（缺失只 WARN，可能是运行时拼接）。
- 导出过滤诊断：读 `export_filter`/`include_filter`/`exclude_filter`，判断 `data/*.json` 等
  非资源文件是否会被排除。未覆盖时只 WARN，文案明确写「按默认规则包内会缺 JSON」+
  「本项目 4.6.3 实际导出包曾包含建筑 JSON，需实机核对」，**不断言导出失败**。
- 助手位置：`tools/windows-typing/` 在 Godot 工程之外，不会进 PCK，只记 INFO 提醒随 exe 分发。

参数：

| 参数 | 说明 |
|---|---|
| `--root <dir>` | 仓库根（默认从脚本位置/当前目录向上找 `apps/desktop/project.godot`） |
| `--text` | 人类可读输出（默认） |
| `--json` | 确定性 JSON（文件顺序、键顺序固定；`generated_at_utc` 默认 `null`） |
| `--out <path>` | 写入文件；stdout 只留提示 |
| `--stamp` | 写入 `generated_at_utc`（默认关闭，保证同输入同字节输出） |

退出码：`0` 无 FAIL；`1` 有 FAIL；`2` 用法/路径错误。

### `export_check.py` — 导出检查（默认 dry-run）

1. 检测 Godot：`--godot`（文件或目录）→ `GODOT_BIN` → `PATH`（godot/godot4）→
   `%PROGRAMFILES%\Godot*`、`%LOCALAPPDATA%\Programs\Godot*`、`C:\Godot`。
2. 找不到：输出 `BLOCKED: godot not found`、`status: blocked`、`reason: godot-not-installed`，
   并仍打印**计划命令**（不执行），退出码 `2`。
3. 找到：按 **godot-export 技能**顺序打印（`--run` 才执行）：
   `--version` → `--export-pack` 冒烟（不需要模板）→ `--main-pack` 跑 300 帧抓 SCRIPT ERROR →
   `--export-release` 模板导出 → 核对产物存在且非空。
4. 预检会提示：模板目录缺失、输出目录不存在（`--run` 自动创建）、`.godot/` 导入缓存缺失、
   预设名大小写不匹配。

参数：`--root`、`--godot`、`--preset`（默认第一个预设）、`--out`、`--pack`、`--timeout`、
`--run`/`--dry-run`（默认 dry-run）、`--json`、`--out-report`、`--stamp`。

退出码：`0` dry-run 计划成功或 `--run` 全部通过；`1` 预检/预设名/导出失败；`2` 找不到 Godot 或用法错误。

### `delivery.py` — 合成 `docs/交付/任务4/delivery.json`

把构建清单（`--manifest`，省略则现场生成）+ 声明文件（`--claims`，必填）合成交付 JSON：
`task`、`git_commit`、`engine_version`、`modules`、`tests`、`untested`、`artifacts`、
`manifest`（含 sha256）、`diagnostics`（静态检查摘要）。

硬规则：

- `tests[].result == "passed"` 必须同时满足 `ran == true`、`evidence` 存在且非空；
  否则整条降级 `unverified`，脚本退出码 `1`。**只有真实跑过的才能写 passed。**
- 每个 claim 都必须有 `evidence`；缺证据一律 `unverified`。
- 没有 git（本机）时 `git_commit: null`，并写 `git_commit_unavailable_reason`；不伪造。
- `untested` 自动补充：git 不可用、未执行引擎、预设无版本线索；claims 的未测项也保留。
- 缺 `artifacts` 文件、引擎版本不一致、清单有 FAIL、测试 failed → 状态 `fail`，退出码 `1`。

声明文件示例：

```json
{
  "task": {"id": "T4-08/T4-12", "title": "可重复导出与资源诊断", "stage": "24"},
  "modules": [
    {"name": "core", "version": "0.5", "path": "apps/desktop/core/kingdom.gd"}
  ],
  "tests": [
    {
      "id": "manifest-static",
      "name": "真实 ROOT 静态清单",
      "command": "python tools/desktop-delivery/build_manifest.py --root .",
      "ran": true,
      "result": "passed",
      "evidence": "apps/desktop/docs/交付/任务4/evidence/build-manifest.json"
    }
  ],
  "untested": ["Godot 实机导出与启动"],
  "artifacts": ["dist/KingdomDesktop-24.zip"]
}
```

参数：`--root`、`--manifest`、`--claims`（必填）、`--out`（默认
`apps/desktop/docs/交付/任务4/delivery.json`）、`--stdout`、`--json`、`--git-commit`、`--stamp`。

退出码：`0` 全部有证据且无硬失败；`1` unverified/failed/缺产物/引擎不一致；`2` 用法/文件错误。

### `startup_notes.py` — 中文启动说明草稿

从 `project.godot`、`export_presets.cfg`、构建清单生成 `docs/交付/任务4/启动说明.md`：
引擎版本、主场景、编辑器打开方式、导出命令、包内 JSON 过滤注意、常见错误表、
静态已核对/未验证清单、复现命令、交付边界。**顶部固定声明"未实机验证"，不会写"已验证可运行"。**

参数：`--root`、`--manifest`、`--out`（默认 `apps/desktop/docs/交付/任务4/启动说明.md`）、`--stdout`。
退出码：`0` 已生成；`1` 静态清单有 FAIL（仍会生成，顶部带警告）；`2` 用法/路径错误。

### `tests/test_delivery_tools.py`

`unittest`，用临时目录造 3 类假仓库（正常 / 版本不符 4.7 / 绝对路径泄漏），
通过 subprocess 调用真实脚本，断言退出码与关键字；另外覆盖 export_check blocked / 预设名大小写、
delivery 的"passed 必须有证据 + ran"、缺产物、启动说明不含"已验证可运行"。

## 没有 Godot / git 时哪些结论有效

**有效（静态）：** 文件清单与哈希、资源类别是否齐全、主场景/预设是否存在、4.6 系版本线索、
绝对路径泄漏、`res://` 引用、导出过滤规则、助手是否在工程外。

**无效（必须实机）：** 导出是否成功、产物是否可启动、启动时间、窗口/DPI、存档读写、
后台输入、包内 JSON 是否真的存在（静态过滤规则与 4.6.3 实机结果可能不同）、
模板是否安装正确、精确引擎补丁版本。

**本机没有 git：** `git_commit` 为 `null`；`delivery.py` 只尝试读 `.git`，读不到就如实说明，不编造。

## 已知边界

- 绝对路径扫描是文本正则，注释/示例里的盘符也会报；按任务要求"不过度聪明"，直接给 `文件:行` 人工确认。
- `/root`、`/tmp` 等 NodePath 常见路径不在 POSIX 泄漏规则内，避免把 `get_node("/root/...")` 误报。
- 模板目录按 `%APPDATA%\Godot\export_templates` 检查；自定义模板/其他编辑器安装位置需人工确认。
- `tests` 依赖外部 godot 可执行真实运行；本仓库测试不安装、不下载任何东西。
- 本目录不修改 `core/`、`ui/main.gd`、`project.godot`、`third_party/`、`data/narrative/`。
