# 任务3 交付目录说明

## 字段语义（避免把"数据已定义"误读成"可玩"）

`data/content/catalog.json` 里的 `implemented` 指的是：**目录数据已定义、校验器可用、`content_rules.plan` 能给出计划**；
它**不代表**已经接入 Kingdom 核心。商栈与前哨营地当前是 `implemented: true` + `preview_only: true` + `wired_to_kingdom: false`：

| 字段 | 含义 |
|---|---|
| `implemented` | 数据与计划实现完成（可被 `plan()` 计算成本/效果） |
| `preview_only` | 只在本轮预览内容中提供 |
| `wired_to_kingdom` | 核心已实现对应命令（`construct_building` / `trade_resources`）。**当前为 false**，由任务2 接线后翻 true |

因此：中控不应把 `implemented: true` 当成"能玩"，能否执行以 `wired_to_kingdom` 与任务2 的接入为准。

## 行尾与指纹

`simulator.gd` 的源码指纹在计算前把 `\r\n` 归一成 `\n`，因此 LF 与 CRLF 检出得到同一指纹。
交付里给出的指纹均为归一后值；如果替换实现导致指纹变化，说明核心结算脚本确实改过。

## 可复现命令

见 `数据报告.md` 第一节；候选实验需要 `GODOT_BIN` 环境变量（`.sh` 与 `.ps1` 各一份）。
