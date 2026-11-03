# 推送.ps1  —— 请在「普通 PowerShell」里运行（不要通过 DeepSeek 沙箱）
# 作用：把本地代码推送到 https://github.com/HDDD1123/game
# 提示：先双击同目录下的 推送.cmd 更省事

$ErrorActionPreference = "Stop"
try { chcp 65001 | Out-Null } catch {}

# 1. 找 git
$git = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    $git = "git"
} else {
    $candidates = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $git = $c; break } }
}

Write-Host "===== 推送工具 =====" -ForegroundColor Cyan
if (-not $git) {
    Write-Host "没有找到 git。请先安装 Git for Windows：https://git-scm.com/download/win" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}
Write-Host "找到 git：$git" -ForegroundColor Green

# 2. 进入项目目录
Set-Location $PSScriptRoot
Write-Host "当前目录：$(Get-Location)"

if (-not (Test-Path ".git")) {
    Write-Host "这个目录不是 git 仓库，请确认文件放在 C:\Users\Administrator\Desktop\小游戏 下" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}

# 3. 输入 token（只用于本次推送，不会存进任何文件）
$token = Read-Host "请粘贴你的 GitHub token（github_pat_ 或 ghp_ 开头），回车确认"
if (-not $token -or -not $token.Trim()) {
    Write-Host "没有输入 token，已取消。" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 1
}
$url = "https://x-access-token:$($token.Trim())@github.com/HDDD1123/game.git"

# 4. 推送（用 openssl 后端绕开证书问题）
Write-Host ""
Write-Host "正在推送..." -ForegroundColor Cyan
& $git -c http.sslBackend=openssl -c credential.helper= push -u $url main
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ 推送成功！代码已上传到 https://github.com/HDDD1123/game" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "❌ 推送失败（退出码 $LASTEXITCODE）。把窗口里的报错截图发我，我帮你看。" -ForegroundColor Red
}
Read-Host "按回车关闭窗口"
