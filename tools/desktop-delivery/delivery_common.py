#!/usr/bin/env python3
"""desktop-delivery 共享静态检查工具。

设计前提：本机可能没有 Godot、没有 git、没有 .NET SDK。
这里只做"不需要引擎"的静态核对：文件清单 / SHA-256 / 工程配置 / 导出过滤规则 /
绝对路径泄漏 / res:// 引用。任何需要引擎才能确认的结论都不在这里假装通过。

仅使用 Python 标准库。
"""

from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime, timezone
from fnmatch import fnmatch
from pathlib import Path, PurePosixPath

TOOL_VERSION = "1.0.0"
MANIFEST_SCHEMA = "desktop-delivery/build-manifest/1"
DELIVERY_SCHEMA = "desktop-delivery/delivery/1"

EXPECTED_ENGINE_SERIES = "4.6"
EXPECTED_ENGINE_VERSION = "4.6.3"

IGNORED_DIR_NAMES = {".godot", "builds", "dist", "__pycache__", ".git", ".import", "node_modules"}
IGNORED_FILE_SUFFIXES = {".tmp", ".bak"}
# 生成物：清单的消费方，不能反过来被清单哈希（否则哈希包含自身，永不收敛）
GENERATED_DELIVERY_FILES = {"docs/交付/任务4/delivery.json", "docs/交付/任务4/delivery_detail.json"}

LEVELS = ("FAIL", "WARN", "PASS", "INFO")

KIND_BY_EXT = {
    ".gd": "script",
    ".tscn": "scene",
    ".tres": "resource",
    ".json": "data",
    ".cfg": "config",
    ".godot": "config",
    ".md": "doc",
    ".txt": "doc",
    ".pdf": "doc",
    ".uid": "meta",
    ".png": "image",
    ".jpg": "image",
    ".jpeg": "image",
    ".svg": "image",
    ".webp": "image",
    ".ttf": "font",
    ".otf": "font",
    ".woff": "font",
    ".woff2": "font",
    ".wav": "audio",
    ".ogg": "audio",
    ".mp3": "audio",
}

LEAK_SCAN_EXTS = {".json", ".tscn", ".cfg", ".gd"}
RES_REF_EXTS = {".tscn", ".tres", ".json", ".cfg", ".gd"}

NON_RESOURCE_EXTS = {
    ".json",
    ".csv",
    ".txt",
    ".ini",
    ".yaml",
    ".yml",
    ".exe",
    ".dll",
    ".pdb",
    ".bat",
    ".ps1",
}


class ToolError(RuntimeError):
    """可预期的用法/环境错误：调用方应输出人话并以退出码 2 结束。"""


# ---------------------------------------------------------------------------
# 路径与哈希
# ---------------------------------------------------------------------------


def find_root(explicit: str | None = None) -> Path:
    """推断仓库根：优先 --root，其次脚本所在目录向上，最后当前目录向上。"""
    if explicit:
        return Path(explicit).expanduser().resolve()
    starts = [Path(__file__).resolve().parent, Path.cwd().resolve()]
    for start in starts:
        for candidate in (start, *start.parents):
            if (candidate / "apps" / "desktop" / "project.godot").is_file():
                return candidate
    return Path.cwd().resolve()


def require_project(root: Path) -> Path:
    project = Path(root) / "apps" / "desktop"
    if not (project / "project.godot").is_file():
        raise ToolError(
            f"在 {root} 下找不到 apps/desktop/project.godot；"
            "请用 --root <仓库根目录> 指定 game-task 根目录。"
        )
    return project


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_path(path: Path) -> str:
    path = Path(path)
    if path.is_dir():
        return directory_digest(path)
    return sha256_file(path)


def directory_digest(path: Path) -> str:
    """目录指纹：对 (相对路径, 文件 sha256) 排序后拼接再哈希。"""
    path = Path(path)
    lines = []
    for file_path in sorted(p for p in path.rglob("*") if p.is_file()):
        rel = file_path.relative_to(path).as_posix()
        lines.append(f"{rel}\t{sha256_file(file_path)}\n")
    return sha256_bytes("".join(lines).encode("utf-8"))


def rel_to_root(path: Path, root: Path) -> str | None:
    try:
        return Path(path).resolve().relative_to(Path(root).resolve()).as_posix()
    except (ValueError, OSError):
        return None


