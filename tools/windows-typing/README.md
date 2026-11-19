# Windows 后台输入计数助手（任务4 T4-04）

统计"非修饰键的一次有效按下"，只输出**整数计数**。不记录文字、不记录键码、不读窗口标题/剪贴板、不联网、不自启动、不需要管理员。

## 构建（无需 .NET SDK）

```powershell
powershell -ExecutionPolicy Bypass -File tools\windows-typing\build.ps1
```

- 编译器用 Windows 自带的 .NET Framework `csc.exe`（`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`）。
- 产物：`tools/windows-typing/bin/TypingCounter.exe`（约 12 KB）+ `bin/build-manifest.json`（含 SHA-256、编译器路径）。
- 没有 .NET SDK 也能构建；但如果目标机器连 .NET Framework 4.x 都没有，需要改用其它原生工具链（未验证）。

## 运行

```powershell
# 正常运行：协议行写到 stdout
.\TypingCounter.exe

# 过滤掉 SendInput 之类的注入按键（只统计真实键盘）
.\TypingCounter.exe --ignore-injected

# 只做判定逻辑自检，不安装钩子、不读真实键盘
.\TypingCounter.exe --self-test

# 协议行写到文件（Godot 桥接用这条路径，原因见下）
.\TypingCounter.exe --out C:\path\session.log

# 诊断：每次有效按下在 stderr 打一行 "press"（不含键码）
.\TypingCounter.exe --trace
```

退出方式：stdin 收到 `{"v":1,"command":"shutdown"}`（或单独一行 `shutdown`）、stdin 关闭（父进程死亡）、被父进程 kill。其余 stdin 内容一律忽略。

## 协议

- stdout 每 250ms 至多一行：`{"v":1,"seq":7,"count":12}`，单行 ≤ 512 字节，`count` ∈ 0..1000。
- 没有输入时不发 0 计数行（`count:0` 合法但不必发）。
- `seq` 每行递增；桥接拒绝重复/倒退序号、畸形行、超长行、越界 count。
- stderr 只放诊断（`ready`、`bye`、`dropped_over_cap`），**不含任何按键信息**。

## 隐私边界

- 键码只在进程内存里用于"按下/释放/自动重复"判定，不输出、不落盘。
- 不创建文件、不写注册表、不设开机启动、不发网络请求。
- 不在游戏存档里保存任何监听计数或监听开关状态（每次启动默认关闭，由玩家显式开启）。

## 为什么 Godot 侧用 `--out` 文件而不是管道

Godot 4.6.3 没有读取子进程 stdout 的非阻塞 API：`OS.execute` 会阻塞主线程，`OS.create_process` 不返回管道。
所以桥接（`apps/desktop/platform/typing/typing_bridge.gd`）让助手把**同样的协议行**写到会话文件，每 250ms 增量读取。
协议内容、校验规则、序号语义与 stdout 版完全一致；若将来引擎提供非阻塞管道，只需替换桥接的读取函数，公开接口不变。

## 测试与验收

| 内容 | 命令 | 本机状态 |
|---|---|---|
| 判定逻辑自检（合成事件） | `bin\TypingCounter.exe --self-test` | **通过**（5 项） |
| 协议/退出/畸形输入（模拟按键） | `python tests/task4/test_typing_helper.py` | 2 项通过（shutdown、stdin EOF）；6 项**跳过**，原因见下 |
| 模拟按键 + 真人后台输入 | `powershell -ExecutionPolicy Bypass -File tools\windows-typing\verify-live.ps1` | 需普通权限会话，DSH 沙箱内无法执行 |

**为什么有两项在本机做不到**：DSH 会话进程运行在 **低完整性级别（Mandatory Label\Low）**，`SendInput` 被 UIPI 拒绝（返回 0、无错误码），因此无法注入合成按键；同样也无法代表"真人打字"。请在普通权限的 PowerShell 里运行 `verify-live.ps1`：它会做 A 自检、B 注入 7 键核对计数、C 请你到别的窗口打 10 秒字并核对计数，日志写入 `apps/desktop/docs/交付/任务4/evidence/`。

## 已知限制

- 以普通权限运行即可统计本会话内的输入；**提权窗口**（以管理员运行的程序）里的按键通常收不到——这是 Windows 的 UIPI 规则，不是 bug，本助手不要求管理员。
- 部分安全软件会拦截全局键盘钩子（表现为 `SetWindowsHookEx` 失败、退出码 3，或 10 秒内 0 计数）。出现时不要为了测试关闭防护，改为在干净环境验证并记录缺口。
- 一个 250ms 窗口内超过 1000 次按下会被截断（`dropped_over_cap` 记在 stderr），真人不可能达到。
- 判定"自动重复"靠"按下集合"去重：按住不放只记 1 次；某些驱动会连发独立的按下/释放对，那种情况要按真实按键计数——需要在目标机器上复核。
