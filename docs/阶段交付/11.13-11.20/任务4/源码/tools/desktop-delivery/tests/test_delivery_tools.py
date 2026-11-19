#!/usr/bin/env python3
"""tools/desktop-delivery 的自测（unittest，仅标准库）。

在临时目录造 3 类假仓库：正常 / 版本不符 / 有绝对路径泄漏，
通过 subprocess 调用真实脚本，断言退出码与关键字。

运行：
    python -m unittest discover -s tools/desktop-delivery/tests -v
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
TOOLS_DIR = TESTS_DIR.parent
REPO_ROOT = TOOLS_DIR.parents[1]
PYTHON = sys.executable

BASE_ENV = dict(os.environ)
BASE_ENV.update({"PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8"})


def make_temp_dir(prefix: str) -> Path:
    """在系统临时目录下造一个可写目录。

    注意：不用 tempfile.mkdtemp/TemporaryDirectory —— 它们以 0o700 创建目录，
    在部分 Windows 沙箱下该目录后续无法写入子文件。这里显式用可写的默认权限创建。
    """
    base = Path(tempfile.gettempdir()) / "dsh-desktop-delivery-tests"
    base.mkdir(parents=True, exist_ok=True)
    path = base / f"{prefix}{uuid.uuid4().hex}"
    path.mkdir()
    probe = path / ".write-probe"
    probe.write_text("ok", encoding="utf-8")
    probe.unlink()
    return path


def run_tool(script: str, *args: str, env: dict | None = None, cwd: Path | None = None):
    command = [PYTHON, str(TOOLS_DIR / script), *args]
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env or BASE_ENV,
        cwd=str(cwd) if cwd else None,
        timeout=180,
    )


def make_repo(
    base: Path,
    *,
    feature: str = "4.6",
    include_filter: str = "",
    leak: bool = False,
    preset_name: str = "Windows Desktop",
) -> Path:
    project = base / "apps" / "desktop"
    (project / "ui").mkdir(parents=True)
    (project / "data").mkdir()
    (project / "core").mkdir()
    (project / "docs").mkdir()

    (project / "project.godot").write_text(
        "config_version=5\n"
        "\n"
        "[application]\n"
        'config/name="Fixture Kingdom"\n'
        'run/main_scene="res://ui/main.tscn"\n'
        f'config/features=PackedStringArray("{feature}", "GL Compatibility")\n'
        "\n"
        "[display]\n"
        "window/size/viewport_width=960\n"
        "window/size/viewport_height=620\n"
        "\n"
        "[rendering]\n"
        'renderer/rendering_method="gl_compatibility"\n',
        encoding="utf-8",
    )
    (project / "export_presets.cfg").write_text(
        "[preset.0]\n"
        "\n"
        f'name="{preset_name}"\n'
        'platform="Windows Desktop"\n'
        "runnable=true\n"
        'export_filter="all_resources"\n'
        f'include_filter="{include_filter}"\n'
        'exclude_filter=""\n'
        'export_path="builds/windows/KingdomDesktop.exe"\n'
        "\n"
        "[preset.0.options]\n"
        "\n"
        'custom_template/debug=""\n'
        'custom_template/release=""\n'
        'binary_format/architecture="x86_64"\n',
        encoding="utf-8",
    )
    (project / "ui" / "main.gd").write_text(
        'extends Control\n\nconst KINGDOM = preload("res://core/kingdom.gd")\n',
        encoding="utf-8",
    )
    (project / "ui" / "main.tscn").write_text(
        "[gd_scene load_steps=2 format=3]\n"
        "\n"
        '[ext_resource type="Script" path="res://ui/main.gd" id="1"]\n'
        "\n"
        '[node name="Main" type="Control"]\n'
        'script = ExtResource("1")\n',
        encoding="utf-8",
    )
    (project / "core" / "kingdom.gd").write_text(
        "extends RefCounted\n\nfunc ping() -> String:\n\treturn \"pong\"\n",
        encoding="utf-8",
    )
    (project / "data" / "building_slots.json").write_text(
        '{\n  "version": 1,\n  "slots": []\n}\n', encoding="utf-8"
    )
    (project / "README.md").write_text("# fixture\n", encoding="utf-8")

    if leak:
        (project / "data" / "save_paths.json").write_text(
            '{\n  "save": "C:\\\\Users\\\\tester\\\\AppData\\\\save.json"\n}\n',
            encoding="utf-8",
        )
    return base


def empty_environment(base: Path) -> dict:
    empty = base / "empty-bin"
    empty.mkdir(exist_ok=True)
    env = dict(BASE_ENV)
    env["PATH"] = str(empty)
    env["PROGRAMFILES"] = str(empty)
    env["PROGRAMFILES(X86)"] = str(empty)
    env["LOCALAPPDATA"] = str(empty)
    env.pop("GODOT_BIN", None)
    return env


class ManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.base = make_temp_dir("manifest-")
        self.root = make_repo(self.base)

    def tearDown(self) -> None:
        shutil.rmtree(self.base, ignore_errors=True)

    def test_good_repo_passes_and_is_deterministic(self) -> None:
        first = run_tool("build_manifest.py", "--root", str(self.root), "--json")
        second = run_tool("build_manifest.py", "--root", str(self.root), "--json")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual(first.stdout, second.stdout, "同输入两次 JSON 输出应完全一致")
        payload = json.loads(first.stdout)
        self.assertEqual(payload["summary"]["fail"], 0)
        self.assertTrue(payload["engine"]["consistent"])
        self.assertGreater(payload["file_count"], 0)
        self.assertIsNone(payload["generated_at_utc"])
        self.assertEqual(payload["project_dir"], "apps/desktop")

    def test_text_mode_warns_about_json_filters(self) -> None:
        proc = run_tool("build_manifest.py", "--root", str(self.root), "--text")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("WARN", proc.stdout)
        self.assertIn("包内会缺 JSON", proc.stdout)
        self.assertIn("实机核对", proc.stdout)
        self.assertIn("data/building_slots.json", proc.stdout)

    def test_version_mismatch_fails(self) -> None:
        root = make_repo(self.base / "v47", feature="4.7")
        proc = run_tool("build_manifest.py", "--root", str(root), "--text")
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("FAIL", proc.stdout)
        self.assertIn("4.7", proc.stdout)
        self.assertIn("不一致", proc.stdout)
        payload = json.loads(
            run_tool("build_manifest.py", "--root", str(root), "--json").stdout
        )
        self.assertFalse(payload["engine"]["consistent"])

    def test_absolute_path_leak_fails_with_file_line(self) -> None:
        root = make_repo(self.base / "leak", leak=True)
        proc = run_tool("build_manifest.py", "--root", str(root), "--text")
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("绝对路径", proc.stdout)
        self.assertIn("save_paths.json:2", proc.stdout)
        payload = json.loads(
            run_tool("build_manifest.py", "--root", str(root), "--json").stdout
        )
        self.assertEqual(len(payload["absolute_path_scan"]["leaks"]), 1)

    def test_out_file_and_usage_error(self) -> None:
        out_path = self.base / "manifest.json"
        proc = run_tool(
            "build_manifest.py", "--root", str(self.root), "--json", "--out", str(out_path)
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(out_path.is_file())
        payload = json.loads(out_path.read_text(encoding="utf-8"))
        self.assertEqual(payload["schema"], "desktop-delivery/build-manifest/1")

        bad = run_tool("build_manifest.py", "--root", str(self.base / "nowhere"), "--text")
        self.assertEqual(bad.returncode, 2)
        self.assertIn("ERROR", bad.stderr)


class ExportCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.base = make_temp_dir("export-")
        self.root = make_repo(self.base)
        self.env = empty_environment(self.base)

    def tearDown(self) -> None:
        shutil.rmtree(self.base, ignore_errors=True)

    def test_blocked_without_godot(self) -> None:
        missing = self.base / "no-such-godot.exe"
        proc = run_tool(
            "export_check.py",
            "--root",
            str(self.root),
            "--godot",
            str(missing),
            env=self.env,
        )
        self.assertEqual(proc.returncode, 2, proc.stdout + proc.stderr)
        self.assertIn("BLOCKED: godot not found", proc.stdout)
        self.assertIn("godot-not-installed", proc.stdout)
        self.assertIn("未执行", proc.stdout)

    def test_plan_contains_export_pack_before_release(self) -> None:
        missing = self.base / "no-such-godot.exe"
        proc = run_tool(
            "export_check.py",
            "--root",
            str(self.root),
            "--godot",
            str(missing),
            "--json",
            env=self.env,
        )
        self.assertEqual(proc.returncode, 2)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "blocked")
        names = [step["name"] for step in payload["plan"]["steps"]]
        self.assertLess(names.index("export-pack"), names.index("export-release"))
        self.assertEqual(payload["preflight"]["selected_preset"], "Windows Desktop")
        self.assertTrue(all(step["ran"] is False for step in payload["plan"]["steps"]))

    def test_preset_name_is_case_sensitive(self) -> None:
        proc = run_tool(
            "export_check.py",
            "--root",
            str(self.root),
            "--preset",
            "windows desktop",
            "--json",
            env=self.env,
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "preset-missing")
        self.assertTrue(any("大小写" in item for item in payload["warnings"]))


class DeliveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.base = make_temp_dir("delivery-")
        self.root = make_repo(self.base)
        evidence_dir = self.root / "docs" / "evidence"
        evidence_dir.mkdir(parents=True)
        (evidence_dir / "manifest.log").write_text("manifest ok\n", encoding="utf-8")
        self.claims_path = self.root / "claims.json"

    def tearDown(self) -> None:
        shutil.rmtree(self.base, ignore_errors=True)

    def write_claims(self, **overrides) -> None:
        claims = {
            "task": {"id": "T4-08/T4-12", "title": "fixture", "stage": "24"},
            "modules": [
                {"name": "core", "version": "0.5", "path": "apps/desktop/core/kingdom.gd"}
            ],
            "tests": [
                {
                    "id": "manifest-static",
                    "name": "静态清单",
                    "command": "python tools/desktop-delivery/build_manifest.py --root .",
                    "ran": True,
                    "result": "passed",
                    "evidence": "docs/evidence/manifest.log",
                }
            ],
            "untested": ["实机导出"],
            "artifacts": [],
        }
        claims.update(overrides)
        self.claims_path.write_text(
            json.dumps(claims, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def test_passed_with_real_evidence_is_ok(self) -> None:
        self.write_claims()
        out_path = self.root / "docs" / "交付" / "任务4" / "delivery.json"
        proc = run_tool(
            "delivery.py",
            "--root",
            str(self.root),
            "--claims",
            str(self.claims_path),
            "--out",
            str(out_path),
            "--json",
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        payload = json.loads(out_path.read_text(encoding="utf-8"))
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["tests"][0]["status"], "passed")
        self.assertTrue(payload["tests"][0]["verified"])
        self.assertIsNone(payload["git_commit"])
        self.assertTrue(payload["git_commit_unavailable_reason"])
        self.assertEqual(len(payload["modules"][0]["sha256"]), 64)
        self.assertTrue(payload["untested"])

    def test_passed_with_missing_evidence_is_unverified(self) -> None:
        self.write_claims(
            tests=[
                {
                    "id": "fake-pass",
                    "name": "没有证据",
                    "command": "echo ok",
                    "ran": True,
                    "result": "passed",
                    "evidence": "docs/evidence/missing.log",
                }
            ]
        )
        proc = run_tool(
            "delivery.py",
            "--root",
            str(self.root),
            "--claims",
            str(self.claims_path),
            "--stdout",
            "--json",
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "unverified")
        self.assertEqual(payload["tests"][0]["status"], "unverified")
        self.assertFalse(payload["tests"][0]["verified"])
        self.assertTrue(any("不存在" in note for note in payload["tests"][0]["notes"]))

    def test_passed_without_ran_is_unverified(self) -> None:
        self.write_claims(
            tests=[
                {
                    "id": "not-run",
                    "name": "没跑过",
                    "command": "echo ok",
                    "ran": False,
                    "result": "passed",
                    "evidence": "docs/evidence/manifest.log",
                }
            ]
        )
        proc = run_tool(
            "delivery.py",
            "--root",
            str(self.root),
            "--claims",
            str(self.claims_path),
            "--stdout",
            "--json",
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["tests"][0]["status"], "unverified")
        self.assertTrue(any("ran" in note for note in payload["tests"][0]["notes"]))

    def test_missing_artifact_is_hard_failure(self) -> None:
        self.write_claims(artifacts=["dist/KingdomDesktop.zip"])
        proc = run_tool(
            "delivery.py",
            "--root",
            str(self.root),
            "--claims",
            str(self.claims_path),
            "--stdout",
            "--json",
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["status"], "fail")
        self.assertIn("artifact-missing", payload["summary"]["hard_failures"])


class StartupNotesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.base = make_temp_dir("notes-")
        self.root = make_repo(self.base)

    def tearDown(self) -> None:
        shutil.rmtree(self.base, ignore_errors=True)

    def test_notes_are_marked_unverified(self) -> None:
        out_path = self.root / "docs" / "交付" / "任务4" / "启动说明.md"
        proc = run_tool(
            "startup_notes.py", "--root", str(self.root), "--out", str(out_path)
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        text = out_path.read_text(encoding="utf-8")
        self.assertIn("4.6.3", text)
        self.assertIn("未验证", text)
        self.assertIn("res://ui/main.tscn", text)
        self.assertIn("Windows Desktop", text)
        self.assertNotIn("已验证可运行", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
