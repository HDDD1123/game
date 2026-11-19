# 任务4 T4-04 输入助手验收（需要**普通权限**的 PowerShell，不要以低权限/沙箱方式运行）
#   powershell -ExecutionPolicy Bypass -File tools\windows-typing\verify-live.ps1
#
# 为什么 DSH 不能代跑：本会话进程为低完整性级别，SendInput 会被 UIPI 拒绝（返回 0、无错误码），
# 无法注入合成按键，也无法确认"真人后台打字"这一项。脚本会先自检权限并说明。
#
# 阶段：
#   A 判定逻辑自检（合成事件，不安装钩子）
#   B 模拟按键：注入 7 次 F24，核对计数合计 = 7
#   C 真人后台输入：切到别的窗口正常打字 10 秒，核对计数 > 0
#
# 日志：apps\desktop\docs\交付\任务4\evidence\typing-live-<时间>.log

# 本脚本按"记录并继续"的方式工作：native 程序的 stderr 不应中断流程。
$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Windows.Forms | Out-Null

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent $here)
$exe = Join-Path $here "bin\TypingCounter.exe"
$evidenceDir = Join-Path $repo "apps\desktop\docs\交付\任务4\evidence"

if (-not (Test-Path -LiteralPath $exe)) {
    Write-Error "未找到 $exe，请先运行 build.ps1"
    exit 2
}
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $evidenceDir "typing-live-$stamp.log"
$log = New-Object System.Collections.Generic.List[string]
$failed = $false

function Log([string]$line) {
    $log.Add($line)
    Write-Host $line
}

function Get-Lines([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $raw = [System.IO.File]::ReadAllText($path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return @($raw -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
}

function Get-Sum([string]$path) {
    $sum = 0
    $n = 0
    foreach ($l in (Get-Lines $path)) {
        if ($l -match '^\{"v":1,"seq":\d+,"count":(\d+)\}$') { $sum += [int]$Matches[1]; $n++ }
        else { throw "非协议行（不得输出键值/文字）：$l" }
    }
    return [pscustomobject]@{ Lines = $n; Sum = $sum }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$groupLine = (whoami /groups | Select-String -Pattern 'Mandatory Level|强制级别|完整性级别' | Out-String).Trim()
$isLow = $groupLine -match 'Low|低'
Log "任务4 T4-04 输入助手验收  $stamp"
Log "助手: $exe"
Log "用户: $($identity.Name)"
Log "完整性: $groupLine"
if ($isLow) {
    Log "警告: 当前为低完整性会话，阶段 B 的 SendInput 会被系统拒绝；请用普通 PowerShell 重跑。"
}
Log ""

# ---------- A ----------
Log "--- A. 判定逻辑自检 ---"
$selfOut = @(& $exe --self-test)
$selfCode = $LASTEXITCODE
$selfOut | ForEach-Object { Log "  $_" }
Log "  exit=$selfCode"
if ($selfCode -eq 0) { Log "A: PASS" } else { Log "A: FAIL"; $failed = $true }
Log ""

if (-not $isLow) {
    Add-Type -Namespace Win32 -Name Kb -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct INPUT { public uint type; public KEYBDINPUT ki; public int pad; }
[StructLayout(LayoutKind.Sequential)]
public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public System.IntPtr dwExtraInfo; }
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError=true)]
public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
public static void Press(ushort vk) {
    INPUT[] d = new INPUT[2];
    d[0].type = 1; d[0].ki.wVk = vk;
    d[1].type = 1; d[1].ki.wVk = vk; d[1].ki.dwFlags = 2;
    uint sent = SendInput(2, d, Marshal.SizeOf(typeof(INPUT)));
    if (sent != 2) throw new System.Exception("SendInput 被拒绝（完整性级别不足或安全软件拦截）");
}
'@

    # ---------- B ----------
    Log "--- B. 模拟按键（注入 7 次 F24）---"
    $outFile = Join-Path $env:TEMP "typing-b-$stamp.log"
    $p = Start-Process -FilePath $exe -ArgumentList @("--out", $outFile) -PassThru
    Start-Sleep -Milliseconds 500
    try {
        1..7 | ForEach-Object { [Win32.Kb]::Press(0x87); Start-Sleep -Milliseconds 40 }
        Start-Sleep -Milliseconds 800
        $r = Get-Sum $outFile
        Log "  行数=$($r.Lines) 计数合计=$($r.Sum)"
        if ($r.Sum -eq 7) { Log "B: PASS" } else { Log "B: FAIL（期望 7）"; $failed = $true }
    } catch {
        Log "B: FAIL —— $($_.Exception.Message)"
        $failed = $true
    } finally {
        try { $p.Kill() } catch {}
    }
    Log ""

    # ---------- C ----------
    Log "--- C. 真人后台输入 ---"
    Write-Host ""
    Write-Host ">>> 接下来 10 秒请把焦点切到别的窗口（记事本/浏览器），正常打字。" -ForegroundColor Yellow
    Write-Host ">>> 不要按 F22/F23/F24，也不要一直按住同一个键；助手自身不在前台。" -ForegroundColor Yellow
    Write-Host ""
    $outFile2 = Join-Path $env:TEMP "typing-c-$stamp.log"
    $p2 = Start-Process -FilePath $exe -ArgumentList @("--out", $outFile2) -PassThru
    Start-Sleep -Milliseconds 400
    $null = [System.Windows.Forms.MessageBox]::Show("按确定后开始 10 秒计时，然后立刻到别的窗口打字。", "任务4 输入验收", "OK", "Information")
    Start-Sleep -Seconds 10
    Start-Sleep -Milliseconds 500
    try {
        $r2 = Get-Sum $outFile2
        Log "  行数=$($r2.Lines) 计数合计=$($r2.Sum)"
        if ($r2.Sum -gt 0) { Log "C: PASS（收到 $($r2.Sum) 次真实按下）" } else { Log "C: FAIL（10 秒内没有计数：没真的打字，或安全软件拦截了键盘钩子）"; $failed = $true }
    } catch {
        Log "C: FAIL —— $($_.Exception.Message)"
        $failed = $true
    } finally {
        try { $p2.Kill() } catch {}
    }
} else {
    Log "--- B/C 跳过：低完整性会话无法注入按键，也无法代表真人输入 ---"
    Log "B: SKIP"
    Log "C: SKIP"
}

Log ""
if ($isLow) {
    Log ("结论: " + $(if ($failed) { "A 存在未通过项；B/C 未测" } else { "A 通过；B/C 未测（需普通权限会话重跑本脚本才能给出后台输入结论）" }))
} else {
    Log ("结论: " + $(if ($failed) { "存在未通过项，见上面各阶段" } else { "A/B/C 全部通过" }))
}
$log | Set-Content -LiteralPath $logPath -Encoding UTF8
Write-Host ""
Write-Host "日志: $logPath" -ForegroundColor Cyan
if ($failed) { exit 1 } else { exit 0 }
