extends SceneTree
## 任务3 T3-04：三路线 × 两种收粮节奏的资源曲线。
## 运行：godot --headless --path apps/desktop --script res://tools/balance_lab/run_curves.gd
## 输出：experiments/task3/curves-<时间戳>.csv / .jsonl，并在 stdout 打印检查点汇总。

const Simulator = preload("res://tools/balance_lab/simulator.gd")

func _initialize() -> void:
	var simulator := Simulator.new()
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var out_dir := ProjectSettings.globalize_path("res://experiments/task3")
	var all_rows: Array = []
	var summary: Array = []
	for route in Simulator.ROUTES:
		for harvest_mode in Simulator.HARVEST_MODES:
			var result: Dictionary = simulator.run(route, harvest_mode, 120, "seed-default")
			all_rows.append_array(result.rows)
			var checkpoint: Dictionary = result.checkpoint
			summary.append({
				"route": route,
				"harvest": harvest_mode,
				"months_run": result.months_run,
				"ended": result.ended,
				"m6": checkpoint.get("m6", {}),
				"m12": checkpoint.get("m12", {}),
				"m24": checkpoint.get("m24", {}),
				"m36": checkpoint.get("m36", {}),
				"m120": checkpoint.get("m120", {}),
				"final": checkpoint.get("final", {}),
			})
			print("%s / %s: %d 月%s" % [route, harvest_mode, result.months_run, "（王国结束）" if result.ended else ""])
	var csv_path := out_dir + "/curves-" + stamp + ".csv"
	var jsonl_path := out_dir + "/curves-" + stamp + ".jsonl"
	var summary_path := out_dir + "/summary-" + stamp + ".json"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var written := simulator.write_csv(all_rows, csv_path)
	simulator.write_jsonl(all_rows, jsonl_path)
	var summary_file := FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file != null:
		summary_file.store_string(JSON.stringify({"fingerprint": simulator.fingerprint(), "generated": stamp, "runs": summary}, "  "))
		summary_file.close()
	print("fingerprint=" + simulator.fingerprint())
	print("csv=" + csv_path + " rows=" + str(written))
	print("summary=" + summary_path)
	for item in summary:
		print("%-14s %-10s m6=food%s/pop%s m12=food%s/pop%s m24=food%s/pop%s m120=food%s/pop%s" % [
			item.route, item.harvest,
			str(item.m6.get("food", "-")), str(item.m6.get("population", "-")),
			str(item.m12.get("food", "-")), str(item.m12.get("population", "-")),
			str(item.m24.get("food", "-")), str(item.m24.get("population", "-")),
			str(item.m120.get("food", "-")), str(item.m120.get("population", "-")),
		])
	quit(0 if written > 0 else 1)
