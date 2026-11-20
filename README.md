# 桌面王国 · 2.1 开发分支

[下载农田修正版 2.0.1](releases/playtest-2.0.1/KingdomDesktop-2.0.1-Windows-x64.zip) · [2.1 四机周任务](apps/desktop/docs/试玩版2.1四机任务.md)


[下载 Windows x64 试玩包](releases/playtest-2.0/KingdomDesktop-2.0-Windows-x64.zip) · [本版说明与四机计划](releases/playtest-2.0/交付与下周计划.md)

源码使用 Godot 4.6.3 标准版。以下保留早期版本的开发记录。

# game

一个**小游戏**项目（技术栈待定，后续补充）。

## 仓库地址

https://github.com/HDDD1123/game

## 同步方式

- **上传（push）**：在项目目录打开 PowerShell，运行

  ```powershell
  .\一键同步到GitHub.ps1
  ```

- **下载最新（pull）**：

  ```powershell
  git pull
  ```

## 项目说明

（待补充：玩法、技术栈、运行方式）

## Godot 桌面原型 v0.3（本分支）

本分支提供可供 DSH 接手的桌面开发工程，使用 Godot 4.6.3 标准版。

- [工程与运行说明](apps/desktop/README.md)
- [任务004：Windows桌面底座](apps/desktop/docs/任务004_Windows桌面底座.md)
- [任务004 PDF](apps/desktop/docs/task004-desktop.pdf)
- [验证结果与未测项](apps/desktop/VERIFICATION.md)

源码已在 `apps/desktop/`，不需要从聊天下载源码包。导入其中的 `project.godot` 后按 F5 运行。当前交付是开发工程，Windows 可执行文件由 DSH 按任务004导出。

已有本地开发进度的成员，先阅读任务单中的独立工作目录步骤，保留当前分支及未提交文件。
