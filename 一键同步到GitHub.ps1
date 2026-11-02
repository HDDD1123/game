# 一键同步到 GitHub：https://github.com/HDDD1123/game
# 用法：在本目录打开 PowerShell，执行  .\一键同步到GitHub.ps1
# 首次推送时会弹出浏览器让你登录 GitHub 授权（Git Credential Manager），登录一次后以后就不用重复登录了。

$ErrorActionPreference = "Stop"

$repo   = "https://github.com/HDDD1123/game.git"
$branch = "main"

Write-Host "===== 检查 Git =====" -ForegroundColor Cyan
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "没有检测到 Git，请先安装：https://git-scm.com/download/win" -ForegroundColor Red
    Write-Host "安装时一路「下一步」即可；装完后【重新打开】PowerShell 再运行本脚本。" -ForegroundColor Yellow
    exit 1
}
Write-Host "Git 已就绪：$(git --version)" -ForegroundColor Green

Write-Host ""
Write-Host "===== 初始化仓库 =====" -ForegroundColor Cyan
if (-not (Test-Path ".git")) {
    git init | Out-Host
} else {
    Write-Host "已经是 git 仓库，跳过 init。"
}

$remotes = git remote
if ($remotes -notmatch "origin") {
    git remote add origin $repo
    Write-Host "已添加远程仓库：$repo"
} else {
    Write-Host "已存在远程 origin：$(git remote get-url origin)"
}

Write-Host ""
Write-Host "===== 配置提交身份（仅第一次需要）=====" -ForegroundColor Cyan
if (-not (git config user.name)) {
    $name = Read-Host "请输入你的名字（提交署名，随意填，例如 HDDD1123）"
    if ($name) { git config user.name $name }
}
if (-not (git config user.email)) {
    $email = Read-Host "请输入邮箱（GitHub 提交署名用）"
    if ($email) { git config user.email $email }
}

Write-Host ""
Write-Host "===== 暂存所有文件 =====" -ForegroundColor Cyan
git add -A

Write-Host ""
Write-Host "===== 提交 =====" -ForegroundColor Cyan
git commit -m "Update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($LASTEXITCODE -ne 0) {
    Write-Host "（没有需要提交的改动，或已经提交过了）"
}

Write-Host ""
Write-Host "===== 推送到 GitHub =====" -ForegroundColor Cyan
Write-Host "首次推送会弹出浏览器让你登录 GitHub，点「授权」即可。" -ForegroundColor Yellow
git branch -M $branch
git push -u origin $branch

Write-Host ""
Write-Host "完成！代码已同步到 $repo" -ForegroundColor Green
