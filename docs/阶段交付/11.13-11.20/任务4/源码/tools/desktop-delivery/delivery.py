#!/usr/bin/env python3
"""把静态构建清单 + 声明文件合成 docs/交付/任务4/delivery.json。

硬规则：
- `tests[].result == "passed"` 必须同时满足 `ran == true` 且 evidence 文件真实存在且非空；
  否则整条降级为 `unverified` 并让脚本退出码为 1。
- 没有 git 时 `git_commit` 写 null，并给出 `git_commit_unavailable_reason`，不伪造提交号。
- `untested` 必须明确列出未测项；自动补充"未执行引擎/无法核对"的事实。

用法：
    python tools/desktop-delivery/delivery.py --root . --claims claims.json
    python tools/desktop-delivery/delivery.py --root . --claims claims.json --stdout --json

退出码：0 = 所有 claim 都有真实证据且无硬失败；1 = 有 unverified/failed/缺产物/引擎不一致；2 = 用法/文件错误。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import delivery_common as common
import build_manifest as manifest_tool
from delivery_common import DELIVERY_SCHEMA, TOOL_VERSION, ToolError

ALLOWED_TEST_RESULTS = {"passed", "failed", "skipped", "unverified"}


# ---------------------------------------------------------------------------
# 路径与声明解析
# ---------------------------------------------------------------------------


def _display_path(root: Path, path: Path, original: str) -> str:
    rel = common.rel_to_root(path, root)
    if rel:
        return rel
    if Path(original).is_absolute():
        return f"<外部>/{Path(original).name}"
    return original


def _resolve(root: Path, claims_dir: Path, value: str) -> tuple[Path, str]:
    candidate = Path(value).expanduser()
    if candidate.is_absolute():
        return candidate, _display_path(root, candidate, value)
    root_candidate = (root / candidate).resolve()
    if root_candidate.exists():
        return root_candidate, _display_path(root, root_candidate, value)
    claims_candidate = (claims_dir / candidate).resolve()
    if claims_candidate.exists():
        return claims_candidate, _display_path(root, claims_candidate, value)
    return root_candidate, value


def _load_json(path: Path, label: str) -> dict:
    if not path.is_file():
        raise ToolError(f"找不到{label}：{path}")
    try:
        payload = json.loads(common.read_text(path))
    except json.JSONDecodeError as exc:
        raise ToolError(f"{label} 不是合法 JSON（{path}）：{exc}") from exc
    if not isinstance(payload, dict):
        raise ToolError(f"{label} 顶层必须是 JSON 对象：{path}")
    return payload


# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------


def detect_git_commit(root: Path) -> tuple[str | None, str | None]:
    git_path = Path(root) / ".git"
    if not git_path.exists():
        return None, (
            "本机没有 git 可执行文件，仓库根目录也没有 .git，无法得到真实提交号；"
            "delivery.json 按约定写 null，不伪造。"
        )
    try:
        if git_path.is_file():  # worktree/submodule：.git 是文件
            match = re.search(r"gitdir:\s*(.+)", common.read_text(git_path))
            if not match:
                return None, ".git 是文件但读不到 gitdir 行，提交号不可用。"
            git_path = Path(match.group(1).strip())
            if not git_path.is_absolute():
                git_path = (Path(root) / git_path).resolve()
        head_path = git_path / "HEAD"
        if not head_path.is_file():
            return None, ".git 存在但没有 HEAD，提交号不可用。"
        head = common.read_text(head_path).strip()
        if head.startswith("ref: "):
            ref = head[len("ref: ") :].strip()
            ref_file = git_path / ref
            if ref_file.is_file():
                commit = common.read_text(ref_file).strip()
                if commit:
                    return commit, None
            packed = git_path / "packed-refs"
            if packed.is_file():
                for line in common.read_text(packed).splitlines():
                    if line.startswith("#") or not line.strip():
                        continue
                    parts = line.split()
                    if len(parts) == 2 and parts[1] == ref:
                        return parts[0], None
            return None, f".git 里有 {ref} 引用但读不到对应 commit，提交号不可用。"
        if re.fullmatch(r"[0-9a-f]{40}", head):
            return head, None
        return None, ".git/HEAD 内容不是 commit 也不是 ref，提交号不可用。"
    except OSError as exc:
        return None, f"读取 .git 失败：{exc}；提交号不可用。"


# ---------------------------------------------------------------------------
# modules / tests / artifacts
# ---------------------------------------------------------------------------


def build_modules(root: Path, claims_dir: Path, claims: dict) -> tuple[list[dict], list[str]]:
    modules: list[dict] = []
    warnings: list[str] = []
    raw_modules = claims.get("modules") or []
    if not isinstance(raw_modules, list):
        raise ToolError("claims.modules 必须是数组。")
    for index, item in enumerate(raw_modules):
        if not isinstance(item, dict):
            raise ToolError(f"claims.modules[{index}] 必须是对象。")
        name = str(item.get("name") or item.get("id") or f"module-{index}")
        version = item.get("version")
        path_value = item.get("path")
        entry = {"name": name, "version": version}
        if path_value:
            path, display = _resolve(root, claims_dir, str(path_value))
            entry["path"] = display
            if path.exists():
                entry["exists"] = True
                entry["sha256"] = common.sha256_path(path)
                entry["sha256_source"] = "filesystem"
                entry["bytes"] = path.stat().st_size if path.is_file() else None
            else:
                entry["exists"] = False
                entry["sha256"] = item.get("sha256")
                entry["sha256_source"] = "claims" if item.get("sha256") else None
                entry["warning"] = "模块路径不存在，无法复核哈希。"
                warnings.append(f"模块 {name} 的路径不存在：{path_value}")
        else:
            entry["path"] = None
            entry["exists"] = None
            entry["sha256"] = item.get("sha256")
            entry["sha256_source"] = "claims" if item.get("sha256") else None
            if not item.get("sha256"):
                entry["warning"] = "claims 既没有 path 也没有 sha256，模块无法核对。"
                warnings.append(f"模块 {name} 没有 path/sha256。")
        modules.append(entry)
    return modules, warnings


def build_tests(root: Path, claims_dir: Path, claims: dict) -> list[dict]:
    raw_tests = claims.get("tests") or []
    if not isinstance(raw_tests, list):
        raise ToolError("claims.tests 必须是数组。")
    tests: list[dict] = []
    for index, item in enumerate(raw_tests):
        if not isinstance(item, dict):
            raise ToolError(f"claims.tests[{index}] 必须是对象。")
        test_id = str(item.get("id") or f"test-{index}")
        result = str(item.get("result") or "").strip().lower()
        ran = item.get("ran") is True
        evidence_value = item.get("evidence")
        evidence_path = None
        evidence_exists = False
        evidence_bytes = None
        display = None
        if evidence_value:
            evidence_path, display = _resolve(root, claims_dir, str(evidence_value))
            evidence_exists = evidence_path.is_file()
            if evidence_exists:
                evidence_bytes = evidence_path.stat().st_size

        notes: list[str] = []
        if not evidence_value:
            notes.append("缺少 evidence：每条 claim 必须带证据文件路径。")
        elif not evidence_exists:
            notes.append(f"证据文件不存在：{evidence_value}")
        elif evidence_bytes == 0:
            notes.append(f"证据文件为空：{evidence_value}")

        if result not in ALLOWED_TEST_RESULTS:
            notes.append(f"result={result or '(空)'} 不是 {sorted(ALLOWED_TEST_RESULTS)} 之一。")

        status = "unverified"
        if notes:
            status = "unverified"
        elif result == "passed":
            if not ran:
                status = "unverified"
                notes.append("claim 声明 passed，但 ran 不为 true：只有真实执行过才能写 passed。")
            else:
                status = "passed"
        elif result == "failed":
            status = "failed"
        elif result == "skipped":
            status = "skipped"
        else:
            status = "unverified"
            notes.append("claim 自述未验证。")

        tests.append(
            {
                "id": test_id,
                "name": item.get("name") or test_id,
                "command": item.get("command"),
                "ran": ran,
                "result": result or None,
                "status": status,
                "verified": status == "passed",
                "evidence": display,
                "evidence_exists": evidence_exists,
                "evidence_bytes": evidence_bytes,
                "notes": notes,
            }
        )
    return tests


def build_artifacts(root: Path, claims_dir: Path, claims: dict) -> tuple[list[dict], list[str]]:
    raw_artifacts = claims.get("artifacts") or []
    if not isinstance(raw_artifacts, list):
        raise ToolError("claims.artifacts 必须是数组。")
    artifacts: list[dict] = []
    missing: list[str] = []
    for index, item in enumerate(raw_artifacts):
        if isinstance(item, str):
            path_value = item
            meta: dict = {}
        elif isinstance(item, dict):
            path_value = item.get("path")
            meta = item
        else:
            raise ToolError(f"claims.artifacts[{index}] 必须是字符串或对象。")
        if not path_value:
            raise ToolError(f"claims.artifacts[{index}] 缺少 path。")
        path, display = _resolve(root, claims_dir, str(path_value))
        entry = {
            "path": display,
            "kind": meta.get("kind"),
            "exists": path.is_file(),
            "bytes": None,
            "sha256": None,
        }
        if entry["exists"]:
            entry["bytes"] = path.stat().st_size
            entry["sha256"] = common.sha256_file(path)
        else:
            missing.append(str(path_value))
            entry["warning"] = "产物文件不存在，无法交付。"
        artifacts.append(entry)
    return artifacts, missing


# ---------------------------------------------------------------------------
# 合成
# ---------------------------------------------------------------------------


def build_delivery(
    root: Path,
    manifest: dict,
    claims: dict,
    claims_path: Path,
    git_override: str | None,
    stamp: bool,
) -> tuple[dict, list[str]]:
    claims_dir = claims_path.parent
    modules, module_warnings = build_modules(root, claims_dir, claims)
    tests = build_tests(root, claims_dir, claims)
    artifacts, missing_artifacts = build_artifacts(root, claims_dir, claims)

    if git_override:
        git_commit = git_override
        git_reason = None
    else:
        git_commit, git_reason = detect_git_commit(root)

    engine = manifest.get("engine") or {}
    engine_block = {
        "expected_series": engine.get("expected_series"),
        "expected_engine": engine.get("expected_engine"),
        "reported_by_project": engine.get("project_series"),
        "consistent": bool(engine.get("consistent")),
        "preset_version_strings": engine.get("preset_version_strings", []),
        "note": engine.get("note")
        or "静态核对只能确认 4.6 系；4.6.3 精确版本与模板需引擎实机确认。",
    }

    manifest_path_value = claims.get("manifest")
    manifest_block: dict = {"summary": manifest.get("summary")}
    if manifest_path_value:
        manifest_path, manifest_display = _resolve(root, claims_dir, str(manifest_path_value))
        manifest_block.update(
            {
                "path": manifest_display,
                "exists": manifest_path.is_file(),
                "sha256": common.sha256_file(manifest_path) if manifest_path.is_file() else None,
            }
        )
    else:
        manifest_block.update(
            {
                "source": "generated-in-memory",
                "sha256": common.sha256_bytes(common.json_dumps(manifest).encode("utf-8")),
            }
        )

    untested: list[dict] = []
    raw_untested = claims.get("untested") or []
    if not isinstance(raw_untested, list):
        raise ToolError("claims.untested 必须是数组。")
    for item in raw_untested:
        untested.append({"item": str(item), "source": "claims"})

    engine_claimed = any(
        test.get("ran") and "godot" in str(test.get("command") or "").lower()
        for test in tests
    )
    if not git_commit:
        untested.append({"item": "git 提交号（本机没有 git/.git，无法记录）", "source": "auto"})
    if not engine_claimed:
        untested.append(
            {
                "item": "Godot 引擎实机导出/启动/桌面运行（本次交付生成没有真实引擎日志）",
                "source": "auto",
            }
        )
    if not engine.get("preset_version_strings"):
        untested.append(
            {
                "item": "导出预设与引擎版本的交叉核对（export_presets.cfg 无版本字段，只能实机核对）",
                "source": "auto",
            }
        )

    diagnostics = {
        "manifest_summary": manifest.get("summary"),
        "checks": [
            {"id": check["id"], "level": check["level"], "message": check["message"]}
            for check in manifest.get("checks", [])
        ],
        "warnings": module_warnings,
    }

    task = claims.get("task") or {}
    if not isinstance(task, dict):
        raise ToolError("claims.task 必须是对象。")

    hard_failures: list[str] = []
    if not engine_block["consistent"]:
        hard_failures.append("engine-version-inconsistent")
    if (manifest.get("summary") or {}).get("fail", 0) > 0:
        hard_failures.append("manifest-has-fail")
    if any(test["status"] == "failed" for test in tests):
        hard_failures.append("test-failed")
    if missing_artifacts:
        hard_failures.append("artifact-missing")

    unverified_count = sum(1 for test in tests if test["status"] == "unverified")
    if hard_failures:
        status = "fail"
    elif unverified_count:
        status = "unverified"
    elif module_warnings:
        status = "warn"
    else:
        status = "ok"

    summary = {
        "tests_total": len(tests),
        "tests_passed_verified": sum(1 for test in tests if test["status"] == "passed"),
        "tests_failed": sum(1 for test in tests if test["status"] == "failed"),
        "tests_skipped": sum(1 for test in tests if test["status"] == "skipped"),
        "tests_unverified": unverified_count,
        "modules": len(modules),
        "artifacts": len(artifacts),
        "artifacts_missing": len(missing_artifacts),
        "untested": len(untested),
        "hard_failures": hard_failures,
        "status": status,
    }

    delivery = {
        "schema": DELIVERY_SCHEMA,
        "tool_version": TOOL_VERSION,
        "generated_at_utc": common.iso_now() if stamp else None,
        "task": {
            "id": str(task.get("id") or "T4-08/T4-12"),
            "title": str(
                task.get("title") or "可重复导出与资源诊断 + 阶段包与交付工具"
            ),
            "stage": task.get("stage"),
        },
        "git_commit": git_commit,
        "git_commit_unavailable_reason": git_reason,
        "engine_version": engine_block,
        "modules": modules,
        "tests": tests,
        "untested": untested,
        "artifacts": artifacts,
        "manifest": manifest_block,
        "diagnostics": diagnostics,
        "claims_file": {
            "path": _display_path(root, claims_path, str(claims_path)),
            "sha256": common.sha256_file(claims_path),
        },
        "summary": summary,
        "status": status,
    }
    return delivery, missing_artifacts


def render_text(delivery: dict) -> str:
    engine = delivery["engine_version"]
    summary = delivery["summary"]
    lines = [
        f"交付清单 · {delivery['task']['id']}"
        + (f"（阶段 {delivery['task']['stage']}）" if delivery["task"].get("stage") else ""),
        f"状态：{delivery['status'].upper()}",
    ]
    if delivery["git_commit"]:
        lines.append(f"git_commit：{delivery['git_commit']}")
    else:
        lines.append(f"git_commit：null — {delivery['git_commit_unavailable_reason']}")
    lines.append(
        "引擎："
        f"{engine.get('reported_by_project') or '(未知)'} 系 / 期望 {engine.get('expected_engine')}"
        f" → {'一致' if engine.get('consistent') else '不一致'}"
    )
    lines.append(f"模块：{summary['modules']} 个；测试：{summary['tests_total']} 条")
    lines.append(
        f"测试结果：passed {summary['tests_passed_verified']} / failed {summary['tests_failed']} / "
        f"skipped {summary['tests_skipped']} / unverified {summary['tests_unverified']}"
    )
    lines.append(f"未测项：{summary['untested']} 条；产物：{summary['artifacts']} 个")
    lines.append("")
    for test in delivery["tests"]:
        if test["status"] == "passed":
            lines.append(f"[PASS] {test['id']}: {test['name']}")
        elif test["status"] == "unverified":
            reason = "; ".join(test["notes"]) or "未验证"
            lines.append(f"[UNVERIFIED] {test['id']}: {reason}")
        elif test["status"] == "failed":
            lines.append(f"[FAIL] {test['id']}: claim 记录为失败")
        else:
            lines.append(f"[SKIPPED] {test['id']}: 未执行")
    for item in delivery["untested"]:
        lines.append(f"[UNTESTED/{item['source']}] {item['item']}")
    if delivery["summary"]["hard_failures"]:
        lines.append("硬失败：" + ", ".join(delivery["summary"]["hard_failures"]))
    lines.append("")
    lines.append("说明：只有 ran=true 且证据文件存在的测试才是 passed；本文件不是导出成功证明。")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="把构建清单 + 声明文件合成为 delivery.json。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--root", help="仓库根目录（默认推断）")
    parser.add_argument("--manifest", help="build_manifest.py 生成的 JSON；省略则现场生成")
    parser.add_argument("--claims", required=True, help="声明文件 JSON（必须提供）")
    parser.add_argument(
        "--out",
        default="apps/desktop/docs/交付/任务4/delivery.json",
        help="输出路径（默认 docs/交付/任务4/delivery.json，相对仓库根）",
    )
    parser.add_argument("--stdout", action="store_true", help="输出到 stdout，不写文件")
    parser.add_argument("--json", action="store_true", help="JSON 格式（默认文本摘要）")
    parser.add_argument("--git-commit", help="手动指定提交号（不建议；本机无 git 时应保持 null）")
    parser.add_argument("--stamp", action="store_true", help="写入 generated_at_utc")
    args = parser.parse_args(argv)

    try:
        root = common.find_root(args.root)
        common.require_project(root)
        claims_path = Path(args.claims).expanduser()
        if not claims_path.is_absolute():
            claims_path = (Path.cwd() / claims_path).resolve()
        claims = _load_json(claims_path, "声明文件")

        if args.manifest:
            manifest_path = Path(args.manifest).expanduser()
            if not manifest_path.is_absolute():
                manifest_path = (Path.cwd() / manifest_path).resolve()
            manifest = _load_json(manifest_path, "构建清单")
            if "files" not in manifest or "engine" not in manifest:
                raise ToolError(
                    f"构建清单缺少 files/engine 字段，可能不是 build_manifest.py 的输出：{manifest_path}"
                )
        else:
            manifest = manifest_tool.build_manifest_data(root)

        delivery, missing_artifacts = build_delivery(
            root, manifest, claims, claims_path, args.git_commit, args.stamp
        )
    except ToolError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    payload = common.json_dumps(delivery) if args.json else render_text(delivery)

    if args.stdout:
        sys.stdout.write(payload)
    else:
        out_path = Path(args.out).expanduser()
        if not out_path.is_absolute():
            out_path = root / out_path
        common.write_text(out_path, payload)
        print(
            f"已写入交付清单：{out_path}（status={delivery['status']}）",
            file=sys.stderr,
        )
        if not args.json:
            sys.stdout.write(render_text(delivery))

    if missing_artifacts:
        print(
            "缺少产物：" + ", ".join(missing_artifacts),
            file=sys.stderr,
        )

    return 1 if delivery["status"] in {"fail", "unverified"} else 0


if __name__ == "__main__":
    sys.exit(main())
