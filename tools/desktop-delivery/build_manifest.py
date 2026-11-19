#!/usr/bin/env python3
"""生成 apps/desktop 的静态构建清单（不需要 Godot）。

用法：
    python tools/desktop-delivery/build_manifest.py --root . --text
    python tools/desktop-delivery/build_manifest.py --root . --json --out build-manifest.json

退出码：0 = 没有 FAIL；1 = 有 FAIL；2 = 用法/路径错误。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import delivery_common as common
from delivery_common import (
    EXPECTED_ENGINE_SERIES,
    EXPECTED_ENGINE_VERSION,
    MANIFEST_SCHEMA,
    TOOL_VERSION,
    ToolError,
    _add_check,
)


def _build_checks(
    project: Path,
    project_info: dict,
    presets: list[dict],
    presets_file: Path,
    categories: dict,
    diagnosis: dict,
    leaks: dict,
    refs: dict,
    helper: dict,
) -> list[dict]:
    checks: list[dict] = []

    _add_check(checks, "project-file", "PASS", "找到 apps/desktop/project.godot。")

    if not presets_file.is_file():
        _add_check(
            checks,
            "export-presets-file",
            "FAIL",
            "缺少 apps/desktop/export_presets.cfg：没有导出预设就无法从命令行 `--export-release` 出包。",
        )
    elif not presets:
        _add_check(
            checks,
            "export-presets-file",
            "FAIL",
            "export_presets.cfg 存在但没有 [preset.N] 段：命令行没有可用预设名。",
        )
    else:
        _add_check(
            checks,
            "export-presets-file",
            "PASS",
            "找到导出预设：" + ", ".join(repr(item["name"]) for item in presets) + "。",
        )

    windows_presets = [
        item for item in presets if "windows" in (item.get("platform") or "").lower()
    ]
    if not presets:
        pass
    elif windows_presets:
        _add_check(
            checks,
            "windows-preset",
            "PASS",
            "存在 Windows 导出预设："
            + ", ".join(
                f"{item['name']!r}（platform={item['platform']!r}）" for item in windows_presets
            )
            + "。命令行预设名大小写和空格敏感。",
        )
    else:
        _add_check(
            checks,
            "windows-preset",
            "FAIL",
            "export_presets.cfg 里没有 Windows 平台预设，无法产出阶段包 .exe。",
        )

    main_scene = project_info.get("main_scene")
    if not main_scene:
        _add_check(checks, "main-scene", "FAIL", "project.godot 没有 run/main_scene，游戏无法确定启动场景。")
    elif not main_scene.startswith("res://"):
        _add_check(checks, "main-scene", "FAIL", f"run/main_scene={main_scene!r} 不是 res:// 路径。")
    else:
        target = project / main_scene[len("res://") :]
        if target.is_file():
            _add_check(checks, "main-scene", "PASS", f"主场景 {main_scene} 存在。")
        else:
            _add_check(
                checks,
                "main-scene",
                "FAIL",
                f"project.godot 指向的主场景 {main_scene} 不存在（导出后会黑屏/启动失败）。",
            )

    data_category = categories["data_json"]
    if data_category["count"] > 0:
        _add_check(
            checks,
            "required-data-json",
            "PASS",
            f"data/ 下有 {data_category['count']} 个 JSON：" + ", ".join(data_category["files"]),
        )
    else:
        _add_check(
            checks,
            "required-data-json",
            "FAIL",
            "data/*.json 是必需资源类别，但工程里一个都没有（建筑槽位等数据会缺失）。",
        )

    ui_category = categories["ui_scene"]
    if ui_category["count"] > 0:
        _add_check(
            checks,
            "required-ui-scene",
            "PASS",
            f"ui/ 下有 {ui_category['count']} 个场景：" + ", ".join(ui_category["files"]),
        )
    else:
        _add_check(
            checks,
            "required-ui-scene",
            "FAIL",
            "ui/*.tscn 是必需资源类别，但工程里一个都没有（主界面启动场景缺失）。",
        )

    for key, label in (("fonts", "fonts/ 或 .ttf/.otf"), ("assets", "assets/")):
        category = categories[key]
        if category["count"]:
            _add_check(
                checks,
                f"optional-{key}",
                "PASS",
                f"发现 {category['count']} 个{label}文件：" + ", ".join(category["files"][:8]),
            )
        else:
            _add_check(
                checks,
                f"optional-{key}",
                "INFO",
                f"未发现{label}（该项可选；当前工程没有也不影响静态清单，但正式包缺字体/美术时需说明）。",
            )

    godot_cache = project / ".godot"
    if godot_cache.is_dir():
        _add_check(
            checks,
            "import-cache",
            "INFO",
            "存在 .godot/ 导入缓存（未校验是否与当前源码一致；干净目录导出前应先 `--import` 生成）。",
        )
    else:
        _add_check(
            checks,
            "import-cache",
            "INFO",
            "没有 .godot/ 导入缓存（干净检出正常；首次用编辑器打开或 `godot --headless --import` 会生成，导出前需要）。",
        )

    dirty_dirs = [name for name in ("builds", "dist") if (project / name).exists()]
    if dirty_dirs:
        _add_check(
            checks,
            "clean-room",
            "WARN",
            "工程内已存在输出目录 "
            + ", ".join(dirty_dirs)
            + "/：最终阶段包应在干净目录/干净检出重新导出，并核对哈希，避免把旧产物当新构建。",
        )
    else:
        _add_check(
            checks, "clean-room", "PASS", "工程内没有 builds/ 或 dist/ 输出目录（干净目录基线）。"
        )

    for preset in presets:
        export_path = preset.get("export_path") or ""
        if not export_path:
            _add_check(
                checks,
                f"preset-output-{preset['index']}",
                "WARN",
                f"预设 {preset['name']!r} 的 export_path 为空：命令行导出必须显式给输出路径。",
            )
            continue
        parent = (project / export_path).parent
        if parent.is_dir():
            _add_check(
                checks,
                f"preset-output-{preset['index']}",
                "PASS",
                f"预设 {preset['name']!r} 的输出目录 {parent.relative_to(project).as_posix()}/ 已存在。",
            )
        else:
            _add_check(
                checks,
                f"preset-output-{preset['index']}",
                "INFO",
                f"预设 {preset['name']!r} 的输出目录 "
                f"{parent.relative_to(project).as_posix()}/ 尚不存在（干净检出正常）；"
                "Godot 不会自动创建目录，导出前需 mkdir，export_check.py --run 会自动创建。",
            )

    if leaks["leaks"]:
        evidence = [
            f"{entry['file']}:{entry['line']}: {entry['text']}"
            for entry in leaks["leaks"][:20]
        ]
        _add_check(
            checks,
            "absolute-path-leak",
            "FAIL",
            f"在 {leaks['scanned_files']} 个文本文件里发现 {len(leaks['leaks'])} 处疑似本机绝对路径"
            "（换机/交付后会失效，资源里不应写入本机路径）：",
            evidence,
        )
    else:
        _add_check(
            checks,
            "absolute-path-leak",
            "PASS",
            f"扫描 {leaks['scanned_files']} 个 .json/.tscn/.cfg/.gd 文件，未发现本机绝对路径"
            "（盘符、UNC、POSIX 绝对路径、文件 URL 四类规则均未命中）。",
        )

    if refs["missing"]:
        evidence = [
            f"{entry['file']}:{entry['line']}: {entry['ref']}" for entry in refs["missing"][:20]
        ]
        _add_check(
            checks,
            "resource-references",
            "WARN",
            f"静态提取到 {refs['checked']} 处 res:// 引用，其中 {len(refs['missing'])} 处对应文件不存在；"
            "可能是运行时拼接路径，也可能是真的缺文件，需人工确认：",
            evidence,
        )
    else:
        _add_check(
            checks,
            "resource-references",
            "PASS",
            f"静态提取到 {refs['checked']} 处 res:// 引用，全部能在工程内找到对应文件。",
        )

    for item in diagnosis["presets"]:
        preset = next(
            (candidate for candidate in presets if candidate["index"] == item["index"]), None
        )
        if preset is None:
            continue
        uncovered = item["json_uncovered"]
        excluded = item["excluded_non_resource_files"]
        if uncovered:
            evidence = uncovered[:20]
            _add_check(
                checks,
                f"export-filter-preset-{item['index']}",
                "WARN",
                f"预设 {item['name']!r}：export_filter={item['export_filter']!r}，"
                f"include_filter={item['include_filter']!r}，未覆盖 {len(uncovered)} 个非资源文件 → "
                "按 Godot 4.x 默认规则包内会缺 JSON。注意：本项目 4.6.3 的实际导出包曾包含建筑 JSON，"
                "静态过滤规则与实机结果可能不同，需实机核对后再决定是否改 include_filter，"
                "不要仅凭本检查断言导出失败。",
                evidence,
            )
        elif diagnosis["json_files"]:
            _add_check(
                checks,
                f"export-filter-preset-{item['index']}",
                "PASS",
                f"预设 {item['name']!r} 的 include_filter 覆盖了全部 {len(diagnosis['json_files'])} 个 JSON 文件。",
            )
        else:
            _add_check(
                checks,
                f"export-filter-preset-{item['index']}",
                "INFO",
                f"预设 {item['name']!r}：工程内没有非资源 JSON，过滤规则无需覆盖。",
            )
        if excluded:
            _add_check(
                checks,
                f"export-exclude-preset-{item['index']}",
                "WARN",
                f"预设 {item['name']!r} 的 exclude_filter={item['exclude_filter']!r} 会排除 "
                f"{len(excluded)} 个文件：" + ", ".join(excluded[:8]),
            )

    if helper.get("exists"):
        exe_files = [item["path"] for item in helper.get("files", []) if item["path"].lower().endswith(".exe")]
        _add_check(
            checks,
            "helper-location",
            "INFO",
            f"发现 tools/windows-typing/（{len(helper.get('files', []))} 个文件"
            + (f"，含 {', '.join(exe_files)}" if exe_files else "")
            + "）。该目录在 Godot 工程之外，不会进入 PCK；发布时必须把助手可执行文件随 exe 一起分发，"
            "并保持可选（助手缺失时主游戏仍应能启动，需实机验证）。",
        )
    else:
        _add_check(
            checks,
            "helper-location",
            "INFO",
            "未发现 tools/windows-typing/（可选后台输入模块；缺失不应阻止主游戏启动，需实机验证）。",
        )

    return checks


def build_manifest_data(root, stamp: bool = False) -> dict:
    root = Path(root).expanduser().resolve()
    project = common.require_project(root)
    project_file = project / "project.godot"
    presets_file = project / "export_presets.cfg"

    project_text = common.read_text(project_file)
    project_info = common.parse_project_godot(project_text)
    presets_text = common.read_text(presets_file) if presets_file.is_file() else None
    presets = common.parse_export_presets(presets_text) if presets_text else []

    files = common.collect_project_files(project)
    categories = common.build_categories(files)
    diagnosis = common.diagnose_export_filters(files, presets)
    leaks = common.scan_absolute_paths(project, files)
    refs = common.scan_resource_references(project, files)
    helper = common.collect_helper_info(root)

    engine_checks: list[dict] = []
    engine = common.assess_engine(project_info, presets_text, engine_checks)

    checks = _build_checks(
        project,
        project_info,
        presets,
        presets_file,
        categories,
        diagnosis,
        leaks,
        refs,
        helper,
    )
    checks.extend(engine_checks)
    summary = common.summarize_checks(checks)

    inputs = {"project_godot_sha256": common.sha256_file(project_file)}
    if presets_file.is_file():
        inputs["export_presets_sha256"] = common.sha256_file(presets_file)
    else:
        inputs["export_presets_sha256"] = None

    return {
        "schema": MANIFEST_SCHEMA,
        "tool_version": TOOL_VERSION,
        "generated_at_utc": common.iso_now() if stamp else None,
        "task": {
            "id": "T4-08/T4-12",
            "title": "可重复导出与资源诊断 + 阶段包与交付工具",
        },
        "project_dir": "apps/desktop",
        "project": project_info,
        "engine": engine,
        "presets": presets,
        "files": files,
        "file_count": len(files),
        "total_bytes": sum(item["bytes"] for item in files),
        "extension_counts": common.extension_counts(files),
        "kind_counts": common.kind_counts(files),
        "groups": common.group_counts(files),
        "categories": categories,
        "export_filters": diagnosis,
        "absolute_path_scan": leaks,
        "resource_references": refs,
        "import_cache": {
            "godot_dir_exists": (project / ".godot").is_dir(),
            "note": "导入缓存格式与引擎版本相关；干净目录导出前需要重新 import。",
        },
        "helper": helper,
        "checks": checks,
        "summary": summary,
        "inputs": inputs,
    }


def render_manifest_text(manifest: dict) -> str:
    engine = manifest["engine"]
    lines = [
        f"构建清单 · {manifest['project_dir']}",
        f"项目：{manifest['project'].get('name') or '(未命名)'}",
        f"引擎：{engine.get('project_series') or '(未知)'} 系 / 期望 "
        f"{EXPECTED_ENGINE_SERIES} 系（{EXPECTED_ENGINE_VERSION}）"
        f" → {'一致' if engine.get('consistent') else '不一致'}",
        f"文件：{manifest['file_count']} 个，合计 {common.format_bytes(manifest['total_bytes'])}",
        "扩展名：" + ", ".join(f"{key}={value}" for key, value in manifest["extension_counts"].items()),
        "分组：" + ", ".join(
            f"{key}={value['files']}" for key, value in manifest["groups"].items()
        ),
        "",
    ]
    lines.extend(common.render_checks_text(manifest["checks"]))
    lines.append("")
    summary = manifest["summary"]
    lines.append(
        f"汇总：PASS {summary['pass']} / WARN {summary['warn']} / FAIL {summary['fail']} / "
        f"INFO {summary['info']} → status={summary['status']}"
    )
    if summary["fail"]:
        lines.append("提示：存在 FAIL，先修掉上面的失败项；本清单不是导出成功证明。")
    else:
        lines.append("说明：本清单只是静态核对，不代表已经导出或实机启动成功。")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="生成 apps/desktop 的静态构建清单（不需要 Godot）。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--root", help="仓库根目录（默认从脚本位置/当前目录向上推断）")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--json", action="store_true", help="输出确定性 JSON")
    group.add_argument("--text", action="store_true", help="输出人类可读文本（默认）")
    parser.add_argument("--out", help="写入文件而不是 stdout")
    parser.add_argument(
        "--stamp",
        action="store_true",
        help="写入 generated_at_utc（默认 null，保证同输入同字节输出）",
    )
    args = parser.parse_args(argv)

    try:
        root = common.find_root(args.root)
        manifest = build_manifest_data(root, stamp=args.stamp)
    except ToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    payload = common.json_dumps(manifest) if args.json else render_manifest_text(manifest)
    if args.out:
        out_path = Path(args.out).expanduser()
        if not out_path.is_absolute():
            out_path = Path.cwd() / out_path
        common.write_text(out_path, payload)
        print(f"已写入清单：{out_path}", file=sys.stderr)
    else:
        sys.stdout.write(payload)

    return 1 if manifest["summary"]["fail"] else 0


if __name__ == "__main__":
    sys.exit(main())
