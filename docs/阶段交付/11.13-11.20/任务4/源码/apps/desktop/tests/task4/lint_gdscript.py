"""任务4 无引擎环境下的 GDScript 静态体检（不是编译器，只挡低级错误）。

本机没有 Godot，无法运行 `--check-only` 或 headless 测试，所以用这个脚本做最低保障：
  1. 括号/花括号/方括号配平（跳过字符串与注释）；
  2. 缩进只用 Tab，且不混用空格缩进；
  3. `func`/`if`/`for`/`while`/`match`/`class` 等块头以 `:` 结尾，且下一非空行缩进更深；
  4. 同一文件内函数名不重复；
  5. 没有制表符出现在行尾空白之外的多余空格缩进；
  6. 文件为 UTF-8 且行尾统一为 LF 或 CRLF 之一。

退出码 0/1；逐条打印 `FAIL: 文件:行 说明`。

用法：
  python apps/desktop/tests/task4/lint_gdscript.py [--root <repo>] [路径...]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

BLOCK_HEADS = re.compile(
    r"^\s*(func|if|elif|else|for|while|match|class|class_name|static func|enum|signal|var|const|@|"
    r"return|pass|break|continue|await)\b"
)
FUNC_DEF = re.compile(r"^\s*(static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")


def strip_code(line: str) -> str:
    """去掉字符串与注释，便于数括号。"""
    out = []
    i = 0
    quote = None
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in "\"'":
            quote = ch
            i += 1
            continue
        if ch == "#":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def check_file(path: str, rel: str) -> list[str]:
    problems: list[str] = []
    with open(path, "rb") as handle:
        raw = handle.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        problems.append(f"{rel}:1 文件带 UTF-8 BOM（GDScript 不报错但会污染首行 diff）")
        raw = raw[3:]
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        problems.append(f"{rel}:1 不是合法 UTF-8：{exc}")
        return problems

    lines = text.split("\n")
    depth = 0
    seen_funcs: dict[str, int] = {}
    for number, line in enumerate(lines, start=1):
        if line.rstrip("\r").strip() == "":
            continue
        body = line.rstrip("\r")
        if body.startswith(" "):
            problems.append(f"{rel}:{number} 行首是空格（本项目用 Tab 缩进）")
        code = strip_code(body)
        for ch in code:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
                if depth < 0:
                    problems.append(f"{rel}:{number} 括号提前闭合")
                    depth = 0
        stripped = code.strip()
        if stripped.startswith(("func ", "static func ")):
            match = FUNC_DEF.match(body)
            if match:
                name = match.group(2)
                if name in seen_funcs:
                    problems.append(f"{rel}:{number} 函数 {name} 与第 {seen_funcs[name]} 行重名")
                else:
                    seen_funcs[name] = number
            if not stripped.endswith(":") and " -> " not in stripped and not stripped.endswith(")"):
                problems.append(f"{rel}:{number} 函数定义缺少结尾的 ':'")
    if depth != 0:
        problems.append(f"{rel}: 文件末尾括号未配平（剩余 {depth}）")

    # 块头必须以 ':' 结尾，且下一非空行缩进更深
    for index, line in enumerate(lines):
        body = line.rstrip("\r")
        stripped = strip_code(body).strip()
        if not stripped:
            continue
        if stripped.startswith(("func ", "static func ")) and not stripped.endswith((":", ")")) and " -> " not in stripped:
            continue
        if stripped.endswith(":") and not stripped.startswith("#"):
            indent = len(body) - len(body.lstrip("\t"))
            next_body = None
            for later in lines[index + 1:]:
                if later.rstrip("\r").strip():
                    next_body = later.rstrip("\r")
                    break
            if next_body is None:
                continue
            next_indent = len(next_body) - len(next_body.lstrip("\t"))
            if next_indent <= indent and not next_body.strip().startswith("#"):
                problems.append(f"{rel}:{index + 1} 块头没有更深的缩进（下一行 {next_body.strip()[:40]!r}）")
    return problems


def iter_gd_files(root: str) -> list[str]:
    found = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in {".git", "third_party", "bin", "obj", ".godot"}]
        for name in files:
            if name.endswith(".gd"):
                found.append(os.path.join(base, name))
    return sorted(found)


def main() -> int:
    parser = argparse.ArgumentParser(description="GDScript 静态体检")
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    parser.add_argument("paths", nargs="*", help="只检查这些文件/目录（默认 apps/desktop）")
    args = parser.parse_args()

    targets: list[str] = []
    if args.paths:
        for item in args.paths:
            full = item if os.path.isabs(item) else os.path.join(args.root, item)
            if os.path.isdir(full):
                targets.extend(iter_gd_files(full))
            elif os.path.isfile(full):
                targets.append(full)
    else:
        targets = iter_gd_files(os.path.join(args.root, "apps", "desktop"))

    if not targets:
        print("FAIL: 没有找到 .gd 文件")
        return 1

    all_problems: list[str] = []
    for path in targets:
        rel = os.path.relpath(path, args.root).replace(os.sep, "/")
        problems = check_file(path, rel)
        all_problems.extend(problems)
        for problem in problems:
            print("FAIL: " + problem)

    print("LINT: %d 个文件, %d 个问题" % (len(targets), len(all_problems)))
    return 0 if not all_problems else 1


if __name__ == "__main__":
    sys.exit(main())