def format_bytes(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if value < 1024 or unit == "GiB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_text(path: Path) -> str:
    return Path(path).read_text(encoding="utf-8", errors="replace")


def write_text(path: Path, text: str) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def json_dumps(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


def write_json(path: Path, payload: dict) -> None:
    write_text(path, json_dumps(payload))


# ---------------------------------------------------------------------------
# 配置解析
# ---------------------------------------------------------------------------


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        inner = value[1:-1]
        return inner.replace('\\"', '"').replace("\\\\", "\\")
    return value


def parse_ini(text: str) -> tuple[list[str], dict[str, dict[str, str]]]:
    """解析 Godot 的 INI 风格 cfg；保留段顺序，值为未加引号的原始字符串。"""
    order: list[str] = []
    sections: dict[str, dict[str, str]] = {}
    current: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            if current not in sections:
                sections[current] = {}
                order.append(current)
            continue
        if current is None or "=" not in line:
            continue
        key, value = line.split("=", 1)
        sections[current][key.strip()] = _unquote(value.strip())
    return order, sections


def parse_project_godot(text: str) -> dict:
    features: list[str] = []
    match = re.search(r"config/features\s*=\s*PackedStringArray\(([^)]*)\)", text, re.S)
    if match:
        features = re.findall(r'"([^"]*)"', match.group(1))

    def quoted(key: str) -> str | None:
        found = re.search(re.escape(key) + r'\s*=\s*"([^"]*)"', text)
        return found.group(1) if found else None

    config_version = None
    version_match = re.search(r"^config_version\s*=\s*(\d+)", text, re.M)
    if version_match:
        config_version = int(version_match.group(1))

    return {
        "name": quoted("config/name"),
        "main_scene": quoted("run/main_scene"),
        "features": features,
        "config_version": config_version,
        "rendering_method": quoted("renderer/rendering_method"),
        "viewport": {
            "width": _quoted_int(text, "window/size/viewport_width"),
            "height": _quoted_int(text, "window/size/viewport_height"),
        },
    }


def _quoted_int(text: str, key: str) -> int | None:
    found = re.search(re.escape(key) + r"\s*=\s*(-?\d+)", text)
    return int(found.group(1)) if found else None


def parse_export_presets(text: str) -> list[dict]:
    order, sections = parse_ini(text)
    presets: list[dict] = []
    for section in order:
        match = re.fullmatch(r"preset\.(\d+)", section)
        if not match:
            continue
        data = sections[section]
        options = sections.get(f"{section}.options", {})
        presets.append(
            {
                "index": int(match.group(1)),
                "name": data.get("name", ""),
                "platform": data.get("platform", ""),
                "runnable": data.get("runnable", "").lower() == "true",
                "export_filter": data.get("export_filter", ""),
                "include_filter": data.get("include_filter", ""),
                "exclude_filter": data.get("exclude_filter", ""),
                "export_path": data.get("export_path", ""),
                "custom_features": data.get("custom_features", ""),
                "custom_template_debug": options.get("custom_template/debug", ""),
                "custom_template_release": options.get("custom_template/release", ""),
                "binary_format_architecture": options.get(
                    "binary_format/architecture", ""
                ),
                "embed_pck": options.get("binary_format/embed_pck", ""),
            }
        )
    return presets


def version_series(version: str | None) -> str | None:
    if not version:
        return None
    parts = re.findall(r"\d+", version)
    if not parts:
        return None
    if len(parts) == 1:
        return parts[0]
    return f"{parts[0]}.{parts[1]}"


def preset_version_evidence(presets_text: str | None) -> list[str]:
    """export_presets.cfg 通常不写引擎版本；只在字段值（自定义模板路径等）里找线索。

    整行注释（; 或 # 开头）不算版本字段，避免把"说明文字里的 4.6.3"当成交叉核对证据。
    """
    if not presets_text:
        return []
    lines = [
        line
        for line in presets_text.splitlines()
        if not line.strip().startswith((";", "#"))
    ]
    evidence: list[str] = []
    for match in re.finditer(r"(?<![\w.])(4\.\d+(?:\.\d+)?)(?![\w.])", "\n".join(lines)):
        evidence.append(match.group(1))
    return evidence


# ---------------------------------------------------------------------------
# 文件清单与分类
# ---------------------------------------------------------------------------


def classify_path(rel: str) -> str:
    suffix = PurePosixPath(rel).suffix.lower()
    return KIND_BY_EXT.get(suffix, "other")


def collect_project_files(project_dir: Path) -> list[dict]:
    project_dir = Path(project_dir)
    entries: list[dict] = []
    for dirpath, dirnames, filenames in os.walk(project_dir):
        dirnames[:] = sorted(d for d in dirnames if d.lower() not in IGNORED_DIR_NAMES)
        for name in sorted(filenames):
            path = Path(dirpath) / name
            if path.suffix.lower() in IGNORED_FILE_SUFFIXES:
                continue
            if path.relative_to(project_dir).as_posix() in GENERATED_DELIVERY_FILES:
                # 清单自己会被写进 delivery.json；再把它算进清单会形成"哈希包含自身"的循环，
                # 导致每次生成都变一个字节。这里显式跳过这些生成物，其余文件仍然全部纳入。
                continue
            try:
                data = path.read_bytes()
            except OSError as exc:  # 权限/占用等：明确报错，不静默跳过
                raise ToolError(f"无法读取 {path}: {exc}") from exc
            rel = path.relative_to(project_dir).as_posix()
            entries.append(
                {
                    "path": rel,
                    "bytes": len(data),
                    "sha256": sha256_bytes(data),
                    "kind": classify_path(rel),
                }
            )
    entries.sort(key=lambda item: item["path"])
    return entries


def extension_counts(files: list[dict]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for item in files:
        suffix = PurePosixPath(item["path"]).suffix.lower().lstrip(".") or "(none)"
        counts[suffix] = counts.get(suffix, 0) + 1
    return dict(sorted(counts.items()))


def kind_counts(files: list[dict]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for item in files:
        counts[item["kind"]] = counts.get(item["kind"], 0) + 1
    return dict(sorted(counts.items()))


def group_counts(files: list[dict]) -> dict[str, dict]:
    groups: dict[str, dict] = {}
    for item in files:
        rel = item["path"]
        top = rel.split("/", 1)[0] if "/" in rel else "(root)"
        entry = groups.setdefault(top, {"files": 0, "bytes": 0})
        entry["files"] += 1
        entry["bytes"] += item["bytes"]
    return {name: groups[name] for name in sorted(groups)}


def build_categories(files: list[dict]) -> dict[str, dict]:
    def category(predicate, required: bool, label: str) -> dict:
        matched = [item["path"] for item in files if predicate(item["path"])]
        return {"label": label, "required": required, "count": len(matched), "files": matched}

    return {
        "data_json": category(
            lambda rel: rel.startswith("data/") and rel.lower().endswith(".json"),
            True,
            "data/*.json 运行数据",
        ),
        "ui_scene": category(
            lambda rel: rel.startswith("ui/") and rel.lower().endswith(".tscn"),
            True,
            "ui/*.tscn 界面场景",
        ),
        "fonts": category(
            lambda rel: PurePosixPath(rel).suffix.lower() in {".ttf", ".otf", ".woff", ".woff2"}
            or "/fonts/" in rel.lower(),
            False,
            "字体资源（可选）",
        ),
        "assets": category(
            lambda rel: rel.startswith("assets/"),
            False,
            "assets/ 美术/音频（可选）",
        ),
    }


# ---------------------------------------------------------------------------
# 导出过滤规则
# ---------------------------------------------------------------------------


def _glob_to_regex(pattern: str) -> re.Pattern:
    out = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "*":
            if index + 1 < len(pattern) and pattern[index + 1] == "*":
                index += 2
                if index < len(pattern) and pattern[index] == "/":
                    out.append("(?:.*/)?")
                    index += 1
                else:
                    out.append(".*")
                continue
            out.append("[^/]*")
        elif char == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(char))
        index += 1
    return re.compile("^" + "".join(out) + "$")


def filter_matches(pattern: str, relpath: str) -> bool:
    pattern = pattern.strip().replace("\\", "/")
    if not pattern:
        return False
    relpath = relpath.replace("\\", "/")
    if pattern.startswith("*."):
        return fnmatch(relpath, pattern) or fnmatch(relpath.rsplit("/", 1)[-1], pattern)
    return bool(_glob_to_regex(pattern).match(relpath)) or fnmatch(relpath, pattern)


def split_filters(value: str) -> list[str]:
    return [part.strip() for part in (value or "").split(",") if part.strip()]


def diagnose_export_filters(files: list[dict], presets: list[dict]) -> dict:
    runtime_files = [
        item["path"]
        for item in files
        if PurePosixPath(item["path"]).suffix.lower() in NON_RESOURCE_EXTS
        and not item["path"].startswith("docs/")
    ]
    json_files = [rel for rel in runtime_files if rel.lower().endswith(".json")]

    per_preset = []
    for preset in presets:
        include = split_filters(preset.get("include_filter", ""))
        exclude = split_filters(preset.get("exclude_filter", ""))
        uncovered = [
            rel
            for rel in json_files
            if not any(filter_matches(pattern, rel) for pattern in include)
        ]
        excluded = [
            rel
            for rel in runtime_files
            if any(filter_matches(pattern, rel) for pattern in exclude)
        ]
        per_preset.append(
            {
                "index": preset["index"],
                "name": preset["name"],
                "export_filter": preset.get("export_filter", ""),
                "include_filter": preset.get("include_filter", ""),
                "exclude_filter": preset.get("exclude_filter", ""),
                "include_patterns": include,
                "exclude_patterns": exclude,
                "json_files": json_files,
                "json_uncovered": uncovered,
                "excluded_non_resource_files": excluded,
            }
        )

    return {
        "runtime_non_resource_files": runtime_files,
        "json_files": json_files,
        "presets": per_preset,
    }


# ---------------------------------------------------------------------------
# 绝对路径泄漏 / res:// 引用
# ---------------------------------------------------------------------------

LEAK_PATTERNS = [
    ("windows-absolute", re.compile(r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/][^\s\"'<>|]*")),
    ("unc-absolute", re.compile(r"\\\\[A-Za-z0-9_.\-]+\\[A-Za-z0-9$_.\-]+")),
    (
        "posix-absolute",
        re.compile(r"(?<![\w:/])/(?:home|Users|mnt|opt|var)/[^\s\"'<>|]*"),
    ),
    ("file-url", re.compile(r"file:///[^\s\"'<>|]*")),
]


def scan_absolute_paths(project_dir: Path, files: list[dict]) -> dict:
    project_dir = Path(project_dir)
    scanned = 0
    leaks: list[dict] = []
    for item in files:
        if PurePosixPath(item["path"]).suffix.lower() not in LEAK_SCAN_EXTS:
            continue
        path = project_dir / item["path"]
        scanned += 1
        text = read_text(path)
        seen: set[tuple[int, str]] = set()
        for line_number, line in enumerate(text.splitlines(), start=1):
            for kind, pattern in LEAK_PATTERNS:
                for match in pattern.finditer(line):
                    key = (line_number, kind)
                    if key in seen:
                        continue
                    seen.add(key)
                    leaks.append(
                        {
                            "file": item["path"],
                            "line": line_number,
                            "column": match.start() + 1,
                            "kind": kind,
                            "match": match.group(0)[:200],
                            "text": line.strip()[:200],
                        }
                    )
    leaks.sort(key=lambda entry: (entry["file"], entry["line"], entry["column"]))
    return {"scanned_files": scanned, "leaks": leaks}


def scan_resource_references(project_dir: Path, files: list[dict]) -> dict:
    project_dir = Path(project_dir)
    checked = 0
    references: list[dict] = []
    missing: list[dict] = []
    for item in files:
        if PurePosixPath(item["path"]).suffix.lower() not in RES_REF_EXTS:
            continue
        text = read_text(project_dir / item["path"])
        for match in re.finditer(r"res://([^\"'\s\)\]\},;]+)", text):
            raw = match.group(1).rstrip(".,;")
            if not raw or any(char in raw for char in "*%${}<>|"):
                continue
            checked += 1
            line_number = text.count("\n", 0, match.start()) + 1
            target = project_dir / raw
            entry = {"file": item["path"], "line": line_number, "ref": "res://" + raw}
            references.append(entry)
            if not target.exists():
                missing.append(entry)
    return {
        "checked": checked,
        "references": references,
        "missing": missing,
    }


# ---------------------------------------------------------------------------
# 引擎版本
# ---------------------------------------------------------------------------


def assess_engine(project_info: dict, presets_text: str | None, checks: list[dict]) -> dict:
    features = project_info.get("features") or []
    project_series = version_series(features[0]) if features else None
    preset_strings = preset_version_evidence(presets_text)
    preset_series_values = sorted({version_series(value) for value in preset_strings if version_series(value)})
    preset_series = preset_series_values[0] if len(preset_series_values) == 1 else None

    consistent = True
    if not features:
        consistent = False
        _add_check(
            checks,
            "engine-project-feature",
            "FAIL",
            "project.godot 没有 config/features，读不到引擎版本线索；任务要求 Godot 4.6 系（4.6.3）。",
        )
    elif project_series != EXPECTED_ENGINE_SERIES:
        consistent = False
        _add_check(
            checks,
            "engine-project-feature",
            "FAIL",
            f"project.godot 的 config/features 是 {features[0]!r}（{project_series} 系），"
            f"任务要求 {EXPECTED_ENGINE_SERIES} 系（{EXPECTED_ENGINE_VERSION}）；版本不一致，不能按 4.6 导出流程验收。",
        )
    else:
        _add_check(
            checks,
            "engine-project-feature",
            "PASS",
            f"project.godot 声明 {features[0]!r}（{project_series} 系），与任务要求的 "
            f"{EXPECTED_ENGINE_SERIES} 系（{EXPECTED_ENGINE_VERSION}）一致；精确补丁版本仍需 godot --version 核对。",
        )

    if preset_series_values:
        if preset_series_values == [EXPECTED_ENGINE_SERIES]:
            _add_check(
                checks,
                "engine-preset-crosscheck",
                "PASS",
                "export_presets.cfg 中的版本线索为 " + ", ".join(preset_strings) + "，与 4.6 系一致。",
            )
        else:
            consistent = False
            _add_check(
                checks,
                "engine-preset-crosscheck",
                "FAIL",
                "export_presets.cfg 的版本线索是 "
                + ", ".join(preset_strings)
                + f"，与 project.godot 的 {project_series or '未知'} 系不一致；模板/预设必须和编辑器版本完全匹配。",
            )
    else:
        _add_check(
            checks,
            "engine-preset-crosscheck",
            "INFO",
            "export_presets.cfg 没有引擎版本字段或自定义模板路径，无法交叉核对；"
            f"当前以 project.godot 的 {project_series or '未知'} 系为准，4.6.3 的精确版本需实机 `godot --version` 确认。",
        )

    return {
        "expected_series": EXPECTED_ENGINE_SERIES,
        "expected_engine": EXPECTED_ENGINE_VERSION,
        "project_features": features,
        "project_series": project_series,
        "preset_version_strings": preset_strings,
        "preset_series": preset_series,
        "consistent": consistent,
        "note": "静态核对只能确认 4.6 系；4.6.3 精确补丁版本与导出模板必须用引擎实机确认。",
    }


# ---------------------------------------------------------------------------
# 助手（可选模块）与其他工程外文件
# ---------------------------------------------------------------------------


def collect_helper_info(root: Path) -> dict:
    helper_dir = Path(root) / "tools" / "windows-typing"
    if not helper_dir.is_dir():
        return {"path": "tools/windows-typing", "exists": False, "files": []}
    files = []
    for path in sorted(p for p in helper_dir.rglob("*") if p.is_file()):
        rel = path.relative_to(Path(root)).as_posix()
        files.append({"path": rel, "bytes": path.stat().st_size, "sha256": sha256_file(path)})
    return {"path": "tools/windows-typing", "exists": True, "files": files}


# ---------------------------------------------------------------------------
# 检查项
# ---------------------------------------------------------------------------


def _add_check(checks: list[dict], check_id: str, level: str, message: str, evidence=None) -> None:
    if level not in LEVELS:
        raise ValueError(f"未知检查级别: {level}")
    entry = {"id": check_id, "level": level, "message": message}
    if evidence:
        entry["evidence"] = evidence
    checks.append(entry)


def summarize_checks(checks: list[dict]) -> dict:
    counts = {level.lower(): 0 for level in LEVELS}
    for check in checks:
        counts[check["level"].lower()] += 1
    if counts["fail"]:
        status = "fail"
    elif counts["warn"]:
        status = "warn"
    else:
        status = "pass"
    return {
        "pass": counts["pass"],
        "warn": counts["warn"],
        "fail": counts["fail"],
        "info": counts["info"],
        "status": status,
    }


def render_checks_text(checks: list[dict]) -> list[str]:
    lines = []
    for level in LEVELS:
        for check in checks:
            if check["level"] != level:
                continue
            line = f"[{level}] {check['id']}: {check['message']}"
            lines.append(line)
            evidence = check.get("evidence") or []
            for item in evidence[:8]:
                lines.append(f"        - {item}")
            if len(evidence) > 8:
                lines.append(f"        - ... 另有 {len(evidence) - 8} 条")
    return lines
