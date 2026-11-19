"""生成任务4 的「路径 + SHA-256」内容清单，并给出一个聚合 content_hash。

为什么需要：本机没有 git，`source_commit` 只能是 null。中控要能核对"我覆盖上去的到底是什么"，
所以用内容清单代替提交号：每个文件一条 sha256，再加一个把所有条目排序拼接后的聚合哈希。

范围只包含任务4 负责的路径（见四机并行总览「文件归属R2」），不扫描别人的 core/、ui/main.gd 等。

用法：
  python tools/desktop-delivery/content_manifest.py --root . \
      --out apps/desktop/docs/交付/任务4/content-manifest.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

SCOPE = [
    "tools/windows-typing",
    "tools/desktop-delivery",
    "apps/desktop/platform",
    "apps/desktop/ui/onboarding",
    "apps/desktop/data/narrative",
    "apps/desktop/tests/task4",
    "apps/desktop/docs/交付/任务4",
    "apps/desktop/export_presets.cfg",
]

EXCLUDE_DIRS = {"__pycache__", "bin", ".godot", "obj"}
EXCLUDE_SUFFIXES = {".pyc", ".exe", ".zip", ".tmp", ".bak"}
# 这个清单本身与它记录的总哈希不能出现在清单里，否则每次生成都会变。
EXCLUDE_FILES = {
    "apps/desktop/docs/交付/任务4/content-manifest.json",
    "apps/desktop/docs/交付/任务4/delivery.json",
    "apps/desktop/docs/交付/任务4/delivery_detail.json",
}


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(root: str) -> list[dict]:
    entries: list[dict] = []
    for item in SCOPE:
        target = os.path.join(root, item)
        if os.path.isfile(target):
            entries.append(make_entry(root, target))
            continue
        for dirpath, dirnames, filenames in os.walk(target):
            dirnames[:] = sorted(d for d in dirnames if d.lower() not in EXCLUDE_DIRS)
            for name in sorted(filenames):
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, root).replace(os.sep, "/")
                if rel in EXCLUDE_FILES:
                    continue
                if os.path.splitext(name)[1].lower() in EXCLUDE_SUFFIXES:
                    continue
                entries.append(make_entry(root, path))
    entries.sort(key=lambda entry: entry["path"])
    return entries


def make_entry(root: str, path: str) -> dict:
    return {
        "path": os.path.relpath(path, root).replace(os.sep, "/"),
        "bytes": os.path.getsize(path),
        "sha256": sha256_file(path),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="生成内容清单与 content_hash")
    parser.add_argument("--root", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
    parser.add_argument("--out", default="apps/desktop/docs/交付/任务4/content-manifest.json")
    args = parser.parse_args()

    entries = collect(args.root)
    if not entries:
        print("FAIL: 没有收集到任何文件", file=sys.stderr)
        return 1

    lines = "".join(f"{entry['path']}\t{entry['sha256']}\n" for entry in entries)
    content_hash = hashlib.sha256(lines.encode("utf-8")).hexdigest()

    payload = {
        "schema": 1,
        "task_id": "T4",
        "base_commit": "631df2c",
        "note": "本机无 git，用内容清单代替 source_commit；content_hash 是下列条目的聚合哈希。",
        "scope": SCOPE,
        "excluded": sorted(EXCLUDE_FILES),
        "file_count": len(entries),
        "total_bytes": sum(entry["bytes"] for entry in entries),
        "content_hash": content_hash,
        "files": entries,
    }
    out_path = os.path.join(args.root, args.out)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"已写入 {out_path}")
    print(f"file_count={len(entries)} total_bytes={payload['total_bytes']}")
    print(f"content_hash={content_hash}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
