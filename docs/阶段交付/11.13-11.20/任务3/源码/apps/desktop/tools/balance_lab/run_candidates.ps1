# T3-04 候选隔离实验（PowerShell 版，等价于 run_candidates.sh）
# 用法：$env:GODOT_BIN="C:\path\to\Godot_v4.6.3-stable_win64_console.exe"; ./run_candidates.ps1
# 说明：本文件保存为 UTF-8 with BOM，Windows PowerShell 5.1 也能正确解析中文。
param()
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '../../../..')
$base = Join-Path $root 'apps/desktop'
if (-not $env:GODOT_BIN) { throw '请设置 GODOT_BIN 指向 Godot 4.6.3 控制台版可执行文件' }
$godot = $env:GODOT_BIN
$work = Join-Path $root '.tmp_candidates'
$out = Join-Path $base 'experiments/task3/candidates'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Run-Candidate([string]$name, [string]$pattern, [string]$replacement) {
  $dir = Join-Path $work $name
  if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  Copy-Item -Recurse $base $dir
  Remove-Item -Recurse -Force (Join-Path $dir '.godot') -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force (Join-Path $dir 'experiments/task3') -ErrorAction SilentlyContinue
  $balance = Join-Path $dir 'core/balance.gd'
  (Get-Content $balance -Raw).Replace($pattern, $replacement) | Set-Content $balance -NoNewline
  Copy-Item $balance (Join-Path $out ("balance-$name.gd")) -Force
  Write-Host "== 候选 $name =="
  Push-Location $dir
  & $godot --headless --path . --script res://tools/balance_lab/run_curves.gd | Select-String -Pattern 'fingerprint|rows='
  Pop-Location
  $dest = Join-Path $out $name
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item (Join-Path $dir 'experiments/task3/*') $dest -Force -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $dir
}

Run-Candidate 'cand_a_food_per_level' 'const FOOD_PER_FARM_LEVEL = 6' 'const FOOD_PER_FARM_LEVEL = 7'
Run-Candidate 'cand_b_drought_factor' 'const DROUGHT_FACTOR = 0.6' 'const DROUGHT_FACTOR = 0.7'
Write-Host "输出目录: $out"
