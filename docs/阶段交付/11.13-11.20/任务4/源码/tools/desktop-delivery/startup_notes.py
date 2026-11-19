#!/usr/bin/env python3
"""生成中文启动说明草稿（docs/交付/任务4/启动说明.md）。

内容只从 project.godot / export_presets.cfg / 构建清单静态推导，并明确标注
"未实机验证"。不会写"已验证可运行"。

用法：
    python tools/desktop-delivery/startup_notes.py --root .
    python tools/desktop-delivery/startup_notes.py --root . --stdout

退出码：0 = 已生成；1 = 静态检查有 FAIL（仍会生成，但顶部有警告）；2 = 用法/路径错误。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import build_manifest as manifest_tool
import delivery_common as common
from delivery_common import (
    EXPECTED_ENGINE_SERIES,
    EXPECTED_ENGINE_VERSION,
    TOOL_VERSION,
    ToolError,
)

DEFAULT_OUT = "apps/desktop/docs/交付/任务4/启动说明.md"


def _md_code_block(lines: list[str], language: str = "powershell") -> list[str]:
    return ["```" + language, *lines, "```"]


def _preset_hint(manifest: dict) -> dict:
    presets = manifest.get("presets") or []
    if presets:
        return presets[0]
    return {"name": "(未找到预设)", "platform": "(未知)", "export_path": ""}


def build_notes(manifest: dict, godot_found: str | None) -> str:
    project = manifest.get("project") or {}
    engine = manifest.get("engine") or {}
    preset = _preset_hint(manifest)
    summary = manifest.get("summary") or {}
    diagnosis = manifest.get("export_filters") or {}
    inputs = manifest.get("inputs") or {}

    project_name = project.get("name") or "(未命名)"
    main_scene = project.get("main_scene") or "(未配置)"
    preset_name = preset.get("name") or "(未找到)"
    export_path = preset.get("export_path") or "builds/windows/KingdomDesktop.exe"
    uncovered = []
    for item in diagnosis.get("presets") or []:
        uncovered.extend(item.get("json_uncovered") or [])
    uncovered = sorted(set(uncovered))

    lines: list[str] = []
    lines.append("# 桌面王国 · 阶段包启动说明（草稿）")
    lines.append("")
    lines.append(
        "> **本文件由脚本静态生成，不是运行/导出成功证明。**  "
        "文中命令与结论来自 `apps/desktop/project.godot`、`apps/desktop/export_presets.cfg` "
        "和构建清单的静态核对；**没有在实机上启动、导出或验收过**。"
    )
    lines.append(">")
    lines.append(
        f"> 生成工具：`tools/desktop-delivery/startup_notes.py` v{TOOL_VERSION}；"
        f"输入 SHA-256：project.godot `{inputs.get('project_godot_sha256') or 'n/a'}`，"
        f"export_presets.cfg `{inputs.get('export_presets_sha256') or 'n/a'}`。"
    )
    lines.append("")
    if summary.get("fail"):
        lines.append(
            f"> ⚠️ 静态检查有 {summary['fail']} 条 FAIL：先修掉再谈导出/交付，"
            "本说明不能替代失败项修复。"
        )
        lines.append("")
    if not engine.get("consistent"):
        lines.append(
            "> ⚠️ 引擎版本静态核对不一致：project.godot 与任务要求的 "
            f"{EXPECTED_ENGINE_SERIES} 系（{EXPECTED_ENGINE_VERSION}）不匹配，导出流程不能按本文执行。"
        )
        lines.append("")

    lines.append("## 一、版本与入口")
    lines.append("")
    lines.append(f"- 项目名：`{project_name}`")
    lines.append(
        f"- 引擎：**Godot {EXPECTED_ENGINE_VERSION} 标准版（GDScript，不用 .NET 版）**；"
        f"project.godot 声明 `{engine.get('project_series') or '未知'}` 系"
        f"（`config/features` = {engine.get('project_features') or []}）。"
    )
    lines.append(
        "- 精确补丁版本必须用 `godot --version` 在目标机核对；导出模板版本必须与编辑器**完全一致**。"
    )
    lines.append(f"- 主场景：`{main_scene}`")
    viewport = project.get("viewport") or {}
    if viewport.get("width") and viewport.get("height"):
        lines.append(
            f"- 默认窗口：{viewport['width']}×{viewport['height']}"
            f"（渲染后端 `{project.get('rendering_method') or '默认'}`）"
        )
    lines.append(f"- 导出预设：`{preset_name}`（platform=`{preset.get('platform')}`）")
    lines.append(
        f"- 预设输出路径：`{export_path}`（相对 `apps/desktop/`；目录不存在时 Godot 不会自动创建）"
    )
    lines.append("")

    lines.append("## 二、环境要求")
    lines.append("")
    lines.append("- Windows 10/11 x86_64；普通用户权限即可，不需要管理员。")
    lines.append(
        "- Godot 4.6.3 标准版（编辑器）＋与 4.6.3 完全匹配的导出模板"
        "（编辑器菜单：编辑器 → 管理导出模板，或手动解压 .tpz 到 "
        "`%APPDATA%\\Godot\\export_templates\\4.6.3.stable\\`）。"
    )
    lines.append("- 已安装 Python 3.10+ 才能运行 `tools/desktop-delivery/` 下的静态检查脚本（可选）。")
    lines.append("- 后台输入助手是可选模块：`tools/windows-typing/bin/TypingCounter.exe`，")
    lines.append("  不在 Godot 工程内、不会进 PCK，发布时必须与主程序 exe 一起放在约定目录；")
    lines.append("  助手缺失时主游戏仍应能启动（**该行为需实机验证，本文不保证**）。")
    lines.append("")

    lines.append("## 三、用编辑器打开")
    lines.append("")
    lines.append("在仓库根目录执行：")
    lines.append("")
    lines.extend(_md_code_block(["godot --editor --path apps/desktop"]))
    lines.append("")
    lines.append(
        "也可以在项目管理器里导入 `apps/desktop/project.godot`。首次打开会生成 `.godot/` 导入缓存"
        "（`.gitignore` 已忽略，不提交）；干净检出直接导出前通常需要先执行："
    )
    lines.append("")
    lines.extend(_md_code_block(["godot --headless --path apps/desktop --import"]))
    lines.append("")
    lines.append("编辑器内按 F5 运行主场景。**本文没有在实机执行过这条路径。**")
    lines.append("")

    lines.append("## 四、不装 Godot 时能做什么（本工具集）")
    lines.append("")
    lines.append("只有静态核对，不能代替导出/运行：")
    lines.append("")
    lines.extend(
        _md_code_block(
            [
                "python tools/desktop-delivery/build_manifest.py --root . --text",
                "python tools/desktop-delivery/export_check.py --root . --dry-run",
            ]
        )
    )
    lines.append("")
    lines.append(
        "`build_manifest.py` 检查工程/资源类别/版本线索/绝对路径泄漏/导出过滤；"
        "`export_check.py` 在没有 Godot 时会输出 `BLOCKED: godot not found` 并以退出码 2 结束，"
        "不会假装导出成功。"
    )
    if godot_found:
        lines.append("")
        lines.append(
            "> 生成本文件的机器上探测到 Godot 可执行文件（只探测路径，未执行任何导出）。"
        )
    else:
        lines.append("")
        lines.append(
            "> 生成本文件的机器上**没有探测到 Godot**；因此本文所有导出步骤都没有实际执行过。"
        )
    lines.append("")

    lines.append("## 五、导出步骤（需要在装了 Godot 4.6.3 的机器上执行）")
    lines.append("")
    lines.append("推荐用本仓库的检查脚本（先 dry-run 看计划，确认后 `--run`）：")
    lines.append("")
    lines.extend(
        _md_code_block(
            [
                "python tools/desktop-delivery/export_check.py --root . --dry-run",
                "python tools/desktop-delivery/export_check.py --root . --run",
            ]
        )
    )
    lines.append("")
    lines.append("它会按顺序执行：版本探测 → `--export-pack` 冒烟 → 用 `--main-pack` 跑 300 帧 →")
    lines.append("`--export-release` 模板导出 → 核对产物存在且非空。手动等价命令：")
    lines.append("")
    lines.extend(
        _md_code_block(
            [
                "mkdir builds\\windows",
                'godot --headless --path apps/desktop --export-pack "Windows Desktop" '
                "apps/desktop/builds/export-check/Windows-Desktop.pck",
                "godot --headless --path apps/desktop --main-pack "
                "apps/desktop/builds/export-check/Windows-Desktop.pck --quit-after 300",
                'godot --headless --path apps/desktop --export-release "Windows Desktop" '
                f"apps/desktop/{export_path}",
            ]
        )
    )
    lines.append("")
    lines.append(
        "注意：预设名 **大小写和空格敏感**，必须与 `export_presets.cfg` 的 `name=` 完全一致；"
        f"当前预设是 `{preset_name}`。"
    )
    lines.append("")

    lines.append("## 六、包内资源与 JSON 过滤器")
    lines.append("")
    if uncovered:
        lines.append(
            "静态检查发现：预设的 `include_filter` 没有覆盖下面这些非资源文件，"
            "**按 Godot 4.x 默认规则包内会缺 JSON**："
        )
        lines.append("")
        lines.extend(f"- `{item}`" for item in uncovered)
        lines.append("")
        lines.append(
            "但本项目 4.6.3 的**实际导出包曾包含建筑 JSON**，静态过滤规则与真机结果可能不同："
            "**必须实机核对 PCK/运行结果**，确认缺文件后再决定是否在预设里加 `*.json`，"
            "不要仅凭静态检查直接改过滤器或断言导出失败。"
        )
    else:
        lines.append("当前没有发现未被 `include_filter` 覆盖的运行时 JSON；仍建议实机核对包内文件。")
    lines.append("")
    lines.append(
        "`tools/windows-typing/` 在 Godot 工程之外，**不会进入 PCK**；"
        "发布时把助手 exe 放到主程序旁边并保持可选。"
    )
    lines.append("")

    lines.append("## 七、常见错误")
    lines.append("")
    lines.append("| 现象 | 原因 | 处理 |")
    lines.append("|---|---|---|")
    lines.append(
        "| `No export template found at the expected path` | 模板缺失或版本不是 4.6.3 | "
        "安装完全匹配的 4.6.3 模板；`--export-pack` 不需要模板，可先冒烟 |"
    )
    lines.append(
        "| `Invalid export preset name: ...` | 预设名大小写/空格不一致 | "
        f"用 `{preset_name}` 的精确写法，命令里加引号 |"
    )
    lines.append(
        "| `Can't open file for writing` | 输出目录不存在 | 先 `mkdir builds\\windows`；"
        "`export_check.py --run` 会自动创建 |"
    )
    lines.append(
        "| 找不到 `godot` | 未安装或不在 PATH | 安装 4.6.3，或用 `--godot <exe>` 指定 |"
    )
    lines.append(
        "| 首次打开报导入/资源错误 | 干净检出没有 `.godot/` 缓存 | 先 `godot --headless --import` |"
    )
    lines.append(
        "| 包内缺 JSON | `include_filter` 未覆盖非资源文件 | 先实机核对，再决定是否加 `*.json` |"
    )
    lines.append(
        "| 助手不工作 | 助手 exe 未随包分发/路径不对 | 按约定路径放置；缺失时主游戏应仍可启动（需实机验证） |"
    )
    lines.append("")

    lines.append("## 八、静态已核对 / 尚未验证")
    lines.append("")
    lines.append(
        f"静态检查汇总：PASS {summary.get('pass', 0)} / WARN {summary.get('warn', 0)} / "
        f"FAIL {summary.get('fail', 0)} / INFO {summary.get('info', 0)}"
        "（来自 build_manifest.py；**不代表运行成功**）。"
    )
    lines.append("")
    lines.append("**已做的静态核对：**")
    lines.append("")
    lines.append("- 工程与导出预设存在、主场景存在、Windows 预设存在、data/ui 资源类别存在。")
    lines.append("- 文件清单与 SHA-256、扩展名/分组统计。")
    lines.append("- 引擎版本线索为 4.6 系（精确 4.6.3 需实机核对）。")
    lines.append("- 资源文本里没有 Windows 盘符/UNC/`/home`/`file:///` 绝对路径（按当前扫描规则）。")
    lines.append("- 静态 `res://` 引用能在工程内找到对应文件。")
    lines.append("")
    lines.append("**尚未验证（不得写成已通过）：**")
    lines.append("")
    lines.append("- Godot 4.6.3 实机版本与导出模板匹配。")
    lines.append("- `--export-pack` / `--export-release` 真正成功、产物可启动。")
    lines.append("- 启动时间、首个可操作界面、窗口/DPI/置顶、存档读写、坏档路径。")
    lines.append("- 后台输入助手在包内/包外的真实行为与焦点场景。")
    lines.append("- 包内 JSON 是否实际存在（导出过滤器的实机结果）。")
    lines.append("- Steam 上传、审核、商店素材：**本阶段不做，也不宣称已通过**。")
    lines.append("")

    lines.append("## 九、复现命令")
    lines.append("")
    lines.extend(
        _md_code_block(
            [
                "python tools/desktop-delivery/build_manifest.py --root . --json --out build-manifest.json",
                "python tools/desktop-delivery/export_check.py --root . --dry-run --json",
                "python tools/desktop-delivery/delivery.py --root . --claims <claims.json>",
                "python -m unittest discover -s tools/desktop-delivery/tests -v",
            ]
        )
    )
    lines.append("")
    lines.append("## 十、交付边界")
    lines.append("")
    lines.append(
        "- 24/48/72 阶段包只能从**任务1集成锁定清单指定的提交**构建；不从缺少其他模块的分支冒充整合版。"
    )
    lines.append("- 本文是启动说明**草稿**，发布前由负责人在实机走一遍并补上真实结果。")
    lines.append("- 不上传 Steam、不支付费用、不宣称已通过 Steam 审核。")
    lines.append("")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="生成中文启动说明草稿（未验证，静态推导）。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--root", help="仓库根目录（默认推断）")
    parser.add_argument("--manifest", help="已有构建清单 JSON（可选；省略则现场生成）")
    parser.add_argument("--out", default=DEFAULT_OUT, help="输出 Markdown 路径（相对仓库根）")
    parser.add_argument("--stdout", action="store_true", help="输出到 stdout，不写文件")
    args = parser.parse_args(argv)

    try:
        root = common.find_root(args.root)
        common.require_project(root)
        if args.manifest:
            manifest_path = Path(args.manifest).expanduser()
            if not manifest_path.is_absolute():
                manifest_path = (Path.cwd() / manifest_path).resolve()
            if not manifest_path.is_file():
                raise ToolError(f"找不到构建清单：{manifest_path}")
            import json

            manifest = json.loads(common.read_text(manifest_path))
            if not isinstance(manifest, dict) or "files" not in manifest:
                raise ToolError(f"构建清单格式不对：{manifest_path}")
        else:
            manifest = manifest_tool.build_manifest_data(root)

        try:
            import export_check

            godot_path, _ = export_check.discover_godot(None)
        except Exception:  # 探测失败不应阻止生成说明
            godot_path = None

        markdown = build_notes(manifest, str(godot_path) if godot_path else None)
    except ToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.stdout:
        sys.stdout.write(markdown)
    else:
        out_path = Path(args.out).expanduser()
        if not out_path.is_absolute():
            out_path = root / out_path
        common.write_text(out_path, markdown)
        print(f"已写入启动说明：{out_path}", file=sys.stderr)

    return 1 if (manifest.get("summary") or {}).get("fail") else 0


if __name__ == "__main__":
    sys.exit(main())
