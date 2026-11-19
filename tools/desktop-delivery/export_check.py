#!/usr/bin/env python3
"""Godot 导出检查（默认 dry-run，不执行任何引擎命令）。

顺序遵循 godot-export 技能：
    1. 探测 Godot 可执行与版本（必须与 4.6.3 完全匹配）
    2. `--export-pack` 冒烟（不需要导出模板）
    3. 用 `--main-pack` 跑一次导出的 PCK，抓 SCRIPT ERROR / 启动错误
    4. `--export-release` 用模板导出 exe
    5. 核对输出文件存在且非空

本机没有 Godot 时输出 blocked / godot-not-installed，退出码 2；
任何"计划命令"都不会被执行，也不会假装导出成功。

用法：
    python tools/desktop-delivery/export_check.py --root .
    python tools/desktop-delivery/export_check.py --root . --run
    python tools/desktop-delivery/export_check.py --root . --godot "C:/Godot/Godot_v4.6.3-stable_win64.exe" --run

退出码：0 = dry-run 计划成功或 --run 全部通过；1 = 预检失败/导出失败；2 = 找不到 Godot 或用法错误。
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import delivery_common as common
from delivery_common import (
    EXPECTED_ENGINE_SERIES,
    EXPECTED_ENGINE_VERSION,
    TOOL_VERSION,
    ToolError,
    version_series,
)

EXPORT_CHECK_SCHEMA = "desktop-delivery/export-check/1"

GODOT_NAMES = ("godot.exe", "godot4.exe", "Godot.exe", "godot", "godot4")

SMOKE_ERROR_PATTERN = re.compile(
    r"(SCRIPT ERROR|^ERROR:|Failed to load|Can't open file|Parse Error)", re.M
)


def _searched_hint(path: Path) -> str:
    return str(path)


def discover_godot(explicit: str | None) -> tuple[Path | None, list[str]]:
    """按 --godot / GODOT_BIN / PATH / 常见安装目录 查找 Godot。"""
    searched: list[str] = []

    def check_file(path: Path) -> Path | None:
        searched.append(str(path))
        if path.is_file():
            return path.resolve()
        return None

    if explicit:
        candidate = Path(explicit).expanduser()
        if candidate.is_dir():
            searched.append(f"{candidate}（目录）")
            for name in GODOT_NAMES:
                found = check_file(candidate / name)
                if found:
                    return found, searched
            for found_exe in sorted(candidate.glob("Godot_v*.exe")):
                found = check_file(found_exe)
                if found:
                    return found, searched
            return None, searched
        found = check_file(candidate)
        return (found, searched) if found else (None, searched)

    env_bin = os.environ.get("GODOT_BIN")
    if env_bin:
        found = check_file(Path(env_bin))
        if found:
            return found, searched

    for name in GODOT_NAMES:
        located = shutil.which(name)
        searched.append(f"PATH:{name}")
        if located:
            return Path(located).resolve(), searched

    directories: list[Path] = []
    for env_name in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
        base = os.environ.get(env_name)
        if not base:
            continue
        root = Path(base)
        if env_name == "LOCALAPPDATA":
            directories.append(root / "Programs" / "Godot")
            directories.append(root / "Godot")
        else:
            directories.append(root / "Godot")
            directories.append(root / "Godot Engine")
    directories.append(Path("C:/Godot"))

    for directory in directories:
        searched.append(str(directory))
        if not directory.is_dir():
            continue
        for name in GODOT_NAMES:
            found = check_file(directory / name)
            if found:
                return found, searched
        for child in sorted(directory.glob("Godot*")):
            if child.is_dir():
                for name in GODOT_NAMES:
                    found = check_file(child / name)
                    if found:
                        return found, searched

    return None, searched


def export_templates_info() -> dict:
    root_display = "%APPDATA%/Godot/export_templates"
    appdata = os.environ.get("APPDATA")
    if not appdata:
        return {"root": root_display, "found": False, "versions": [], "windows_template": None}
    root = Path(appdata) / "Godot" / "export_templates"
    if not root.is_dir():
        return {"root": root_display, "found": False, "versions": [], "windows_template": None}
    versions = sorted(child.name for child in root.iterdir() if child.is_dir())
    windows_template = None
    for version_dir in sorted(root.iterdir(), reverse=True):
        if not version_dir.is_dir():
            continue
        for candidate in ("windows_release_x86_64.exe", "windows_debug_x86_64.exe"):
            if (version_dir / candidate).is_file():
                windows_template = f"{version_dir.name}/{candidate}"
                break
        if windows_template:
            break
    return {
        "root": root_display,
        "found": bool(versions),
        "versions": versions,
        "windows_template": windows_template,
    }


def format_argv(argv: list[str]) -> str:
    def quote(part: str) -> str:
        if not part or re.search(r'[\s"]', part):
            return '"' + part.replace('"', '\\"') + '"'
        return part

    return " ".join(quote(part) for part in argv)


def build_plan(godot: Path | None, project: Path, preset: dict, out_path: Path, pack_path: Path) -> dict:
    godot_display = str(godot) if godot else "godot"
    steps = [
        {
            "name": "version-probe",
            "argv": [godot_display, "--headless", "--path", str(project), "--version"],
            "note": "核对引擎版本；导出模板必须与编辑器版本完全一致。",
            "ran": False,
            "exit_code": None,
            "log_path": None,
            "tail": [],
        },
        {
            "name": "export-pack",
            "argv": [
                godot_display,
                "--headless",
                "--path",
                str(project),
                "--export-pack",
                preset["name"],
                str(pack_path),
            ],
            "note": "冒烟：只导出 PCK，不需要导出模板；用于先暴露脚本/资源/过滤问题。",
            "ran": False,
            "exit_code": None,
            "log_path": None,
            "tail": [],
        },
        {
            "name": "pack-smoke-run",
            "argv": [
                godot_display,
                "--headless",
                "--main-pack",
                str(pack_path),
                "--quit-after",
                "300",
            ],
            "note": "只加载包内文件跑 300 帧；抓 SCRIPT ERROR / 资源缺失。",
            "ran": False,
            "exit_code": None,
            "log_path": None,
            "tail": [],
        },
        {
            "name": "export-release",
            "argv": [
                godot_display,
                "--headless",
                "--path",
                str(project),
                "--export-release",
                preset["name"],
                str(out_path),
            ],
            "note": "正式模板导出；预设名大小写和空格敏感，输出目录必须已存在。",
            "ran": False,
            "exit_code": None,
            "log_path": None,
            "tail": [],
        },
        {
            "name": "verify-artifact",
            "argv": [],
            "note": f"核对输出文件存在且非空：{out_path}",
            "ran": False,
            "exit_code": None,
            "log_path": None,
            "tail": [],
        },
    ]
    for step in steps:
        step["display"] = format_argv(step["argv"]) if step["argv"] else step["note"]
    return {"steps": steps, "out_path": str(out_path), "pack_path": str(pack_path)}


def _tail(text: str, limit: int = 40) -> list[str]:
    lines = text.splitlines()
    return lines[-limit:] if len(lines) > limit else lines


def execute_step(step: dict, project: Path, log_dir: Path, timeout: int) -> None:
    step["ran"] = True
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{step['name']}.log"
    step["log_path"] = str(log_path)
    output = ""
    try:
        proc = subprocess.run(
            step["argv"],
            cwd=str(project),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        step["exit_code"] = proc.returncode
        output = proc.stdout or ""
        if proc.stderr:
            output += ("\n[stderr]\n" if output else "[stderr]\n") + proc.stderr
    except FileNotFoundError:
        step["exit_code"] = 127
        output = f"找不到可执行文件：{step['argv'][0]}"
    except subprocess.TimeoutExpired as exc:
        step["exit_code"] = 124
        partial = exc.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", "replace")
        output = f"命令超时（{timeout}s）\n{partial}"
    except OSError as exc:
        step["exit_code"] = 126
        output = f"无法执行：{exc}"

    common.write_text(log_path, output)
    step["tail"] = _tail(output)
    step["ok"] = step["exit_code"] == 0

    if step["name"] == "version-probe" and step["exit_code"] == 0:
        found = re.search(r"(\d+\.\d+(?:\.\d+)?)", output)
        step["engine_version"] = found.group(1) if found else None
        series = version_series(step.get("engine_version"))
        step["engine_series"] = series
        if series != EXPECTED_ENGINE_SERIES:
            step["ok"] = False
            step["note"] = (
                f"引擎版本 {step.get('engine_version') or '(未知)'} 不是 {EXPECTED_ENGINE_SERIES} 系"
                f"（任务要求 {EXPECTED_ENGINE_VERSION}）；中止导出。"
            )

    if step["name"] == "pack-smoke-run" and step["exit_code"] == 0 and output:
        errors = sorted(set(match.group(0) for match in SMOKE_ERROR_PATTERN.finditer(output)))
        if errors:
            step["ok"] = False
            step["note"] = "冒烟运行日志里出现错误标记：" + ", ".join(errors[:5])


def build_preflight(project: Path, presets: list[dict], preset: dict, out_path: Path, pack_path: Path) -> dict:
    templates = export_templates_info()
    return {
        "project_dir": "apps/desktop",
        "project_godot_exists": (project / "project.godot").is_file(),
        "presets_file_exists": (project / "export_presets.cfg").is_file(),
        "preset_names": [item["name"] for item in presets],
        "selected_preset": preset["name"] if preset else None,
        "selected_platform": preset.get("platform") if preset else None,
        "include_filter": preset.get("include_filter") if preset else None,
        "export_path": preset.get("export_path") if preset else None,
        "output_path": str(out_path),
        "output_dir_exists": out_path.parent.is_dir(),
        "pack_path": str(pack_path),
        "import_cache_exists": (project / ".godot").is_dir(),
        "templates": templates,
    }


def render_text(result: dict) -> str:
    lines = ["导出检查 · apps/desktop"]
    godot = result["godot"]
    if not godot["found"]:
        lines.append("BLOCKED: godot not found")
        lines.append("状态：BLOCKED (godot-not-installed)")
    else:
        lines.append(f"Godot：{godot['path']}")
        lines.append(f"状态：{result['status']}")

    preflight = result["preflight"]
    lines.append(f"预设：{preflight.get('selected_preset')!r}，输出：{preflight.get('output_path')}")
    lines.append(f"导出模板（%APPDATA%/Godot/export_templates）：{preflight['templates']['windows_template'] or '未发现'}")
    lines.append("")
    if result["reason"]:
        lines.append(f"原因：{result['reason']}")
    if result["next"]:
        lines.append("下一步：")
        lines.extend(f"  - {item}" for item in result["next"])
        lines.append("")
    lines.append("计划命令（" + ("已执行" if result["run"] else "未执行，dry-run") + "）：")
    for index, step in enumerate(result["plan"]["steps"], start=1):
        lines.append(f"  {index}) {step['display']}")
        if step.get("ran"):
            lines.append(
                f"     退出码 {step['exit_code']}，日志 {step.get('log_path') or '(未写)'}"
            )
            if not step.get("ok", True):
                lines.append(f"     结果：FAILED {step.get('note') or ''}".rstrip())
        else:
            lines.append("     （未执行）")
    if result.get("warnings"):
        lines.append("")
        lines.append("预检提醒：")
        lines.extend(f"  - {item}" for item in result["warnings"])
    lines.append("")
    lines.append("说明：本工具不会伪造导出结果；没有 Godot 时只能给出静态预检与计划。")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Godot 导出检查（默认 dry-run，不执行任何命令）。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--root", help="仓库根目录（默认推断）")
    parser.add_argument("--godot", help="Godot 可执行文件或所在目录")
    parser.add_argument("--preset", help="导出预设名（默认取 export_presets.cfg 的第一个预设）")
    parser.add_argument("--out", help="输出 exe 路径（默认取预设的 export_path）")
    parser.add_argument("--pack", help="冒烟 PCK 路径（默认 apps/desktop/builds/export-check/<preset>.pck）")
    parser.add_argument("--timeout", type=int, default=900, help="单条命令超时秒数（默认 900）")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--run", action="store_true", help="真正执行命令（默认不执行）")
    mode.add_argument("--dry-run", action="store_true", help="只打印计划（默认行为）")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    parser.add_argument("--out-report", help="把报告写入文件")
    parser.add_argument("--stamp", action="store_true", help="写入 generated_at_utc")
    args = parser.parse_args(argv)

    try:
        root = common.find_root(args.root)
        project = common.require_project(root)
    except ToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    presets_file = project / "export_presets.cfg"
    presets = (
        common.parse_export_presets(common.read_text(presets_file))
        if presets_file.is_file()
        else []
    )

    warnings: list[str] = []
    preset = None
    if args.preset:
        preset = next((item for item in presets if item["name"] == args.preset), None)
        if preset is None and presets:
            case_matches = [
                item for item in presets if item["name"].lower() == args.preset.lower()
            ]
            if case_matches:
                warnings.append(
                    f"预设名大小写不匹配：请求 {args.preset!r}，实际是 {case_matches[0]['name']!r}；"
                    "Godot 命令行区分大小写和空格。"
                )
    elif presets:
        preset = presets[0]

    godot, searched = discover_godot(args.godot)

    if preset is None:
        result = {
            "schema": EXPORT_CHECK_SCHEMA,
            "tool_version": TOOL_VERSION,
            "generated_at_utc": common.iso_now() if args.stamp else None,
            "status": "preset-missing",
            "reason": "export-preset-not-found",
            "run": bool(args.run),
            "godot": {
                "found": bool(godot),
                "path": str(godot) if godot else None,
                "searched": searched,
            },
            "preflight": {
                "project_dir": "apps/desktop",
                "preset_names": [item["name"] for item in presets],
                "selected_preset": None,
            },
            "plan": {"steps": []},
            "next": [
                "在 apps/desktop/export_presets.cfg 里确认 [preset.N] 的 name，"
                "或用 --preset 指定完全一致的名字（大小写/空格敏感）。",
            ],
            "warnings": warnings,
        }
        payload = common.json_dumps(result) if args.json else render_text(result)
        if args.out_report:
            common.write_text(Path(args.out_report).expanduser(), payload)
        else:
            sys.stdout.write(payload)
        return 1

    export_path = preset.get("export_path") or ""
    if args.out:
        out_path = Path(args.out).expanduser()
        if not out_path.is_absolute():
            out_path = project / out_path
    elif export_path:
        out_path = project / export_path
    else:
        out_path = project / "builds" / "windows" / "KingdomDesktop.exe"

    if args.pack:
        pack_path = Path(args.pack).expanduser()
        if not pack_path.is_absolute():
            pack_path = project / pack_path
    else:
        safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "-", preset["name"]).strip("-") or "preset"
        pack_path = project / "builds" / "export-check" / f"{safe_name}.pck"

    plan = build_plan(godot, project, preset, out_path, pack_path)
    preflight = build_preflight(project, presets, preset, out_path, pack_path)

    if not preflight["output_dir_exists"]:
        warnings.append(
            f"输出目录 {out_path.parent} 不存在：Godot 不会自动创建；"
            "--run 会先创建目录，手动导出前需 mkdir。"
        )
    if not preflight["templates"]["windows_template"]:
        warnings.append(
            "没有发现 Windows 导出模板（%APPDATA%/Godot/export_templates）；"
            "--export-pack 仍可冒烟，但 --export-release 会报 No export template found。"
        )
    if not preflight["import_cache_exists"]:
        warnings.append(
            "工程内没有 .godot/ 导入缓存；干净检出在模板导出前通常需要先 `godot --headless --import`。"
        )

    result = {
        "schema": EXPORT_CHECK_SCHEMA,
        "tool_version": TOOL_VERSION,
        "generated_at_utc": common.iso_now() if args.stamp else None,
        "status": "blocked" if not godot else ("dry-run" if not args.run else "running"),
        "reason": "godot-not-installed" if not godot else None,
        "run": bool(args.run),
        "godot": {
            "found": bool(godot),
            "path": str(godot) if godot else None,
            "searched": searched,
        },
        "preflight": preflight,
        "plan": plan,
        "warnings": warnings,
        "next": [],
    }

    if not godot:
        result["next"] = [
            "安装 Godot 4.6.3 标准版（不是 .NET 版），确认 `godot` 在 PATH，或用 --godot <exe> 指定。",
            "安装与编辑器完全一致的 4.6.3 导出模板（编辑器 → 管理导出模板）。",
            "没有引擎时只能做静态检查：build_manifest.py 可用；不得声称已导出或已实机运行。",
        ]
        payload = common.json_dumps(result) if args.json else render_text(result)
        if args.out_report:
            common.write_text(Path(args.out_report).expanduser(), payload)
        else:
            sys.stdout.write(payload)
        return 2

    if not args.run:
        result["status"] = "dry-run"
        result["next"] = ["确认计划后加 --run 真正执行；本机未执行任何引擎命令。"]
    else:
        if not out_path.parent.is_dir():
            out_path.parent.mkdir(parents=True, exist_ok=True)
        pack_path.parent.mkdir(parents=True, exist_ok=True)
        log_dir = pack_path.parent / "logs"

        steps = plan["steps"]
        result["status"] = "ok"
        for step in steps:
            if step["name"] == "verify-artifact":
                step["ran"] = True
                if out_path.is_file() and out_path.stat().st_size > 0:
                    step["exit_code"] = 0
                    step["ok"] = True
                    step["tail"] = [
                        f"{out_path.name}: {out_path.stat().st_size} bytes",
                        f"sha256: {common.sha256_file(out_path)}",
                    ]
                else:
                    step["exit_code"] = 1
                    step["ok"] = False
                    step["note"] = "输出文件不存在或为空：导出没有真正成功。"
                continue

            execute_step(step, project, log_dir, args.timeout)
            if not step.get("ok", False):
                result["status"] = "failed"
                break
            if step["name"] == "version-probe":
                result["engine_version"] = step.get("engine_version")
            if step["name"] == "pack-smoke-run":
                result["smoke_ok"] = step.get("ok", False)
                if result.get("smoke_ok"):
                    smoke_log = step.get("log_path")
                    if smoke_log:
                        result["smoke_log"] = smoke_log
        if result["status"] == "ok":
            result["next"] = [
                "在真实 Windows 桌面双击产物并核对启动、存档、窗口与后台输入；"
                "静态检查与退出码 0 不能替代实机验收。",
            ]
        else:
            result["next"] = [
                "查看失败步骤的日志尾部与 log_path；按提示修复后重跑。",
                "模板问题：安装 4.6.3 模板；预设名问题：核对大小写/空格；输出目录问题：先 mkdir。",
            ]

    payload = common.json_dumps(result) if args.json else render_text(result)
    if args.out_report:
        common.write_text(Path(args.out_report).expanduser(), payload)
        print(f"已写入报告：{args.out_report}", file=sys.stderr)
    else:
        sys.stdout.write(payload)

    if result["status"] == "ok" or result["status"] == "dry-run":
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
