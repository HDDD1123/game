extends SceneTree
## 任务4 T4-09 向导模型测试（纯逻辑，不需要窗口）。
## 运行（4.6.3）：
##   godot --headless --path apps/desktop --script res://tests/task4/test_onboarding_model.gd

const Onboarding = preload("res://ui/onboarding/onboarding_model.gd")

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var model = Onboarding.new()
	check(model.warnings().is_empty(), "向导数据读取无警告")
	check(model.all_steps().size() == 8, "8 个向导步骤")

	var first: Dictionary = model.next_step([], {})
	check(first.step.get("id", "") == "step_welcome", "开局先讲欢迎（always 触发）")

	# 看过欢迎后，没有任何事实/计数 → 没有下一步可讲，不硬塞
	model.mark_seen("step_welcome")
	check(model.next_step([], {}).step.is_empty(), "无状态时不再展示条件步骤")

	# 收成事实触发农田说明
	var facts: Array = [{"type": "harvest_summary", "fact_id": "f1", "game_month": 1}]
	var harvest: Dictionary = model.next_step(facts, {})
	check(harvest.step.get("id", "") == "step_harvest", "收成后讲农田")

	# 跳过农田只影响这一步：人口计数满足后应讲人口
	model.mark_seen("step_harvest")
	var population: Dictionary = model.next_step(facts, {"population": 12})
	check(population.step.get("id", "") == "step_population", "人口达标后讲住房")

	# 计数缺失视为不满足（不猜值）
	check(model.next_step(facts, {}).step.is_empty(), "缺少计数时条件不成立")

	# 计数类型不对也不满足
	check(model.next_step(facts, {"population": "十二"}).step.is_empty(), "非数值计数不满足")

	# 重看：清空已看记录，重新从欢迎开始
	model.reset()
	check(model.next_step([], {}).step.get("id", "") == "step_welcome", "重看从第一步开始")

	# 未知触发类型：不满足并记警告
	check(not model._trigger_met({"kind": "magic"}, [], {}), "未知触发类型不满足")
	check(not model.warnings().is_empty(), "未知触发类型留下警告")

	# 步骤顺序稳定：重复调用结果一致
	var a: Dictionary = model.next_step(facts, {"population": 12})
	var b: Dictionary = model.next_step(facts, {"population": 12})
	check(a.step.get("id", "") == b.step.get("id", ""), "同输入同结果")

	print("TASK4 ONBOARDING TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
