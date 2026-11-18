# balance_lab 使用说明（任务3）

## 组成

| 文件 | 作用 |
|---|---|
| `simulator.gd` | 只用 `Kingdom.act()/snapshot()/view()` 驱动游戏的模拟器；带源码指纹、CSV/JSONL 输出、回放对比 |
| `run_curves.gd` | 三路线（稳健农业 / 城镇扩张 / 冒险采矿）× 两种收粮节奏（每月 / 每三月），推进 120 月，输出曲线 |
| `download-godot.sh` | 本机没有 Godot 时用的分段下载脚本（GitHub API 资产重定向 + 8 路 Range） |

## 运行（仓库根目录）

```bash
# 需要 Godot 4.6.3 标准版；本机路径 D:\tools\godot\Godot_v4.6.3-stable_win64.exe
GODOT="D:/tools/godot/Godot_v4.6.3-stable_win64.exe"

# 内容目录校验测试
"$GODOT" --headless --path apps/desktop --script res://tests/task3/test_content_catalog.gd

# 资源曲线（输出到 apps/desktop/experiments/task3/）
"$GODOT" --headless --path apps/desktop --script res://tools/balance_lab/run_curves.gd
```

## 约束

- 模拟器不得访问 `_state`、不复制结算公式、不注资；所有状态变化都通过 `act()`。
- 每份输出都带 `fingerprint`（`core/kingdom.gd` 等四个文件的 SHA-256 前 16 位），用于判断曲线来自哪版源码。
- 候选数值只在 `experiments/task3/` 的临时工程里改，生产 `balance.gd` 不动。
