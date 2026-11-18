extends SceneTree
## 任务3 T3-03：模拟器可重放性测试。
## 运行：godot --headless --path apps/desktop --script res://tests/task3/test_simulator_replay.gd

const Simulator = preload("res://tools/balance_lab/simulator.gd")

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var simulator := Simulator.new()
	var fingerprint := simulator.fingerprint()
	check(fingerprint.length() == 64, "源码指纹是 64 位 SHA-256")
	check(fingerprint == Simulator.new().fingerprint(), "同一份源码的指纹稳定")

	var first: Dictionary = simulator.run("steady_farm", "monthly", 24, "seed-replay")
	check(first.months_run == 24, "跑满 24 个月")
	check(first.rows.size() == 24, "每月一行记录")
	check(String(first.rows[0].fingerprint).length() == 16, "行内带 16 位指纹前缀")

	# 同参数重跑必须逐行一致（纯函数式确定性）
	var second: Dictionary = simulator.run("steady_farm", "monthly", 24, "seed-replay")
	var diffs := 0
	for index in first.rows.size():
		if first.rows[index] != second.rows[index]:
			diffs += 1
	check(diffs == 0, "重跑逐行一致（%d 行差异）" % diffs)

	# 回放对比接口：用第 12 月记录重放，应无差异
	var expected: Dictionary = first.rows[11]
	check(int(expected.month) == 12, "取到第 12 月记录")
	var mismatch := simulator.replay_matches("steady_farm", "monthly", 12, expected)
	check(mismatch.is_empty(), "回放与记录一致: %s" % str(mismatch))

	# 输出接口：写到 user:// 目录（运行模式 res:// 只读）
	var dir := ProjectSettings.globalize_path("user://task3_test/")
	DirAccess.make_dir_recursive_absolute(dir)
	var csv_rows := simulator.write_csv(first.rows, dir + "replay.csv")
	check(csv_rows == 24, "CSV 写入 24 行（实际 %d）" % csv_rows)
	check(FileAccess.file_exists(dir + "replay.csv"), "CSV 文件存在")
	var jsonl_rows := simulator.write_jsonl(first.rows, dir + "replay.jsonl")
	check(jsonl_rows == 24, "JSONL 写入 24 行（实际 %d）" % jsonl_rows)

	# 不注资：初始资源与 Balance.INITIAL 一致，模拟不额外加钱
	var game = simulator.new_game()
	check(game.snapshot().food == 30 and game.snapshot().wood == 20, "新局初始资源与核心一致")

	print("T3-03 simulator replay: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
