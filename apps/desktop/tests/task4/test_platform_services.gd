extends SceneTree
## 任务4 平台层测试：偏好、启动诊断、输入桥校验、窗口几何。
## 这些是**纯逻辑/文件层**测试，不需要真实键盘、不需要窗口。
## 运行（4.6.3）：
##   godot --headless --path apps/desktop --script res://tests/task4/test_platform_services.gd
## 背景输入助手的协议测试在 tests/task4/test_typing_helper.py（Python，直接跑 exe）。

const SettingsStore = preload("res://platform/settings/settings_store.gd")
const StartupService = preload("res://platform/bootstrap/startup_service.gd")
const TypingBridge = preload("res://platform/typing/typing_bridge.gd")
const WindowMetrics = preload("res://platform/desktop/window_metrics.gd")

const PREF_PATH := "user://test-task4-preferences.json"

var checks: int = 0
var failures: int = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := PREF_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _initialize() -> void:
	_cleanup()
	_test_settings()
	_test_startup()
	_test_typing_bridge()
	_test_window_metrics()
	_cleanup()
	print("TASK4 PLATFORM TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _test_settings() -> void:
	var store = SettingsStore.new(PREF_PATH)

	var missing: Dictionary = store.load_preferences()
	check(missing.ok and missing.preferences.master_volume == 0.8, "settings: defaults when file missing")
	check(missing.preferences.has("font_scale") and not missing.preferences.has("auto_run"), "settings: no auto_run key")

	var saved: Dictionary = store.save_preferences({"master_volume": 0.35, "reduce_motion": true})
	check(saved.ok, "settings: save ok")
	var loaded: Dictionary = store.load_preferences()
	check(loaded.ok and absf(loaded.preferences.master_volume - 0.35) < 0.0001, "settings: roundtrip volume")
	check(loaded.preferences.reduce_motion == true, "settings: roundtrip bool")

	var clamped: Dictionary = store.save_preferences({"font_scale": 99.0, "music_volume": -3.0})
	check(clamped.ok, "settings: out-of-range save accepted but clamped")
	var reloaded: Dictionary = store.load_preferences()
	check(reloaded.preferences.font_scale == 1.6 and reloaded.preferences.music_volume == 0.0, "settings: clamped to range")

	var dropped: Dictionary = store.save_preferences({"typing_enabled": true, "evil_key": "x"})
	check(dropped.ok and dropped.has("message") and dropped.message.find("已忽略") >= 0, "settings: unknown/not-persisted dropped")
	var after_drop: Dictionary = store.load_preferences()
	check(not after_drop.preferences.has("typing_enabled"), "settings: typing_enabled never persisted")
	check(FileAccess.file_exists(PREF_PATH + ".bak"), "settings: previous file kept as .bak")

	# 版本不符：报错但不覆盖原文件
	var raw := FileAccess.open(PREF_PATH, FileAccess.WRITE)
	raw.store_string(JSON.stringify({"version": 99, "preferences": {"master_volume": 0.1}}))
	raw.close()
	var incompatible: Dictionary = store.load_preferences()
	check(not incompatible.ok and incompatible.preferences.master_volume == 0.8, "settings: version mismatch falls back to defaults")
	check(FileAccess.file_exists(PREF_PATH), "settings: bad version file not deleted")

	# 坏 JSON
	raw = FileAccess.open(PREF_PATH, FileAccess.WRITE)
	raw.store_string("{not json")
	raw.close()
	var broken: Dictionary = store.load_preferences()
	check(not broken.ok, "settings: corrupt json reported")

	var unknown_key: Dictionary = store.set_value("nope", 1)
	check(not unknown_key.ok, "settings: set_value rejects unknown key")
	_cleanup()

func _test_startup() -> void:
	var service = StartupService.new()
	var isolated: Array = [
		{"path": "user://test-task4-absent-v5.json", "version": 5},
		{"path": "user://test-task4-absent-v4.json", "version": 4},
	]
	var missing: Dictionary = service.inspect_saves(isolated)
	check(missing.primary.status == StartupService.STATUS_MISSING, "startup: missing save status")
	check(missing.can_start_new and not missing.can_continue, "startup: can start new, cannot continue")

	var fake := "user://test-task4-save.json"
	# 损坏
	var f := FileAccess.open(fake, FileAccess.WRITE)
	f.store_string("{oops")
	f.close()
	check(service.inspect_file(fake, 5).status == StartupService.STATUS_CORRUPT, "startup: corrupt json")
	# 空文件
	f = FileAccess.open(fake, FileAccess.WRITE)
	f.store_string("")
	f.close()
	check(service.inspect_file(fake, 5).status == StartupService.STATUS_CORRUPT, "startup: empty file")
	# 版本不符
	f = FileAccess.open(fake, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 4, "state": {}}))
	f.close()
	check(service.inspect_file(fake, 5).status == StartupService.STATUS_INCOMPATIBLE, "startup: version mismatch")
	# 缺 state
	f = FileAccess.open(fake, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 5}))
	f.close()
	check(service.inspect_file(fake, 5).status == StartupService.STATUS_CORRUPT, "startup: missing state")
	# 正常
	f = FileAccess.open(fake, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 5, "state": {"food": 10}}))
	f.close()
	var ok_result: Dictionary = service.inspect_file(fake, 5)
	check(ok_result.status == StartupService.STATUS_READABLE and ok_result.bytes > 0, "startup: readable candidate")
	check(ok_result.message.find("完整校验") >= 0, "startup: readable is not claimed as validated")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fake))

	var resources: Dictionary = service.check_resources()
	check(resources.ok, "startup: required resources present")
	var env: Dictionary = service.environment_summary()
	check(env.has("engine") and env.has("os"), "startup: environment summary")

