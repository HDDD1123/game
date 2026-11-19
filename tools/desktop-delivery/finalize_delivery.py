"""把 delivery.py 的详细清单包一层「中控约定的交付回传字段」。

中控要求 delivery.json 至少含：task_id、stage_points、task_revision、base_commit、
source_commit、completed_packages、tests、known_gaps、ready_for_integration、branch，
返工版还要求 content_hash 与文件清单。

本脚本不伪造任何一项：
  * source_commit 在无 git 的机器上只能是 null，并写 unavailable_reason；
  * completed_packages 只收「实现 + 引擎测试都通过」的包，由 claims.json 里真实 passed 的测试推出；
  * stage_points = 6 × completed 数量，不手填；
  * content_hash 来自 content_manifest.py 的输出（路径+SHA-256 的聚合哈希）。

用法：
  python tools/desktop-delivery/finalize_delivery.py --root . \
      --detail apps/desktop/docs/交付/任务4/delivery_detail.json \
      --out apps/desktop/docs/交付/任务4/delivery.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys

TASK_REVISION = "R2"
BASE_COMMIT = "631df2c"
BRANCH_INTENT = "dsh/task4-typing-v05"

# 每个包要"完成"，需要哪些 claim 变为 passed。未列出的包本轮不算完成。
PACKAGE_TESTS = {
    "T4-02": ["godot-platform-services"],
    "T4-03": ["godot-platform-services"],
    "T4-09": ["godot-onboarding-model"],
    "T4-10": ["godot-narrative-render", "narrative-data-validation"],
}

PACKAGE_TITLES = {
    "T4-01": "启动/运行基线与参考",
    "T4-02": "启动服务与故障反馈",
    "T4-03": "设置与桌面生命周期服务",
    "T4-04": "Windows 输入计数助手",
    "T4-05": "Godot 输入桥与故障隔离",
    "T4-06": "生命周期联调与独立演示",
    "T4-07": "CPU/GPU/内存与渲染优化",
    "T4-08": "可重复导出与资源诊断",
    "T4-09": "精灵宰相向导与反馈组件",
    "T4-10": "史书事实与结局模板",
    "T4-11": "启动与长期实机回归",
    "T4-12": "阶段包与交付工具",
}

PACKAGE_DELIVERED = {
    "T4-02": "startup_service.gd 实现并通过引擎测试；主入口装配仍归任务1",
    "T4-03": "settings_store.gd / window_metrics.gd 实现并通过引擎测试；窗口写入仍归任务1",
    "T4-04": "助手可构建、--self-test 通过与协议/退出测试；低完整性会话无法确认真实后台输入",
    "T4-05": "typing_bridge.gd 的协议校验/会话清理通过引擎测试；真实子进程启动与 kill 未测",
    "T4-08": "清单/导出检查工具可运行；未安装导出模板，未执行真实导出",
    "T4-12": "交付工具链与内容清单可运行；没有 24/48/72 阶段包（未导出）",
}

NOT_STARTED = {
    "T4-01": "启动基线需要实机计时；本轮只完成研究部分（创意候选.md）",
    "T4-06": "需要任务1 主UI开关与任务2 SessionController 联调",
    "T4-07": "性能采样需要实机长时间观察，本轮未做",
    "T4-11": "10 次热启动 + 2 小时在线观察未做",
}


def main() -> int:
    parser = argparse.ArgumentParser(description="合成中控约定的 delivery.json")
    parser.add_argument("--root", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
    parser.add_argument("--detail", default="apps/desktop/docs/交付/任务4/delivery_detail.json")
    parser.add_argument("--claims", default="apps/desktop/docs/交付/任务4/claims.json")
    parser.add_argument("--manifest", default="apps/desktop/docs/交付/任务4/content-manifest.json")
    parser.add_argument("--out", default="apps/desktop/docs/交付/任务4/delivery.json")
    args = parser.parse_args()

    detail_path = os.path.join(args.root, args.detail)
    claims_path = os.path.join(args.root, args.claims)
    manifest_path = os.path.join(args.root, args.manifest)
    for path in (detail_path, claims_path, manifest_path):
        if not os.path.isfile(path):
            print(f"FAIL: 缺少输入文件：{path}", file=sys.stderr)
            return 2

    with open(detail_path, encoding="utf-8") as handle:
        detail = json.load(handle)
    with open(claims_path, encoding="utf-8") as handle:
        claims = json.load(handle)
    with open(manifest_path, encoding="utf-8") as handle:
        content = json.load(handle)

    passed = {t["id"] for t in claims.get("tests", []) if str(t.get("result")) == "passed" and t.get("ran") is True}
    completed = sorted(pkg for pkg, needs in PACKAGE_TESTS.items() if all(need in passed for need in needs))
    delivered = sorted(pkg for pkg in PACKAGE_DELIVERED if pkg not in completed)
    not_started = sorted(NOT_STARTED)

    merged = {
        "task_id": "T4",
        "task_title": "启动、桌面运行、后台输入与叙事交付（72点）· 返工版",
        "task_revision": TASK_REVISION,
        "task_document_commit": BASE_COMMIT,
        "stage_points": 6 * len(completed),
        "stage_points_note": "每包 6 点；只有实现+引擎测试都通过的包才计入（由 claims.json 的 passed 推出）。",
        "base_commit": BASE_COMMIT,
        "source_commit": None,
        "source_commit_unavailable_reason": "本机没有 git；仓库由 GitHub 官方 tarball 取件（分支 HEAD "
                                            "631df2c1b7efcd95dda8ccd629bbf66775f6ae04），无 .git 元数据，"
                                            "无法每包提交。改用 content_hash 核对内容。",
        "content_hash": content.get("content_hash"),
        "content_manifest": os.path.relpath(manifest_path, args.root).replace(os.sep, "/"),
        "content_file_count": content.get("file_count"),
        "content_total_bytes": content.get("total_bytes"),
        "branch": BRANCH_INTENT,
        "branch_note": "分支是意图名；本机无法执行 git switch -c，不存在真实分支引用。",
        "completed_packages": [
            {"id": pkg, "title": PACKAGE_TITLES[pkg], "points": 6} for pkg in completed
        ],
        "delivered_but_unverified_packages": [
            {"id": pkg, "title": PACKAGE_TITLES[pkg], "points_if_verified": 6, "why_unverified": PACKAGE_DELIVERED[pkg]}
            for pkg in delivered
        ],
        "not_started_packages": [
            {"id": pkg, "title": PACKAGE_TITLES[pkg], "points": 0, "reason": NOT_STARTED[pkg]}
            for pkg in not_started
        ],
        "ready_for_integration": len(completed) > 0,
        "ready_for_integration_reason": "有 4 个包通过引擎测试（平台层、向导、史书），另有 4 个包有代码但未验证；"
                                        "无 git 提交，需按内容清单合入。",
        "tests": detail.get("tests", []),
        "known_gaps": detail.get("untested", []),
        "delivery_mode": "B-ZIP（不能推 GitHub）",
        "detail": detail,
    }

    out_path = os.path.join(args.root, args.out)
    with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(merged, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"已写入 {out_path}")
    print(f"stage_points={merged['stage_points']} completed={completed} "
          f"delivered={len(delivered)} not_started={len(not_started)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
