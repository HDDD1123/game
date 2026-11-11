extends SceneTree
## 窗口功能回归。几何/信号检查不等同于 Windows DPI、多屏或真实鼠标验收。
var failures := 0
var checks := 0
var config_path := "user://verify-window-" + str(Time.get_ticks_usec()) + ".json"

class FailedSave:
	extends RefCounted
	func save_game(_game) -> Dictionary:
		return {"ok": false, "message": "测试：无法写入存档"}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://ui/main.tscn").instantiate()
	scene.window_config_path = config_path
	root.add_child(scene)
	await process_frame
	await process_frame
	check(scene.street_mode and root.size.y == scene.STREET_HEIGHT, "default street mode")
	check(not root.always_on_top, "pin off by default")
	check(scene.close_dialog.get_ok_button().text == "保存并退出", "close has save and exit")
	check(scene.close_dialog.get_cancel_button().text == "取消", "close has cancel")
	scene._toggle_street()
	await process_frame
	root.size = Vector2i(1100, 660)
	await process_frame
	var normal_size := root.size
	scene._toggle_street()
	await process_frame
	check(scene.street_mode and root.size.y == scene.STREET_HEIGHT, "return to bottom street")
	scene._open_skills()
	await process_frame
	scene._save_window_config()
	var cfg: Dictionary = scene._load_window_config()
	check(cfg.size[1] == scene.STREET_HEIGHT, "open research does not persist enlarged street height")
	check(scene._to_vec2i(cfg.normal_size) == normal_size, "normal dimensions persisted")
	scene._close_panels()
	await process_frame
	scene._toggle_street()
	await process_frame
	check(root.size == normal_size, "normal dimensions restored across mode changes")
	scene._on_pin_toggled(true)
	if DisplayServer.get_name() != "headless":
		check(root.always_on_top and scene._load_window_config().always_on_top, "pin saved")
	else:
		print("SKIP: native pin flag requires graphical display")
	scene._on_pin_toggled(false)
	check(not root.always_on_top, "pin disabled")
	scene._toggle_street()
	await process_frame
	scene.saves = FailedSave.new()
	scene._on_close_save()
	check(scene.is_inside_tree() and scene.street_notice.is_visible_in_tree(), "failed save keeps window and feedback visible")
	check(scene.street_notice.text.contains("保存失败") and scene.street_notice.text.contains("窗口保持打开"), "failed save reports cause")

	var usable := Rect2i(-1920, 0, 1920, 1040)
	check(usable.encloses(scene.fit_window_rect(Rect2i(5000, 3000, 4000, 3000), usable)), "oversized/offscreen window fits negative-origin display")
	var on_screen := Rect2i(-1600, 100, 1000, 600)
	check(scene.fit_window_rect(on_screen, usable) == on_screen, "valid location remains unchanged")
	check(scene._to_vec2i([{}, []]) == Vector2i.ZERO, "malformed position safely ignored")
	check(scene._to_vec2i([1.5, 2]) == Vector2i.ZERO, "fractional position safely ignored")
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"street_mode": true, "size": [5000, 4000], "position": [9999, 9999], "always_on_top": false}))
	file.close()
	scene._apply_window_config()
	await process_frame
	check(scene._usable_rect().encloses(Rect2i(root.position, root.size)), "loading stale screen dimensions clamps size and position")
	file = FileAccess.open(config_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"street_mode": true, "size": [{}, []], "position": [{}, []], "normal_size": [null, null]}))
	file.close()
	scene._apply_window_config()
	check(scene.is_inside_tree(), "corrupt window config does not crash")
	print("VERIFY WINDOW: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(config_path)
	quit(1 if failures else 0)