func _test_typing_bridge() -> void:
	var bridge = TypingBridge.new()
	check(bridge.status().enabled == false, "bridge: disabled by default")
	check(bridge.drain_count() == 0, "bridge: drain empty is 0")
	bridge.stop()
	bridge.stop()
	check(bridge.status().enabled == false, "bridge: stop idempotent")

	bridge._ingest_line('{"v":1,"seq":1,"count":7}')
	check(bridge.drain_count() == 7, "bridge: count ingested")
	check(bridge.drain_count() == 0, "bridge: single batch consumed once")

	bridge._ingest_line('{"v":1,"seq":1,"count":7}')
	check(bridge.drain_count() == 0, "bridge: duplicate seq rejected")
	bridge._ingest_line('{"v":1,"seq":2,"count":0}')
	check(bridge.drain_count() == 0, "bridge: zero count frame is legal but adds nothing")
	bridge._ingest_line('{"v":1,"seq":3,"count":1001}')
	check(bridge.drain_count() == 0, "bridge: count over cap rejected")
	bridge._ingest_line('{"v":2,"seq":4,"count":5}')
	check(bridge.drain_count() == 0, "bridge: bad version rejected")
	bridge._ingest_line('{"v":1,"seq":5,"count":"5"}')
	check(bridge.drain_count() == 0, "bridge: string count rejected")
	bridge._ingest_line('hello')
	check(bridge.drain_count() == 0, "bridge: non-json rejected")
	bridge._ingest_line('{"v":1,"seq":6,"count":3,"key":"x"}')
	check(bridge.drain_count() == 3, "bridge: extra fields ignored, count kept")

	var missing: Dictionary = bridge.start("res://__no_such_helper__.exe")
	check(not missing.ok and bridge.status().last_error == "helper-missing", "bridge: missing helper reports error")
	check(bridge.status().helper_running == false, "bridge: no process on failure")
	bridge.free()

func _test_window_metrics() -> void:
	var usable := Rect2i(0, 0, 1920, 1040)  # 1080 屏减去 40px 任务栏
	var recommended: Rect2i = WindowMetrics.recommended_rect(usable, Vector2i(1280, 800))
	check(WindowMetrics.is_inside(recommended, usable), "window: recommended inside usable")
	check(recommended.size == Vector2i(1280, 800), "window: recommended keeps preferred size")

	var too_small := Rect2i(-500, -300, 100, 80)
	var clamped: Rect2i = WindowMetrics.clamp_to_usable(too_small, usable)
	check(WindowMetrics.is_inside(clamped, usable), "window: clamped inside usable")
	check(clamped.size.x >= WindowMetrics.MIN_WIDTH, "window: clamped respects min width")

	var oversized := Rect2i(0, 0, 4000, 3000)
	var shrunk: Rect2i = WindowMetrics.clamp_to_usable(oversized, usable)
	check(shrunk.size == usable.size, "window: oversized shrinks to usable")

	var dock: Rect2i = WindowMetrics.bottom_dock_rect(usable, 260)
	check(WindowMetrics.is_inside(dock, usable), "window: dock inside usable")
	check(dock.position.y + dock.size.y == usable.position.y + usable.size.y, "window: dock sits on bottom")

	var tiny := Rect2i(0, 0, 100, 50)
	var tiny_dock: Rect2i = WindowMetrics.bottom_dock_rect(tiny, 260)
	check(WindowMetrics.is_inside(tiny_dock, tiny), "window: dock fits tiny screen")

	var scaled: Rect2i = WindowMetrics.scale_rect(Rect2i(10, 10, 100, 50), 1.5)
	check(scaled == Rect2i(15, 15, 150, 75), "window: dpi scale")
	check(WindowMetrics.scale_rect(Rect2i(0, 0, 10, 10), 0.0) == Rect2i(0, 0, 10, 10), "window: scale guard")
