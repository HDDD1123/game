extends SceneTree
## 以真实主场景从新局走到续玩；可在空目录针对导出 PCK 复跑。
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var scene = load("res://ui/main.tscn").instantiate()
	var prefix := "user://playtest-%d" % Time.get_ticks_usec()
	scene.window_config_path = prefix + "-window.json"
	scene.saves.primary_path = prefix + "-save.json"
	root.add_child(scene)
	await process_frame
	await process_frame
	check(scene.slot_buttons.size() == 7 and scene.slot_buttons[1].icon != null, "街景数据与贴图")
	scene._open_overlay("手记", scene._fill_history)
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(scene.overlay_panel.get_global_rect()), "街景浮层没有裁切")
	check(scene.overlay_content.get_child(0).text.contains("落笔之前"), "向导读取包内数据")
	scene._close_panels()
	check(not scene.overlay_panel.visible and not scene.panel_restore_rect.has_area(), "关闭浮层恢复街景")
	scene.street_next_button.pressed.emit()
	check(scene.street_events.visible and scene.street_next_button.disabled, "流民事件暂停")
	scene.slot_buttons[1].pressed.emit()
	scene.street_reject_button.pressed.emit()
	check(scene.game.view().farm.ready_food == 0 and scene.game.snapshot().pending.is_empty(), "收粮与处理流民")
	scene._toggle_street()
	scene.auto_button.pressed.emit()
	await create_timer(0.4).timeout
	check(scene.game.view().clock.month_elapsed_ms > 0 and scene.next_button.disabled, "主场景驱动时间")
	scene.auto_button.pressed.emit()
	var saved: Dictionary = scene.game.snapshot()
	check(scene.saves.save_game(scene.game).ok, "写入格式5")
	scene.next_button.pressed.emit()
	check(scene.game.snapshot().months > saved.months, "暂停自动时间后可跳月")
	check(scene.saves.load_game(scene.game).ok and scene.game.snapshot() == saved, "恢复月内进度和资源")
	scene._open_overlay("人才", scene._fill_talents)
	await process_frame
	check(scene.overlay_content.get_child_count() >= 7, "包内人才目录可读")
	var file := FileAccess.open(scene.saves.primary_path, FileAccess.WRITE)
	file.store_string('{"version":[],"state":{}}')
	file.close()
	check(not scene.saves.load_game(scene.game).ok and scene.game.snapshot() == saved, "拒绝无效版本并保留当前局")
	for path in [scene.window_config_path, scene.saves.primary_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	print("PLAYTEST 2.0: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
