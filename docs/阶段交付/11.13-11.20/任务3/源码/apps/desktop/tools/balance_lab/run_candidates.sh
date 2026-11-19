#!/usr/bin/env bash
# T3-04：两个单变量候选的隔离实验（不改生产 balance.gd）。
# 做法：把 apps/desktop 复制到仓库外的临时目录，改一个常量，跑同一套曲线，回收输出。
set -u
# 依赖：bash + sed + cp。Windows 用户请在 git-bash 下运行，或改用同目录的 run_candidates.ps1。
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
BASE="$ROOT/apps/desktop"
GODOT="${GODOT_BIN:?请设置 GODOT_BIN 指向 Godot 4.6.3 控制台版可执行文件}"
WORK="$ROOT/.tmp_candidates"
OUT="$BASE/experiments/task3/candidates"
mkdir -p "$OUT"

run_candidate() {
  local name="$1" pattern="$2" replacement="$3"
  local dir="$WORK/$name"
  rm -rf "$dir"; mkdir -p "$WORK"
  cp -r "$BASE" "$dir"
  rm -rf "$dir/.godot"
  rm -rf "$dir/experiments/task3"
  # 只改一行常量，保留原文件副本用于证据
  sed -i "s|$pattern|$replacement|" "$dir/core/balance.gd"
  cp "$dir/core/balance.gd" "$OUT/balance-$name.gd"
  echo "== 候选 $name =="
  grep -n "$replacement" "$dir/core/balance.gd" | head -1
  ( cd "$dir" && "$GODOT" --headless --path . --script res://tools/balance_lab/run_curves.gd 2>&1 | grep -E "fingerprint|rows=|m120=" | tail -8 )
  mkdir -p "$OUT/$name"
  cp "$dir"/experiments/task3/*.csv "$OUT/$name/" 2>/dev/null || true
  cp "$dir"/experiments/task3/*.json "$OUT/$name/" 2>/dev/null || true
  cp "$dir"/experiments/task3/*.jsonl "$OUT/$name/" 2>/dev/null || true
  rm -rf "$dir"
}

run_candidate "cand_a_food_per_level" "const FOOD_PER_FARM_LEVEL = 6" "const FOOD_PER_FARM_LEVEL = 7"
run_candidate "cand_b_drought_factor" "const DROUGHT_FACTOR = 0.6" "const DROUGHT_FACTOR = 0.7"
echo "输出目录: $OUT"
ls "$OUT"
