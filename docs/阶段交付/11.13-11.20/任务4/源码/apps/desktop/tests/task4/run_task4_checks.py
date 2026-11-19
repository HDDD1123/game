"""任务4 引擎侧检查运行器：真实调用 Godot 4.6.3 headless，记录每条的完整证据。

做四件事：
  1. 探测 Godot（--godot 参数 > 工作区 .tools/godot-4.6.3 > PATH），打印 --version；
  2. 导入工程（--headless --path apps/desktop --import），生成 .godot 缓存；
  3. 依次跑 3 个任务4 测试 + 8 组原有回归，逐条写日志到 docs/交付/任务4/evidence/；
  4. 汇总 check 数与失败数，任何一条失败/超时都让退出码非 0。

日志里包含：命令、Godot 版本行、退出码、stdout/stderr 尾部。没有真实运行就不会有日志。

用法：
  python apps/desktop/tests/task4/run_task4_checks.py
  python apps/desktop/tests/task4/run_task4_checks.py --godot D:\\Godot\\Godot_v4.6.3-stable_win64.exe
"""

from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys
import time

REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
)
# __file__ = <repo>/apps/desktop/tests/task4/run_task4_checks.py，需要上溯 5 层才到仓库根。
PROJECT = os.path.join(REPO_ROOT, "apps", "desktop")
EVIDENCE = os.path.join(PROJECT, "docs", "交付", "任务4", "evidence")

TASK4_TESTS = [
    ("platform-services", "res://tests/task4/test_platform_services.gd", 48),
    ("narrative-render", "res://tests/task4/test_narrative_render.gd", 66),
    ("onboarding-model", "res://tests/task4/test_onboarding_model.gd", 12),
]

REGRESSION_TESTS = [
    ("test_core", "res://tests/test_core.gd", 42),
    ("test_ui", "res://tests/test_ui.gd", 8),
    ("test_building_modules", "res://tests/test_building_modules.gd", 59),
    ("test_v04_regressions", "res://tests/test_v04_regressions.gd", 63),
    ("verify_004b", "res://tests/verify_004b.gd", 17),
    ("verify_005", "res://tests/verify_005.gd", 27),
    ("test_decision_preview", "res://tests/test_decision_preview.gd", 23),
    ("test_street_workflow", "res://tests/test_street_workflow.gd", 24),
]

CHECK_RE = re.compile(r"(\d+)\s+checks?,\s+(\d+)\s+failures?", re.IGNORECASE)


def find_godot(explicit: str | None) -> str | None:
    if explicit:
        return explicit if os.path.isfile(explicit) else None
    candidates = [
        os.path.join(REPO_ROOT, ".tools", "godot-4.6.3", "Godot_v4.6.3-stable_win64.exe"),
    ]
    for pattern in [os.path.join(REPO_ROOT, ".tools", "godot-4.6.3", "*.exe")]:
        candidates.extend(sorted(glob.glob(pattern)))
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    from shutil import which

    return which("godot") or which("Godot_v4.6.3-stable_win64.exe")


def run(godot: str, args: list[str], timeout: int, env: dict[str, str]) -> tuple[int, str]:
    started = time.time()
    try:
        # 显式管道会与沙箱冲突时，这里用文件重定向由 subprocess 内部完成（capture_output 用的是管道，
        # Windows 低权限会话下已验证可用；若失败会抛 OSError 并被下面的 except 记录）。
        completed = subprocess.run(
            [godot] + args,
            cwd=REPO_ROOT,
            capture_output=True,
            timeout=timeout,
            env=env,
        )
        text = completed.stdout.decode("utf-8", "replace") + completed.stderr.decode("utf-8", "replace")
        return completed.returncode, text + f"\n[elapsed {time.time() - started:.1f}s]\n"
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or b"") + (exc.stderr or b"")
        return 124, out.decode("utf-8", "replace") + f"\n[TIMEOUT after {timeout}s]\n"
    except Exception as exc:  # noqa: BLE001
        return 125, f"[无法执行: {type(exc).__name__}: {exc}]\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="运行任务4 引擎侧检查")
    parser.add_argument("--godot", default=None)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--skip-regression", action="store_true")
    args = parser.parse_args()

    godot = find_godot(args.godot)
    if not godot:
        print("FAIL: 找不到 Godot 4.6.3 可执行文件；用 --godot 指定，或放到 .tools/godot-4.6.3/", file=sys.stderr)
        return 2

    os.makedirs(EVIDENCE, exist_ok=True)
    env = dict(os.environ)
    # 低完整性会话里 user:// 可能写不进 %APPDATA%；把它指到工作区内，避免"测试写档失败"被误判。
    appdata = os.path.join(REPO_ROOT, ".tools", "appdata")
    os.makedirs(appdata, exist_ok=True)
    env["APPDATA"] = appdata
    env["LOCALAPPDATA"] = os.path.join(appdata, "Local")

    version_code, version_text = run(godot, ["--version"], 120, env)
    print(f"Godot: {godot}")
    print(f"--version -> {version_text.strip()} (exit {version_code})")
    version_line = version_text.strip().splitlines()[0] if version_text.strip() else "(no version output)"

    summary = []
    report = [f"Godot 可执行文件: {godot}", f"--version: {version_line}", ""]

    import_code, import_text = run(godot, ["--headless", "--path", PROJECT, "--import"], args.timeout, env)
    with open(os.path.join(EVIDENCE, "godot-import.log"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"命令: {godot} --headless --path apps/desktop --import\n")
        handle.write(f"退出码: {import_code}\n\n{import_text}")
    print(f"import -> exit {import_code}")
    report.append(f"[import] exit={import_code}")

    cases = list(TASK4_TESTS) + ([] if args.skip_regression else list(REGRESSION_TESTS))
    for name, script, expected in cases:
        code, text = run(godot, ["--headless", "--path", PROJECT, "--script", script], args.timeout, env)
        match = CHECK_RE.search(text)
        checks, failures = (int(match.group(1)), int(match.group(2))) if match else (None, None)
        log_name = f"godot-{name}.log"
        with open(os.path.join(EVIDENCE, log_name), "w", encoding="utf-8", newline="\n") as handle:
            handle.write(f"命令: {godot} --headless --path apps/desktop --script {script}\n")
            handle.write(f"Godot: {version_line}\n")
            handle.write(f"退出码: {code}\n")
            handle.write(f"解析到: checks={checks} failures={failures} expected_checks={expected}\n\n")
            handle.write(text)
        status = "PASS" if code == 0 and failures == 0 else "FAIL"
        summary.append((name, status, checks, failures, code, log_name))
        report.append(f"[{name}] {status} checks={checks} failures={failures} exit={code} log=evidence/{log_name}")
        print(f"{status}: {name} (checks={checks}, failures={failures}, exit={code})")

    with open(os.path.join(EVIDENCE, "godot-summary.log"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(report) + "\n")

    failed = [row for row in summary if row[1] != "PASS"]
    print("")
    print(f"共 {len(summary)} 条，失败 {len(failed)} 条；日志在 {EVIDENCE}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
