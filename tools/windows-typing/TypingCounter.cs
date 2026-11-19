// TypingCounter —— 桌面王国 任务4 T4-04 后台输入计数助手
//
// 职责边界（见 apps/desktop/docs/四机接口约定.md B 节）：
//   * 只统计"非修饰键的一次有效按下"，忽略系统自动重复（按住不放）。
//   * 只向 stdout 输出 {v,seq,count} 三种整数/版本字段；不输出键码、文字、窗口标题、剪贴板内容。
//   * 诊断信息只走 stderr，且不含任何按键内容。
//   * 无网络、无自启动、无注册表写入、无管理员要求。
//
// 协议：
//   stdout 每 250ms 至多一行，例如 {"v":1,"seq":7,"count":12}；count 范围 0..1000，
//   单行不超过 512 字节。没有输入时不发空行（0 行合法但不必发）。
//   stdin 接受 {"v":1,"command":"shutdown"}（也接受单独一行 shutdown）请求退出。
//   stdin 读到 EOF（父进程关闭管道/被结束）同样视为退出请求——这是父进程崩溃时的兜底。
//
// 构建：tools/windows-typing/build.ps1（用系统自带 .NET Framework 的 csc.exe，不需要 .NET SDK）
// 说明：仅本机进程内使用键码做"按下/释放"去重，键码不落盘、不出进程。

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace KingdomTypingCounter
{
    internal static class NativeMethods
    {
        internal const int WH_KEYBOARD_LL = 13;
        internal const int WM_KEYDOWN = 0x0100;
        internal const int WM_KEYUP = 0x0101;
        internal const int WM_SYSKEYDOWN = 0x0104;
        internal const int WM_SYSKEYUP = 0x0105;
        internal const int WM_QUIT = 0x0012;

        [StructLayout(LayoutKind.Sequential)]
        internal struct KBDLLHOOKSTRUCT
        {
            internal uint vkCode;
            internal uint scanCode;
            internal uint flags;
            internal uint time;
            internal IntPtr dwExtraInfo;
        }

        internal delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        internal static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        internal static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PostThreadMessage(uint idThread, uint msg, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        internal static extern uint GetCurrentThreadId();

        [StructLayout(LayoutKind.Sequential)]
        internal struct MSG
        {
            internal IntPtr hwnd;
            internal uint message;
            internal IntPtr wParam;
            internal IntPtr lParam;
            internal uint time;
            internal int ptX;
            internal int ptY;
        }

        [DllImport("user32.dll", EntryPoint = "PeekMessageW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool PeekMessage(out MSG lpMsg, IntPtr hWnd, uint min, uint max, uint remove);

        [DllImport("user32.dll", EntryPoint = "TranslateMessage")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool TranslateMessage(ref MSG lpMsg);
    }

    internal sealed class Counter
    {
        private readonly object _gate = new object();
        private int _pending;
        private long _seq;
        private long _dropped;
        private bool _closing;

        internal void Add(int n)
        {
            lock (_gate)
            {
                if (_closing)
                {
                    return;
                }
                long next = (long)_pending + n;
                if (next > 1000)
                {
                    // 一个 250ms 窗口内超过 1000 次按下不可能是真人输入；截断并在 stderr 记账（不含键值）。
                    _dropped += next - 1000;
                    next = 1000;
                }
                _pending = (int)next;
            }
        }

        internal bool TryTake(out long seq, out int count)
        {
            lock (_gate)
            {
                if (_pending <= 0)
                {
                    seq = 0;
                    count = 0;
                    return false;
                }
                seq = ++_seq;
                count = _pending;
                _pending = 0;
                return true;
            }
        }

        internal long Dropped
        {
            get { lock (_gate) { return _dropped; } }
        }

        internal void Close()
        {
            lock (_gate)
            {
                _closing = true;
            }
        }
    }

    internal static class Program
    {
        private const int EmitIntervalMs = 250;
        private const int MaxLineBytes = 512;

        // 修饰键/锁存键：不计入"打字次数"。
        private static readonly HashSet<int> IgnoredKeys = new HashSet<int>
        {
            0x10, // VK_SHIFT
            0x11, // VK_CONTROL
            0x12, // VK_MENU (Alt)
            0x14, // VK_CAPITAL
            0x5B, // VK_LWIN
            0x5C, // VK_RWIN
            0x90, // VK_NUMLOCK
            0x91, // VK_SCROLL
            0xA0, 0xA1, // L/R SHIFT
            0xA2, 0xA3, // L/R CONTROL
            0xA4, 0xA5, // L/R MENU(Alt)
        };

        private static readonly object StdoutGate = new object();
        private static Counter _counter;
        private static NativeMethods.LowLevelKeyboardProc _hookProc; // 保持委托引用，防止被GC回收
        private static IntPtr _hookHandle = IntPtr.Zero;
        private static readonly HashSet<int> Pressed = new HashSet<int>(); // 仅进程内存，用于去重
        private static volatile bool _ignoreInjected;
        private static volatile bool _stopRequested;
        private static uint _threadId;
        private static bool _trace;

        private static bool _selfTest;
        private static string _outFile;
        private static StreamWriter _outWriter;

        private static int Main(string[] args)
        {
            if (!ParseArgs(args))
            {
                return 2;
            }

            _counter = new Counter();
            if (_selfTest)
            {
                return SelfTest();
            }
            if (!OpenOutput())
            {
                return 4;
            }
            _hookProc = HookCallback;
            _threadId = NativeMethods.GetCurrentThreadId();

            try
            {
                using (Process current = Process.GetCurrentProcess())
                {
                    _hookHandle = NativeMethods.SetWindowsHookEx(
                        NativeMethods.WH_KEYBOARD_LL,
                        _hookProc,
                        NativeMethods.GetModuleHandle(current.MainModule.ModuleName),
                        0);
                }
            }
            catch (Exception ex)
            {
                Error("安装键盘钩子失败：" + ex.GetType().Name);
                return 3;
            }

            if (_hookHandle == IntPtr.Zero)
            {
                Error("安装键盘钩子失败（系统拒绝，可能需要交互式桌面会话）。");
                return 3;
            }

            Error("ready pid=" + Process.GetCurrentProcess().Id
                + " ignore_injected=" + (_ignoreInjected ? "1" : "0"));

            var stdinThread = new Thread(ReadStdin) { IsBackground = true, Name = "stdin" };
            stdinThread.Start();

            var emitThread = new Thread(EmitLoop) { IsBackground = true, Name = "emit" };
            emitThread.Start();

            // 消息循环：低层键盘钩子需要在本线程泵消息。
            while (!_stopRequested)
            {
                if (!PeekAndDispatch())
                {
                    Thread.Sleep(5);
                }
            }

            // 退出前再取一次，尽量不丢最后一批。
            EmitOnce();

            if (_hookHandle != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(_hookHandle);
                _hookHandle = IntPtr.Zero;
            }
            _counter.Close();
            if (_outWriter != null)
            {
                try
                {
                    _outWriter.Flush();
                    _outWriter.Dispose();
                }
                catch (Exception)
                {
                }
                _outWriter = null;
            }
            if (_counter.Dropped > 0)
            {
                Error("dropped_over_cap=" + _counter.Dropped);
            }
            Error("bye");
            return 0;
        }

        private static bool OpenOutput()
        {
            if (string.IsNullOrEmpty(_outFile))
            {
                return true;
            }
            try
            {
                _outWriter = new StreamWriter(_outFile, false, new UTF8Encoding(false));
                _outWriter.AutoFlush = true;
                return true;
            }
            catch (Exception ex)
            {
                Error("无法打开 --out 文件：" + ex.GetType().Name);
                return false;
            }
        }

        private static bool ParseArgs(string[] args)
        {
            for (int i = 0; i < args.Length; i++)
            {
                string raw = args[i];
                string a = raw.Trim();
                if (a.Length == 0)
                {
                    continue;
                }
                if (a == "--ignore-injected")
                {
                    _ignoreInjected = true;
                }
                else if (a == "--out")
                {
                    if (i + 1 >= args.Length)
                    {
                        Console.Error.WriteLine("--out 需要一个文件路径");
                        return false;
                    }
                    _outFile = args[++i]; // 仅测试/验收用：内容与 stdout 完全相同，不外泄键值
                }
                else if (a == "--trace")
                {
                    _trace = true; // 只打印"收到一次有效按下"，不含键码
                }
                else if (a == "--self-test")
                {
                    _selfTest = true; // 用合成事件验证判定逻辑，不安装钩子、不读真实输入
                }
                else if (a == "-h" || a == "--help")
                {
                    Console.Error.WriteLine("用法: TypingCounter.exe [--ignore-injected] [--trace] [--self-test] [--out <file>]");
                    return false;
                }
                else
                {
                    Console.Error.WriteLine("未知参数，已拒绝启动。");
                    return false;
                }
            }
            return true;
        }

        private static bool PeekAndDispatch()
        {
            NativeMethods.MSG msg;
            bool any = false;
            while (NativeMethods.PeekMessage(out msg, IntPtr.Zero, 0, 0, 1 /*PM_REMOVE*/))
            {
                any = true;
                if (msg.message == NativeMethods.WM_QUIT)
                {
                    _stopRequested = true;
                    return true;
                }
                NativeMethods.TranslateMessage(ref msg);
                // 不调用 DispatchMessage：钩子由系统回调，不依赖窗口。
            }
            return any;
        }

        private static void HookCallbackBody(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode < 0)
            {
                return;
            }

            int message = wParam.ToInt32();
            if (message != NativeMethods.WM_KEYDOWN
                && message != NativeMethods.WM_SYSKEYDOWN
                && message != NativeMethods.WM_KEYUP
                && message != NativeMethods.WM_SYSKEYUP)
            {
                return;
            }

            var data = (NativeMethods.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(
                lParam, typeof(NativeMethods.KBDLLHOOKSTRUCT));
            int vk = (int)data.vkCode;
            bool injected = (data.flags & 0x10) != 0; // LLKHF_INJECTED

            HandleKey(message, vk, injected);
        }

        private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                HookCallbackBody(nCode, wParam, lParam);
            }
            return NativeMethods.CallNextHookEx(_hookHandle, nCode, wParam, lParam);
        }

        // 按键判定逻辑抽成独立方法，既给钩子用，也给 --self-test 用，避免两套实现漂移。
        internal static void HandleKey(int message, int vk, bool injected)
        {
            lock (Pressed)
            {
                if (message == NativeMethods.WM_KEYDOWN || message == NativeMethods.WM_SYSKEYDOWN)
                {
                    // 已在按下集合中 = 按键自动重复；只记一次。
                    if (Pressed.Add(vk))
                    {
                        if (!IgnoredKeys.Contains(vk) && !(_ignoreInjected && injected))
                        {
                            _counter.Add(1);
                            if (_trace)
                            {
                                Error("press");
                            }
                        }
                    }
                }
                else
                {
                    Pressed.Remove(vk);
                }
            }
        }

        private static int SelfTest()
        {
            _counter = new Counter();
            int failures = 0;

            // 1) 5 次普通按下
            Pressed.Clear();
            for (int i = 0; i < 5; i++)
            {
                HandleKey(NativeMethods.WM_KEYDOWN, 0x87, false);
                HandleKey(NativeMethods.WM_KEYUP, 0x87, false);
            }
            failures += Check("plain-5", TakeAll() == 5);

            // 2) 按住重复：12 次 KEYDOWN 无 KEYUP，只计 1（仅首个按下有效，随后重复被忽略）
            Pressed.Clear();
            for (int i = 0; i < 12; i++)
            {
                HandleKey(NativeMethods.WM_KEYDOWN, 0x86, false);
            }
            HandleKey(NativeMethods.WM_KEYUP, 0x86, false);
            failures += Check("repeat-1", TakeAll() == 1);

            // 3) 单独修饰键不计数
            Pressed.Clear();
            HandleKey(NativeMethods.WM_KEYDOWN, 0x10, false);
            HandleKey(NativeMethods.WM_KEYUP, 0x10, false);
            failures += Check("modifier-0", TakeAll() == 0);

            // 4) 多键交替仍各自计数
            Pressed.Clear();
            HandleKey(NativeMethods.WM_KEYDOWN, 0x85, false);
            HandleKey(NativeMethods.WM_KEYDOWN, 0x87, false);
            HandleKey(NativeMethods.WM_KEYUP, 0x85, false);
            HandleKey(NativeMethods.WM_KEYUP, 0x87, false);
            failures += Check("two-keys-2", TakeAll() == 2);

            // 5) 注入过滤：默认计入注入键（6 次=6），--ignore-injected 时必须为 0
            int injectedCount = TakeAllAfter(6);
            failures += Check("injected-filter", _ignoreInjected ? injectedCount == 0 : injectedCount == 6);

            if (failures == 0)
            {
                Out("selftest PASS");
                return 0;
            }
            Out("selftest FAIL count=" + failures);
            return 1;
        }

        private static int TakeAllAfter(int presses)
        {
            Pressed.Clear();
            for (int i = 0; i < presses; i++)
            {
                HandleKey(NativeMethods.WM_KEYDOWN, 0x84, true);
                HandleKey(NativeMethods.WM_KEYUP, 0x84, true);
            }
            return TakeAll();
        }

        private static int Check(string name, bool ok)
        {
            Out("selftest " + name + " " + (ok ? "ok" : "FAIL"));
            return ok ? 0 : 1;
        }

        private static int TakeAll()
        {
            int total = 0;
            long seq;
            int count;
            while (_counter.TryTake(out seq, out count))
            {
                total += count;
            }
            return total;
        }

        private static void EmitLoop()
        {
            while (!_stopRequested)
            {
                Thread.Sleep(EmitIntervalMs);
                EmitOnce();
            }
        }

        private static void EmitOnce()
        {
            long seq;
            int count;
            if (!_counter.TryTake(out seq, out count))
            {
                return;
            }
            string line = "{\"v\":1,\"seq\":" + seq.ToString() + ",\"count\":" + count.ToString() + "}";
            try
            {
                lock (StdoutGate)
                {
                    if (_outWriter != null)
                    {
                        _outWriter.WriteLine(line);
                        _outWriter.Flush();
                    }
                    else
                    {
                        byte[] bytes = Encoding.UTF8.GetBytes(line + "\n");
                        if (bytes.Length > MaxLineBytes)
                        {
                            Error("line_too_long");
                            return;
                        }
                        Stream stdout = Console.OpenStandardOutput();
                        stdout.Write(bytes, 0, bytes.Length);
                        stdout.Flush();
                    }
                }
            }
            catch (IOException)
            {
                // 父进程关闭了管道：安静退出。
                RequestStop();
            }
            catch (ObjectDisposedException)
            {
                RequestStop();
            }
        }

        private static readonly Regex ShutdownPattern = new Regex(
            "\"command\"\\s*:\\s*\"shutdown\"", RegexOptions.CultureInvariant);

        private static void ReadStdin()
        {
            try
            {
                string line;
                while ((line = Console.In.ReadLine()) != null)
                {
                    if (ShutdownPattern.IsMatch(line) || line.Trim() == "shutdown")
                    {
                        RequestStop();
                        return;
                    }
                    // 其他内容一律忽略：不接受运行期改变行为的指令。
                }
            }
            catch (IOException)
            {
                // 管道异常同样视为父进程消失。
            }
            catch (ObjectDisposedException)
            {
            }
            RequestStop();
        }

        private static void RequestStop()
        {
            if (_stopRequested)
            {
                return;
            }
            _stopRequested = true;
            if (_threadId != 0)
            {
                NativeMethods.PostThreadMessage(_threadId, NativeMethods.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
            }
        }

        private static void Out(string message)
        {
            try
            {
                Console.Out.WriteLine(message);
                Console.Out.Flush();
            }
            catch (IOException)
            {
            }
        }

        private static void Error(string message)
        {
            try
            {
                Console.Error.WriteLine("typing-counter: " + message);
                Console.Error.Flush();
            }
            catch (IOException)
            {
            }
        }
    }
}
