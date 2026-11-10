extends SceneTree
## 无图形环境的信号接线测试，不冒充真实鼠标、Windows 或渲染验收。
var failures: int = 0
var checks: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var packed = load("res://ui/main.tscn")
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.stats.text.contains("第1年1月"), "initial label")
	scene.next_button.pressed.emit()
	check(scene.game.snapshot().months == 1, "advance connected")
	check(scene.next_button.disabled and not scene.accept_button.disabled, "pending disables next")
	scene.accept_button.pressed.emit()
	check(scene.game.snapshot().population == 14 and not scene.next_button.disabled, "accept connected")
	scene.troops.value = 12
	check(not scene.dispatch_button.disabled, "dispatch validation enabled")
	scene.dispatch_button.pressed.emit()
	check(scene.game.snapshot().expedition.troops == 12, "dispatch connected")
	scene.next_button.pressed.emit()
	check(scene.game.snapshot().expedition.room == 1, "battle month connected")
	check(scene.details.text.contains("阵亡"), "battle visible as text")
	print("UI WIRING TESTS: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
