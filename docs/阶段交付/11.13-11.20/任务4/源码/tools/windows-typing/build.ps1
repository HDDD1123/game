# 构建 Windows 输入计数助手（无需 .NET SDK，只用 Windows 自带的 .NET Framework 编译器）
# 用法：powershell -ExecutionPolicy Bypass -File tools\windows-typing\build.ps1
# 输出：tools\windows-typing\bin\TypingCounter.exe 及其 SHA-256（不写时间戳，便于比对）

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $here "TypingCounter.cs"
$outDir = Join-Path $here "bin"
$outExe = Join-Path $outDir "TypingCounter.exe"

if (-not (Test-Path -LiteralPath $source)) {
    Write-Error "找不到源文件：$source"
    exit 1
}

$cscCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) {
    Write-Error "未找到 .NET Framework 编译器 csc.exe（Windows 10/11 通常自带）。可用 Visual Studio Build Tools 替代。"
    exit 2
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$argsList = @(
    "/nologo",
    "/target:exe",
    "/platform:anycpu",
    "/optimize+",
    "/warn:4",
    "/out:$outExe",
    $source
)

& $csc @argsList
if ($LASTEXITCODE -ne 0) {
    Write-Error "编译失败，csc 退出码 $LASTEXITCODE"
    exit $LASTEXITCODE
}

$hash = (Get-FileHash -LiteralPath $outExe -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $outExe).Length
$manifest = [ordered]@{
    tool        = "TypingCounter"
    source      = "tools/windows-typing/TypingCounter.cs"
    compiler    = $csc
    framework   = "net48 (Windows 自带 .NET Framework 4.x)"
    bytes       = $size
    sha256      = $hash
    protocol    = 'stdout 每250ms至多一行 {"v":1,"seq":N,"count":N}'
}
$manifestPath = Join-Path $outDir "build-manifest.json"
($manifest | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Output "已构建：$outExe"
Write-Output "大小：$size 字节"
Write-Output "SHA-256：$hash"
Write-Output "清单：$manifestPath"
exit 0
